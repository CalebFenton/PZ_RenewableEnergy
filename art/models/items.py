"""What each inventory item's ground model and icon are made of.

The builders are in their family's module (solar.py, batteries.py, electronics.py, magazines.py,
biogas.py, woodgas.py, wind.py and trailer.py), in real-world sizes of 1993 hardware, painted from
palette.py and sharing the parts in parts.py. Each adds one thing's parts to a collection, standing
on z = 0, centred, front to -Y (see the harness's lib/art/kit.py); tiles.py places the same
builders on tiles. A builder takes keyword options, so a tile can draw a battery rack without its
batteries and an overlay just the batteries.
"""
import batteries
import biogas
import electronics
import magazines
import solar
import wind
import woodgas
from art.kit import added, group
from parts import DRUM_LOOKS, dropped_drum


def lying(builder, **options):
    """A builder for the thing on its side, as an item lies on the ground."""
    def build(col):
        group(col, "Lying", [obj for obj in added(col, builder, **options) if obj.parent is None], rotate=(0, 90, 0))
    return build


# Item type -> builder of its ground model, of its icon when that shows more, the icon's camera
# elevation in degrees when the 30 of a tile would show a flat thing edge on, and the ground
# model's scale in Models.txt when it isn't models.GROUND_SCALE.
#
# The game's car battery mesh at its model script's scale is 0.19 x 0.13 x 0.14 m, about three
# quarters of a real one's 0.26 x 0.17 x 0.20, and the game draws it through the same 1.5 as ours
# (models.GROUND_SCALE), a little larger than life. A battery at real size would lie on the ground
# smaller than the car battery beside it, so the batteries, their cases and the plates and molds
# sized to fit them take the car battery's own scale instead; the parts stay real size for the
# icons and the battery storage tiles.
BATTERY_GROUND_SCALE = 0.75
ITEMS = {
    "SolarModule": {"model": solar.solar_module, "icon_elevation": 55},
    "HomemadeSolarModule": {"model": solar.homemade_module, "icon_elevation": 55},
    "SolarCells": {"model": solar.solar_cells, "icon_elevation": 60},
    "SolarFlat": {"model": solar.solar_flat, "icon_elevation": 25},
    "SolarWallWood": {"model": lambda col: solar.solar_wall(col, "wood", lying=True), "icon": lambda col: solar.solar_wall(col, "wood")},
    "SolarWallMetal": {"model": lambda col: solar.solar_wall(col, "metal", lying=True),
                       "icon": lambda col: solar.solar_wall(col, "metal")},
    "SolarRackWood": {"model": lambda col: solar.solar_rack(col, "wood")},
    "SolarRackMetal": {"model": lambda col: solar.solar_rack(col, "metal")},
    "BatteryBoxWood": {"model": batteries.STORAGE["BatteryBoxWood"],
                       "icon": lambda col: batteries.STORAGE["BatteryBoxWood"](col, batteries=2, meter_level=4)},
    "BatteryBoxMetal": {"model": batteries.STORAGE["BatteryBoxMetal"],
                        "icon": lambda col: batteries.STORAGE["BatteryBoxMetal"](col, batteries=2, meter_level=4)},
    "BatteryRackWood": {"model": batteries.STORAGE["BatteryRackWood"],
                        "icon": lambda col: batteries.STORAGE["BatteryRackWood"](col, batteries=6, meter_level=4)},
    "BatteryRackMetal": {"model": batteries.STORAGE["BatteryRackMetal"],
                         "icon": lambda col: batteries.STORAGE["BatteryRackMetal"](col, batteries=8, meter_level=4)},
    "BatteryBankWood": {"model": batteries.STORAGE["BatteryBankWood"],
                        "icon": lambda col: batteries.STORAGE["BatteryBankWood"](col, batteries=8, meter_level=4)},
    "BatteryBankMetal": {"model": batteries.STORAGE["BatteryBankMetal"],
                         "icon": lambda col: batteries.STORAGE["BatteryBankMetal"](col, batteries=12, meter_level=4)},
    "PlugInInverter": {"model": electronics.plug_in_inverter},
    "PowerInverter": {"model": electronics.power_inverter},
    "InverterCharger": {"model": electronics.inverter_charger},
    "MakeshiftInverter": {"model": electronics.makeshift_inverter, "icon_elevation": 45},
    "HomemadeInverter": {"model": electronics.homemade_inverter, "icon_elevation": 50},
    "MicrowaveTransformer": {"model": electronics.microwave_transformer},
    "ChargeController": {"model": electronics.charge_controller},
    "SolarFailsafe": {"model": electronics.solar_failsafe, "icon": lambda col: electronics.solar_failsafe(col, cable=False)},
    "DeepCycleBattery": {"model": batteries.deep_cycle_battery, "ground_scale": BATTERY_GROUND_SCALE},
    "L16Battery": {"model": batteries.l16_battery, "ground_scale": BATTERY_GROUND_SCALE},
    "JarBattery": {"model": batteries.jar_battery, "ground_scale": BATTERY_GROUND_SCALE},
    "SolarMaintainer": {"model": electronics.solar_maintainer, "icon_elevation": 40},
    "SolarCellCharger": {"model": electronics.solar_cell_charger, "icon_elevation": 45},
    "SolarGardenLight": {"model": lying(solar.solar_garden_light), "icon": solar.solar_garden_light},
    "CarBatteryCase": {"model": lambda col: batteries.battery_case(col, "CarCase", (0.26, 0.17, 0.2), "carbattery", 6, "carlabel",
                                                                   bolt=True),
                       "icon_elevation": 40, "ground_scale": BATTERY_GROUND_SCALE},
    "DeepCycleBatteryCase": {"model": lambda col: batteries.battery_case(col, "DeepCycleCase", (0.32, 0.17, 0.23), "marine", 6, "label"),
                             "icon_elevation": 40, "ground_scale": BATTERY_GROUND_SCALE},
    "L16BatteryCase": {"model": lambda col: batteries.battery_case(col, "L16Case", batteries.L16, "maroon", 3, "label", words="L-16",
                                                                   handles=True),
                       "icon_elevation": 40, "ground_scale": BATTERY_GROUND_SCALE},
    "WornBatteryPlates": {"model": lambda col: batteries.battery_plates(col, worn=True), "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryPlates": {"model": batteries.battery_plates, "ground_scale": BATTERY_GROUND_SCALE},
    "WoodenBatteryPlatePattern": {"model": batteries.plate_pattern, "icon_elevation": 55, "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryPlateMoldUnfired": {"model": batteries.plate_mold, "icon_elevation": 50, "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryPlateMold": {"model": lambda col: batteries.plate_mold(col, fired=True), "icon_elevation": 50,
                         "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryElectrolyte": {"model": batteries.battery_electrolyte},
    "HomesteadPowerMag1": {"model": lambda col: magazines.magazine(col, 1), "icon_elevation": 70},
    "HomesteadPowerMag2": {"model": lambda col: magazines.magazine(col, 2), "icon_elevation": 70},
    "HomesteadPowerMag3": {"model": lambda col: magazines.magazine(col, 3), "icon_elevation": 70},
    "HomesteadPowerMag4": {"model": lambda col: magazines.magazine(col, 4), "icon_elevation": 70},
    "WoodAsh": {"model": woodgas.wood_ash, "icon_elevation": 25},
    "GasConversionKit": {"model": biogas.gas_conversion_kit, "icon_elevation": 45},
    "FridgeCompressor": {"model": biogas.fridge_compressor},
    "GasHeater": {"model": biogas.gas_heater},
    "TarryPacking": {"model": woodgas.tarry_packing, "icon_elevation": 35},
    "FemaPamphlet": {"model": magazines.fema_pamphlet, "icon_elevation": 70},
    "TreadmillMotor": {"model": wind.treadmill_motor},
    "WoodenBlades": {"model": lambda col: wind.blade_bundle(col, "wood"), "icon_elevation": 50},
    "PipeBlades": {"model": lambda col: wind.blade_bundle(col, "pipe"), "icon_elevation": 50},
    "SteelBlades": {"model": lambda col: wind.blade_bundle(col, "steel"), "icon_elevation": 50},
    "BrokenWoodenBlades": {"model": lambda col: wind.broken_blades(col, "wood"), "icon_elevation": 50},
    "BrokenPipeBlades": {"model": lambda col: wind.broken_blades(col, "pipe"), "icon_elevation": 50},
    "BrokenSteelBlades": {"model": lambda col: wind.broken_blades(col, "steel"), "icon_elevation": 50},
    "HomemadeAlternator": {"model": wind.homemade_alternator, "icon_elevation": 40},
    "CarAlternator": {"model": wind.car_alternator, "icon_elevation": 35},
}

# Vanilla items with no ground model of their own, which the game drops as a flat icon: the drums
# the digesters are built from. Lua (RenewableEnergy/DrumModels.lua) points the items at these, and
# they get no icon.
GROUND_MODELS = {look: {"model": lying(dropped_drum, look=look)} for look in DRUM_LOOKS}
