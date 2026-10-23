-- Ratings for the mod's power hardware, in watts and watt-hours; balancing changes only this file.
-- Appliances draw what vanilla bills a generator for them (Specs.wattsPerFuel); everything else is
-- rated against those draws.

RenewableEnergy = RenewableEnergy or {}
local Specs = {}
RenewableEnergy.Specs = Specs

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
    ["RenewableEnergy.L16Battery"] = { wh = 2100, cyclesAt50 = 1500, wiring = { tools = { "SCREWDRIVER", "WRENCH" } } },
    -- Homemade from open glass jars and soft pipe lead: heavy for what it holds, and short-lived.
    ["RenewableEnergy.JarBattery"] = { wh = 400, cyclesAt50 = 150 },
}

-- Inverters by item type: watts carried (a bank's limit sums its working inverters), idle draw while
-- on, built-in charger watts from grid/generator power (0 for none), and the wiring skill/xp that
-- override Specs.wiring.inverter. Sized so each tier carries a meaningfully larger set of appliances.
Specs.inverters = {
    ["RenewableEnergy.PlugInInverter"] = { watts = 300, idle = 4, chargerWatts = 0, wiring = { skill = 0, xp = 10 } },
    ["RenewableEnergy.PowerInverter"] = { watts = 600, idle = 8, chargerWatts = 0, wiring = { skill = 2, xp = 15 } },
    ["RenewableEnergy.InverterCharger"] = { watts = 1000, idle = 15, chargerWatts = 1000, wiring = { skill = 4, xp = 25 } },
}

-- Share of battery power a period modified-sine inverter turns into AC.
Specs.inverterEfficiency = 0.9

-- Bank parts besides batteries and inverters; vanilla's car battery charger doubles as a bank charger.
Specs.controller = "RenewableEnergy.ChargeController"
Specs.charger = "Base.CarBatteryCharger"

-- Input slots a bank has without a charge controller, and how many each working controller adds.
-- Each source uses the `slots` of its kind's row (Specs.mounts, Specs.wind.turbines, Specs.treadmill).
Specs.freeSlots = 2
Specs.slotsPerController = 7

-- Wind chargers by kind (RenewableEnergy.Wind): watts at ratedKph, starting at cutInKph. Game wind is
-- ClimateManager's windPower × 120 km/h. Left unbraked at breakKph or more, blades break at
-- breakPerHour (scaled by the StormDamage options); any item in `blades` repairs them. A turbine with
-- furlKph turns out of strong wind, making furledShare of its rating instead of breaking early.
Specs.wind = {
    turbines = {
        scoop = { slots = 1, watts = 480, cutInKph = 8, ratedKph = 50 },
        propeller = { slots = 2, watts = 1600, cutInKph = 10, ratedKph = 40, breakKph = 55, breakPerHour = 0.25,
            blades = { "RenewableEnergy.WoodenBlades", "RenewableEnergy.PipeBlades" } },
        alternator = { slots = 3, watts = 3200, cutInKph = 9, ratedKph = 40, furlKph = 55, furledShare = 0.3,
            breakKph = 90, breakPerHour = 0.1, blades = { "RenewableEnergy.SteelBlades" } },
    },
    -- Share added per level above ground, capped at maxBonusLevel.
    heightBonusPerLevel = 0.15,
    maxBonusLevel = 3,
    -- Squares checked for shelter, and the share lost when fully hemmed in.
    shelterRadius = 8,
    shelterLoss = 0.7,
}

-- Treadmill (RenewableEnergy.Treadmill): wiring cost (as Specs.wiring), watts a runner puts in (an
-- hour of running is roughly an hour of a fridge-freezer), run length, and an hour's cost and XP.
-- Unwired, a run draws drawFuel: vanilla bills nothing for a treadmill, so it is billed like the
-- other clothing appliances (IsoGenerator.ClothingAppliancePowerConsumption).
Specs.treadmill = {
    slots = 1,
    wiring = { seconds = 90, wire = 2, scrap = 1, tools = { "SCREWDRIVER" }, skill = 2, xp = 10 },
    watts = 240, runMinutes = 30, drawFuel = 0.09,
    endurancePerHour = 0.6, thirstPerHour = 0.2,
    xpPerHour = { Fitness = 20, Sprinting = 15 },
}

-- Watts each wired-in Car Battery Charger puts in while grid or generator power reaches the bank:
-- a car battery's capacity over vanilla's charge time (IsoCarBatteryCharger chargeRate), matching
-- what one standing alone draws (Specs.wattsPerFuel).
Specs.chargerWatts = 100

-- Condition a bank part loses per hour while its bank powers its area, and per overload that cuts
-- the bank; tuned so an inverter needs roughly weekly Electronics Scrap repairs.
Specs.partWear = {
    perHour = { inverter = 0.06, controller = 0.03 },
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
-- and storm crack factor before the material's. Snow settles where holdsSnow and stays until it
-- melts or is swept, unless shedsSnow lets it slide off in sun or mild air.
Specs.mounts = {
    flat = { slots = 1, modules = 1, tilt = 0, stormFactor = 1, holdsSnow = true },
    wall = { slots = 1, modules = 1, tilt = 90, stormFactor = 0 },
    rack = { slots = 1, modules = 2, tilt = 38, stormFactor = 1, holdsSnow = true, shedsSnow = true },
}
-- A wooden mount flexes and lets modules crack; a welded one holds them.
Specs.materials = {
    wood = { stormFactor = 2 },
    metal = { stormFactor = 0.5 },
}

-- Thunderstorms at windMin km/h or more crack a module per panel with chancePerHour (times the
-- mount, material and StormDamageRate factors), costing `crack` condition. Tuned from a
-- fast-forwarded game year to crack an occasional module every few months across a modest array.
Specs.storm = { windMin = 45, chancePerHour = 0.0035, crack = 30 }
-- Below this condition a module shows cracked glass, on a mount or the arrow board. Reglazed modules
-- show whole; sealed ones still show cracked, because the glass still is.
Specs.crackedBelow = 60

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
-- Electric Wire (returned by Unwire), Electronics Scrap (kept by the part), tool ItemTags (which
-- unwiring takes too), Electricity level, and XP for the first time an item is ever wired.
-- Inverters set skill/xp per type. Every part takes a screwdriver, as vanilla's battery, radio and
-- headlights do in a car.
Specs.wiring = {
    battery = { seconds = 30, wire = 1, scrap = 0, tools = { "SCREWDRIVER" }, skill = 0, xp = 5 },
    inverter = { seconds = 60, wire = 2, scrap = 0, tools = { "SCREWDRIVER" } },
    charger = { seconds = 30, wire = 1, scrap = 0, tools = { "SCREWDRIVER" }, skill = 0, xp = 5 },
    controller = { seconds = 60, wire = 2, scrap = 1, tools = { "SCREWDRIVER" }, skill = 3, xp = 15 },
}

-- Electricity XP for each module of a panel the first time it is ever connected to a bank.
Specs.connectXp = 5

-- Rated watts of the gadgets' cells.
Specs.cellChargerWatts = 5
Specs.maintainerWatts = 10

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

-- How far a panel may be from the bank it is connected to, in tiles and in floors.
Specs.sourceReach = { tiles = 20, levels = 3 }

-- Watts per unit of vanilla's generator bill for a switched-on appliance
-- (IsoObject:getGeneratorPowerConsumption, fuel an hour before the GeneratorFuelConsumption option),
-- so appliances keep vanilla's balance and follow its changes. Chosen so vanilla's car battery
-- charger's bill matches the watts that fill a car battery in its charge time.
Specs.wattsPerFuel = 2000

return Specs
