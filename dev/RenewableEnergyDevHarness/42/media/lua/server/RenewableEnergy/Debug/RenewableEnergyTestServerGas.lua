-- The authority's half of the gas line and wood gas tests (RenewableEnergyTestsGasLine.lua,
-- RenewableEnergyTestsWoodGas.lua): generators with the Gas Conversion Kit, the load they carry,
-- and burning a gasifier's wood. The records themselves are RenewableEnergyTestServerBiogas.lua's.
-- Only registers handlers, so a --stay rerun loads it again (RELOAD_FILES);
-- RenewableEnergyTestHelpers.lua says how these handlers work.

require "PZHarness/ServerHandlers"
local Helpers = require "RenewableEnergy/Debug/RenewableEnergyTestHelpers"

local handler = PZHarness.serverHandler

-- Generators ------------------------------------------------------------------------------------

local function generatorOn(args)
    local square = Helpers.squareAt(args)
    local generator = square and RenewableEnergy.findObjectOn(square, RenewableEnergy.GasKit.isGenerator)
    if not generator then
        return nil, "a generator at " .. tostring(args.x) .. "," .. tostring(args.y)
    end
    return generator
end

-- The generator at x, y, z: whether it runs, its fuel, vanilla's idle bill an hour (`idle`), its
-- kit's state (nil without a kit) with whether a line is connected and to what kind of source,
-- whether the gas pass lists it, its overlays and its sprite, which picks the kit's and pipe's
-- overlays (Sprites.gasKitFor).
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
        plain = Helpers.plainFields(state, keys)
        plain.connected = state.source ~= nil
        plain.sourceKind = state.source and state.source.kind
    end
    local key = generator:getX() .. "," .. generator:getY() .. "," .. generator:getZ()
    return {
        running = generator:isActivated(), fuel = generator:getFuel(), idle = generator:getBasePowerConsumption(), state = plain,
        listed = ModData.getOrCreate(RenewableEnergy.GasLines.MOD_DATA)[key] ~= nil,
        overlays = Helpers.overlaysOf(generator), sprite = RenewableEnergy.Sprites.nameOf(generator),
    }
end)

-- Pours `args.pour` litres into the generator at x, y, z, as a player pouring petrol does (onto
-- whatever it shows), and switches it on or off (`args.running`), as a player does.
handler("generatorSet", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    if args.pour then
        generator:setFuel(math.min(generator:getMaxFuel(), generator:getFuel() + args.pour))
    end
    if args.running ~= nil then
        generator:setActivated(args.running)
    end
    return {}
end)

-- Takes `args.litres` from the fuel of the generator at x, y, z, as vanilla's hourly bill
-- (IsoGenerator.update) and a bank charging from it (Bank:chargeFrom) take it.
handler("generatorBurn", function(player, args)
    local generator, missing = generatorOn(args)
    if not generator then return nil, missing end
    generator:setFuel(generator:getFuel() - args.litres)
    return {}
end)

-- Sets the last pass of the kitted generator at x, y, z `args.hours` ago, as though that time had
-- passed since. Answers what is missing, or nil.
local function age(args)
    local generator, missing = generatorOn(args)
    if not generator then return missing end
    local state = RenewableEnergy.GasKit.stateOf(generator)
    if not state then return "a kit on the generator at " .. args.x .. "," .. args.y end
    state.lastHour = getGameTime():getWorldAgeHours() - args.hours
    return nil
end

-- Runs the gas pass as though `args.hours` had passed since the last of the generator at x, y, z.
handler("gasPass", function(player, args)
    local missing = age(args)
    if missing then return nil, missing end
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

-- Burns `args.kg` in the gasifier at x, y, z, as a pass would, to leave its ash and tar.
handler("gasifierBurn", function(player, args)
    local record, _, missing = Helpers.recordAt({ kind = "gasifier", x = args.x, y = args.y, z = args.z })
    if not record then return nil, missing end
    local burned = record:burn(args.kg)
    record:afterChange()
    return { burned = burned }
end)
