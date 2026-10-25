-- The authority's half of the gas line and wood gas tests (RenewableEnergyTestsGasLine.lua,
-- RenewableEnergyTestsWoodGas.lua): generators with the Gas Conversion Kit, the load they carry,
-- and burning a gasifier's wood. The generator reads, settings and billing serve the bank tests'
-- generators too (RenewableEnergyTestsBankGenerators.lua). The records themselves are
-- RenewableEnergyTestServerBiogas.lua's.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
require "PZHarness/Fixtures"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

-- Generators ------------------------------------------------------------------------------------

local function generatorOn(args)
    local square = PZHarness.Fixtures.squareAt(args)
    local generator = square and RenewableEnergy.findObjectOn(square, RenewableEnergy.isGenerator)
    if not generator then
        return nil, "a generator at " .. tostring(args.x) .. "," .. tostring(args.y)
    end
    return generator
end

-- The generator at x, y, z: whether it runs, its fuel and condition, vanilla's idle bill an hour
-- (`idle`) and its whole bill an hour (`bill`), its kit's state (nil without a kit) with whether a
-- line is connected and to what kind of source, whether the gas pass lists it, its overlays and its
-- sprite, which picks the kit's and pipe's overlays (Sprites.gasKitFor), whether its building is
-- toxic, and the world hour on the server as it was read (`hours`).
handler("generatorRead", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local GasKit = RenewableEnergy.GasKit
    local state = GasKit.stateOf(generator)
    local plain
    if state then
        local keys = {}
        for key in pairs(state) do
            table.insert(keys, key)
        end
        plain = PZHarness.Fixtures.fieldsOf(state, keys)
        plain.connected = state.source ~= nil
        plain.sourceKind = state.source and state.source.kind
    end
    local building = generator:getSquare():getBuilding()
    return {
        running = generator:isActivated(), fuel = generator:getFuel(), idle = generator:getBasePowerConsumption(),
        bill = generator:getTotalPowerUsing(), condition = generator:getCondition(), state = plain,
        listed = RenewableEnergy.GasLines.isListed(generator),
        overlays = PZHarness.Fixtures.overlaysOf(generator), sprite = RenewableEnergy.Sprites.nameOf(generator),
        toxic = building ~= nil and building:isToxic(), hours = getGameTime():getWorldAgeHours(),
    }
end)

-- Pours `args.pour` litres into the generator at x, y, z, as a player pouring petrol does (onto
-- whatever it shows), switches it on or off (`args.running`), as a player does, and has vanilla
-- rebuild the bills of the generators reaching it (`args.rebuild`). Answers the world update count
-- it acted at (`frame`, see worldFrame).
handler("generatorSet", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
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

-- The world updates the authority has run (`frame`). A server serves commands between its updates
-- (GameServer.main), and single player within one, after the objects' (IsoCell.update), so once
-- the count passes an earlier answer's, every generator has had an update since that answer, and
-- a step queued after the wait for it comes after that update's OnTick too.
handler("worldFrame", function()
    return { frame = getWorld():getFrameNo() }
end)

-- Takes `args.litres` from the fuel of the generator at x, y, z, as vanilla's hourly bill
-- (IsoGenerator.update) and a bank charging from it (Bank:chargeFrom) take it.
handler("generatorBurn", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    generator:setFuel(generator:getFuel() - args.litres)
    return {}
end)

-- Takes away, when the test ends, whatever generator stands at x, y, z then: one whose chunk
-- unloaded and loaded meanwhile is a new copy, which the generator fixture's own removal misses.
handler("generatorTrack", function(player, args, defer)
    defer(function()
        local generator = generatorOn(args)
        if generator then
            PZHarness.Fixtures.removePlaced(generator)
        end
    end)
    return {}
end)

-- Bills every running generator its share, as the ten-minute pass does (Payers.billGenerators).
handler("billGenerators", function()
    RenewableEnergy.Payers.billGenerators()
    return {}
end)

-- Sets the wear chance of the item script of the generator at x, y, z to one in `args.oneIn` an
-- hour it runs (its ConditionLowerChanceOneIn) until the test ends.
handler("generatorWearChance", function(player, args, defer)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local item = getScriptManager():getItem(generator:getGeneratorItemType())
    if not item then return nil, "the item script of the generator at " .. args.x .. "," .. args.y end
    local was = item:getConditionLowerChance()
    item:setConditionLowerChance(args.oneIn)
    defer(function() item:setConditionLowerChance(was) end)
    return {}
end)

-- Builds the gas action of `args.feature` and `args.job` at the generator at x, y, z as the server
-- builds the one a client asks for (NetTimedAction.parse calls the class's new, the class first).
-- Answers whether that gave an action.
handler("gasActionFrom", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local action = RenewableEnergyGasAction.new(RenewableEnergyGasAction, player, args.feature, args.job, generator)
    return { built = action ~= nil }
end)

-- Does the kit job `args.job` at the generator at x, y, z for the character as the authority does
-- the one a client's action asks for once it ends: the action's complete(). Answers whether it was
-- done; a client's own action that the server turns down stops its whole queue.
handler("kitJobComplete", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local action = RenewableEnergyGasAction:new(player, "kit", args.job, generator)
    return { done = action:complete() }
end)

-- Has the kit job `args.job` not get done on the authority until the test ends, as a job whose
-- work fails there: its site's act (GasJobs.perform) answers false and changes nothing.
handler("kitJobNotDone", function(player, args, defer)
    local site = RenewableEnergy.GasLines.jobSite
    local act = site.act
    site.act = function(character, job, ...)
        if job == args.job then
            return false
        end
        return act(character, job, ...)
    end
    defer(function() site.act = act end)
    return {}
end)

-- Runs the gas pass as though `args.hours` had passed since the last of the kitted generator at
-- x, y, z.
handler("gasPass", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    local state = RenewableEnergy.GasKit.stateOf(generator)
    if not state then return nil, "a kit on the generator at " .. args.x .. "," .. args.y end
    state.lastHour = getGameTime():getWorldAgeHours() - args.hours
    RenewableEnergy.GasLines.updateAll()
    return {}
end)

-- Makes every kitted generator deliver `args.watts` in place of what its scan finds, until the test
-- ends. GasLines.run looks loadOf up on every call.
handler("gasLoad", function(player, args, defer)
    local GasLines = RenewableEnergy.GasLines
    local scan = GasLines.loadOf
    GasLines.loadOf = function() return args.watts end
    defer(function() GasLines.loadOf = scan end)
    return {}
end)

-- Gasifiers ------------------------------------------------------------------------------------

-- Burns `args.kg` in the gasifier record `args` (T.recordArgs), as a pass would, to leave its ash
-- and tar.
handler("gasifierBurn", function(player, args)
    local record, _, missing = Helpers.recordAt(args)
    if not record then return nil, missing end
    local burned = record:burn(args.kg)
    record:afterChange()
    return { burned = burned }
end)
