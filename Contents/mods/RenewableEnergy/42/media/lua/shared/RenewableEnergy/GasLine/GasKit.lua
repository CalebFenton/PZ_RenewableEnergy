-- The Gas Conversion Kit, as both sides know it: which generators carry one, the gas line from a
-- digester or gasifier (its source) that feeds it, and what each job at the generator takes. The
-- authority does the jobs and runs the line (GasLines).
--
-- A generator's kit and line live in its modData (GasKit.MOD_DATA), which the authority sends to
-- the clients. On gas the generator runs on vanilla's own update on fuel the gas pays for: its tank
-- (`tank`) stays what it was, and an empty one shows a little fuel so the game lets it run (`set`,
-- what the authority last put in).

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/GasJobs"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/PowerBank/PowerBank"

RenewableEnergy = RenewableEnergy or {}
local GasKit = {}
RenewableEnergy.GasKit = GasKit

local Digester, Gasifier, PowerBank = RenewableEnergy.Digester, RenewableEnergy.Gasifier, RenewableEnergy.PowerBank
local Sprites = RenewableEnergy.Sprites

GasKit.MOD_DATA = "RenewableEnergy_gas"
GasKit.ITEM = "RenewableEnergy.GasConversionKit"
GasKit.HOSE = "Base.RubberHose"
-- A gasifier's gas leaves it hot, so its line is a metal pipe, and it stands beside the generator.
GasKit.PIPE = "Base.MetalPipe"

-- A digester feeds a generator this far away at most, in squares, with a rubber hose for each
-- HOSE_SQUARES of the way (or part of it).
GasKit.REACH = 20
GasKit.HOSE_SQUARES = 5

-- Litres an empty-tanked generator on gas shows, so vanilla starts it and bills it from them. A bill
-- that takes them all (a long absence, a high GeneratorFuelConsumption) stops it; the next pass
-- bills those hours to the gas and starts it again (GasLines.run).
GasKit.PHANTOM_FUEL = 2
-- A generator carries this many watts on gas, against what vanilla bills (Specs.wattsPerFuel).
-- Sized so clean gas carries a whole house with a bank charging off the generator, while a
-- gasifier's dirty output (Gasifier.outputShare) forces trade-offs.
GasKit.CAP_W = 3000
-- Biogas a generator burns for each litre of petrol vanilla bills it, by energy: petrol about
-- 9.5 kWh a litre, biogas about 6 kWh a m³.
GasKit.M3_PER_LITRE = 1.6
-- Litres an hour vanilla bills an idling generator before the GeneratorFuelConsumption option
-- (IsoGenerator's GeneratorBasePowerConsumption; only a generator's getBasePowerConsumption gives
-- it). A fire kept going with no generator to feed, a lit gasifier's or a gas heater's, burns it.
GasKit.IDLE_FUEL = 0.02

--- Litres of petrol vanilla bills an idling generator an hour.
function GasKit.idleLitresPerHour()
    return GasKit.IDLE_FUEL * SandboxVars.GeneratorFuelConsumption
end

--- Whether `object` is a vanilla generator: a placed IsoGenerator that isn't one of the mod's
--- battery banks.
function GasKit.isGenerator(object)
    return object ~= nil and instanceof(object, "IsoGenerator") and not PowerBank.isBank(object)
end

--- The generator's gas state, or nil without a kit: { kit, source = { x, y, z, kind } or nil,
--- line = { item, count } (what the line took) or nil, mode = "gas" or "petrol", tank, set, onGas,
--- watts, stalled, outOfGas, and while it runs on gas billedHour and billLitres, vanilla's last bill
--- as the gas line sees it (GasLines.run) }.
function GasKit.stateOf(generator)
    local state = GasKit.isGenerator(generator) and generator:getModData()[GasKit.MOD_DATA]
    return state and state.kit and state or nil
end

function GasKit.hasKit(generator)
    return GasKit.stateOf(generator) ~= nil
end

--- Rubber hoses a line from `generator` to `digester` takes.
function GasKit.hosesFor(generator, digester)
    local distance = IsoUtils.DistanceTo(generator:getX(), generator:getY(), digester:getX(), digester:getY())
    return math.max(1, math.ceil(distance / GasKit.HOSE_SQUARES))
end

-- The sources a line runs from, by their tiles' kind (Sprites.kindOf), which the line keeps as its
-- source's `kind`:
-- - owner: the source's shared module, whose recordAt gives the authority its record.
-- - nameKey, tierOf(object): its name in the menu, the key's ending its tier.
-- - inReach(generator, source): whether it may feed `generator`, else the key `tooFar` says why.
-- - line(generator, source): what the line takes (a RenewableEnergy.Materials item).
-- - piped: the line is a pipe drawn on both ends.
GasKit.SOURCES = {
    digester = {
        owner = Digester, nameKey = "IGUI_RenewableEnergy_Digester_", tierOf = Digester.tileOf,
        inReach = function(generator, source)
            return IsoUtils.DistanceTo(generator:getX(), generator:getY(), source:getX(), source:getY()) <= GasKit.REACH
        end,
        tooFar = "Tooltip_RenewableEnergy_DigesterOutOfReach",
        line = function(generator, source)
            return { item = GasKit.HOSE, need = GasKit.hosesFor(generator, source) }
        end,
    },
    gasifier = {
        owner = Gasifier, nameKey = "IGUI_RenewableEnergy_Gasifier_", tierOf = Gasifier.tierOf,
        inReach = function(generator, source)
            return Gasifier.sideOf(generator:getX(), generator:getY(), source:getX(), source:getY()) ~= nil
        end,
        tooFar = "Tooltip_RenewableEnergy_GasifierNotBeside",
        line = function()
            return { item = GasKit.PIPE, need = 1 }
        end,
        piped = true,
    },
}

--- The kind of gas source `object`'s tile is (a key of SOURCES), else nil.
function GasKit.sourceKind(object)
    local kind = Sprites.kindOf(Sprites.nameOf(object))
    return kind and GasKit.SOURCES[kind] and kind or nil
end

-- What keeps `source` from feeding `generator`, as a translation key, or nil: on the generator's
-- level and in its reach.
local function sourceBlocker(generator, source)
    local kind = GasKit.sourceKind(source)
    if not kind then
        return "Tooltip_RenewableEnergy_DigesterOutOfReach"
    end
    local spec = GasKit.SOURCES[kind]
    if not RenewableEnergy.onSquare(source) or source:getZ() ~= generator:getZ()
            or not spec.inReach(generator, source) then
        return spec.tooFar
    end
    return nil
end

--- The sources that may feed `generator`, nearest first.
function GasKit.sourcesNear(generator)
    local found = {}
    local gx, gy, z = generator:getX(), generator:getY(), generator:getZ()
    for x = gx - GasKit.REACH, gx + GasKit.REACH do
        for y = gy - GasKit.REACH, gy + GasKit.REACH do
            local source = RenewableEnergy.findObjectOn(getSquare(x, y, z), GasKit.sourceKind)
            if source and not sourceBlocker(generator, source) then
                table.insert(found, source)
            end
        end
    end
    table.sort(found, function(a, b)
        return IsoUtils.DistanceTo(gx, gy, a:getX(), a:getY()) < IsoUtils.DistanceTo(gx, gy, b:getX(), b:getY())
    end)
    return found
end

-- Jobs at a generator.
GasKit.INSTALL = "InstallKit"
GasKit.REMOVE = "RemoveKit"
GasKit.CONNECT = "ConnectLine"
GasKit.DISCONNECT = "DisconnectLine"
GasKit.TO_GAS = "RunOnGas"
GasKit.TO_PETROL = "RunOnPetrol"

local WRENCH = { tool = "WRENCH", item = "Base.Wrench" }
-- The kit's fitting is spanner work at the engine, which needs light to see the fittings by; a
-- switch-over is a turn of the valve.
local SPANNER_ANIM, SPANNER_SOUND = "VehicleWorkOnMid", "GeneratorRepair"

-- A blocker of a job on the kit: none fitted refuses it, else `blocker(state, generator, source)`.
local function withKit(blocker)
    return function(generator, source)
        local state = GasKit.stateOf(generator)
        if not state then
            return "Tooltip_RenewableEnergy_NoKit"
        end
        return blocker(state, generator, source)
    end
end

-- The job that switches the generator to `mode`, which `already` refuses it in.
local function switchTo(mode, already)
    return {
        minutes = 1, mode = mode, hideBlocked = true,
        blocker = withKit(function(state)
            return state.mode == mode and already or nil
        end),
    }
end

-- Every job, by name, as GasJobs.define has them, read against the generator itself; `source` is
-- Connect Gas Line's other end, nil for the other jobs. minutes; blocker(generator, source);
-- materials, or a function(generator, source) of them; xp; light; how it looks. `mode`: the fuel
-- the job switches to.
GasKit.JOBS = {
    [GasKit.INSTALL] = {
        minutes = 30, anim = SPANNER_ANIM, sound = SPANNER_SOUND, light = true,
        blocker = function(generator)
            return GasKit.hasKit(generator) and "Tooltip_RenewableEnergy_HasKit" or nil
        end,
        materials = { { perk = "Mechanics", need = 2 }, WRENCH, { item = GasKit.ITEM, need = 1 } },
        xp = { perk = "Mechanics", amount = 15 },
    },
    [GasKit.REMOVE] = {
        minutes = 15, anim = SPANNER_ANIM, sound = SPANNER_SOUND, light = true,
        blocker = withKit(function(state, generator)
            return generator:isActivated() and "Tooltip_RenewableEnergy_GeneratorRunning" or nil
        end),
        materials = { WRENCH },
    },
    -- To the source `source`: a digester within REACH on its level, or a gasifier beside it.
    [GasKit.CONNECT] = {
        minutes = 20, anim = SPANNER_ANIM, sound = SPANNER_SOUND, light = true,
        blocker = withKit(function(state, generator, source)
            if state.source then
                return "Tooltip_RenewableEnergy_HasLine"
            end
            return sourceBlocker(generator, source)
        end),
        materials = function(generator, source)
            local kind = GasKit.sourceKind(source)
            if not kind then
                return { WRENCH }
            end
            return { WRENCH, GasKit.SOURCES[kind].line(generator, source) }
        end,
        xp = { perk = "Mechanics", amount = 5 },
    },
    [GasKit.DISCONNECT] = {
        minutes = 5, anim = SPANNER_ANIM, sound = SPANNER_SOUND, light = true,
        blocker = withKit(function(state)
            return not state.source and "Tooltip_RenewableEnergy_NoLine" or nil
        end),
    },
    [GasKit.TO_GAS] = switchTo("gas", "Tooltip_RenewableEnergy_OnGasAlready"),
    [GasKit.TO_PETROL] = switchTo("petrol", "Tooltip_RenewableEnergy_OnPetrolAlready"),
}

RenewableEnergy.GasJobs.define(GasKit, {
    subjectOf = function(generator)
        return GasKit.isGenerator(generator) and RenewableEnergy.onSquare(generator) and generator or nil
    end,
    missing = "Tooltip_RenewableEnergy_NoGenerator",
})

return GasKit
