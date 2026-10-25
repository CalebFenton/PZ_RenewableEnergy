-- Every hands-on job at a digester, gas heater, gasifier or a generator's Gas Conversion Kit
-- (RenewableEnergy.JobAction); the authority's complete() does the job. A global, as the server
-- finds the class by its Type (NetTimedAction.parse).

require "Util/BuildingHelper"
require "RenewableEnergy/Utilities"
require "RenewableEnergy/TimedActions/JobAction"
require "RenewableEnergy/GasJobs"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/Biogas/DigesterJobs"
require "RenewableEnergy/Biogas/GasHeater"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/GasLine/GasKit"

RenewableEnergyGasAction = RenewableEnergy.JobAction:derive("RenewableEnergyGasAction")

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
        isTarget = RenewableEnergy.isGenerator,
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
Action.REACH = 2.6

-- A job's row (its JOBS entry) says how the job looks (JobAction.row), and `shovel`, dug with the
-- shovel in hand; a job that digs reaches in as "Loot" without one.
local function rowOf(feature, job)
    return FEATURES[feature].jobs.JOBS[job]
end

-- Whether `with` is an inventory item the character works with, rather than a world object.
local function isItem(with)
    return with ~= nil and instanceof(with, "InventoryItem")
end

function Action:row()
    return rowOf(self.feature, self.job)
end

function Action:units()
    local minutes = self:row().minutes
    if type(minutes) == "function" then
        minutes = minutes(self.object, self.with)
    end
    return minutes * RenewableEnergy.unitsPerMinute()
end

function Action:target()
    return self.object
end

function Action:keeps()
    if not (RenewableEnergy.onSquare(self.object) and FEATURES[self.feature].isTarget(self.object)) then
        return false
    end
    return not isItem(self.with) or self.character:getInventory():containsRecursive(self.with)
end

function Action:canPerform()
    return not FEATURES[self.feature].jobs.refusal(self.character, self.job, self.object, self.with)
end

function Action:findItems()
    if isItem(self.with) then
        self.with = self.character:getInventory():getItemWithIDRecursiv(self.with:getID())
    end
end

function Action:startJob()
    local shovel = self:row().shovel and self.character:getPrimaryHandItem()
    if shovel then
        self:setActionAnim(BuildingHelper.getShovelAnim(shovel))
        return
    end
    RenewableEnergy.JobAction.startJob(self)
end

-- The job's own rules are rechecked by GasJobs.perform, after it catches the target up.
function Action:complete()
    if not (RenewableEnergy.onSquare(self.object) and self:atJobForAuthority()) then
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
    o.maxTime = o:getDuration()
    return o
end

--- Walks `playerNum`'s character over to `object` and queues `job` there, with the shovel in
--- hand for a job that digs, as vanilla's Clear Ashes takes it. Client only.
function Action.queue(playerNum, feature, job, object, with)
    local character = RenewableEnergy.walkTo(playerNum, object:getSquare())
    if not character then
        return
    end
    if rowOf(feature, job).shovel then
        ISWorldObjectContextMenu.equip(character, character:getPrimaryHandItem(), function(tool)
            return tool:hasTag(ItemTag.TAKE_DIRT) and RenewableEnergy.notBroken(tool)
        end, true)
    end
    ISTimedActionQueue.add(Action:new(character, feature, job, object, with))
end
