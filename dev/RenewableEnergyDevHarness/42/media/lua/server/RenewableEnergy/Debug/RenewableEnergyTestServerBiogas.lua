-- The authority's half of the biogas tests: the stink and running a digester; the harness's record
-- kit drives the digesters' records (RenewableEnergyTestKinds). Only registers handlers, so a
-- --stay rerun loads it again (RELOAD_FILES); RenewableEnergyTestHelpers.lua says how these
-- handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerChecks"
require "PZHarness/ServerRecords"
require "PZHarness/Fixtures"
local Materials = require "cf_commonlib/Materials"
local Digester = require "RenewableEnergy/Biogas/Digester"
local DigesterObject = require "RenewableEnergy/Biogas/DigesterObject"
local Stink = require "RenewableEnergy/Biogas/Stink"

local handler = PZHarness.serverHandler

-- Carried bags count as inventory for jobs, including water split across nested bags. The same
-- selection must satisfy the menu's needs and consume fullest first without taking tainted water.
PZHarness.checkHandler("baggedWaterMaterials", function(expect, expectNear, player)
    local inventory = player:getInventory()
    local outer = inventory:AddItem("Base.Bag_DuffelBag")
    local inner = outer:getInventory():AddItem("Base.Bag_DuffelBag")
    local function water(container, litres, tainted)
        local item = container:AddItem("Base.Bucket")
        local fluid = item:getFluidContainer()
        fluid:Empty()
        fluid:addFluid(tainted and FluidType.TaintedWater or FluidType.Water, litres)
        return fluid
    end
    local main = water(inventory, 1)
    local bagged = water(inner:getInventory(), 4)
    local tainted = water(outer:getInventory(), 6, true)
    local materials = { { water = 3, labelKey = "IGUI_RenewableEnergy_WaterLitres" } }
    expectNear("clean water available across carried bags", Materials.needs(player, materials)[1].have, 5)
    Materials.consume(player, materials)
    expectNear("water left in the fullest bagged bucket", bagged:getAmount(), 1)
    expectNear("water left in the smaller main-inventory bucket", main:getAmount(), 1)
    expectNear("tainted water after consuming clean water", tainted:getAmount(), 6)
    materials[1].water = 2
    Materials.consume(player, materials)
    expectNear("water left after consuming across containers", main:getAmount() + bagged:getAmount(), 0)
    expectNear("clean water available after consumption", Materials.needs(player, materials)[1].have, 0)
    expectNear("tainted water after consuming across containers", tainted:getAmount(), 6)
end)

-- Stink ------------------------------------------------------------------------------------------

-- Makes the source `args.key` at x, y, z smell like `args.count` corpses (Stink.set),
-- until the test ends.
handler("stinkSet", function(player, args, defer)
    Stink.set(args.key, args.x, args.y, args.z, args.count)
    defer(function() Stink.set(args.key, args.x, args.y, args.z, 0) end)
    return {}
end)

-- What the authority's copy of the character smells: its noxious smell moodle level and corpse
-- sickness rate; the corpses and moving objects on the square at x, y, z, which ghosts never join;
-- what is left of the filter of a worn gas mask, if any; and the corpse counts at which the game's
-- smell levels start (Stink.LEVEL_CORPSES), which a multiplayer client's Lua doesn't have.
handler("stinkRead", function(player, args)
    local square = PZHarness.Fixtures.squareAt(args)
    local mask
    local worn = player:getWornItems()
    for i = 0, worn:size() - 1 do
        local item = worn:getItemByIndex(i)
        if item and item:hasTag(ItemTag.GAS_MASK) then
            mask = item:getUsedDelta()
        end
    end
    local levels = {}
    for i, count in ipairs(Stink.LEVEL_CORPSES) do
        levels[i] = count
    end
    return {
        level = player:getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL),
        rate = player:getCorpseSicknessRate(),
        bodies = square and square:getDeadBodys():size() or -1,
        objects = square and square:getMovingObjects():size() or -1,
        mask = mask,
        levels = levels,
    }
end)

-- How an outdoor source smelling like `args.count` corpses spreads its ghosts (Stink.spread),
-- which a multiplayer client's Lua doesn't have.
handler("stinkSpread", function(_, args)
    local own, ring = Stink.spread(args.count)
    return { own = own, ring = ring }
end)

-- The stink score's edges (Digester.SMELL_SCORES): none just below the first, then each smell
-- level's corpses from its edge up to just below the next.
PZHarness.checkHandler("digesterCorpsesFor", function(expect)
    local corpsesFor = DigesterObject.corpsesFor
    local levels, scores = Stink.LEVEL_CORPSES, Digester.SMELL_SCORES
    local below = 0.001
    local function band(score, lowest, under)
        local corpses = corpsesFor(score)
        expect(corpses >= lowest and (not under or corpses < under),
            "a stink score of " .. score .. " smells like " .. corpses .. " corpses")
    end
    band(scores[1] - below, 0, 1)
    for i, score in ipairs(scores) do
        band(score, levels[i], levels[i + 1])
        if scores[i + 1] then
            band(scores[i + 1] - below, levels[i], levels[i + 1])
        end
    end
end)

-- Digesters -------------------------------------------------------------------------------------

-- Runs the digester at x, y, z for `args.hours` at the air temperature `args.air` (°C), feeding
-- from its hopper as its pass does, without moving the clock.
handler("runDigester", function(player, args)
    local record, object = PZHarness.Records.at({ kind = "digester", x = args.x, y = args.y, z = args.z })
    record:run(args.hours, PZHarness.need(object, "the digester's tile loaded on the server"):getContainer(), args.air)
    record.lastHour = getGameTime():getWorldAgeHours()
    record:afterChange()
    return {}
end)
