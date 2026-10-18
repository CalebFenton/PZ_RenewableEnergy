-- What each piece of the mod's power hardware is rated for, in watts and watt-hours.
--
-- Code that needs a rating reads it here, so balancing changes only this file. Appliances draw
-- what vanilla bills a generator for them (Specs.wattsPerFuel). Everything else is rated to play
-- well against those draws: sources by how many of them run a fridge-freezer, inverters by what
-- each carries, batteries from the car battery vanilla's charger fills.

RenewableEnergy = RenewableEnergy or {}
local Specs = {}
RenewableEnergy.Specs = Specs

-- Batteries by item type. wh is the capacity at full condition; cyclesAt50 is how many 50%
-- discharges wear one out. Down to half its capacity: a car battery run flat every night in about
-- two and a half months, a deep cycle drained halfway every night in about two years.
Specs.batteries = {
    ["Base.CarBattery1"] = { wh = 600, cyclesAt50 = 300 },
    ["Base.CarBattery2"] = { wh = 600, cyclesAt50 = 300 },
    ["Base.CarBattery3"] = { wh = 600, cyclesAt50 = 300 },
    ["RenewableEnergy.DeepCycleBattery"] = { wh = 1260, cyclesAt50 = 1500 },
    ["RenewableEnergy.L16Battery"] = { wh = 2100, cyclesAt50 = 2500 },
    -- Homemade from open glass jars and soft pipe lead: heavy for what it holds, and short-lived.
    ["RenewableEnergy.JarBattery"] = { wh = 400, cyclesAt50 = 150 },
}

-- Inverters by item type: the watts it carries (a bank's limit is the sum over its working
-- inverters), the watts it draws itself while on, the watts its built-in charger puts into the
-- bank from grid or generator power (0 for none), and the Electricity level wiring it in needs and
-- the Electricity XP of the first time one is ever wired in (over Specs.wiring.inverter's).
-- The Plug-in Inverter carries a fridge-freezer and the lights, or the TV, the radio and the lights,
-- but not the fridge-freezer and the TV. The Power Inverter carries both, with a freezer or one of
-- the range, the microwave, the washer and the dryer. An Inverter/Charger carries a fridge-freezer,
-- a freezer, the TV, the lights, the washer and the microwave together; the range and the dryer as
-- well take two.
Specs.inverters = {
    ["RenewableEnergy.PlugInInverter"] = { watts = 300, idle = 4, chargerWatts = 0, wiring = { skill = 0, xp = 10 } },
    ["RenewableEnergy.PowerInverter"] = { watts = 600, idle = 8, chargerWatts = 0, wiring = { skill = 2, xp = 15 } },
    ["RenewableEnergy.InverterCharger"] = { watts = 1000, idle = 15, chargerWatts = 1500, wiring = { skill = 4, xp = 25 } },
}

-- A 1993 modified-sine inverter turns about this much of the battery's power into AC.
Specs.inverterEfficiency = 0.9

-- The bank parts besides batteries and inverters: the charge controller, and vanilla's car
-- battery charger, which a bank wires in as its charger.
Specs.controller = "RenewableEnergy.ChargeController"
Specs.charger = "Base.CarBatteryCharger"

-- Input slots: what a bank takes without a charge controller, and how many more each working
-- controller adds. Every source takes the `slots` of its kind's row (Specs.mounts,
-- Specs.wind.turbines, Specs.treadmill), by what it can make.
Specs.freeSlots = 2
Specs.slotsPerController = 7

-- Wind chargers by kind (RenewableEnergy.Wind): watts at the rated speed, the wind it starts
-- turning in and the wind it makes its rating in, in km/h. The game's wind runs
-- ClimateManager's windPower × 120, mostly 10 to 40 km/h, stronger in winter, past 60 in a bad
-- storm. Left unbraked in a wind of `breakKph` or more, its blades break at `breakPerHour` (scaled
-- by the StormDamage options), and any of `blades` makes it whole again. The scoop rotor is weak
-- and slow but takes any wind and never breaks; the propeller makes real power and wants braking
-- before a storm; the homemade alternator turns its head out of a wind of `furlKph`, making
-- `furledShare` of its rating, and breaks only in the worst.
Specs.wind = {
    turbines = {
        scoop = { slots = 1, watts = 480, cutInKph = 8, ratedKph = 50 },
        propeller = { slots = 2, watts = 1600, cutInKph = 10, ratedKph = 40, breakKph = 55, breakPerHour = 0.25,
            blades = { "RenewableEnergy.WoodenBlades", "RenewableEnergy.PipeBlades" } },
        alternator = { slots = 3, watts = 3200, cutInKph = 9, ratedKph = 40, furlKph = 55, furledShare = 0.3,
            breakKph = 90, breakPerHour = 0.1, blades = { "RenewableEnergy.SteelBlades" } },
    },
    -- Each level it stands above the ground adds this share, up to maxBonusLevel.
    heightBonusPerLevel = 0.15,
    maxBonusLevel = 3,
    -- Shelter counts the squares this far around; hemmed in all round, it loses this share.
    shelterRadius = 8,
    shelterLoss = 0.7,
}

-- A treadmill (RenewableEnergy.Treadmill): what wiring it to a bank takes (as a bank part's,
-- Specs.wiring), the watts a runner then puts in (an hour of running is about an hour of a
-- fridge-freezer), how long one run lasts, wired or not, and what an hour of it costs and teaches.
-- Unwired, a run draws `drawFuel` (Specs.wattsPerFuel): vanilla bills nothing for a treadmill, so
-- it bills one as its washer, dryer and stove (IsoGenerator.ClothingAppliancePowerConsumption).
Specs.treadmill = {
    slots = 1,
    wiring = { seconds = 90, wire = 2, scrap = 1, tool = "SCREWDRIVER", skill = 2, xp = 10 },
    watts = 240, runMinutes = 30, drawFuel = 0.09,
    endurancePerHour = 0.6, thirstPerHour = 0.2,
    xpPerHour = { Fitness = 20, Sprinting = 15 },
}

-- Watts each Car Battery Charger wired into a bank puts in while grid or generator power
-- reaches the bank: vanilla's charger fills a car battery in 6 hours (IsoCarBatteryCharger
-- chargeRate 1/6 an hour), so 600 Wh / 6 h, what one standing alone draws (Specs.wattsPerFuel).
Specs.chargerWatts = 100

-- Condition each kind of bank part loses per hour while its bank powers its area, and per overload
-- that cuts the bank: about one Electronics Scrap of repairs a week per inverter.
Specs.partWear = {
    perHour = { inverter = 0.06, controller = 0.03 },
    perOverload = { inverter = 1 },
}
-- An Electronics Scrap repairs this much of a part's condition, at this Electricity level or more
-- (as vanilla's ISFixGenerator).
Specs.partRepair = { condition = 10, skill = 2, xp = 5 }

-- Solar modules by item type: rated watts at condition 100, so that four or five run a
-- fridge-freezer through an average July at the default Sunlight Multiplier, about eight on racks
-- in December. A module makes its rating times its condition / 100, so a homemade one, whose
-- ConditionMax is lower, tops out lower.
Specs.modules = {
    ["RenewableEnergy.SolarModule"] = { watts = 160 },
    ["RenewableEnergy.HomemadeSolarModule"] = { watts = 160 },
}
-- The factory-made module: what a panel holds when nothing recorded its modules, and what
-- world spawns place.
Specs.factoryModule = "RenewableEnergy.SolarModule"

-- Panel mounts by kind (RenewableEnergy.Sprites.kindOf): input slots, modules held, tilt from
-- flat, and how likely a storm is to crack one of its modules, before the material's own factor.
-- Snow settles on a mount that holdsSnow (not on an upright wall panel) and lies there until it
-- melts or is swept off, unless the mount shedsSnow as a tilted rack does in sun or mild air.
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

-- Thunderstorms at or above windMin km/h crack a module of each panel with chancePerHour
-- (times the mount's factors and the StormDamageRate sandbox option), costing it `crack`
-- condition. Aimed at one cracked module every 2-3 months on ten flat panels: a fast-forwarded
-- game year had 21 thunderstorms and about 150 hours of them at windMin or more.
Specs.storm = { windMin = 45, chancePerHour = 0.0035, crack = 30 }
-- A module below this condition shows a cracked cover glass, on a mount and on the arrow board
-- trailer: every cracked module found in the world, and any storm crack on a module that wasn't
-- far above it, while weathered finds and reglazed modules (Reglaze Module) show whole. A sealed
-- module (Seal Cracked Module's caps) still shows cracked: the glass is.
Specs.crackedBelow = 60

-- Banks by item type. sprite is the Sprites field of its placed tile; the rest is how many of
-- each part can be wired in.
Specs.banks = {
    ["RenewableEnergy.BatteryBoxWood"] = { sprite = "batteryBoxWood", maxBatteries = 2, maxInverters = 1, maxChargers = 1, maxControllers = 0 },
    ["RenewableEnergy.BatteryBoxMetal"] = { sprite = "batteryBoxMetal", maxBatteries = 2, maxInverters = 1, maxChargers = 1, maxControllers = 0 },
    ["RenewableEnergy.BatteryRackWood"] = { sprite = "batteryRackWood", maxBatteries = 6, maxInverters = 1, maxChargers = 2, maxControllers = 2 },
    ["RenewableEnergy.BatteryRackMetal"] = { sprite = "batteryRackMetal", maxBatteries = 8, maxInverters = 1, maxChargers = 2, maxControllers = 2 },
    ["RenewableEnergy.BatteryBankWood"] = { sprite = "batteryBankWood", maxBatteries = 12, maxInverters = 2, maxChargers = 2, maxControllers = 4 },
    ["RenewableEnergy.BatteryBankMetal"] = { sprite = "batteryBankMetal", maxBatteries = 16, maxInverters = 2, maxChargers = 2, maxControllers = 4 },
}

-- What wiring each kind of part into a bank takes: seconds at normal game speed at Electricity 0
-- (RenewableEnergyAction), Electric Wire (Unwire gives it back), Electronics Scrap (kept by the
-- part), the tool (an ItemTag field) and the Electricity level. xp is the Electricity XP of the
-- first time an item is ever wired in. Each inverter type takes its own skill and xp (Specs.inverters).
Specs.wiring = {
    battery = { seconds = 30, wire = 1, scrap = 0, tool = "WRENCH", skill = 0, xp = 5 },
    inverter = { seconds = 60, wire = 2, scrap = 0, tool = "SCREWDRIVER" },
    charger = { seconds = 30, wire = 1, scrap = 0, tool = "SCREWDRIVER", skill = 0, xp = 5 },
    controller = { seconds = 60, wire = 2, scrap = 1, tool = "SCREWDRIVER", skill = 3, xp = 15 },
}

-- Electricity XP for each module of a panel the first time it is ever connected to a bank.
Specs.connectXp = 5

-- Rated watts of the gadgets' cells.
Specs.cellChargerWatts = 5
Specs.maintainerWatts = 10

-- A solar garden light: its cell's rated watts, the watt-hours its battery holds, what its lamp
-- draws at night, and the radius it lights.
Specs.gardenLight = { watts = 1, wh = 3, nightWatts = 0.5, radius = 2 }

-- The arrow board trailer's lamps, lit, take what vanilla's lightbar takes from a vehicle's
-- battery with the engine off, day or night: Vehicles.Update.Lightbar charges it -0.000025 a
-- minute, which VehicleUtils.chargeBattery applies twice, so `lampShare` of a car battery's charge
-- an hour (VehicleBattery.CAR_BATTERY, 1.8 W). The MUTCD (2009, 6F.61) asks 25 to 40 flashes a
-- minute, each lit at least half the time. The controller shuts the lamps off below `cutoff` of a
-- full charge in every battery, nearly flat, and lights them again once a battery is back at
-- `reconnect`. At night the lit board lights the ground `radius` squares around it.
Specs.arrowBoard = {
    lampShare = 0.003, flashesPerMinute = 30, onShare = 0.5,
    cutoff = 0.1, reconnect = 0.25, radius = 3,
}

-- Batteries found in the world hold this fraction of a charge.
Specs.foundCharge = { min = 0.3, max = 0.8 }

-- How far a panel may be from the bank it is connected to, in tiles and in floors.
Specs.sourceReach = { tiles = 20, levels = 3 }

-- Watts per unit of what vanilla bills a generator for a switched-on appliance
-- (IsoObject:getGeneratorPowerConsumption, fuel an hour before the GeneratorFuelConsumption
-- option), so appliances keep vanilla's balance and follow its changes. Vanilla's car battery
-- charger is billed 0.05 and fills a 600 Wh car battery in 6 hours: 100 W. A fridge-freezer (0.13)
-- comes to 260 W, a stove, washer or dryer (0.09) 180 W, a TV (0.03) 60 W and a light (0.002) 4 W.
Specs.wattsPerFuel = 2000

return Specs
