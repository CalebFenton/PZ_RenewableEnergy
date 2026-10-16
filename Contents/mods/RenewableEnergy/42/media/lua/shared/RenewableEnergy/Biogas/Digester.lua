-- Biogas digesters, as both sides know them: the three tiers and their gas holders, what each
-- feed is worth, which tiles are digesters, and the summary every client keeps of each one.
--
-- A digester is a tile the build menu places (scripts/RenewableEnergy/Entities.txt) with a
-- container that is its feed hopper. The authority keeps its state in a Global Object System
-- (server/RenewableEnergy/Biogas/DigesterSystem.lua), which runs it while its chunk is unloaded and
-- sends every client its summary.
--
-- Units: gas and the feed's potential in cubic metres of biogas, temperatures in degrees Celsius,
-- time in game hours.

require "RenewableEnergy/Sprites"

RenewableEnergy = RenewableEnergy or {}
local Digester = {}
RenewableEnergy.Digester = Digester

local Sprites = RenewableEnergy.Sprites

Digester.SYSTEM_NAME = "renewable_energy_digester"
Digester.CONTAINER = "RenewableEnergyDigester"

-- potentialCap: undigested potential it holds; feed waits in the hopper above it.
-- days: how many days its temperature takes to follow the air (a time constant).
-- stink: its share of the stink score; the Brick Dome stays below the second smell level whatever
-- state it is in (stinkCap).
-- warmTo, heatShare: the dome is buried and burns a share of its gas to keep at least this warm.
Digester.TIERS = {
    barrel = { potentialCap = 5, days = 1, stink = 1.0 },
    insulated = { potentialCap = 15, days = 3, stink = 0.6 },
    dome = { potentialCap = 45, days = 8, stink = 0.3, stinkCap = 0.99, warmTo = 20, heatShare = 0.25 },
}

-- capacity: gas the holder stores. wearPerDay: condition lost a day; a holder at none is torn,
-- holds nothing and leaks. The drum and the dome don't wear.
Digester.HOLDERS = {
    bags = { capacity = 0.6, wearPerDay = 1 },
    tarp = { capacity = 1.0, wearPerDay = 0.25 },
    drum = { capacity = 1.5 },
    dome = { capacity = 4.0 },
}
Digester.HOLDER_OF_TIER = { insulated = "drum", dome = "dome" }

-- Sludge, in percent of the tank, that one compost bag holds, as vanilla's composter
-- (ISGetCompost).
Digester.SLUDGE_PER_BAG = 10

-- Propane tanks. A tank holds this much biogas when full: its propane's energy at 6 kWh a m³. Real
-- biogas can't be pressed into a tank anywhere near that; the game lets it.
Digester.TANK = "Base.PropaneTank"
Digester.M3_PER_TANK = 40
-- A tire pump fills a tank this far at most, and it is hard work: minutes and endurance per m³.
Digester.PUMP = "Base.TirePump"
Digester.PUMP_FILL = 0.25
Digester.PUMP_MINUTES_PER_M3 = 15
Digester.PUMP_ENDURANCE_PER_M3 = 0.06
-- A fridge compressor, on power, fills a tank all the way, but only with scrubbed gas.
Digester.COMPRESSOR = "RenewableEnergy.FridgeCompressor"
Digester.COMPRESSOR_MINUTES_PER_M3 = 2
-- What the scrubber's water takes out before it is spent, in m³ of gas: plain water, lye from
-- wood ash, or lime; and what one use of steel wool takes the rotten-egg gas out of.
Digester.SCRUB_M3 = { water = 5, ash = 15, lime = 30 }
Digester.WOOL_M3 = 10
-- Litres of water a scrubber charge takes.
Digester.SCRUB_WATER = 4

-- Feed ---------------------------------------------------------------------------------------

-- By full type: potential (m³ before the Biogas multiplier), acid (what it adds to souring;
-- below zero neutralises), seedHours (startup it saves: manure brings the bacteria).
-- Manure stands for an animal's day of it, since the game drops about one item every other day.
local FEEDS = {
    ["Base.Dung_Cow"] = { potential = 1.0, acid = -1.5, seedHours = 24 },
    ["Base.Dung_Pig"] = { potential = 0.3, acid = -1.0, seedHours = 12 },
    ["Base.Dung_Sheep"] = { potential = 0.1, acid = -0.3 },
    ["Base.Dung_Deer"] = { potential = 0.1, acid = -0.3 },
    ["Base.Dung_Chicken"] = { potential = 0.02, acid = -0.05 },
    ["Base.Dung_Turkey"] = { potential = 0.02, acid = -0.05 },
    ["Base.GrassTuft"] = { potential = 0.01, acid = 0.02 },
    ["Base.HayTuft"] = { potential = 0.005, acid = 0 },
}
-- Alkalis that fix a sour digester: acid taken off per item, or per use of a drainable.
local NEUTRALISERS = {
    ["RenewableEnergy.WoodAsh"] = -3,
    ["Base.BakingSoda"] = -3,
    ["Base.Quicklime"] = -6,
}
-- Food by the kilogram: meat is richer and sours twice as fast.
local FOOD_POTENTIAL_PER_KG, FOOD_ACID_PER_KG = 0.12, 1
local MEAT_POTENTIAL_PER_KG, MEAT_ACID_PER_KG = 0.2, 2
local MEAT_TYPES = { Meat = true, Game = true, Beef = true, Poultry = true, Sausage = true, Fish = true, Seafood = true, Roe = true }
-- Dung of the other animals (mice, rats) is worth a little.
local OTHER_DUNG = { potential = 0.01, acid = 0 }

local function isNeutraliser(item)
    return NEUTRALISERS[item:getFullType()] ~= nil
end

--- What one hourly meter takes of `item` into the digester: { potential, acid, seedHours,
--- whole }, where whole is false for a drainable neutraliser, of which one use goes in at a time.
--- Nil when the digester doesn't take it: the composter's food (rotten, or tagged compostable)
--- and the neutralisers.
function Digester.feedOf(item)
    local fullType = item:getFullType()
    local neutraliser = NEUTRALISERS[fullType]
    if neutraliser then
        return { potential = 0, acid = neutraliser, whole = not instanceof(item, "DrainableComboItem") }
    end
    local known = FEEDS[fullType]
    if known then
        return { potential = known.potential, acid = known.acid, seedHours = known.seedHours, whole = true }
    end
    if not instanceof(item, "Food") then
        return nil
    end
    if fullType:find("^Base%.Dung_") then
        return { potential = OTHER_DUNG.potential, acid = OTHER_DUNG.acid, whole = true }
    end
    if not (item:isRotten() or item:hasTag(ItemTag.IS_COMPOSTABLE)) then
        return nil
    end
    local kg = item:getActualWeight()
    if MEAT_TYPES[item:getFoodType()] then
        return { potential = MEAT_POTENTIAL_PER_KG * kg, acid = MEAT_ACID_PER_KG * kg, whole = true }
    end
    return { potential = FOOD_POTENTIAL_PER_KG * kg, acid = FOOD_ACID_PER_KG * kg, whole = true }
end

--- The hopper's AcceptItemFunction: feed and neutralisers only. Not saved with the container,
--- so every side sets it whenever a digester loads or is placed (Digester.adoptContainer).
function Digester.acceptItem(container, item)
    return Digester.feedOf(item) ~= nil
end

function Digester.adoptContainer(container)
    if container and container:getAcceptItemFunction() == nil then
        container:setAcceptItemFunction("RenewableEnergy.Digester.acceptItem")
    end
end

Digester.isNeutraliser = isNeutraliser

-- Tiles --------------------------------------------------------------------------------------

-- Base tile name -> { tier, material }.
local TILES = {
    [Sprites.digester.barrel.steel] = { tier = "barrel", material = "steel" },
    [Sprites.digester.barrel.plastic] = { tier = "barrel", material = "plastic" },
    [Sprites.digester.insulated] = { tier = "insulated" },
    [Sprites.digester.dome] = { tier = "dome" },
}

local HOLDER_OVERLAYS = {}
for _, list in pairs({ Sprites.digesterHolder.bags, Sprites.digesterHolder.tarp, Sprites.digesterHolder.drum }) do
    for _, name in ipairs(list) do
        HOLDER_OVERLAYS[name] = true
    end
end
HOLDER_OVERLAYS[Sprites.digesterHolder.bagsTorn] = true
HOLDER_OVERLAYS[Sprites.digesterHolder.tarpTorn] = true

--- { tier, material } of a digester tile, or nil.
function Digester.tileOf(isoObject)
    local name = Sprites.nameOf(isoObject)
    return name and TILES[name]
end

function Digester.isDigester(isoObject)
    return isoObject ~= nil and Digester.tileOf(isoObject) ~= nil
end

function Digester.isHolderOverlay(spriteName)
    return HOLDER_OVERLAYS[spriteName] == true
end

local SCRUBBER_OVERLAYS = {}
for _, name in pairs(Sprites.digesterScrubber) do
    SCRUBBER_OVERLAYS[name] = true
end

function Digester.isScrubberOverlay(spriteName)
    return SCRUBBER_OVERLAYS[spriteName] == true
end

--- Every digester base tile, for MapObjects.OnLoadWithSprite.
function Digester.sprites()
    local names = {}
    for name in pairs(TILES) do
        table.insert(names, name)
    end
    return names
end

--- The holder overlay for a holder kind, its fill (0..1) and whether it's torn, or nil for the
--- dome, whose holder is itself.
function Digester.holderOverlay(holder, fill, torn)
    local set = Sprites.digesterHolder
    if holder == "bags" or holder == "tarp" then
        if torn then
            return holder == "bags" and set.bagsTorn or set.tarpTorn
        end
        local levels = set[holder]
        return levels[math.min(#levels, 1 + math.floor(fill * #levels))]
    elseif holder == "drum" then
        local levels = set.drum
        return levels[math.min(#levels, 1 + math.floor(fill * #levels))]
    end
    return nil
end

-- Clients ------------------------------------------------------------------------------------

--- What every client keeps of the digester at x, y, z (DigesterObject:buildSummary), or nil.
function Digester.getSummary(x, y, z)
    local system = Digester.clientSystem
    local globalObject = system and system.system:getObjectAt(x, y, z)
    return globalObject and globalObject:getModData().summary
end

function Digester.summaryOf(isoObject)
    return Digester.getSummary(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- The digester's record on the authority (single player or the server), or nil elsewhere.
function Digester.recordOf(isoObject)
    local system = not isClient() and Digester.serverSystem
    return system and system:getLuaObjectAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
end

--- The digester's summary as this side knows it, or nil: the authority builds it from its record,
--- which a job may have changed since the last summary went out, and has no client copy.
function Digester.currentSummary(isoObject)
    local record = Digester.recordOf(isoObject)
    return record and record:buildSummary() or Digester.summaryOf(isoObject)
end

return Digester
