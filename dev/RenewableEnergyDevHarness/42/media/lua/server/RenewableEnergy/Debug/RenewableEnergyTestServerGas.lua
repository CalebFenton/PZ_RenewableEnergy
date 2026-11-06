-- The authority's half of the gas line and wood gas tests (RenewableEnergyTestsGasLine.lua,
-- RenewableEnergyTestsWoodGas.lua): generators with the Gas Conversion Kit, the load they carry,
-- burning a gasifier's wood, and vanilla's wood fires, and the bank tests' generators.

require "PZHarness/ServerHandlers"
require "PZHarness/ServerFixtures"
require "PZHarness/ServerRecords"
require "PZHarness/Fixtures"
local Squares = require "cf_commonlib/Squares"
local Kinds = require "RenewableEnergy/Debug/RenewableEnergyTestKinds"
local FireAsh = require "RenewableEnergy/WoodGas/FireAsh"
local GasKit = require "RenewableEnergy/GasLine/GasKit"
local GasLines = require "RenewableEnergy/GasLine/GasLines"
local Payers = require "RenewableEnergy/PowerBank/Payers"
local Sprites = require "RenewableEnergy/Sprites"

local handler = PZHarness.serverHandler
local Fixtures, Records = PZHarness.Fixtures, PZHarness.Records

-- Generators ------------------------------------------------------------------------------------

local function generatorOn(args)
    return Kinds.find({ x = args.x, y = args.y, z = args.z, kind = "generator" })
end

-- `idle` and `bill` are vanilla's idle and whole bills an hour; the sprite picks the kit's and
-- pipe's overlays (Sprites.gasKitFor).
local function generatorRead(generator)
    local state = GasKit.stateOf(generator)
    local plain
    if state then
        local keys = {}
        for key in pairs(state) do
            table.insert(keys, key)
        end
        plain = Fixtures.fieldsOf(state, keys)
        plain.connected = state.source ~= nil
        plain.sourceKind = state.source and state.source.kind
    end
    local building = generator:getSquare():getBuilding()
    return {
        running = generator:isActivated(), fuel = generator:getFuel(), idle = generator:getBasePowerConsumption(),
        bill = generator:getTotalPowerUsing(), condition = generator:getCondition(), state = plain,
        overlays = Fixtures.overlaysOf(generator), sprite = Sprites.nameOf(generator),
        toxic = building ~= nil and building:isToxic(), hours = getGameTime():getWorldAgeHours(),
    }
end

handler("generatorRead", function(player, args)
    return generatorRead(generatorOn(args))
end)

-- What the authority's ISTakeGenerator:complete() answers for the generator at x, y, z, as when a
-- client's Take Generator reaches it, and whether the generator is still on its square after.
handler("takeGenerator", function(player, args)
    local done = ISTakeGenerator.complete({ character = player, generator = generatorOn(args) })
    return { done = done == true, kept = Kinds.findOn({ x = args.x, y = args.y, z = args.z, kind = "generator" }) ~= nil }
end)

-- A bank's read and its generators' reads in one call. A job's reads before and after
-- (T.job's `reads`) bracket the job with it in the same call, so no tick or explicit billing can
-- repair a missing job-boundary settlement between them.
handler("bankSettlement", function(_, args)
    local record, bank = Records.at({ kind = "bank", x = args.x, y = args.y, z = args.z })
    PZHarness.need(bank, "the bank's tile on the server")
    local state = Records.read("bank", record, bank)
    state.generators = {}
    for i, at in ipairs(args.generators or {}) do
        local generator = generatorOn(at)
        state.generators[i] = generatorRead(generator)
        state.generators[i].chargesBank = record:chargesFrom(generator)
    end
    return state
end)

-- Answers the world update count it acted at (`frame`, PZHarness.worldFrame).
handler("generatorSet", function(player, args)
    local generator = generatorOn(args)
    if args.pour then
        generator:setFuel(math.min(generator:getMaxFuel(), generator:getFuel() + args.pour))
    end
    if args.running ~= nil then
        ISActivateGenerator.complete({ generator = generator, activate = args.running })
    end
    if args.rebuild then
        -- What an appliance switching in its reach does: the generators reaching it rebuild their bill
        -- in their next update (IsoGenerator.update).
        IsoGenerator.updateGenerator(generator:getSquare())
    end
    return { frame = getWorld():getFrameNo() }
end)

-- Takes `args.litres` from the fuel of the generator at x, y, z, as vanilla's hourly bill
-- (IsoGenerator.update) and a bank charging from it (Bank:chargeFrom) take it.
handler("burnFuel", function(player, args)
    local generator = generatorOn(args)
    generator:setFuel(generator:getFuel() - args.litres)
    return {}
end)

-- Bills every running generator its share, as the ten-minute pass does (Payers.billGenerators).
handler("billGenerators", function()
    Payers.billGenerators()
    return {}
end)

-- Sets the wear chance of the item script of the generator at x, y, z to one in `args.oneIn` an
-- hour it runs (its ConditionLowerChanceOneIn) until the test ends.
handler("generatorWearChance", function(player, args, defer)
    local generator = generatorOn(args)
    local item = PZHarness.need(getScriptManager():getItem(generator:getGeneratorItemType()),
        "the item script of the generator at " .. args.x .. "," .. args.y)
    local was = item:getConditionLowerChance()
    item:setConditionLowerChance(args.oneIn)
    defer(function() item:setConditionLowerChance(was) end)
    return {}
end)

-- Runs the gas pass as though `args.hours` had passed since the last of the kitted generator at
-- x, y, z.
handler("gasPass", function(player, args)
    local generator = generatorOn(args)
    local state = PZHarness.need(GasKit.stateOf(generator), "a kit on the generator at " .. args.x .. "," .. args.y)
    state.lastHour = getGameTime():getWorldAgeHours() - args.hours
    GasLines.updateAll()
    return {}
end)

-- Makes every kitted generator deliver `args.watts` in place of what its scan finds, until the test
-- ends, for the documented exact-cap scenarios. GasLines.run looks Payers.deliveredW up on every
-- call.
handler("gasLoad", function(_, args, defer)
    Fixtures.replace(defer, Payers, "deliveredW", function() return args.watts end)
    return {}
end)

-- Gasifiers ------------------------------------------------------------------------------------

-- Burns `args.kg` in the gasifier at x, y, z, as a pass would, to leave its ash and tar.
handler("burnGasifier", function(_, args)
    local record = Records.at({ kind = "gasifier", x = args.x, y = args.y, z = args.z })
    local burned = record:burn(args.kg)
    record:afterChange()
    return { burned = burned }
end)

-- Wood fires ------------------------------------------------------------------------------------

-- A charcoal grill's tile, as vanilla's own tests place one (TimedActionsTests.lua's newBBQCharcoal).
local CHARCOAL_GRILL = "appliances_cooking_01_35"

-- A vanilla wood fire on the square at `args`, empty and unlit: a campfire as building one makes it
-- (SCampfireSystem:addCampfire), or with `args.grill` a charcoal grill. Whatever fire stands there
-- when the test ends goes.
handler("placeFire", function(_, args, defer)
    local square = PZHarness.squareAt(args)
    if args.grill then
        local grill = IsoBarbecue.new(getCell(), square, getSprite(CHARCOAL_GRILL))
        square:AddTileObject(grill)
        grill:transmitCompleteItemToClients()
    else
        SCampfireSystem.instance:addCampfire(square)
    end
    defer(function()
        local fire = Squares.findObjectOn(Fixtures.squareAt(args), FireAsh.isFire)
        if fire then
            Fixtures.removePlaced(fire)
        end
    end)
    return {}
end)

-- Burns `args.minutes` of the fuel in the unlit wood fire at `args`, as the campfire system's
-- minutes or a grill's update would while it burned. Answers the Wood Ash it then has
-- (FireAsh.ashItems).
handler("burnFire", function(_, args)
    local fire = PZHarness.need(Squares.findObjectOn(PZHarness.squareAt(args), FireAsh.isFire), "a wood fire on the server")
    local campfire = SCampfireSystem.instance:getLuaObjectOnSquare(fire:getSquare())
    if campfire then
        SCampfireSystem.instance:lowerFuelAmountSpecific(campfire, args.minutes)
    else
        fire:setFuelAmount(fire:getFuelAmount() - args.minutes)
        fire:sendObjectChange(IsoObjectChange.STATE)
    end
    return { ash = FireAsh.ashItems(fire) }
end)
