"""What each tile of renewable_energy_01 shows, built from the item builders.

The index of each entry is the tile's number, which Lua reads through
media/lua/shared/RenewableEnergy/Sprites.lua and tools/make_tiles.py gives properties; keep the
three in step. A tile is a list of layers. A layer marked `holdout` is drawn invisible: an overlay
tile renders the object it sits on that way, so it keeps only the pixels the object doesn't hide.

Tile coordinates are a square one metre wide centred on the origin: its north edge is y = +0.5 and
its west edge x = -0.5 (see kit.py).
"""
import items


def layer(build, holdout=False, at=(0, 0, 0), turn=0, **options):
    return {"build": build, "options": options, "at": at, "turn": turn, "holdout": holdout}


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


def _overlay(build, **options):
    return [layer(build, holdout=True), layer(build, frame=False, **options)]


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

# Battery storage: the item type, its tile, its first battery overlay and its first meter
# overlay. Overlay n of the batteries shows n of them, overlay n of the meter n LEDs lit.
STORAGE_TILES = (
    ("BatteryBoxWood", 8, 36, 48),
    ("BatteryBoxMetal", 23, 38, 53),
    ("BatteryRackWood", 32, 73, 58),
    ("BatteryRackMetal", 33, 79, 63),
    ("BatteryBankWood", 34, 87, 68),
    ("BatteryBankMetal", 9, 99, 40),
)
STORAGE_CAPACITY = {"BatteryBoxWood": 2, "BatteryBoxMetal": 2, "BatteryRackWood": 6, "BatteryRackMetal": 8,
                    "BatteryBankWood": 12, "BatteryBankMetal": 16}
for item, base, first_battery, first_meter in STORAGE_TILES:
    build = items.STORAGE[item]
    TILES[base] = [layer(build)]
    for count in range(1, STORAGE_CAPACITY[item] + 1):
        TILES[first_battery + count - 1] = _overlay(build, batteries=count)
    for level in range(1, 6):
        TILES[first_meter + level - 1] = _overlay(build, meter_level=level)
