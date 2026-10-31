-- The authority's half of the car alternator tests: the hood the job needs open, and a wreck
-- scrapped where vanilla's scrap completes.

require "PZHarness/ServerHandlers"
require "Vehicles/TimedActions/ISRemoveBurntVehicle"
require "PZHarness/ServerFixtures"
require "PZHarness/Rolls"
local CarAlternator = require "RenewableEnergy/Gadgets/CarAlternator"

local handler = PZHarness.serverHandler

-- Opens the car's hood, and unlocks its doors so that working on the engine needs no key
-- (VehicleUtils.RequiredKeyNotFound), both sent to the clients, as a player who got in would
-- leave them.
handler("openCarHood", function(_, args)
    local vehicle = PZHarness.vehicleAt(args)
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        local door = part:getDoor()
        if door then
            if part:getId() == CarAlternator.HOOD then
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
    return { gave = CarAlternator.takeOut(player, PZHarness.vehicleAt(args)) }
end)

-- Scraps the wreck as vanilla's blowtorch job completes it (ISRemoveBurntVehicle:complete), the
-- player's blowtorch a fresh one, every roll at `args.roll`, and answers how many car alternators it left on the wreck's square
-- and whether the wreck is gone. Everything the scrap dropped goes when the test ends.
handler("scrapWreck", function(player, args, defer)
    local vehicle = PZHarness.vehicleAt(args)
    local square = vehicle:getSquare()
    local before = PZHarness.Fixtures.worldItems({ square })
    local action = ISRemoveBurntVehicle:new(player, vehicle)
    action.item = instanceItem("Base.BlowTorch")
    local done = PZHarness.Rolls.with(defer, args.roll, action.complete, action)
    local alternators = 0
    for _, object in ipairs(PZHarness.Fixtures.newSince(before, PZHarness.Fixtures.worldItems({ square }))) do
        defer(function() PZHarness.Fixtures.removePlaced(object) end)
        local item = object:getItem()
        if item and item:getFullType() == CarAlternator.ITEM then
            alternators = alternators + 1
        end
    end
    return { done = done == true, alternators = alternators, removed = vehicle:isRemovedFromWorld() }
end)
