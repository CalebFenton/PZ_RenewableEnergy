-- What each piece of the mod's power hardware is rated for, in watts and watt-hours.
--
-- Code that needs a rating reads it here, so balancing changes only this file. The ratings
-- start from the specifications of 1993 parts.

RenewableEnergy = RenewableEnergy or {}
local Specs = {}
RenewableEnergy.Specs = Specs

-- Batteries by item type. wh is the capacity at full condition; cyclesAt50 is how many 50%
-- discharges wear one out.
Specs.batteries = {
    ["Base.CarBattery1"] = { wh = 600, cyclesAt50 = 80 },
    ["Base.CarBattery2"] = { wh = 600, cyclesAt50 = 80 },
    ["Base.CarBattery3"] = { wh = 600, cyclesAt50 = 80 },
    ["RenewableEnergy.DeepCycleBattery"] = { wh = 1260, cyclesAt50 = 1000 },
    ["RenewableEnergy.L16Battery"] = { wh = 2100, cyclesAt50 = 1200 },
}

-- Inverters by item type: the watts it carries (a bank's limit is the sum over its working
-- inverters), the watts it draws itself while on, the watts its built-in charger puts into the
-- bank from grid or generator power (0 for none), the Electricity level wiring it in needs, and
-- the Electricity XP of the first time one is ever wired in.
-- The Plug-in Inverter carries a TV and one lamp, or a mini fridge, but not a full fridge.
Specs.inverters = {
    ["RenewableEnergy.PlugInInverter"] = { watts = 150, idle = 4, chargerWatts = 0, wireSkill = 0, wireXp = 10 },
    ["RenewableEnergy.PowerInverter"] = { watts = 600, idle = 8, chargerWatts = 0, wireSkill = 2, wireXp = 15 },
    ["RenewableEnergy.InverterCharger"] = { watts = 2500, idle = 15, chargerWatts = 1500, wireSkill = 4, wireXp = 25 },
}

-- A 1993 modified-sine inverter turns about this much of the battery's power into AC.
Specs.inverterEfficiency = 0.9

-- The bank parts besides batteries and inverters: the charge controller, and vanilla's car
-- battery charger, which a bank wires in as its charger.
Specs.controller = "RenewableEnergy.ChargeController"
Specs.charger = "Base.CarBatteryCharger"

-- Input slots: what a bank takes without a charge controller, and how many more each working
-- controller adds. Every source takes slots by what it can make (`sourceSlots`, by kind).
Specs.freeSlots = 2
Specs.slotsPerController = 7
Specs.sourceSlots = { flat = 1, wall = 1, rack = 1, scoop = 1, treadmill = 1, propeller = 2, alternator = 3 }

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
        scoop = { ratedW = 150, cutInKph = 8, ratedKph = 50 },
        propeller = { ratedW = 500, cutInKph = 10, ratedKph = 40, breakKph = 55, breakPerHour = 0.25,
            blades = { "RenewableEnergy.WoodenBlades", "RenewableEnergy.PipeBlades" } },
        alternator = { ratedW = 1000, cutInKph = 9, ratedKph = 40, furlKph = 55, furledShare = 0.3,
            breakKph = 90, breakPerHour = 0.1, blades = { "RenewableEnergy.SteelBlades" } },
    },
    -- Each level it stands above the ground adds this share, up to maxBonusLevel.
    heightBonusPerLevel = 0.15,
    maxBonusLevel = 3,
    -- Shelter counts the squares this far around; hemmed in all round, it loses this share.
    shelterRadius = 8,
    shelterLoss = 0.7,
}

-- A treadmill wired to a bank (RenewableEnergy.Treadmill): what wiring it takes (as a bank part's,
-- Specs.wiring), the watts a runner puts in (an hour of running is about an hour of TV), how long
-- one run lasts, and what an hour of it costs and teaches.
Specs.treadmill = {
    wiring = { seconds = 90, wire = 2, scrap = 1, tool = "SCREWDRIVER", skill = 2, xp = 10 },
    watts = 75, runMinutes = 30,
    endurancePerHour = 0.6, thirstPerHour = 0.2,
    xpPerHour = { Fitness = 20, Sprinting = 15 },
}

-- Watts each Car Battery Charger wired into a bank puts in while grid or generator power
-- reaches the bank.
Specs.chargerWatts = 250

-- Condition inverters and controllers lose per hour while their bank powers its area, and an
-- inverter's extra loss each time an overload cuts the bank: about one Electronics Scrap of
-- repairs a week per inverter.
Specs.partWear = {
    inverterPerHour = 0.06,
    controllerPerHour = 0.03,
    overload = 1,
}
-- An Electronics Scrap repairs this much of a part's condition, at this Electricity level or more
-- (as vanilla's ISFixGenerator).
Specs.partRepair = { condition = 10, skill = 2, xp = 5 }

-- Solar modules by item type: rated watts at condition 100. A module makes its rating times its
-- condition / 100, so a homemade one, whose ConditionMax is lower, tops out lower.
Specs.modules = {
    ["RenewableEnergy.SolarModule"] = { watts = 50 },
    ["RenewableEnergy.HomemadeSolarModule"] = { watts = 50 },
}
-- The factory-made module: what a panel holds when nothing recorded its modules, and what
-- world spawns place.
Specs.factoryModule = "RenewableEnergy.SolarModule"

-- Panel mounts by kind (RenewableEnergy.Sprites.kindOf): modules held, tilt from flat, and how
-- likely a storm is to crack one of its modules, before the material's own factor.
Specs.mounts = {
    flat = { modules = 1, tilt = 0, stormFactor = 1 },
    wall = { modules = 1, tilt = 90, stormFactor = 0 },
    rack = { modules = 2, tilt = 38, stormFactor = 1 },
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
-- far above it, while weathered finds and repaired modules (Repair Cracked Module's caps) show whole.
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

-- What wiring each kind of part into a bank takes: game seconds at Electricity 0, Electric Wire
-- (Unwire gives it back), Electronics Scrap (kept by the part), the tool (an ItemTag field) and
-- the Electricity level. xp is the Electricity XP of the first time an item is ever wired in.
-- Inverters take their own wireSkill and wireXp.
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

-- The arrow board trailer's 15-lamp board and its controller, as Solar Technology's Silent
-- Sentinel manual measures them at 12.5 V (P/N 550-025-100, Power Consumption and Battery Level):
-- a single arrow draws dayWatts while lit by day (1.25 A) and nightWatts once the photocell dims
-- it after dark (0.5 A), the controller offWatts between flashes (0.05 A). The MUTCD (2009,
-- 6F.61) asks 25 to 40 flashes a minute, each lit at least half the time. The controller shuts
-- the lamps off below 10.7 V, which a lead-acid battery under that load reaches nearly flat:
-- below `cutoff` of a full charge in every battery. It lights them again once a battery is back
-- at `reconnect`, about the 12 V rested where its battery level reads Normal again. At night the
-- lit board lights the ground `radius` squares around it.
Specs.arrowBoard = {
    dayWatts = 15.6, nightWatts = 6.25, offWatts = 0.625, flashesPerMinute = 30, onShare = 0.5,
    cutoff = 0.1, reconnect = 0.25, radius = 3,
}

-- Batteries found in the world hold this fraction of a charge.
Specs.foundCharge = { min = 0.3, max = 0.8 }

-- How far a panel may be from the bank it is connected to, in tiles and in floors.
Specs.sourceReach = { tiles = 20, levels = 3 }

-- What appliances draw while on, in watts. A compressor runs only part of the time: watts is
-- its draw while it runs, which the inverters must carry, and duty the share of the time it
-- runs, which sets the energy it takes.
Specs.loads = {
    fridgeFreezer = { watts = 200, duty = 0.4 },
    fridge = { watts = 160, duty = 0.4 },
    miniFridge = { watts = 80, duty = 0.5 },
    light = { watts = 60 },
    television = { watts = 65 },
    radio = { watts = 10 },
    microwave = { watts = 1000 },
    range = { watts = 2000 },
    washer = { watts = 500 },
    dryer = { watts = 4000 },
    batteryCharger = { watts = 100 },
    -- Anything else the engine says draws power, gas pumps included: watts per unit of
    -- IsoObject:getGeneratorPowerConsumption, so that a fridge-freezer's 0.13 comes to 80 W.
    other = { wattsPerConsumption = 600 },
}

return Specs
