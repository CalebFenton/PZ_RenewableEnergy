"""Inverters, the charge controller, the failsafe, small solar chargers, and the transformers the
homemade inverters are wound on."""
import math

from art.kit import box, cylinder, group, prism, ring, text, tube
from palette import M
from parts import BOARD, SHEET, side_handles


# Electronics --------------------------------------------------------------------------------------


def fins(col, name, mat, width, depth, z, count, height=0.008):
    """A row of `count` heat-sink fins or louvres across `width`, each running front to back: 8 mm
    thick, about a pixel at the game's closest zoom, as a thinner one comes and goes as it draws."""
    for i in range(count):
        box(col, name, mat, (0.008, depth * 0.9, height), at=(-width / 2 + (i + 0.5) * width / count, 0, z))


def outlet(col, name, at, scale=1.0, turn=0):
    """A US NEMA 5-15 receptacle face: two slots and a ground hole, facing -Y before `turn` degrees
    about Z."""
    parts = [box(col, name + "_Face", M("cream"), (0.034 * scale, 0.003, 0.04 * scale), bevel=0.003)]
    for dx in (-0.007, 0.007):
        parts.append(box(col, name + "_Slot", M("ink"), (0.003 * scale, 0.002, 0.011 * scale),
                         at=(dx * scale, -0.002, 0.02 * scale)))
    parts.append(box(col, name + "_Ground", M("ink"), (0.005 * scale, 0.002, 0.005 * scale), at=(0, -0.002, 0.007 * scale)))
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


def sticker(col, name, band, size, at, rotate=None):
    """A maker's rating sticker, as most of the game's own electronics carry: white with a coloured
    band along its top edge. `size` = (width, height), standing and facing -Y before `rotate`, its
    bottom centre at `at` on the face it is stuck to."""
    width, height = size
    parts = [box(col, name, M("label"), (width, 0.0008, height), at=(0, -0.0004, 0)),
             box(col, name + "Band", M(band), (width, 0.0008, height * 0.3), at=(0, -0.0008, height * 0.7))]
    return group(col, name + "_At", parts, at=at, rotate=rotate)


def plug_in_inverter(col):
    """A 140 W inverter for a cigarette lighter socket: an aluminium extrusion, one outlet, a cord."""
    box(col, "PlugInv_Body", M("aluminium"), (0.14, 0.075, 0.045), bevel=0.006)
    fins(col, "PlugInv_Rib", M("aluminium"), 0.12, 0.075, 0.045, 7, height=0.003)
    for sign in (-1, 1):
        box(col, "PlugInv_Cap", M("black"), (0.012, 0.079, 0.049), at=(sign * 0.072, 0, -0.002), bevel=0.004)
    outlet(col, "PlugInv_Outlet", (-0.079, 0, 0.003), scale=0.9, turn=-90)
    tube(col, "PlugInv_Cord", M("black"), [(0.078, 0, 0.02), (0.13, 0.01, 0.01), (0.17, 0.06, 0.005),
                                           (0.12, 0.1, 0.005), (0.06, 0.09, 0.005)], 0.0035)
    cylinder(col, "PlugInv_Plug", M("black"), 0.011, 0.05, at=(0.06, 0.09, 0.011), rotate=(0, -90, 0), segments=10)
    box(col, "PlugInv_Led", M("ledgreen"), (0.006, 0.003, 0.006), at=(-0.04, -0.039, 0.02))
    sticker(col, "PlugInv_Sticker", "red", (0.045, 0.022), (0.03, -0.0375, 0.012))


def power_inverter(col):
    """A 600 W inverter: a charcoal steel case with black louvres and a rating sticker on top, and
    on a brushed aluminium faceplate two outlets, a switch and a light."""
    width, depth, height = 0.3, 0.18, 0.075
    box(col, "Inv600_Case", M("darkgrey"), (width, depth, height), bevel=0.006)
    fins(col, "Inv600_Louvre", M("black"), width * 0.6, depth * 0.6, height, 9, height=0.002)
    box(col, "Inv600_Panel", M("aluminium"), (width - 0.02, 0.003, height - 0.015), at=(0, -depth / 2 - 0.001, 0.007))
    outlet(col, "Inv600_OutletA", (-0.09, -depth / 2 - 0.003, 0.016))
    outlet(col, "Inv600_OutletB", (-0.04, -depth / 2 - 0.003, 0.016))
    box(col, "Inv600_Switch", M("red"), (0.02, 0.008, 0.025), at=(0.05, -depth / 2 - 0.004, 0.025), bevel=0.003)
    box(col, "Inv600_Led", M("ledgreen"), (0.008, 0.004, 0.008), at=(0.09, -depth / 2 - 0.003, 0.04))
    text(col, "Inv600_Text", M("ink"), "600W", 0.02, at=(0.09, -depth / 2 - 0.004, 0.015))
    sticker(col, "Inv600_Sticker", "red", (0.045, 0.06), (0.12, -0.03, height), rotate=(-90, 0, 0))
    for sign, colour in ((1, "red"), (-1, "black")):
        cylinder(col, "Inv600_Terminal", M(colour), 0.012, 0.02, at=(sign * 0.05, depth / 2 + 0.01, 0.025),
                 rotate=(90, 0, 0), segments=10)


def inverter_charger(col):
    """A 2,500 W inverter/charger: a heavy blue-grey cabinet with a black control panel, heat-sink
    fins on top, carrying handles, big terminal covers and a rating sticker on its side."""
    width, depth, height = 0.52, 0.28, 0.22
    box(col, "InvChg_Case", M("bluegrey"), (width, depth, height), bevel=0.01)
    fins(col, "InvChg_Fin", M("aluminium"), width * 0.9, depth * 0.9, height, 16, height=0.025)
    box(col, "InvChg_Panel", M("black"), (0.3, 0.004, 0.14), at=(-0.08, -depth / 2 - 0.002, 0.04), bevel=0.002)
    for i, colour in enumerate(("ledgreen", "ledyellow", "ledred", "ledoff")):
        box(col, "InvChg_Led", M(colour), (0.012, 0.004, 0.012), at=(-0.2 + i * 0.03, -depth / 2 - 0.004, 0.14))
    cylinder(col, "InvChg_Knob", M("grey"), 0.02, 0.015, at=(0.02, -depth / 2 - 0.003, 0.09), rotate=(90, 0, 0), segments=14)
    text(col, "InvChg_Text", M("white"), "2500", 0.03, at=(-0.13, -depth / 2 - 0.005, 0.06))
    outlet(col, "InvChg_Outlet", (0.15, -depth / 2 - 0.003, 0.06), scale=1.2)
    side_handles(col, "InvChg_Handle", M("darkgrey"), width / 2, (0.06, 0.16), (0.05, 0.16), 0.035, 0.008)
    for x, colour in ((0.12, "red"), (0.2, "black")):
        box(col, "InvChg_TermCover", M(colour), (0.06, 0.05, 0.05), at=(x, depth / 2 + 0.02, 0.02), bevel=0.01)
    sticker(col, "InvChg_Sticker", "navy", (0.1, 0.06), (width / 2, 0.03, 0.04), rotate=(0, 0, 90))


def charge_controller(col):
    """A 30 A charge controller: a navy anodised box with fins and a rating sticker on top, three
    LEDs and a terminal strip."""
    width, depth, height = 0.19, 0.13, 0.055
    box(col, "Ctrl_Case", M("navy"), (width, depth, height), bevel=0.005)
    fins(col, "Ctrl_Fin", M("aluminium"), width * 0.55, depth, height, 6, height=0.012)
    for i, colour in enumerate(("ledgreen", "ledyellow", "ledred")):
        box(col, "Ctrl_Led", M(colour), (0.008, 0.004, 0.008), at=(-0.06 + i * 0.02, -depth / 2 - 0.002, 0.03))
    box(col, "Ctrl_Strip", M("black"), (0.16, 0.025, 0.02), at=(0, depth / 2 + 0.01, 0.0), bevel=0.003)
    for i in range(6):
        cylinder(col, "Ctrl_Screw", M("lead"), 0.005, 0.004, at=(-0.065 + i * 0.026, depth / 2 + 0.012, 0.02), segments=8)
    text(col, "Ctrl_Text", M("white"), "30A", 0.02, at=(0.05, -depth / 2 - 0.002, 0.018))
    sticker(col, "Ctrl_Sticker", "red", (0.03, 0.07), (-0.074, -0.035, height), rotate=(-90, 0, 0))


def solar_failsafe(col, cable=True):
    """A generator auto-start relay box: grey enclosure, its lid screwed down at the corners, a
    warning label, LED, and a control cable out through a gland in its side."""
    width, depth, height = 0.18, 0.1, 0.14
    box(col, "Failsafe_Case", M("grey"), (width, depth, height), bevel=0.008)
    box(col, "Failsafe_Lid", M("darkgrey"), (width + 0.006, depth + 0.006, 0.012), at=(0, 0, height - 0.012), bevel=0.004)
    box(col, "Failsafe_Label", M("yellow"), (0.12, 0.002, 0.045), at=(0, -depth / 2 - 0.001, 0.05))
    text(col, "Failsafe_Text", M("ink"), "AUTO START", 0.0135, at=(0, -depth / 2 - 0.0025, 0.068))
    box(col, "Failsafe_Led", M("ledgreen"), (0.012, 0.004, 0.012), at=(0.06, -depth / 2 - 0.002, 0.1))
    box(col, "Failsafe_Switch", M("black"), (0.02, 0.006, 0.02), at=(-0.06, -depth / 2 - 0.002, 0.095))
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylinder(col, "Failsafe_Screw", M("lead"), 0.005, 0.002, at=(sx * (width / 2 - 0.014), sy * (depth / 2 - 0.014), height),
                     segments=8)
    # The gland: a hex nut against the side and a domed cap the cable comes out of.
    gland_y, gland_z = 0.02, 0.04
    cylinder(col, "Failsafe_GlandNut", M("darkgrey"), 0.014, 0.006, at=(width / 2, gland_y, gland_z), rotate=(0, 90, 0), segments=6)
    cylinder(col, "Failsafe_Gland", M("darkgrey"), 0.011, 0.016, at=(width / 2 + 0.006, gland_y, gland_z), rotate=(0, 90, 0),
             segments=12, radius_top=0.008)
    if cable:
        tube(col, "Failsafe_Cable", M("black"), [(width / 2 + 0.02, gland_y, gland_z), (width / 2 + 0.06, 0.03, 0.006),
                                                 (width / 2 + 0.16, 0.1, 0.006), (width / 2 + 0.2, 0.22, 0.006)], 0.007)


def solar_cell_charger(col):
    """A solar charger for AA cells: a yellow tray, a small mono panel in its lid, four cell bays."""
    width, depth, height = 0.18, 0.11, 0.035
    box(col, "CellChg_Tray", M("yellow"), (width, depth, height), bevel=0.006)
    box(col, "CellChg_Panel", M("black"), (0.1, depth - 0.02, 0.003), at=(-0.03, 0, height), bevel=0.001)
    for i in range(4):
        for j in range(2):
            box(col, "CellChg_Cell", M("mono"), (0.021, 0.035, 0.002), at=(-0.066 + i * 0.024, -0.02 + j * 0.04, height + 0.002))
    for i in range(4):
        box(col, "CellChg_Bay", M("darkgrey"), (0.012, 0.06, 0.004), at=(0.035 + i * 0.016, 0, height - 0.002))
    box(col, "CellChg_Led", M("ledgreen"), (0.008, 0.008, 0.004), at=(0.075, 0.042, height))


def amorphous_panel(col, name, size, stripes):
    """A small thin-film panel as on battery maintainers: dark blue glass striped by the
    silver lines between its cell strips, in an aluminium frame."""
    width, depth, height = size
    border = 0.015
    parts = [box(col, name + "_Frame", M("aluminium"), size, bevel=0.004),
             box(col, name + "_Film", M("amorphous"), (width - 2 * border, depth - 2 * border, 0.002),
                 at=(0, 0, height - 0.001))]
    for i in range(1, stripes):
        x = -width / 2 + border + i * (width - 2 * border) / stripes
        parts.append(box(col, name + "_Scribe", M("busbar"), (0.0025, depth - 2 * border, 0.0005),
                         at=(x, 0, height + 0.0008)))
    return parts


def solar_maintainer(col):
    """A 10 W battery maintainer: an amorphous panel on a fold-out stand, its cable ending in red
    and black clips and a lighter plug."""
    # Propped up at the back, its front edge on the ground.
    tilt = 18
    group(col, "Maint_Panel", amorphous_panel(col, "Maint", (0.34, 0.27, 0.018), 16),
          at=(0, 0, 0.135 * math.sin(math.radians(tilt))), rotate=(tilt, 0, 0))
    box(col, "Maint_Stand", M("black"), (0.24, 0.015, 0.085), at=(0, 0.11, 0), rotate=(-20, 0, 0))
    box(col, "Maint_Diode", M("black"), (0.05, 0.03, 0.02), at=(0.24, -0.06, 0), bevel=0.004)
    tube(col, "Maint_Cable", M("black"), [(0.17, 0.0, 0.04), (0.22, -0.04, 0.01), (0.24, -0.06, 0.01)], 0.004)
    for dx, colour in ((-0.025, "red"), (0.025, "black")):
        tube(col, "Maint_Lead", M(colour), [(0.24 + dx * 0.3, -0.075, 0.008), (0.25 + dx, -0.12, 0.006), (0.27 + dx * 1.6, -0.16, 0.006)], 0.003)
        box(col, "Maint_Clip", M(colour), (0.024, 0.065, 0.02), at=(0.27 + dx * 1.6, -0.2, 0), bevel=0.005)
    cylinder(col, "Maint_Plug", M("black"), 0.011, 0.055, at=(0.3, 0.02, 0.011), rotate=(90, 0, 0), segments=10)


# Transformers and homemade inverters --------------------------------------------------------------
#
# A homebuilt inverter of the day was a push-pull pair of power transistors driving a mains
# transformer backwards: a battery charger's on a scrap board, or a microwave oven's, its secondary
# stripped and rewound with a few turns of heavy wire, on a bent-up chassis.

# E-I cores: the width, the lamination stack's depth and the height. A microwave oven's is heavy and
# nearly a cube; a car battery charger's is smaller.
MOT_CORE = (0.1, 0.06, 0.084)
CHARGER_CORE = (0.07, 0.04, 0.058)
# Between the lines drawn between laminations: a packet of them each, as a line a lamination apart
# would blur to grey.
LAMINATION_PITCH = 0.0075


def _transformer(col, name, core, windings, at=(0, 0, 0), spades=False, screwed=False):
    """A transformer on its steel mounting feet: an E-I core of stacked laminations, `core` = its
    width, the stack's depth along Y and its height, the lines between the laminations on its top
    and ends, weld beads across the stack where the I meets the E, and the windings round its
    centre leg bulging out of the stack front and back, `windings` naming them from the bottom up:
    "copper" or "enamel" wire, or "rewound", a few turns of heavy insulated wire. `spades` adds the
    bottom winding's two spade terminals at the front, `screwed` a screw through each foot."""
    width, depth, height = core
    leg = width / 6  # an outer leg's width, and a window's; the centre leg is twice it
    tab = width * 0.22
    foot = 0.003
    ear = height * 0.25
    parts = [box(col, name + "_Feet", M("rawsteel"), (width + 2 * tab, depth, foot), bevel=0.001)]
    for sign in (-1, 1):
        parts.append(box(col, name + "_FootEar", M("rawsteel"), (foot, depth, ear), at=(sign * (width / 2 + foot / 2), 0, foot)))
        hole = (sign * (width / 2 + tab / 2), 0, foot)
        if screwed:
            parts.append(cylinder(col, name + "_Screw", M("galvanised"), 0.0045, 0.003, at=hole, segments=8))
        else:
            parts.append(cylinder(col, name + "_Hole", M("ink"), 0.004, 0.001, at=hole, segments=10))
    parts.append(box(col, name + "_Core", M("lamination"), (width, depth, height), at=(0, 0, foot), bevel=0.0015))
    top, joint = foot + height, foot + height - leg
    count = max(2, round(depth / LAMINATION_PITCH))
    for i in range(1, count):
        y = -depth / 2 + depth * i / count
        parts.append(box(col, name + "_Seam", M("darkgrey"), (width - 0.003, 0.0012, 0.0008), at=(0, y, top)))
        for sign in (-1, 1):
            parts.append(box(col, name + "_Seam", M("darkgrey"), (0.0008, 0.0012, height - ear - 0.003),
                             at=(sign * (width / 2 + 0.0004), y, foot + ear + 0.001)))
    for sign in (-1, 1):
        parts.append(box(col, name + "_Joint", M("weld"), (width - 0.003, 0.0008, 0.0012), at=(0, sign * (depth / 2 + 0.0004), joint)))
        parts.append(box(col, name + "_Weld", M("weld"), (0.003, depth + 0.002, 0.004), at=(sign * (width / 2 + 0.0015), 0, joint - 0.002),
                         bevel=0.001))
    proud = depth * 0.28
    gap = 0.004
    span = (height - 2 * leg - gap * (len(windings) - 1)) / len(windings)
    for k, kind in enumerate(windings):
        z = foot + leg + k * (span + gap)
        for sign in (-1, 1):
            if kind == "rewound":
                turns = 3
                radius = span / turns / 2
                parts.append(box(col, name + "_Turns", M("black"), (4 * leg - 0.004, proud, span), at=(0, sign * depth / 2, z), bevel=0.003))
                for t in range(turns):
                    zt = z + radius * (2 * t + 1)
                    y = sign * (depth / 2 + proud - radius)
                    parts.append(tube(col, name + "_Turn", M("black"), [(-2 * leg + radius, y, zt), (2 * leg - radius, y, zt)], radius, 8))
            else:
                parts.append(box(col, name + "_Winding", M(kind), (4 * leg, proud + 0.004, span),
                                 at=(0, sign * (depth / 2 + proud / 2 - 0.002), z), bevel=0.004))
    if spades:
        z = foot + leg + span / 2
        front = -(depth / 2 + proud)
        for x in (-leg, leg):
            parts.append(box(col, name + "_SpadeBase", M("cream"), (0.011, 0.006, 0.009), at=(x, front, z - 0.0045), bevel=0.001))
            parts.append(box(col, name + "_Spade", M("lead"), (0.0065, 0.012, 0.003), at=(x, front - 0.008, z - 0.0015)))
    return group(col, name, parts, at=at)


def microwave_transformer(col):
    """A microwave oven's transformer, pulled from a dead oven: the heavy laminated core welded
    across its ends, the copper primary below and the enamelled high-voltage secondary above, on
    its mounting feet, the primary's two spade terminals at the front."""
    _transformer(col, "MOT", MOT_CORE, ("copper", "enamel"), spades=True)


def _to3(col, name, at, turn=0):
    """A TO-3 power transistor bolted down, a 2N3055 as most homebuilt inverters used: a steel can
    on a flange pointed at both ends, a screw through each, white heat-sink compound squeezed out
    round it, its length along X before `turn` degrees about Z."""
    half, wide, thick, grease = 0.0195, 0.0125, 0.003, 0.0015
    outline = [(-half, 0), (-0.009, -wide), (0.009, -wide), (half, 0), (0.009, wide), (-0.009, wide)]
    parts = [prism(col, name + "_Grease", M("white"), [(x * 1.15, z * 1.2) for x, z in outline], grease, at=(0, 0, grease / 2),
                   rotate=(90, 0, 0)),
             prism(col, name + "_Flange", M("worn"), outline, thick, at=(0, 0, grease + thick / 2), rotate=(90, 0, 0)),
             cylinder(col, name + "_Can", M("aluminium"), 0.0115, 0.008, at=(0, 0, grease + thick), segments=16)]
    for sign in (-1, 1):
        parts.append(cylinder(col, name + "_Screw", M("galvanised"), 0.003, 0.003, at=(sign * 0.015, 0, grease + thick), segments=8))
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


def _heatsink(col, name, size, at, transistors, finish="aluminium"):
    """A finned heat sink lying fins up, bare aluminium or another `finish`, `size` = (width, depth,
    fin height), its bottom centre at `at`: two fins each side of a flat channel down its length,
    and `transistors` TO-3s bolted in a row along the channel."""
    width, depth, fin = size
    x, y, z = at
    base, channel = 0.005, 0.028
    box(col, name + "_Base", M(finish), (width, depth, base), at=at, bevel=0.001)
    pitch = (width - channel) / 4
    for sign in (-1, 1):
        for i in range(2):
            box(col, name + "_Fin", M(finish), (0.006, depth, fin), at=(x + sign * (channel / 2 + pitch * (i + 0.5)), y, z + base),
                bevel=0.001)
    step = depth / transistors
    for i in range(transistors):
        _to3(col, name + "_Transistor", (x, y - depth / 2 + step * (i + 0.5), z + base), turn=90)


def _toggle(col, name, at, turn=0):
    """A bat-handle toggle switch through a panel facing -Y before `turn` degrees about Z: its hex
    nut and its chrome lever, thrown up."""
    parts = [cylinder(col, name + "_Nut", M("galvanised"), 0.008, 0.004, rotate=(90, 0, 0), segments=6),
             cylinder(col, name + "_Bushing", M("worn"), 0.0045, 0.009, rotate=(90, 0, 0), segments=10),
             tube(col, name + "_Bat", M("worn"), [(0, -0.009, 0), (0, -0.013, 0.007), (0, -0.016, 0.014)], 0.003, 8)]
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


def _pilot_light(col, name, at, turn=0):
    """A neon pilot light lit in its chrome bezel, through a panel facing -Y before `turn`."""
    parts = [cylinder(col, name + "_Bezel", M("worn"), 0.007, 0.003, rotate=(90, 0, 0), segments=12),
             cylinder(col, name + "_Lens", M("ledred"), 0.0045, 0.007, rotate=(90, 0, 0), segments=12, radius_top=0.0035)]
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


def _ring_lug(col, name, colour, centre, angle, z=0.0, cable=0.0055):
    """A crimped ring lug lying flat, its ring round `centre` at height `z` and its barrel running
    off at `angle` degrees about Z, sleeved in the cable's `colour`; returns where the cable leaves
    the sleeve."""
    dx, dy = math.cos(math.radians(angle)), math.sin(math.radians(angle))

    def off(d):
        return centre[0] + dx * d, centre[1] + dy * d

    ring(col, name + "_Ring", M("copper"), centre, 0.0075, z + 0.0028, 0.0028)
    box(col, name + "_Tongue", M("copper"), (0.012, 0.011, 0.003), at=(*off(0.013), z), rotate=(0, 0, angle))
    tube(col, name + "_Barrel", M("copper"), [(*off(0.016), z + 0.004), (*off(0.024), z + cable)], 0.0045, 8)
    tube(col, name + "_Sleeve", M(colour), [(*off(0.022), z + cable), (*off(0.036), z + cable)], cable * 1.25, 8)
    return (*off(0.036), z + cable)


def _battery_clamp(col, name, colour, at, turn=0):
    """A battery charger's spring clamp lying on its side, its jaws to -X before `turn` degrees about
    Z and its lead in at +X: two handles in the lead's colour, the spring between them, copper jaws."""
    parts = []
    for z, tilt in ((0.0, 0), (0.009, -5)):
        parts.append(box(col, name + "_Handle", M(colour), (0.06, 0.018, 0.007), at=(0.008, 0, z), rotate=(0, tilt, 0), bevel=0.002))
        parts.append(box(col, name + "_Jaw", M("copper"), (0.022, 0.016, 0.006), at=(-0.032, 0, z), bevel=0.001))
    parts.append(cylinder(col, name + "_Spring", M("galvanised"), 0.006, 0.02, at=(0.0, 0.01, 0.009), rotate=(90, 0, 0), segments=10))
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


def makeshift_inverter(col):
    """A 300 W inverter knocked up on an offcut of pine: a car battery charger's transformer screwed
    down, a heat sink with two power transistors, one outlet in a steel handy box, loose hookup wire
    twisted under a wire nut, a zip cord patched with tape, "300W" in marker, and a pair of leads
    ending in the charger's battery clamps."""
    top = BOARD
    box(col, "MakeInv_Board", M("pine"), (0.19, 0.135, top), bevel=0.002)
    tx, ty = -0.045, 0.02
    _transformer(col, "MakeInv_Transformer", CHARGER_CORE, ("copper", "copper"), at=(tx, ty, top), screwed=True)
    _heatsink(col, "MakeInv_Sink", (0.064, 0.085, 0.02), (0.06, 0.025, top), 2)
    box(col, "MakeInv_HandyBox", M("galvanised"), (0.055, 0.035, 0.052), at=(0.065, -0.045, top), bevel=0.003)
    box(col, "MakeInv_Cover", M("grey"), (0.05, 0.003, 0.05), at=(0.065, -0.064, top + 0.001), bevel=0.001)
    outlet(col, "MakeInv_Outlet", (0.065, -0.0665, top + 0.006))
    # The transistors' leads twisted together under a wire nut, and on to the transformer.
    nut = (0.0, 0.06, top + 0.012)
    for y in (0.004, 0.046):
        tube(col, "MakeInv_Hookup", M("yellow"), [(0.028, y, top + 0.006), (0.012, (y + nut[1]) / 2, top + 0.02),
                                                  (nut[0], nut[1] + (y - 0.025) * 0.1, nut[2])], 0.0022)
    cylinder(col, "MakeInv_WireNut", M("yellow"), 0.0065, 0.014, at=nut, rotate=(0, -90, 0), segments=10, radius_top=0.004)
    tube(col, "MakeInv_Hookup", M("red"), [(nut[0] - 0.014, nut[1], nut[2]), (-0.022, 0.058, top + 0.03), (-0.03, 0.052, top + 0.035)],
         0.0022)
    cord = [(-0.03, -0.012, top + 0.04), (-0.015, -0.03, top + 0.004), (0.012, -0.036, top + 0.009), (0.028, -0.04, top + 0.014),
            (0.0375, -0.042, top + 0.02)]
    tube(col, "MakeInv_Cord", M("white"), cord, 0.0028)
    tube(col, "MakeInv_Tape", M("black"), [(-0.008, -0.0315, top + 0.005), (0.004, -0.0335, top + 0.007)], 0.0042, 8)
    text(col, "MakeInv_Marker", M("ink"), "300W", 0.016, at=(-0.018, -0.062, top + 0.0005), rotate=(0, 0, 0))
    for colour, points, clamp in (
            ("red", [(-0.055, -0.011, top + 0.02), (-0.058, -0.04, top + 0.004), (-0.052, -0.065, top + 0.003), (-0.045, -0.079, 0.012),
                     (-0.038, -0.092, 0.006), (-0.033, -0.097, 0.004)], (-0.071, -0.097)),
            ("black", [(0.035, -0.02, top + 0.004), (0.02, -0.045, top + 0.003), (0.022, -0.066, top + 0.003), (0.03, -0.08, 0.012),
                       (0.036, -0.1, 0.006), (0.038, -0.117, 0.004)], (0.0, -0.117))):
        tube(col, "MakeInv_Lead", M(colour), points, 0.003)
        _battery_clamp(col, "MakeInv_Clamp", colour, (*clamp, 0))


def homemade_inverter(col):
    """A 600 W inverter built on a microwave oven's transformer, its secondary stripped and rewound
    with a few turns of heavy wire: a sheet steel chassis bent up at both ends and painted, two heat
    sinks of power transistors, a duplex outlet, a toggle switch and a pilot light on the end, and
    heavy red and black battery cables off a terminal block, ending in ring lugs."""
    sheet = SHEET
    width, depth = 0.3, 0.17
    box(col, "HomeInv_Base", M("hammertone"), (width, depth, sheet), bevel=0.001)
    # Bent up high at the panel end, low at the other.
    for sign, flange in ((-1, 0.045), (1, 0.075)):
        box(col, "HomeInv_Flange", M("hammertone"), (sheet, depth, flange), at=(sign * (width / 2 - sheet / 2), 0, sheet), bevel=0.001)
    _transformer(col, "HomeInv_Transformer", MOT_CORE, ("copper", "rewound"), at=(-0.065, 0.01, sheet), spades=True, screwed=True)
    for x in (0.046, 0.11):
        _heatsink(col, "HomeInv_Sink", (0.064, 0.11, 0.028), (x, 0.02, sheet), 2, finish="black")
    # The end panel, facing +X.
    face = width / 2
    box(col, "HomeInv_Yoke", M("cream"), (0.003, 0.088, 0.05), at=(face + 0.0015, -0.032, 0.016))
    for y in (-0.052, -0.012):
        outlet(col, "HomeInv_Outlet", (face + 0.0045, y, 0.021), turn=90)
    _toggle(col, "HomeInv_Switch", (face, 0.045, 0.03), turn=90)
    _pilot_light(col, "HomeInv_Pilot", (face, 0.045, 0.06), turn=90)
    # The primary's leads along the front to the outlets, the rewound winding's to the heat sinks.
    for i, (x, colour) in enumerate(((-0.0817, "black"), (-0.0483, "white"))):
        y = -0.06 - 0.006 * i
        tube(col, "HomeInv_Lead", M(colour), [(x, -0.049, 0.035), (x, -0.056, 0.02), (x + 0.01, y, sheet + 0.0025), (0.13, y, sheet + 0.0025),
                                              (0.143, -0.045, 0.02), (0.145, -0.032 - 0.006 * i, 0.035)], 0.0025)
    tube(col, "HomeInv_Heavy", M("black"), [(-0.045, -0.034, 0.068), (-0.02, -0.04, 0.05), (0.02, -0.045, 0.02), (0.046, -0.04, 0.012)], 0.0035)
    tube(col, "HomeInv_Heavy", M("black"), [(-0.045, 0.054, 0.068), (0.0, 0.08, 0.04), (0.06, 0.082, 0.015), (0.11, 0.08, 0.012)], 0.0035)
    # The battery terminals: two studs through a block, a cable's lug under each nut.
    block_y, stud_z = -0.066, sheet + 0.012
    box(col, "HomeInv_Block", M("black"), (0.056, 0.026, 0.012), at=(-0.115, block_y, sheet), bevel=0.002)
    tube(col, "HomeInv_Tap", M("red"), [(-0.101, -0.053, 0.01), (-0.098, -0.048, 0.035), (-0.08, -0.045, 0.06), (-0.066, -0.039, 0.062)], 0.003)
    for x, colour, path, end, angle in (
            (-0.101, "red", [(-0.099, -0.118, 0.012), (-0.09, -0.135, 0.006)], (-0.035, -0.155), 160),
            (-0.129, "black", [(-0.127, -0.12, 0.012), (-0.12, -0.14, 0.006), (-0.108, -0.156, 0.0055)], (-0.06, -0.172), 165)):
        cylinder(col, "HomeInv_Stud", M("galvanised"), 0.004, 0.016, at=(x, block_y, stud_z), segments=8)
        start = _ring_lug(col, "HomeInv_Lug", colour, (x, block_y), -90, z=stud_z)
        cylinder(col, "HomeInv_Nut", M("galvanised"), 0.0065, 0.005, at=(x, block_y, stud_z + 0.0056), segments=6)
        tube(col, "HomeInv_Cable", M(colour), [start, *path, _ring_lug(col, "HomeInv_Lug", colour, end, angle)], 0.0055, 8)
