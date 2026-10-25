"""Biogas digesters, the scrubber, the gas heater, and the gas kit that runs a generator on gas."""
import math
import random

from kit import FACING_TURN, around, beam, box, cylinder, group, lathe, mound, prism, ring, tube
from palette import BANK_FADE, M
from parts import BOARD, DRUM, FEED_BUNG, GAS_BUNG, drum

# Biogas digesters ---------------------------------------------------------------------------------
#
# A digester is built where it stands and never carried, so each is laid out on its square about the
# square's centre, not its own. Its gas holder shows on overlay tiles: a builder takes `frame` (the
# digester itself) and the holder's state, so a tile can draw the digester alone and an overlay
# just the holder.

# The barrel stands in the west corner of its square and its holder in the east, side by side as the
# viewer sees them.
BARREL_AT = (-0.21, -0.21)
# The side its sludge spigot faces, in degrees from east.
SPIGOT_ANGLE = -40
# Where the gas hose comes down off the barrel's head to the holder on the ground.
HOLDER_INLET = (0.06, 0.06)


def _funnel(col, name, x, y, z):
    """The recipe's funnel, its foot at (x, y, z), and its dark mouth."""
    cylinder(col, name + "_Funnel", M("funnel"), 0.03, 0.12, at=(x, y, z), radius_top=0.1, segments=18)
    cylinder(col, name + "_FunnelMouth", M("black"), 0.088, 0.003, at=(x, y, z + 0.118), segments=18)


def _gas_valve(col, name, x, y, z, side):
    """A copper gas valve standing at (x, y, z), its red lever out to `side` (-1 or 1) along X."""
    cylinder(col, name + "_GasValve", M("copper"), 0.014, 0.05, at=(x, y, z), segments=10)
    box(col, name + "_GasLever", M("red"), (0.07, 0.014, 0.01), at=(x + side * 0.03, y, z + 0.03))


def barrel_digester(col, look="MetalDrum", frame=True, holder=None, fill=3, torn=False, scrubber=False):
    """A homestead batch digester: a 55 gallon drum of slurry, any of the game's four (DRUM_LOOKS,
    by `look`), fed through a funnel taped into its big bung, the recipe's rubber hose run down
    inside it to near the bottom so feeding lets no gas out; emptied at a spigot near its foot; its
    gas taken off the small bung through a valve and a hose down to a holder on the ground beside
    it. `holder` draws the holder alone, "bags" or "tarp", `fill` its level from 1 (slack) to 3
    (taut), `torn` it ripped and empty. `scrubber` draws the scrubber alone, in front of the barrel
    where neither it nor the holder hides it, teed off the head and led on to the holder."""
    radius, height = DRUM
    x, y = BARREL_AT
    if frame:
        drum(col, "Barrel", BARREL_AT, look)
        fx, fy = x + FEED_BUNG[0], y + FEED_BUNG[1]
        cylinder(col, "Barrel_FeedBung", M("darkgrey"), 0.042, 0.012, at=(fx, fy, height), segments=14)
        cylinder(col, "Barrel_FeedTape", M("ducttape"), 0.034, 0.04, at=(fx, fy, height + 0.012), segments=14)
        _funnel(col, "Barrel", fx, fy, height + 0.05)
        gx, gy = x + GAS_BUNG[0], y + GAS_BUNG[1]
        cylinder(col, "Barrel_GasBung", M("darkgrey"), 0.026, 0.012, at=(gx, gy, height), segments=12)
        _gas_valve(col, "Barrel", gx, gy, height + 0.012, -1)
        hx, hy = HOLDER_INLET
        run = math.hypot(hx - x, hy - y)
        ux, uy = (hx - x) / run, (hy - y) / run
        ex, ey = x + ux * (radius + 0.035), y + uy * (radius + 0.035)
        tube(col, "Barrel_Hose", M("rubberhose"), [(gx, gy, height + 0.06), (gx + ux * 0.04, gy + uy * 0.04, height + 0.12),
                                              (ex - ux * 0.05, ey - uy * 0.05, height + 0.09), (ex, ey, height - 0.06),
                                              (ex + ux * 0.015, ey + uy * 0.015, 0.4), (hx - ux * 0.02, hy - uy * 0.02, 0.12),
                                              (hx, hy, 0.04)], 0.014, 8)
        sx, sy = around(BARREL_AT, SPIGOT_ANGLE, radius)
        ox, oy = around((0, 0), SPIGOT_ANGLE, 1)
        tube(col, "Barrel_Spigot", M("galvanised"), [(sx - ox * 0.01, sy - oy * 0.01, 0.1), (sx + ox * 0.05, sy + oy * 0.05, 0.1)],
             0.012, 8)
        box(col, "Barrel_SpigotValve", M("copper"), (0.034, 0.034, 0.034), at=(sx + ox * 0.045, sy + oy * 0.045, 0.083),
            rotate=(0, 0, SPIGOT_ANGLE))
        box(col, "Barrel_SpigotLever", M("red"), (0.08, 0.014, 0.01), at=(sx + ox * 0.045, sy + oy * 0.045, 0.117),
            rotate=(0, 0, SPIGOT_ANGLE + 90))
        tube(col, "Barrel_Spout", M("galvanised"), [(sx + ox * 0.06, sy + oy * 0.06, 0.095), (sx + ox * 0.078, sy + oy * 0.078, 0.08),
                                                    (sx + ox * 0.08, sy + oy * 0.08, 0.05)], 0.009, 8)
        mound(col, "Barrel_Spill", M("sludge"), (0.085, 0.055, 0.006), at=(sx + ox * 0.1, sy + oy * 0.1, 0),
              rotate=(0, 0, SPIGOT_ANGLE), lumps=0.2, seed=5)
    if holder == "bags":
        _garbage_bags(col, fill, torn)
    elif holder == "tarp":
        _tarp_bag(col, fill, torn)
    if scrubber:
        tee = (x + 0.17, y - 0.1)
        cylinder(col, "Barrel_ScrubberTee", M("copper"), 0.014, 0.04, at=(*tee, height), segments=10)
        inlet, outlet = _scrubber(col, (0.32, -0.33), (0.45, -0.21))
        tube(col, "Barrel_ScrubberHose", M("rubberhose"), [(*tee, height + 0.04), (tee[0] + 0.05, tee[1] - 0.04, height + 0.08),
                                                      (0.24, -0.27, 0.6), inlet], 0.012, 8)
        # Back into the holder's south end, where the bags and the tarp both lie.
        tube(col, "Barrel_ScrubberReturn", M("rubberhose"), [outlet, (outlet[0], outlet[1] + 0.03, outlet[2] + 0.04),
                                                        (0.4, -0.08, 0.12), (0.36, -0.02, 0.04)], 0.012, 8)


# The garbage bags' centres, half lengths and widths, and turns: three lying round the hose's end,
# their necks gathered and taped round it, taped to each other where they touch.
BAGS = (((0.04, 0.3), (0.21, 0.14), 0), ((0.3, 0.04), (0.21, 0.14), 90), ((0.3, 0.3), (0.17, 0.16), 45))
BAG_HEIGHTS = (0.08, 0.15, 0.23)
BAG_LUMPS = (0.28, 0.12, 0.03)


def _garbage_bags(col, fill, torn):
    """Black garbage bags taped into one holder, creased and slack at `fill` 1, taut at 3, or
    split open and lying flat when `torn`."""
    height = 0.026 if torn else BAG_HEIGHTS[fill - 1]
    lumps = 0.25 if torn else BAG_LUMPS[fill - 1]
    swell = 1.08 if fill == 3 and not torn else 1.0
    for i, ((bx, by), (rx, ry), turn) in enumerate(BAGS):
        mound(col, "Bags_Bag", M("garbagebag"), (rx * swell, ry * swell, height), at=(bx, by, 0), rotate=(0, 0, turn),
              lumps=lumps, seed=10 + i, segments=20, rings=5)
        if torn:
            # The split, the ground showing through it, and a flap of the bag lifting off it.
            mound(col, "Bags_Split", M("earth"), (rx * 0.45, ry * 0.25, height * 1.3), at=(bx, by, 0), rotate=(0, 0, turn + 15),
                  lumps=0.2, seed=13 + i, segments=10, rings=3)
            flap_x, flap_y = around((bx, by), turn + 15 + 90, ry * 0.25)
            prism(col, "Bags_Flap", M("garbagebag"), [(-0.06, 0), (0.07, 0), (0.0, 0.08)], 0.003,
                  at=(flap_x, flap_y, height * 1.1), rotate=(55, 0, turn + 15))
    hx, hy = HOLDER_INLET
    neck = 0.03 if torn else 0.09
    cylinder(col, "Bags_Neck", M("garbagebag"), 0.045, neck, at=(hx, hy, 0), radius_top=0.02, segments=10)
    cylinder(col, "Bags_NeckTape", M("ducttape"), 0.025, 0.03, at=(hx, hy, neck - 0.035), segments=10)
    # Tape across each join, dipping into the crease between the two bags.
    for a, b in ((0, 1), (0, 2), (1, 2)):
        (ax, ay), _, _ = BAGS[a]
        (bx, by), _, _ = BAGS[b]
        points = [(ax + (bx - ax) * t, ay + (by - ay) * t, height * z + 0.004) for t, z in ((0.32, 0.8), (0.5, 0.55), (0.68, 0.8))]
        for start, end in zip(points, points[1:]):
            beam(col, "Bags_Tape", M("ducttape"), start, end, (0.05, 0.003))


TARP_AT = (0.25, 0.25)
TARP = (0.21, 0.19)  # half its length and width
TARP_HEIGHTS = (0.06, 0.13, 0.2)


def _tarp_bag(col, fill, torn):
    """A pillow sewn from a blue poly tarp, a hem round it with a grommet at each corner and a hose
    barb in the corner nearest the barrel: soft and creased at `fill` 1, filled square at 3, or flat
    and ripped across when `torn`."""
    cx, cy = TARP_AT
    rx, ry = TARP
    height = 0.022 if torn else TARP_HEIGHTS[fill - 1]
    lumps = 0.3 if torn else (0.2, 0.08, 0.02)[fill - 1]
    squareness = 1.6 if torn else (1.8, 2.2, 2.6)[fill - 1]
    mound(col, "Tarp_Bag", M("tarp"), (rx, ry, height), at=(cx, cy, 0), squareness=squareness, lumps=lumps, seed=20,
          segments=24, rings=6)
    mound(col, "Tarp_Hem", M("tarp"), (rx + 0.03, ry + 0.03, 0.012), at=(cx, cy, 0), squareness=4, segments=24, rings=2)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder(col, "Tarp_Grommet", M("lead"), 0.01, 0.014, at=(cx + sx * (rx + 0.01), cy + sy * (ry + 0.01), 0), segments=8)
    hx, hy = HOLDER_INLET
    tube(col, "Tarp_Barb", M("galvanised"), [(hx, hy, 0.04), (cx - rx * 0.78, cy - ry * 0.78, min(height, 0.05))], 0.011, 8)
    if torn:
        mound(col, "Tarp_Rip", M("earth"), (rx * 0.6, 0.03, height * 1.3), at=(cx + 0.02, cy - 0.02, 0), rotate=(0, 0, -30),
              lumps=0.2, seed=22, segments=10, rings=3)
        prism(col, "Tarp_Flap", M("tarp"), [(-0.09, 0), (0.09, 0), (0.02, 0.07)], 0.003, at=(cx + 0.03, cy - 0.05, height),
              rotate=(60, 0, -30))


# The box's width and height: as tight round the 55 gallon drum as a hand's depth of straw allows,
# and tall enough for the straw to bury it to its head.
INSULATED = (0.8, 0.84)
INSULATED_GAP = 0.006  # between its boards
FLOAT_DRUM = (0.24, 0.62)  # a 30 gallon drum's radius and height
# The floating drum's head above the slurry drum's, by gas level: only its top pokes out of the
# straw, as the gas fills it, so the digester stays packed in to its head. And the guide pipe's top.
FLOAT_RISE = (0.03, 0.07, 0.11, 0.15)
GUIDE_TOP = DRUM[1] + FLOAT_RISE[-1] + 0.12
# The feed funnel, on the box's north-east corner, and where its pipe enters the drum's side.
INSULATED_FEED = (0.26, 0.26)
INSULATED_INLET = (0.19, 0.19)


def insulated_digester(col, frame=True, level=0, scrubber=False):
    """A floating-drum digester of the village kind, built for a cold winter: the slurry in a 55
    gallon drum standing in a box of planks, straw packed round it and heaped over it to its head,
    a guide pipe standing up out of the slurry, fed through a funnel on the box's corner whose pipe
    runs down through the straw into the drum's side. The gas holder is a smaller drum turned upside
    down in the slurry, riding up the pipe as gas fills it: `level` draws it alone at its height from
    1 (low) to 4 (high), its gas valve and hose on its head. `scrubber` draws the scrubber alone: the
    box fills its square, so it stands on the front corner of the box's top, clear of both drums,
    fed from a fitting on the slurry drum's rim outside the floating drum."""
    size, height = INSULATED
    radius, rim = DRUM
    if frame:
        _straw_box(col)
        cylinder(col, "Insulated_Drum", M("drummetal"), radius, rim, segments=32)
        ring(col, "Insulated_Chime", M("weld"), (0, 0), radius, rim, 0.011)
        cylinder(col, "Insulated_Slurry", M("sludge"), radius - 0.006, 0.002, at=(0, 0, rim), segments=28)
        cylinder(col, "Insulated_Guide", M("galvanised"), 0.021, GUIDE_TOP - rim, at=(0, 0, rim), segments=10)
        cylinder(col, "Insulated_GuideCap", M("galvanised"), 0.028, 0.025, at=(0, 0, GUIDE_TOP), segments=10)
        fx, fy = INSULATED_FEED
        tube(col, "Insulated_FeedPipe", M("pvc"), [(fx, fy, height + 0.06), (fx, fy, height), (*INSULATED_INLET, rim - 0.16)], 0.024, 12)
        cylinder(col, "Insulated_FeedTape", M("ducttape"), 0.03, 0.04, at=(fx, fy, height + 0.03), segments=14)
        _funnel(col, "Insulated", fx, fy, height + 0.06)
    if level:
        top = rim + FLOAT_RISE[level - 1]
        float_radius, float_height = FLOAT_DRUM
        cylinder(col, "Insulated_Float", M("drummetal"), float_radius, float_height, at=(0, 0, top - float_height), segments=32)
        cylinder(col, "Insulated_FloatHoop", M("drummetal"), float_radius + 0.007, 0.022, at=(0, 0, top - float_height / 2 - 0.01),
                 segments=32)
        ring(col, "Insulated_FloatChime", M("weld"), (0, 0), float_radius - 0.002, top + 0.002, 0.01)
        cylinder(col, "Insulated_Sleeve", M("galvanised"), 0.034, 0.07, at=(0, 0, top), segments=10)
        vx, vy = -0.1, -0.12
        _gas_valve(col, "Insulated", vx, vy, top, 1)
        # The hose to the stove, slack enough for the drum's whole rise, over the box's front.
        front = -size / 2
        tube(col, "Insulated_Hose", M("rubberhose"), [(vx, vy, top + 0.05), (vx - 0.04, vy - 0.06, top + 0.09),
                                                 (-0.27, front + 0.05, height + 0.07), (-0.29, front - 0.03, height - 0.05),
                                                 (-0.3, front - 0.035, 0.25), (-0.33, front - 0.06, 0.03)], 0.014, 8)
    if scrubber:
        base = height + 0.02
        fitting = around((0, 0), -45, radius - 0.015)
        cylinder(col, "Insulated_ScrubberFitting", M("copper"), 0.012, 0.04, at=(*fitting, rim), segments=10)
        inlet, outlet = _scrubber(col, (0.28, -0.28), (0.06, -0.34), z=base)
        tube(col, "Insulated_ScrubberHose", M("rubberhose"), [(*fitting, rim + 0.04), (fitting[0] + 0.03, fitting[1] - 0.03, rim + 0.12),
                                                         (inlet[0] - 0.03, inlet[1] + 0.03, inlet[2] + 0.08), inlet], 0.012, 8)
        tube(col, "Insulated_ScrubberOut", M("rubberhose"), [outlet, (outlet[0] + 0.02, outlet[1] - 0.06, outlet[2] + 0.02),
                                                        (0.1, -size / 2 - 0.03, height - 0.05), (0.11, -size / 2 - 0.035, 0.25),
                                                        (0.13, -size / 2 - 0.06, 0.03)], 0.012, 8)


def _straw_box(col):
    """Weathered planks nailed round the drum to corner posts, butted close, each a little off true
    as boards nailed up by hand are, nail heads at their ends, a batten down the middle of each side,
    and straw packed inside and heaped over the top to the drum's head. The inside is dark, so the
    hairline gaps between boards read as shadow."""
    size, height = INSULATED
    rows = 5
    board = (height - (rows - 1) * INSULATED_GAP) / rows
    shades = ("planks", "planksdark")
    post = 0.05
    box(col, "Insulated_Core", M("planksdark"), (size - 0.03, size - 0.03, height - 0.01))
    mound(col, "Insulated_StrawTop", M("straw"), (size / 2 - 0.02, size / 2 - 0.02, 0.06), at=(0, 0, height - 0.03),
          squareness=3, lumps=0.1, seed=30, segments=24, rings=5)
    # Corner posts inside the boards, which are nailed to them.
    inside = size / 2 - BOARD - post / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(col, "Insulated_Post", M("planksdark"), (post, post, height), at=(sx * inside, sy * inside, 0), bevel=0.005)
    rng = random.Random(32)
    for row in range(rows):
        z = row * (board + INSULATED_GAP)
        for sign in (-1, 1):
            lift, tilt = rng.uniform(-0.004, 0.004), rng.uniform(-0.6, 0.6)
            box(col, "Insulated_FrontBack", M(shades[row % 2]), (size, BOARD, board), at=(0, sign * (size - BOARD) / 2, z + lift),
                rotate=(0, tilt, 0), bevel=0.005)
            lift, tilt = rng.uniform(-0.004, 0.004), rng.uniform(-0.6, 0.6)
            box(col, "Insulated_Side", M(shades[(row + 1) % 2]), (BOARD, size - 2 * BOARD, board),
                at=(sign * (size - BOARD) / 2, 0, z + lift), rotate=(tilt, 0, 0), bevel=0.005)
        # The nail heads the viewer sees, on the front (-Y) and east (+X) faces: into the posts at
        # each end, and through the battens.
        for up in (0.3, 0.7):
            nz = z + board * up
            for along, proud in ((-inside, 0), (inside, 0), (-0.05, 0.022)):
                cylinder(col, "Insulated_Nail", M("nail"), 0.006, 0.003, at=(along, -size / 2 - proud - 0.001, nz),
                         rotate=(90, 0, 0), segments=6)
            for along, proud in ((-inside, 0), (inside, 0), (-0.05, 0.022)):
                cylinder(col, "Insulated_Nail", M("nail"), 0.006, 0.003, at=(size / 2 + proud + 0.001, along, nz),
                         rotate=(0, 90, 0), segments=6)
    for sign in (-1, 1):
        box(col, "Insulated_Batten", M("planksdark"), (0.07, 0.022, height), at=(0.05 * sign, sign * (size / 2 + 0.011), 0), bevel=0.005)
        box(col, "Insulated_Batten", M("planksdark"), (0.022, 0.07, height), at=(sign * (size / 2 + 0.011), -0.05 * sign, 0), bevel=0.005)


# A real fixed dome holding the 4 m³ of gas the game gives it is 2 to 3 m across, its pit sunk in
# the ground and the dug earth banked back over its foot; on one square its dome fills the square,
# thigh high, bigger than the insulated digester beside it as it is in play.
DOME = (0.4, 0.6)  # the brick dome's radius and height
# The earth over its foot: how high it stands against the bricks and how far out from the dome's
# centre it runs, out to the square's sides; where round there it is grassed over and where it
# thins into the ground are the palette's BANK_TURF and BANK_FADE, which its material takes.
BANK = (0.3, 0.53)
BANK_TUFTS = 300
DOME_AT = (-0.02, 0.02)
BRICK = (0.2, 0.05, 0.068)  # a brick as laid: along the course, into the dome, up
# Where round the dome its feed pipe comes out, in degrees from east: towards the viewer.
DOME_FEED_ANGLE = -60


def dome_digester(col, frame=True, scrubber=False):
    """A fixed-dome digester of the Chinese kind: its pit sunk in the ground, the brick dome over it
    showing above the earth banked round its foot, a concrete collar on its crown and the gas pipe
    and valve out of that, its hose led off behind the dome, and the feed pipe climbing out of the
    bank to a funnel, as the other digesters are fed. `scrubber` draws the scrubber alone, on the
    ground at the square's back corner, teed off the gas pipe above the valve."""
    cx, cy = DOME_AT
    crown = DOME[1]
    if frame:
        _dome(col)
    if scrubber:
        tee = (cx + 0.03, cy + 0.03, crown + 0.17)
        tube(col, "Dome_ScrubberTee", M("galvanised"), [(cx, cy, tee[2]), tee], 0.014, 8)
        inlet, outlet = _scrubber(col, (0.37, 0.37), (0.43, 0.1))
        tube(col, "Dome_ScrubberHose", M("rubberhose"), [tee, (tee[0] + 0.08, tee[1] + 0.06, tee[2] + 0.03),
                                                         (0.24, 0.3, inlet[2] + 0.14), inlet], 0.012, 8)
        # On to the house, underground.
        tube(col, "Dome_ScrubberOut", M("rubberhose"), [outlet, (outlet[0] + 0.02, outlet[1] - 0.02, outlet[2] + 0.03),
                                                        (0.48, 0.02, 0.12), (0.49, 0.0, 0.02)], 0.012, 8)


def _dome(col):
    cx, cy = DOME_AT
    radius, rise = DOME
    # The mortar behind the bricks.
    mound(col, "Dome_Mortar", M("mortar"), (radius - 0.008, radius - 0.008, rise), segments=32, rings=10, at=(cx, cy, 0))
    # The bank: from the bricks' faces, falling away in a soft curve to nothing on the ground.
    height, reach = BANK
    foot = radius * math.sqrt(1 - (height / rise) ** 2) + 0.01

    def bank(out):
        return height * (1 + math.cos(math.pi * min(1.0, max(0.0, (out - foot) / (reach - foot))))) / 2

    steps = 10
    lathe(col, "Dome_Bank", M("domebank"), [(foot + (reach - foot) * i / steps, bank(foot + (reach - foot) * i / steps))
                                            for i in range(steps + 1)], at=(cx, cy, 0), lumps=0.08, seed=42, segments=48)
    # Grass comes up through it, but not where the feed pipe was dug in.
    rng = random.Random(43)
    for _ in range(BANK_TUFTS):
        azimuth = rng.uniform(0, 360)
        if abs((azimuth - DOME_FEED_ANGLE + 180) % 360 - 180) < 20:
            continue
        out = rng.uniform(foot + 0.03, BANK_FADE[1] - 0.01)
        x, y = around((cx, cy), azimuth, out)
        shade = M("grass" if rng.random() < 0.7 else "grassdry")
        for _ in range(rng.randint(3, 5)):
            tall = rng.uniform(0.04, 0.08)
            prism(col, "Dome_Grass", shade, [(-0.004, 0), (0.004, 0), (rng.uniform(-0.015, 0.015), tall)], 0.002,
                  at=(x + rng.uniform(-0.01, 0.01), y + rng.uniform(-0.01, 0.01), bank(out) - 0.01),
                  rotate=(0, 0, rng.uniform(0, 180)))
    rng = random.Random(41)
    polar, course = 0.0, 0
    while polar < math.radians(70):
        circle, z = radius * math.cos(polar), rise * math.sin(polar)
        tilt = math.degrees(math.atan2(math.sin(polar) / rise, math.cos(polar) / radius))
        count = max(6, round(2 * math.pi * circle / (BRICK[0] + 0.012)))
        # Courses the bank buries whole aren't laid: none of them would show.
        if z + BRICK[2] > height - 0.03:
            for k in range(count):
                azimuth = 360 * (k + 0.5 * (course % 2)) / count
                x, y = around((cx, cy), azimuth, circle)
                length = 2 * math.pi * circle / count - 0.012
                box(col, "Dome_Brick", M("brick" if rng.random() < 0.6 else "brickdark"), (length, BRICK[1], BRICK[2]),
                    at=(x, y, z), rotate=(tilt, 0, azimuth - 90))
        # The next course starts a brick and its mortar further up the curve.
        polar += (BRICK[2] + 0.01) / math.hypot(radius * math.sin(polar), rise * math.cos(polar))
        course += 1
    crown = rise
    cylinder(col, "Dome_Collar", M("concrete"), 0.17, 0.09, at=(cx, cy, crown - 0.07), radius_top=0.14, segments=24)
    pipe_top = crown + 0.2
    cylinder(col, "Dome_GasPipe", M("galvanised"), 0.016, pipe_top - crown, at=(cx, cy, crown), segments=10)
    box(col, "Dome_Valve", M("copper"), (0.04, 0.04, 0.04), at=(cx, cy, crown + 0.08))
    box(col, "Dome_GasLever", M("red"), (0.09, 0.014, 0.01), at=(cx + 0.035, cy, crown + 0.12))
    tube(col, "Dome_GasHose", M("rubberhose"), [(cx, cy, pipe_top), (cx - 0.02, cy + 0.04, pipe_top + 0.04),
                                                (cx - 0.1, cy + 0.12, pipe_top), (cx - 0.24, cy + 0.3, crown - 0.15),
                                                (-0.36, 0.44, 0.12), (-0.38, 0.48, 0.03)], 0.014, 8)
    # The feed: the recipe's pipe out of the dome's foot, bent up to stand clear of it, a funnel
    # taped into its end.
    lx, ly = around((cx, cy), DOME_FEED_ANGLE, radius - 0.03)
    bx, by = around((cx, cy), DOME_FEED_ANGLE, radius + 0.04)
    fx, fy = around((cx, cy), DOME_FEED_ANGLE, radius + 0.06)
    tube(col, "Dome_FeedPipe", M("pvc"), [(lx, ly, 0.1), (bx, by, 0.12), (fx, fy, 0.2), (fx, fy, 0.32)], 0.024, 12)
    cylinder(col, "Dome_FeedTape", M("ducttape"), 0.03, 0.04, at=(fx, fy, 0.29), segments=14)
    _funnel(col, "Dome", fx, fy, 0.32)


SCRUBBER_BUCKET = (0.12, 0.34)  # a 5 gallon bucket's radius at its rim and its height
SCRUBBER_CAN = (0.045, 0.2)  # the steel wool can's radius and height


def _scrubber(col, bucket_at, can_at, z=0.0, can_z=None):
    """A biogas scrubber: an orange 5 gallon bucket of water, its lid on, the gas bubbling in through
    one pipe stub and out of the other, then through a coffee can packed with steel wool, capped,
    that takes out the rotten-egg gas. The bucket stands at `bucket_at` on `z`, the can at `can_at`
    on `can_z` (default `z`). Returns the tops of the bucket's inlet stub and the can's outlet."""
    radius, height = SCRUBBER_BUCKET
    bx, by = bucket_at
    cylinder(col, "Scrubber_Bucket", M("safety"), radius * 0.88, height, at=(bx, by, z), radius_top=radius, segments=20)
    for rib in (0.5, 0.88):
        ring(col, "Scrubber_Rib", M("safety"), bucket_at, radius * (0.88 + 0.12 * rib), z + height * rib, 0.006)
    cylinder(col, "Scrubber_Lid", M("hdpe"), radius + 0.008, 0.022, at=(bx, by, z + height), segments=20)
    top = z + height + 0.022
    stubs = []
    for dx, dy in ((-0.05, 0.03), (0.05, -0.03)):
        cylinder(col, "Scrubber_Stub", M("pvc"), 0.013, 0.05, at=(bx + dx, by + dy, top), segments=10)
        stubs.append((bx + dx, by + dy, top + 0.05))
    can_radius, can_height = SCRUBBER_CAN
    cx, cy = can_at
    cz = z if can_z is None else can_z
    cylinder(col, "Scrubber_Can", M("galvanised"), can_radius, can_height, at=(cx, cy, cz), segments=16)
    cylinder(col, "Scrubber_CanLabel", M("red"), can_radius + 0.001, 0.07, at=(cx, cy, cz + 0.06), segments=16)
    cylinder(col, "Scrubber_CanCap", M("black"), can_radius + 0.004, 0.018, at=(cx, cy, cz + can_height), segments=16)
    can_top = cz + can_height + 0.018
    cylinder(col, "Scrubber_CanStub", M("pvc"), 0.011, 0.04, at=(cx - 0.015, cy, can_top), segments=10)
    cylinder(col, "Scrubber_CanOut", M("pvc"), 0.011, 0.04, at=(cx + 0.015, cy, can_top), segments=10)
    out = stubs[1]
    tube(col, "Scrubber_Hose", M("rubberhose"), [out, (out[0], out[1], out[2] + 0.06), (cx - 0.015, cy, can_top + 0.1),
                                            (cx - 0.015, cy, can_top + 0.04)], 0.012, 8)
    return stubs[0], (cx + 0.015, cy, can_top + 0.04)


# Biogas appliances and parts ----------------------------------------------------------------------

HEATER = (0.42, 0.28, 0.4)  # its box's width, depth and height
HEATER_LEGS = 0.08


def gas_heater(col, lit=False):
    """A homemade gas heater: a box bent up from sheet steel and welded, on four short angle-iron
    legs, its front punched with rows of holes, a burner across its foot behind a slot, a flue
    collar on top and a gas pipe stub with a valve out of its side. `lit` burns blue in the slot
    and glows orange through the holes."""
    width, depth, height = HEATER
    legs = HEATER_LEGS
    front = -depth / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(col, "Heater_Leg", M("weld"), (0.025, 0.025, legs + 0.02), at=(sx * (width / 2 - 0.0125), sy * (depth / 2 - 0.0125), 0))
    box(col, "Heater_Body", M("rustysteel"), (width, depth, height), at=(0, 0, legs), bevel=0.006)
    box(col, "Heater_Top", M("rustysteel"), (width + 0.02, depth + 0.02, 0.012), at=(0, 0, legs + height), bevel=0.003)
    cylinder(col, "Heater_Flue", M("rawsteel"), 0.045, 0.07, at=(0, depth / 4, legs + height + 0.012), segments=14)
    for sx in (-1, 1):
        box(col, "Heater_Seam", M("weld"), (0.008, 0.004, height - 0.01), at=(sx * (width / 2 - 0.002), front - 0.001, legs + 0.005))
    holes = M("flame" if lit else "black")
    for row in range(4):
        for column in range(6):
            cylinder(col, "Heater_Hole", holes, 0.014, 0.003, at=(-width / 2 + (column + 1) * width / 7, front - 0.0005,
                                                                  legs + 0.17 + row * 0.055), rotate=(90, 0, 0), segments=8)
    box(col, "Heater_Slot", M("flameblue" if lit else "black"), (width * 0.7, 0.003, 0.045), at=(0, front - 0.0015, legs + 0.05))
    stub_z = legs + 0.07
    tube(col, "Heater_GasStub", M("galvanised"), [(width / 2 - 0.01, 0.04, stub_z), (width / 2 + 0.1, 0.04, stub_z)], 0.012, 8)
    box(col, "Heater_GasValve", M("brass"), (0.035, 0.03, 0.03), at=(width / 2 + 0.06, 0.04, stub_z - 0.015))
    box(col, "Heater_GasLever", M("red"), (0.012, 0.06, 0.01), at=(width / 2 + 0.06, 0.04, stub_z + 0.015))


def _mixer(col, name, at, turn):
    """The kit's mixer valve: a brass body for the air horn's end, a hose barb at each end, a branch
    up for the gas and a red throttle lever on its side. Lies along X at `at`, turned `turn`."""
    axis = 0.026
    parts = [cylinder(col, name + "_Body", M("brass"), 0.024, 0.13, at=(-0.065, 0, axis), rotate=(0, 90, 0), segments=14)]
    for sign in (-1, 1):
        parts.append(cylinder(col, name + "_Nut", M("brass"), 0.03, 0.016, at=(sign * 0.065 - (sign > 0) * 0.016, 0, axis),
                              rotate=(0, 90, 0), segments=6))
        parts.append(cylinder(col, name + "_Barb", M("brass"), 0.013, 0.035, at=(sign * 0.065 + (sign < 0) * -0.035, 0, axis),
                              rotate=(0, 90, 0), segments=10))
    parts.append(cylinder(col, name + "_Branch", M("brass"), 0.017, 0.05, at=(0, 0, axis), segments=12))
    parts.append(cylinder(col, name + "_Shaft", M("galvanised"), 0.006, 0.03, at=(0.02, -0.02, axis), rotate=(90, 0, 0), segments=8))
    parts.append(box(col, name + "_Lever", M("red"), (0.065, 0.01, 0.014), at=(0.045, -0.05, axis - 0.007)))
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


def gas_conversion_kit(col):
    """The kit that lets a petrol engine run on gas: the mixer valve, a coil of black rubber hose,
    two worm-drive hose clamps and the steel plate that adapts the mixer to the carburettor's air
    horn, as it lies out of its box."""
    _mixer(col, "Kit_Mixer", (-0.07, -0.05, 0), 10)
    box(col, "Kit_Plate", M("rawsteel"), (0.12, 0.09, 0.005), at=(0.08, -0.05, 0), rotate=(0, 0, -8))
    cylinder(col, "Kit_PlateHole", M("black"), 0.026, 0.001, at=(0.08, -0.05, 0.005), segments=16)
    for sx in (-1, 1):
        cylinder(col, "Kit_PlateBolt", M("black"), 0.005, 0.001, at=(0.08 + sx * 0.045, -0.05 - sx * 0.006, 0.005), segments=8)
    for i in range(3):
        ring(col, "Kit_Hose", M("rubberhose"), (-0.02, 0.07), 0.075 - 0.004 * i, 0.012 + 0.022 * i, 0.012)
    tube(col, "Kit_HoseEnd", M("rubberhose"), [(0.051, 0.07, 0.056), (0.1, 0.05, 0.03), (0.14, 0.06, 0.012)], 0.012, 8)
    for x, y in ((0.1, 0.07), (0.15, 0.03)):
        ring(col, "Kit_Clamp", M("galvanised"), (x, y), 0.022, 0.004, 0.004)
        box(col, "Kit_ClampScrew", M("galvanised"), (0.012, 0.016, 0.01), at=(x + 0.026, y, 0))


# The game's generators (appliances_misc_01): three bodies, the red and the yellow sharing one, each
# in four facings. A real kit goes on the engine's air intake, where the carburettor draws the gas
# in, so the kit overlay is drawn there, per body and facing. Each body is given as it faces south
# (-Y), in metres from its square's centre: where its intake is (picked on the game's sprites, read
# back through its depth map), which way the intake faces, and the box the gas pipe keeps clear of.
# The red and yellow ones take air at the front panel's engine end, the old open-frame one at the
# end of its air cleaner's horn, the blue inverter low in its front cover.
GENERATOR_BODIES = {
    "frame": {"intake": (0.225, -0.186, 0.366), "facing": (0, -1), "box": ((-0.34, -0.27, 0.0), (0.34, 0.13, 0.6))},
    "old": {"intake": (-0.272, 0.127, 0.423), "facing": (-1, 0), "box": ((-0.3, -0.43, 0.0), (0.3, 0.34, 0.68))},
    "inverter": {"intake": (0.102, -0.172, 0.131), "facing": (0, -1), "box": ((-0.36, -0.25, 0.0), (0.3, 0.15, 0.42))},
}
GAS_KIT_SCALE = 1.2  # a little larger than life, so the mixer reads beside the game's chunky generators
# Where the kit lies on a generator the game doesn't know, another mod's: on the floor across the
# square's front corner, which a generator in its middle leaves clear.
GAS_KIT_AT = (0.35, -0.34)


def _rotated(point, degrees):
    """`point` turned `degrees` about Z."""
    a = math.radians(degrees)
    x, y = point[0], point[1]
    return (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a), *point[2:])


def generator_fit(body, facing):
    """For a generator of `body` facing `facing`, or None for an unknown one: the mixer's origin and
    turn, the top of its gas branch where the pipe comes down into it, the intake and its outward
    direction, and the body's box (lowest and highest corner) on its square."""
    s = GAS_KIT_SCALE
    if body is None:
        origin, turn = (*GAS_KIT_AT, 0.0), 45
        intake, out, box_ = None, None, None
    else:
        spec, degrees = GENERATOR_BODIES[body], FACING_TURN[facing]
        intake = _rotated(spec["intake"], degrees)
        out = _rotated(spec["facing"], degrees)
        # The mixer lies along the intake's axis, its +X barb in the intake, its axis at the intake.
        origin = (intake[0] + out[0] * 0.1 * s, intake[1] + out[1] * 0.1 * s, intake[2] - 0.026 * s)
        turn = math.degrees(math.atan2(-out[1], -out[0]))
        corners = [_rotated((x, y, 0), degrees) for x in (spec["box"][0][0], spec["box"][1][0]) for y in (spec["box"][0][1], spec["box"][1][1])]
        box_ = ((min(c[0] for c in corners), min(c[1] for c in corners), 0.0),
                (max(c[0] for c in corners), max(c[1] for c in corners), spec["box"][1][2]))
    branch = (origin[0], origin[1], origin[2] + 0.076 * s)
    return origin, turn, branch, intake, out, box_


def generator_gas_kit(col, body=None, facing="S"):
    """The kit fitted to a generator, as the overlay on the generator's square shows it: the mixer
    on the engine's air intake of a generator of `body` facing `facing` (GENERATOR_BODIES), its
    adapter plate against the intake, its gas branch up for the line; on a generator the game
    doesn't know (`body` None), lying across the square's front corner with a hose up into it."""
    s = GAS_KIT_SCALE
    origin, turn, _, intake, out, _ = generator_fit(body, facing)
    _mixer(col, "GenKit_Mixer", origin, turn).scale = (s, s, s)
    if body is None:
        cx, cy = GAS_KIT_AT
        tube(col, "GenKit_Hose", M("rubberhose"), [(cx, cy, 0.07 * s), (cx - 0.01, cy + 0.01, 0.12 * s), (cx - 0.05, cy + 0.05, 0.2),
                                                   (cx - 0.1, cy + 0.1, 0.24)], 0.013 * s, 8)
    else:
        box(col, "GenKit_Plate", M("rawsteel"), (0.11, 0.006, 0.09), at=(intake[0] + out[0] * 0.003, intake[1] + out[1] * 0.003,
                                                                        intake[2] - 0.045), rotate=(0, 0, turn + 90))


def fridge_compressor(col):
    """A hermetic compressor cut out of a dead fridge: the black welded can, its copper suction,
    discharge and process stubs pinched shut, the relay box clipped to its side and its maker's
    label, on its mounting plate and rubber feet."""
    plate = 0.02
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder(col, "Comp_Foot", M("black"), 0.016, plate, at=(sx * 0.1, sy * 0.065, 0), segments=10)
    box(col, "Comp_Plate", M("rawsteel"), (0.26, 0.17, 0.006), at=(0, 0, plate))
    base = plate + 0.006
    radius, can = 0.1, 0.11
    cylinder(col, "Comp_Can", M("black"), radius, can, at=(0, 0, base), segments=24)
    mound(col, "Comp_Dome", M("black"), (radius, radius, 0.075), at=(0, 0, base + can), segments=24, rings=6)
    ring(col, "Comp_Seam", M("darkgrey"), (0, 0), radius + 0.002, base + can, 0.005)
    box(col, "Comp_Label", M("label"), (0.07, 0.002, 0.04), at=(0.0, -radius - 0.001, base + 0.04))
    box(col, "Comp_Relay", M("darkgrey"), (0.045, 0.07, 0.06), at=(-radius - 0.02, 0, base + 0.03), bevel=0.004)
    for (x, y), lean in (((0.04, 0.05), (0.05, 0.07)), ((0.06, -0.02), (0.08, -0.03)), ((-0.02, 0.06), (-0.03, 0.08))):
        tube(col, "Comp_Stub", M("copper"), [(x, y, base + can + 0.04), (x + lean[0] * 0.4, y + lean[1] * 0.4, base + can + 0.09),
                                             (x + lean[0], y + lean[1], base + can + 0.11)], 0.007, 8)
