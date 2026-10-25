-- Ratings for the mod's power hardware, in watts and watt-hours, and its wear and repair figures.
-- Appliances draw what vanilla bills a generator for them (Specs.wattsPerFuel); everything else is
-- rated against those draws.
-- Names: a rating ends in Watts (chargerWatts, Sun.panelWatts), a live quantity the bank or gas
-- line works out each pass ends in W (Bank:limitW, loadW), and watt-hours end in Wh. Saved fields
-- (loadW, chargeWantW, a source's watts) keep their names.

RenewableEnergy = RenewableEnergy or {}
local Specs = {}
RenewableEnergy.Specs = Specs

-- The tools wiring jobs take, as materials (RenewableEnergy.Materials): a tag, and the item a
-- tooltip names for it, as vanilla names the wrench its jobs take.
local SCREWDRIVER = { tool = "SCREWDRIVER", item = "Base.Screwdriver" }
local WRENCH = { tool = "WRENCH", item = "Base.Wrench" }

-- Batteries by item type. wh is capacity at full condition; cyclesAt50 is how many discharges of
-- half the new capacity use up a battery's condition (Battery.cycleWear), so one carrying such a
-- load every night is at half capacity after cyclesAt50 / 2 nights: a car battery in about five
-- months, a deep cycle in a year, an L-16 in about two. A long game outlives a bank or two. wiring
-- overrides Specs.wiring.battery: an L-16's cable lugs bolt onto its studs.
Specs.batteries = {
    ["Base.CarBattery1"] = { wh = 600, cyclesAt50 = 300 },
    ["Base.CarBattery2"] = { wh = 600, cyclesAt50 = 300 },
    ["Base.CarBattery3"] = { wh = 600, cyclesAt50 = 300 },
    ["RenewableEnergy.DeepCycleBattery"] = { wh = 1260, cyclesAt50 = 750 },
    ["RenewableEnergy.L16Battery"] = { wh = 2100, cyclesAt50 = 1500, wiring = { tools = { SCREWDRIVER, WRENCH } } },
    -- Homemade from open glass jars and soft pipe lead: heavy for what it holds, and short-lived.
    ["RenewableEnergy.JarBattery"] = { wh = 400, cyclesAt50 = 150 },
}

-- Inverters by item type: watts carried (a bank's limit sums its working inverters), idle draw while
-- on, the share of battery power it turns into AC, built-in charger watts from grid/generator power
-- (0 for none), and the wiring skill/xp that override Specs.wiring.inverter. Sized so each tier
-- carries a meaningfully larger set of appliances. A `homemade` one is crafted, never found, and
-- its `wear` scales its share of Specs.partWear. The homemade pair carry what their found twins do
-- but waste more, idle hotter and wear sooner, and the makeshift one worst of all, so a found
-- inverter or the next recipe is always worth having.
Specs.inverters = {
    ["RenewableEnergy.PlugInInverter"] = { watts = 300, idle = 4, efficiency = 0.9, chargerWatts = 0,
        wiring = { skill = 0, xp = 10 } },
    ["RenewableEnergy.PowerInverter"] = { watts = 600, idle = 8, efficiency = 0.9, chargerWatts = 0,
        wiring = { skill = 2, xp = 15 } },
    ["RenewableEnergy.InverterCharger"] = { watts = 1000, idle = 15, efficiency = 0.9, chargerWatts = 1000,
        wiring = { skill = 4, xp = 25 } },
    ["RenewableEnergy.MakeshiftInverter"] = { watts = 300, idle = 8, efficiency = 0.75, chargerWatts = 0,
        wiring = { skill = 0, xp = 10 }, homemade = true, wear = 1.2 },
    ["RenewableEnergy.HomemadeInverter"] = { watts = 600, idle = 16, efficiency = 0.8, chargerWatts = 0,
        wiring = { skill = 2, xp = 15 }, homemade = true, wear = 1.2 },
}

-- Bank parts besides batteries and inverters; vanilla's car battery charger doubles as a bank charger.
Specs.controller = "RenewableEnergy.ChargeController"
Specs.charger = "Base.CarBatteryCharger"

-- Input slots a bank has without a charge controller, and how many each working controller adds.
-- Each source uses the `slots` of its kind's row (Specs.mounts, Specs.wind.turbines, Specs.treadmill).
Specs.freeSlots = 2
Specs.slotsPerController = 7

-- Wind chargers by kind (RenewableEnergy.Wind): watts at ratedKph, starting at cutInKph. Game wind is
-- ClimateManager's windPower × 120 km/h. The generator alone sets the power: `blades` lists the
-- blade materials (Specs.wind.blades) it takes, the first for a charger whose sprite names none,
-- and they decide only when it breaks. rotorAbove is how many levels above its own the rotor turns
-- (each mast charger's hub is a storey and a half up, art/models/items.py), where its shelter is
-- counted. A turbine with furlKph swings its tail-hinged head out of strong wind and holds
-- furledShare of its rating, as a furling tail governs the rotor near its rated speed; turned
-- aside, its blades take less of the gale and break only furledBladeKph above their break speed.
-- propeller is the treadmill wind charger, alternator the homebuilt wind turbine (their names in
-- saved records and tiles from before they were renamed).
Specs.wind = {
    turbines = {
        scoop = { slots = 1, watts = 480, cutInKph = 8, ratedKph = 50, rotorAbove = 0 },
        propeller = { slots = 2, watts = 1600, cutInKph = 10, ratedKph = 40, rotorAbove = 1,
            blades = { "wood", "pipe", "steel" } },
        carAlternator = { slots = 2, watts = 2000, cutInKph = 10, ratedKph = 40, rotorAbove = 1,
            blades = { "wood", "pipe", "steel" } },
        alternator = { slots = 3, watts = 3200, cutInKph = 9, ratedKph = 40, rotorAbove = 1,
            furlKph = 55, furledShare = 0.85, furledBladeKph = 20, blades = { "steel", "wood", "pipe" } },
    },
    -- Blades by material: the item that makes and mends them, and the `broken` item a mend hands
    -- back; the wind above which unbraked they can break (Specs.storm), and their stormShare of the
    -- weakest blades' chance; the sound they make straining in that wind and breaking. Plastic pipe
    -- goes brittle and snaps first, carved wood flexes, and forged steel holds through all but the worst.
    blades = {
        pipe = { item = "RenewableEnergy.PipeBlades", broken = "RenewableEnergy.BrokenPipeBlades", breakKph = 60,
            stormShare = 1, strainSound = "WindowRattle", breakSound = "BreakObject" },
        wood = { item = "RenewableEnergy.WoodenBlades", broken = "RenewableEnergy.BrokenWoodenBlades", breakKph = 70,
            stormShare = 0.5, strainSound = "WoodDoorCreak", breakSound = "BreakBarricadePlank" },
        steel = { item = "RenewableEnergy.SteelBlades", broken = "RenewableEnergy.BrokenSteelBlades", breakKph = 90,
            stormShare = 0.25, strainSound = "WindowRattle", breakSound = "BreakBarricadeMetal" },
    },
    -- Share added per level above ground, capped at maxBonusLevel.
    heightBonusPerLevel = 0.15,
    maxBonusLevel = 3,
    -- Squares checked for shelter, and the share lost when fully hemmed in. Trees shelter a rotor
    -- turning on treetopLevel or lower: a mast charger standing on the ground or a first floor.
    shelterRadius = 8,
    shelterLoss = 0.7,
    treetopLevel = 2,
    -- Another charger whose rotor turns on the same level within crowdRadius squares takes wind
    -- from this one, crowdLoss of it right beside it and less with each square further, none
    -- beyond: a rotor's wake takes a few rotor widths to fill back in, and these rotors are about
    -- two squares across (art/models/items.py blade lengths). Each such neighbour takes its share
    -- of what the others leave. Not shelter: a mast and a turning rotor stop far less wind than a wall.
    crowdRadius = 3,
    crowdLoss = 0.25,
}

-- Treadmill (RenewableEnergy.Treadmill): wiring cost (as Specs.wiring), watts a runner puts in (an
-- hour of running is roughly an hour of a fridge-freezer), run length, and an hour's cost and XP.
-- Unwired, a run draws drawFuel: vanilla bills nothing for a treadmill, so it is billed like the
-- other clothing appliances (IsoGenerator.ClothingAppliancePowerConsumption).
Specs.treadmill = {
    slots = 1,
    wiring = { seconds = 90, wire = 2, scrap = 1, tools = { SCREWDRIVER }, skill = 2, xp = 10 },
    watts = 240, runMinutes = 30, drawFuel = 0.09,
    endurancePerHour = 0.6, thirstPerHour = 0.2,
    xpPerHour = { Fitness = 20, Sprinting = 15 },
}

-- Watts each wired-in Car Battery Charger puts in while grid or generator power reaches the bank:
-- a car battery's capacity over vanilla's charge time (IsoCarBatteryCharger chargeRate), matching
-- what one standing alone draws (Specs.wattsPerFuel).
Specs.chargerWatts = 100

-- Condition a bank part loses per hour while its bank powers its area, and per overload that cuts
-- the bank. A bank's upkeep is all its parts together, so the rates are tuned on the fullest bank,
-- two inverters and four controllers: together they lose about twice what a vanilla generator
-- does in a day (IsoGenerator's hourly ConditionLowerChanceOneIn roll), and a lone inverter less.
Specs.partWear = {
    perHour = { inverter = 0.025, controller = 0.0125 },
    perOverload = { inverter = 1 },
}
-- What one Electronics Scrap repairs, and the Electricity level needed (as vanilla's ISFixGenerator).
Specs.partRepair = { condition = 10, skill = 2, xp = 5 }

-- Solar modules by item type: rated watts at full condition, tuned so a handful run a fridge-freezer
-- through an average July at the default Sunlight Multiplier. Output scales with condition / 100,
-- so a homemade module's lower ConditionMax caps it lower.
Specs.modules = {
    ["RenewableEnergy.SolarModule"] = { watts = 160 },
    ["RenewableEnergy.HomemadeSolarModule"] = { watts = 160 },
}
-- What a panel holds when nothing recorded its modules, and what world spawns place.
Specs.factoryModule = "RenewableEnergy.SolarModule"

-- Panel mounts by kind (RenewableEnergy.Sprites.kindOf): input slots, modules held, tilt from flat,
-- and stormShare (Specs.storm), times its material's. Snow settles where holdsSnow and stays until
-- it melts or is swept, unless shedsSnow lets it slide off in sun or mild air.
Specs.mounts = {
    flat = { slots = 1, modules = 1, tilt = 0, stormShare = 0.5, holdsSnow = true },
    wall = { slots = 1, modules = 1, tilt = 90, stormShare = 0 },
    rack = { slots = 1, modules = 2, tilt = 38, stormShare = 1, holdsSnow = true, shedsSnow = true },
}
-- A wooden mount flexes and lets modules crack; a welded one holds them. A wooden rack is the
-- weakest panel, at a stormShare of 1.
Specs.materials = {
    wood = { stormShare = 1 },
    metal = { stormShare = 0.25 },
}

-- Storm damage. Unbraked blades (Specs.wind.blades) break with an hourly chance that rises with the
-- square of the wind above their break speed (wind load goes with the square of its speed), from
-- none there to the full chance at fullKph, the game's strongest wind. The full chance is set so
-- worstHours of it, the longest blizzard (WeatherPeriod: 24 + 24 × strength), break the weakest
-- blades with worstChance at the default Storm Damage Rate; other blades get their stormShare of
-- it. Most weather never comes close: a thunderstorm tops out at 84 km/h, a blizzard blows 90 to
-- 120 (WeatherPeriod.updateCurrentStage).
-- Modules crack in any thunderstorm blowing panelKph or more, at panelPerHour for the weakest panel
-- and its stormShare of that for the others: half the chance a fast-forwarded game year once tuned
-- to crack a module every few months across a modest array. That keeps the longest run of
-- thunderstorms, a tropical storm and the two storms that can follow it
-- (WeatherPeriod.createWeatherPattern), under worstChance too. A crack, a storm's or a trailer
-- crash's (ArrowBoard), costs `crack` condition.
Specs.storm = { fullKph = 120, worstHours = 48, worstChance = 0.15, panelKph = 45, panelPerHour = 0.0035,
    crack = 20, crackSound = "BreakGlassItem" }
-- How a module's glass looks, on a mount or the arrow board, by its condition as a share of its
-- own ConditionMax (RenewableEnergy.crackLookOf): whole down to `lightBelow`, lightly cracked
-- below that, heavily cracked below `heavyBelow`. A share, so a homemade module, whose max is
-- lower, looks whole when new and cracks into each look as a factory one does. The first crack
-- of a new module shows: lightBelow sits above the share one crack (storm.crack) leaves it. Reglazed
-- modules show whole; sealed ones still show cracked, because the glass still is (Recipes.lua
-- keeps both levels so).
Specs.crackLooks = { lightBelow = 0.85, heavyBelow = 0.5 }

-- Banks by item type: the Sprites field of its placed tile, and how many of each part it takes.
Specs.banks = {
    ["RenewableEnergy.BatteryBoxWood"] = { sprite = "batteryBoxWood", maxBatteries = 2, maxInverters = 1, maxChargers = 1, maxControllers = 0 },
    ["RenewableEnergy.BatteryBoxMetal"] = { sprite = "batteryBoxMetal", maxBatteries = 2, maxInverters = 1, maxChargers = 1, maxControllers = 0 },
    ["RenewableEnergy.BatteryRackWood"] = { sprite = "batteryRackWood", maxBatteries = 6, maxInverters = 1, maxChargers = 2, maxControllers = 2 },
    ["RenewableEnergy.BatteryRackMetal"] = { sprite = "batteryRackMetal", maxBatteries = 8, maxInverters = 1, maxChargers = 2, maxControllers = 2 },
    ["RenewableEnergy.BatteryBankWood"] = { sprite = "batteryBankWood", maxBatteries = 12, maxInverters = 2, maxChargers = 2, maxControllers = 4 },
    ["RenewableEnergy.BatteryBankMetal"] = { sprite = "batteryBankMetal", maxBatteries = 16, maxInverters = 2, maxChargers = 2, maxControllers = 4 },
}

-- Wiring each part kind into a bank: seconds at normal speed at Electricity 0 (RenewableEnergyAction),
-- Electric Wire (returned by Unwire), Electronics Scrap (kept by the part), tools (which unwiring
-- takes too), Electricity level, and XP for the first time an item is ever wired.
-- Inverters set skill/xp per type. Every part takes a screwdriver, as vanilla's battery, radio and
-- headlights do in a car.
Specs.wiring = {
    battery = { seconds = 30, wire = 1, scrap = 0, tools = { SCREWDRIVER }, skill = 0, xp = 5 },
    inverter = { seconds = 60, wire = 2, scrap = 0, tools = { SCREWDRIVER } },
    charger = { seconds = 30, wire = 1, scrap = 0, tools = { SCREWDRIVER }, skill = 0, xp = 5 },
    controller = { seconds = 60, wire = 2, scrap = 1, tools = { SCREWDRIVER }, skill = 3, xp = 15 },
}

-- Electricity XP for each module of a panel the first time it is ever connected to a bank.
Specs.connectXp = 5

-- Rated watts of the gadgets' cells.
Specs.cellChargerWatts = 5
Specs.maintainerWatts = 10
-- Watt-hours that fill one of the cell charger's batteries (Base.Battery): a game figure, not a
-- real cell's, sized so a full tray charges over a sunny day or two.
Specs.cellChargerBatteryWh = 25

-- A solar garden light: its cell's rated watts, the watt-hours its battery holds, what its lamp
-- draws at night, and the radius it lights.
Specs.gardenLight = { watts = 1, wh = 3, nightWatts = 0.5, radius = 2 }

-- Arrow board lamps draw what vanilla's lightbar takes from a vehicle battery with the engine off
-- (Vehicles.Update.Lightbar, applied twice by VehicleUtils.chargeBattery), as a share of a car
-- battery an hour. Flash rate and duty follow MUTCD 6F.61. The controller cuts the lamps below
-- `cutoff` charge in every battery and relights at `reconnect`; at night they light `radius` squares.
Specs.arrowBoard = {
    lampShare = 0.003, flashesPerMinute = 30, onShare = 0.5,
    cutoff = 0.1, reconnect = 0.25, radius = 3,
}

-- Batteries found in the world hold this fraction of a charge.
Specs.foundCharge = { min = 0.3, max = 0.8 }

-- How far a source (panel, wind charger, treadmill) may be from the bank it is connected to: a
-- radius in tiles, and floors up or down.
Specs.sourceReach = { tiles = 20, levels = 3 }

-- A backup generator a failsafe can start is one plugged in within this many squares of its bank
-- on either axis, on the bank's floor.
Specs.backupReach = 3

-- Watts per unit of vanilla's generator bill for a switched-on appliance
-- (IsoObject:getGeneratorPowerConsumption, fuel an hour before the GeneratorFuelConsumption option),
-- so appliances keep vanilla's balance and follow its changes. Chosen so vanilla's car battery
-- charger's bill matches the watts that fill a car battery in its charge time.
Specs.wattsPerFuel = 2000

--- The watts of an appliance vanilla bills `fuel` an hour for (Specs.wattsPerFuel).
function Specs.wattsFromFuel(fuel)
    return fuel * Specs.wattsPerFuel
end

--- The fuel an hour vanilla would bill for `watts` (Specs.wattsPerFuel), before the
--- GeneratorFuelConsumption option.
function Specs.fuelFromWatts(watts)
    return watts / Specs.wattsPerFuel
end

return Specs
