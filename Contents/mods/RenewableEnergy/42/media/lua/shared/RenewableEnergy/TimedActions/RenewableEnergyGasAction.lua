require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/GasLine/GasKit"

-- Every hands-on job at a digester, gas heater, gasifier or a generator's Gas Conversion Kit. In
-- multiplayer the client runs start() and perform() and the server rebuilds the action from new()'s
-- parameters and runs complete(), which does the job; single player runs both. A global, as the
-- server finds the class by its Type (NetTimedAction.parse).
RenewableEnergyGasAction = ISBaseTimedAction:derive("RenewableEnergyGasAction")

local Action = RenewableEnergyGasAction

-- Each feature's job rules. Every one has isTarget(object), minutesFor(job, object, item, other),
-- refusal(character, job, object, item, other) and LOOK[job].
local JOBS = {
    digester = RenewableEnergy.DigesterJobs,
    heater = RenewableEnergy.GasHeater,
    gasifier = RenewableEnergy.GasifierJobs,
    kit = RenewableEnergy.GasKit,
}
-- Who does each feature's jobs on the authority, by RenewableEnergy field: perform(character, job,
-- object, item, other). Looked up when a job completes, since server files load after shared ones.
local PERFORMERS = { digester = "DigesterSystem", heater = "DigesterSystem", gasifier = "GasifierSystem", kit = "GasLines" }

-- How a job looks unless its LOOK says otherwise: reaching down into the object.
local LOOT_LOW = { anim = "Loot", position = "Low" }

-- How far from the middle of the object's square, on each axis in squares, the character may work
-- at it: what luautils.walkAdj counts as there, and a little for drift and a client's lag.
local REACH = 2.6

function Action:look()
    return JOBS[self.feature].LOOK[self.job] or LOOT_LOW
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local minutes = JOBS[self.feature].minutesFor(self.job, self.object, self.item, self.other)
    return minutes * RenewableEnergy.unitsPerMinute()
end

function Action:isValid()
    -- Past here the item may already be gone: complete() can sync the item it used before the
    -- server's word that the action is done arrives.
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    if not (RenewableEnergy.onSquare(self.object) and JOBS[self.feature].isTarget(self.object)) then
        return false
    end
    if self.item and not self.character:getInventory():containsRecursive(self.item) then
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
    if self:look().heavy then
        self.character:setMetabolicTarget(Metabolics.HeavyWork)
    end
end

function Action:start()
    if not isClient() and JOBS[self.feature].refusal(self.character, self.job, self.object, self.item, self.other) then
        self:forceStop()
        return
    end
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemWithIDRecursiv(self.item:getID())
    end
    local look = self:look()
    local shovel = look.shovel and self.character:getPrimaryHandItem()
    if shovel then
        self:setActionAnim(BuildingHelper.getShovelAnim(shovel))
    else
        -- A look that names no anim (one that only sounds, or digs without a shovel in hand) loots low.
        local loot = look.anim and look or LOOT_LOW
        self:setActionAnim(loot.anim)
        if loot.position then
            self.character:SetVariable("LootPosition", loot.position)
        end
    end
    if look.sound then
        self.sound = self.character:playSound(look.sound)
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
    local doneSound = self:look().doneSound
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
    return RenewableEnergy[PERFORMERS[self.feature]].perform(self.character, self.job, self.object, self.item, self.other)
end

-- Parameter names match the fields: the multiplayer server rebuilds the action by passing them to
-- new() in order (NetTimedAction). `feature` is a key of JOBS and `job` one of its jobs; `object`
-- the tile worked at; `item` the inventory item the job fills or uses (a bag, a tank, a drain
-- container), else nil; `other` a second world object (Connect Gas Line's source), else nil.
function Action:new(character, feature, job, object, item, other)
    local o = ISBaseTimedAction.new(self, character)
    o.feature = feature
    o.job = job
    o.object = object
    o.item = item
    o.other = other
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

--- Walks `playerNum`'s character over to `object` and queues `job` there, with the shovel in
--- hand for a job that digs, as vanilla's Clear Ashes takes it. Client only.
function Action.queue(playerNum, feature, job, object, item, other)
    local character = getSpecificPlayer(playerNum)
    if not luautils.walkAdj(character, object:getSquare(), true) then
        return
    end
    if (JOBS[feature].LOOK[job] or LOOT_LOW).shovel then
        ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), function(tool)
            return tool:hasTag(ItemTag.TAKE_DIRT) and RenewableEnergy.notBroken(tool)
        end, true)
    end
    ISTimedActionQueue.add(Action:new(character, feature, job, object, item, other))
end
