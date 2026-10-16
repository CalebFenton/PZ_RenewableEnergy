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
-- pit each kg fills. A full filter lasts about 25, 65 and 130 kg, 15, 40 and 80 hours of running.
Gasifier.TIERS = {
    primitive = { hopperKg = 8, filterCapacity = 1, tarKgPerItem = 2.5, ashPerKg = 5 },
    standard = { hopperKg = 20, filterCapacity = 1, tarKgPerItem = 6.5, ashPerKg = 2.5 },
    advanced = { hopperKg = 30, filterCapacity = 2, tarKgPerItem = 6.5, ashPerKg = 1.25 },
}

-- Wood a lit gasifier burns an hour idling, and per kWh the generator delivers on it: about 5 lb
-- an hour at the load cap, FEMA's 20 lb of wood for a gallon of gasoline.
Gasifier.IDLE_KG_PER_HOUR = 0.8
Gasifier.KG_PER_KWH = 0.6
-- Charcoal makes this share of wood's tar and ash.
Gasifier.CHARCOAL_TAR = 0.25
Gasifier.CHARCOAL_ASH = 0.5
-- A full ash pit, or a filter with no clean packing left, cuts what the generator carries to this
-- share; the tar a spent filter lets through wears the generator up to WEAR_DIRTY times as fast.
Gasifier.DIRTY_OUTPUT = 0.5
Gasifier.WEAR_DIRTY = 3
-- Out longer than this, a gasifier is cold, and lighting it takes bellows.
Gasifier.COLD_HOURS = 1
Gasifier.BELLOWS = { "Base.Bellows", "Base.LargeBellows" }
-- Clean Out Ash gives one Wood Ash per this much of the pit.
Gasifier.ASH_PER_ITEM = 25
Gasifier.WOOD_ASH = "RenewableEnergy.WoodAsh"
Gasifier.TARRY = "RenewableEnergy.TarryPacking"

-- The filter's condensate, wood vinegar: litres per kg burned, what the filter's drain holds, and
-- how much faster tar fills the packing while it is full. About a litre and a half a day's running.
Gasifier.VINEGAR = "RenewableEnergy_WoodVinegar"
Gasifier.CONDENSATE_PER_KG = 0.05
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
    ["Base.HayTuft"] = true,
    ["Base.Straw2"] = true,
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

-- Tiles --------------------------------------------------------------------------------------

-- Base tile name -> tier.
local TILES = {}
for tier, name in pairs(Sprites.gasifier) do
    TILES[name] = tier
end

local LIT_OVERLAYS, PIPE_OVERLAYS = {}, {}
for _, name in pairs(Sprites.gasifierLit) do
    LIT_OVERLAYS[name] = true
end
for _, name in pairs(Sprites.gasifierPipe) do
    PIPE_OVERLAYS[name] = true
end

function Gasifier.tierOf(isoObject)
    local name = Sprites.nameOf(isoObject)
    return name and TILES[name]
end

function Gasifier.isGasifier(isoObject)
    return isoObject ~= nil and Gasifier.tierOf(isoObject) ~= nil
end

function Gasifier.isLitOverlay(spriteName)
    return LIT_OVERLAYS[spriteName] == true
end

function Gasifier.isPipeOverlay(spriteName)
    return PIPE_OVERLAYS[spriteName] == true
end

--- Every gasifier base tile, for MapObjects.OnLoadWithSprite.
function Gasifier.sprites()
    local names = {}
    for name in pairs(TILES) do
        table.insert(names, name)
    end
    return names
end

--- The side of (x, y) that (tx, ty), a square next to it, is on: "N", "E", "S" or "W", or nil if
--- it isn't one of the four beside it.
function Gasifier.sideOf(x, y, tx, ty)
    if tx == x and ty == y - 1 then return "N" end
    if tx == x + 1 and ty == y then return "E" end
    if tx == x and ty == y + 1 then return "S" end
    if tx == x - 1 and ty == y then return "W" end
    return nil
end

-- State ----------------------------------------------------------------------------------------

--- What every client keeps of the gasifier at x, y, z (GasifierObject:buildSummary), or nil.
function Gasifier.getSummary(x, y, z)
    local system = Gasifier.clientSystem
    local globalObject = system and system.system:getObjectAt(x, y, z)
    return globalObject and globalObject:getModData().summary
end

function Gasifier.summaryOf(isoObject)
    return Gasifier.getSummary(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- The gasifier's record on the authority (single player or the server), or nil elsewhere.
function Gasifier.recordOf(isoObject)
    local system = not isClient() and Gasifier.serverSystem
    return system and system:getLuaObjectAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- The gasifier's summary as this side knows it, or nil: the authority builds it from its record,
--- which a job may have changed since the last summary went out, and has no client copy.
function Gasifier.currentSummary(isoObject)
    local record = Gasifier.recordOf(isoObject)
    return record and record:buildSummary() or Gasifier.summaryOf(isoObject)
end

return Gasifier
