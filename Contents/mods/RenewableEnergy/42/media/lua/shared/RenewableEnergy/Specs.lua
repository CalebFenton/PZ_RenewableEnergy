-- What each piece of the mod's power hardware is rated for, in watts and watt-hours.
--
-- Every number is a 1993 part's: .agent/design-ideas.md §2-§5 names the real model behind
-- each. Code that needs a rating reads it here, so balancing changes only this file.

RenewableEnergy = RenewableEnergy or {}

local Specs = {}
RenewableEnergy.Specs = Specs

-- Batteries by item type. wh is the nominal capacity at 25 °C and full condition;
-- cyclesAt50 is how many 50% discharges wear one out.
Specs.batteries = {
    ["Base.CarBattery1"] = { wh = 600, cyclesAt50 = 80 },
    ["Base.CarBattery2"] = { wh = 600, cyclesAt50 = 80 },
    ["Base.CarBattery3"] = { wh = 600, cyclesAt50 = 80 },
    ["RenewableEnergy.DeepCycleBattery"] = { wh = 1260, cyclesAt50 = 1000 },
    ["RenewableEnergy.L16Battery"] = { wh = 2100, cyclesAt50 = 1200 },
}

-- Inverters by item type: continuous and start-surge watts, the watts the inverter itself
-- draws while on, and the watts its built-in charger puts into the bank from a running
-- backup generator (0 for none).
Specs.inverters = {
    ["RenewableEnergy.PlugInInverter"] = { watts = 140, surge = 300, idle = 4, chargerWatts = 0 },
    ["RenewableEnergy.PowerInverter"] = { watts = 600, surge = 1200, idle = 8, chargerWatts = 0 },
    ["RenewableEnergy.InverterCharger"] = { watts = 2500, surge = 6000, idle = 15, chargerWatts = 1500 },
}

-- Charge controllers by item type: rated panel watts each one regulates (30 A at 12 V).
Specs.controllers = {
    ["RenewableEnergy.ChargeController"] = { watts = 360 },
}

-- Panel mounts by kind (RenewableEnergy.Sprites.kindOf): modules held and tilt from flat.
Specs.mounts = {
    flat = { modules = 1, tilt = 0 },
    wall = { modules = 1, tilt = 90 },
    rack = { modules = 2, tilt = 38 },
}

-- Battery banks by item type. sprite is the Sprites field of its placed tile.
-- uncontrolledModules is how many modules may charge it without a controller: small
-- modules regulate themselves on a battery that size.
Specs.banks = {
    ["RenewableEnergy.BatteryBox"] = { sprite = "batteryBox", maxBatteries = 2, maxControllers = 0, uncontrolledModules = 2 },
    ["RenewableEnergy.BatteryBank"] = { sprite = "batteryBank", maxBatteries = 12, maxControllers = 4, uncontrolledModules = 2 },
}

-- Rated watts of the panels.
Specs.moduleWatts = 50
Specs.cellChargerWatts = 5
Specs.maintainerWatts = 10

-- Batteries found in the world hold this fraction of a charge.
Specs.foundCharge = { min = 0.3, max = 0.8 }

-- How far a panel may be wired from its bank, in tiles and in floors.
Specs.sourceReach = { tiles = 20, levels = 3 }

-- A running vehicle within this many tiles charges a bank through electric wire run from its
-- battery, with a 50 A alternator at idle.
Specs.vehicleReach = 3
Specs.vehicleWatts = 600

-- What appliances draw while on, in watts (design §2.4). surge is the start-up draw of a
-- compressor or motor; volts = 240 needs a split-phase supply no Release 1 inverter makes.
Specs.loads = {
    fridgeFreezer = { watts = 80, surge = { min = 600, max = 900 } },
    fridge = { watts = 50, surge = { min = 400, max = 500 } },
    light = { watts = 60 },
    television = { watts = 90 },
    radio = { watts = 10 },
    microwave = { watts = 1000 },
    range = { watts = 2000, volts = 240 },
    washer = { watts = 500, surge = { min = 800, max = 1000 } },
    dryer = { watts = 4000, volts = 240 },
    batteryCharger = { watts = 100 },
    -- Anything else the engine says draws power, gas pumps included (when one pumps can't
    -- be told): watts per unit of IsoObject:getGeneratorPowerConsumption, so that a
    -- fridge-freezer's 0.13 comes to 80 W.
    other = { wattsPerConsumption = 600 },
}

return Specs
