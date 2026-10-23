require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/GasJobs"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/GasLine/GasKit"

-- Every hands-on job at a digester, gas heater, gasifier or a generator's Gas Conversion Kit. In
-- multiplayer the client runs start() and perform() and the server rebuilds the action from new()'s
-- parameters and runs complete(), which does the job; single player runs both. A global, as the
-- server finds the class by its Type (NetTimedAction.parse).
RenewableEnergyGasAction = ISBaseTimedAction:derive("RenewableEnergyGasAction")

local Action = RenewableEnergyGasAction

-- Each feature: isTarget(object), the tiles it works at; jobs, its job module
-- (RenewableEnergy.GasJobs), which has JOBS[job] (minutes and how the job looks) and
-- refusal(character, job, object, with); and site(), its side of the jobs on the authority
-- (GasJobs.perform), looked up when a job completes, since server files load after shared ones.
local FEATURES = {
    digester = {
        isTarget = RenewableEnergy.Digester.isDigester,
        jobs = RenewableEnergy.DigesterJobs,
        site = function() return RenewableEnergy.DigesterSystem.jobSite end,
    },
    heater = {
        isTarget = RenewableEnergy.GasHeater.isHeater,
        jobs = RenewableEnergy.GasHeater,
        site = function() return RenewableEnergy.DigesterSystem.heaterSite end,
    },
    gasifier = {
        isTarget = RenewableEnergy.Gasifier.isGasifier,
        jobs = RenewableEnergy.GasifierJobs,
        site = function() return RenewableEnergy.GasifierSystem.jobSite end,
    },
    kit = {
        isTarget = RenewableEnergy.GasKit.isGenerator,
        jobs = RenewableEnergy.GasKit,
        site = function() return RenewableEnergy.GasLines.jobSite end,
    },
}

--- The job module of `feature`, a key of FEATURES.
function Action.jobsOf(feature)
    return FEATURES[feature].jobs
end

-- How far from the middle of the object's square, on each axis in squares, the character may work
-- at it: what luautils.walkAdj counts as there, and a little for drift and a client's lag.
local REACH = 2.6

-- A job's row (its JOBS entry) says how the job looks: `anim`, else the "Loot" reach; LootPosition
-- `position`; `shovel`, dug with the shovel in hand; `heavy`, heavy work; `sound` while it runs and
-- `doneSound` once done.
local function rowOf(feature, job)
    return FEATURES[feature].jobs.JOBS[job]
end

-- Whether `with` is an inventory item the character works with, rather than a world object.
local function isItem(with)
    return with ~= nil and instanceof(with, "InventoryItem")
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local minutes = rowOf(self.feature, self.job).minutes
    if type(minutes) == "function" then
        minutes = minutes(self.object, self.with)
    end
    return minutes * RenewableEnergy.unitsPerMinute()
end

function Action:isValid()
    -- Past here the item may already be gone: complete() can sync the item it used before the
    -- server's word that the action is done arrives.
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    if not (RenewableEnergy.onSquare(self.object) and FEATURES[self.feature].isTarget(self.object)) then
        return false
    end
    if isItem(self.with) and not self.character:getInventory():containsRecursive(self.with) then
        return false
    end
    -- The server can't tell whether a remote player stands in the dark
    -- (IsoPlayer.tooDarkToRead), so the player's own side checks the light.
    if FEATURES[self.feature].jobs.needsLight(self.job) and self.character:tooDarkToRead() then
        HaloTextHelper.addBadText(self.character, getText("Tooltip_RenewableEnergy_TooDark"))
        return false
    end
    return RenewableEnergy.withinReach(self.character, self.object, REACH)
end

function Action:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.object)
    if rowOf(self.feature, self.job).heavy then
        self.character:setMetabolicTarget(Metabolics.HeavyWork)
    end
end

function Action:start()
    if not isClient() and FEATURES[self.feature].jobs.refusal(self.character, self.job, self.object, self.with) then
        self:forceStop()
        return
    end
    if isClient() and isItem(self.with) then
        self.with = self.character:getInventory():getItemWithIDRecursiv(self.with:getID())
    end
    local row = rowOf(self.feature, self.job)
    local shovel = row.shovel and self.character:getPrimaryHandItem()
    if shovel then
        self:setActionAnim(BuildingHelper.getShovelAnim(shovel))
    elseif row.anim then
        self:setActionAnim(row.anim)
        if row.position then
            self.character:SetVariable("LootPosition", row.position)
        end
    else
        -- Reaching into the object, down low unless the job says otherwise; a job that digs loots
        -- so without a shovel in hand.
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", row.position or "Low")
    end
    if row.sound then
        self.sound = self.character:playSound(row.sound)
    end
end

function Action:stopSound()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function Action:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function Action:perform()
    self:stopSound()
    local doneSound = rowOf(self.feature, self.job).doneSound
    if doneSound then
        self.character:playSound(doneSound)
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so the performer checks the job again; this checks that the
-- character is at the object, which NetTimedAction doesn't.
function Action:complete()
    if not RenewableEnergy.onSquare(self.object) or (isServer() and not RenewableEnergy.withinReach(self.character, self.object, REACH)) then
        return false
    end
    local feature = FEATURES[self.feature]
    return RenewableEnergy.GasJobs.perform(feature.jobs, feature.site(), self.character, self.job, self.object, self.with)
end

-- Parameter names match the fields: the multiplayer server rebuilds the action by passing them to
-- new() in order (NetTimedAction). `feature` is a key of FEATURES and `job` one of its jobs;
-- `object` the tile worked at; `with` what the job works with, if anything: the inventory item it
-- fills or uses (a bag, a tank, a drain container), or a second world object (Connect Gas Line's
-- source). Returns nil for a feature or job there is none of: those come from the client, every
-- later step looks them up, and the server turns down a request whose new() gives no action
-- (NetTimedActionPacket.processServer).
function Action:new(character, feature, job, object, with)
    if not (FEATURES[feature] and rowOf(feature, job)) then
        return nil
    end
    local o = ISBaseTimedAction.new(self, character)
    o.feature = feature
    o.job = job
    o.object = object
    o.with = with
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

--- Walks `playerNum`'s character over to `object` and queues `job` there, with the shovel in
--- hand for a job that digs, as vanilla's Clear Ashes takes it. Client only.
function Action.queue(playerNum, feature, job, object, with)
    local character = getSpecificPlayer(playerNum)
    if not luautils.walkAdj(character, object:getSquare(), true) then
        return
    end
    if rowOf(feature, job).shovel then
        ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), function(tool)
            return tool:hasTag(ItemTag.TAKE_DIRT) and RenewableEnergy.notBroken(tool)
        end, true)
    end
    ISTimedActionQueue.add(Action:new(character, feature, job, object, with))
end
