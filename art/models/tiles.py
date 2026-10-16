"""What each tile of renewable_energy_01 shows, built from the item builders.

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

# A wall panel's bottom edge, above the floor.
WALL_PANEL_HEIGHT = 1.1


def _wall(material, facing, cracks=False):
    """On the square's north edge facing south, or on its west edge facing east. `cracks` makes the
    overlay of the cracks in its glass."""
    at = (0, 0.5, WALL_PANEL_HEIGHT) if facing == "S" else (-0.5, 0, WALL_PANEL_HEIGHT)
    turn = FACING_TURN[facing]
    if cracks:
        return [layer(items.solar_wall, holdout=True, material=material, at=at, turn=turn),
                layer(items.solar_wall, material=material, cracks=True, at=at, turn=turn)]
    return [layer(items.solar_wall, material=material, at=at, turn=turn)]


def _rack(material, facing, snow=False, cracks=None):
    """`snow` makes the overlay of the snow on it, `cracks` (a module slot) that of the cracks in
    one module's glass."""
    turn = FACING_TURN[facing]
    if snow or cracks:
        return [layer(items.solar_rack, holdout=True, material=material, turn=turn),
                layer(items.solar_rack, material=material, snow=snow, cracks=cracks, turn=turn)]
    return [layer(items.solar_rack, material=material, turn=turn)]


def _overlay(build, at, **options):
    return [layer(build, holdout=True, at=at), layer(build, frame=False, at=at, **options)]


def _battery_overlay(build, at, slot, look):
    """The battery in `slot` (from 0) as `look`, and its link to the one before. A bank draws its
    batteries' overlays in slot order, so this one keeps out from behind the storage and the
    batteries in the slots before it, and draws over any in front of it."""
    return [layer(build, holdout=True, at=at), layer(build, holdout=True, frame=False, batteries=slot, at=at),
            layer(build, frame=False, slot=slot, look=look, at=at)]


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
}
for material, first_wall, first_rack, first_snow in (("metal", 1, 3, 17), ("wood", 21, 24, 28)):
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = _wall(material, facing)
    for offset, facing in enumerate("SENW"):
        TILES[first_rack + offset] = _rack(material, facing)
        TILES[first_snow + offset] = _rack(material, facing, snow=True)
# Cracked glass: a wall panel's per facing, and a rack's per facing and module slot, slot 1 first.
for material, first_wall, first_rack in (("metal", 116, 120), ("wood", 118, 128)):
    for offset, facing in enumerate("SE"):
        TILES[first_wall + offset] = _wall(material, facing, cracks=True)
    for offset, facing in enumerate("SENW"):
        for slot in (1, 2):
            TILES[first_rack + 2 * offset + slot - 1] = _rack(material, facing, cracks=slot)

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
for item, base, first_batteries, first_meter in STORAGE_TILES:
    build, at = items.STORAGE[item], (0, STORAGE_NORTH[item], 0)
    TILES[base] = [layer(build, at=at)]
    for look, first_battery in zip(items.BANK_BATTERY_LOOKS, first_batteries):
        for slot in range(STORAGE_CAPACITY[item]):
            TILES[first_battery + slot] = _battery_overlay(build, at, slot, look)
    for level in range(1, 6):
        TILES[first_meter + level - 1] = _overlay(build, at, meter_level=level)

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

# The gas heater, off and lit, one facing.
TILES[244] = [layer(items.gas_heater)]
TILES[245] = [layer(items.gas_heater, lit=True)]
# The gas kit fitted to a generator: an overlay on the game's own generator tiles, so it has no
# base of the mod's to hold out. Tile 246 lies on the floor at the front corner of a generator the
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
# square with the kit, one by the direction of the gasifier it comes from: 260 to 263 for a
# generator the game doesn't know, from GENERATOR_PIPE_FIRST four for each body and facing.
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

# The propeller and alternator chargers, wooden and pipe propellers first, one tile per facing in
# Sprites.lua's N, E, S, W order, each its sprite model's first spin step. They stand taller than a
# tile's sprite can draw, so the tiles show them shrunk to fit, whole; in play the game draws their
# sprite models at full size.
WIND_TILE_SCALE = {"Propeller": 0.55, "Alternator": 0.48}
for first, build, scale, options in ((265, items.propeller_charger, WIND_TILE_SCALE["Propeller"], {"blades": "wood"}),
                                     (269, items.propeller_charger, WIND_TILE_SCALE["Propeller"], {"blades": "pipe"}),
                                     (273, items.alternator_charger, WIND_TILE_SCALE["Alternator"], {})):
    for offset, facing in enumerate("NESW"):
        TILES[first + offset] = [layer(build, turn=FACING_TURN[facing], scale=scale, **options)]

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
    "Alternator": [layer(items.alternator_charger)],
}
