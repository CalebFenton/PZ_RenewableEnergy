"""Solar modules and their mounts, the crate they ship in, homemade modules, loose cells and the
garden light."""
import math
import random

from kit import beam, box, cylinder, group, text, tube
from palette import M

# Solar modules ------------------------------------------------------------------------------------

# A 51 W multicrystalline module of the early nineties (Kyocera's K51 is 986 x 446 mm): 36 cells in
# four strings of nine, on a white backsheet, in a clear anodised frame.
MODULE = (0.986, 0.446, 0.036)
FRAME = 0.028


# A module's cover glass shows whole, lightly cracked or heavily cracked by its condition
# (RenewableEnergy.crackLookOf), drawn by module_cracks everywhere it shows: on the mounts' crack
# overlay tiles and on the arrow board trailer's cracked panels. Lines wide enough to read at a
# tile's scale, about a centimetre a pixel.
CRACK_WIDTH = 0.01


def module_cracks(col, name, light=False):
    """The cracks of a broken cover glass, lying on a module built by solar_module: lines
    radiating from where something struck it, and a broken ring round the strike. `light` draws
    the first cracks of a glass that took a knock: a few short lines from a strike near a corner,
    no ring, so the two looks tell apart at a glance."""
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

    if light:
        strike, rays, steps, reaches = (-0.2, 0.06), 3, 2, (0.12, 0.26)
    else:
        rays, steps, reaches = 9, 3, (0.18, 0.5)
    for i in range(rays):
        heading = 2 * math.pi * i / rays + rng.uniform(-0.3, 0.3)
        reach = rng.uniform(*reaches)
        point = strike
        for _ in range(steps):
            heading += rng.uniform(-0.35, 0.35)
            x = max(-inner_w, min(inner_w, point[0] + reach / steps * math.cos(heading)))
            y = max(-inner_d, min(inner_d, point[1] + reach / steps * math.sin(heading)))
            segment(point, (x, y))
            point = (x, y)
    if light:
        return parts
    ring = 0.07
    for i in range(8):
        if i % 3 == 2:
            continue
        a0, a1 = 2 * math.pi * i / 8, 2 * math.pi * (i + 1) / 8
        segment((strike[0] + ring * math.cos(a0), strike[1] + ring * math.sin(a0)),
                (strike[0] + ring * math.cos(a1), strike[1] + ring * math.sin(a1)))
    return parts


def solar_module(col, name="Module", snow=False, cracked=False, cracks=False, light_cracks=False):
    """A module lying glass up. `snow` adds only the snow lying on it and `cracks` only the cracks
    of a broken glass, for overlay tiles; `cracked` draws the whole module with those cracks.
    `light_cracks` makes either the light cracks rather than the heavy ones."""
    if cracks:
        return module_cracks(col, name, light=light_cracks)
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
        parts += module_cracks(col, name, light=light_cracks)
    return parts


def solar_flat(col, snow=False, cracks=False, light_cracks=False):
    """One module on two low rails, for a roof or the ground at 0 degrees. `snow` and `cracks` give
    only the snow on it or the cracks in its glass, for overlay tiles; `light_cracks` the light ones."""
    module = solar_module(col, "Flat", snow=snow, cracks=cracks, light_cracks=light_cracks)
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


def solar_wall(col, material="metal", lying=False, cracks=False, light_cracks=False):
    """One module upright, its back WALL_STANDOFF in front of y = 0 (the wall), its bottom edge at
    z = 0: on two galvanised channel brackets lagged to the wall, or on two pine battens with a
    ledger board under it and cleats nailed over its top edge. `lying` lays it glass up on its
    brackets, as it lies on the ground. `cracks` gives only the cracks in its glass, `light_cracks`
    the light ones."""
    # Turning +90 degrees about X takes glass up to glass to the front (-Y).
    module = group(col, "Wall_Module", solar_module(col, "Wall", cracks=cracks, light_cracks=light_cracks),
                   at=(0, -WALL_STANDOFF, MODULE[1] / 2),
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


def solar_rack(col, material="metal", snow=False, cracks=None, light_cracks=False):
    """Two modules, one above the other, tilted RACK_TILT degrees to the front on a galvanised pipe
    frame or a frame of pine 2 x 4s on skids. Both hold the modules in the same place, so the
    snow on them is the same. `cracks`, a module slot (1 the lower module, 2 the upper), gives only
    the cracks in that module's glass, `light_cracks` the light ones."""
    tilt = math.radians(RACK_TILT)
    gap = 0.01
    span = 2 * MODULE[1] + gap
    panels = []
    for i, offset in enumerate((-(MODULE[1] + gap) / 2, (MODULE[1] + gap) / 2)):
        if cracks and cracks != i + 1:
            continue
        module = solar_module(col, "Rack%d" % i, snow=snow, cracks=bool(cracks), light_cracks=light_cracks)
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


# The crate ----------------------------------------------------------------------------------------

CRATE = (0.99, 0.5, 0.3)


def solar_crate(col, frame=True, contents=False, closed=False):
    """The cardboard carton solar modules ship in: open, its flaps folded down the outside, with
    modules inside (`contents`) or its top flaps taped shut (`closed`). `frame` is the carton."""
    width, depth, height = CRATE
    wall = 0.006
    if frame:
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
    post = 0.26
    if stake:
        cylinder(col, "Garden_Stake", M("black"), 0.003, base, radius_top=0.016, segments=8)
    cylinder(col, "Garden_Post", M("black"), 0.014, post, at=(0, 0, base), segments=10)
    cylinder(col, "Garden_Collar", M("black"), 0.056, 0.012, at=(0, 0, base + post), segments=16)
    cylinder(col, "Garden_Lens", M("lenslit" if lit else "lens"), 0.05, 0.075, at=(0, 0, base + post + 0.012), segments=16)
    top = base + post + 0.087
    cylinder(col, "Garden_Cap", M("black"), 0.068, 0.026, at=(0, 0, top), radius_top=0.06, segments=16)
    box(col, "Garden_Cell", M("mono"), (0.06, 0.06, 0.002), at=(0, 0, top + 0.026))
