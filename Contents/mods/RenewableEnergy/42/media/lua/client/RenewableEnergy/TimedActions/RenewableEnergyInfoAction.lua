-- Opens an object's status window (a bank's, a digester's, a gasifier's) once the character stands
-- at it, as vanilla's info actions do (ISGeneratorInfoAction, ISCheckAnimalInsideTrailer): the
-- menu walks them over first, and the window closes once they walk away (InfoAction.inReach).
-- Client only, with no complete(): opening a window is nothing the server does.

require "TimedActions/ISBaseTimedAction"
require "RenewableEnergy/Utilities"

RenewableEnergy = RenewableEnergy or {}
local InfoAction = ISBaseTimedAction:derive("RenewableEnergyInfoAction")
RenewableEnergy.InfoAction = InfoAction

-- How far from the object, in squares on each axis, its window stays open: vanilla closes a
-- trailer's or a hutch's animal window past 4 squares (ISVehicleAnimalUI, ISAnimalUI).
local WINDOW_REACH = 4

--- Whether `object`'s window stays open for `playerNum`: the object still on its square and their
--- living character within WINDOW_REACH of it on its level.
function InfoAction.inReach(playerNum, object)
    local character = getSpecificPlayer(playerNum)
    return RenewableEnergy.onSquare(object) and character ~= nil and not character:isDead()
        and RenewableEnergy.withinReach(character, object, WINDOW_REACH)
end

function InfoAction:isValid()
    return RenewableEnergy.onSquare(self.object)
end

function InfoAction:waitToStart()
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function InfoAction:perform()
    self.open(self.character:getPlayerNum(), self.object)
    -- Removes the action from the queue and starts the next.
    ISBaseTimedAction.perform(self)
end

-- `open(playerNum, object)` opens the window.
function InfoAction:new(character, object, open)
    local o = ISBaseTimedAction.new(self, character)
    o.object = object
    o.open = open
    o.maxTime = 0
    return o
end

--- Walks `playerNum`'s character over to `object` and opens its window there with
--- `open(playerNum, object)`.
function InfoAction.queue(playerNum, object, open)
    local character = getSpecificPlayer(playerNum)
    if luautils.walkAdj(character, object:getSquare(), true) then
        ISTimedActionQueue.add(InfoAction:new(character, object, open))
    end
end

return InfoAction
