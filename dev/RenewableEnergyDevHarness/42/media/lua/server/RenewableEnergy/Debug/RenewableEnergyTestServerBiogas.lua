-- The authority's half of the biogas tests: the stink and running a digester; the harness's record
-- kit drives the digesters' records (RenewableEnergyTestKinds).

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
PZHarness.checkHandler("baggedWaterMaterials", function(expect, expectNear, _, player)
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

-- What the authority's copy of the character smells: its noxious smell moodle level; the corpses
-- and moving objects on the square at x, y, z, which ghosts never join; and the corpse counts at
-- which the game's smell levels start (Stink.LEVEL_CORPSES), which a multiplayer client's Lua
-- doesn't have.
handler("stinkRead", function(player, args)
    local square = PZHarness.Fixtures.squareAt(args)
    local levels = {}
    for i, count in ipairs(Stink.LEVEL_CORPSES) do
        levels[i] = count
    end
    return {
        level = player:getMoodles():getMoodleLevel(MoodleType.NOXIOUS_SMELL),
        bodies = square and square:getDeadBodys():size() or -1,
        objects = square and square:getMovingObjects():size() or -1,
        levels = levels,
    }
end)

-- Stops the authority's clock while `args.frozen`, until the test ends, so that no game minute
-- passes: what a game minute would do later can't pass for what happened at once.
handler("freezeClock", function(player, args, defer)
    local options, name = getDebugOptions(), "GameTime.TimeOfDay.Freeze"
    local was = options:getBoolean(name)
    options:setBoolean(name, args.frozen)
    defer(function() options:setBoolean(name, was) end)
    return {}
end)

-- The stink score (DigesterObject:stinkScore) of a digester in each state, against the sums of its
-- constants, and the corpses a score smells like (DigesterObject.corpsesFor): none just below the
-- first of Digester.SMELL_SCORES, each smell level's first count at its score, and one short of the
-- next level's count just below the next score.
PZHarness.checkHandler("digesterStink", function(_, expectNear, expectEqual)
    local needed = getSandboxOptions():getCompostHours()
    -- A record of `tier`, mature (14 days of gas), fed to its cap, outdoors, with `fields` over that;
    -- stinkScore reads only its fields and its tier.
    local function score(tier, fields)
        local state = { luaSystem = { owner = Digester }, tier = tier, fed = true, started = true, gasHours = 14 * 24,
            startupHours = 0, seedHours = 0, potential = Digester.TIERS[tier].potentialCap, sludge = 0, sour = false,
            indoors = false }
        for key, value in pairs(fields) do
            state[key] = value
        end
        return setmetatable(state, { __index = DigesterObject }):stinkScore()
    end
    -- DigesterObject's constants: a startup stinks 1.0, plus 0.5 at its middle (a sine); gas brings
    -- it from 0.8 to 0.4 over 14 days; full sludge adds 0.8 and souring 1.5; a part-filled one
    -- stinks 0.5 + 0.5 × its fill of that; indoors twice that; all times its tier's stink (barrel 1,
    -- insulated 0.6, dome 0.3, which stops at 0.99).
    for _, case in ipairs({
        { "an unfed barrel", "barrel", { fed = false }, 0 },
        { "a barrel just fed", "barrel", { started = false }, 1.0 },
        { "a barrel halfway through its startup", "barrel", { started = false, startupHours = needed / 2 }, 1.5 },
        { "a barrel with its first gas", "barrel", { gasHours = 0 }, 0.8 },
        { "a barrel a week into its gas", "barrel", { gasHours = 7 * 24 }, 0.6 },
        { "a mature barrel", "barrel", {}, 0.4 },
        { "a mature barrel half full of sludge", "barrel", { sludge = 50 }, 0.4 + 0.8 * 0.5 },
        { "a sour mature barrel", "barrel", { sour = true }, 0.4 + 1.5 },
        { "a mature barrel fed to half its cap", "barrel", { potential = 2.5 }, 0.4 * (0.5 + 0.5 * 0.5) },
        { "a mature barrel with nothing left to digest", "barrel", { potential = 0 }, 0.4 * 0.5 },
        { "a mature barrel indoors", "barrel", { indoors = true }, 0.4 * 2 },
        { "a mature insulated digester", "insulated", {}, 0.4 * 0.6 },
        { "a mature brick dome", "dome", {}, 0.4 * 0.3 },
        -- (1.5 + 0.8 + 1.5) × 0.3 = 1.14, past the dome's cap.
        { "a sour brick dome full of sludge mid-startup", "dome",
            { started = false, startupHours = needed / 2, sour = true, sludge = 100 }, 0.99 },
    }) do
        expectNear("the stink score of " .. case[1], score(case[2], case[3]), case[4], 1e-9)
    end

    local corpsesFor = DigesterObject.corpsesFor
    local levels, scores = Stink.LEVEL_CORPSES, Digester.SMELL_SCORES
    local below = 0.001
    local function smells(score, corpses)
        expectEqual("corpses a stink score of " .. score .. " smells like", corpsesFor(score), corpses)
    end
    smells(scores[1] - below, 0)
    for i, score in ipairs(scores) do
        smells(score, levels[i])
        if scores[i + 1] then
            smells(scores[i + 1] - below, levels[i + 1] - 1)
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
