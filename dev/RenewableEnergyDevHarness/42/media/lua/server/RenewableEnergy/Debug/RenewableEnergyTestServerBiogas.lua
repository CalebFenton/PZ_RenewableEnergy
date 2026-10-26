-- The authority's half of the biogas tests: the stink, the digesters, propane on the floor, and the
-- Global Object System records both digesters and gasifiers are (Helpers.recordAt), which the wood
-- gas tests drive too. Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerChecks"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler
local removePlaced = PZHarness.Fixtures.removePlaced
local need = PZHarness.need
local Items = require "cf_commonlib/Items"

-- Carried bags count as inventory for jobs, including water split across nested bags. The same
-- selection must satisfy the menu's needs and consume fullest first without taking tainted water.
PZHarness.checkHandler("baggedWaterMaterials", function(expect, expectNear, player)
    local Materials = require "cf_commonlib/Materials"
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

-- Makes the source `args.key` at x, y, z smell like `args.count` corpses (RenewableEnergy.Stink),
-- until the test ends.
handler("stinkSet", function(player, args, defer)
    local Stink = RenewableEnergy.Stink
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
    for i, count in ipairs(RenewableEnergy.Stink.LEVEL_CORPSES) do
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
    local own, ring = RenewableEnergy.Stink.spread(args.count)
    return { own = own, ring = ring }
end)

-- The stink score's edges (Digester.SMELL_SCORES): none just below the first, then each smell
-- level's corpses from its edge up to just below the next.
PZHarness.checkHandler("digesterCorpsesFor", function(expect)
    local corpsesFor = RenewableEnergy.DigesterObject.corpsesFor
    local levels, scores = RenewableEnergy.Stink.LEVEL_CORPSES, RenewableEnergy.Digester.SMELL_SCORES
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

-- Records (digesters and gasifiers) -----------------------------------------------------------------

-- Builds the record of kind `args.kind` on the Sprites[kind] tile `args.tile` at x, y, z as the
-- build menu does (Helpers.placeRecord). Taken away when the test ends, the way the game removes
-- it, found again by its place, since a chunk that unloaded and loaded meanwhile holds a new copy.
handler("placeRecord", function(player, args, defer)
    local thumpable = Helpers.placeRecord(args.kind, args.tile, Helpers.squareAt(args))
    defer(function() removePlaced(Helpers.findOn(args) or thumpable) end)
    return {}
end)

-- Sets the record's fields `args.fields` as of now, and each field of `args.ago` ({ [field] =
-- hours }) to the world hour that many hours before now, then shows and sends what changed. Each
-- must be one of its SAVED_FIELDS, the record's state: a misspelled one would sit beside the field
-- the code reads, and change nothing.
handler("setRecord", function(player, args)
    local record = Helpers.recordAt(args)
    local saved = {}
    for _, field in ipairs(Helpers.RECORD_KINDS[args.kind].object().SAVED_FIELDS) do
        saved[field] = true
    end
    for _, fields in ipairs({ args.fields or {}, args.ago or {} }) do
        for key in pairs(fields) do
            need(saved[key], "a saved field " .. tostring(key) .. " of a " .. args.kind)
        end
    end
    local now = getGameTime():getWorldAgeHours()
    for key, value in pairs(args.fields or {}) do
        record[key] = value
    end
    for key, hours in pairs(args.ago or {}) do
        record[key] = now - hours
    end
    record.lastHour = now
    record:afterChange()
    return {}
end)

-- Puts `args.items` ({ [container name] = { { type, count, rotten } } }, the names of
-- Helpers.RECORD_KINDS) in the record's containers, past their filters, as a player's transfer
-- would: the record hears of it only in its next pass.
handler("fillRecord", function(player, args)
    local _, object = Helpers.recordAt(args)
    local containers = Helpers.RECORD_KINDS[args.kind].containers(object)
    for name, entries in pairs(args.items) do
        local container = need(containers[name], "a " .. name .. " on the " .. args.kind)
        for _, entry in ipairs(entries) do
            for _ = 1, entry.count or 1 do
                local item = need(instanceItem(entry.type), "an item " .. tostring(entry.type))
                if entry.rotten then
                    item:setAge(item:getOffAgeMax() + 1)
                end
                Items.addItem(container, item)
            end
        end
    end
    return {}
end)

-- Brings the record of kind `args.kind` at x, y, z up to now as its pass does, as though
-- `args.hours` had passed since its last, its chunk loaded or not. Answers its state
-- (Helpers.recordState), from the record alone while unloaded.
handler("ageRecord", function(player, args)
    local kind = Helpers.RECORD_KINDS[args.kind]
    local record = need(kind and kind.owner().recordAt(args.x, args.y, args.z),
        "a " .. tostring(args.kind) .. " record at " .. args.x .. "," .. args.y)
    record.lastHour = getGameTime():getWorldAgeHours() - args.hours
    record:update()
    return Helpers.recordState(args.kind, record, record:getIsoObject())
end)

-- The record's state (Helpers.recordState).
handler("readRecord", function(player, args)
    local record, object = Helpers.recordAt(args)
    return Helpers.recordState(args.kind, record, object)
end)

-- Digesters -------------------------------------------------------------------------------------

-- Runs the digester at x, y, z for `args.hours` at the air temperature `args.air` (°C), feeding
-- from its hopper as its pass does, without moving the clock.
handler("runDigester", function(player, args)
    local record, object = Helpers.recordAt(args)
    record:run(args.hours, object:getContainer(), args.air)
    record.lastHour = getGameTime():getWorldAgeHours()
    record:afterChange()
    return {}
end)

-- Propane --------------------------------------------------------------------------------------

-- Drops an `args.type` holding `args.uses` (its share of full) on the floor of the square at x, y,
-- z, as a player dropping it does, for everyone to see. Taken away when the test ends.
handler("floorItem", function(player, args, defer)
    local square = Helpers.squareAt(args)
    local item = need(instanceItem(args.type), "an item " .. tostring(args.type))
    if args.uses then
        item:setCurrentUsesFloat(args.uses)
    end
    square:AddWorldInventoryItem(item, 0.5, 0.5, 0)
    defer(function()
        local world = item:getWorldItem()
        if world then
            removePlaced(world)
        end
    end)
    return {}
end)
