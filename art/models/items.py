"""The parts of every model, in real-world sizes of 1993 hardware.

Each builder adds one thing's parts to a collection, standing on z = 0, centred, front to -Y (see
kit.py). ITEMS lists what each inventory item's ground model and icon are made of; tiles.py places
the same builders on tiles. A builder takes keyword options, so a tile can draw a battery rack
without its batteries and an overlay just the batteries.
"""
import math

from kit import box, cylinder, group, material, prism, text, tube

# Palette ------------------------------------------------------------------------------------------


def M(name):
    """The shared materials, made on first use."""
    return {
        "aluminium": lambda: material("RE_Aluminium", "#b9bdc1", roughness=0.35, metallic=0.8, grime=0.08),
        "galvanised": lambda: material("RE_Galvanised", "#a3a9ab", roughness=0.5, metallic=0.7, grime=0.2),
        "steel": lambda: material("RE_RackSteel", "#56635a", roughness=0.55, metallic=0.3, grime=0.25),
        "cells": lambda: material("RE_PolyCells", "#1d3a7c", roughness=0.25, metallic=0.2, grime=0.05,
                                  speckle=("#4c78c8", 0.9)),
        "backsheet": lambda: material("RE_Backsheet", "#e9e8df", roughness=0.5, grime=0.05),
        "busbar": lambda: material("RE_Busbar", "#cfd2d6", roughness=0.3, metallic=0.9, grime=0.0),
        "amorphous": lambda: material("RE_Amorphous", "#2c3a78", roughness=0.2, metallic=0.25, grime=0.05),
        "mono": lambda: material("RE_MonoCells", "#17191f", roughness=0.25, metallic=0.3, grime=0.04),
        "black": lambda: material("RE_BlackPlastic", "#1f2022", roughness=0.55, grime=0.15),
        "darkgrey": lambda: material("RE_DarkGrey", "#3a3c3f", roughness=0.5, grime=0.15),
        "grey": lambda: material("RE_GreyPaint", "#8b9089", roughness=0.55, grime=0.2),
        "battery": lambda: material("RE_BatteryCase", "#29292b", roughness=0.6, grime=0.15),
        "marine": lambda: material("RE_MarineBlue", "#2155a8", roughness=0.45, grime=0.12),
        "maroon": lambda: material("RE_Maroon", "#6e2024", roughness=0.5, grime=0.15),
        "cream": lambda: material("RE_Cream", "#e6dfc8", roughness=0.6, grime=0.1),
        "white": lambda: material("RE_White", "#ecebe6", roughness=0.6, grime=0.08),
        "yellow": lambda: material("RE_Yellow", "#dcb22b", roughness=0.5, grime=0.1),
        "lead": lambda: material("RE_Lead", "#8e8f8a", roughness=0.45, metallic=0.8, grime=0.15),
        "red": lambda: material("RE_Red", "#b8231f", roughness=0.5, grime=0.1),
        "plywood": lambda: material("RE_Plywood", "#b48d5c", roughness=0.8, grime=0.25, scale=12),
        "wood": lambda: material("RE_Wood", "#94693f", roughness=0.8, grime=0.3, scale=10),
        "navy": lambda: material("RE_Navy", "#2c416d", roughness=0.4, metallic=0.4, grime=0.1),
        "bluegrey": lambda: material("RE_BlueGrey", "#5e7189", roughness=0.45, metallic=0.3, grime=0.15),
        "cardboard": lambda: material("RE_Cardboard", "#bb9061", roughness=0.85, grime=0.2, scale=14),
        "tape": lambda: material("RE_Tape", "#c9b27c", roughness=0.4, grime=0.05),
        "snow": lambda: material("RE_Snow", "#ffffff", roughness=1.0, grime=0.04),
        "ledoff": lambda: material("RE_LedOff", "#2a2b26", roughness=0.3, grime=0.0),
        "ledred": lambda: material("RE_LedRed", "#ff3b2e", roughness=0.3, grime=0.0, emission="#ff3b2e"),
        "ledyellow": lambda: material("RE_LedYellow", "#ffd23a", roughness=0.3, grime=0.0, emission="#ffd23a"),
        "ledgreen": lambda: material("RE_LedGreen", "#4dff4a", roughness=0.3, grime=0.0, emission="#4dff4a"),
        "label": lambda: material("RE_Label", "#f1eee2", roughness=0.6, grime=0.05),
        "ink": lambda: material("RE_Ink", "#1b1b1b", roughness=0.6, grime=0.0),
        "magazine1": lambda: material("RE_Mag1", "#e7a42c", roughness=0.4, grime=0.05),
        "magazine2": lambda: material("RE_Mag2", "#2f6f8f", roughness=0.4, grime=0.05),
        "sky": lambda: material("RE_Sky", "#8fc4e8", roughness=0.4, grime=0.05),
        "sun": lambda: material("RE_Sun", "#ffd640", roughness=0.4, grime=0.0),
    }[name]()


# Solar modules ------------------------------------------------------------------------------------

# A 51 W multicrystalline module of the early nineties (Kyocera's K51 is 986 x 446 mm): 36 cells in
# four strings of nine, on a white backsheet, in a clear anodised frame.
MODULE = (0.986, 0.446, 0.036)
FRAME = 0.028


def solar_module(col, name="Module", snow=False):
    """A module lying glass up. `snow` adds only the snow lying on it."""
    width, depth, height = MODULE
    parts = []
    if snow:
        return [box(col, name + "_Snow", M("snow"), (width - 0.02, depth - 0.02, 0.025),
                    at=(0, 0, height - 0.004), bevel=0.01)]
    for sign in (-1, 1):
        parts.append(box(col, name + "_FrameLong", M("aluminium"), (width, FRAME, height),
                         at=(0, sign * (depth - FRAME) / 2, 0), bevel=0.003))
        parts.append(box(col, name + "_FrameShort", M("aluminium"), (FRAME, depth - 2 * FRAME, height),
                         at=(sign * (width - FRAME) / 2, 0, 0), bevel=0.003))
    inner_w, inner_d = width - 2 * FRAME, depth - 2 * FRAME
    parts.append(box(col, name + "_Backsheet", M("backsheet"), (inner_w, inner_d, 0.004), at=(0, 0, height - 0.008)))
    columns, rows = 9, 4
    cell_w = (inner_w - 0.02 - (columns - 1) * 0.003) / columns
    cell_d = (inner_d - 0.016 - (rows - 1) * 0.004) / rows
    for row in range(rows):
        y = -inner_d / 2 + 0.008 + cell_d / 2 + row * (cell_d + 0.004)
        for column in range(columns):
            x = -inner_w / 2 + 0.01 + cell_w / 2 + column * (cell_w + 0.003)
            parts.append(box(col, name + "_Cell", M("cells"), (cell_w, cell_d, 0.002), at=(x, y, height - 0.0045)))
        for offset in (-cell_d / 4, cell_d / 4):
            parts.append(box(col, name + "_Busbar", M("busbar"), (inner_w - 0.02, 0.0025, 0.0006),
                             at=(0, y + offset, height - 0.0025)))
    parts.append(box(col, name + "_JunctionBox", M("black"), (0.11, 0.08, 0.02), at=(0, 0.06, 0.004), bevel=0.004))
    return parts


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


def solar_flat(col, snow=False):
    """One module on two low rails, for a roof or the ground at 0 degrees."""
    module = solar_module(col, "Flat", snow=snow)
    lift = 0.045
    for obj in module:
        obj.location.z += lift
    if snow:
        return
    for sign in (-1, 1):
        box(col, "Flat_Rail", M("aluminium"), (MODULE[0] - 0.12, 0.03, lift), at=(0, sign * 0.13, 0), bevel=0.002)
        for x in (-0.38, 0.38):
            box(col, "Flat_Foot", M("galvanised"), (0.05, 0.07, 0.008), at=(x, sign * 0.13, 0), bevel=0.002)


WALL_STANDOFF = 0.05


def solar_wall(col, lying=False):
    """One module upright on two channel brackets, its back WALL_STANDOFF in front of y = 0 (the
    wall), its bottom edge at z = 0. `lying` lays it glass up on its brackets, as it lies on the
    ground."""
    # Turning +90 degrees about X takes glass up to glass to the front (-Y).
    module = group(col, "Wall_Module", solar_module(col, "Wall"), at=(0, -WALL_STANDOFF, MODULE[1] / 2),
                   rotate=(90, 0, 0))
    parts = [module]
    for x in (-0.33, 0.33):
        parts.append(box(col, "Wall_Bracket", M("galvanised"), (0.04, WALL_STANDOFF, MODULE[1] + 0.12),
                         at=(x, -WALL_STANDOFF / 2, -0.06), bevel=0.003))
        for z in (-0.04, MODULE[1] + 0.03):
            parts.append(box(col, "Wall_Lag", M("lead"), (0.018, 0.012, 0.018), at=(x, -WALL_STANDOFF - 0.004, z)))
    if lying:
        group(col, "Wall_Lying", parts, at=(0, -MODULE[1] / 2, 0), rotate=(-90, 0, 0))


RACK_TILT = 38
RACK_FRONT = 0.25  # height of the lower edge


def solar_rack(col, snow=False):
    """Two modules, one above the other, tilted RACK_TILT degrees to the front on a galvanised pipe
    frame."""
    tilt = math.radians(RACK_TILT)
    gap = 0.01
    span = 2 * MODULE[1] + gap
    panels = []
    for i, offset in enumerate((-(MODULE[1] + gap) / 2, (MODULE[1] + gap) / 2)):
        panels.append(group(col, "Rack_Module%d" % i, solar_module(col, "Rack%d" % i, snow=snow), at=(0, offset, 0)))
    group(col, "Rack_Panels", panels, at=(0, 0, RACK_FRONT + span / 2 * math.sin(tilt)), rotate=(RACK_TILT, 0, 0))
    if snow:
        return
    pipe = 0.016
    front_y, back_y = -span / 2 * math.cos(tilt), span / 2 * math.cos(tilt)
    top = RACK_FRONT + span * math.sin(tilt)
    for x in (-0.4, 0.4):
        tube(col, "Rack_Base", M("galvanised"), [(x, front_y - 0.05, pipe), (x, back_y + 0.04, pipe)], pipe, 8)
        tube(col, "Rack_FrontLeg", M("galvanised"), [(x, front_y + 0.02, 0), (x, front_y + 0.02, RACK_FRONT - 0.01)], pipe, 8)
        tube(col, "Rack_BackLeg", M("galvanised"), [(x, back_y - 0.03, 0), (x, back_y - 0.03, top - 0.035)], pipe, 8)
        tube(col, "Rack_Rafter", M("galvanised"),
             [(x, front_y - 0.02, RACK_FRONT - 0.02), (x, back_y, top - 0.02)], pipe * 0.9, 8)
        tube(col, "Rack_Brace", M("galvanised"), [(x, front_y + 0.02, pipe), (x, back_y - 0.03, top * 0.62)], pipe * 0.7, 6)
        for y in (front_y - 0.05, back_y + 0.04):
            box(col, "Rack_Foot", M("galvanised"), (0.07, 0.07, 0.006), at=(x, y, 0))
    tube(col, "Rack_Cross", M("galvanised"), [(-0.42, back_y - 0.03, 0.3), (0.42, back_y - 0.03, 0.3)], pipe * 0.8, 6)


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
        tube(col, name + "_Rope", M("black"), [(-width / 2 + 0.03, 0, height), (-width / 4, 0, height + 0.06),
                                               (width / 4, 0, height + 0.06), (width / 2 - 0.03, 0, height)], 0.006)
    elif handle == "sides":
        for sign in (-1, 1):
            tube(col, name + "_Handle", M("black"), [(sign * width / 2, -depth / 4, height - 0.06),
                                                     (sign * (width / 2 + 0.03), -depth / 5, height - 0.03),
                                                     (sign * (width / 2 + 0.03), depth / 5, height - 0.03),
                                                     (sign * width / 2, depth / 4, height - 0.06)], 0.007)


def deep_cycle_battery(col):
    """A group 27 marine and RV deep-cycle battery: blue, rope handle, wing-nut posts."""
    battery(col, "DeepCycle", (0.32, 0.17, 0.23), "marine", "white", caps=(-0.06, 0.06), cap_colour="white",
            label=("DEEP CYCLE", 0.03), handle="rope", post_height=0.03)


def l16_battery(col):
    """An L-16 6 V battery: tall, heavy, maroon, lifting handles at the ends."""
    battery(col, "L16", (0.30, 0.18, 0.43), "maroon", "battery", caps=(-0.08, 0.0, 0.08), cap_colour="black",
            label=("L-16", 0.05), handle="sides", post_height=0.035)


def bank_battery(col, name):
    """The generic flooded battery the bank and box tiles show, whatever type is inside."""
    battery(col, name, (0.18, 0.30, 0.24), "battery", "darkgrey", caps=(-0.03, 0.03), cap_colour="cream",
            handle=None, post_height=0.02)


# Battery bank and box -----------------------------------------------------------------------------

BANK = (0.92, 0.44, 1.18)
SHELVES = (0.06, 0.44, 0.82)
SLOTS = [(-0.315 + 0.21 * i) for i in range(4)]


def battery_bank(col, frame=True, batteries=0, meter_level=0):
    """The steel battery rack: three shelves of four batteries, a fused disconnect and a charge meter
    on top. `batteries` fills shelves from the bottom left; `meter_level` lights that many LEDs."""
    width, depth, height = BANK
    if frame:
        for x in (-width / 2 + 0.02, width / 2 - 0.02):
            for y in (-depth / 2 + 0.02, depth / 2 - 0.02):
                box(col, "Bank_Upright", M("steel"), (0.04, 0.04, height), at=(x, y, 0), bevel=0.004)
        for z in SHELVES:
            box(col, "Bank_Shelf", M("steel"), (width - 0.02, depth - 0.02, 0.02), at=(0, 0, z - 0.02), bevel=0.003)
            box(col, "Bank_Lip", M("steel"), (width - 0.02, 0.012, 0.04), at=(0, -depth / 2 + 0.006, z - 0.04), bevel=0.002)
        box(col, "Bank_Top", M("steel"), (width, depth, 0.025), at=(0, 0, height - 0.025), bevel=0.004)
        # Charge meter: a grey box on top with a row of five LEDs on its face.
        box(col, "Bank_Meter", M("grey"), (0.34, 0.08, 0.15), at=(-0.18, -depth / 2 + 0.06, height), bevel=0.008)
        box(col, "Bank_MeterFace", M("black"), (0.3, 0.004, 0.09), at=(-0.18, -depth / 2 + 0.019, height + 0.035))
        text(col, "Bank_MeterText", M("white"), "CHARGE", 0.022, at=(-0.18, -depth / 2 + 0.016, height + 0.098))
        for i in range(5):
            box(col, "Bank_Led", M("ledoff"), (0.04, 0.006, 0.04), at=(-0.3 + i * 0.06, -depth / 2 + 0.016, height + 0.05))
        # Fused disconnect on the right upright, cables down to the shelves.
        box(col, "Bank_Disconnect", M("grey"), (0.14, 0.1, 0.22), at=(width / 2 - 0.12, -depth / 2 + 0.03, height), bevel=0.01)
        box(col, "Bank_Handle", M("red"), (0.03, 0.05, 0.08), at=(width / 2 - 0.12, -depth / 2 - 0.03, height + 0.08), bevel=0.006)
        for i, colour in enumerate(("red", "black")):
            x = width / 2 - 0.05 - 0.03 * i
            tube(col, "Bank_MainCable", M(colour), [(x, -depth / 2 + 0.08, height + 0.05), (x + 0.02, depth / 2 - 0.06, height + 0.02),
                                                     (x + 0.02, depth / 2 - 0.06, 0.1)], 0.012)
    for i in range(batteries):
        shelf, slot = divmod(i, 4)
        name = "BankBattery%d" % i
        before = set(col.objects)
        bank_battery(col, name)
        for obj in set(col.objects) - before:
            obj.location.x += SLOTS[slot]
            obj.location.z += SHELVES[shelf]
        if slot > 0:
            # Series link from the last battery's + post to this one's - post.
            post_y = -0.15 + 0.03
            tube(col, name + "_Link", M("red" if slot % 2 else "black"),
                 [(SLOTS[slot - 1] + 0.055, post_y, SHELVES[shelf] + 0.26), (SLOTS[slot - 1] + 0.1, post_y - 0.01, SHELVES[shelf] + 0.29),
                  (SLOTS[slot] - 0.055, post_y, SHELVES[shelf] + 0.26)], 0.006)
    colours = ("ledred", "ledyellow", "ledgreen", "ledgreen", "ledgreen")
    for i in range(meter_level):
        box(col, "Bank_LedLit", M(colours[i]), (0.042, 0.006, 0.042), at=(-0.3 + i * 0.06, -depth / 2 + 0.013, height + 0.049))


BOX = (0.5, 0.36, 0.22)
PLY = 0.018


def battery_box(col, frame=True, batteries=0):
    """The stage-0 bank: an open plywood box for two batteries, its lid propped open against the
    back, with a terminal block and cable on the side."""
    width, depth, height = BOX
    if frame:
        box(col, "Box_Floor", M("plywood"), (width, depth, PLY), bevel=0.003)
        for sign in (-1, 1):
            box(col, "Box_Side", M("plywood"), (PLY, depth, height), at=(sign * (width - PLY) / 2, 0, 0), bevel=0.003)
            box(col, "Box_FrontBack", M("plywood"), (width - 2 * PLY, PLY, height), at=(0, sign * (depth - PLY) / 2, 0), bevel=0.003)
            box(col, "Box_Cleat", M("wood"), (0.025, 0.12, 0.03), at=(sign * (width / 2 + 0.012), 0, height - 0.07), bevel=0.004)
        box(col, "Box_Lid", M("plywood"), (width, PLY, depth), at=(0, depth / 2 + 0.03, height - 0.01),
                  rotate=(-12, 0, 0), bevel=0.003)
        box(col, "Box_Terminal", M("black"), (0.02, 0.1, 0.06), at=(width / 2 + 0.01, -0.08, 0.06), bevel=0.004)
        for i, colour in enumerate(("red", "black")):
            y = -0.1 + 0.04 * i
            tube(col, "Box_Lead", M(colour), [(width / 2 + 0.02, y, 0.09), (width / 2 + 0.06, y - 0.02, 0.05),
                                               (width / 2 + 0.09, y - 0.06, 0.01)], 0.007)
        text(col, "Box_Stencil", M("ink"), "12V", 0.06, at=(0, -depth / 2 - 0.0015, 0.07))
    for i in range(batteries):
        before = set(col.objects)
        bank_battery(col, "BoxBattery%d" % i)
        for obj in set(col.objects) - before:
            obj.location.x += (-0.11 if i == 0 else 0.11)
            obj.location.z += PLY


# Electronics --------------------------------------------------------------------------------------


def fins(col, name, mat, width, depth, z, count, height=0.008):
    """A row of `count` heat-sink fins or louvres across `width`, each running front to back."""
    for i in range(count):
        box(col, name, mat, (0.004, depth * 0.9, height), at=(-width / 2 + (i + 0.5) * width / count, 0, z))


def outlet(col, name, at, scale=1.0, turn=0):
    """A US NEMA 5-15 receptacle face: two slots and a ground hole, facing -Y before `turn` degrees
    about Z."""
    parts = [box(col, name + "_Face", M("cream"), (0.034 * scale, 0.003, 0.04 * scale), bevel=0.003)]
    for dx in (-0.007, 0.007):
        parts.append(box(col, name + "_Slot", M("ink"), (0.003 * scale, 0.002, 0.011 * scale),
                         at=(dx * scale, -0.002, 0.02 * scale)))
    parts.append(box(col, name + "_Ground", M("ink"), (0.005 * scale, 0.002, 0.005 * scale), at=(0, -0.002, 0.007 * scale)))
    return group(col, name, parts, at=at, rotate=(0, 0, turn))


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


def power_inverter(col):
    """A 600 W inverter: black steel case, louvred top, two outlets and a switch on the front."""
    width, depth, height = 0.3, 0.18, 0.075
    box(col, "Inv600_Case", M("black"), (width, depth, height), bevel=0.006)
    fins(col, "Inv600_Louvre", M("darkgrey"), width * 0.6, depth * 0.6, height, 9, height=0.002)
    box(col, "Inv600_Panel", M("darkgrey"), (width - 0.02, 0.003, height - 0.015), at=(0, -depth / 2 - 0.001, 0.007))
    outlet(col, "Inv600_OutletA", (-0.09, -depth / 2 - 0.003, 0.016))
    outlet(col, "Inv600_OutletB", (-0.04, -depth / 2 - 0.003, 0.016))
    box(col, "Inv600_Switch", M("red"), (0.02, 0.008, 0.025), at=(0.05, -depth / 2 - 0.004, 0.025), bevel=0.003)
    box(col, "Inv600_Led", M("ledgreen"), (0.008, 0.004, 0.008), at=(0.09, -depth / 2 - 0.003, 0.04))
    text(col, "Inv600_Text", M("white"), "600W", 0.02, at=(0.09, -depth / 2 - 0.004, 0.015))
    for sign, colour in ((1, "red"), (-1, "black")):
        cylinder(col, "Inv600_Terminal", M(colour), 0.012, 0.02, at=(sign * 0.05, depth / 2 + 0.01, 0.025),
                 rotate=(90, 0, 0), segments=10)


def inverter_charger(col):
    """A 2,500 W inverter/charger: a heavy blue-grey cabinet with a black control panel, heat-sink
    fins on top, carrying handles and big terminal covers."""
    width, depth, height = 0.52, 0.28, 0.22
    box(col, "InvChg_Case", M("bluegrey"), (width, depth, height), bevel=0.01)
    fins(col, "InvChg_Fin", M("aluminium"), width * 0.9, depth * 0.9, height, 16, height=0.025)
    box(col, "InvChg_Panel", M("black"), (0.3, 0.004, 0.14), at=(-0.08, -depth / 2 - 0.002, 0.04), bevel=0.002)
    for i, colour in enumerate(("ledgreen", "ledyellow", "ledred", "ledoff")):
        box(col, "InvChg_Led", M(colour), (0.012, 0.004, 0.012), at=(-0.2 + i * 0.03, -depth / 2 - 0.004, 0.14))
    cylinder(col, "InvChg_Knob", M("grey"), 0.02, 0.015, at=(0.02, -depth / 2 - 0.003, 0.09), rotate=(90, 0, 0), segments=14)
    text(col, "InvChg_Text", M("white"), "2500", 0.03, at=(-0.13, -depth / 2 - 0.005, 0.06))
    outlet(col, "InvChg_Outlet", (0.15, -depth / 2 - 0.003, 0.06), scale=1.2)
    for sign in (-1, 1):
        tube(col, "InvChg_Handle", M("darkgrey"), [(sign * (width / 2), -0.06, 0.16), (sign * (width / 2 + 0.035), -0.05, 0.16),
                                                    (sign * (width / 2 + 0.035), 0.05, 0.16), (sign * (width / 2), 0.06, 0.16)], 0.008)
    for x, colour in ((0.12, "red"), (0.2, "black")):
        box(col, "InvChg_TermCover", M(colour), (0.06, 0.05, 0.05), at=(x, depth / 2 + 0.02, 0.02), bevel=0.01)


def charge_controller(col):
    """A 30 A charge controller: a navy anodised box with fins, three LEDs and a terminal strip."""
    width, depth, height = 0.19, 0.13, 0.055
    box(col, "Ctrl_Case", M("navy"), (width, depth, height), bevel=0.005)
    fins(col, "Ctrl_Fin", M("aluminium"), width * 0.55, depth, height, 6, height=0.012)
    for i, colour in enumerate(("ledgreen", "ledyellow", "ledred")):
        box(col, "Ctrl_Led", M(colour), (0.008, 0.004, 0.008), at=(-0.06 + i * 0.02, -depth / 2 - 0.002, 0.03))
    box(col, "Ctrl_Strip", M("black"), (0.16, 0.025, 0.02), at=(0, depth / 2 + 0.01, 0.0), bevel=0.003)
    for i in range(6):
        cylinder(col, "Ctrl_Screw", M("lead"), 0.005, 0.004, at=(-0.065 + i * 0.026, depth / 2 + 0.012, 0.02), segments=8)
    text(col, "Ctrl_Text", M("white"), "30A", 0.02, at=(0.05, -depth / 2 - 0.002, 0.018))


def solar_failsafe(col, cable=True):
    """A generator auto-start relay box: grey enclosure, warning label, LED, a control cable."""
    width, depth, height = 0.18, 0.1, 0.14
    box(col, "Failsafe_Case", M("grey"), (width, depth, height), bevel=0.008)
    box(col, "Failsafe_Lid", M("darkgrey"), (width + 0.006, depth + 0.006, 0.012), at=(0, 0, height - 0.012), bevel=0.004)
    box(col, "Failsafe_Label", M("yellow"), (0.12, 0.002, 0.045), at=(0, -depth / 2 - 0.001, 0.05))
    text(col, "Failsafe_Text", M("ink"), "AUTO START", 0.0135, at=(0, -depth / 2 - 0.0025, 0.068))
    box(col, "Failsafe_Led", M("ledgreen"), (0.012, 0.004, 0.012), at=(0.06, -depth / 2 - 0.002, 0.1))
    box(col, "Failsafe_Switch", M("black"), (0.02, 0.006, 0.02), at=(-0.06, -depth / 2 - 0.002, 0.095))
    if cable:
        tube(col, "Failsafe_Cable", M("black"), [(width / 2, 0.02, 0.04), (width / 2 + 0.06, 0.03, 0.006),
                                                 (width / 2 + 0.16, 0.1, 0.006), (width / 2 + 0.2, 0.22, 0.006)], 0.007)


def solar_cell_charger(col):
    """A solar charger for AA cells: a yellow tray, a small mono panel in its lid, four cell bays."""
    width, depth, height = 0.18, 0.11, 0.035
    box(col, "CellChg_Tray", M("yellow"), (width, depth, height), bevel=0.006)
    box(col, "CellChg_Panel", M("black"), (0.1, depth - 0.02, 0.003), at=(-0.03, 0, height), bevel=0.001)
    for i in range(4):
        for j in range(2):
            box(col, "CellChg_Cell", M("mono"), (0.04, 0.035, 0.002), at=(-0.06 + i * 0.024 - 0.0, -0.02 + j * 0.04, height + 0.002))
    for i in range(4):
        box(col, "CellChg_Bay", M("black"), (0.012, 0.06, 0.004), at=(0.035 + i * 0.016, 0, height - 0.002))
    box(col, "CellChg_Led", M("ledgreen"), (0.008, 0.008, 0.004), at=(0.075, 0.042, height))


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


# Magazines and the crate --------------------------------------------------------------------------

MAGAZINE = (0.21, 0.275, 0.004)


def magazine(col, issue):
    """Homestead Power, a fictional 1990s homesteading magazine: issue 1 on sun and batteries,
    issue 2 on inverters and control."""
    width, depth, height = MAGAZINE
    cover = "magazine1" if issue == 1 else "magazine2"
    box(col, "Mag%d_Pages" % issue, M("white"), (width - 0.004, depth - 0.004, height - 0.001))
    box(col, "Mag%d_Cover" % issue, M(cover), (width, depth, 0.001), at=(0, 0, height - 0.001))
    top = height + 0.0003
    flat = (0, 0, 0)
    text(col, "Mag%d_Title" % issue, M("white" if issue == 2 else "ink"), "HOMESTEAD", 0.03, at=(0, 0.09, top), rotate=flat)
    text(col, "Mag%d_Title2" % issue, M("white" if issue == 2 else "ink"), "POWER", 0.036, at=(0, 0.052, top), rotate=flat)
    text(col, "Mag%d_Issue" % issue, M("red"), "#%d" % issue, 0.03, at=(0.075, 0.105, top), rotate=flat)
    box(col, "Mag%d_Picture" % issue, M("sky"), (0.17, 0.13, 0.0004), at=(0, -0.04, height))
    if issue == 1:
        cylinder(col, "Mag1_Sun", M("sun"), 0.025, 0.0006, at=(-0.045, -0.0, height + 0.0002), segments=16)
        box(col, "Mag1_Panel", M("cells"), (0.09, 0.05, 0.0008), at=(0.025, -0.065, height + 0.0002), rotate=(0, 0, -8))
        box(col, "Mag1_Battery", M("marine"), (0.04, 0.025, 0.0009), at=(-0.05, -0.085, height + 0.0002))
        line = "SUN & BATTERIES"
    else:
        box(col, "Mag2_Inverter", M("bluegrey"), (0.08, 0.05, 0.0008), at=(-0.02, -0.05, height + 0.0002))
        box(col, "Mag2_Panel", M("black"), (0.04, 0.03, 0.0009), at=(-0.03, -0.05, height + 0.0003))
        prism(col, "Mag2_Bolt", M("sun"), [(0, 0.05), (0.02, 0.0), (0.008, 0.0), (0.016, -0.04), (-0.006, 0.01), (0.006, 0.01)],
              0.0008, at=(0.055, -0.04, height + 0.0002), rotate=(90, 0, 0))
        line = "INVERTERS & CONTROL"
    text(col, "Mag%d_Line" % issue, M("white"), line, 0.015, at=(0, -0.122, top), rotate=flat)


def magazine_1(col):
    magazine(col, 1)


def magazine_2(col):
    magazine(col, 2)


CRATE = (0.99, 0.5, 0.3)


def solar_crate(col, box_=True, contents=False, closed=False):
    """The cardboard carton solar modules ship in: open, its flaps folded down the outside, with
    modules inside (`contents`) or its top flaps taped shut (`closed`)."""
    width, depth, height = CRATE
    wall = 0.006
    if box_:
        box(col, "Crate_Bottom", M("cardboard"), (width, depth, wall))
        for sign in (-1, 1):
            box(col, "Crate_Side", M("cardboard"), (wall, depth, height), at=(sign * (width - wall) / 2, 0, 0))
            box(col, "Crate_Wall", M("cardboard"), (width, wall, height), at=(0, sign * (depth - wall) / 2, 0))
            box(col, "Crate_FlapLong", M("cardboard"), (width - 0.01, wall, depth / 2 - 0.02),
                at=(0, sign * (depth / 2 + wall), height - depth / 2 + 0.02), rotate=(sign * 6, 0, 0))
        text(col, "Crate_Print", M("ink"), "SOLAR MODULES", 0.05, at=(0, -depth / 2 - wall - 0.002, 0.07))
        text(col, "Crate_Print2", M("red"), "FRAGILE - GLASS", 0.03, at=(0, -depth / 2 - wall - 0.002, 0.025))
    if contents:
        for k in range(3):
            group(col, "Crate_Module%d" % k, solar_module(col, "CrateModule%d" % k),
                  at=(0, 0, height - 0.11 - (2 - k) * 0.04))
        group(col, "Crate_ModuleTop", solar_module(col, "CrateModuleTop"), at=(0, 0.02, height - 0.05), rotate=(14, 0, 0))
    if closed:
        box(col, "Crate_Top", M("cardboard"), (width - 0.004, depth - 0.004, wall), at=(0, 0, height - wall))
        box(col, "Crate_Seam", M("ink"), (width - 0.01, 0.002, 0.0005), at=(0, 0, height + 0.0002))
        box(col, "Crate_Tape", M("tape"), (width + 0.01, 0.05, 0.0012), at=(0, 0, height))


# Inventory items ----------------------------------------------------------------------------------

# Item type -> builder of its ground model, of its icon when that shows more, and the icon's
# camera elevation in degrees when the 30 of a tile would show a flat thing edge on.
ITEMS = {
    "SolarModule": {"model": solar_module, "icon_elevation": 55},
    "SolarFlat": {"model": solar_flat, "icon_elevation": 25},
    "SolarWall": {"model": lambda col: solar_wall(col, lying=True), "icon": solar_wall},
    "SolarRack": {"model": solar_rack},
    "BatteryBox": {"model": battery_box, "icon": lambda col: battery_box(col, batteries=2)},
    "BatteryBank": {"model": battery_bank, "icon": lambda col: battery_bank(col, batteries=6, meter_level=4)},
    "PlugInInverter": {"model": plug_in_inverter},
    "PowerInverter": {"model": power_inverter},
    "InverterCharger": {"model": inverter_charger},
    "ChargeController": {"model": charge_controller},
    "SolarFailsafe": {"model": solar_failsafe, "icon": lambda col: solar_failsafe(col, cable=False)},
    "DeepCycleBattery": {"model": deep_cycle_battery},
    "L16Battery": {"model": l16_battery},
    "SolarMaintainer": {"model": solar_maintainer, "icon_elevation": 40},
    "SolarCellCharger": {"model": solar_cell_charger, "icon_elevation": 45},
    "HomesteadPowerMag1": {"model": magazine_1, "icon_elevation": 70},
    "HomesteadPowerMag2": {"model": magazine_2, "icon_elevation": 70},
}
