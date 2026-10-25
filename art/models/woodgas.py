"""Wood gas: the gasifiers, their pipe to a generator, and what they leave behind."""
import math
import random

from biogas import generator_fit
from kit import around, beam, box, cylinder, mound, ring, tube
from palette import M
from parts import DRUM, arch, drum, drum_patch

# Wood gas -----------------------------------------------------------------------------------------
#
# A gasifier stands on its square as a digester does: its body in the west and its filter in the
# east, side by side as the viewer sees them, so neither hides the other. Its glow while lit and the
# metal pipe on to a generator on the next square are overlays. As in the FEMA plans (ORNL-6404,
# 2.2, steps 8 to 11), every hole is in the filter's lid: the gas comes in from the body, goes down
# through wood chips on one side of a divider and up the other, and leaves by the outlet beside the
# blower's stack for the engine. Every tier's filter is the bucket its recipe takes, so one set of
# pipe overlays, rising from the outlet, fits all three.

GASIFIER_AT = (-0.14, -0.04)
GASIFIER_FILTER_AT = (0.3, 0.08)
FILTER_BUCKET = (0.13, 0.15, 0.34)  # the game's bucket: its radius at the foot and the rim, its height
FILTER_TOP = FILTER_BUCKET[2] + 0.012  # the lid's top
FILTER_INLET = (GASIFIER_FILTER_AT[0] - 0.07, GASIFIER_FILTER_AT[1] + 0.03)
FILTER_OUTLET = (GASIFIER_FILTER_AT[0] + 0.06, GASIFIER_FILTER_AT[1] - 0.05)
FILTER_BLOWER = (GASIFIER_FILTER_AT[0] + 0.0, GASIFIER_FILTER_AT[1] + 0.09)
OUTLET_STUB = 0.05  # the outlet's threaded stub above the lid, capped while no pipe is on it
# The side the fire's ash or air door faces, in degrees from east: the front, clear of the filter.
GASIFIER_DOOR_ANGLE = -100
PIPE_RADIUS = 0.021
# The height the pipe to a generator runs at: over every generator's body and in front of every
# gasifier's, from where it rises off the filter to where it comes down to the generator's intake.
PIPE_RUN_Z = 0.78
# Where the pipe leaves the gasifier's square for a generator on the next square, by the generator's
# direction: straight off the outlet, or round the front of the body to the west.
GASIFIER_PIPE_EDGES = {"N": (FILTER_OUTLET[0], 0.5), "E": (0.5, FILTER_OUTLET[1]), "S": (FILTER_OUTLET[0], -0.5), "W": (-0.5, -0.44)}
OPPOSITE = {"N": "S", "E": "W", "S": "N", "W": "E"}
STEP = {"N": (0, 1), "E": (1, 0), "S": (0, -1), "W": (-1, 0)}


def _generator_pipe_edge(side):
    """Where the pipe comes onto a generator's square from the gasifier on its `side`: the gasifier
    half's end at the shared edge, in the generator square's frame."""
    x, y = GASIFIER_PIPE_EDGES[OPPOSITE[side]]
    dx, dy = STEP[side]
    return x + dx, y + dy, PIPE_RUN_Z


def _pipe(col, name, points):
    """The recipes' metal pipe through `points`, square at each bend as a threaded elbow is."""
    for start, end in zip(points, points[1:]):
        tube(col, name, M("metalpipe"), [start, end], PIPE_RADIUS, 10)
    for x, y, z in points[1:-1]:
        box(col, name + "_Elbow", M("metalpipe"), (0.05, 0.05, 0.05), at=(x, y, z - 0.025), bevel=0.008)


def _gasifier_outlet(col, name, radius, z, clear=None):
    """The gas pipe out of the body's side near the fire, up and over into the filter lid's inlet.
    It leaves the body turned toward the viewer from the filter, where there is room to rise, and
    rises clear of `clear`, the widest the body gets above the outlet (default `radius`)."""
    fx, fy = FILTER_INLET
    angle = math.degrees(math.atan2(fy - GASIFIER_AT[1], fx - GASIFIER_AT[0])) - 35
    inside = around(GASIFIER_AT, angle, radius - 0.01)
    out = around(GASIFIER_AT, angle, (clear or radius) + 0.03)
    over = FILTER_TOP + 0.12
    _pipe(col, name, [(*inside, z), (*out, z), (*out, over), (fx, fy, over), (fx, fy, FILTER_TOP)])


def _filter(col, name):
    """The filter: the game's galvanised bucket of wood chips, a lid cut from sheet and latched down
    on a hose seal, three holes in it: the inlet from the body, the blower's stack with its cap, and
    the outlet to the engine, capped until a pipe is screwed on; the drain cock at its foot."""
    foot, rim, height = FILTER_BUCKET
    fx, fy = GASIFIER_FILTER_AT
    cylinder(col, name + "_Bucket", M("bucket"), foot, height, at=(fx, fy, 0), radius_top=rim, segments=28)
    for t in (0.3, 0.7):
        ring(col, name + "_BucketRib", M("bucket"), GASIFIER_FILTER_AT, foot + (rim - foot) * t + 0.003, height * t, 0.005)
    ring(col, name + "_Seal", M("black"), GASIFIER_FILTER_AT, rim + 0.002, height, 0.008)
    cylinder(col, name + "_Lid", M("rawsteel"), rim + 0.012, 0.012, at=(fx, fy, height), segments=28)
    for angle in (-60, 60, 180):
        x, y = around(GASIFIER_FILTER_AT, angle, rim + 0.012)
        box(col, name + "_Latch", M("weld"), (0.025, 0.012, 0.05), at=(x, y, height - 0.035), rotate=(0, 0, angle + 90))
    cylinder(col, name + "_Outlet", M("galvanised"), PIPE_RADIUS, OUTLET_STUB, at=(*FILTER_OUTLET, FILTER_TOP), segments=12)
    cylinder(col, name + "_OutletCap", M("galvanised"), PIPE_RADIUS + 0.006, 0.02, at=(*FILTER_OUTLET, FILTER_TOP + OUTLET_STUB - 0.012),
             segments=12)
    bx, by = FILTER_BLOWER
    cylinder(col, name + "_Blower", M("darkgrey"), 0.045, 0.05, at=(bx, by, FILTER_TOP), segments=16)
    cylinder(col, name + "_Stack", M("galvanised"), 0.02, 0.18, at=(bx, by, FILTER_TOP + 0.05), segments=12)
    cylinder(col, name + "_StackCap", M("red"), 0.026, 0.025, at=(bx, by, FILTER_TOP + 0.23), segments=12)
    cock = around(GASIFIER_FILTER_AT, -80, foot + 0.02)
    box(col, name + "_DrainCock", M("brass"), (0.03, 0.03, 0.03), at=(*cock, 0.02))


def _at_door(radius, z, out=0.0):
    """Where on the body's side, at `radius` and `z`, the fire door's face is, and the turn that lays
    a part's X along the side there; `out` stands it that much proud."""
    return (*around(GASIFIER_AT, GASIFIER_DOOR_ANGLE, radius + out), z), (0, 0, GASIFIER_DOOR_ANGLE + 90)


def _along_door(point, offset):
    """`point` moved `offset` along the body's side at the door, to the viewer's right for positive."""
    dx, dy = around((0, 0), GASIFIER_DOOR_ANGLE + 90, offset)
    return point[0] + dx, point[1] + dy, point[2]


def _door_disc(col, name, mat, at, disc):
    """A disc of `disc` radius facing out of the body's side at the door, its back at `at`."""
    cylinder(col, name, mat, disc, 0.004, at=at, rotate=(90, 0, GASIFIER_DOOR_ANGLE + 90), segments=12)


def gasifier(col, tier="standard", frame=True, lit=False, pipe=None):
    """A downdraft wood gas generator as the 1989 FEMA plans build one, in three tiers: "primitive"
    the plans' own, "standard" a steel drum, "advanced" a welded body with a forged grate. `lit`
    draws only the fire's glow at its door, `pipe` only the metal pipe up off the filter's outlet and
    across to the square's edge toward a generator that way ("N", "E", "S" or "W")."""
    if frame:
        {"primitive": _primitive_gasifier, "standard": _drum_gasifier, "advanced": _welded_gasifier}[tier](col)
        _filter(col, "Filter")
    if lit:
        _gasifier_glow(col, tier)
    if pipe:
        ox, oy = FILTER_OUTLET
        ex, ey = GASIFIER_PIPE_EDGES[pipe]
        points = [(ox, oy, FILTER_TOP + OUTLET_STUB - 0.01), (ox, oy, PIPE_RUN_Z)]
        if pipe == "W":
            points.append((ox, ey, PIPE_RUN_Z))
        _pipe(col, "Gasifier_Pipe", points + [(ex, ey, PIPE_RUN_Z)])


PRIMITIVE_POT = (0.2, 0.22)  # the cooking pot's radius and height
PRIMITIVE_BIN = (0.21, 0.24, 0.6)  # the game's round bin: its radius at the foot and the rim, its height
DRUM_DOOR_Z = 0.05  # the drum's ash door's foot
WELDED = (0.27, 0.86)  # the welded body's radius and height to its shoulder


def _primitive_gasifier(col):
    """The FEMA unit itself, from what a scavenger finds: the game's round bin, a plain steel can
    painted near black, for the hopper, its seam to the big steel cooking pot that holds the fire
    taped round, an air hole in the pot's side and the gas pipe out of it, soot up both."""
    bx, by = GASIFIER_AT
    pot_radius, pot_height = PRIMITIVE_POT
    cylinder(col, "Prim_Pot", M("potscorched"), pot_radius, pot_height, at=(bx, by, 0), segments=28)
    for angle in (30, 210):
        a, b = around(GASIFIER_AT, angle - 12, pot_radius), around(GASIFIER_AT, angle + 12, pot_radius)
        c, d = around(GASIFIER_AT, angle - 8, pot_radius + 0.035), around(GASIFIER_AT, angle + 8, pot_radius + 0.035)
        tube(col, "Prim_PotHandle", M("darkgrey"), [(*a, pot_height - 0.04), (*c, pot_height - 0.04), (*d, pot_height - 0.04),
                                                    (*b, pot_height - 0.04)], 0.007, 6)
    hole, _ = _at_door(pot_radius, 0.07)
    _door_disc(col, "Prim_AirHole", M("black"), hole, 0.04)
    foot, rim, height = PRIMITIVE_BIN
    cylinder(col, "Prim_Bin", M("roundbin"), foot, height, at=(bx, by, pot_height), radius_top=rim, segments=28)
    ring(col, "Prim_BinRim", M("roundbin"), GASIFIER_AT, rim + 0.004, pot_height + height, 0.01)
    cylinder(col, "Prim_Tape", M("ducttape"), foot + 0.006, 0.05, at=(bx, by, pot_height - 0.02), segments=28)
    top = pot_height + height
    cylinder(col, "Prim_Lid", M("rawsteel"), rim + 0.012, 0.012, at=(bx, by, top), segments=28)
    arch(col, "Prim_LidHandle", M("weld"), bx, by, 0.06, 0.05, top + 0.01, top + 0.05, 0.008)
    _gasifier_outlet(col, "Prim_Pipe", pot_radius, 0.13, clear=rim + 0.01)


def _drum_gasifier(col):
    """The game's Metal Drum scorched black about its fire and tinted brown above, its head made a
    lid clamped on with a ring, tar wept from under the clamp, an ash door welded on at its foot with
    draft holes punched in it."""
    radius, height = DRUM
    bx, by = GASIFIER_AT
    drum(col, "Drum_Body", GASIFIER_AT, "MetalDrum", paint="drumscorched")
    rng = random.Random(72)
    for angle in (-130, -95, -60, -20):
        drum_patch(col, "Drum_Tar", M("tar"), GASIFIER_AT, radius + 0.002, angle, height - rng.uniform(0.08, 0.16), (0.02, rng.uniform(0.06, 0.14)))
    cylinder(col, "Drum_Lid", M("rawsteel"), radius + 0.008, 0.02, at=(bx, by, height), segments=32)
    ring(col, "Drum_Clamp", M("weld"), GASIFIER_AT, radius + 0.01, height + 0.01, 0.012)
    arch(col, "Drum_LidHandle", M("weld"), bx, by, 0.07, 0.06, height + 0.02, height + 0.07, 0.008)
    at, turn = _at_door(radius, DRUM_DOOR_Z, 0.004)
    box(col, "Drum_AshDoor", M("rustysteel"), (0.22, 0.008, 0.14), at=at, rotate=turn, bevel=0.002)
    for side in (-1, 1):
        hinge, _ = _at_door(radius, DRUM_DOOR_Z + 0.055 + side * 0.04, 0.012)
        box(col, "Drum_DoorHinge", M("weld"), (0.02, 0.02, 0.03), at=_along_door(hinge, -0.11), rotate=turn)
    latch, _ = _at_door(radius, DRUM_DOOR_Z + 0.06, 0.012)
    box(col, "Drum_DoorLatch", M("weld"), (0.03, 0.012, 0.02), at=_along_door(latch, 0.09), rotate=turn)
    hole, _ = _at_door(radius, DRUM_DOOR_Z + 0.09, 0.008)
    for offset in (-0.05, 0.0, 0.05):
        _door_disc(col, "Drum_DraftHole", M("black"), _along_door(hole, offset), 0.014)
    _gasifier_outlet(col, "Drum_Pipe", radius, 0.2)


def _welded_gasifier(col):
    """A body welded up from sheet steel and painted with stove black, the paint burnt off and rusting
    low round the fire: seams round it, a shoulder up to a clamped hopper lid, a forged grate door at
    its foot."""
    radius, height = WELDED
    bx, by = GASIFIER_AT
    cylinder(col, "Welded_Body", M("stovescorched"), radius, height, at=(bx, by, 0), segments=32)
    for z in (0.3, 0.6):
        ring(col, "Welded_Seam", M("weld"), GASIFIER_AT, radius + 0.001, z, 0.005)
    cylinder(col, "Welded_Shoulder", M("stoveblack"), radius, 0.12, at=(bx, by, height), radius_top=0.13, segments=32)
    ring(col, "Welded_ShoulderSeam", M("weld"), GASIFIER_AT, radius + 0.001, height, 0.005)
    neck = height + 0.12
    cylinder(col, "Welded_Neck", M("rawsteel"), 0.13, 0.05, at=(bx, by, neck), segments=24)
    cylinder(col, "Welded_Lid", M("weld"), 0.145, 0.025, at=(bx, by, neck + 0.05), segments=24)
    box(col, "Welded_LidClamp", M("weld"), (0.03, 0.08, 0.02), at=(bx + 0.13, by, neck + 0.05), bevel=0.004)
    arch(col, "Welded_LidHandle", M("weld"), bx, by, 0.05, 0.04, neck + 0.075, neck + 0.12, 0.008)
    at, turn = _at_door(radius, 0.06, 0.002)
    box(col, "Welded_GrateOpening", M("black"), (0.2, 0.004, 0.16), at=at, rotate=turn)
    for z in (0.045, 0.22):
        rail, _ = _at_door(radius, z, 0.006)
        box(col, "Welded_GrateFrame", M("weld"), (0.23, 0.012, 0.015), at=rail, rotate=turn)
    bar, _ = _at_door(radius, 0.06, 0.008)
    for offset in (-0.105, -0.05, 0.0, 0.05, 0.105):
        box(col, "Welded_GrateBar", M("weld"), (0.014, 0.012, 0.16), at=_along_door(bar, offset), rotate=turn)
    _gasifier_outlet(col, "Welded_Pipe", radius, 0.2)


def _gasifier_glow(col, tier):
    """The fire showing at the door, a little proud of what it shows through, so a lit overlay drawn
    over the gasifier's tile keeps it: the pot's air hole, the drum door's draft holes and the gap
    under it, the welded body's grate opening behind its bars."""
    if tier == "primitive":
        hole, _ = _at_door(PRIMITIVE_POT[0], 0.07, 0.002)
        _door_disc(col, "Glow_AirHole", M("flame"), hole, 0.036)
    elif tier == "standard":
        hole, _ = _at_door(DRUM[0], DRUM_DOOR_Z + 0.09, 0.011)
        for offset in (-0.05, 0.0, 0.05):
            _door_disc(col, "Glow_DraftHole", M("flame"), _along_door(hole, offset), 0.012)
        gap, turn = _at_door(DRUM[0], DRUM_DOOR_Z - 0.012, 0.004)
        box(col, "Glow_DoorGap", M("flame"), (0.2, 0.006, 0.01), at=gap, rotate=turn)
    else:
        at, turn = _at_door(WELDED[0], 0.065, 0.005)
        box(col, "Glow_Grate", M("flame"), (0.19, 0.003, 0.15), at=at, rotate=turn)


def _clear_of(start, end, box_, margin=0.05):
    """Whether the straight run from `start` to `end` keeps `margin` clear of the box."""
    if box_ is None:
        return True
    (x0, y0, z0), (x1, y1, z1) = box_
    for k in range(41):
        t = k / 40
        x, y, z = (start[i] + (end[i] - start[i]) * t for i in range(3))
        if x0 - margin < x < x1 + margin and y0 - margin < y < y1 + margin and z < z1 + margin:
            return False
    return True


def generator_gas_pipe(col, side, body=None, facing="S"):
    """The metal pipe on a generator's square from the gasifier on the square to its `side` ("N",
    "E", "S" or "W") down into the gas branch of the kit's mixer on a generator of `body` facing
    `facing` (generator_gas_kit): sloping straight down from the shared edge to above the branch
    where nothing is in the way, else over the generator's body and down, then down into it."""
    _, _, branch, _, _, box_ = generator_fit(body, facing)
    edge = _generator_pipe_edge(side)
    above = (branch[0], branch[1], branch[2] + 0.12)
    if _clear_of(edge, above, box_):
        route = [edge, above, branch]
    else:
        route = [edge, (above[0], above[1], PIPE_RUN_Z), branch]
    _pipe(col, "GenPipe", route)


def tarry_packing(col):
    """A wad of straw out of a gasifier's filter, soaked black-brown with tar, a glossy smear of tar
    run out under it, patches of the straw showing through where it soaked less, and strands
    sticking out, some soaked dark and some still pale."""
    rx, ry, height = 0.1, 0.08, 0.045
    mound(col, "Tarry_Smear", M("tar"), (rx * 1.2, ry * 1.15, 0.006), lumps=0.12, seed=62, segments=20, rings=3)
    mound(col, "Tarry_Wad", M("tar"), (rx, ry, height), lumps=0.25, seed=60, segments=16, rings=5)
    rng = random.Random(61)
    for i in range(4):
        spread = rng.uniform(0.2, 0.6)
        u, v = around((0, 0), 40 + i * 95, spread)
        mound(col, "Tarry_Patch", M("tarstraw"), (rng.uniform(0.012, 0.018), rng.uniform(0.008, 0.012), 0.008),
              at=(u * rx, v * ry, height * math.sqrt(1 - spread * spread) * 1.05), rotate=(0, 0, rng.uniform(0, 180)),
              lumps=0.1, seed=63 + i, segments=10, rings=3)
    for k in range(18):
        angle, reach = rng.uniform(0, 360), rng.uniform(0.5, 0.85)
        ux, uy = around((0, 0), angle, 1)
        z = height * math.sqrt(1 - reach * reach) + 0.003
        start = (ux * rx * reach, uy * ry * reach, z)
        length = rng.uniform(0.04, 0.07)
        end = (start[0] + ux * length, start[1] + uy * length, max(0.004, z + rng.uniform(-0.03, 0.01)))
        # Thicker than a decal (models.DECAL_THICKNESS), so the ground model keeps them standing out.
        beam(col, "Tarry_Strand", M("straw" if k % 3 == 0 else "tarstraw"), start, end, (0.006, 0.003))


def wood_ash(col):
    """A shovelful of wood ash out of a stove: a soft pale grey heap slumped into a darker skirt
    of fines round its foot, flecked white where the ash burnt clean, with bits of charcoal in it
    and a couple of charred twig ends poking out."""
    rx, ry, height = 0.12, 0.1, 0.075
    mound(col, "Ash_Skirt", M("ashdark"), (rx * 1.3, ry * 1.3, 0.02), lumps=0.08, seed=52, segments=24, rings=4)
    mound(col, "Ash_Heap", M("ash"), (rx, ry, height), lumps=0.08, seed=50, segments=20, rings=6)
    rng = random.Random(51)

    def on_heap(spread):
        # Clear of the heap's lumps, which raise its surface by up to a twelfth.
        return height * math.sqrt(1 - spread * spread) * 1.06
    # Spread evenly over the heap, on a golden-angle spiral, so no side of it is bare.
    for i in range(12):
        spread = 0.75 * math.sqrt((i + 0.5) / 12)
        u, v = around((0, 0), i * 137.5, spread)
        size = (rng.uniform(0.012, 0.022), rng.uniform(0.008, 0.014), 0.01)
        box(col, "Ash_Charcoal", M("charcoal"), size, at=(u * rx, v * ry, on_heap(spread) - 0.004),
            rotate=(rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(0, 180)))
    for i in range(9):
        spread = 0.8 * math.sqrt((i + 0.3) / 9)
        u, v = around((0, 0), 60 + i * 137.5, spread)
        mound(col, "Ash_Fleck", M("ashwhite"), (rng.uniform(0.008, 0.014), rng.uniform(0.006, 0.01), 0.004),
              at=(u * rx, v * ry, on_heap(spread) - 0.003), rotate=(0, 0, rng.uniform(0, 180)), segments=8, rings=2)
    for angle, spread, length in ((30, 0.55, 0.07), (200, 0.45, 0.06)):
        u, v = around((0, 0), angle, spread)
        start = (u * rx, v * ry, on_heap(spread) - 0.012)
        out = around((0, 0), angle, 1)
        beam(col, "Ash_Twig", M("charcoal"), start, (start[0] + out[0] * length, start[1] + out[1] * length, start[2] + 0.025),
             (0.009, 0.009))
