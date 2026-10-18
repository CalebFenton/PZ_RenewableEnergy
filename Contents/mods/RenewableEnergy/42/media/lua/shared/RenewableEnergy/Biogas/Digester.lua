-- Biogas digesters, as both sides know them: the three tiers and their gas holders, how they
-- digest, what each feed is worth, which tiles are digesters, and the summary every client keeps
-- of each one.
--
-- A digester is a tile the build menu places (scripts/RenewableEnergy/Entities.txt) with a
-- container that is its feed hopper. The authority keeps its state in a Global Object System
-- (server/RenewableEnergy/Biogas/DigesterSystem.lua), which runs it while its chunk is unloaded and
-- sends every client its summary.
--
-- Units: gas and the feed's potential in cubic metres of biogas, temperatures in degrees Celsius,
-- time in game hours.

require "RenewableEnergy/Sprites"
require "RenewableEnergy/GlobalObjects"
require "RenewableEnergy/WoodGas/Gasifier"

RenewableEnergy = RenewableEnergy or {}
local Digester = {}
RenewableEnergy.Digester = Digester

local Sprites, Gasifier = RenewableEnergy.Sprites, RenewableEnergy.Gasifier

Digester.SYSTEM_NAME = "renewable_energy_digester"

-- potentialCap: undigested potential it holds; feed waits in the hopper above it.
-- days: how many days its temperature takes to follow the air (a time constant).
-- stink: its share of the stink score; the Brick Dome stays below the second smell level whatever
-- state it is in (stinkCap).
-- warmTo: the dome is buried and burns its gas to keep at least this warm, as a lit gas heater
-- does (GasHeater.m3PerHour).
-- holder: the gas holder it is built with (HOLDERS). upgrade: the tier its Upgrade job makes of it.
-- sealed: it never fumes indoors.
Digester.TIERS = {
    barrel = { potentialCap = 5, days = 1, stink = 1.0, holder = "bags", upgrade = "insulated" },
    insulated = { potentialCap = 15, days = 3, stink = 0.6, holder = "drum" },
    dome = { potentialCap = 45, days = 8, stink = 0.3, stinkCap = 0.99, warmTo = 20, holder = "dome",
        sealed = true },
}

-- capacity: gas the holder stores. wearPerDay: condition lost a day; a holder at none is torn,
-- holds nothing and leaks. The drum and the dome don't wear. levels: its overlays from slack to
-- full, and torn: its overlay once torn; the dome's holder is the dome itself.
Digester.HOLDERS = {
    bags = { capacity = 0.6, wearPerDay = 1, levels = Sprites.digesterHolder.bags, torn = Sprites.digesterHolder.bagsTorn },
    tarp = { capacity = 1.0, wearPerDay = 0.25, levels = Sprites.digesterHolder.tarp, torn = Sprites.digesterHolder.tarpTorn },
    drum = { capacity = 1.5, levels = Sprites.digesterHolder.drum },
    dome = { capacity = 4.0 },
}

-- The stink score at which each smell level starts (DigesterObject.corpsesFor, the status window).
Digester.SMELL_SCORES = { 0.2, 1, 2 }
-- The souring buffer: a digester sours with more acid than ACID_LIMIT per unit of potentialCap, and
-- recovers below ACID_RECOVER of that limit.
Digester.ACID_LIMIT = 0.8
Digester.ACID_RECOVER = 0.5

-- Digestion rate k (share of the undigested potential a day) by temperature in °C, between which
-- it runs in straight lines: nothing at the first, the mesophilic best at 35 to 40, nothing again
-- at the last.
Digester.K_BY_TEMP = { { 10, 0 }, { 15, 0.01 }, { 25, 1 / 30 }, { 35, 1 / 15 }, { 40, 1 / 15 }, { 50, 0 } }
-- Startup counts only hours this warm, and manure's head start covers at most this share of it.
Digester.STARTUP_MIN_TEMP = 10
Digester.SEED_SHARE = 0.7
-- Sludge, in percent, past which digestion slows to SLUDGE_K.
Digester.SLUDGE_SLOW, Digester.SLUDGE_K = 80, 0.5
-- A holder that vents indoors leaks for this many hours.
Digester.LEAK_HOURS = 2

-- Sludge, in percent of the tank, that one compost bag holds, as vanilla's composter
-- (ISGetCompost).
Digester.SLUDGE_PER_BAG = 10

-- Propane tanks. A full tank holds the biogas for a generator's full tank: IsoGenerator's 10 L
-- (MaximumGeneratorFuel) at GasKit.M3_PER_LITRE.
Digester.TANK = "Base.PropaneTank"
Digester.M3_PER_TANK = 16
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
    [Gasifier.WOOD_ASH] = -3,
    ["Base.BakingSoda"] = -3,
    ["Base.Quicklime"] = -6,
}
-- Food by the kilogram: meat is richer and sours twice as fast.
local FOOD_POTENTIAL_PER_KG, FOOD_ACID_PER_KG = 0.12, 1
local MEAT_POTENTIAL_PER_KG, MEAT_ACID_PER_KG = 0.2, 2
local MEAT_TYPES = { Meat = true, Game = true, Beef = true, Poultry = true, Sausage = true, Fish = true, Seafood = true, Roe = true }
-- Dung of the other animals (mice, rats) is worth a little.
local OTHER_DUNG = { potential = 0.01, acid = 0 }

function Digester.isNeutraliser(item)
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

--- How many feeds wait in the hopper `container`.
function Digester.feedCount(container)
    local count = 0
    local items = container and container:getItems()
    for i = 0, (items and items:size() or 0) - 1 do
        if Digester.feedOf(items:get(i)) then
            count = count + 1
        end
    end
    return count
end

-- Tiles --------------------------------------------------------------------------------------

--- The tier and, for a barrel, the material of a digester tile; nil for any other object.
function Digester.tileOf(isoObject)
    local kind, tier, material = Sprites.kindOf(Sprites.nameOf(isoObject))
    if kind ~= "digester" then
        return nil
    end
    return tier, material
end

function Digester.isDigester(isoObject)
    return isoObject ~= nil and Digester.tileOf(isoObject) ~= nil
end

Digester.isHolderOverlay = Sprites.matcher(Sprites.digesterHolder)
Digester.isScrubberOverlay = Sprites.matcher(Sprites.digesterScrubber)

--- The holder overlay for a holder kind, its fill (0..1) and whether it's torn, or nil for the
--- dome, whose holder is itself.
function Digester.holderOverlay(holder, fill, torn)
    local spec = Digester.HOLDERS[holder]
    if torn then
        return spec.torn
    end
    local levels = spec.levels
    if not levels then
        return nil
    end
    return levels[math.min(#levels, 1 + math.floor(fill * #levels))]
end

-- Summary --------------------------------------------------------------------------------------

-- The summary (DigesterObject:buildSummary) gets `hopper`, the feeds waiting, from this side's
-- copy of the hopper.
RenewableEnergy.GlobalObjects.addAccessors(Digester, function(summary, isoObject)
    summary.hopper = Digester.feedCount(isoObject:getContainer())
end)

return Digester
