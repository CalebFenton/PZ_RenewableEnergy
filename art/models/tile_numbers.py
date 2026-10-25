"""The numbers of the tiles in renewable_energy_01 that both tile generators key by: tiles.py, which
says what each shows, and tools/make_tiles.py, which gives each its properties. Lua names them in
media/lua/shared/RenewableEnergy/Sprites.lua; keep it in step. It imports nothing, so
make_tiles.py runs without Blender.
"""
COLUMNS = 8  # the game reads tilesets and their depth maps eight tiles wide
# The order of an object's tiles from its first, one per facing, that the placing cursor turns it
# through.
FACINGS = "SENW"

SOLAR_FLAT = 0
SOLAR_FAILSAFE = 7
SOLAR_CELL_CHARGER = 10
SOLAR_CRATE = 11
GARDEN_LIGHT, GARDEN_LIGHT_LIT = 14, 15
# Each mount's material, its first wall panel (facing S, then E), its first rack and its first
# rack's snow overlay (in FACINGS' order).
MOUNTS = (("metal", 1, 3, 17), ("wood", 21, 24, 28))
# Battery storage: the item type, the tile a save's storage stands on, facing S, the first battery
# overlay of each look in batteries.BANK_BATTERY_LOOKS' order, and its first meter overlay.
STORAGE_TILES = (
    ("BatteryBoxWood", 8, (36, 136, 182), 48),
    ("BatteryBoxMetal", 23, (38, 138, 184), 53),
    ("BatteryRackWood", 32, (73, 140, 186), 58),
    ("BatteryRackMetal", 33, (79, 146, 192), 63),
    ("BatteryBankWood", 34, (87, 154, 200), 68),
    ("BatteryBankMetal", 9, (99, 166, 212), 40),
)
# Each storage in STORAGE_TILES' order turns through four tiles from here, in FACINGS' order.
TURNED_STORAGE_FIRST = 340
# The gas heater off and lit, as a save's heaters stand; then off in each facing from
# TURNED_HEATER_FIRST, then lit in each.
HEATER, HEATER_LIT = 244, 245
TURNED_HEATER_FIRST = TURNED_STORAGE_FIRST + len(FACINGS) * len(STORAGE_TILES)
# The barrel digester's tile for each of the game's drums it may be built from.
BARREL_DIGESTERS = {"MetalDrum": 228, "Mov_OrangeBarrel": 229, "Mov_DarkGreenBarrel": 277, "Mov_LightGreenBarrel": 278}
INSULATED_DIGESTER, DOME_DIGESTER = 230, 231
GASIFIERS = {"primitive": 250, "standard": 251, "advanced": 252}
SCOOP_ROTOR = 264
# The blade machines: each one's first tile, of one per facing in N, E, S, W order, the sprite
# model it is (wind.SPRITE_MODELS) and its blades.
WIND_TILES = ((265, "Propeller", "wood"), (269, "Propeller", "pipe"), (273, "Alternator", "steel"),
              (372, "Propeller", "steel"), (397, "Alternator", "wood"), (401, "Alternator", "pipe"),
              (405, "CarAlternator", "wood"), (409, "CarAlternator", "pipe"), (413, "CarAlternator", "steel"))
