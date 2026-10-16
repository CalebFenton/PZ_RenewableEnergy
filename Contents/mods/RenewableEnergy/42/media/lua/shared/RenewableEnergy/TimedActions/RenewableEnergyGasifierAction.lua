require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/WoodGas/GasifierJobs"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"

-- Every job at a gasifier (RenewableEnergy.GasifierJobs). In multiplayer the client runs start()
-- and perform() and the server rebuilds the action from new()'s parameters and runs complete(),
-- which does the job; single player runs both. A global, as the server finds the class by its
-- Type (NetTimedAction.parse).
RenewableEnergyGasifierAction = ISBaseTimedAction:derive("RenewableEnergyGasifierAction")

local Action = RenewableEnergyGasifierAction
local Gasifier, GasifierJobs = RenewableEnergy.Gasifier, RenewableEnergy.GasifierJobs

-- How far from the middle of the gasifier's square, on each axis, the character may work at it:
-- what luautils.walkAdj counts as there, and a little for drift and a client's lag.
local REACH = 2.6

local function withinReach(character, object)
    local square = object:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= REACH
        and math.abs(character:getY() - (square:getY() + 0.5)) <= REACH
        and math.abs(character:getZ() - square:getZ()) < 1
end

local function onSquare(object)
    return object ~= nil and object:getObjectIndex() ~= -1
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local summary = self.gasifier and Gasifier.currentSummary(self.gasifier)
    return GasifierJobs.minutesFor(self.job, summary) * RenewableEnergyAction.unitsPerMinute()
end

function Action:isValid()
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    return onSquare(self.gasifier) and withinReach(self.character, self.gasifier)
end

function Action:waitToStart()
    self.character:faceThisObject(self.gasifier)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.gasifier)
end

function Action:start()
    if not isClient() and GasifierJobs.refusal(self.character, self.job, Gasifier.currentSummary(self.gasifier)) then
        self:forceStop()
        return
    end
    local shovel = self.job == GasifierJobs.CLEAN_ASH and self.character:getPrimaryHandItem()
    if shovel then
        -- As vanilla's Clear Ashes digs, with the shovel the menu put in hand.
        self:setActionAnim(BuildingHelper.getShovelAnim(shovel))
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
    end
end

function Action:perform()
    if self.job == GasifierJobs.LIGHT then
        self.character:playSound("CampfireLight")
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so this checks the job again, and that the character is at the
-- gasifier, which NetTimedAction doesn't check.
function Action:complete()
    if not onSquare(self.gasifier) or (isServer() and not withinReach(self.character, self.gasifier)) then
        return false
    end
    return RenewableEnergy.GasifierSystem.perform(self.character, self.job, self.gasifier)
end

-- Parameter names match the fields: the multiplayer server rebuilds the action by passing them to
-- new() in order (NetTimedAction).
function Action:new(character, job, gasifier)
    local o = ISBaseTimedAction.new(self, character)
    o.job = job
    o.gasifier = gasifier
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
