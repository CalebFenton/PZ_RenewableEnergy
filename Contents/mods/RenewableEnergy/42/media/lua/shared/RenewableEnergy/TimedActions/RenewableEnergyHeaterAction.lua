require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Biogas/GasHeater"

-- Lighting and putting out a gas heater (RenewableEnergy.GasHeater). In multiplayer the client
-- runs start() and perform() and the server rebuilds the action from new()'s parameters and runs
-- complete(); single player runs both. A global, as the server finds the class by its Type
-- (NetTimedAction.parse).
RenewableEnergyHeaterAction = ISBaseTimedAction:derive("RenewableEnergyHeaterAction")

local Action = RenewableEnergyHeaterAction
local GasHeater = RenewableEnergy.GasHeater

-- How far from the middle of the heater's square, on each axis, the character may work at it.
local REACH = 2.6
-- As long as vanilla takes to light a lamp.
local DURATION = 50

local function withinReach(character, object)
    local square = object:getSquare()
    return square ~= nil and math.abs(character:getX() - (square:getX() + 0.5)) <= REACH
        and math.abs(character:getY() - (square:getY() + 0.5)) <= REACH
        and math.abs(character:getZ() - square:getZ()) < 1
end

function Action:getDuration()
    return self.character:isTimedActionInstant() and 1 or DURATION
end

function Action:isValid()
    if self.action and self.action:getJobDelta() >= 0.9 then
        return true
    end
    return self.heater ~= nil and self.heater:getObjectIndex() ~= -1 and withinReach(self.character, self.heater)
end

function Action:waitToStart()
    self.character:faceThisObject(self.heater)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.heater)
end

function Action:start()
    if not isClient() and GasHeater.refusal(self.character, self.job, self.heater) then
        self:forceStop()
        return
    end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function Action:perform()
    if self.job == GasHeater.LIGHT then
        self.character:playSound("CampfireLight")
    end
    ISBaseTimedAction.perform(self)
end

-- The server never calls isValid(), so this checks again that the character is at the heater.
function Action:complete()
    if not (self.heater and self.heater:getObjectIndex() ~= -1) or (isServer() and not withinReach(self.character, self.heater)) then
        return false
    end
    return GasHeater.perform(self.character, self.job, self.heater)
end

-- Parameter names match the fields: the multiplayer server rebuilds the action by passing them to
-- new() in order (NetTimedAction).
function Action:new(character, job, heater)
    local o = ISBaseTimedAction.new(self, character)
    o.job = job
    o.heater = heater
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end
