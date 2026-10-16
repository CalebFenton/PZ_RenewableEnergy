require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/GasLine/GasKit"
require "RenewableEnergy/TimedActions/RenewableEnergyAction"

-- Every job at a generator's Gas Conversion Kit (RenewableEnergy.GasKit). In multiplayer the
-- client runs start() and perform() and the server rebuilds the action from new()'s parameters
-- and runs complete(), which does the job; single player runs both. A global, as the server finds
-- the class by its Type (NetTimedAction.parse).
RenewableEnergyGasAction = ISBaseTimedAction:derive("RenewableEnergyGasAction")

local Action = RenewableEnergyGasAction
local GasKit = RenewableEnergy.GasKit

-- How far from the middle of the generator's square, on each axis, the character may work at it:
-- what luautils.walkAdj counts as there, and a little for drift and a client's lag.
local REACH = 2.6

local function onSquare(object)
    return object ~= nil and object:getObjectIndex() ~= -1
end

local function withinReach(character, object)
    local square = object:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= REACH
        and math.abs(character:getY() - (square:getY() + 0.5)) <= REACH
        and math.abs(character:getZ() - square:getZ()) < 1
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return GasKit.MINUTES[self.job] * RenewableEnergyAction.unitsPerMinute()
end

function Action:isValid()
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    return onSquare(self.generator) and withinReach(self.character, self.generator)
end

function Action:waitToStart()
    self.character:faceThisObject(self.generator)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.generator)
end

function Action:start()
    if not isClient() and GasKit.refusal(self.character, self.job, self.generator, self.digester) then
        self:forceStop()
        return
    end
    if self.job == GasKit.TO_GAS or self.job == GasKit.TO_PETROL then
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
        return
    end
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = self.character:playSound("GeneratorRepair")
end

function Action:stop()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISBaseTimedAction.stop(self)
end

function Action:perform()
    if self.sound then
        self.character:stopOrTriggerSound(self.sound)
    end
    ISInventoryPage.renderDirty = true
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so this checks the job again, and that the character is at the
-- generator, which NetTimedAction doesn't check.
function Action:complete()
    if not onSquare(self.generator) or (isServer() and not withinReach(self.character, self.generator)) then
        return false
    end
    return RenewableEnergy.GasLines.perform(self.character, self.job, self.generator, self.digester)
end

-- Parameter names match the fields: the multiplayer server rebuilds the action by passing them to
-- new() in order (NetTimedAction). `digester` is the far end of Connect Gas Line, else nil.
function Action:new(character, job, generator, digester)
    local o = ISBaseTimedAction.new(self, character)
    o.job = job
    o.generator = generator
    o.digester = digester
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
