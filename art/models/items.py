"""The parts of every model, in real-world sizes of 1993 hardware.

Each builder adds one thing's parts to a collection, standing on z = 0, centred, front to -Y (see
kit.py). ITEMS lists what each inventory item's ground model and icon are made of; tiles.py places
the same builders on tiles. A builder takes keyword options, so a tile can draw a battery rack
without its batteries and an overlay just the batteries.
"""
import math
import random

from kit import beam, box, cylinder, group, material, prism, text, tube

# Palette ------------------------------------------------------------------------------------------


def M(name):
    """The shared materials, made on first use."""
    return {
        "aluminium": lambda: material("RE_Aluminium", "#b9bdc1", roughness=0.35, metallic=0.8, grime=0.08),
        "galvanised": lambda: material("RE_Galvanised", "#a3a9ab", roughness=0.5, metallic=0.7, grime=0.2),
        "cells": lambda: material("RE_PolyCells", "#1d3a7c", roughness=0.25, metallic=0.2, grime=0.05,
                                  speckle=("#4c78c8", 0.9)),
        "backsheet": lambda: material("RE_Backsheet", "#e9e8df", roughness=0.5, grime=0.05),
        "busbar": lambda: material("RE_Busbar", "#cfd2d6", roughness=0.3, metallic=0.9, grime=0.0),
        "amorphous": lambda: material("RE_Amorphous", "#2c3a78", roughness=0.2, metallic=0.25, grime=0.05),
        "mono": lambda: material("RE_MonoCells", "#17191f", roughness=0.25, metallic=0.3, grime=0.04),
        # Broken cover glass: the fractures catch the light and read pale over the cells.
        "crack": lambda: material("RE_Crack", "#dfe7ee", roughness=0.3, grime=0.0),
        "black": lambda: material("RE_BlackPlastic", "#1f2022", roughness=0.55, grime=0.15),
        "darkgrey": lambda: material("RE_DarkGrey", "#3a3c3f", roughness=0.5, grime=0.15),
        "grey": lambda: material("RE_GreyPaint", "#8b9089", roughness=0.55, grime=0.2),
        "battery": lambda: material("RE_BatteryCase", "#29292b", roughness=0.6, grime=0.15),
        # A shade lighter than the game's own car battery's grey, which it draws nearly black on a
        # face as big as an open case's, with the same label, so the case stripped from one reads as it.
        "carbattery": lambda: material("RE_CarBattery", "#585858", roughness=0.6, grime=0.15),
        "carlabel": lambda: material("RE_CarLabel", "#698a5f", roughness=0.6, grime=0.1),
        "bolt": lambda: material("RE_Bolt", "#e9e147", roughness=0.5, grime=0.0),
        # The grey paste and sulphate a battery's plates leave smeared on the inside of its case.
        "leadstain": lambda: material("RE_LeadStain", "#99958a", roughness=0.9, grime=0.4, scale=30),
        "marine": lambda: material("RE_MarineBlue", "#2155a8", roughness=0.45, grime=0.12),
        "maroon": lambda: material("RE_Maroon", "#8c2a2f", roughness=0.5, grime=0.15),
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
        # Pine boards and 2 x 4s, two shades so neighbouring boards read apart.
        "pine": lambda: material("RE_Pine", "#c39b62", roughness=0.8, grime=0.3, scale=9),
        "pinedark": lambda: material("RE_PineDark", "#9a7041", roughness=0.8, grime=0.3, scale=9),
        # Bare mild steel with darker weld beads at its joints.
        "rawsteel": lambda: material("RE_RawSteel", "#8c9296", roughness=0.5, metallic=0.6, grime=0.35),
        "weld": lambda: material("RE_Weld", "#3f3c39", roughness=0.75, metallic=0.5, grime=0.3),
        "copper": lambda: material("RE_Copper", "#c27a3e", roughness=0.35, metallic=0.85, grime=0.1),
        "lens": lambda: material("RE_Lens", "#e6e2d4", roughness=0.25, grime=0.05),
        "lenslit": lambda: material("RE_LensLit", "#ffd28a", roughness=0.25, grime=0.0, emission="#ffc46a"),
        "clay": lambda: material("RE_Clay", "#8e8172", roughness=0.9, grime=0.2, scale=16),
        "terracotta": lambda: material("RE_Terracotta", "#b2603b", roughness=0.85, grime=0.25, scale=16),
        "hdpe": lambda: material("RE_Hdpe", "#e8e4d8", roughness=0.5, grime=0.1),
        "sulphate": lambda: material("RE_Sulphate", "#dcd9cb", roughness=0.95, grime=0.15, scale=60),
        "plate": lambda: material("RE_Plate", "#6a6e72", roughness=0.6, metallic=0.5, grime=0.2),
        # Highway work-zone orange, the amber of its reflectors, and the board's lamps while they're
        # dark: lit, the vehicle's lights texture draws them bright (models.GLOWING).
        "safety": lambda: material("RE_SafetyOrange", "#e0661a", roughness=0.5, grime=0.25),
        "amberlamp": lambda: material("RE_AmberLamp", "#f5a623", roughness=0.3, grime=0.05),
        "amberlampdark": lambda: material("RE_AmberLampDark", "#6e4510", roughness=0.3, grime=0.05),
    }[name]()


# Solar modules ------------------------------------------------------------------------------------

# A 51 W multicrystalline module of the early nineties (Kyocera's K51 is 986 x 446 mm): 36 cells in
# four strings of nine, on a white backsheet, in a clear anodised frame.
MODULE = (0.986, 0.446, 0.036)
FRAME = 0.028


# A module whose condition is below Specs.crackedBelow has a cracked cover glass, drawn by
# module_cracks everywhere it shows: on the mounts' crack overlay tiles and on the arrow board
# trailer's cracked panels. Lines wide enough to read at a tile's scale, about a centimetre a pixel.
CRACK_WIDTH = 0.01


def module_cracks(col, name):
    """The cracks of a broken cover glass, lying on a module built by solar_module: lines
    radiating from where something struck it, and a broken ring round the strike."""
    width, depth, height = MODULE
    inner_w, inner_d = width / 2 - FRAME - 0.01, depth / 2 - FRAME - 0.01
    rng = random.Random(42)
    strike = (0.14, -0.03)
    z = height - 0.0018
    parts = []

    def segment(a, b):
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        angle = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        parts.append(box(col, name + "_Crack", M("crack"), (length + CRACK_WIDTH * 0.5, CRACK_WIDTH, 0.0008),
                         at=((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, z), rotate=(0, 0, angle)))

    for i in range(9):
        heading = 2 * math.pi * i / 9 + rng.uniform(-0.3, 0.3)
        reach = rng.uniform(0.18, 0.5)
        point = strike
        for _ in range(3):
            heading += rng.uniform(-0.35, 0.35)
            x = max(-inner_w, min(inner_w, point[0] + reach / 3 * math.cos(heading)))
            y = max(-inner_d, min(inner_d, point[1] + reach / 3 * math.sin(heading)))
            segment(point, (x, y))
            point = (x, y)
    ring = 0.07
    for i in range(8):
        if i % 3 == 2:
            continue
        a0, a1 = 2 * math.pi * i / 8, 2 * math.pi * (i + 1) / 8
        segment((strike[0] + ring * math.cos(a0), strike[1] + ring * math.sin(a0)),
                (strike[0] + ring * math.cos(a1), strike[1] + ring * math.sin(a1)))
    return parts


def solar_module(col, name="Module", snow=False, cracked=False, cracks=False):
    """A module lying glass up. `snow` adds only the snow lying on it and `cracks` only the cracks
    of a broken glass, for overlay tiles; `cracked` draws the whole module with those cracks."""
    if cracks:
        return module_cracks(col, name)
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
    if cracked:
        parts += module_cracks(col, name)
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


def solar_flat(col, snow=False, cracks=False):
    """One module on two low rails, for a roof or the ground at 0 degrees. `snow` and `cracks` give
    only the snow on it or the cracks in its glass, for overlay tiles."""
    module = solar_module(col, "Flat", snow=snow, cracks=cracks)
    lift = 0.045
    for obj in module:
        obj.location.z += lift
    if snow or cracks:
        return
    for sign in (-1, 1):
        box(col, "Flat_Rail", M("aluminium"), (MODULE[0] - 0.12, 0.03, lift), at=(0, sign * 0.13, 0), bevel=0.002)
        for x in (-0.38, 0.38):
            box(col, "Flat_Foot", M("galvanised"), (0.05, 0.07, 0.008), at=(x, sign * 0.13, 0), bevel=0.002)


WALL_STANDOFF = 0.05


def solar_wall(col, material="metal", lying=False, cracks=False):
    """One module upright, its back WALL_STANDOFF in front of y = 0 (the wall), its bottom edge at
    z = 0: on two galvanised channel brackets lagged to the wall, or on two pine battens with a
    ledger board under it and cleats nailed over its top edge. `lying` lays it glass up on its
    brackets, as it lies on the ground. `cracks` gives only the cracks in its glass."""
    # Turning +90 degrees about X takes glass up to glass to the front (-Y).
    module = group(col, "Wall_Module", solar_module(col, "Wall", cracks=cracks), at=(0, -WALL_STANDOFF, MODULE[1] / 2),
                   rotate=(90, 0, 0))
    if cracks:
        return
    parts = [module]
    if material == "metal":
        for x in (-0.33, 0.33):
            parts.append(box(col, "Wall_Bracket", M("galvanised"), (0.04, WALL_STANDOFF, MODULE[1] + 0.12),
                             at=(x, -WALL_STANDOFF / 2, -0.06), bevel=0.003))
            for z in (-0.04, MODULE[1] + 0.03):
                parts.append(box(col, "Wall_Lag", M("lead"), (0.018, 0.012, 0.018), at=(x, -WALL_STANDOFF - 0.004, z)))
    else:
        for x in (-0.36, 0.36):
            parts.append(box(col, "Wall_Batten", M("pinedark"), (0.07, WALL_STANDOFF, MODULE[1] + 0.2),
                             at=(x, -WALL_STANDOFF / 2, -0.1), bevel=0.004))
            parts.append(box(col, "Wall_Cleat", M("pine"), (0.1, 0.02, 0.05),
                             at=(x, -WALL_STANDOFF - MODULE[2] - 0.01, MODULE[1] - 0.03), bevel=0.003))
            for z in (-0.07, MODULE[1] + 0.05):
                parts.append(cylinder(col, "Wall_Nail", M("lead"), 0.006, 0.004, at=(x, -WALL_STANDOFF, z),
                                      rotate=(90, 0, 0), segments=8))
        parts.append(box(col, "Wall_Ledger", M("pine"), (MODULE[0] + 0.06, WALL_STANDOFF + MODULE[2] + 0.02, 0.04),
                         at=(0, -(WALL_STANDOFF + MODULE[2] + 0.02) / 2, -0.04), bevel=0.004))
    if lying:
        group(col, "Wall_Lying", parts, at=(0, -MODULE[1] / 2, 0), rotate=(-90, 0, 0))


RACK_TILT = 38
RACK_FRONT = 0.25  # height of the lower edge


def solar_rack(col, material="metal", snow=False, cracks=None):
    """Two modules, one above the other, tilted RACK_TILT degrees to the front on a galvanised pipe
    frame or a frame of pine 2 x 4s on skids. Both hold the modules in the same place, so the
    snow on them is the same. `cracks`, a module slot (1 the lower module, 2 the upper), gives only
    the cracks in that module's glass."""
    tilt = math.radians(RACK_TILT)
    gap = 0.01
    span = 2 * MODULE[1] + gap
    panels = []
    for i, offset in enumerate((-(MODULE[1] + gap) / 2, (MODULE[1] + gap) / 2)):
        if cracks and cracks != i + 1:
            continue
        module = solar_module(col, "Rack%d" % i, snow=snow, cracks=bool(cracks))
        panels.append(group(col, "Rack_Module%d" % i, module, at=(0, offset, 0)))
    group(col, "Rack_Panels", panels, at=(0, 0, RACK_FRONT + span / 2 * math.sin(tilt)), rotate=(RACK_TILT, 0, 0))
    if snow or cracks:
        return
    front_y, back_y = -span / 2 * math.cos(tilt), span / 2 * math.cos(tilt)
    top = RACK_FRONT + span * math.sin(tilt)
    if material == "metal":
        _pipe_rack_frame(col, front_y, back_y, top)
    else:
        _timber_rack_frame(col, front_y, back_y, top)


def _pipe_rack_frame(col, front_y, back_y, top):
    pipe = 0.016
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


def _timber_rack_frame(col, front_y, back_y, top):
    """2 x 4s (38 x 89 mm) on edge: a skid each side, posts and a rafter under the modules, a
    diagonal brace, and two boards across the back."""
    stud = (0.038, 0.089)
    skid_z = stud[1] / 2
    # The rafter's centre line runs half its depth below the modules' underside.
    drop = stud[1] / 2 / math.cos(math.radians(RACK_TILT))
    for i, x in enumerate((-0.42, 0.42)):
        beam(col, "Rack_Skid", M("pinedark"), (x, front_y - 0.07, skid_z), (x, back_y + 0.06, skid_z), stud, bevel=0.004)
        beam(col, "Rack_FrontPost", M("pine"), (x, front_y + 0.04, stud[1]), (x, front_y + 0.04, RACK_FRONT - drop),
             (stud[0], stud[0] * 1.6), bevel=0.004)
        beam(col, "Rack_BackPost", M("pine"), (x, back_y - 0.05, stud[1]), (x, back_y - 0.05, top - drop - 0.02),
             (stud[0], stud[0] * 1.6), bevel=0.004)
        beam(col, "Rack_Rafter", M("pinedark" if i else "pine"), (x, front_y - 0.03, RACK_FRONT - drop),
             (x, back_y + 0.01, top - drop), stud, bevel=0.004)
        beam(col, "Rack_Brace", M("pine"), (x + 0.03 * (1 if x < 0 else -1), front_y + 0.06, stud[1]),
             (x + 0.03 * (1 if x < 0 else -1), back_y - 0.07, top * 0.6), (0.02, 0.07), bevel=0.003)
    for z in (0.22, top * 0.62):
        beam(col, "Rack_BackBoard", M("pine"), (-0.47, back_y - 0.005, z), (0.47, back_y - 0.005, z), (0.089, 0.02),
             bevel=0.003)


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


# An L-16's case, a little shorter than a real one's 0.43 m: at full height it towered over the
# game's car battery, which is drawn small (DEVELOPMENT.md).
L16 = (0.30, 0.18, 0.38)


def l16_battery(col):
    """An L-16 6 V battery: tall, heavy, maroon, lifting handles at the ends."""
    battery(col, "L16", L16, "maroon", "battery", caps=(-0.08, 0.0, 0.08), cap_colour="black",
            label=("L-16", 0.05), handle="sides", post_height=0.035)


def bank_battery(col, name):
    """The generic flooded battery the bank and box tiles show, whatever type is inside."""
    battery(col, name, (0.18, 0.30, 0.24), "battery", "darkgrey", caps=(-0.03, 0.03), cap_colour="cream",
            handle=None, post_height=0.02)


# Battery storage ----------------------------------------------------------------------------------
#
# Each tier comes in pine and in welded steel, the same size on the floor. Every builder takes
# `frame` (the storage itself), `batteries` (how many stand in it, filled from the bottom left)
# and `meter_level` (how many of its charge meter's five LEDs are lit), so a tile can draw the
# frame alone and an overlay just the batteries or just the lit LEDs.

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


def bank_batteries(col, name, slots, count):
    """`count` batteries standing in `slots` = [(x, z), ...] in order, each linked in series to the
    one before it on the same shelf, from that one's + post to its - post."""
    post_x, post_y = 0.055, -0.12
    for i in range(count):
        x, z = slots[i]
        battery_name = "%sBattery%d" % (name, i)
        before = set(col.objects)
        bank_battery(col, battery_name)
        for obj in set(col.objects) - before:
            obj.location.x += x
            obj.location.z += z
        if i > 0 and slots[i - 1][1] == z:
            last_x = slots[i - 1][0]
            tube(col, battery_name + "_Link", M("red" if i % 2 else "black"),
                 [(last_x + post_x, post_y, z + 0.26), ((last_x + x) / 2, post_y - 0.01, z + 0.265),
                  (x - post_x, post_y, z + 0.26)], 0.006)


BOX = (0.5, 0.36, 0.22)
PLY = 0.018
SHEET = 0.004


def battery_box(col, material, frame=True, batteries=0, meter_level=0):
    """The first bank: an open box for two batteries, its lid propped open against the back, a
    terminal block and leads on its side and a small charge meter on its front. Plywood with
    pine cleats, or steel sheet welded at the corners with an angle-iron rim and side handles."""
    width, depth, height = BOX
    floor = PLY if material == "wood" else SHEET
    if frame:
        if material == "wood":
            _plywood_box(col)
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
    bank_batteries(col, "Box", [(-0.11, floor), (0.11, floor)], batteries)


def _plywood_box(col):
    width, depth, height = BOX
    box(col, "Box_Floor", M("plywood"), (width, depth, PLY), bevel=0.003)
    for sign in (-1, 1):
        box(col, "Box_Side", M("plywood"), (PLY, depth, height), at=(sign * (width - PLY) / 2, 0, 0), bevel=0.003)
        box(col, "Box_FrontBack", M("plywood"), (width - 2 * PLY, PLY, height), at=(0, sign * (depth - PLY) / 2, 0), bevel=0.003)
        box(col, "Box_Cleat", M("wood"), (0.025, 0.12, 0.03), at=(sign * (width / 2 + 0.012), 0, height - 0.07), bevel=0.004)
    box(col, "Box_Lid", M("plywood"), (width, PLY, depth), at=(0, depth / 2 + 0.03, height - 0.01),
        rotate=(-12, 0, 0), bevel=0.003)


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
        tube(col, "Box_Handle", M("rawsteel"), [(sign * width / 2, -0.07, height - 0.07), (sign * (width / 2 + 0.035), -0.05, height - 0.06),
                                                (sign * (width / 2 + 0.035), 0.05, height - 0.06), (sign * width / 2, 0.07, height - 0.07)],
             0.007)
        for y_sign in (-1, 1):
            box(col, "Box_Weld", M("weld"), (0.01, 0.01, height - 0.02),
                at=(sign * (width / 2 + 0.001), y_sign * (depth / 2 + 0.001), 0.01))
    for x in (-0.15, 0.15):
        cylinder(col, "Box_Hinge", M("weld"), 0.009, 0.05, at=(x - 0.025, depth / 2 + rim / 2, height), rotate=(0, 90, 0),
                 segments=8)
    box(col, "Box_Lid", M("rawsteel"), (width + 2 * rim, SHEET, depth + rim), at=(0, depth / 2 + rim, height),
        rotate=(-12, 0, 0))


SHELVING = (0.92, 0.44)
SLOTS_4 = tuple(-0.315 + 0.21 * i for i in range(4))
SLOTS_3 = (-0.28, 0.0, 0.28)

# Shelving tiers: overall height, the top of each shelf a row of batteries stands on, and the
# battery positions across a shelf. Steel shelves are thinner, so a metal tier fits a shelf
# or a battery more in the same space.
RACK_WOOD = {"height": 0.76, "shelves": (0.07, 0.43), "slots": SLOTS_3}
RACK_METAL = {"height": 0.76, "shelves": (0.05, 0.41), "slots": SLOTS_4}
BANK_WOOD = {"height": 1.24, "shelves": (0.07, 0.47, 0.87), "slots": SLOTS_4}
BANK_METAL = {"height": 1.24, "shelves": (0.05, 0.35, 0.65, 0.95), "slots": SLOTS_4}


def battery_shelving(col, tier, material, frame=True, batteries=0, meter_level=0):
    """A battery rack or bank: shelves of batteries in pine or angle iron, a fused disconnect and
    a charge meter on top."""
    width, depth = SHELVING
    height = tier["height"]
    if frame:
        if material == "wood":
            _pine_shelving(col, height, tier["shelves"])
        else:
            _steel_shelving(col, height, tier["shelves"])
        # Fused disconnect on the right, its cables down the back to the bottom shelf.
        box(col, "Shelving_Disconnect", M("grey"), (0.14, 0.1, 0.22), at=(width / 2 - 0.12, -depth / 2 + 0.06, height), bevel=0.01)
        box(col, "Shelving_Handle", M("red"), (0.03, 0.05, 0.08), at=(width / 2 - 0.12, -depth / 2, height + 0.08), bevel=0.006)
        for i, colour in enumerate(("red", "black")):
            x = width / 2 - 0.05 - 0.03 * i
            tube(col, "Shelving_MainCable", M(colour), [(x, -depth / 2 + 0.1, height + 0.05), (x + 0.02, depth / 2 - 0.06, height + 0.02),
                                                         (x + 0.02, depth / 2 - 0.06, 0.1)], 0.012)
    charge_meter(col, (-0.18, -depth / 2 + 0.08, height), frame, meter_level)
    slots = [(x, z) for z in tier["shelves"] for x in tier["slots"]]
    bank_batteries(col, "Shelving", slots, batteries)


def _pine_shelving(col, height, shelves):
    """2 x 4 corner posts, each shelf three boards with an apron board nailed along its front and
    back, a top of boards, and a diagonal brace across the back."""
    width, depth = SHELVING
    for x in (-width / 2 + 0.019, width / 2 - 0.019):
        for y in (-depth / 2 + 0.045, depth / 2 - 0.045):
            box(col, "Shelving_Post", M("pinedark"), (0.038, 0.089, height), at=(x, y, 0), bevel=0.004)
    boards = 3
    board_depth = depth / boards
    for z in shelves + (height,):
        for i in range(boards):
            box(col, "Shelving_Board", M("pine" if i % 2 == 0 else "pinedark"), (width, board_depth - 0.006, 0.02),
                at=(0, -depth / 2 + board_depth * (i + 0.5), z - 0.02), bevel=0.003)
        apron_bottom = max(0.0, z - 0.09)
        for sign in (-1, 1):
            box(col, "Shelving_Apron", M("pine"), (width, 0.02, z - apron_bottom), at=(0, sign * (depth / 2 + 0.01), apron_bottom),
                bevel=0.003)
        for x in (-width / 2 + 0.019, width / 2 - 0.019):
            for dz in (0.025, 0.06):
                if z - dz > apron_bottom:
                    cylinder(col, "Shelving_Nail", M("lead"), 0.005, 0.003, at=(x, -depth / 2 - 0.02, z - dz),
                             rotate=(90, 0, 0), segments=8)
    beam(col, "Shelving_Brace", M("pinedark"), (-width / 2 + 0.05, depth / 2 + 0.03, 0.1),
         (width / 2 - 0.05, depth / 2 + 0.03, height - 0.1), (0.07, 0.02), bevel=0.003)


def _steel_shelving(col, height, shelves):
    """Angle-iron uprights, each shelf a steel sheet on angle-iron rails welded between them, a
    sheet on top, and flat bars crossed on the back."""
    width, depth = SHELVING
    angle, thick = 0.04, SHEET
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(col, "Shelving_Angle", M("rawsteel"), (angle, thick, height), at=(sx * (width - angle) / 2, sy * (depth - thick) / 2, 0))
            box(col, "Shelving_Angle", M("rawsteel"), (thick, angle, height), at=(sx * (width - thick) / 2, sy * (depth - angle) / 2, 0))
            box(col, "Shelving_Foot", M("rawsteel"), (0.06, 0.06, 0.005), at=(sx * (width / 2 - 0.03), sy * (depth / 2 - 0.03), 0))
    rail = width - 2 * angle
    for z in shelves + (height,):
        box(col, "Shelving_Sheet", M("rawsteel"), (width - 2 * thick, depth - 2 * thick, thick), at=(0, 0, z - thick))
        for sy in (-1, 1):
            box(col, "Shelving_Rail", M("rawsteel"), (rail, thick, 0.035), at=(0, sy * (depth / 2 - thick / 2), max(0.0, z - 0.035)))
            for sx in (-1, 1):
                box(col, "Shelving_Weld", M("weld"), (0.012, 0.008, 0.035),
                    at=(sx * rail / 2, sy * (depth / 2 + 0.002), max(0.0, z - 0.035)))
    back = depth / 2 + 0.004
    for sx in (-1, 1):
        beam(col, "Shelving_Brace", M("rawsteel"), (sx * (width / 2 - 0.03), back, 0.06), (-sx * (width / 2 - 0.03), back, height - 0.06),
             (0.03, 0.005))


# The item type of every battery storage tier and its builder.
STORAGE = {
    "BatteryBoxWood": lambda col, **options: battery_box(col, "wood", **options),
    "BatteryBoxMetal": lambda col, **options: battery_box(col, "metal", **options),
    "BatteryRackWood": lambda col, **options: battery_shelving(col, RACK_WOOD, "wood", **options),
    "BatteryRackMetal": lambda col, **options: battery_shelving(col, RACK_METAL, "metal", **options),
    "BatteryBankWood": lambda col, **options: battery_shelving(col, BANK_WOOD, "wood", **options),
    "BatteryBankMetal": lambda col, **options: battery_shelving(col, BANK_METAL, "metal", **options),
}


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


# Homemade modules, cells and the garden light -----------------------------------------------------

HOMEMADE = (0.92, 0.42, 0.04)


def homemade_module(col):
    """A module built at home from salvaged cells: a plywood back in a frame of pine strips, window
    glass held down by clips, and 12 big cells of two kinds, uneven and a little askew, a strip of
    tabbing along each row, its leads out through the frame."""
    width, depth, height = HOMEMADE
    strip = 0.032
    rng = random.Random(42)
    box(col, "Homemade_Back", M("plywood"), (width, depth, 0.012), bevel=0.002)
    for sign in (-1, 1):
        box(col, "Homemade_FrameLong", M("pine"), (width, strip, height), at=(0, sign * (depth - strip) / 2, 0), bevel=0.004)
        box(col, "Homemade_FrameShort", M("pinedark"), (strip, depth - 2 * strip, height),
            at=(sign * (width - strip) / 2, 0, 0), bevel=0.004)
    inner_w, inner_d = width - 2 * strip, depth - 2 * strip
    columns, rows = 6, 2
    pitch_x, pitch_y = inner_w / columns, inner_d / rows
    for row in range(rows):
        y = -inner_d / 2 + pitch_y * (row + 0.5)
        for column in range(columns):
            x = -inner_w / 2 + pitch_x * (column + 0.5)
            # Thin enough to bake into the back's texture, as the factory module's cells do.
            box(col, "Homemade_Cell", M("mono" if rng.random() < 0.25 else "cells"),
                (pitch_x * rng.uniform(0.84, 0.93), pitch_y * rng.uniform(0.84, 0.93), 0.002),
                at=(x + rng.uniform(-0.006, 0.006), y + rng.uniform(-0.005, 0.005), 0.012), rotate=(0, 0, rng.uniform(-4, 4)))
        box(col, "Homemade_Tab", M("busbar"), (inner_w - 0.02, 0.003, 0.0008), at=(0, y, 0.0142))
    for x in (-width / 2 + 0.12, 0, width / 2 - 0.12):
        for sign in (-1, 1):
            box(col, "Homemade_Clip", M("aluminium"), (0.03, 0.045, 0.004), at=(x, sign * (depth / 2 - 0.02), height))
    for i, colour in enumerate(("red", "black")):
        y = 0.03 * i
        tube(col, "Homemade_Lead", M(colour), [(width / 2 - 0.01, y, 0.025), (width / 2 + 0.05, y + 0.01, 0.02),
                                               (width / 2 + 0.09, y + 0.05, 0.006)], 0.005)


def solar_cells(col):
    """A handful of loose cells salvaged from gadgets and broken modules, stacked askew, a strip of
    tabbing ribbon still soldered to the top one."""
    rng = random.Random(7)
    size, thick = 0.1, 0.004
    for i in range(4):
        cell = [box(col, "Cells_Cell", M("cells" if i % 2 else "mono"), (size, size, thick))]
        for offset in (-size / 4, size / 4):
            cell.append(box(col, "Cells_Busbar", M("busbar"), (0.003, size - 0.01, 0.0006), at=(offset, 0, thick)))
        group(col, "Cells_Stacked", cell, at=(rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), i * thick),
              rotate=(0, 0, rng.uniform(-25, 25)))
    tube(col, "Cells_Ribbon", M("copper"), [(0.0, 0.0, 4 * thick + 0.001), (0.06, -0.03, 4 * thick), (0.09, -0.07, 0.002)], 0.002, 4)


def solar_garden_light(col, lit=False, stake=True):
    """A solar path light: a frosted lens under a black cap with a little mono cell on top, on a
    black post. `lit` makes the lens glow warm; the light it casts on the ground is the game's,
    from the lamp SolarGardenLight lights on its square. `stake` adds the spike that a placed
    light has in the ground."""
    base = 0.1 if stake else 0.0
    post = 0.32
    if stake:
        cylinder(col, "Garden_Stake", M("black"), 0.003, base, radius_top=0.016, segments=8)
    cylinder(col, "Garden_Post", M("black"), 0.014, post, at=(0, 0, base), segments=10)
    cylinder(col, "Garden_Collar", M("black"), 0.056, 0.012, at=(0, 0, base + post), segments=16)
    cylinder(col, "Garden_Lens", M("lenslit" if lit else "lens"), 0.05, 0.075, at=(0, 0, base + post + 0.012), segments=16)
    top = base + post + 0.087
    cylinder(col, "Garden_Cap", M("black"), 0.068, 0.026, at=(0, 0, top), radius_top=0.06, segments=16)
    box(col, "Garden_Cell", M("mono"), (0.06, 0.06, 0.002), at=(0, 0, top + 0.026))


def lying(builder, **options):
    """A builder for the thing on its side, as an item lies on the ground."""
    def build(col):
        before = set(col.objects)
        builder(col, **options)
        group(col, "Lying", [obj for obj in col.objects if obj not in before and obj.parent is None], rotate=(0, 90, 0))
    return build


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
    for i in range(1, cells):
        box(col, name + "_CellWall", M("leadstain"), (0.004, depth - 2 * (wall + stain), height - 0.025),
            at=(-width / 2 + i * width / cells, 0, wall))
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
        for sign in (-1, 1):
            tube(col, name + "_Handle", M("black"), [(sign * width / 2, -depth / 4, height - 0.06),
                                                     (sign * (width / 2 + 0.03), -depth / 5, height - 0.03),
                                                     (sign * (width / 2 + 0.03), depth / 5, height - 0.03),
                                                     (sign * width / 2, depth / 4, height - 0.06)], 0.007)


def car_battery_case(col):
    battery_case(col, "CarCase", (0.26, 0.17, 0.2), "carbattery", 6, "carlabel", bolt=True)


def deep_cycle_battery_case(col):
    battery_case(col, "DeepCycleCase", (0.32, 0.17, 0.23), "marine", 6, "label")


def l16_battery_case(col):
    battery_case(col, "L16Case", L16, "maroon", 3, "label", words="L-16", handles=True)


PLATE = (0.13, 0.12)  # a plate's width and height, without its lug


def battery_plates(col, worn=False):
    """A cell's plates: lead grids standing in a row, the positive and negative ones joined by a
    strap and lug each. Worn plates are buckled and crusted white with sulphate."""
    width, height = PLATE
    count, pitch = 7, 0.014
    rng = random.Random(3)
    for i in range(count):
        plate = [box(col, "Plates_Plate", M("plate"), (width, 0.005, height))]
        for k in range(1, 4):
            plate.append(box(col, "Plates_Rib", M("lead"), (width - 0.01, 0.002, 0.004), at=(0, -0.0035, k * height / 4)))
        if worn:
            for _ in range(3):
                plate.append(box(col, "Plates_Crust", M("sulphate"), (rng.uniform(0.02, 0.06), 0.008, rng.uniform(0.015, 0.04)),
                                 at=(rng.uniform(-0.04, 0.04), 0, rng.uniform(0.01, 0.07)), bevel=0.003))
        group(col, "Plates_Set", plate, at=(0, (i - (count - 1) / 2) * pitch, 0),
              rotate=(rng.uniform(-7, 7) if worn else 0, 0, rng.uniform(-3, 3) if worn else 0))
    span = count * pitch
    for sign in (-1, 1):
        box(col, "Plates_Strap", M("lead"), (0.025, span, 0.012), at=(sign * 0.04, 0, height), bevel=0.003)
        box(col, "Plates_Lug", M("lead"), (0.018, 0.018, 0.03), at=(sign * 0.04, 0, height + 0.012), bevel=0.003)


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


# Vehicles -----------------------------------------------------------------------------------------
#
# A vehicle body is built in the frame of vanilla's vehicle meshes as the game draws them: +Y
# forward (towards the hitch), Z up, the origin where vanilla's utility trailer has its own, so the
# vehicle script's wheel, hitch and physics offsets, copied from that trailer, fit it the same way.
# The ground is TRAILER_GROUND below the origin.

TRAILER_GROUND = -0.45
TRAILER_DECK = (1.16, 1.67)  # width and length
TRAILER_DECK_Y = -0.575  # the deck's centre
TRAILER_AXLE = (-0.56, -0.18)  # y and z of the wheel centres
TRAILER_HITCH_Y = 1.4


def arrow_board_trailer(col):
    """A solar arrow board trailer of the late 1980s, set for the road: a steel deck on one axle in
    highway orange, the lamp board folded down flat over the back on its mast, two modules on a
    frame over the front, and a padlocked battery box on the tongue."""
    width, length = TRAILER_DECK
    front, rear = TRAILER_DECK_Y + length / 2, TRAILER_DECK_Y - length / 2
    axle_y, axle_z = TRAILER_AXLE
    paint = M("safety")
    for sign in (-1, 1):
        box(col, "Trailer_Rail", paint, (0.05, length, 0.13), at=(sign * (width / 2 - 0.025), TRAILER_DECK_Y, -0.13), bevel=0.005)
        box(col, "Trailer_Spring", M("darkgrey"), (0.05, 0.6, 0.04), at=(sign * (width / 2 - 0.025), axle_y, axle_z - 0.02))
        # A fender over each wheel, outside the rails.
        box(col, "Trailer_Fender", M("black"), (0.24, 0.66, 0.025), at=(sign * 0.69, axle_y, 0.12), bevel=0.008)
        for y in (axle_y - 0.32, axle_y + 0.32):
            box(col, "Trailer_FenderSkirt", M("black"), (0.24, 0.025, 0.17), at=(sign * 0.69, y, -0.05))
        box(col, "Trailer_TailLight", M("red"), (0.1, 0.02, 0.05), at=(sign * (width / 2 - 0.08), rear - 0.01, -0.1), bevel=0.005)
        box(col, "Trailer_Reflector", M("amberlamp"), (0.004, 0.06, 0.03), at=(sign * (width / 2 + 0.002), front - 0.1, -0.09))
    for y in (rear + 0.025, axle_y, front - 0.025):
        box(col, "Trailer_CrossMember", paint, (width - 0.1, 0.05, 0.1), at=(0, y, -0.12))
    box(col, "Trailer_Deck", M("rawsteel"), (width, length, 0.012))
    tube(col, "Trailer_Axle", M("darkgrey"), [(-0.62, axle_y, axle_z), (0.62, axle_y, axle_z)], 0.035, 8)
    _trailer_tongue(col, front)
    _trailer_battery_box(col)
    _arrow_board(col, rear)
    _trailer_modules(col, front)


def _trailer_tongue(col, front):
    """The A-frame tongue from the deck's front corners to the coupler, and the jack stand."""
    for sign in (-1, 1):
        beam(col, "Trailer_Tongue", M("safety"), (sign * 0.5, front - 0.05, -0.09), (sign * 0.03, TRAILER_HITCH_Y - 0.1, -0.12),
             (0.06, 0.07), bevel=0.005)
    box(col, "Trailer_Coupler", M("darkgrey"), (0.1, 0.22, 0.08), at=(0, TRAILER_HITCH_Y - 0.12, -0.16), bevel=0.01)
    cylinder(col, "Trailer_CouplerCap", M("darkgrey"), 0.05, 0.08, at=(0, TRAILER_HITCH_Y - 0.02, -0.16), segments=12)
    jack_x, jack_y = 0.33, front + 0.45
    cylinder(col, "Trailer_Jack", M("darkgrey"), 0.03, 0.55, at=(jack_x, jack_y, TRAILER_GROUND), segments=10)
    box(col, "Trailer_JackFoot", M("darkgrey"), (0.12, 0.12, 0.01), at=(jack_x, jack_y, TRAILER_GROUND))
    top = TRAILER_GROUND + 0.55
    tube(col, "Trailer_JackCrank", M("darkgrey"), [(jack_x, jack_y, top), (jack_x + 0.1, jack_y, top), (jack_x + 0.1, jack_y, top + 0.06)],
         0.008)


TRAILER_BOX = (0.72, 0.42, 0.34)  # width, depth and height of the battery box
TRAILER_BOX_AT = (TRAILER_DECK_Y + TRAILER_DECK[1] / 2 + 0.3, -0.05)  # y and z of its bottom centre
# The lid's hinge pins run along X at the back of the box's top, and the lid turns about them. Open
# this far, it clears the panels' undersides by a centimetre and a half; much further and it meets
# them.
TRAILER_LID_HINGE = (0, TRAILER_BOX_AT[0] - TRAILER_BOX[1] / 2 - 0.01, TRAILER_BOX_AT[1] + TRAILER_BOX[2])
TRAILER_LID_OPEN = 70


def _trailer_battery_box(col):
    """The battery box bolted across the tongue: steel with a lid over its rim, a hasp with a
    staple and a padlock, stencilled on the side that faces the towing car. The padlock hangs from
    the staple, which stays on the box with the hasp, so the box looks right with the lock cut."""
    width, depth, height = TRAILER_BOX
    y, z = TRAILER_BOX_AT
    face = y + depth / 2
    box(col, "Trailer_BatteryBox", M("safety"), (width, depth, height), at=(0, y, z), bevel=0.01)
    box(col, "Trailer_BatteryLid", M("safety"), (width + 0.03, depth + 0.03, 0.035), at=(0, y, z + height), bevel=0.008)
    for x in (-0.22, 0.22):
        cylinder(col, "Trailer_BatteryHinge", M("darkgrey"), 0.012, 0.08, at=(x - 0.04, TRAILER_LID_HINGE[1], TRAILER_LID_HINGE[2]),
                 rotate=(0, 90, 0), segments=8)
    box(col, "Trailer_Hasp", M("rawsteel"), (0.04, 0.012, 0.09), at=(0, face + 0.02, z + height - 0.05))
    staple_y = (face + 0.026, face + 0.045)
    tube(col, "Trailer_Staple", M("rawsteel"), [(0, staple_y[0], z + height - 0.032), (0, staple_y[1], z + height - 0.032),
                                                (0, staple_y[1], z + height - 0.048), (0, staple_y[0], z + height - 0.048)], 0.003)
    box(col, "Trailer_Padlock", M("yellow"), (0.05, 0.025, 0.05), at=(0, face + 0.035, z + height - 0.12), bevel=0.006)
    tube(col, "Trailer_PadlockShackle", M("rawsteel"), [(-0.015, face + 0.035, z + height - 0.07), (-0.015, face + 0.035, z + height - 0.04),
                                                        (0.015, face + 0.035, z + height - 0.04), (0.015, face + 0.035, z + height - 0.07)], 0.004)
    text(col, "Trailer_Stencil", M("ink"), "BATTERIES", 0.05, at=(0, face + 0.002, z + 0.1), rotate=(90, 0, 180))


ARROW_BOARD = (1.5, 0.85, 0.09)
# The board's 15 lamps, (across, along) from its centre: a shaft and a head pointing left.
ARROW_LAMPS = ([(x, 0.0) for x in (0.62, 0.47, 0.32, 0.17, 0.02, -0.13, -0.28, -0.43, -0.6)]
               + [(x, sign * y) for x, y in ((-0.46, 0.12), (-0.32, 0.24), (-0.18, 0.34)) for sign in (-1, 1)])


def _arrow_board(col, rear):
    """The lamp board folded down for the road, lamps up, resting on its mast at the back and a
    cradle post ahead of it."""
    width, depth, thick = ARROW_BOARD
    centre_y = rear + 0.08 + depth / 2
    top = 0.62
    bottom = top - thick
    box(col, "Trailer_Mast", M("safety"), (0.09, 0.09, bottom), at=(0, rear + 0.12, 0.012), bevel=0.006)
    cylinder(col, "Trailer_MastPivot", M("darkgrey"), 0.03, 0.14, at=(-0.07, rear + 0.12, bottom - 0.04), rotate=(0, 90, 0), segments=10)
    box(col, "Trailer_Cradle", M("safety"), (0.3, 0.05, bottom), at=(0, centre_y + depth / 2 - 0.1, 0.012), bevel=0.006)
    box(col, "Board_Back", M("black"), (width - 0.06, depth - 0.06, thick), at=(0, centre_y, bottom))
    for sign in (-1, 1):
        box(col, "Board_FrameLong", M("safety"), (width, 0.04, thick + 0.01), at=(0, centre_y + sign * (depth - 0.04) / 2, bottom),
            bevel=0.005)
        box(col, "Board_FrameShort", M("safety"), (0.04, depth - 0.08, thick + 0.01), at=(sign * (width - 0.04) / 2, centre_y, bottom),
            bevel=0.005)
    for x, y in ARROW_LAMPS:
        cylinder(col, "Board_Lamp", M("amberlampdark"), 0.045, 0.015, at=(x, centre_y + y, top), segments=12)
        box(col, "Board_Visor", M("black"), (0.1, 0.012, 0.05), at=(x, centre_y + y + 0.052, top))


# The trailer's panels are vehicle parts the player can take off, each shown whole or cracked by
# its module's condition, so each is a model of its own: TrailerN_ the whole module N (0 on the
# left, at -X), TrailerCrackedN_ the cracked one. The cracked pair is built this far off and moved
# back after baking, because the bake takes each surface's colour from the nearest detail and the
# two pairs would otherwise lie in one place.
TRAILER_CRACKED_OFFSET = (0.0, 0.0, 4.0)


def _trailer_modules(col, front):
    """Two modules side by side, long sides front to back, on rails over the front of the deck and
    the battery box, raised a little at the front, on posts from the deck."""
    tilt, centre_y, height = 10, 0.2, 0.72
    for prefix, cracked, offset in (("Trailer", False, (0, 0, 0)), ("TrailerCracked", True, TRAILER_CRACKED_OFFSET)):
        modules = [group(col, "Trailer_Module", solar_module(col, "%s%d" % (prefix, i), cracked=cracked), at=(x, 0, 0),
                         rotate=(0, 0, 90))
                   for i, x in enumerate((-0.235, 0.235))]
        group(col, "Trailer_Panels", modules, at=(offset[0], centre_y + offset[1], height + offset[2]), rotate=(tilt, 0, 0))
    rails = [box(col, "Trailer_PanelRail", M("galvanised"), (0.04, MODULE[0] + 0.04, 0.04), at=(x, 0, -0.04)) for x in (-0.4, 0.4)]
    group(col, "Trailer_Rails", rails, at=(0, centre_y, height), rotate=(tilt, 0, 0))
    rise = math.sin(math.radians(tilt))
    for x in (-0.4, 0.4):
        for y in (-0.25, front - 0.04):
            beam(col, "Trailer_PanelPost", M("galvanised"), (x, y, 0.012), (x, y, height - 0.04 + (y - centre_y) * rise), (0.04, 0.04))


# Inventory items ----------------------------------------------------------------------------------

# Item type -> builder of its ground model, of its icon when that shows more, the icon's camera
# elevation in degrees when the 30 of a tile would show a flat thing edge on, and the ground
# model's scale in Models.txt when it isn't models.WORLD_SCALE.
#
# The game draws its car battery at 0.19 x 0.13 x 0.14 m, about three quarters of a real one's
# 0.26 x 0.17 x 0.20, so a battery built true to life lies on the ground half again as big as the
# car battery beside it. The batteries, their cases and the plates and molds sized to fit them
# shrink by as much; the parts stay real size for the icons and the battery storage tiles.
BATTERY_GROUND_SCALE = 0.75
ITEMS = {
    "SolarModule": {"model": solar_module, "icon_elevation": 55},
    "HomemadeSolarModule": {"model": homemade_module, "icon_elevation": 55},
    "SolarCells": {"model": solar_cells, "icon_elevation": 60},
    "SolarFlat": {"model": solar_flat, "icon_elevation": 25},
    "SolarWallWood": {"model": lambda col: solar_wall(col, "wood", lying=True), "icon": lambda col: solar_wall(col, "wood")},
    "SolarWallMetal": {"model": lambda col: solar_wall(col, "metal", lying=True), "icon": lambda col: solar_wall(col, "metal")},
    "SolarRackWood": {"model": lambda col: solar_rack(col, "wood")},
    "SolarRackMetal": {"model": lambda col: solar_rack(col, "metal")},
    "BatteryBoxWood": {"model": STORAGE["BatteryBoxWood"],
                       "icon": lambda col: STORAGE["BatteryBoxWood"](col, batteries=2, meter_level=4)},
    "BatteryBoxMetal": {"model": STORAGE["BatteryBoxMetal"],
                        "icon": lambda col: STORAGE["BatteryBoxMetal"](col, batteries=2, meter_level=4)},
    "BatteryRackWood": {"model": STORAGE["BatteryRackWood"],
                        "icon": lambda col: STORAGE["BatteryRackWood"](col, batteries=6, meter_level=4)},
    "BatteryRackMetal": {"model": STORAGE["BatteryRackMetal"],
                         "icon": lambda col: STORAGE["BatteryRackMetal"](col, batteries=8, meter_level=4)},
    "BatteryBankWood": {"model": STORAGE["BatteryBankWood"],
                        "icon": lambda col: STORAGE["BatteryBankWood"](col, batteries=8, meter_level=4)},
    "BatteryBankMetal": {"model": STORAGE["BatteryBankMetal"],
                         "icon": lambda col: STORAGE["BatteryBankMetal"](col, batteries=12, meter_level=4)},
    "PlugInInverter": {"model": plug_in_inverter},
    "PowerInverter": {"model": power_inverter},
    "InverterCharger": {"model": inverter_charger},
    "ChargeController": {"model": charge_controller},
    "SolarFailsafe": {"model": solar_failsafe, "icon": lambda col: solar_failsafe(col, cable=False)},
    "DeepCycleBattery": {"model": deep_cycle_battery, "ground_scale": BATTERY_GROUND_SCALE},
    "L16Battery": {"model": l16_battery, "ground_scale": BATTERY_GROUND_SCALE},
    "SolarMaintainer": {"model": solar_maintainer, "icon_elevation": 40},
    "SolarCellCharger": {"model": solar_cell_charger, "icon_elevation": 45},
    "SolarGardenLight": {"model": lying(solar_garden_light), "icon": solar_garden_light},
    "CarBatteryCase": {"model": car_battery_case, "icon_elevation": 40, "ground_scale": BATTERY_GROUND_SCALE},
    "DeepCycleBatteryCase": {"model": deep_cycle_battery_case, "icon_elevation": 40, "ground_scale": BATTERY_GROUND_SCALE},
    "L16BatteryCase": {"model": l16_battery_case, "icon_elevation": 40, "ground_scale": BATTERY_GROUND_SCALE},
    "WornBatteryPlates": {"model": lambda col: battery_plates(col, worn=True), "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryPlates": {"model": battery_plates, "ground_scale": BATTERY_GROUND_SCALE},
    "WoodenBatteryPlatePattern": {"model": plate_pattern, "icon_elevation": 55, "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryPlateMoldUnfired": {"model": plate_mold, "icon_elevation": 50, "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryPlateMold": {"model": lambda col: plate_mold(col, fired=True), "icon_elevation": 50,
                         "ground_scale": BATTERY_GROUND_SCALE},
    "BatteryElectrolyte": {"model": battery_electrolyte},
    "HomesteadPowerMag1": {"model": magazine_1, "icon_elevation": 70},
    "HomesteadPowerMag2": {"model": magazine_2, "icon_elevation": 70},
}

# Vehicle -> builder of its body, and the part models cut out of it: model suffix -> (the prefixes
# of the parts it takes, and how far they were built from where they belong). Every piece shares
# the body's texture and mask, and the body keeps whatever no piece takes. A piece in "hinged" turns
# about a hinge in the game: it gets a bone there and one clip, named for the vehicle script's anim
# blocks, that swings it from open, `open` degrees about `axis` by the right-hand rule, to shut.
VEHICLES = {
    "ArrowBoardTrailer": {
        "build": arrow_board_trailer,
        "pieces": {
            "_Lid": (("Trailer_BatteryLid",), (0, 0, 0)),
            "_Padlock": (("Trailer_Padlock",), (0, 0, 0)),
            "_PanelLeft": (("Trailer0_",), (0, 0, 0)),
            "_PanelRight": (("Trailer1_",), (0, 0, 0)),
            "_PanelLeftCracked": (("TrailerCracked0_",), TRAILER_CRACKED_OFFSET),
            "_PanelRightCracked": (("TrailerCracked1_",), TRAILER_CRACKED_OFFSET),
        },
        "hinged": {
            "_Lid": {"pivot": TRAILER_LID_HINGE, "axis": (1, 0, 0), "open": TRAILER_LID_OPEN, "clip": "Lid_closing"},
        },
    },
}
