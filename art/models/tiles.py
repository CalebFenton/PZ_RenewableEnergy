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


def _rack(facing, snow=False):
    turn = FACING_TURN[facing]
    if snow:
        return [layer(items.solar_rack, holdout=True, turn=turn), layer(items.solar_rack, snow=True, turn=turn)]
    return [layer(items.solar_rack, turn=turn)]


def _bank_overlay(**options):
    return [layer(items.battery_bank, holdout=True), layer(items.battery_bank, frame=False, **options)]


TILES = {
    0: [layer(items.solar_flat)],
    # On the square's north edge facing south, and on its west edge facing east.
    1: [layer(items.solar_wall, at=(0, 0.5, WALL_PANEL_HEIGHT))],
    2: [layer(items.solar_wall, at=(-0.5, 0, WALL_PANEL_HEIGHT), turn=FACING_TURN["E"])],
    3: _rack("S"),
    4: _rack("E"),
    5: _rack("N"),
    6: _rack("W"),
    # The failsafe shares the generator's square, so it sits in the corner nearest the viewer's
    # left, where the generator doesn't cover it.
    7: [layer(items.solar_failsafe, at=(-0.28, -0.3, 0), turn=-20)],
    8: [layer(items.battery_box)],
    9: [layer(items.battery_bank)],
    10: [layer(items.solar_cell_charger, turn=-15)],
    11: [layer(items.solar_crate)],
    12: [layer(items.solar_crate, holdout=True), layer(items.solar_crate, box_=False, contents=True)],
    13: [layer(items.solar_crate, holdout=True), layer(items.solar_crate, box_=False, closed=True)],
    16: [layer(items.solar_flat, holdout=True), layer(items.solar_flat, snow=True)],
    17: _rack("S", snow=True),
    18: _rack("E", snow=True),
    19: _rack("N", snow=True),
    20: _rack("W", snow=True),
    36: [layer(items.battery_box, holdout=True), layer(items.battery_box, frame=False, batteries=1)],
    37: [layer(items.battery_box, holdout=True), layer(items.battery_box, frame=False, batteries=2)],
}
for count in range(1, 13):
    TILES[23 + count] = _bank_overlay(batteries=count)
for level in range(1, 6):
    TILES[39 + level] = _bank_overlay(meter_level=level)
