"""Wind chargers, their blades and alternators, and the sprite models the game draws them as."""
import math

from kit import around, beam, box, cylinder, group, loft, mound, ring, tube
from palette import M
from parts import DRUM

# Wind ---------------------------------------------------------------------------------------------
#
# A wind charger is drawn in play as a sprite model that the game turns about its vertical axis to
# spin the rotor, so every part but the rotor is round about the shaft: turned, it looks the same.

# The pole's height to the rotor's foot: the whole stands about 2.5 m, as tall as a tile's sprite
# can draw it.
SCOOP_POLE = 1.6
SCOOP_OVERLAP = 0.15  # how far each scoop's inner edge reaches past the shaft, together


def _scoop(col, name, centre, start, height, z):
    """Half a 55 gallon drum cut lengthwise, standing at `centre` (the drum's axis), its arc from
    `start` degrees round half a turn: painted outside with its rolling hoop, rust inside."""
    radius = DRUM[0]
    strips = 12
    step = 180 / strips
    chord = 2 * radius * math.sin(math.radians(step / 2))
    for i in range(strips):
        a = start + (i + 0.5) * step
        for mat, out, thick in (("drummetal", 0.002, 0.003), ("rust", -0.002, 0.003)):
            x, y = around(centre, a, radius + out)
            box(col, name, M(mat), (chord + 0.004, thick, height), at=(x, y, z), rotate=(0, 0, a + 90))
        for rise in (height / 3, 2 * height / 3):
            x, y = around(centre, a, radius + 0.006)
            box(col, name + "_Hoop", M("drummetal"), (chord + 0.004, 0.006, 0.022), at=(x, y, z + rise - 0.011), rotate=(0, 0, a + 90))


def scoop_rotor(col):
    """A homestead Savonius wind charger: the two halves of a 55 gallon drum cut lengthwise, set in
    an S with their inner edges overlapping, between steel plates on a shaft, on a steel pole set in
    a concrete footing, the treadmill motor it turns in a round housing at the pole's foot, its cable
    buried, since anything off the shaft's axis would swing round as the rotor spins."""
    radius, height = DRUM
    offset = radius - SCOOP_OVERLAP / 2
    reach = offset + radius + 0.01
    cylinder(col, "Scoop_Footing", M("concrete"), 0.2, 0.06, segments=24)
    cylinder(col, "Scoop_Housing", M("darkgrey"), 0.12, 0.24, at=(0, 0, 0.06), segments=20)
    cylinder(col, "Scoop_HousingCap", M("weld"), 0.13, 0.025, at=(0, 0, 0.3), segments=20)
    cylinder(col, "Scoop_Pole", M("galvanised"), 0.045, SCOOP_POLE - 0.325, at=(0, 0, 0.325), segments=14)
    cylinder(col, "Scoop_Bearing", M("weld"), 0.07, 0.05, at=(0, 0, SCOOP_POLE - 0.05), segments=14)
    plate = 0.008
    cylinder(col, "Scoop_PlateLow", M("rustysteel"), reach, plate, at=(0, 0, SCOOP_POLE), segments=32)
    foot = SCOOP_POLE + plate
    _scoop(col, "Scoop_Half", (offset, 0), 180, height, foot)
    _scoop(col, "Scoop_Half", (-offset, 0), 0, height, foot)
    top = foot + height
    cylinder(col, "Scoop_PlateTop", M("rustysteel"), reach, plate, at=(0, 0, top), segments=32)
    cylinder(col, "Scoop_Shaft", M("galvanised"), 0.025, 0.09, at=(0, 0, top + plate), segments=12)
    cylinder(col, "Scoop_ShaftCap", M("weld"), 0.035, 0.03, at=(0, 0, top + plate + 0.06), segments=12)


def treadmill_motor(col):
    """A home treadmill's permanent-magnet DC drive motor, lying on its mounting bracket: a black
    can between aluminium end bells, a grooved flywheel pulley on its shaft, its maker's label, and
    two leads, red and black, out of the back."""
    radius, length = 0.045, 0.15
    axis = 0.058
    box(col, "Motor_Bracket", M("rawsteel"), (0.09, 0.07, 0.008), at=(0, 0, 0))
    cylinder(col, "Motor_Can", M("black"), radius, length, at=(-length / 2, 0, axis), rotate=(0, 90, 0), segments=18)
    for x in (-length / 2 - 0.012, length / 2):
        cylinder(col, "Motor_EndBell", M("aluminium"), radius + 0.002, 0.012, at=(x, 0, axis), rotate=(0, 90, 0), segments=18)
    box(col, "Motor_Label", M("label"), (0.06, 0.035, 0.001), at=(0, 0, axis + radius - 0.0005))
    front = length / 2 + 0.012
    cylinder(col, "Motor_Shaft", M("galvanised"), 0.006, 0.02, at=(front, 0, axis), rotate=(0, 90, 0), segments=8)
    cylinder(col, "Motor_Pulley", M("aluminium"), 0.052, 0.03, at=(front + 0.012, 0, axis), rotate=(0, 90, 0), segments=24)
    for groove in (0.008, 0.016, 0.024):
        cylinder(col, "Motor_PulleyGroove", M("darkgrey"), 0.053, 0.002, at=(front + 0.012 + groove, 0, axis), rotate=(0, 90, 0),
                 segments=24)
    back = -length / 2 - 0.012
    for colour, side in (("red", -1), ("black", 1)):
        tube(col, "Motor_Lead", M(colour), [(back, side * 0.012, axis), (back - 0.03, side * 0.02, axis - 0.01),
                                             (back - 0.06, side * 0.035, 0.006)], 0.0035, 6)


# The treadmill and car alternator wind chargers and the homebuilt wind turbine face the wind on a
# heading fixed when they are built. Each is built facing south (-Y), its mast at the origin, and
# the game turns the whole to face the other ways. Only its rotor spins: the parts named with ROTOR
# are turned about the hub's axis within the mesh, a mesh per spin step (models.py), the mast
# staying put.
ROTOR = "Rotor_"
PROPELLER_HUB = 3.8  # the hub's height, a storey and a half up, on either pipe mast
PROPELLER_BLADE = (0.82, 0.13, 0.02)  # a blade's length past its root, its chord at the root, its thickness
ALTERNATOR_HUB = 4.3
ALTERNATOR_BLADE = (1.0, 0.14, 0.005)
# The rotor turned a step at a time: three blades look the same after a third of a turn.
ROTOR_SPINS = (0, 20, 40, 60, 80, 100)
# The radius of the plastic pipe the pipe blades are sawn from: its curve is their airfoil.
PIPE_BLADE_CURVE = 0.1


def _section(points, turn, shift):
    """An outline of (x, y) points turned `turn` degrees about Z and moved `shift` along X."""
    c, s = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    return [(x * c - y * s + shift, x * s + y * c) for x, y in points]


def _blade(col, name, kind, size, kept=None):
    """A blade along +Z from its root at the origin, its chord along X, made the way its material
    allows, so each reads apart at a glance:
    - "wood": carved from a plank, thick at a square root block bolted on, a twisted airfoil
      tapering to a rounded tip, the grain along it;
    - "pipe": sawn lengthwise from plastic pipe, a thin curved shell that keeps the pipe's grey,
      cut on a straight taper, its flat root bolted to a steel strap;
    - "steel": hammered from sheet, thin, flat and narrow to a point, a welded strap at its root,
      bare steel pocked by the hammer.
    Each blade is one mesh lofted through its sections (kit.loft), so the bake gives it one long
    stretch of texture. A blade a storm snapped keeps only its first `kept` of `pieces` lengths
    from the root, and no tip."""
    length, chord, thick = size
    pieces = 6
    kept = pieces if kept is None else kept
    bolt = M("weld")
    parts = []

    def stations(foot):
        return [(j / pieces, foot + j * length / pieces) for j in range(kept + 1)]

    if kind == "wood":
        mat = M("carvedwood")
        parts.append(box(col, name, mat, (chord * 0.9, thick * 2.2, 0.1), bevel=0.006))
        # An airfoil as thick as the plank's piece there: round at the leading edge (-X), thinning
        # to the trailing edge.
        foil = [(math.cos(a) / 2, math.sin(a) * (0.45 - 0.27 * math.cos(a)))
                for a in (2 * math.pi * k / 10 for k in range(10))]
        parts.append(loft(col, name, mat, [(z, _section([(x * chord * (1 - 0.55 * t), y * thick * (1.6 - 0.9 * t))
                                                         for x, y in foil], 26 - 20 * t, chord * 0.18 * t))
                                           for t, z in stations(0.08)]))
        if kept == pieces:
            parts.append(mound(col, name, mat, (chord * 0.22, thick * 0.35, 0.05), at=(chord * 0.18, 0, 0.08 + length - 0.004),
                               rotate=(0, 0, 6), segments=10, rings=3))
        for z in (0.03, 0.07):
            parts.append(cylinder(col, name, bolt, 0.01, 0.006, at=(0, -thick * 1.1, z), rotate=(90, 0, 0), segments=6))
    elif kind == "pipe":
        mat = M("pvc")
        parts.append(box(col, name, M("rawsteel"), (chord * 0.6, 0.006, 0.12), at=(0, 0.004, -0.02)))
        wall, arcs = 0.005, 6

        def shell(width):
            # The pipe's wall across `width` of its curve: the outside of the arc, then back along
            # the inside.
            span = width / PIPE_BLADE_CURVE
            angles = [(k / arcs - 0.5) * span for k in range(arcs + 1)]
            outer = [(math.sin(a) * PIPE_BLADE_CURVE, PIPE_BLADE_CURVE * (math.cos(a) - 1)) for a in angles]
            inner = [(math.sin(a) * (PIPE_BLADE_CURVE - wall), PIPE_BLADE_CURVE * (math.cos(a) - 1) - wall * math.cos(a))
                     for a in reversed(angles)]
            return outer + inner
        parts.append(loft(col, name, mat, [(z, _section(shell(chord * (1 - 0.6 * t)), 12, chord * 0.2 * t))
                                           for t, z in stations(0.06)]))
        for z in (0.0, 0.06):
            parts.append(cylinder(col, name, bolt, 0.008, 0.006, at=(0, -0.003, z), rotate=(90, 0, 0), segments=6))
    else:
        mat = M("hammered")
        parts.append(box(col, name, M("weld"), (chord * 0.7, thick * 3, 0.07), bevel=0.002))

        def plate(width):
            return [(-width / 2, -thick / 2), (width / 2, -thick / 2), (width / 2, thick / 2), (-width / 2, thick / 2)]
        parts.append(loft(col, name, mat, [(z, _section(plate(chord * (1 - 0.85 * t)), 14 - 10 * t, chord * 0.1 * t))
                                           for t, z in stations(0.05)]))
        for z in (0.02, 0.05):
            parts.append(cylinder(col, name, M("galvanised"), 0.008, 0.005, at=(0, -thick * 1.5, z), rotate=(90, 0, 0), segments=6))
    return parts


def _rotor_blades(col, hub, kind, size):
    """Three blades of `kind` (_blade) bolted round `hub`, turning in the plane that faces -Y."""
    for k in range(3):
        group(col, ROTOR + "Blade", _blade(col, ROTOR + "Blade", kind, size), at=hub, rotate=(0, 120 * k, 0))


def _tail(col, name, start, length, vane, z):
    """A tail boom back (+Y) from `start` and a sheet-metal vane on its end, `vane` long and high,
    that keeps the rotor into the wind."""
    end = (0, start[1] + length, z + 0.03)
    tube(col, name + "_Boom", M("galvanised"), [(0, start[1], z), end], 0.02, 8)
    box(col, name + "_Vane", M("drummetal"), (0.004, vane[0], vane[1]), at=(0, end[1] + vane[0] / 2 - 0.05, z - vane[1] / 2 + 0.05))


def _pipe_mast(col, name, top):
    """A welded pipe mast on a concrete footing, gusseted to its base plate, with the yaw bearing a
    wind charger's head turns on from `top` up."""
    box(col, name + "_Footing", M("concrete"), (0.4, 0.4, 0.08), bevel=0.01)
    box(col, name + "_BasePlate", M("rawsteel"), (0.26, 0.26, 0.012), at=(0, 0, 0.08))
    for angle in (45, 135, 225, 315):
        box(col, name + "_Gusset", M("weld"), (0.1, 0.008, 0.12), at=(*around((0, 0), angle, 0.09), 0.092), rotate=(0, 0, angle))
    cylinder(col, name + "_Mast", M("galvanised"), 0.045, top - 0.092, at=(0, 0, 0.092), segments=14)
    for z in (top / 3, 2 * top / 3):
        ring(col, name + "_MastWeld", M("weld"), (0, 0), 0.046, z, 0.006)
    cylinder(col, name + "_YawBearing", M("weld"), 0.065, 0.07, at=(0, 0, top), segments=14)


def _spinner(col, y, hub):
    """The plate the blades bolt to, its back at `y`, and the nose cone in front of it."""
    cylinder(col, ROTOR + "Spinner", M("rawsteel"), 0.07, 0.05, at=(0, y, hub), rotate=(90, 0, 0), segments=16)
    cylinder(col, ROTOR + "Nose", M("rawsteel"), 0.07, 0.05, at=(0, y - 0.05, hub), rotate=(90, 0, 0), radius_top=0.02, segments=16)


def propeller_charger(col, blades="wood"):
    """The treadmill wind charger: a welded pipe mast on a concrete footing, a yaw bearing on top,
    the treadmill motor as its generator, three blades on its shaft, carved from pine planks
    ("wood"), cut from plastic pipe ("pipe") or forged from sheet steel ("steel"), to the same shape,
    and a tail vane behind."""
    hub = PROPELLER_HUB
    top = hub - 0.12
    _pipe_mast(col, "Prop", top)
    box(col, "Prop_MotorPlate", M("rawsteel"), (0.1, 0.36, 0.01), at=(0, -0.08, hub - 0.075))
    cylinder(col, "Prop_Motor", M("black"), 0.065, 0.3, at=(0, 0.06, hub), rotate=(90, 0, 0), segments=18)
    for y in (0.075, -0.24):
        cylinder(col, "Prop_MotorBell", M("aluminium"), 0.067, 0.015, at=(0, y, hub), rotate=(90, 0, 0), segments=18)
    _tail(col, "Prop_Tail", (0, 0.06), 0.8, (0.42, 0.32), hub)
    tube(col, "Prop_Cable", M("black"), [(0.04, 0.04, hub - 0.07), (0.055, 0.0, top), (0.055, 0.0, 0.3), (0.12, 0.08, 0.09),
                                         (0.2, 0.2, 0.0)], 0.007, 6)
    _spinner(col, -0.255, hub)
    _rotor_blades(col, (0, -0.28, hub), blades, PROPELLER_BLADE)


CAR_ALTERNATOR_RADIUS = 0.065  # its case's
CAR_ALTERNATOR_PULLEY = (0.036, 0.03)  # its pulley's radius and width


def _car_alternator(col, name):
    """A car's alternator, its axis along Y, its pulley's front face at the origin and the rest
    behind (+Y): the pulley and the cooling fan behind it, the cast aluminium case in two halves
    slotted for air, the dark stator core showing between them and the through-bolts along it,
    the mounting ears below and the adjusting ear above, the output stud and the regulator's plug
    at the back."""
    radius = CAR_ALTERNATOR_RADIUS
    pulley, width = CAR_ALTERNATOR_PULLEY
    alloy = M("aluminium")
    parts = [cylinder(col, name + "Nut", M("galvanised"), 0.012, 0.008, at=(0, 0, 0), rotate=(90, 0, 0), segments=6),
             cylinder(col, name + "Pulley", M("rawsteel"), pulley, width, at=(0, width, 0), rotate=(90, 0, 0), segments=20)]
    fan = width + 0.003
    parts.append(cylinder(col, name + "FanDisc", M("darkgrey"), radius - 0.006, 0.003, at=(0, fan + 0.003, 0), rotate=(90, 0, 0),
                          segments=20))
    for k in range(12):
        a = 30 * k
        x, z = around((0, 0), a, 0.024)
        parts.append(box(col, name + "FanBlade", M("darkgrey"), (0.004, 0.012, radius - 0.032), at=(x, fan + 0.009, z),
                         rotate=(0, 90 - a, 0)))
    front, core, back = fan + 0.016, fan + 0.056, fan + 0.074
    end = back + 0.06
    parts.append(cylinder(col, name + "FrontCase", alloy, radius, core - front, at=(0, core, 0), rotate=(90, 0, 0), segments=22))
    parts.append(cylinder(col, name + "Stator", M("weld"), radius + 0.002, back - core, at=(0, back, 0), rotate=(90, 0, 0), segments=22))
    parts.append(cylinder(col, name + "RearCase", alloy, radius, end - back, at=(0, end, 0), rotate=(90, 0, 0), segments=22))
    parts.append(cylinder(col, name + "RearCap", M("darkgrey"), radius * 0.65, 0.018, at=(0, end + 0.018, 0), rotate=(90, 0, 0),
                          segments=18))
    # The air slots round each half: dark windows on the case, which a boolean cut would only
    # thicken into the same look.
    for k in range(8):
        a = 45 * k + 22.5
        for y in ((front + core) / 2, (back + end) / 2):
            x, z = around((0, 0), a, radius - 0.0015)
            parts.append(box(col, name + "Slot", M("black"), (0.02, 0.022, 0.003), at=(x, y, z), rotate=(0, 90 - a, 0)))
    for k in range(4):
        x, z = around((0, 0), 90 * k + 45, radius - 0.002)
        parts.append(cylinder(col, name + "ThroughBolt", M("galvanised"), 0.005, end - front, at=(x, end, z), rotate=(90, 0, 0), segments=6))
    for y in (front + 0.012, end - 0.012):
        parts.append(box(col, name + "Ear", alloy, (0.028, 0.022, 0.04), at=(0, y, -radius - 0.035), bevel=0.004))
    parts.append(cylinder(col, name + "PivotBolt", M("galvanised"), 0.007, end - front + 0.01, at=(0, end + 0.005, -radius - 0.018),
                          rotate=(90, 0, 0), segments=8))
    parts.append(box(col, name + "AdjustEar", alloy, (0.026, 0.02, 0.03), at=(0, front + 0.012, radius - 0.008), bevel=0.004))
    parts.append(cylinder(col, name + "Stud", M("copper"), 0.005, 0.035, at=(0.028, end, 0.02), rotate=(-90, 0, 0), segments=8))
    parts.append(box(col, name + "Plug", M("black"), (0.022, 0.016, 0.018), at=(-0.026, end + 0.024, 0.012)))
    return parts


def _flat_belt(col, name, mat, a, ra, b, rb, y, width, thick, step=12):
    """An open flat belt round two pulleys turning in the plane at `y`, their centres `a` and `b`
    as (x, z) and their radii `ra` and `rb`: the two straight runs on the pulleys' outer tangents,
    and the belt's wrap round each pulley between them, a facet every `step` degrees."""
    angle = math.atan2(b[1] - a[1], b[0] - a[0])
    # Each run leaves both pulleys at the same angle about their centres, off the line between them.
    off = math.acos((ra - rb) / math.dist(a, b))

    def arc(centre, radius, start, span):
        count = max(2, int(math.degrees(span) / step))
        return [around(centre, math.degrees(start + span * i / count), radius + thick / 2) for i in range(count + 1)]

    loop = arc(a, ra, angle + off, 2 * math.pi - 2 * off) + arc(b, rb, angle - off, 2 * off)
    for p, q in zip(loop, loop[1:] + loop[:1]):
        beam(col, name, mat, (p[0], y, p[1]), (q[0], y, q[1]), (thick, width))


CAR_ALTERNATOR_RAISE = 0.34  # how far the shaft runs above the head plate, for its pulley to clear it
CAR_ALTERNATOR_PULLEY_RADIUS = 0.22  # the rotor's pulley, many times the alternator's to step it up
CAR_ALTERNATOR_X = 0.2  # the alternator beside the mast, clear of the rotor's pulley


def car_alternator_charger(col, blades="wood"):
    """The car alternator wind charger: the treadmill charger's welded pipe mast with a sheet-metal
    head plate on its yaw bearing, three blades on a short shaft in two pillow-block bearings and
    a large flat pulley behind them, a leather flat belt down to the small pulley of a car's
    alternator bolted to the plate beside the mast, and a sheet-metal tail vane clamped rigid
    behind."""
    hub = PROPELLER_HUB
    deck = hub - CAR_ALTERNATOR_RAISE
    top = deck - 0.08
    _pipe_mast(col, "CarAlt", top)
    # The plate stops short of the blades' sweep in front.
    box(col, "CarAlt_HeadPlate", M("rawsteel"), (0.42, 0.56, 0.01), at=(0.1, 0.01, deck - 0.01))
    for y in (-0.22, 0.02):
        box(col, "CarAlt_PedestalFoot", M("rustysteel"), (0.15, 0.06, 0.008), at=(0, y, deck))
        box(col, "CarAlt_Pedestal", M("rustysteel"), (0.08, 0.05, hub - deck - 0.03), at=(0, y, deck))
        cylinder(col, "CarAlt_Bearing", M("darkgrey"), 0.042, 0.06, at=(0, y + 0.03, hub), rotate=(90, 0, 0), segments=14)
        for x in (-0.058, 0.058):
            cylinder(col, "CarAlt_Bolt", M("galvanised"), 0.008, 0.008, at=(x, y, deck + 0.008), segments=6)
    cylinder(col, ROTOR + "Shaft", M("galvanised"), 0.02, 0.36, at=(0, 0.08, hub), rotate=(90, 0, 0), segments=10)
    belt_y = -0.125
    big, width = CAR_ALTERNATOR_PULLEY_RADIUS, 0.05
    cylinder(col, ROTOR + "Pulley", M("rawsteel"), big, width, at=(0, belt_y + width / 2, hub), rotate=(90, 0, 0), segments=32)
    cylinder(col, ROTOR + "PulleyBoss", M("weld"), 0.05, width + 0.02, at=(0, belt_y + width / 2 + 0.01, hub), rotate=(90, 0, 0),
             segments=14)
    for k in range(6):
        x, z = around((0, hub), 60 * k, big * 0.6)
        cylinder(col, ROTOR + "PulleyBolt", M("galvanised"), 0.01, 0.006, at=(x, belt_y - width / 2, z), rotate=(90, 0, 0), segments=6)
    pulley, small_width = CAR_ALTERNATOR_PULLEY
    # The alternator stands on its mounting ears on the plate, its pulley in line with the rotor's.
    axis = deck + CAR_ALTERNATOR_RADIUS + 0.035
    group(col, "CarAlt_Alternator", _car_alternator(col, "CarAlt_Alt"), at=(CAR_ALTERNATOR_X, belt_y - small_width / 2, axis))
    _flat_belt(col, "CarAlt_Belt", M("leather"), (0, hub), big, (CAR_ALTERNATOR_X, axis), pulley, belt_y, small_width - 0.004, 0.006)
    for y in (0.14, 0.24):
        box(col, "CarAlt_TailClamp", M("weld"), (0.06, 0.025, 0.055), at=(0, y, deck), bevel=0.003)
    _tail(col, "CarAlt_Tail", (0, 0.1), 0.85, (0.42, 0.32), deck + 0.03)
    tube(col, "CarAlt_Cable", M("black"), [(CAR_ALTERNATOR_X + 0.03, 0.06, axis + 0.02), (0.33, 0.07, deck - 0.02), (0.1, 0.03, top - 0.15),
                                           (0.055, 0.0, top - 0.3), (0.055, 0.0, 0.3), (0.12, 0.08, 0.09), (0.2, 0.2, 0.0)], 0.007, 6)
    _spinner(col, -0.28, hub)
    _rotor_blades(col, (0, -0.305, hub), blades, PROPELLER_BLADE)


def _alternator_head(col, rotor):
    """A homemade axial-flux alternator built on a car's front brake hub, its axis along Y, the hub's
    face at the origin and the rest behind (+Y): a steel magnet disc either side of an amber resin
    stator with its copper coils showing round the rim, the hub's wheel studs and the disc bolts in
    front, the knuckle's spindle behind. The parts that turn are named with `rotor`."""
    parts = [cylinder(col, rotor + "Hub", M("darkgrey"), 0.09, 0.06, at=(0, 0.06, 0), rotate=(90, 0, 0), segments=18)]
    for k in range(5):
        x, z = around((0, 0), 72 * k + 90, 0.055)
        parts.append(cylinder(col, rotor + "Stud", M("galvanised"), 0.007, 0.025, at=(x, 0.002, z), rotate=(90, 0, 0), segments=6))
    for name, y in (("Front", 0.072), ("Rear", 0.133)):
        parts.append(cylinder(col, rotor + "MagnetDisc" + name, M("rawsteel"), 0.2, 0.012, at=(0, y, 0), rotate=(90, 0, 0), segments=28))
    for k in range(6):
        x, z = around((0, 0), 60 * k + 30, 0.15)
        parts.append(cylinder(col, rotor + "DiscBolt", M("galvanised"), 0.009, 0.006, at=(x, 0.06, z), rotate=(90, 0, 0), segments=6))
    parts.append(cylinder(col, "Alt_Stator", M("resin"), 0.23, 0.035, at=(0, 0.115, 0), rotate=(90, 0, 0), segments=28))
    for k in range(9):
        x, z = around((0, 0), 40 * k, 0.205)
        parts.append(cylinder(col, "Alt_Coil", M("copper"), 0.032, 0.039, at=(x, 0.117, z), rotate=(90, 0, 0), segments=12))
    parts.append(cylinder(col, "Alt_Spindle", M("weld"), 0.05, 0.13, at=(0, 0.27, 0), rotate=(90, 0, 0), segments=14))
    return parts


ALTERNATOR_HEAD_Y = -0.32  # the hub's face, in front of the mast


def alternator_charger(col, blades="steel"):
    """The homebuilt wind turbine, the best of the homestead wind chargers: a two-storey braced
    tripod of welded angle iron, kept inside its own square, a homemade alternator on its head,
    three long blades of any kind _blade makes and a tail vane that folds it out of a storm."""
    hub = ALTERNATOR_HUB
    top = hub - 0.2
    feet = [around((0, 0), angle, 0.42) for angle in (90, 210, 330)]
    heads = [around((0, 0), angle, 0.07) for angle in (90, 210, 330)]

    def on_leg(leg, z):
        t = z / top
        return (feet[leg][0] + (heads[leg][0] - feet[leg][0]) * t, feet[leg][1] + (heads[leg][1] - feet[leg][1]) * t, z)

    for leg in range(3):
        cylinder(col, "Alt_Footing", M("concrete"), 0.08, 0.05, at=(*feet[leg], 0), segments=12)
        beam(col, "Alt_Leg", M("rustysteel"), on_leg(leg, 0.05), on_leg(leg, top), (0.045, 0.045))
    levels = (0.9, 1.9, 2.8, 3.6)
    for i, z in enumerate(levels):
        for leg in range(3):
            beam(col, "Alt_Brace", M("rustysteel"), on_leg(leg, z), on_leg((leg + 1) % 3, z), (0.03, 0.03))
            low = levels[i - 1] if i else 0.05
            beam(col, "Alt_Diagonal", M("rustysteel"), on_leg(leg, low), on_leg((leg + 1) % 3, z), (0.025, 0.025))
    cylinder(col, "Alt_TopPlate", M("weld"), 0.12, 0.02, at=(0, 0, top), segments=16)
    cylinder(col, "Alt_YawBearing", M("weld"), 0.06, 0.1, at=(0, 0, top + 0.02), segments=14)
    beam(col, "Alt_Frame", M("rustysteel"), (0, 0.02, top + 0.11), (0, ALTERNATOR_HEAD_Y + 0.3, hub), (0.05, 0.05))
    group(col, "Alt_Head", _alternator_head(col, ROTOR), at=(0, ALTERNATOR_HEAD_Y, hub))
    cylinder(col, "Alt_FurlHinge", M("weld"), 0.025, 0.22, at=(0.06, 0.05, hub - 0.12), segments=10)
    _tail(col, "Alt_Tail", (0, 0.05), 1.05, (0.55, 0.42), hub)
    tube(col, "Alt_Cable", M("black"), [(0.03, 0.05, hub - 0.1), on_leg(0, top - 0.05), on_leg(0, 0.3), (feet[0][0] + 0.05, feet[0][1], 0.0)],
         0.007, 6)
    _rotor_blades(col, (0, ALTERNATOR_HEAD_Y - 0.01, hub), blades, ALTERNATOR_BLADE)


# Each kind of blade's size, and how far apart its blades stack in a bundle: their roots'
# thickness, or a pipe blade's curve.
BLADE_BUNDLES = {"wood": (PROPELLER_BLADE, 2.4 * PROPELLER_BLADE[2]), "pipe": (PROPELLER_BLADE, 0.03),
                 "steel": (ALTERNATOR_BLADE, 3.2 * ALTERNATOR_BLADE[2])}


def blade_bundle(col, kind):
    """Three blades of `kind` stacked flat and tied with twine at two places."""
    size, spacing = BLADE_BUNDLES[kind]
    length, chord, _ = size
    name = "%sBlades" % kind.title()
    for i in range(3):
        # Span along X, chord along Y, flat side up.
        group(col, name, _blade(col, name, kind, size), at=(-length / 2, 0, spacing * (0.5 + i)), rotate=(90, 0, 90))
    for x in (-length * 0.2, length * 0.25):
        box(col, name + "_Twine", M("tape"), (0.012, chord + 0.02, spacing * 3.2), at=(x, chord * 0.1, 0))


def broken_blades(col, kind):
    """Three blades of `kind` a storm snapped, their root ends lying splayed in a loose heap."""
    size, spacing = BLADE_BUNDLES[kind]
    length, chord, _ = size
    name = "Broken%sBlades" % kind.title()
    for i, (kept, turn) in enumerate(((3, 0), (2, 25), (4, -20))):
        group(col, name, _blade(col, name, kind, size, kept=kept),
              at=(-length * 0.3, chord * 0.4 * (i - 1), spacing * (0.5 + i)), rotate=(90, 0, 90 + turn))


def homemade_alternator(col):
    """The homemade alternator lying on its back, the hub's face up."""
    group(col, "AltItem", _alternator_head(col, "AltItem_"), at=(0, 0, 0.27), rotate=(-90, 0, 0))


def car_alternator(col):
    """A car's alternator, loose, standing on its mounting ears, its pulley on."""
    group(col, "CarAltItem", _car_alternator(col, "CarAltItem_"), at=(0, -0.085, CAR_ALTERNATOR_RADIUS + 0.035))


# The sprite model's yaw that turns a south-facing model to face each way. The game draws an
# exported model half a turn round from how it was built, so these are kit.FACING_TURN's turned
# half round again (seen in the art mode's art_wind_tall shot).
FACING_YAWS = {"N": 0, "E": -90, "S": 180, "W": 90}

# Sprite models by name. "skins" are the builders' options for each skin, a mesh and texture of
# its own, by the name after the model's; "yaws" the turns of the whole model, by the name after
# that; "spins" the rotor's angles in degrees about the hub at height "hub", a mesh each, named by
# their index last. A sprite model's name is the model's, the skin's, the yaw's and the spin's, so
# the scoop rotor, the same after half a turn and spun by turning it whole, is ScoopRotor and an
# index. Every blade machine takes every blade set, a skin each: each set's blades are shaped
# their own way (_blade), and baked onto another set's shape they would leave its edges uncoloured.
BLADE_SKINS = {"Wood": {"blades": "wood"}, "Pipe": {"blades": "pipe"}, "Steel": {"blades": "steel"}}
SPRITE_MODELS = {
    "ScoopRotor": {"model": scoop_rotor, "yaws": {str(step): 30 * step for step in range(6)}},
    "Propeller": {"model": propeller_charger, "skins": BLADE_SKINS, "yaws": FACING_YAWS, "spins": ROTOR_SPINS, "hub": PROPELLER_HUB},
    "CarAlternator": {"model": car_alternator_charger, "skins": BLADE_SKINS, "yaws": FACING_YAWS, "spins": ROTOR_SPINS,
                      "hub": PROPELLER_HUB},
    "Alternator": {"model": alternator_charger, "skins": BLADE_SKINS, "yaws": FACING_YAWS, "spins": ROTOR_SPINS, "hub": ALTERNATOR_HUB},
}


def sprite_model_names(name):
    """A sprite model's skins as (texture, meshes), a mesh per spin step, and its sprite models as
    (name, mesh, texture, yaw)."""
    spec = SPRITE_MODELS[name]
    spins = spec.get("spins", (0,))
    steps = [str(index) if len(spins) > 1 else "" for index in range(len(spins))]
    skins = [(name + skin, [name + skin + step for step in steps]) for skin in spec.get("skins") or {"": {}}]
    sprites = [(texture + label + step, mesh, texture, yaw)
               for texture, meshes in skins for label, yaw in spec["yaws"].items() for step, mesh in zip(steps, meshes)]
    return skins, sprites
