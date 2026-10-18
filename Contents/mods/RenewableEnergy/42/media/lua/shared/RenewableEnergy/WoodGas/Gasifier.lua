-- Wood gas gasifiers, as both sides know them: the three tiers, what burns in them, what packs
-- their filter, which tiles are gasifiers, and the summary every client keeps of each one.
--
-- A gasifier is a tile the build menu places (scripts/RenewableEnergy/Entities.txt) beside a
-- generator carrying the Gas Conversion Kit. Its tile container is the fuel hopper and a second
-- container on the same object is the filter. The authority keeps its state in a Global Object
-- System (server/RenewableEnergy/WoodGas/GasifierSystem.lua) and sends every client its summary.
-- The generator it feeds draws on it through the gas line (server/RenewableEnergy/GasLine).
--
-- Units: fuel in kilograms (an item's weight), time in game hours.

require "RenewableEnergy/Sprites"
require "RenewableEnergy/GlobalObjects"

RenewableEnergy = RenewableEnergy or {}
local Gasifier = {}
RenewableEnergy.Gasifier = Gasifier

local Sprites = RenewableEnergy.Sprites

Gasifier.SYSTEM_NAME = "renewable_energy_gasifier"
Gasifier.CONTAINER = "RenewableEnergyGasifier"
Gasifier.FILTER = "RenewableEnergyGasifierFilter"

-- hopperKg: wood the hopper holds (its tile's ContainerCapacity; a whole log needs the bigger
-- two). filterCapacity: the filter container's capacity, ten tufts of hay to a unit.
-- tarKgPerItem: wood burned for each packing item that turns tarry. ashPerKg: percent of the ash
-- pit each kg fills. Upkeep is set by a home's usual load at the default GeneratorFuelConsumption:
-- a fridge-freezer, the lights, a TV and a radio bill about 0.021 L an hour, 8.5 kg of wood a
-- week. That fills the ash pit about 2.5, 1.7 and 0.85 times a week, and tars a filter about 1.7,
-- 0.85 and 0.4 times.
Gasifier.TIERS = {
    primitive = { hopperKg = 8, filterCapacity = 1, tarKgPerItem = 0.5, ashPerKg = 30 },
    standard = { hopperKg = 20, filterCapacity = 1, tarKgPerItem = 1, ashPerKg = 20 },
    advanced = { hopperKg = 30, filterCapacity = 2, tarKgPerItem = 1, ashPerKg = 10 },
}

-- Wood a generator on wood gas burns for each litre of petrol vanilla bills it: FEMA's 20 lb of
-- wood for a gallon of gasoline.
Gasifier.KG_PER_LITRE = 2.4
-- Charcoal makes this share of wood's tar and ash.
Gasifier.CHARCOAL_TAR = 0.25
Gasifier.CHARCOAL_ASH = 0.5
-- A full ash pit (ASH_FULL percent), or a filter with no clean packing left, cuts what the
-- generator carries to this share; the tar a spent filter lets through wears the generator up to
-- WEAR_DIRTY times as fast.
Gasifier.ASH_FULL = 100
Gasifier.DIRTY_OUTPUT = 0.5
Gasifier.WEAR_DIRTY = 3
-- Out longer than this, a gasifier is cold, and lighting it takes bellows.
Gasifier.COLD_HOURS = 1
Gasifier.BELLOWS = { "Base.Bellows", "Base.LargeBellows" }
-- Clean Out Ash gives one Wood Ash per this much of the pit. Wood Ash also neutralises a digester
-- and charges its scrubber, and a campfire's ashes give it.
Gasifier.ASH_PER_ITEM = 25
Gasifier.WOOD_ASH = "RenewableEnergy.WoodAsh"
Gasifier.TARRY = "RenewableEnergy.TarryPacking"
-- Hay and straw pack the filter, and insulate a digester's upgrade.
Gasifier.HAY = { "Base.HayTuft", "Base.Straw2" }

-- The filter's condensate, wood vinegar: litres per kg burned, what the filter's drain holds (a
-- home's week fills it about 1.7 times), and how much faster tar fills the packing while it is
-- full.
Gasifier.VINEGAR = "RenewableEnergy_WoodVinegar"
Gasifier.CONDENSATE_PER_KG = 0.6
Gasifier.CONDENSATE_MAX = 3
Gasifier.CONDENSATE_TAR = 2

--- Whether `item` can take the condensate now: a fluid container with room whose fluid wood
--- vinegar may join (FluidContainer.canAddFluid). Drained from a lit gasifier it is near boiling
--- and softens plastic, so then only metal, glass or cookware will do.
function Gasifier.takesCondensate(item, lit)
    local fluid = item and item:getFluidContainer()
    if not (fluid and fluid:getFreeCapacity() > 0 and fluid:canAddFluid(Fluid.Get(Gasifier.VINEGAR))) then
        return false
    end
    return not lit or item:hasTag(ItemTag.HAS_METAL) or item:hasTag(ItemTag.GLASS)
        or item:hasTag(ItemTag.GLASS_BOTTLE) or item:hasTag(ItemTag.COOKABLE)
end

-- What packs the filter.
local PACKING = {
    [Gasifier.HAY[1]] = true,
    [Gasifier.HAY[2]] = true,
    ["Base.Splinters"] = true,
    ["Base.GrassTuft"] = true,
}

-- Wood that isn't tagged for the charcoal kiln.
local FUEL_TYPES = {
    ["Base.Log"] = true,
    ["Base.LargeBranch"] = true,
    ["Base.Plank"] = true,
    ["Base.FirewoodBundle"] = true,
    ["Base.Twigs"] = true,
    ["Base.TwigsBundle"] = true,
    ["Base.Splinters"] = true,
    ["Base.Pinecone"] = true,
    [Gasifier.TARRY] = true,
}

function Gasifier.isCharcoal(item)
    return item:hasTag(ItemTag.CHARCOAL)
end

--- The kilograms `item` burns for, or nil if it isn't gasifier fuel: wood (the charcoal kiln's
--- wood list and the rest of FUEL_TYPES), spent filter packing, and charcoal.
function Gasifier.fuelKg(item)
    if FUEL_TYPES[item:getFullType()] or Gasifier.isCharcoal(item)
        or item:hasTag(ItemTag.MAKE_WOOD_CHARCOAL_SMALL) or item:hasTag(ItemTag.MAKE_WOOD_CHARCOAL_MEDIUM)
        or item:hasTag(ItemTag.MAKE_WOOD_CHARCOAL_LARGE) then
        return item:getActualWeight()
    end
    return nil
end

function Gasifier.isPacking(item)
    return PACKING[item:getFullType()] == true
end

-- The containers' AcceptItemFunctions: not saved with them, so every side sets them whenever a
-- gasifier loads or is placed (Gasifier.adoptContainers).
function Gasifier.acceptFuel(container, item)
    return Gasifier.fuelKg(item) ~= nil
end

function Gasifier.acceptPacking(container, item)
    return Gasifier.isPacking(item) or item:getFullType() == Gasifier.TARRY
end

local ACCEPT = {
    [Gasifier.CONTAINER] = "RenewableEnergy.Gasifier.acceptFuel",
    [Gasifier.FILTER] = "RenewableEnergy.Gasifier.acceptPacking",
}

function Gasifier.adoptContainer(container)
    local accept = container and ACCEPT[container:getType()]
    if accept and container:getAcceptItemFunction() == nil then
        container:setAcceptItemFunction(accept)
    end
end

function Gasifier.adoptContainers(isoObject)
    for i = 0, isoObject:getContainerCount() - 1 do
        Gasifier.adoptContainer(isoObject:getContainerByIndex(i))
    end
end

function Gasifier.hopperOf(isoObject)
    return isoObject:getContainerByType(Gasifier.CONTAINER)
end

function Gasifier.filterOf(isoObject)
    return isoObject:getContainerByType(Gasifier.FILTER)
end

--- The filter's clean and tarry packing counts.
function Gasifier.filterCounts(container)
    local clean, tarry = 0, 0
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        local item = items:get(i)
        if item:getFullType() == Gasifier.TARRY then
            tarry = tarry + 1
        elseif Gasifier.isPacking(item) then
            clean = clean + 1
        end
    end
    return clean, tarry
end

--- Kilograms of fuel in the hopper.
function Gasifier.hopperKg(container)
    local kg = 0
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        kg = kg + (Gasifier.fuelKg(items:get(i)) or 0)
    end
    return kg
end

--- What it carries, as a share of what a generator carries on gas, with `ash` percent in its pit
--- and `clean` packing left in its filter: a full pit or a spent filter halves it.
function Gasifier.outputShare(ash, clean)
    local share = 1
    if ash >= Gasifier.ASH_FULL then
        share = share * Gasifier.DIRTY_OUTPUT
    end
    if clean == 0 then
        share = share * Gasifier.DIRTY_OUTPUT
    end
    return share
end

--- How much faster the generator wears on its gas: with the tar the filter lets through.
function Gasifier.wearFactor(clean, tarry)
    if clean == 0 then
        return Gasifier.WEAR_DIRTY
    end
    return 1 + (Gasifier.WEAR_DIRTY - 1) * tarry / (clean + tarry)
end

--- Whether lighting it takes bellows: out long enough to have gone cold (since the world hour
--- `outSince`), or never lit.
function Gasifier.isCold(lit, outSince)
    return not lit and (outSince == nil or getGameTime():getWorldAgeHours() - outSince > Gasifier.COLD_HOURS)
end

-- Tiles --------------------------------------------------------------------------------------

--- The tier of a gasifier tile, or nil for any other object.
function Gasifier.tierOf(isoObject)
    local kind, tier = Sprites.kindOf(Sprites.nameOf(isoObject))
    return kind == "gasifier" and tier or nil
end

function Gasifier.isGasifier(isoObject)
    return isoObject ~= nil and Gasifier.tierOf(isoObject) ~= nil
end

Gasifier.isLitOverlay = Sprites.matcher(Sprites.gasifierLit)
Gasifier.isPipeOverlay = Sprites.matcher(Sprites.gasifierPipe)

--- The side of (x, y) that (tx, ty), a square next to it, is on: "N", "E", "S" or "W", or nil if
--- it isn't one of the four beside it.
function Gasifier.sideOf(x, y, tx, ty)
    if tx == x and ty == y - 1 then return "N" end
    if tx == x + 1 and ty == y then return "E" end
    if tx == x and ty == y + 1 then return "S" end
    if tx == x - 1 and ty == y then return "W" end
    return nil
end

-- Summary --------------------------------------------------------------------------------------

-- The summary (GasifierObject:buildSummary) gets what follows from this side's copies of the
-- containers and the clock: `hopperKg` (the hopper and the firebox), the filter's `clean` and
-- `tarry` packing, the `output` share and `wear` factor they make, and whether it is `cold`.
RenewableEnergy.GlobalObjects.addAccessors(Gasifier, function(summary, isoObject)
    local clean, tarry = Gasifier.filterCounts(Gasifier.filterOf(isoObject))
    summary.hopperKg = Gasifier.hopperKg(Gasifier.hopperOf(isoObject)) + summary.fireKg
    summary.clean, summary.tarry = clean, tarry
    summary.output = Gasifier.outputShare(summary.ash, clean)
    summary.wear = Gasifier.wearFactor(clean, tarry)
    summary.cold = Gasifier.isCold(summary.lit, summary.outSince)
end)

return Gasifier
