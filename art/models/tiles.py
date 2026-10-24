"""What each tile of renewable_energy_01 and renewable_energy_02 shows, built from the item builders.

The index of each entry is the tile's number, which Lua reads through
media/lua/shared/RenewableEnergy/Sprites.lua and tools/make_tiles.py gives properties; keep the
three in step. A tile is a list of layers. A layer marked `holdout` is drawn invisible: an overlay
tile renders the object it sits on that way, so it keeps only the pixels the object doesn't hide.

Tile coordinates are a square one metre wide centred on the origin: its north edge is y = +0.5 and
its west edge x = -0.5 (see kit.py).
"""
import items


def layer(build, holdout=False, at=(0, 0, 0), turn=0, scale=1, **options):
    return {"build": build, "options": options, "at": at, "turn": turn, "scale": scale, "holdout": holdout}


# Turning an object whose front faces south (-Y) to face each direction.
FACING_TURN = {"S": 0, "E": 90, "N": 180, "W": -90}


def _turned(at, facing):
    """`at` turned about the square's centre as FACING_TURN turns an object to face `facing`."""
    x, y, z = at
    return {"S": (x, y, z), "E": (-y, x, z), "N": (-x, -y, z), "W": (y, -x, z)}[facing]


# A wall panel's bottom edge, above the floor.
WALL_PANEL_HEIGHT = 1.1


def _wall(material, facing, cracks=False, light_cracks=False):
    """On the square's north edge facing south, or on its west edge facing east. `cracks` makes the
    overlay of the cracks in its glass, the light ones with `light_cracks`."""
    at = (0, 0.5, WALL_PANEL_HEIGHT) if facing == "S" else (-0.5, 0, WALL_PANEL_HEIGHT)
    turn = FACING_TURN[facing]
    if cracks:
        return [layer(items.solar_wall, holdout=True, material=material, at=at, turn=turn),
                layer(items.solar_wall, material=material, cracks=True, light_cracks=light_cracks, at=at, turn=turn)]
    return [layer(items.solar_wall, material=material, at=at, turn=turn)]


def _rack(material, facing, snow=False, cracks=None, light_cracks=False):
    """`snow` makes the overlay of the snow on it, `cracks` (a module slot) that of the cracks in
    one module's glass, the light ones with `light_cracks`."""
    turn = FACING_TURN[facing]
    if snow or cracks:
        return [layer(items.solar_rack, holdout=True, material=material, turn=turn),
                layer(items.solar_rack, material=material, snow=snow, cracks=cracks, light_cracks=light_cracks, turn=turn)]
    return [layer(items.solar_rack, material=material, turn=turn)]


def _overlay(build, at, turn=0, **options):
    return [layer(build, holdout=True, at=at, turn=turn), layer(build, frame=False, at=at, turn=turn, **options)]


def _battery_overlay(build, at, turn, slot, look):
    """The battery in `slot` (from 0) as `look`, and its link to the one before. A bank draws its
    batteries' overlays in slot order, so this one keeps out from behind the storage and the
    batteries in the slots before it, and draws over any in front of it. That holds in every
    facing: a battery behind an earlier one is cut where that one hides it."""
    return [layer(build, holdout=True, at=at, turn=turn), layer(build, holdout=True, frame=False, batteries=slot, at=at, turn=turn),
            layer(build, frame=False, slot=slot, look=look, at=at, turn=turn)]


TILES = {
    0: [layer(items.solar_flat)],
    # The failsafe shares the generator's square, so it sits in the corner nearest the viewer's
    # left, where the generator doesn't cover it.
    7: [layer(items.solar_failsafe, at=(-0.28, -0.3, 0), turn=-20)],
    10: [layer(items.solar_cell_charger, turn=-15)],
    11: [layer(items.solar_crate)],
    12: [layer(items.solar_crate, holdout=True), layer(items.solar_crate, box_=False, contents=True)],
    13: [layer(items.solar_crate, holdout=True), layer(items.solar_crate, box_=False, closed=True)],
    14: [layer(items.solar_garden_light, stake=False)],
    15: [layer(items.solar_garden_light, stake=False, lit=True)],
    16: [layer(items.solar_flat, holdout=True), layer(items.solar_flat, snow=True)],
    115: [layer(items.solar_flat, holdout=True), layer(items.solar_flat, cracks=True)],
    376: [layer(items.solar_flat, holdout=True), layer(items.solar_flat, cracks=True, light_cracks=True)],
}
for material, first_wall, first_rack, first_snow in (("metal", 1, 3, 17), ("wood", 21, 24, 28)):
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = _wall(material, facing)
    for offset, facing in enumerate("SENW"):
        TILES[first_rack + offset] = _rack(material, facing)
        TILES[first_snow + offset] = _rack(material, facing, snow=True)
# Cracked glass, heavy then light (RenewableEnergy.crackLookOf): a wall panel's per facing, and a
# rack's per facing and module slot, slot 1 first.
for light, metal_wall, metal_rack, wood_wall, wood_rack in ((False, 116, 120, 118, 128), (True, 377, 381, 379, 389)):
    for material, first_wall, first_rack in (("metal", metal_wall, metal_rack), ("wood", wood_wall, wood_rack)):
        for offset, facing in enumerate("SE"):
            TILES[first_wall + offset] = _wall(material, facing, cracks=True, light_cracks=light)
        for offset, facing in enumerate("SENW"):
            for slot in (1, 2):
                TILES[first_rack + 2 * offset + slot - 1] = _rack(material, facing, cracks=slot, light_cracks=light)

# Battery storage: the item type, its tile, the first battery overlay of each look in
# items.BANK_BATTERY_LOOKS' order, and its first meter overlay. Battery overlay n of a look shows a
# battery of that look in slot n; meter overlay n shows n LEDs lit. The car batteries' overlays
# are the tiles that once showed n batteries of any type, which a save may still have on a bank.
STORAGE_TILES = (
    ("BatteryBoxWood", 8, (36, 136, 182), 48),
    ("BatteryBoxMetal", 23, (38, 138, 184), 53),
    ("BatteryRackWood", 32, (73, 140, 186), 58),
    ("BatteryRackMetal", 33, (79, 146, 192), 63),
    ("BatteryBankWood", 34, (87, 154, 200), 68),
    ("BatteryBankMetal", 9, (99, 166, 212), 40),
)
STORAGE_CAPACITY = {"BatteryBoxWood": 2, "BatteryBoxMetal": 2, "BatteryRackWood": 6, "BatteryRackMetal": 8,
                    "BatteryBankWood": 12, "BatteryBankMetal": 16}
# Storage stands at the back of its square, as the game's own shelves and cabinets do, so that
# against a wall on the square's north edge it stands against the wall: this far north of the
# centre, which leaves a box's propped lid and a rack's back brace just short of the edge.
STORAGE_NORTH = {"BatteryBoxWood": 0.18, "BatteryBoxMetal": 0.18, "BatteryRackWood": 0.22, "BatteryRackMetal": 0.22,
                 "BatteryBankWood": 0.22, "BatteryBankMetal": 0.22}


def _storage(item, facing):
    """A storage's tile facing `facing`, its battery overlays by look, each a list by slot, and its
    meter overlays by level."""
    build, at, turn = items.STORAGE[item], _turned((0, STORAGE_NORTH[item], 0), facing), FACING_TURN[facing]
    batteries = {look: [_battery_overlay(build, at, turn, slot, look) for slot in range(STORAGE_CAPACITY[item])]
                 for look in items.BANK_BATTERY_LOOKS}
    return [layer(build, at=at, turn=turn)], batteries, [_overlay(build, at, turn, meter_level=level) for level in range(1, 6)]


for item, base, first_batteries, first_meter in STORAGE_TILES:
    TILES[base], batteries, meter = _storage(item, "S")
    for look, first_battery in zip(items.BANK_BATTERY_LOOKS, first_batteries):
        for slot, overlay in enumerate(batteries[look]):
            TILES[first_battery + slot] = overlay
    for level, overlay in enumerate(meter):
        TILES[first_meter + level] = overlay

# The storage in all four facings, which the placing cursor turns it through as it does the game's
# furniture. The cursor finds a facing's tile by its number in the same tileset, at most 96 away
# (ISMoveableSpriteProps.getFaces, IsoWorld.SetCustomPropertyValues), and the tiles above, which a
# save's storage stands on, have no free numbers that near. So each storage, in STORAGE_TILES'
# order, has four tiles in FACINGS' order from TURNED_STORAGE_FIRST, its S one drawn as the tile
# above and taking its overlays. The other facings' overlays fill renewable_energy_02 facing by
# facing, storage by storage: each look's batteries by slot, then the meter where it shows. The
# meter is on the storage's front, which the camera, from the south-east, sees only facing S or E;
# facing N or W the storage hides every LED.
FACINGS = "SENW"
METER_FACINGS = "SE"
TURNED_STORAGE_FIRST = 340
TILES_02 = {}
for f, facing in enumerate(FACINGS):
    for i, (item, *_) in enumerate(STORAGE_TILES):
        TILES[TURNED_STORAGE_FIRST + len(FACINGS) * i + f], batteries, meter = _storage(item, facing)
        if facing == "S":
            continue
        for look in items.BANK_BATTERY_LOOKS:
            for overlay in batteries[look]:
                TILES_02[len(TILES_02)] = overlay
        for overlay in meter if facing in METER_FACINGS else ():
            TILES_02[len(TILES_02)] = overlay

# Biogas digesters: a base tile each, then their gas holders' overlays. The barrel digester has a tile
# for each of the game's drums it may be built from (Sprites.digester.barrel); its holder overlays fit
# them all, which share one outline. Level n of a holder shows it that full, from slack to taut; the
# insulated digester's shows its floating drum risen to n.
TILES[228] = [layer(items.barrel_digester)]  # the Metal Drum, the builder's default
for index, look in ((229, "Mov_OrangeBarrel"), (277, "Mov_DarkGreenBarrel"), (278, "Mov_LightGreenBarrel")):
    TILES[index] = [layer(items.barrel_digester, look=look)]
TILES[230] = [layer(items.insulated_digester)]
TILES[231] = [layer(items.dome_digester)]
for holder, first in (("bags", 232), ("tarp", 236)):
    for fill in (1, 2, 3):
        TILES[first + fill - 1] = _overlay(items.barrel_digester, (0, 0, 0), holder=holder, fill=fill)
    TILES[first + 3] = _overlay(items.barrel_digester, (0, 0, 0), holder=holder, torn=True)
for level in range(1, 5):
    TILES[239 + level] = _overlay(items.insulated_digester, (0, 0, 0), level=level)
# The scrubber fitted to each digester, drawn over its tile.
TILES[247] = _overlay(items.barrel_digester, (0, 0, 0), scrubber=True)
TILES[248] = _overlay(items.insulated_digester, (0, 0, 0), scrubber=True)
TILES[249] = _overlay(items.dome_digester, (0, 0, 0), scrubber=True)

# The gas heater, off and lit, as a save's heaters stand; then, for the placing cursor to turn it
# as it turns the storage, off in each of FACINGS from TURNED_HEATER_FIRST, then lit in each.
TILES[244] = [layer(items.gas_heater)]
TILES[245] = [layer(items.gas_heater, lit=True)]
TURNED_HEATER_FIRST = TURNED_STORAGE_FIRST + len(FACINGS) * len(STORAGE_TILES)
for s, lit in enumerate((False, True)):
    for f, facing in enumerate(FACINGS):
        TILES[TURNED_HEATER_FIRST + len(FACINGS) * s + f] = [layer(items.gas_heater, lit=lit, turn=FACING_TURN[facing])]

# The gas kit fitted to a generator: an overlay on the game's own generator tiles, so it has no
# base of the mod's to hold out. The first lies on the floor at the front corner of a generator the
# game doesn't know; from GENERATOR_KIT_FIRST, one sits on the air intake of each of the game's
# generator bodies in each facing (Sprites.generatorFittings).
GENERATOR_BODIES = ("frame", "old", "inverter")
GENERATOR_KIT_FIRST = 280
GENERATOR_PIPE_FIRST = GENERATOR_KIT_FIRST + 4 * len(GENERATOR_BODIES)
TILES[246] = [layer(items.generator_gas_kit)]
for b, body in enumerate(GENERATOR_BODIES):
    for f, facing in enumerate("NESW"):
        TILES[GENERATOR_KIT_FIRST + 4 * b + f] = [layer(items.generator_gas_kit, body=body, facing=facing)]

# Gasifiers: each tier's tile, then its lit overlay. The pipe overlays on its square, one by the
# direction of the generator they run to, rise off the filter's outlet, which is in one place in
# every tier; the preview draws them over the drum's. The pipe's other half lies on the generator's
# square with the kit, one by the direction of the gasifier it comes from: four for a generator the
# game doesn't know, then from GENERATOR_PIPE_FIRST four for each body and facing.
for offset, tier in enumerate(("primitive", "standard", "advanced")):
    TILES[250 + offset] = [layer(items.gasifier, tier=tier)]
    TILES[253 + offset] = [layer(items.gasifier, holdout=True, tier=tier), layer(items.gasifier, frame=False, tier=tier, lit=True)]
for offset, side in enumerate("NESW"):
    TILES[256 + offset] = [layer(items.gasifier, holdout=True, tier="standard"),
                           layer(items.gasifier, frame=False, tier="standard", pipe=side)]
    TILES[260 + offset] = [layer(items.generator_gas_pipe, side=side)]
    for b, body in enumerate(GENERATOR_BODIES):
        for f, facing in enumerate("NESW"):
            TILES[GENERATOR_PIPE_FIRST + 16 * b + 4 * f + offset] = [layer(items.generator_gas_pipe, side=side, body=body, facing=facing)]

# The scoop rotor wind charger as a tile: what the object is and how the build menu shows it. In
# play the game draws its sprite model (items.SPRITE_MODELS) instead, and spins that.
TILES[264] = [layer(items.scoop_rotor)]

# The blade machines, one tile per facing in Sprites.lua's N, E, S, W order, each its sprite
# model's first spin step: the treadmill wind charger with wooden and pipe blades, the homebuilt
# wind turbine with steel blades, the treadmill charger with steel blades, then the turbine with
# wooden and pipe blades, then the car alternator wind charger with each. They stand taller than a
# tile's sprite can draw, so the tiles show them shrunk to fit, whole; in play the game draws
# their sprite models at full size.
WIND_TILE_SCALE = {"Propeller": 0.55, "CarAlternator": 0.55, "Alternator": 0.48}
WIND_TILES = ((265, items.propeller_charger, "Propeller", "wood"), (269, items.propeller_charger, "Propeller", "pipe"),
              (273, items.alternator_charger, "Alternator", "steel"), (372, items.propeller_charger, "Propeller", "steel"),
              (397, items.alternator_charger, "Alternator", "wood"), (401, items.alternator_charger, "Alternator", "pipe"),
              (405, items.car_alternator_charger, "CarAlternator", "wood"),
              (409, items.car_alternator_charger, "CarAlternator", "pipe"),
              (413, items.car_alternator_charger, "CarAlternator", "steel"))
for first, build, model, blades in WIND_TILES:
    for offset, facing in enumerate("NESW"):
        TILES[first + offset] = [layer(build, turn=FACING_TURN[facing], scale=WIND_TILE_SCALE[model], blades=blades)]

# Each tileset's tiles by number.
TILESETS = {"renewable_energy_01": TILES, "renewable_energy_02": TILES_02}

# Build-menu icons by the name after RenewableEnergy_Build_: each digester as it stands built and
# working, its holder full, each gasifier and each wind charger.
BUILD_ICONS = {
    "BarrelDigester": [layer(items.barrel_digester, holder="bags")],
    "InsulatedDigester": [layer(items.insulated_digester, level=3)],
    "BrickDome": [layer(items.dome_digester)],
    "PrimitiveGasifier": [layer(items.gasifier, tier="primitive")],
    "Gasifier": [layer(items.gasifier, tier="standard")],
    "AdvancedGasifier": [layer(items.gasifier, tier="advanced")],
    "ScoopRotor": [layer(items.scoop_rotor)],
    "Propeller": [layer(items.propeller_charger)],
    "CarAlternator": [layer(items.car_alternator_charger)],
    "Alternator": [layer(items.alternator_charger)],
}
