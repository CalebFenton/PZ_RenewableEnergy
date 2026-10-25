-- Biogas digesters, as both sides know them: the tiers and their gas holders, how they digest, what
-- each feed is worth, which tiles are digesters, and the summary every client keeps of each one.
--
-- A digester is a built tile whose container is its feed hopper. The authority keeps its state in a
-- Global Object System (DigesterSystem), which runs it while its chunk is unloaded.
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
-- stink: its share of the stink score; stinkCap: the most it stinks whatever its state.
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
-- holds nothing and leaks. levels: its overlays from slack to full, and torn: its overlay once torn;
-- the dome's holder is the dome itself.
Digester.HOLDERS = {
    bags = { capacity = 0.6, wearPerDay = 1, levels = Sprites.digesterHolder.bags, torn = Sprites.digesterHolder.bagsTorn },
    tarp = { capacity = 1.0, wearPerDay = 0.25, levels = Sprites.digesterHolder.tarp, torn = Sprites.digesterHolder.tarpTorn },
    drum = { capacity = 1.5, levels = Sprites.digesterHolder.drum },
    dome = { capacity = 4.0 },
}

-- The stink score at which each smell level starts.
Digester.SMELL_SCORES = { 0.2, 1, 2 }
-- The souring buffer: a digester sours with more acid than ACID_LIMIT per unit of potentialCap, and
-- recovers below ACID_RECOVER of that limit.
Digester.ACID_LIMIT = 0.8
Digester.ACID_RECOVER = 0.5

-- Digestion rate k (share of the undigested potential a day) by temperature in °C, between which
-- it runs in straight lines: nothing at either end, best across the mesophilic range.
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

-- Propane tanks. A full tank holds the biogas for a generator's full tank (IsoGenerator's
-- MaximumGeneratorFuel) at GasKit.M3_PER_LITRE.
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

--- Whether a fridge compressor `character` carries can be plugged in where they stand.
function Digester.compressorPowered(character)
    local square = character:getCurrentSquare()
    return square ~= nil and square:haveElectricity()
end

-- What the scrubber's water takes out before it is spent, in m³ of gas: plain water, lye from
-- wood ash, or lime; and what one use of steel wool takes the rotten-egg gas out of.
Digester.SCRUB_M3 = { water = 5, ash = 15, lime = 30 }
Digester.WOOL_M3 = 10
-- Litres of water a scrubber charge takes.
Digester.SCRUB_WATER = 4

-- By full type: potential (m³ before the Biogas multiplier), acid (what it adds to souring;
-- below zero neutralises), seedHours (startup it saves: manure brings the bacteria).
-- Manure stands for an animal's day of it, as the game drops one item about every other day for
-- cows and pigs, every third for the rest (AnimalData.checkPoop), so the values follow what each
-- animal makes in a day. Hens drop none inside a hutch.
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
-- Food by the kilogram: meat is richer and sours faster.
local FOOD_POTENTIAL_PER_KG, FOOD_ACID_PER_KG = 0.12, 1
local MEAT_POTENTIAL_PER_KG, MEAT_ACID_PER_KG = 0.2, 2
local MEAT_TYPES = { Meat = true, Game = true, Beef = true, Poultry = true, Sausage = true, Fish = true, Seafood = true, Roe = true }
-- Dung of the other animals (mice, rats) is worth a little.
local OTHER_DUNG = { potential = 0.01, acid = 0 }

--- What one hourly meter takes of `item` into the digester: { potential, acid, seedHours,
--- whole, neutraliser }, where whole is false for a drainable neutraliser, of which one use goes in
--- at a time. Nil for what the digester doesn't take; it takes manure, grass and hay, the
--- composter's food (rotten, or tagged compostable) and the neutralisers.
function Digester.feedOf(item)
    local fullType = item:getFullType()
    local neutraliser = NEUTRALISERS[fullType]
    if neutraliser then
        return { potential = 0, acid = neutraliser, whole = not instanceof(item, "DrainableComboItem"), neutraliser = true }
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

--- The hopper's AcceptItemFunction: feed and neutralisers only (Digester.adoptContainer).
function Digester.acceptItem(container, item)
    return Digester.feedOf(item) ~= nil
end

function Digester.adoptContainer(container)
    RenewableEnergy.adoptContainer(container, "RenewableEnergy.Digester.acceptItem")
end

--- The feeds waiting in the hopper `container`, in its order: the items, and each one's feed
--- (Digester.feedOf).
function Digester.feedsIn(container)
    local items, feeds = {}, {}
    local list = container and container:getItems()
    for i = 0, (list and list:size() or 0) - 1 do
        local item = list:get(i)
        local feed = Digester.feedOf(item)
        if feed then
            table.insert(items, item)
            table.insert(feeds, feed)
        end
    end
    return items, feeds
end

--- The tier of a digester tile, or nil for any other object.
function Digester.tierOf(isoObject)
    local kind, tier = Sprites.kindOfObject(isoObject)
    return kind == "digester" and tier or nil
end

function Digester.isDigester(isoObject)
    return isoObject ~= nil and Digester.tierOf(isoObject) ~= nil
end

--- The translation key of the name of a digester of `tier`.
function Digester.nameKey(tier)
    return "IGUI_RenewableEnergy_Digester_" .. tier
end

-- The floors a pit can be dug in: the ones vanilla digs a grave in (ISEmptyGraves:isValid).
local DIGGABLE_FLOORS = { "floors_exterior_natural", "blends_natural_01" }

--- Whether a brick dome can be built on the square `params.square`: its pit is dug, so only into
--- the ground, on a ground floor of earth, grass or sand (the build cursor's OnIsValid).
function Digester.OnIsValidDome(params)
    local square = params.square
    local floor = square:getZ() == 0 and square:getFloor()
    local name = floor and floor:getTextureName()
    if not name then
        return false
    end
    for _, prefix in ipairs(DIGGABLE_FLOORS) do
        if luautils.stringStarts(name, prefix) then
            return true
        end
    end
    return false
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

-- The summary (DigesterObject:buildSummary) gets `hopper`, the feeds waiting, from this side's
-- copy of the hopper.
RenewableEnergy.GlobalObjects.addAccessors(Digester, function(summary, isoObject)
    local _, feeds = Digester.feedsIn(isoObject:getContainer())
    summary.hopper = #feeds
end)

return Digester
