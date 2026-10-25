-- The authority's half of the car alternator tests: the car's state as the server holds it, the
-- hood the job needs open, and a wreck scrapped where vanilla's scrap completes. Only registers
-- handlers, so a --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says
-- how these handlers work.

require "PZHarness/ServerHandlers"
require "Vehicles/TimedActions/ISRemoveBurntVehicle"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local onVehicle = Helpers.onVehicle

local function alternatorState(vehicle)
    local CarAlternator = RenewableEnergy.CarAlternator
    return { out = CarAlternator.isOut(vehicle), hoodOpen = CarAlternator.hoodOpen(vehicle) }
end

-- Whether the server's copy of the car has its alternator out, and its hood open.
onVehicle("alternatorState", alternatorState)

-- Opens the car's hood, and unlocks its doors so that working on the engine needs no key
-- (VehicleUtils.RequiredKeyNotFound), both sent to the clients, as a player who got in would
-- leave them.
onVehicle("openCarHood", function(vehicle)
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        local door = part:getDoor()
        if door then
            if part:getId() == RenewableEnergy.CarAlternator.HOOD then
                door:setOpen(true)
            else
                door:setLocked(false)
            end
            vehicle:transmitPartDoor(part)
        end
    end
    return alternatorState(vehicle)
end)

-- Takes the alternator out for the player straight away, as the job's complete() would; answers
-- whether it gave one, which it mustn't once the alternator is out.
onVehicle("takeOutAlternatorAgain", function(vehicle, _, player)
    return { gave = RenewableEnergy.CarAlternator.takeOut(player, vehicle) }
end)

local function isAlternator(object)
    local item = object:getItem()
    return item ~= nil and item:getFullType() == RenewableEnergy.CarAlternator.ITEM
end

-- Scraps the wreck as vanilla's blowtorch job completes it (ISRemoveBurntVehicle:complete), the
-- player's blowtorch a fresh one, and answers how many car alternators it left on the wreck's
-- square and whether the wreck is gone. Everything the scrap dropped goes when the test ends.
onVehicle("scrapWreck", function(vehicle, _, player, defer)
    local square = vehicle:getSquare()
    local before = {}
    local objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        before[objects:get(i)] = true
    end
    local action = ISRemoveBurntVehicle:new(player, vehicle)
    action.item = instanceItem("Base.BlowTorch")
    local done = action:complete()
    local dropped, alternators = {}, 0
    objects = square:getWorldObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if not before[object] then
            table.insert(dropped, object)
            if isAlternator(object) then
                alternators = alternators + 1
            end
        end
    end
    defer(function()
        for _, object in ipairs(dropped) do
            Helpers.removeFloorItem(square, object)
        end
    end)
    return { done = done == true, alternators = alternators, removed = vehicle:isRemovedFromWorld() }
end)
