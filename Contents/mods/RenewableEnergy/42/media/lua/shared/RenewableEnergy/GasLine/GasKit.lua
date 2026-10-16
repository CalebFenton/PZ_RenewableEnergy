-- The Gas Conversion Kit, as both sides know it: which generators carry one, the gas line from a
-- digester or gasifier (its source) that feeds it, and what each job at the generator takes. The
-- authority does the jobs (server/RenewableEnergy/GasLine/GasLines.lua).
--
-- A generator's kit and line live in its modData (GasKit.MOD_DATA), which the authority sends to
-- the clients. While gas reaches it (server/RenewableEnergy/GasLine/GasLines.lua) the generator
-- runs on vanilla's own update, with its sound, zombie noise, fumes and wear, on fuel the gas pays
-- for: its tank (`tank`) stays what it was, and an empty one shows a little fuel so the game lets
-- it run (`set`, what the authority last put in).

require "RenewableEnergy/Utilities"
require "RenewableEnergy/Sprites"
require "RenewableEnergy/Materials"
require "RenewableEnergy/Biogas/Digester"
require "RenewableEnergy/WoodGas/Gasifier"
require "RenewableEnergy/PowerBank/PowerBank"

RenewableEnergy = RenewableEnergy or {}
local GasKit = {}
RenewableEnergy.GasKit = GasKit

local Digester, Gasifier, PowerBank = RenewableEnergy.Digester, RenewableEnergy.Gasifier, RenewableEnergy.PowerBank
local Sprites, Materials = RenewableEnergy.Sprites, RenewableEnergy.Materials

GasKit.MOD_DATA = "RenewableEnergy_gas"
GasKit.ITEM = "RenewableEnergy.GasConversionKit"
GasKit.HOSE = "Base.RubberHose"
-- A gasifier's gas leaves it hot, so its line is a metal pipe, and it stands beside the generator.
GasKit.PIPE = "Base.MetalPipe"

-- A digester feeds a generator this far away at most, in squares, with a rubber hose for each
-- HOSE_SQUARES of the way (or part of it).
GasKit.REACH = 20
GasKit.HOSE_SQUARES = 5

-- Litres an empty-tanked generator on gas shows, enough for vanilla to keep it running between
-- passes, after a long absence too.
GasKit.PHANTOM_FUEL = 2
-- A generator carries this many watts on gas, about 60 % of a 1990s 5 kW portable: an engine
-- loses a third or more of its power on gas.
GasKit.CAP_W = 3000
-- Gas an engine burns, m³ an hour, idling and per kilowatt it delivers: small gensets on biogas.
GasKit.IDLE_M3_PER_HOUR = 0.3
GasKit.M3_PER_KWH = 0.8

--- Gas a generator delivering `watts` burns over `hours`, in m³.
function GasKit.gasFor(watts, hours)
    return (GasKit.IDLE_M3_PER_HOUR + GasKit.M3_PER_KWH * watts / 1000) * hours
end

-- Jobs at a generator.
GasKit.INSTALL = "InstallKit"
GasKit.REMOVE = "RemoveKit"
GasKit.CONNECT = "ConnectLine"
GasKit.DISCONNECT = "DisconnectLine"
GasKit.TO_GAS = "RunOnGas"
GasKit.TO_PETROL = "RunOnPetrol"

GasKit.MINUTES = {
    [GasKit.INSTALL] = 30,
    [GasKit.REMOVE] = 15,
    [GasKit.CONNECT] = 20,
    [GasKit.DISCONNECT] = 5,
    [GasKit.TO_GAS] = 1,
    [GasKit.TO_PETROL] = 1,
}

-- How each job looks (RenewableEnergyGasAction): the switch-overs are a turn of the valve, the
-- rest spanner work.
local SPANNER = { anim = "VehicleWorkOnMid", sound = "GeneratorRepair" }
GasKit.LOOK = {
    [GasKit.INSTALL] = SPANNER,
    [GasKit.REMOVE] = SPANNER,
    [GasKit.CONNECT] = SPANNER,
    [GasKit.DISCONNECT] = SPANNER,
}

-- The modules of the sources a line runs from, by their tiles' kind (Sprites.kindOf), which the
-- line keeps as its source's `kind`.
GasKit.SOURCES = { digester = Digester, gasifier = Gasifier }

--- Whether `object` is a vanilla generator: a placed IsoGenerator that isn't one of the mod's
--- battery banks.
function GasKit.isGenerator(object)
    return object ~= nil and instanceof(object, "IsoGenerator") and not PowerBank.isBank(object)
end

GasKit.isTarget = GasKit.isGenerator

--- The generator's gas state, or nil without a kit: { kit, source = { x, y, z, kind } or nil,
--- hoses, mode = "gas" or "petrol", tank, set, onGas, watts, stalled, outOfGas }.
function GasKit.stateOf(generator)
    local state = GasKit.isGenerator(generator) and generator:getModData()[GasKit.MOD_DATA]
    return state and state.kit and state or nil
end

function GasKit.hasKit(generator)
    return GasKit.stateOf(generator) ~= nil
end

--- "digester" or "gasifier" for a gas source's tile, else nil.
function GasKit.sourceKind(object)
    local kind = Sprites.kindOf(Sprites.nameOf(object))
    return kind and GasKit.SOURCES[kind] and kind or nil
end

--- The gasifiers on the four squares beside `generator`.
function GasKit.gasifiersBeside(generator)
    local found = {}
    local gx, gy, z = generator:getX(), generator:getY(), generator:getZ()
    for _, offset in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
        local square = getSquare(gx + offset[1], gy + offset[2], z)
        local gasifier = square and RenewableEnergy.findObjectOn(square, Gasifier.isGasifier)
        if gasifier then
            table.insert(found, gasifier)
        end
    end
    return found
end

--- Rubber hoses a line from `generator` to `digester` takes.
function GasKit.hosesFor(generator, digester)
    local distance = IsoUtils.DistanceTo(generator:getX(), generator:getY(), digester:getX(), digester:getY())
    return math.max(1, math.ceil(distance / GasKit.HOSE_SQUARES))
end

--- The digesters within reach of `generator` on its level, nearest first.
function GasKit.digestersInReach(generator)
    local found = {}
    local gx, gy, z = generator:getX(), generator:getY(), generator:getZ()
    for x = gx - GasKit.REACH, gx + GasKit.REACH do
        for y = gy - GasKit.REACH, gy + GasKit.REACH do
            local square = getSquare(x, y, z)
            local digester = square and RenewableEnergy.findObjectOn(square, Digester.isDigester)
            if digester and IsoUtils.DistanceTo(gx, gy, x, y) <= GasKit.REACH then
                table.insert(found, digester)
            end
        end
    end
    table.sort(found, function(a, b)
        return IsoUtils.DistanceTo(gx, gy, a:getX(), a:getY()) < IsoUtils.DistanceTo(gx, gy, b:getX(), b:getY())
    end)
    return found
end

local WRENCH = { tool = "WRENCH", item = "Base.Wrench" }

--- What `job` takes (RenewableEnergy.Materials). `source` is the line's other end for Connect
--- Gas Line: a gasifier's line is a pipe, a digester's a hose for every HOSE_SQUARES.
function GasKit.materials(job, generator, source)
    if job == GasKit.INSTALL then
        return { { perk = "Mechanics", need = 2 }, WRENCH, { item = GasKit.ITEM, need = 1 } }
    elseif job == GasKit.REMOVE then
        return { WRENCH }
    elseif job == GasKit.CONNECT then
        if GasKit.sourceKind(source) == "gasifier" then
            return { WRENCH, { item = GasKit.PIPE, need = 1 } }
        end
        return { WRENCH, { item = GasKit.HOSE, need = source and GasKit.hosesFor(generator, source) or 1 } }
    end
    return {}
end

--- What `job` takes of `character` (RenewableEnergy.firstUnmet, RenewableEnergy.Needs).
function GasKit.needs(character, job, generator, source)
    return Materials.needs(character, GasKit.materials(job, generator, source))
end

function GasKit.minutesFor(job)
    return GasKit.MINUTES[job]
end

-- What keeps `source` from feeding `generator`, as a translation key, or nil: a digester within
-- REACH on its level, or a gasifier on a square beside it.
local function sourceBlocker(generator, source)
    local kind = GasKit.sourceKind(source)
    if not kind or not RenewableEnergy.onSquare(source) or source:getZ() ~= generator:getZ() then
        return "Tooltip_RenewableEnergy_DigesterOutOfReach"
    end
    if kind == "gasifier" then
        if not Gasifier.sideOf(generator:getX(), generator:getY(), source:getX(), source:getY()) then
            return "Tooltip_RenewableEnergy_GasifierNotBeside"
        end
    elseif IsoUtils.DistanceTo(generator:getX(), generator:getY(), source:getX(), source:getY()) > GasKit.REACH then
        return "Tooltip_RenewableEnergy_DigesterOutOfReach"
    end
    return nil
end

--- The state of the generator (or the line's source) that refuses `job`, as a translation key,
--- or nil.
function GasKit.blocker(job, generator, source)
    if not (GasKit.isGenerator(generator) and RenewableEnergy.onSquare(generator)) then
        return "Tooltip_RenewableEnergy_NoGenerator"
    end
    local state = GasKit.stateOf(generator)
    if job == GasKit.INSTALL then
        return state and "Tooltip_RenewableEnergy_HasKit" or nil
    end
    if not state then
        return "Tooltip_RenewableEnergy_NoKit"
    end
    if job == GasKit.REMOVE then
        return generator:isActivated() and "Tooltip_RenewableEnergy_GeneratorRunning" or nil
    elseif job == GasKit.CONNECT then
        if state.source then
            return "Tooltip_RenewableEnergy_HasLine"
        end
        return sourceBlocker(generator, source)
    elseif job == GasKit.DISCONNECT then
        return not state.source and "Tooltip_RenewableEnergy_NoLine" or nil
    elseif job == GasKit.TO_GAS then
        return state.mode ~= "petrol" and "Tooltip_RenewableEnergy_OnGasAlready" or nil
    elseif job == GasKit.TO_PETROL then
        return state.mode == "petrol" and "Tooltip_RenewableEnergy_OnPetrolAlready" or nil
    end
    return nil
end

--- What refuses `character` doing `job`: a blocker key, "short" when they lack a need, or nil.
--- No kit job takes an inventory item of its own, so the slot every gas job has for one (the
--- fourth) is unused; `source` is Connect Gas Line's.
function GasKit.refusal(character, job, generator, _, source)
    if not GasKit.MINUTES[job] then
        return "Tooltip_RenewableEnergy_NoGenerator"
    end
    return GasKit.blocker(job, generator, source)
        or (RenewableEnergy.firstUnmet(GasKit.needs(character, job, generator, source)) and "short")
        or nil
end

return GasKit
