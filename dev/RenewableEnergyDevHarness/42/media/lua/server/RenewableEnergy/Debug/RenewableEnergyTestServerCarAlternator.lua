-- The authority's half of the car alternator tests: the hood the job needs open, and a wreck
-- scrapped where vanilla's scrap completes. Only registers handlers, so a --stay rerun loads it
-- again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "Vehicles/TimedActions/ISRemoveBurntVehicle"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

-- Opens the car's hood, and unlocks its doors so that working on the engine needs no key
-- (VehicleUtils.RequiredKeyNotFound), both sent to the clients, as a player who got in would
-- leave them.
handler("openCarHood", function(_, args)
    local vehicle = Helpers.vehicleAt(args)
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
    return {}
end)

-- Takes the alternator out for the player straight away, as the job's complete() would; answers
-- whether it gave one, which it mustn't once the alternator is out.
handler("takeOutAlternatorAgain", function(player, args)
    return { gave = RenewableEnergy.CarAlternator.takeOut(player, Helpers.vehicleAt(args)) }
end)

-- Scraps the wreck as vanilla's blowtorch job completes it (ISRemoveBurntVehicle:complete), the
-- player's blowtorch a fresh one, rolling `args.roll` (Helpers.trialRoll) against the player's
-- CarAlternator.scrapChance, and answers how many car alternators it left on the wreck's square
-- and whether the wreck is gone. Everything the scrap dropped goes when the test ends.
handler("scrapWreck", function(player, args, defer)
    local CarAlternator, vehicle = RenewableEnergy.CarAlternator, Helpers.vehicleAt(args)
    local chance = CarAlternator.scrapChance(player:getPerkLevel(Perks.Mechanics), player:getPerkLevel(Perks.MetalWelding))
    local square = vehicle:getSquare()
    local before = Helpers.worldItems({ square })
    local action = ISRemoveBurntVehicle:new(player, vehicle)
    action.item = instanceItem("Base.BlowTorch")
    local done = Helpers.withRolls(defer, Helpers.trialRoll(args.roll, chance), action.complete, action)
    local alternators = 0
    for _, object in ipairs(Helpers.newSince(before, Helpers.worldItems({ square }))) do
        defer(function() PZHarness.Fixtures.removePlaced(object) end)
        local item = object:getItem()
        if item and item:getFullType() == CarAlternator.ITEM then
            alternators = alternators + 1
        end
    end
    return { done = done == true, alternators = alternators, removed = vehicle:isRemovedFromWorld() }
end)
