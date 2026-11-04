"""Wood gas: the gasifiers, their pipe to a generator, and what they leave behind."""
import math
import random

from mathutils import Vector

from art.kit import around, box, cylinder, lathe, loft, mound, place, ring, spline, tube
from biogas import generator_fit
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


# The tarry packing: one tuft of the hay, grass or splinters a filter is packed with, once tar has
# soaked it and matted it: shorter than the game's hay tuft as it lies on the ground (0.41 m long,
# 0.12 wide, 0.18 high), pressed down into a filter bucket 0.3 m across. Its half length, its half
# width where its ends splay, and its height at the middle.
TARRY_TUFT = (0.11, 0.075, 0.06)


def tarry_packing(col):
    """A tuft of a gasifier filter's packing once tar has soaked it, in the game's hay tuft's form:
    its strands glued by the tar into thick locks lying side by side in layers, drawn in at the
    middle and fanning out and up at both ends, glossy black-brown, a few browner where they soaked
    less; loose strands cross them, and at each lock's ends a few strands stand free of the tar,
    still the colour of straw on some, soaked brown on others."""
    half, flare, height = TARRY_TUFT
    rng = random.Random(61)
    # The locks, layer on layer up the tuft, each a little askew of the rest and kinked, drawn in to
    # the waist and fanning out at the ends, the upper layers' ends lifting.
    for layer, count in enumerate((5, 5, 5, 4)):
        up = (layer + 0.5) / 4
        for j in range(count):
            lane = -1 + 2 * (j + 0.5) / count + rng.uniform(-0.12, 0.12)
            start, end = -half * rng.uniform(0.75, 1.0), half * rng.uniform(0.75, 1.0)
            wave, phase = rng.uniform(0.002, 0.005), rng.uniform(0, 2 * math.pi)
            slope, lift = rng.uniform(-0.1, 0.1), up * rng.uniform(0.5, 1.1)
            points = []
            for k in range(11):
                x = start + (end - start) * k / 10
                t = x / half
                y = lane * flare * (0.6 + 0.4 * t * t) + slope * x + wave * math.sin(3 * math.pi * k / 10 + phase)
                z = 0.008 + height * 0.75 * up * (1 - 0.3 * t * t) + lift * height * 1.4 * abs(t) ** 3
                points.append(Vector((x, y, z)))
            radius = rng.uniform(0.0075, 0.009)
            tube(col, "Tarry_Lock", M("tarstraw") if rng.random() < 0.3 else M("tar"), spline(points, 3), radius, 8)
            _free_ends(col, rng, points, radius, rng.randint(2, 4))
    # Loose strands through the clump, crossing the locks at a slant, sticking out further.
    for i in range(30):
        lane, up = rng.uniform(-1, 1), rng.random()
        start, end = -half * rng.uniform(0.85, 1.15), half * rng.uniform(0.85, 1.15)
        slope, lift = rng.uniform(-0.25, 0.25), up * rng.uniform(0.4, 1.2)
        points = []
        for k in range(9):
            x = start + (end - start) * k / 8
            t = x / half
            y = lane * flare * (0.55 + 0.45 * t * t) + slope * x
            z = 0.004 + height * 0.9 * up * (1 - 0.3 * t * t) + lift * height * 1.4 * abs(t) ** 3
            points.append(Vector((x, y, z)))
        tube(col, "Tarry_Loose", M("tar"), spline(points, 3), rng.uniform(0.0022, 0.003), 5)
        _free_ends(col, rng, points, 0.002, 1)


def _free_ends(col, rng, points, radius, count):
    """`count` strands standing free of the tar at each end of a lock or strand along `points`,
    spreading out of it and mostly up: straw on some, soaked brown or tarred on others."""
    for tip, before in ((points[0], points[1]), (points[-1], points[-2])):
        out = (tip - before).normalized()
        side = Vector((-out.y, out.x, 0))
        for _ in range(count):
            length, spread = rng.uniform(0.022, 0.045), rng.uniform(-0.6, 0.6)
            root = tip - out * 0.006 + side * spread * radius
            free = root + (out + side * spread + Vector((0, 0, rng.uniform(-0.3, 0.4)))).normalized() * length
            free.z = max(free.z, 0.003)
            shade = rng.random()
            strand = M("straw") if shade < 0.45 else M("tarstraw") if shade < 0.75 else M("tar")
            tube(col, "Tarry_Strand", strand, [root, (root + free) / 2 + Vector((0, 0, 0.002)), free], 0.0022, 5)


# A heap of wood ash as it is raked out of a gasifier's ash pit or a fire: half a kilo, slumped to a
# low cone between the heaps the game lays its quicklime (0.26 m across, 0.10 high) and gunpowder
# (0.16 m, 0.04 high) down as. Its radius at the foot and its height.
ASH_HEAP = (0.09, 0.07)
# The heap's profile up from its foot, as fractions of its radius and height: its slopes straight as
# a poured heap's, easing in at the foot and rounding off at the peak.
ASH_PROFILE = ((1.0, 0.0), (0.86, 0.1), (0.66, 0.33), (0.46, 0.58), (0.27, 0.8), (0.1, 0.96), (0.0, 1.0))


def wood_ash(col):
    """Wood ash in a bare heap, as the game lays its quicklime and gunpowder down: soft pale grey
    powder slumped into a low cone, its foot uneven, bits of charcoal half buried in it, a few flecks
    white where it burnt clean, and a few crumbs spilt round its foot."""
    radius, height = ASH_HEAP
    rng = random.Random(50)
    waves = [(rng.uniform(0.03, 0.06), rng.uniform(0, 360), k) for k in (2, 3, 5)]

    def reach(angle):
        # How far the heap's foot runs out that way, as a fraction of its radius.
        return 1 + sum(a * math.cos(math.radians(k * angle + phase)) for a, phase, k in waves)

    def shape(angle, row):
        # The foot pushed out or drawn in with the outline, every row but the foot and the top
        # raised or lowered a little, so the heap isn't turned as on a lathe.
        out, _ = ASH_PROFILE[row]
        lump = rng.uniform(-0.03, 0.03) if 0 < row < len(ASH_PROFILE) - 1 else 0.0
        return radius * out * (reach(angle) - 1), height * lump
    lathe(col, "Ash_Heap", M("ash"), [(radius * out, height * up) for out, up in ASH_PROFILE], segments=32, shape=shape)

    def on_heap(spread, angle):
        # The point on the heap a fraction `spread` of the way out to its foot that way.
        for (r0, z0), (r1, z1) in zip(ASH_PROFILE, ASH_PROFILE[1:]):
            if r1 <= spread <= r0:
                z = height * (z0 + (z1 - z0) * (r0 - spread) / (r0 - r1))
                return (*around((0, 0), angle, spread * radius * reach(angle)), z)
        return (*around((0, 0), angle, spread * radius * reach(angle)), 0.0)
    # Spread over the heap on a golden-angle spiral, so no side of it is bare.
    for i in range(11):
        spread, angle = 0.85 * math.sqrt((i + 0.5) / 11), i * 137.5
        x, y, z = on_heap(spread, angle)
        size = (rng.uniform(0.007, 0.012), rng.uniform(0.005, 0.009), rng.uniform(0.005, 0.007))
        box(col, "Ash_Charcoal", M("charcoal"), size, at=(x, y, z - size[2] * 0.7),
            rotate=(rng.uniform(-25, 25), rng.uniform(-25, 25), rng.uniform(0, 180)))
    for i in range(6):
        spread, angle = 0.8 * math.sqrt((i + 0.3) / 6), 60 + i * 137.5
        x, y, z = on_heap(spread, angle)
        mound(col, "Ash_Fleck", M("ashwhite"), (rng.uniform(0.007, 0.01), rng.uniform(0.005, 0.007), 0.0025),
              at=(x, y, z - 0.002), rotate=(0, 0, rng.uniform(0, 180)), segments=8, rings=2)
    # Crumbs of ash and charcoal spilt round the foot.
    for i in range(5):
        angle = 20 + i * 71 + rng.uniform(-10, 10)
        x, y = around((0, 0), angle, radius * reach(angle) * rng.uniform(1.08, 1.25))
        if i % 2:
            box(col, "Ash_Crumb", M("charcoal"), (0.007, 0.005, 0.004), at=(x, y, 0), rotate=(0, 0, rng.uniform(0, 180)))
        else:
            mound(col, "Ash_Crumb", M("ashdark"), (0.008, 0.006, 0.004), at=(x, y, 0), rotate=(0, 0, rng.uniform(0, 180)),
                  segments=8, rings=2)
