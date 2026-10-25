"""Batteries, the battery storage that holds them, and what rebuilding one takes."""
import functools
import random

from art.kit import added, around, beam, box, cylinder, group, mound, prism, text, tube
from palette import M
from parts import BOARD, SHEET, arch, side_handles

# Batteries ----------------------------------------------------------------------------------------


def battery(col, name, size, case, lid, caps=(), cap_colour="cream", label=None, handle=None, post_height=0.02):
    """A lead-acid battery: a case, a lid, vent caps, two posts (red +, black -) and a label on its
    front. `caps` lists cap x positions, `handle` is "rope" or "sides"."""
    width, depth, height = size
    lid_height = 0.02
    box(col, name + "_Case", M(case), (width, depth, height - lid_height), bevel=0.006)
    box(col, name + "_Lid", M(lid), (width + 0.004, depth + 0.004, lid_height), at=(0, 0, height - lid_height), bevel=0.004)
    for x in caps:
        cylinder(col, name + "_Cap", M(cap_colour), min(0.018, depth / 7), 0.012, at=(x, 0.0, height), segments=10)
    post_x = width / 2 - min(0.035, width / 5)
    post_y = -depth / 2 + min(0.03, depth / 4)
    for sign, colour in ((1, "red"), (-1, "black")):
        cylinder(col, name + "_Post", M("lead"), 0.009, post_height, at=(sign * post_x, post_y, height), segments=10,
                 radius_top=0.007)
        cylinder(col, name + "_Ring", M(colour), 0.013, 0.004, at=(sign * post_x, post_y, height), segments=10)
    if label:
        text_body, size_ = label
        box(col, name + "_Label", M("label"), (width * 0.8, 0.002, height * 0.32),
            at=(0, -depth / 2 - 0.001, height * 0.3))
        text(col, name + "_Text", M("ink"), text_body, size_, at=(0, -depth / 2 - 0.0035, height * 0.3 + height * 0.1))
    if handle == "rope":
        arch(col, name + "_Rope", M("black"), 0, 0, width / 2 - 0.03, width / 4, height, height + 0.06, 0.006)
    elif handle == "sides":
        side_handles(col, name + "_Handle", M("black"), width / 2, (depth / 4, height - 0.06), (depth / 5, height - 0.03), 0.03, 0.007)


def deep_cycle_battery(col):
    """A group 27 marine and RV deep-cycle battery: blue, rope handle, wing-nut posts."""
    battery(col, "DeepCycle", (0.32, 0.17, 0.23), "marine", "white", caps=(-0.06, 0.06), cap_colour="white",
            label=("DEEP CYCLE", 0.03), handle="rope", post_height=0.03)


# An L-16's case, a little shorter than a real one's 0.43 m: at full height it towered over the
# game's car battery, which is drawn small (DEVELOPMENT.md).
L16 = (0.30, 0.18, 0.38)


def l16_battery(col):
    """An L-16 6 V battery: tall, heavy, maroon, lifting handles at the ends."""
    battery(col, "L16", L16, "maroon", "battery", caps=(-0.08, 0.0, 0.08), cap_colour="black",
            label=("L-16", 0.05), handle="sides", post_height=0.035)


def jar_battery(col):
    """Six of the game's glass jars, each a 2 V cell, its lid screwed down and its plates' lugs
    standing up through it, sealed round with pitch; the acid line showing through the glass. They
    stand in sand in a nailed pine tray, lashed together with twine round their middles, wired in
    series by copper straps across their tops."""
    width, depth, wall, tray_height = 0.36, 0.25, 0.015, 0.06
    # A hair inside the sides and ends, so their outer faces don't lie in one plane with it.
    box(col, "JarTray_Bottom", M("pinestrip"), (width - 0.004, depth - 0.004, wall), bevel=0.002)
    for sign in (-1, 1):
        box(col, "JarTray_Side", M("pinestripdark"), (width, wall, tray_height), at=(0, sign * (depth - wall) / 2, 0), bevel=0.002)
        box(col, "JarTray_End", M("pinestrip"), (wall, depth - 2 * wall, tray_height), at=(sign * (width - wall) / 2, 0, 0), bevel=0.002)
    box(col, "JarTray_Sand", M("sand"), (width - 2 * wall, depth - 2 * wall, tray_height - 0.015), at=(0, 0, wall), bevel=0.004)
    radius, neck, pitch, rows = 0.05, 0.039, 0.112, (-0.055, 0.055)
    acid, body, shoulder, band = 0.1, 0.13, 0.014, 0.016
    lid_top = wall + body + shoulder + band + 0.003
    lugs = []
    for y in rows:
        for i in range(3):
            x = (i - 1) * pitch
            cylinder(col, "Jar_AcidGlass", M("jaracid"), radius, acid, at=(x, y, wall), segments=16)
            cylinder(col, "Jar_Glass", M("jarglass"), radius, body - acid, at=(x, y, wall + acid), segments=16)
            cylinder(col, "Jar_Shoulder", M("jarglass"), radius, shoulder, at=(x, y, wall + body), radius_top=neck, segments=16)
            cylinder(col, "Jar_Band", M("galvanised"), neck + 0.003, band, at=(x, y, wall + body + shoulder), segments=16)
            cylinder(col, "Jar_Lid", M("galvanised"), neck, 0.003, at=(x, y, wall + body + shoulder + band), segments=16)
            for sign in (-1, 1):
                lx = x + sign * 0.02
                cylinder(col, "Jar_Pitch", M("black"), 0.011, 0.005, at=(lx, y, lid_top), segments=10)
                box(col, "Jar_Lug", M("lead"), (0.011, 0.011, 0.028), at=(lx, y, lid_top), bevel=0.002)
                lugs.append((lx, y))
    # Twine round the six, following the outside of the corner jars, and a knot at the front.
    corners = ((pitch, rows[1], 0), (-pitch, rows[1], 90), (-pitch, rows[0], 180), (pitch, rows[0], 270))
    lash = wall + 0.085
    loop = [(*around((cx, cy), start + 15 * k, radius + 0.003), lash) for cx, cy, start in corners for k in range(7)]
    tube(col, "Jar_Twine", M("twine"), loop + loop[:1], 0.0035, 6)
    mound(col, "Jar_Knot", M("twine"), (0.008, 0.006, 0.01), at=(0.05, rows[0] - radius - 0.004, lash - 0.005), rotate=(90, 0, 0),
          segments=8, rings=3)
    top = lid_top + 0.022
    # In series: each jar's + lug to the next jar's - lug, along the front row and back.
    order = [lugs[1], lugs[2], lugs[3], lugs[4], lugs[5], lugs[11], lugs[10], lugs[9], lugs[8], lugs[7], lugs[6]]
    for a, b in zip(order[::2], order[1::2]):
        tube(col, "Jar_Strap", M("copper"), [(a[0], a[1], top), (b[0], b[1], top)], 0.004, 6)
    for lug, colour in ((lugs[0], "red"), (order[-1], "black")):
        tube(col, "Jar_Lead", M(colour), [(lug[0], lug[1], top), (lug[0], lug[1] - 0.02, top + 0.02),
                                          (lug[0] - 0.05, lug[1] - 0.03, top + 0.01)], 0.004, 6)


# How a battery in a bank or box tile looks by its type, at the one size every slot fits: case, lid,
# vent caps and the label on its end. A car battery is grey all over with the game's own car
# battery's green label, a deep-cycle marine blue with a white lid, an L-16 maroon with a black lid,
# so even a box, which hides all but their tops, tells them apart.
BANK_BATTERY_LOOKS = {
    "car": ("carbattery", "carbattery", "cream", "carlabel"),
    "deepCycle": ("marine", "white", "white", "label"),
    "l16": ("maroon", "battery", "black", "label"),
}


def bank_battery(col, name, look="car"):
    """A flooded battery as the bank and box tiles show it, whatever its size, coloured as its type."""
    case, lid, caps, label = BANK_BATTERY_LOOKS[look]
    width, depth, height = 0.18, 0.30, 0.24
    battery(col, name, (width, depth, height), case, lid, caps=(-0.03, 0.03), cap_colour=caps, handle=None, post_height=0.02)
    box(col, name + "_Label", M(label), (width * 0.75, 0.002, height * 0.35), at=(0, -depth / 2 - 0.001, height * 0.3))


# Battery storage ----------------------------------------------------------------------------------
#
# Each tier comes in pine and in welded steel, the same size on the floor. Every builder takes
# `frame` (the storage itself), `batteries` (how many car batteries stand in it, filled from the
# bottom left), `slot` and `look` (only the battery in that slot, as that BANK_BATTERY_LOOKS look)
# and `meter_level` (how many of its charge meter's five LEDs are lit), so a tile can draw the
# frame alone and an overlay just one battery or just the lit LEDs.

METER_COLOURS = ("ledred", "ledyellow", "ledgreen", "ledgreen", "ledgreen")


def charge_meter(col, at, frame, level, scale=1.0):
    """A grey meter box facing -Y, its bottom centre at `at`, with a row of five LEDs: dark with
    `frame`, and `level` of them lit a hair in front of the dark ones."""
    x, y, z = at
    width, depth, height = 0.34 * scale, 0.08 * scale, 0.15 * scale
    front = y - depth / 2
    led, pitch = 0.04 * scale, 0.06 * scale
    if frame:
        box(col, "Meter_Box", M("grey"), (width, depth, height), at=at, bevel=0.008 * scale)
        box(col, "Meter_Face", M("black"), (width - 0.04 * scale, 0.004, 0.09 * scale), at=(x, front - 0.001, z + 0.035 * scale))
        text(col, "Meter_Text", M("white"), "CHARGE", 0.022 * scale, at=(x, front - 0.004, z + 0.098 * scale))
        for i in range(5):
            box(col, "Meter_Led", M("ledoff"), (led, 0.006, led), at=(x + (i - 2) * pitch, front - 0.004, z + 0.05 * scale))
    for i in range(level):
        box(col, "Meter_LedLit", M(METER_COLOURS[i]), (led * 1.05, 0.006, led * 1.05),
            at=(x + (i - 2) * pitch, front - 0.007, z + 0.049 * scale))


def bank_batteries(col, name, slots, count, slot=None, look="car"):
    """`count` car batteries standing in `slots` = [(x, z), ...] in order, each linked in series to
    the one before it on the same shelf, from that one's + post to its - post; or with `slot`, only
    the battery in that slot, as `look`, and its link."""
    post_x, post_y = 0.055, -0.12
    for i in range(count) if slot is None else (slot,):
        x, z = slots[i]
        battery_name = "%sBattery%d" % (name, i)
        for obj in added(col, bank_battery, battery_name, look):
            obj.location.x += x
            obj.location.z += z
        if i > 0 and slots[i - 1][1] == z:
            last_x = slots[i - 1][0]
            tube(col, battery_name + "_Link", M("red" if i % 2 else "black"),
                 [(last_x + post_x, post_y, z + 0.26), ((last_x + x) / 2, post_y - 0.01, z + 0.265),
                  (x - post_x, post_y, z + 0.26)], 0.006)


BOX = (0.5, 0.36, 0.22)


def battery_box(col, material, frame=True, batteries=0, meter_level=0, slot=None, look="car"):
    """The first bank: an open box for two batteries, its lid propped open against the back, a
    terminal block and leads on its side and a small charge meter on its front. Pine boards nailed
    together, or steel sheet welded at the corners with an angle-iron rim and side handles."""
    width, depth, height = BOX
    floor = BOARD if material == "wood" else SHEET
    if frame:
        if material == "wood":
            _plank_box(col)
        else:
            _steel_box(col)
        box(col, "Box_Terminal", M("black"), (0.02, 0.1, 0.06), at=(width / 2 + 0.012, -0.08, 0.06), bevel=0.004)
        for i, colour in enumerate(("red", "black")):
            y = -0.1 + 0.04 * i
            tube(col, "Box_Lead", M(colour), [(width / 2 + 0.022, y, 0.09), (width / 2 + 0.06, y - 0.02, 0.05),
                                               (width / 2 + 0.09, y - 0.06, 0.01)], 0.007)
        text(col, "Box_Stencil", M("ink" if material == "wood" else "white"), "12V", 0.06,
             at=(-0.12, -depth / 2 - 0.0015, 0.06))
    charge_meter(col, (0.11, -depth / 2 - 0.02, 0.11), frame, meter_level, scale=0.5)
    bank_batteries(col, "Box", [(-0.11, floor), (0.11, floor)], batteries, slot, look)


def _plank_box(col):
    """Planks nailed at the corners, two boards high, in two shades so they read apart, a floor of
    boards, cleats on the ends to lift it by, and a lid of boards on two battens."""
    width, depth, height = BOX
    gap = 0.003
    shades = ("pine", "pinedark")
    board = (depth - 2 * gap) / 3
    for i in range(3):
        box(col, "Box_Floor", M(shades[i % 2]), (width, board, BOARD), at=(0, -depth / 2 + board / 2 + i * (board + gap), 0),
            bevel=0.003)
    rise = (height - gap) / 2
    for row in range(2):
        z = row * (rise + gap)
        for sign in (-1, 1):
            box(col, "Box_FrontBack", M(shades[row]), (width, BOARD, rise), at=(0, sign * (depth - BOARD) / 2, z), bevel=0.004)
            box(col, "Box_Side", M(shades[(row + 1) % 2]), (BOARD, depth - 2 * BOARD, rise), at=(sign * (width - BOARD) / 2, 0, z),
                bevel=0.004)
            # Through the front board into the end of the side's.
            for dz in (0.025, rise - 0.025):
                cylinder(col, "Box_Nail", M("lead"), 0.004, 0.001, at=(sign * (width - BOARD) / 2, -depth / 2 - 0.0005, z + dz),
                         rotate=(90, 0, 0), segments=8)
    for sign in (-1, 1):
        box(col, "Box_Cleat", M("wood"), (0.025, 0.12, 0.03), at=(sign * (width / 2 + 0.012), 0, height - 0.07), bevel=0.004)
    lid = []
    for i in range(3):
        lid.append(box(col, "Box_Lid", M(shades[i % 2]), (width, BOARD, board), at=(0, 0, i * (board + gap)), bevel=0.003))
    for sign in (-1, 1):
        lid.append(box(col, "Box_LidBatten", M("wood"), (0.05, BOARD, depth - 0.05), at=(sign * (width / 2 - 0.07), -BOARD, 0.025),
                       bevel=0.003))
    group(col, "Box_LidBoards", lid, at=(0, depth / 2 + 0.03, height - 0.01), rotate=(-12, 0, 0))


def _steel_box(col):
    width, depth, height = BOX
    rim = 0.025
    box(col, "Box_Floor", M("rawsteel"), (width, depth, SHEET))
    for sign in (-1, 1):
        box(col, "Box_Side", M("rawsteel"), (SHEET, depth, height), at=(sign * (width - SHEET) / 2, 0, 0))
        box(col, "Box_FrontBack", M("rawsteel"), (width - 2 * SHEET, SHEET, height), at=(0, sign * (depth - SHEET) / 2, 0))
        # The angle-iron rim's outward flange along each top edge.
        box(col, "Box_RimLong", M("rawsteel"), (width + 2 * rim, rim, SHEET), at=(0, sign * (depth + rim) / 2, height - SHEET))
        box(col, "Box_RimShort", M("rawsteel"), (rim, depth, SHEET), at=(sign * (width + rim) / 2, 0, height - SHEET))
        side_handles(col, "Box_Handle", M("rawsteel"), width / 2, (0.07, height - 0.07), (0.05, height - 0.06), 0.035, 0.007,
                     signs=(sign,))
        for y_sign in (-1, 1):
            box(col, "Box_Weld", M("weld"), (0.01, 0.01, height - 0.02),
                at=(sign * (width / 2 + 0.001), y_sign * (depth / 2 + 0.001), 0.01))
    for x in (-0.15, 0.15):
        cylinder(col, "Box_Hinge", M("weld"), 0.009, 0.05, at=(x - 0.025, depth / 2 + rim / 2, height), rotate=(0, 90, 0),
                 segments=8)
    box(col, "Box_Lid", M("rawsteel"), (width + 2 * rim, SHEET, depth + rim), at=(0, depth / 2 + rim, height),
        rotate=(-12, 0, 0))
    # Batteries go in and out over the front, so the rim is rubbed bright there, and the damp of
    # the floor has rusted the foot of the front in patches.
    box(col, "Box_Wear", M("worn"), (width * 0.55, rim * 0.8, 0.0008), at=(0, -(depth + rim) / 2, height))
    for x, w, h in ((-0.17, 0.06, 0.02), (0.04, 0.09, 0.014), (0.19, 0.05, 0.025)):
        box(col, "Box_Rust", M("rust"), (w, 0.0008, h), at=(x, -depth / 2 - 0.0004, 0))


SHELVING = (0.92, 0.44)
SLOTS_4 = tuple(-0.315 + 0.21 * i for i in range(4))
SLOTS_3 = (-0.28, 0.0, 0.28)

# Shelving tiers: overall height, the top of each shelf a row of batteries stands on, the
# battery positions across a shelf, and whether it is built neat. Steel shelves are thinner, so
# a metal tier fits a shelf or a battery more in the same space. A rack is knocked up at home from
# what was to hand; the bank, the tier above it, is built neat and finished.
RACK_WOOD = {"height": 0.76, "shelves": (0.07, 0.43), "slots": SLOTS_3, "neat": False}
RACK_METAL = {"height": 0.76, "shelves": (0.05, 0.41), "slots": SLOTS_4, "neat": False}
BANK_WOOD = {"height": 1.24, "shelves": (0.07, 0.47, 0.87), "slots": SLOTS_4, "neat": True}
BANK_METAL = {"height": 1.24, "shelves": (0.05, 0.35, 0.65, 0.95), "slots": SLOTS_4, "neat": True}


def battery_shelving(col, tier, material, frame=True, batteries=0, meter_level=0, slot=None, look="car"):
    """A battery rack or bank: shelves of batteries in pine or angle iron, a fused disconnect and
    a charge meter on top. A neat one has a no-smoking sign on the front of its top, as battery
    rooms do."""
    width, depth = SHELVING
    height, neat = tier["height"], tier["neat"]
    if frame:
        if material == "wood":
            _pine_shelving(col, height, tier["shelves"], neat)
            front = -depth / 2 - 0.02
        else:
            _steel_shelving(col, height, tier["shelves"], neat)
            front = -depth / 2
        # Fused disconnect on the right, its cables down the back to the bottom shelf.
        box(col, "Shelving_Disconnect", M("grey"), (0.14, 0.1, 0.22), at=(width / 2 - 0.12, -depth / 2 + 0.06, height), bevel=0.01)
        box(col, "Shelving_Handle", M("red"), (0.03, 0.05, 0.08), at=(width / 2 - 0.12, -depth / 2, height + 0.08), bevel=0.006)
        for i, colour in enumerate(("red", "black")):
            x = width / 2 - 0.05 - 0.03 * i
            tube(col, "Shelving_MainCable", M(colour), [(x, -depth / 2 + 0.1, height + 0.05), (x + 0.02, depth / 2 - 0.06, height + 0.02),
                                                         (x + 0.02, depth / 2 - 0.06, 0.1)], 0.012)
        if neat:
            box(col, "Shelving_Sign", M("yellow"), (0.13, 0.002, 0.028), at=(0.1, front - 0.001, height - 0.032))
            text(col, "Shelving_SignText", M("ink"), "NO SMOKING", 0.012, at=(0.1, front - 0.0025, height - 0.0225))
    charge_meter(col, (-0.18, -depth / 2 + 0.08, height), frame, meter_level)
    slots = [(x, z) for z in tier["shelves"] for x in tier["slots"]]
    bank_batteries(col, "Shelving", slots, batteries, slot, look)


def _pine_shelving(col, height, shelves, neat):
    """2 x 4 corner posts, each shelf three boards with an apron board nailed along its front and
    back, a top of boards, and a diagonal brace across the back. Neat, it is all matched boards
    stained dark; rough, it is odd boards and a plywood offcut cut and laid by eye, its posts left
    standing proud of the top at whatever length they were."""
    width, depth = SHELVING
    rng = random.Random(len(shelves))
    frame = M("wood" if neat else "pinedark")
    for x in (-width / 2 + 0.019, width / 2 - 0.019):
        for y in (-depth / 2 + 0.045, depth / 2 - 0.045):
            box(col, "Shelving_Post", frame, (0.038, 0.089, height + (0 if neat else rng.uniform(0.02, 0.06))), at=(x, y, 0),
                bevel=0.004)
    boards = 3
    board_depth = depth / boards
    for z in shelves + (height,):
        for i in range(boards):
            if neat:
                shade, short, shift, turn = "wood", 0.0, 0.0, 0.0
            else:
                shade = rng.choice(("pine", "pinedark", "wood", "plywood"))
                short, shift, turn = rng.uniform(0.0, 0.03), rng.uniform(-0.015, 0.015), rng.uniform(-1.2, 1.2)
            box(col, "Shelving_Board", M(shade), (width - short, board_depth - 0.006, 0.02),
                at=(shift, -depth / 2 + board_depth * (i + 0.5), z - 0.02), rotate=(0, 0, turn), bevel=0.003)
        apron_bottom = max(0.0, z - 0.09)
        for sign in (-1, 1):
            box(col, "Shelving_Apron", M("wood" if neat else rng.choice(("pine", "pinedark"))), (width, 0.02, z - apron_bottom),
                at=(0 if neat else rng.uniform(-0.012, 0.012), sign * (depth / 2 + 0.01), apron_bottom), bevel=0.003)
        for x in (-width / 2 + 0.019, width / 2 - 0.019):
            for dz in (0.025, 0.06):
                if z - dz > apron_bottom:
                    cylinder(col, "Shelving_Nail", M("lead"), 0.005, 0.003, at=(x, -depth / 2 - 0.02, z - dz),
                             rotate=(90, 0, 0), segments=8)
    beam(col, "Shelving_Brace", frame, (-width / 2 + 0.05, depth / 2 + 0.03, 0.1),
         (width / 2 - 0.05, depth / 2 + 0.03, height - 0.1), (0.07, 0.02), bevel=0.003)


def _steel_shelving(col, height, shelves, neat):
    """Angle-iron uprights, each shelf a steel sheet on angle-iron rails welded between them, a
    sheet on top, and flat bars crossed on the back. Neat, it is painted, the welds under the paint,
    and stands on rubber feet, its paint chipped to bare steel where batteries and boots knock it;
    rough, it is scrap steel flecked with rust, rust at its welds, rubbed bright where batteries
    slide on and off."""
    width, depth = SHELVING
    angle, thick = 0.04, SHEET
    steel = M("bluegrey" if neat else "rustysteel")
    rng = random.Random(len(shelves))
    front = -depth / 2 - 0.0004
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(col, "Shelving_Angle", steel, (angle, thick, height), at=(sx * (width - angle) / 2, sy * (depth - thick) / 2, 0))
            box(col, "Shelving_Angle", steel, (thick, angle, height), at=(sx * (width - thick) / 2, sy * (depth - angle) / 2, 0))
            if neat:
                cylinder(col, "Shelving_Foot", M("black"), 0.022, 0.012, at=(sx * (width / 2 - 0.022), sy * (depth / 2 - 0.022), 0),
                         segments=12)
            else:
                box(col, "Shelving_Foot", steel, (0.06, 0.06, 0.005), at=(sx * (width / 2 - 0.03), sy * (depth / 2 - 0.03), 0))
        if neat:
            box(col, "Shelving_Chip", M("worn"), (0.03, 0.0008, 0.035), at=(sx * (width / 2 - 0.02), front, 0.015))
    rail = width - 2 * angle
    for z in shelves + (height,):
        box(col, "Shelving_Sheet", steel, (width - 2 * thick, depth - 2 * thick, thick), at=(0, 0, z - thick))
        for sy in (-1, 1):
            box(col, "Shelving_Rail", steel, (rail, thick, 0.035), at=(0, sy * (depth / 2 - thick / 2), max(0.0, z - 0.035)))
            if not neat:
                for sx in (-1, 1):
                    box(col, "Shelving_Weld", M("rust"), (0.012, 0.008, 0.035),
                        at=(sx * rail / 2, sy * (depth / 2 + 0.002), max(0.0, z - 0.035)))
        for _ in range(2):
            if neat:
                box(col, "Shelving_Chip", M("worn"), (rng.uniform(0.015, 0.035), 0.0008, rng.uniform(0.008, 0.016)),
                    at=(rng.uniform(-0.38, 0.38), front, z - 0.018))
            else:
                box(col, "Shelving_Wear", M("worn"), (rng.uniform(0.08, 0.13), 0.0008, 0.008), at=(rng.uniform(-0.3, 0.3), front, z - 0.009))
    back = depth / 2 + 0.004
    for sx in (-1, 1):
        beam(col, "Shelving_Brace", steel, (sx * (width / 2 - 0.03), back, 0.06), (-sx * (width / 2 - 0.03), back, height - 0.06),
             (0.03, 0.005))


# The item type of every battery storage tier and its builder.
STORAGE = {
    "BatteryBoxWood": functools.partial(battery_box, material="wood"),
    "BatteryBoxMetal": functools.partial(battery_box, material="metal"),
    "BatteryRackWood": functools.partial(battery_shelving, tier=RACK_WOOD, material="wood"),
    "BatteryRackMetal": functools.partial(battery_shelving, tier=RACK_METAL, material="metal"),
    "BatteryBankWood": functools.partial(battery_shelving, tier=BANK_WOOD, material="wood"),
    "BatteryBankMetal": functools.partial(battery_shelving, tier=BANK_METAL, material="metal"),
}


# Battery rebuilding -------------------------------------------------------------------------------


def battery_case(col, name, size, colour, cells, label, words=None, bolt=False, handles=False):
    """A stripped battery: the case with its lid cut off and its plates pulled, grey inside with the
    paste they left, moulded with a lip round its top, ribs up its ends and a ledge along its foot,
    each catching the light so its big faces don't read as one flat patch, and a torn scrap of its
    label on the front.
    `cells` is how many cells it holds: six for 12 V, three for 6 V. `label` is the scrap's material,
    `words` what is left of its lettering, and `bolt` puts the game's car battery's lightning bolt on it."""
    width, depth, height = size
    wall, stain = 0.005, 0.003
    inside = height - wall - 0.004  # the stain stops short of the cut, which shows the case's colour
    box(col, name + "_Floor", M(colour), (width, depth, wall))
    box(col, name + "_Residue", M("leadstain"), (width - 2 * wall, depth - 2 * wall, 0.002), at=(0, 0, wall))
    for sign in (-1, 1):
        box(col, name + "_Side", M(colour), (wall, depth, height), at=(sign * (width - wall) / 2, 0, 0), bevel=0.002)
        box(col, name + "_End", M(colour), (width - 2 * wall, wall, height), at=(0, sign * (depth - wall) / 2, 0), bevel=0.002)
        box(col, name + "_SideStain", M("leadstain"), (stain, depth - 2 * wall, inside),
            at=(sign * (width / 2 - wall - stain / 2), 0, wall))
        box(col, name + "_EndStain", M("leadstain"), (width - 2 * wall - 2 * stain, stain, inside),
            at=(0, sign * (depth / 2 - wall - stain / 2), wall))
        box(col, name + "_Ledge", M(colour), (width - 0.004, 0.008, 0.016), at=(0, sign * (depth / 2 + 0.004), 0), bevel=0.002)
        box(col, name + "_Lip", M(colour), (width + 0.006, 0.006, 0.014), at=(0, sign * depth / 2, height - 0.016), bevel=0.002)
        box(col, name + "_Lip", M(colour), (0.006, depth - 0.006, 0.014), at=(sign * width / 2, 0, height - 0.016), bevel=0.002)
        for rib in (-1, 1):
            box(col, name + "_Rib", M(colour), (0.006, 0.01, height - 0.034), at=(sign * (width / 2 + 0.001), rib * depth * 0.38, 0.012),
                bevel=0.002)
    # The walls between the cells, stained like the inside, their cut tops the case's own plastic.
    for i in range(1, cells):
        x = -width / 2 + i * width / cells
        box(col, name + "_CellWall", M("leadstain"), (0.006, depth - 2 * (wall + stain), inside), at=(x, 0, wall))
        box(col, name + "_CellWallCut", M(colour), (0.006, depth - 2 * (wall + stain), 0.001), at=(x, 0, wall + inside))
    w, h = width * 0.6, height * 0.35
    x, z = -width * 0.08, height * 0.2
    torn = [(-0.5, 0), (0.2, 0), (0.32, 0.18), (0.22, 0.38), (0.42, 0.6), (0.3, 0.8), (0.5, 1.0), (-0.5, 1.0)]
    prism(col, name + "_Label", M(label), [(x + u * w, z + v * h) for u, v in torn], 0.002, at=(0, -depth / 2 - 0.001, 0))
    # Both kept left of the tear, which reaches in to 0.2 of the scrap's width from its middle.
    if words:
        lettering = text(col, name + "_Text", M("ink"), words, h * 0.4, at=(x - 0.44 * w, -depth / 2 - 0.0035, z + h * 0.3),
                         align="LEFT")
        lettering.scale *= min(1.0, 0.6 * w / lettering.dimensions.x)
    if bolt:
        s = h * 0.8
        outline = [(-0.25, 0.45), (-0.02, 0.45), (-0.2, 0.0), (0.3, 0.58), (0.05, 0.58), (0.25, 1.0), (-0.15, 1.0)]
        prism(col, name + "_Bolt", M("bolt"), [(x - 0.15 * w + u * s, z + h * 0.1 + v * s) for u, v in outline], 0.001,
              at=(0, -depth / 2 - 0.0025, 0))
    if handles:
        side_handles(col, name + "_Handle", M("black"), width / 2, (depth / 4, height - 0.06), (depth / 5, height - 0.03), 0.03, 0.007)


PLATE = (0.13, 0.12)  # a plate's width and height, without its lug


def battery_plates(col, worn=False):
    """A cell's plates: grey pasted lead in a cast grid, standing in a row, the positive and negative
    ones joined by a strap and lug each. Worn plates are buckled and black with dirt, grid and all,
    bare lead showing through in patches, crusted white with sulphate, and blue-green where the
    acid ate at them and their straps."""
    width, height = PLATE
    count, pitch = 7, 0.014
    rng = random.Random(3)
    grid = M("plateworn" if worn else "lead")
    for i in range(count):
        plate = [box(col, "Plates_Plate", M("plateworn" if worn else "plate"), (width, 0.005, height))]
        for k in range(1, 4):
            plate.append(box(col, "Plates_Rib", grid, (width - 0.01, 0.002, 0.004), at=(0, -0.0035, k * height / 4)))
        for k in range(1, 5):
            plate.append(box(col, "Plates_Rib", grid, (0.004, 0.002, height - 0.01), at=(-width / 2 + k * width / 5, -0.0035, 0.005)))
        if worn:
            # About a fifth of its face, under the grid.
            for _ in range(3):
                plate.append(box(col, "Plates_Bare", M("lead"), (rng.uniform(0.03, 0.05), 0.001, rng.uniform(0.02, 0.04)),
                                 at=(rng.uniform(-0.04, 0.04), -0.003, rng.uniform(0.005, 0.08))))
            for crust in ("sulphate", "sulphate", "corrosion", "corrosion"):
                plate.append(box(col, "Plates_Crust", M(crust), (rng.uniform(0.02, 0.05), 0.008, rng.uniform(0.015, 0.035)),
                                 at=(rng.uniform(-0.045, 0.045), 0, rng.uniform(0.01, 0.08)), bevel=0.003))
        group(col, "Plates_Set", plate, at=(0, (i - (count - 1) / 2) * pitch, 0),
              rotate=(rng.uniform(-7, 7) if worn else 0, 0, rng.uniform(-3, 3) if worn else 0))
    span = count * pitch
    for sign in (-1, 1):
        box(col, "Plates_Strap", M("lead"), (0.025, span, 0.012), at=(sign * 0.04, 0, height), bevel=0.003)
        box(col, "Plates_Lug", M("lead"), (0.018, 0.018, 0.03), at=(sign * 0.04, 0, height + 0.012), bevel=0.003)
        if worn:
            box(col, "Plates_StrapCrust", M("corrosion"), (0.03, span * 0.45, 0.006), at=(sign * 0.04, sign * span * 0.2, height + 0.009),
                bevel=0.003)
            box(col, "Plates_LugCrust", M("corrosion"), (0.022, 0.022, 0.012), at=(sign * 0.04, 0, height + 0.03), bevel=0.004)


def plate_pattern(col):
    """The plate whittled from a pine board, lug and all, a grid scored into its face and a knob to
    lift it out of the clay."""
    width, depth = PLATE
    thick = 0.012
    box(col, "Pattern_Plate", M("pine"), (width, depth, thick), bevel=0.002)
    box(col, "Pattern_Lug", M("pine"), (0.025, 0.03, thick), at=(width / 2 - 0.025, depth / 2 + 0.015, 0), bevel=0.002)
    for k in range(1, 4):
        box(col, "Pattern_Score", M("pinedark"), (width - 0.012, 0.002, 0.0008), at=(0, -depth / 2 + k * depth / 4, thick))
    for k in range(1, 5):
        box(col, "Pattern_Score", M("pinedark"), (0.002, depth - 0.012, 0.0008), at=(-width / 2 + k * width / 5, 0, thick))
    cylinder(col, "Pattern_Knob", M("pinedark"), 0.012, 0.025, at=(0, 0, thick), segments=10)


def plate_mold(col, fired=False):
    """The pattern pressed into a slab of clay: a plate-shaped recess with its lug's channel. Firing
    turns the grey clay terracotta."""
    clay = M("terracotta" if fired else "clay")
    width, depth = PLATE
    rim, lug, recess = 0.03, 0.03, 0.012
    outer_w, outer_d, height = width + 2 * rim, depth + 2 * rim + lug, 0.05
    box(col, "Mold_Base", clay, (outer_w, outer_d, height - recess), bevel=0.004)
    front = -outer_d / 2
    plate_back = front + rim + depth
    lug_x = (width / 2 - 0.0375, width / 2 - 0.0125)
    # The raised clay around the recess, as rectangles (x0, x1, y0, y1).
    rims = [(-outer_w / 2, outer_w / 2, front, front + rim),
            (-outer_w / 2, -width / 2, front + rim, plate_back),
            (width / 2, outer_w / 2, front + rim, plate_back),
            (-outer_w / 2, lug_x[0], plate_back, plate_back + lug),
            (lug_x[1], outer_w / 2, plate_back, plate_back + lug),
            (-outer_w / 2, outer_w / 2, plate_back + lug, outer_d / 2)]
    for x0, x1, y0, y1 in rims:
        box(col, "Mold_Rim", clay, (x1 - x0, y1 - y0, recess), at=((x0 + x1) / 2, (y0 + y1) / 2, height - recess))


def battery_electrolyte(col):
    """A litre of battery acid in a white plastic bottle: a red child-proof cap and a yellow label
    with a black warning band."""
    width, depth, height = 0.085, 0.085, 0.19
    box(col, "Acid_Body", M("hdpe"), (width, depth, height), bevel=0.012)
    cylinder(col, "Acid_Shoulder", M("hdpe"), 0.04, 0.03, at=(0, 0, height - 0.005), radius_top=0.018, segments=16)
    cylinder(col, "Acid_Neck", M("hdpe"), 0.016, 0.012, at=(0, 0, height + 0.025), segments=12)
    cylinder(col, "Acid_Cap", M("red"), 0.019, 0.022, at=(0, 0, height + 0.035), segments=16)
    front = -depth / 2
    box(col, "Acid_Label", M("yellow"), (width * 0.86, 0.002, height * 0.5), at=(0, front - 0.001, height * 0.22))
    box(col, "Acid_Band", M("ink"), (width * 0.86, 0.0022, 0.022), at=(0, front - 0.0012, height * 0.25))
    text(col, "Acid_Danger", M("white"), "DANGER", 0.012, at=(0, front - 0.0026, height * 0.25 + 0.006))
    text(col, "Acid_Text", M("ink"), "ACID", 0.024, at=(0, front - 0.0026, height * 0.5))
    text(col, "Acid_Text2", M("red"), "ELECTROLYTE", 0.0085, at=(0, front - 0.0026, height * 0.4))
