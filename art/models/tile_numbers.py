"""The numbers of every tile in renewable_energy_01 and renewable_energy_02, the one record of them:
tiles.py says what each shows, and tools/make_tiles.py gives each its properties and writes them
for Lua, by meaning, into media/lua/shared/RenewableEnergy/SpriteTiles.lua. Also the wind
chargers' spin steps, which wind.py models and Lua counts. It imports nothing, so make_tiles.py
runs without Blender.
"""
# The order of an object's tiles from its first, one per facing, that the placing cursor turns it
# through.
FACINGS = "SENW"
# The order of the tiles, one per direction, of what the cursor doesn't turn: a wind charger's by
# its rotor's facing, a gas pipe's by the way it runs, a gas kit's by its generator's facing.
DIRECTIONS = "NESW"

SOLAR_FLAT = 0
SOLAR_FAILSAFE = 7
SOLAR_CELL_CHARGER = 10
SOLAR_CRATE = 11
# The crate's overlays: the modules in it, and its lid shut.
CRATE_FULL, CRATE_CLOSED = 12, 13
GARDEN_LIGHT, GARDEN_LIGHT_LIT = 14, 15
# Snow on the flat panel; a rack's is in MOUNTS, and a wall panel holds none.
FLAT_SNOW = 16
# Each mount's material, its first wall panel (facing S, then E), its first rack and its first
# rack's snow overlay (in FACINGS' order).
MOUNTS = (("metal", 1, 3, 17), ("wood", 21, 24, 28))
# Cracked glass by look (RenewableEnergy.crackLookOf): the flat panel's overlay, then each mount
# material's first wall panel overlay (facing S, then E) and first rack overlay, a rack having one
# per module slot (RACK_SLOTS of them) in each facing, in FACINGS' order, slot 1 first.
CRACKS = (("heavy", 115, {"metal": (116, 120), "wood": (118, 128)}),
          ("light", 376, {"metal": (377, 381), "wood": (379, 389)}))
RACK_SLOTS = 2
# A homemade module in a mount's slot, laid out as one look of CRACKS: the flat panel's overlay,
# then each mount material's first wall panel overlay and first rack overlay, one per slot per
# facing. Each covers the factory module the mount's tile draws in that slot; the slot's crack and
# snow overlays draw over it.
HOMEMADE_MODULES = (424, {"metal": (425, 427), "wood": (435, 437)})

# Battery storage: the item type, the tile a save's storage stands on, facing S, the first battery
# overlay of each look in BATTERY_LOOKS' order, and its first meter overlay.
STORAGE_TILES = (
    ("BatteryBoxWood", 8, (36, 136, 182), 48),
    ("BatteryBoxMetal", 23, (38, 138, 184), 53),
    ("BatteryRackWood", 32, (73, 140, 186), 58),
    ("BatteryRackMetal", 33, (79, 146, 192), 63),
    ("BatteryBankWood", 34, (87, 154, 200), 68),
    ("BatteryBankMetal", 9, (99, 166, 212), 40),
)
# The batteries each storage holds, an overlay each per look.
STORAGE_CAPACITY = {"BatteryBoxWood": 2, "BatteryBoxMetal": 2, "BatteryRackWood": 6, "BatteryRackMetal": 8,
                    "BatteryBankWood": 12, "BatteryBankMetal": 16}
# The looks a battery's overlay draws it with (batteries.BANK_BATTERY_LOOKS).
BATTERY_LOOKS = ("car", "deepCycle", "l16")
# A meter's overlays, from one LED lit to all.
METER_LEVELS = 5
# The meter is on the storage's front, which the camera, from the south-east, sees only facing S or
# E; facing N or W the storage hides every LED.
METER_FACINGS = "SE"
# Each storage in STORAGE_TILES' order turns through four tiles from here, in FACINGS' order.
TURNED_STORAGE_FIRST = 340


def _turned_storage_overlays():
    # renewable_energy_02 from 0, facing by facing but S, whose overlays are those above, storage by
    # storage: each look's batteries by slot, then the meter where it shows.
    overlays, next_tile = {}, 0
    for facing in FACINGS[1:]:
        for item, *_ in STORAGE_TILES:
            slots = STORAGE_CAPACITY[item]
            batteries = {}
            for look in BATTERY_LOOKS:
                batteries[look] = list(range(next_tile, next_tile + slots))
                next_tile += slots
            levels = METER_LEVELS if facing in METER_FACINGS else 0
            overlays[facing, item] = batteries, list(range(next_tile, next_tile + levels))
            next_tile += levels
    return overlays


# The storage's overlays in renewable_energy_02 by (facing, item): its battery overlays by look,
# each a list by slot, and its meter overlays by level (none facing away).
TURNED_STORAGE_OVERLAYS = _turned_storage_overlays()

# The gas heater off and lit, as a save's heaters stand; then off in each facing from
# TURNED_HEATER_FIRST, then lit in each.
HEATER, HEATER_LIT = 244, 245
TURNED_HEATER_FIRST = TURNED_STORAGE_FIRST + len(FACINGS) * len(STORAGE_TILES)

# The barrel digester's tile for each of the game's drums it may be built from.
BARREL_DIGESTERS = {"MetalDrum": 228, "Mov_OrangeBarrel": 229, "Mov_DarkGreenBarrel": 277, "Mov_LightGreenBarrel": 278}
INSULATED_DIGESTER, DOME_DIGESTER = 230, 231
# The digesters in the order of the overlays below.
DIGESTERS = ("barrel", "insulated", "dome")
# The barrel digester's gas holders, each its first of HOLDER_FILLS overlays from slack to taut, then
# one torn; and the insulated digester's floating drum, risen to each of DRUM_LEVELS from the first.
BARREL_HOLDERS = {"bags": 232, "tarp": 236}
HOLDER_FILLS = 3
DRUM_HOLDER, DRUM_LEVELS = 240, 4
# Over each digester in DIGESTERS' order: its scrubber, the scrubber spent, and a sour digester's foam.
SCRUBBERS, SPENT_SCRUBBERS, SOUR_FOAM = 247, 420, 417

# The gas kit on the floor at a generator the game doesn't know.
GAS_KIT = 246
# The game's generator bodies that the gas kit and the gasifier's pipe fit (biogas.GENERATOR_BODIES),
# in the order of their overlays, with their tiles in appliances_misc_01: each set of four's first,
# and the facings the four show, in order.
GENERATOR_BODIES = (("frame", (0, 8), "ESWN"), ("old", (4,), "ESWN"), ("inverter", (12,), "SENW"))
GENERATOR_TILESET = "appliances_misc_01"
# One kit overlay per body and generator facing, in DIRECTIONS' order; then the generator's half of
# the pipe, four per body and facing, one by the direction of the gasifier it comes from.
GENERATOR_KIT_FIRST = 280
GENERATOR_PIPE_FIRST = GENERATOR_KIT_FIRST + len(DIRECTIONS) * len(GENERATOR_BODIES)

# Each gasifier tier's tile; its lit overlay is len(GASIFIERS) after it.
GASIFIERS = {"primitive": 250, "standard": 251, "advanced": 252}
# The pipe's half on the gasifier's tile, by the direction of the generator it runs to, and its half
# on a generator the game doesn't know, by the direction of the gasifier, each in DIRECTIONS' order.
GASIFIER_PIPE, GENERATOR_PIPE = 256, 260

SCOOP_ROTOR = 264
TIMBER_SCOOP = 469  # the scoop rotor on a wooden frame
# The blade machines: each one's first tile, of one per facing in DIRECTIONS' order, the sprite
# model it is (wind.SPRITE_MODELS) and its blades.
WIND_TILES = ((265, "Propeller", "wood"), (269, "Propeller", "pipe"), (273, "Alternator", "steel"),
              (372, "Propeller", "steel"), (397, "Alternator", "wood"), (401, "Alternator", "pipe"),
              (405, "CarAlternator", "wood"), (409, "CarAlternator", "pipe"), (413, "CarAlternator", "steel"),
              (445, "TimberPropeller", "wood"), (449, "TimberPropeller", "pipe"), (453, "TimberPropeller", "steel"),
              (457, "TimberCarAlternator", "wood"), (461, "TimberCarAlternator", "pipe"),
              (465, "TimberCarAlternator", "steel"))
# The sprite models' spins: each step's turn in degrees and how many steps a model has. The scoop
# rotor turns whole, the same after half a turn; a bladed rotor about its hub, the same after a third.
SCOOP_SPIN = (30, 6)
ROTOR_SPIN = (20, 6)
