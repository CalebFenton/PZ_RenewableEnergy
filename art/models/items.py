"""The parts of every model, in real-world sizes of 1993 hardware.

Each builder adds one thing's parts to a collection, standing on z = 0, centred, front to -Y (see
kit.py). ITEMS lists what each inventory item's ground model and icon are made of; tiles.py places
the same builders on tiles. A builder takes keyword options, so a tile can draw a battery rack
without its batteries and an overlay just the batteries.
"""
import math
import random

from kit import beam, box, cylinder, group, lathe, loft, material, mound, prism, text, tube

# Palette ------------------------------------------------------------------------------------------


def M(name):
    """The shared materials, made on first use."""
    return {
        "aluminium": lambda: material("RE_Aluminium", "#a9adb1", roughness=0.5, metallic=0.8, grime=0.08),
        "galvanised": lambda: material("RE_Galvanised", "#b4babc", roughness=0.5, metallic=0.7, grime=0.2),
        # The game's metal pipe, a dull grey as its icon draws it.
        "metalpipe": lambda: material("RE_MetalPipe", "#7f8487", roughness=0.6, metallic=0.5, grime=0.3, scale=12),
        # Cell faces and their busbars under glass, rough enough that the sun, whose mirror image off
        # a module tilted south at a rack's angle falls on the camera, doesn't white them out.
        "cells": lambda: material("RE_PolyCells", "#142c63", roughness=0.75, metallic=0.2, grime=0.05,
                                  speckle=("#3a60a8", 0.9)),
        "backsheet": lambda: material("RE_Backsheet", "#e9e8df", roughness=0.5, grime=0.05),
        "busbar": lambda: material("RE_Busbar", "#aeb2b6", roughness=0.7, metallic=0.6, grime=0.0),
        "amorphous": lambda: material("RE_Amorphous", "#2c3a78", roughness=0.75, metallic=0.25, grime=0.05),
        "mono": lambda: material("RE_MonoCells", "#222838", roughness=0.75, metallic=0.3, grime=0.04),
        # Broken cover glass: the fractures catch the light and read pale over the cells.
        "crack": lambda: material("RE_Crack", "#dfe7ee", roughness=0.3, grime=0.0),
        # Black and dark grey plastic as light as the game's own black radios and speakers, which it
        # still draws as black: darker, and a shaded face loses all its detail.
        "black": lambda: material("RE_BlackPlastic", "#393a3d", roughness=0.55, grime=0.15),
        "darkgrey": lambda: material("RE_DarkGrey", "#4e5156", roughness=0.5, grime=0.15),
        "grey": lambda: material("RE_GreyPaint", "#8b9089", roughness=0.55, grime=0.2),
        "battery": lambda: material("RE_BatteryCase", "#3a3a3d", roughness=0.6, grime=0.15),
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
        "lead": lambda: material("RE_Lead", "#bbbdb9", roughness=0.45, metallic=0.8, grime=0.15),
        "red": lambda: material("RE_Red", "#b8231f", roughness=0.5, grime=0.1),
        "plywood": lambda: material("RE_Plywood", "#b48d5c", roughness=0.8, grime=0.25, scale=12, grain="veneer"),
        "wood": lambda: material("RE_Wood", "#94693f", roughness=0.8, grime=0.3, scale=10, grain="board"),
        "navy": lambda: material("RE_Navy", "#2c416d", roughness=0.4, metallic=0.4, grime=0.1),
        # The inverter/charger's cabinet, and the factory paint on a battery bank's steel.
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
        "magazine3": lambda: material("RE_Mag3", "#4f7d32", roughness=0.4, grime=0.05),
        "magazine4": lambda: material("RE_Mag4", "#8c3b2e", roughness=0.4, grime=0.05),
        "sky": lambda: material("RE_Sky", "#8fc4e8", roughness=0.4, grime=0.05),
        "sun": lambda: material("RE_Sun", "#ffd640", roughness=0.4, grime=0.0),
        # Pine boards and 2 x 4s, two shades so neighbouring boards read apart, and the same pine
        # in strips too narrow for a board's grain, as a tray's sides.
        "pine": lambda: material("RE_Pine", "#c39b62", roughness=0.8, grime=0.2, scale=9, grain="board"),
        "pinedark": lambda: material("RE_PineDark", "#9a7041", roughness=0.8, grime=0.2, scale=9, grain="board"),
        "pinestrip": lambda: material("RE_PineStrip", "#c39b62", roughness=0.8, grime=0.2, scale=9, grain="fine"),
        "pinestripdark": lambda: material("RE_PineStripDark", "#9a7041", roughness=0.8, grime=0.2, scale=9, grain="fine"),
        # Bare mild steel, as pale as the game's own sheet metal, with darker weld beads at its joints.
        # Rusty steel, flecked brown, is scrap welded up at home. Worn steel is bare steel rubbed
        # bright, or showing through chipped paint.
        "rawsteel": lambda: material("RE_RawSteel", "#a9afb3", roughness=0.5, metallic=0.6, grime=0.35),
        "rustysteel": lambda: material("RE_RustySteel", "#a9afb3", roughness=0.6, metallic=0.5, grime=0.35, scale=6,
                                       speckle=("#93602f", 0.45)),
        "worn": lambda: material("RE_WornSteel", "#d3d7da", roughness=0.35, metallic=0.8, grime=0.05),
        "weld": lambda: material("RE_Weld", "#3f3c39", roughness=0.75, metallic=0.5, grime=0.3),
        "rust": lambda: material("RE_Rust", "#7b4a2c", roughness=0.9, grime=0.3, scale=30),
        "copper": lambda: material("RE_Copper", "#c27a3e", roughness=0.35, metallic=0.85, grime=0.1),
        "lens": lambda: material("RE_Lens", "#e6e2d4", roughness=0.25, grime=0.05),
        "lenslit": lambda: material("RE_LensLit", "#ffd28a", roughness=0.25, grime=0.0, emission="#ffc46a"),
        "clay": lambda: material("RE_Clay", "#8e8172", roughness=0.9, grime=0.2, scale=16),
        "terracotta": lambda: material("RE_Terracotta", "#b2603b", roughness=0.85, grime=0.25, scale=16),
        "hdpe": lambda: material("RE_Hdpe", "#e8e4d8", roughness=0.5, grime=0.1),
        # A jar's green-tinged glass, opaque as the game draws its own jars, pale streaks running up
        # it where it catches the light; below the acid line, the glass darkened by the acid behind it.
        "jarglass": lambda: material("RE_JarGlass", "#a6c4b9", roughness=0.12, grime=0.06, scale=20, streaks=("#e4f2ec", 0.7)),
        "jaracid": lambda: material("RE_JarAcid", "#6b877d", roughness=0.12, grime=0.08, scale=20, streaks=("#a9c4ba", 0.6)),
        # Pale tan twine.
        "twine": lambda: material("RE_Twine", "#c8b07a", roughness=0.9, grime=0.15, scale=40),
        "sand": lambda: material("RE_Sand", "#c9b48a", roughness=0.95, grime=0.2, scale=60, speckle=("#a48f64", 0.4)),
        "sulphate": lambda: material("RE_Sulphate", "#dcd9cb", roughness=0.95, grime=0.15, scale=60),
        # A plate's paste is dull grey lead in a grid of brighter cast lead. Worn out, it is black
        # with dirt but for patches of bare grey, crusted white with sulphate and blue-green where
        # the acid ate at it. The game draws a side face much darker than its colour (a mid grey at
        # about a third of its brightness), so the greys are pale to read as lead.
        "plate": lambda: material("RE_Plate", "#9a9fa4", roughness=0.8, grime=0.2),
        "plateworn": lambda: material("RE_PlateWorn", "#4a4b4e", roughness=0.85, grime=0.4, scale=30),
        "corrosion": lambda: material("RE_Corrosion", "#7fc0ae", roughness=0.95, grime=0.2, scale=60),
        # Highway work-zone orange, the amber of its reflectors, and the board's lamps while they're
        # dark: lit, the vehicle's lights texture draws them bright (models.GLOWING).
        "safety": lambda: material("RE_SafetyOrange", "#e0661a", roughness=0.5, grime=0.25),
        "amberlamp": lambda: material("RE_AmberLamp", "#f5a623", roughness=0.3, grime=0.05),
        "amberlampdark": lambda: material("RE_AmberLampDark", "#6e4510", roughness=0.3, grime=0.05),
        # Biogas digesters. The garbage bags are glossy, so their folds and bulge catch the light
        # that a black as dark as the game's own would lose. The drums are the game's own four, as
        # its sprites paint them (crafted_01_32, industry_01_22, location_military_generic_01_14 and
        # _6): dull, weathered steel, rust and grime run down their sides by the rain.
        "drummetal": lambda: material("RE_DrumMetal", "#76776f", roughness=0.7, metallic=0.25, grime=0.4, scale=8,
                                      speckle=("#7a5434", 0.12), streaks=("#4c4136", 0.55)),
        "drumorange": lambda: material("RE_DrumOrange", "#a2683d", roughness=0.75, metallic=0.15, grime=0.4, scale=8,
                                       speckle=("#6e4a32", 0.3), streaks=("#5a3f2c", 0.6)),
        "drumgreen": lambda: material("RE_DrumGreen", "#4d5d46", roughness=0.75, metallic=0.15, grime=0.35, scale=8,
                                      speckle=("#6b5034", 0.15), streaks=("#2f362b", 0.5)),
        "drumolive": lambda: material("RE_DrumOlive", "#77714f", roughness=0.75, metallic=0.15, grime=0.35, scale=8,
                                      speckle=("#6b5034", 0.15), streaks=("#4a4433", 0.5)),
        "ducttape": lambda: material("RE_DuctTape", "#a7aaab", roughness=0.35, metallic=0.3, grime=0.1),
        "garbagebag": lambda: material("RE_GarbageBag", "#45484d", roughness=0.25, grime=0.08),
        # The game's own tarp, rubber hose, funnel and plastic pipe, as its icons draw them: tan
        # canvas, tan rubber, a yellow funnel and grey pipe, a light grey, which the game draws
        # darker on a model.
        "tarp": lambda: material("RE_Tarp", "#c09347", roughness=0.85, grime=0.3, scale=14),
        "rubberhose": lambda: material("RE_RubberHose", "#8c7a50", roughness=0.7, grime=0.25),
        "funnel": lambda: material("RE_Funnel", "#c9b234", roughness=0.45, grime=0.15),
        "pvc": lambda: material("RE_Pvc", "#a4a6a8", roughness=0.45, grime=0.2),
        # Old straw, gone dull and dusty, flecked with darker stalks.
        "straw": lambda: material("RE_Straw", "#bfa862", roughness=0.9, grime=0.3, scale=60, speckle=("#8a7234", 0.6)),
        # Planks nailed up outdoors, grey-brown and deeply grained by the rain as the game's own
        # composters and crates are, two shades so neighbouring boards read apart.
        "planks": lambda: material("RE_Planks", "#946a44", roughness=0.85, grime=0.35, scale=10, grain="weathered"),
        "planksdark": lambda: material("RE_PlanksDark", "#77553a", roughness=0.85, grime=0.35, scale=10, grain="weathered"),
        "nail": lambda: material("RE_Nail", "#3b3936", roughness=0.6, metallic=0.5, grime=0.2),
        # The game's round bin, a plain steel can painted near black, and its galvanised bucket.
        "roundbin": lambda: material("RE_RoundBin", "#3a352f", roughness=0.7, metallic=0.2, grime=0.35, scale=8,
                                     streaks=("#5b4a3a", 0.4)),
        "bucket": lambda: material("RE_Bucket", "#8e9091", roughness=0.55, metallic=0.5, grime=0.35, scale=10,
                                   streaks=("#5d5a55", 0.4)),
        # The stove black a welded body is painted with, rusting where the rain runs down it. A body
        # with a fire in it is sooted from its foot up to a ragged line and tinted brown by the heat
        # above that.
        "stoveblack": lambda: material("RE_StoveBlack", "#45443f", roughness=0.75, metallic=0.2, grime=0.35, scale=8,
                                       streaks=("#6b4a30", 0.45)),
        "stovescorched": lambda: material("RE_StoveScorched", "#45443f", roughness=0.75, metallic=0.2, grime=0.35, scale=8,
                                          streaks=("#6b4a30", 0.45), scorch=("#262320", "#7a4b2a", 0.28)),
        "drumscorched": lambda: material("RE_DrumScorched", "#76776f", roughness=0.7, metallic=0.25, grime=0.4, scale=8,
                                         speckle=("#7a5434", 0.12), streaks=("#4c4136", 0.55), scorch=("#2a2622", "#7b5232", 0.34)),
        "potscorched": lambda: material("RE_PotScorched", "#8d9396", roughness=0.5, metallic=0.6, grime=0.3, scale=10,
                                        scorch=("#2a2622", "#6e5a48", 0.14)),
        "earth": lambda: material("RE_Earth", "#6e5b43", roughness=1.0, grime=0.3, scale=20, speckle=("#54462f", 0.35)),
        # The earth banked round the brick dome: dug soil, grassed over towards its foot, where it
        # thins into whatever ground the game draws round the square, the olive of its grass.
        "domebank": lambda: material("RE_DomeBank", "#6e5b43", roughness=1.0, grime=0.45, scale=10, speckle=("#43420a", 0.5),
                                     turf=("#625f09", BANK_TURF[0], BANK_TURF[1]), fade=BANK_FADE, shine=0.05),
        # Blades of grass, green and gone to seed.
        "grass": lambda: material("RE_Grass", "#414b10", roughness=0.9, grime=0.3, scale=20, shine=0.1),
        "grassdry": lambda: material("RE_GrassDry", "#6f6828", roughness=0.9, grime=0.3, scale=20, shine=0.1),
        "brick": lambda: material("RE_Brick", "#a5503a", roughness=0.85, grime=0.2, scale=30),
        "brickdark": lambda: material("RE_BrickDark", "#86412d", roughness=0.85, grime=0.2, scale=30),
        "mortar": lambda: material("RE_Mortar", "#b0aa9c", roughness=0.95, grime=0.2, scale=30),
        "concrete": lambda: material("RE_Concrete", "#a9a69d", roughness=0.9, grime=0.3, scale=20),
        "sludge": lambda: material("RE_Sludge", "#4f4330", roughness=0.5, grime=0.2, scale=20),
        "ash": lambda: material("RE_Ash", "#a3a09a", roughness=1.0, grime=0.3, scale=6, speckle=("#75726c", 0.5)),
        # Ash fines settled round a heap's foot, and the white of ash burnt clean.
        "ashdark": lambda: material("RE_AshDark", "#7d7a74", roughness=1.0, grime=0.3, scale=6, speckle=("#5e5b56", 0.5)),
        "ashwhite": lambda: material("RE_AshWhite", "#e0ded8", roughness=1.0, grime=0.1),
        "charcoal": lambda: material("RE_Charcoal", "#36312d", roughness=0.8, grime=0.1),
        "brass": lambda: material("RE_Brass", "#c8a24c", roughness=0.35, metallic=0.85, grime=0.15),
        # A gas flame: yellow-orange where it licks the steel, blue at the burner.
        "flame": lambda: material("RE_Flame", "#ff9a3c", roughness=0.3, grime=0.0, emission="#ff8a2a"),
        "flameblue": lambda: material("RE_FlameBlue", "#5a8cff", roughness=0.3, grime=0.0, emission="#4a7dff"),
        # Wood tar: black-brown and wet, so it shines; the straw it soaks stays a shade lighter.
        "tar": lambda: material("RE_Tar", "#3d2c1e", roughness=0.25, grime=0.25, scale=20, speckle=("#1f1712", 0.4)),
        "tarstraw": lambda: material("RE_TarStraw", "#7a5a2e", roughness=0.6, grime=0.3),
        # Blades: carved from the game's planks and oiled; and hammered out of sheet steel at the
        # forge, left bare, pocked by the hammer and rusting at the edges, the amber casting resin a
        # homemade alternator's coils are set in.
        "carvedwood": lambda: material("RE_CarvedWood", "#a2703f", roughness=0.6, grime=0.25, scale=10, grain="fine"),
        "hammered": lambda: material("RE_Hammered", "#9a9c9b", roughness=0.5, metallic=0.6, grime=0.3, scale=30,
                                     speckle=("#55595b", 0.35), streaks=("#7a5434", 0.35)),
        "resin": lambda: material("RE_Resin", "#c99a4a", roughness=0.35, grime=0.15),
        # The flat belt a car alternator wind charger's rotor drives its alternator with, cut from
        # leather the brown of the game's own leather belt (Belt2).
        "leather": lambda: material("RE_Leather", "#6e4a2c", roughness=0.7, grime=0.2, scale=14),
    }[name]()


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
    loop = [(*_around((cx, cy), start + 15 * k, radius + 0.003), lash) for cx, cy, start in corners for k in range(7)]
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
        before = set(col.objects)
        bank_battery(col, battery_name, look)
        for obj in set(col.objects) - before:
            obj.location.x += x
            obj.location.z += z
        if i > 0 and slots[i - 1][1] == z:
            last_x = slots[i - 1][0]
            tube(col, battery_name + "_Link", M("red" if i % 2 else "black"),
                 [(last_x + post_x, post_y, z + 0.26), ((last_x + x) / 2, post_y - 0.01, z + 0.265),
                  (x - post_x, post_y, z + 0.26)], 0.006)


BOX = (0.5, 0.36, 0.22)
BOARD = 0.019  # a pine 1 x 6's thickness
SHEET = 0.004


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
    "BatteryBoxWood": lambda col, **options: battery_box(col, "wood", **options),
    "BatteryBoxMetal": lambda col, **options: battery_box(col, "metal", **options),
    "BatteryRackWood": lambda col, **options: battery_shelving(col, RACK_WOOD, "wood", **options),
    "BatteryRackMetal": lambda col, **options: battery_shelving(col, RACK_METAL, "metal", **options),
    "BatteryBankWood": lambda col, **options: battery_shelving(col, BANK_WOOD, "wood", **options),
    "BatteryBankMetal": lambda col, **options: battery_shelving(col, BANK_METAL, "metal", **options),
}


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
    for sign in (-1, 1):
        tube(col, "InvChg_Handle", M("darkgrey"), [(sign * (width / 2), -0.06, 0.16), (sign * (width / 2 + 0.035), -0.05, 0.16),
                                                    (sign * (width / 2 + 0.035), 0.05, 0.16), (sign * (width / 2), 0.06, 0.16)], 0.008)
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


# Each issue's cover colour, whether its title is printed dark, and the line under its picture.
MAGAZINE_ISSUES = {1: ("magazine1", True, "SUN & BATTERIES"), 2: ("magazine2", False, "INVERTERS & CONTROL"),
                   3: ("magazine3", False, "BIOGAS FROM MANURE"), 4: ("magazine4", False, "WIND & TREADMILL POWER")}


def magazine(col, issue):
    """Homestead Power, a fictional 1990s homesteading magazine: issue 1 on sun and batteries,
    issue 2 on inverters and control, issue 3 on biogas from the farm's manure, issue 4 on wind
    chargers and the treadmill."""
    width, depth, height = MAGAZINE
    cover, dark_title, line = MAGAZINE_ISSUES[issue]
    title = M("ink" if dark_title else "white")
    box(col, "Mag%d_Pages" % issue, M("white"), (width - 0.004, depth - 0.004, height - 0.001))
    box(col, "Mag%d_Cover" % issue, M(cover), (width, depth, 0.001), at=(0, 0, height - 0.001))
    top = height + 0.0003
    flat = (0, 0, 0)
    text(col, "Mag%d_Title" % issue, title, "HOMESTEAD", 0.03, at=(0, 0.09, top), rotate=flat)
    text(col, "Mag%d_Title2" % issue, title, "POWER", 0.036, at=(0, 0.052, top), rotate=flat)
    text(col, "Mag%d_Issue" % issue, M("red"), "#%d" % issue, 0.03, at=(0.075, 0.105, top), rotate=flat)
    box(col, "Mag%d_Picture" % issue, M("sky"), (0.17, 0.13, 0.0004), at=(0, -0.04, height))
    if issue == 1:
        cylinder(col, "Mag1_Sun", M("sun"), 0.025, 0.0006, at=(-0.045, -0.0, height + 0.0002), segments=16)
        box(col, "Mag1_Panel", M("cells"), (0.09, 0.05, 0.0008), at=(0.025, -0.065, height + 0.0002), rotate=(0, 0, -8))
        box(col, "Mag1_Battery", M("marine"), (0.04, 0.025, 0.0009), at=(-0.05, -0.085, height + 0.0002))
    elif issue == 2:
        box(col, "Mag2_Inverter", M("bluegrey"), (0.08, 0.05, 0.0008), at=(-0.02, -0.05, height + 0.0002))
        box(col, "Mag2_Panel", M("black"), (0.04, 0.03, 0.0009), at=(-0.03, -0.05, height + 0.0003))
        prism(col, "Mag2_Bolt", M("sun"), [(0, 0.05), (0.02, 0.0), (0.008, 0.0), (0.016, -0.04), (-0.006, 0.01), (0.006, 0.01)],
              0.0008, at=(0.055, -0.04, height + 0.0002), rotate=(90, 0, 0))
    elif issue == 3:
        # A brick dome in the farmyard's mud, a cow beside it, and the blue flame its gas burns with.
        box(col, "Mag3_Ground", M("earth"), (0.17, 0.045, 0.0008), at=(0, -0.0825, height + 0.0002))
        prism(col, "Mag3_Dome", M("brick"), [(-0.04, 0), (0.04, 0), (0.03, 0.025), (0.0, 0.035), (-0.03, 0.025)], 0.0008,
              at=(-0.03, -0.06, height + 0.0003), rotate=(-90, 0, 0))
        box(col, "Mag3_Cow", M("white"), (0.04, 0.022, 0.0009), at=(0.045, -0.05, height + 0.0003))
        for x in (0.03, 0.06):
            box(col, "Mag3_CowSpot", M("ink"), (0.01, 0.008, 0.001), at=(x, -0.045, height + 0.0003))
        prism(col, "Mag3_Flame", M("flameblue"), [(-0.01, 0), (0.01, 0), (0.0, 0.03)], 0.0008, at=(0.05, -0.005, height + 0.0003),
              rotate=(-90, 0, 0))
    else:
        # A treadmill wind charger on its mast over a red barn, and a treadmill in the yard.
        box(col, "Mag4_Ground", M("earth"), (0.17, 0.035, 0.0008), at=(0, -0.0875, height + 0.0002))
        prism(col, "Mag4_Barn", M("red"), [(-0.03, 0), (0.03, 0), (0.03, 0.03), (0.0, 0.048), (-0.03, 0.03)], 0.0008,
              at=(-0.045, -0.07, height + 0.0003), rotate=(-90, 0, 0))
        hub = (0.035, -0.005)
        box(col, "Mag4_Mast", M("ink"), (0.003, 0.065, 0.0009), at=(hub[0], hub[1] - 0.0325, height + 0.0003))
        for k in range(3):
            angle = 120 * k + 15
            x, y = _around(hub, angle + 90, 0.0125)
            box(col, "Mag4_Blade", M("white"), (0.004, 0.025, 0.001), at=(x, y, height + 0.0003), rotate=(0, 0, angle))
        box(col, "Mag4_Treadmill", M("black"), (0.035, 0.012, 0.001), at=(0.06, -0.08, height + 0.0003))
        box(col, "Mag4_TreadmillRail", M("black"), (0.003, 0.018, 0.001), at=(0.077, -0.07, height + 0.0003))
    text(col, "Mag%d_Line" % issue, M("white"), line, 0.015, at=(0, -0.122, top), rotate=flat)


def magazine_1(col):
    magazine(col, 1)


def magazine_2(col):
    magazine(col, 2)


def magazine_3(col):
    magazine(col, 3)


def magazine_4(col):
    magazine(col, 4)


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
    post = 0.26
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


# Biogas digesters ---------------------------------------------------------------------------------
#
# A digester is built where it stands and never carried, so each is laid out on its square about the
# square's centre, not its own. Its gas holder shows on overlay tiles: a builder takes `frame` (the
# digester itself) and the holder's state, so a tile can draw the digester alone and an overlay
# just the holder.

DRUM = (0.29, 0.88)  # a 55 gallon drum's radius and height
# The barrel stands in the west corner of its square and its holder in the east, side by side as the
# viewer sees them.
BARREL_AT = (-0.21, -0.21)
# The bungs in its head, from its centre, and the side its sludge spigot faces, in degrees from east.
FEED_BUNG = (-0.1, -0.06)
GAS_BUNG = (0.1, 0.12)
SPIGOT_ANGLE = -40
# Where the gas hose comes down off the barrel's head to the holder on the ground.
HOLDER_INLET = (0.06, 0.06)


def _around(centre, angle, distance):
    a = math.radians(angle)
    return centre[0] + math.cos(a) * distance, centre[1] + math.sin(a) * distance


def _ring(col, name, mat, centre, radius, z, thickness):
    """A rolled rim round a drum's head: a solid cap there would lie in the plane of the head and
    shade it black."""
    tube(col, name, mat, [(*_around(centre, 360 * k / 28, radius), z) for k in range(29)], thickness, 6)


def _drum_patch(col, name, mat, centre, radius, angle, z, size):
    """A patch of `size` (along the curve, up) on a drum's side, in strips narrow enough to follow
    its curve."""
    width, height = size
    strips = max(1, round(width / 0.035))
    step = math.degrees(width / strips / radius)
    for i in range(strips):
        a = angle + (i - (strips - 1) / 2) * step
        x, y = _around(centre, a, radius + 0.001)
        box(col, name, mat, (width / strips + 0.004, 0.002, height), at=(x, y, z), rotate=(0, 0, a + 90))


# The game's four drums, which a barrel digester may be built from, by the item: its paint, and
# whether it is the game's homemade Metal Drum, rolled from sheet with a welded seam up its side and a
# band round its middle, or a bought drum with two rolling hoops.
DRUM_LOOKS = {"MetalDrum": ("drummetal", "seam"), "Mov_OrangeBarrel": ("drumorange", "hoops"),
              "Mov_DarkGreenBarrel": ("drumgreen", "hoops"), "Mov_LightGreenBarrel": ("drumolive", "hoops")}


def drum(col, name, at, look="MetalDrum", paint=None):
    """One of the game's 55 gallon drums (DRUM_LOOKS) standing at `at`, its chimes and hoops or band
    standing proud, the top chime dark as the game outlines its own, rust eating at it where the wet
    ground and the rain on its head reach, on the sides the viewer sees. `paint` overrides its
    look's material, for a drum a fire has scorched. Every look has the one outline, so an overlay
    fits over any."""
    radius, height = DRUM
    look_paint, kind = DRUM_LOOKS[look]
    paint = paint or look_paint
    hoop, proud = 0.025, 0.008
    cylinder(col, name, M(paint), radius, height, at=(at[0], at[1], 0), segments=32)
    bands = (height / 2 - hoop / 2,) if kind == "seam" else (height / 3 - hoop / 2, 2 * height / 3 - hoop / 2)
    # Each hoop is its own part, its paint measured from its own foot, so only the drum's foot
    # takes a scorched body's soot.
    for z in (0,) + bands:
        cylinder(col, name + "_Hoop", M(paint if z == 0 else look_paint), radius + proud, hoop, at=(at[0], at[1], z), segments=32)
    _ring(col, name + "_Chime", M("weld"), at, radius - 0.002, height + 0.002, 0.011)
    if kind == "seam":
        _drum_patch(col, name + "_Seam", M("weld"), at, radius + 0.001, -15, 0.0, (0.012, height))
        for z in (0.06, 0.2, 0.33, 0.55, 0.68, 0.82):
            x, y = _around(at, -11, radius + 0.004)
            cylinder(col, name + "_Rivet", M("weld"), 0.006, 0.004, at=(x, y, z), rotate=(90, 0, -11 + 90), segments=6)
    for angle, z, size, on_hoop in ((-112, 0, (0.13, hoop), True), (-98, hoop, (0.05, 0.03), False),
                                    (-30, 0, (0.09, hoop), True), (-62, height - 0.035, (0.08, 0.03), False),
                                    (-48, height - 0.085, (0.02, 0.05), False), (15, bands[0], (0.06, hoop), True)):
        _drum_patch(col, name + "_Rust", M("rust"), at, radius + (proud if on_hoop else 0), angle, z, size)


def dropped_drum(col, look):
    """One of the game's drums (DRUM_LOOKS) as its item, its bungs in its head. Its ground model lies
    on its side, so a dropped drum can't pass for one standing installed. A standing drum's foot
    is two caps in one plane, which the occlusion bake turns black, so a lying one shows a bottom
    head of its own just below them, rimmed with a chime like its top."""
    radius, height = DRUM
    drum(col, "Drum", (0, 0), look)
    for (x, y), bung in ((FEED_BUNG, 0.042), (GAS_BUNG, 0.026)):
        cylinder(col, "Drum_Bung", M("darkgrey"), bung, 0.012, at=(x, y, height), segments=14)
    cylinder(col, "Drum_Bottom", M(DRUM_LOOKS[look][0]), radius + 0.008, 0.004, at=(0, 0, -0.004), segments=32)
    _ring(col, "Drum_BottomChime", M("weld"), (0, 0), radius - 0.002, -0.006, 0.011)


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
        cylinder(col, "Barrel_Funnel", M("funnel"), 0.03, 0.12, at=(fx, fy, height + 0.05), radius_top=0.1, segments=18)
        cylinder(col, "Barrel_FunnelMouth", M("black"), 0.088, 0.003, at=(fx, fy, height + 0.168), segments=18)
        gx, gy = x + GAS_BUNG[0], y + GAS_BUNG[1]
        cylinder(col, "Barrel_GasBung", M("darkgrey"), 0.026, 0.012, at=(gx, gy, height), segments=12)
        cylinder(col, "Barrel_GasValve", M("copper"), 0.014, 0.05, at=(gx, gy, height + 0.012), segments=10)
        box(col, "Barrel_GasLever", M("red"), (0.07, 0.014, 0.01), at=(gx - 0.03, gy, height + 0.042))
        hx, hy = HOLDER_INLET
        run = math.hypot(hx - x, hy - y)
        ux, uy = (hx - x) / run, (hy - y) / run
        ex, ey = x + ux * (radius + 0.035), y + uy * (radius + 0.035)
        tube(col, "Barrel_Hose", M("rubberhose"), [(gx, gy, height + 0.06), (gx + ux * 0.04, gy + uy * 0.04, height + 0.12),
                                              (ex - ux * 0.05, ey - uy * 0.05, height + 0.09), (ex, ey, height - 0.06),
                                              (ex + ux * 0.015, ey + uy * 0.015, 0.4), (hx - ux * 0.02, hy - uy * 0.02, 0.12),
                                              (hx, hy, 0.04)], 0.014, 8)
        sx, sy = _around(BARREL_AT, SPIGOT_ANGLE, radius)
        ox, oy = _around((0, 0), SPIGOT_ANGLE, 1)
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
            flap_x, flap_y = _around((bx, by), turn + 15 + 90, ry * 0.25)
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
        _ring(col, "Insulated_Chime", M("weld"), (0, 0), radius, rim, 0.011)
        cylinder(col, "Insulated_Slurry", M("sludge"), radius - 0.006, 0.002, at=(0, 0, rim), segments=28)
        cylinder(col, "Insulated_Guide", M("galvanised"), 0.021, GUIDE_TOP - rim, at=(0, 0, rim), segments=10)
        cylinder(col, "Insulated_GuideCap", M("galvanised"), 0.028, 0.025, at=(0, 0, GUIDE_TOP), segments=10)
        fx, fy = INSULATED_FEED
        tube(col, "Insulated_FeedPipe", M("pvc"), [(fx, fy, height + 0.06), (fx, fy, height), (*INSULATED_INLET, rim - 0.16)], 0.024, 12)
        cylinder(col, "Insulated_FeedTape", M("ducttape"), 0.03, 0.04, at=(fx, fy, height + 0.03), segments=14)
        cylinder(col, "Insulated_Funnel", M("funnel"), 0.03, 0.12, at=(fx, fy, height + 0.06), radius_top=0.1, segments=18)
        cylinder(col, "Insulated_FunnelMouth", M("black"), 0.088, 0.003, at=(fx, fy, height + 0.178), segments=18)
    if level:
        top = rim + FLOAT_RISE[level - 1]
        float_radius, float_height = FLOAT_DRUM
        cylinder(col, "Insulated_Float", M("drummetal"), float_radius, float_height, at=(0, 0, top - float_height), segments=32)
        cylinder(col, "Insulated_FloatHoop", M("drummetal"), float_radius + 0.007, 0.022, at=(0, 0, top - float_height / 2 - 0.01),
                 segments=32)
        _ring(col, "Insulated_FloatChime", M("weld"), (0, 0), float_radius - 0.002, top + 0.002, 0.01)
        cylinder(col, "Insulated_Sleeve", M("galvanised"), 0.034, 0.07, at=(0, 0, top), segments=10)
        vx, vy = -0.1, -0.12
        cylinder(col, "Insulated_GasValve", M("copper"), 0.014, 0.05, at=(vx, vy, top), segments=10)
        box(col, "Insulated_GasLever", M("red"), (0.07, 0.014, 0.01), at=(vx + 0.03, vy, top + 0.03))
        # The hose to the stove, slack enough for the drum's whole rise, over the box's front.
        front = -size / 2
        tube(col, "Insulated_Hose", M("rubberhose"), [(vx, vy, top + 0.05), (vx - 0.04, vy - 0.06, top + 0.09),
                                                 (-0.27, front + 0.05, height + 0.07), (-0.29, front - 0.03, height - 0.05),
                                                 (-0.3, front - 0.035, 0.25), (-0.33, front - 0.06, 0.03)], 0.014, 8)
    if scrubber:
        base = height + 0.02
        fitting = _around((0, 0), -45, radius - 0.015)
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
# centre it runs, out to the square's sides; where round there it is grassed over, and where it
# thins into the ground.
BANK = (0.3, 0.53)
BANK_TURF = (0.36, 0.42)
BANK_FADE = (0.46, 0.53)
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
        x, y = _around((cx, cy), azimuth, out)
        shade = M("grass" if rng.random() < 0.7 else "grassdry")
        for _ in range(rng.randint(3, 5)):
            tall = rng.uniform(0.04, 0.08)
            prism(col, "Dome_Grass", shade, [(-0.004, 0), (0.004, 0), (rng.uniform(-0.015, 0.015), tall)], 0.002,
                  at=(x + rng.uniform(-0.01, 0.01), y + rng.uniform(-0.01, 0.01), bank(out) - 0.01),
                  rotate=(0, 0, rng.uniform(0, 180)))
    rng = random.Random(41)
    polar, course = 0.0, 0
    while polar < math.radians(70):
        ring, z = radius * math.cos(polar), rise * math.sin(polar)
        tilt = math.degrees(math.atan2(math.sin(polar) / rise, math.cos(polar) / radius))
        count = max(6, round(2 * math.pi * ring / (BRICK[0] + 0.012)))
        # Courses the bank buries whole aren't laid: none of them would show.
        if z + BRICK[2] > height - 0.03:
            for k in range(count):
                azimuth = 360 * (k + 0.5 * (course % 2)) / count
                x, y = _around((cx, cy), azimuth, ring)
                length = 2 * math.pi * ring / count - 0.012
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
    box(col, "Dome_ValveLever", M("red"), (0.09, 0.014, 0.01), at=(cx + 0.035, cy, crown + 0.12))
    tube(col, "Dome_GasHose", M("rubberhose"), [(cx, cy, pipe_top), (cx - 0.02, cy + 0.04, pipe_top + 0.04),
                                                (cx - 0.1, cy + 0.12, pipe_top), (cx - 0.24, cy + 0.3, crown - 0.15),
                                                (-0.36, 0.44, 0.12), (-0.38, 0.48, 0.03)], 0.014, 8)
    # The feed: the recipe's pipe out of the dome's foot, bent up to stand clear of it, a funnel
    # taped into its end.
    lx, ly = _around((cx, cy), DOME_FEED_ANGLE, radius - 0.03)
    bx, by = _around((cx, cy), DOME_FEED_ANGLE, radius + 0.04)
    fx, fy = _around((cx, cy), DOME_FEED_ANGLE, radius + 0.06)
    tube(col, "Dome_Feed", M("pvc"), [(lx, ly, 0.1), (bx, by, 0.12), (fx, fy, 0.2), (fx, fy, 0.32)], 0.024, 12)
    cylinder(col, "Dome_FeedTape", M("ducttape"), 0.03, 0.04, at=(fx, fy, 0.29), segments=14)
    cylinder(col, "Dome_Funnel", M("funnel"), 0.03, 0.12, at=(fx, fy, 0.32), radius_top=0.1, segments=18)
    cylinder(col, "Dome_FunnelMouth", M("black"), 0.088, 0.003, at=(fx, fy, 0.438), segments=18)


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
        u, v = _around((0, 0), i * 137.5, spread)
        size = (rng.uniform(0.012, 0.022), rng.uniform(0.008, 0.014), 0.01)
        box(col, "Ash_Charcoal", M("charcoal"), size, at=(u * rx, v * ry, on_heap(spread) - 0.004),
            rotate=(rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(0, 180)))
    for i in range(9):
        spread = 0.8 * math.sqrt((i + 0.3) / 9)
        u, v = _around((0, 0), 60 + i * 137.5, spread)
        mound(col, "Ash_Fleck", M("ashwhite"), (rng.uniform(0.008, 0.014), rng.uniform(0.006, 0.01), 0.004),
              at=(u * rx, v * ry, on_heap(spread) - 0.003), rotate=(0, 0, rng.uniform(0, 180)), segments=8, rings=2)
    for angle, spread, length in ((30, 0.55, 0.07), (200, 0.45, 0.06)):
        u, v = _around((0, 0), angle, spread)
        start = (u * rx, v * ry, on_heap(spread) - 0.012)
        out = _around((0, 0), angle, 1)
        beam(col, "Ash_Twig", M("charcoal"), start, (start[0] + out[0] * length, start[1] + out[1] * length, start[2] + 0.025),
             (0.009, 0.009))


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
        _ring(col, "Scrubber_Rib", M("safety"), bucket_at, radius * (0.88 + 0.12 * rib), z + height * rib, 0.006)
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
    box(col, "Heater_GasHandle", M("red"), (0.012, 0.06, 0.01), at=(width / 2 + 0.06, 0.04, stub_z + 0.015))


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
        _ring(col, "Kit_Hose", M("rubberhose"), (-0.02, 0.07), 0.075 - 0.004 * i, 0.012 + 0.022 * i, 0.012)
    tube(col, "Kit_HoseEnd", M("rubberhose"), [(0.051, 0.07, 0.056), (0.1, 0.05, 0.03), (0.14, 0.06, 0.012)], 0.012, 8)
    for x, y in ((0.1, 0.07), (0.15, 0.03)):
        _ring(col, "Kit_Clamp", M("galvanised"), (x, y), 0.022, 0.004, 0.004)
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
# The turn, in degrees about Z, from a body facing south to one facing each way.
BODY_TURN = {"S": 0, "E": 90, "N": 180, "W": 270}
GAS_KIT_SCALE = 1.2  # a little larger than life, so the mixer reads beside the game's chunky generators
# Where the kit lies on a generator the game doesn't know, another mod's: on the floor across the
# square's front corner, which a generator in its middle leaves clear.
GAS_KIT_AT = (0.35, -0.34)


def _turned(point, degrees):
    a = math.radians(degrees)
    x, y = point[0], point[1]
    return (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a), *point[2:])


def _generator_fit(body, facing):
    """For a generator of `body` facing `facing`, or None for an unknown one: the mixer's origin and
    turn, the top of its gas branch where the pipe comes down into it, the intake and its outward
    direction, and the body's box (lowest and highest corner) on its square."""
    s = GAS_KIT_SCALE
    if body is None:
        origin, turn = (*GAS_KIT_AT, 0.0), 45
        intake, out, box_ = None, None, None
    else:
        spec, degrees = GENERATOR_BODIES[body], BODY_TURN[facing]
        intake = _turned(spec["intake"], degrees)
        out = _turned(spec["facing"], degrees)
        # The mixer lies along the intake's axis, its +X barb in the intake, its axis at the intake.
        origin = (intake[0] + out[0] * 0.1 * s, intake[1] + out[1] * 0.1 * s, intake[2] - 0.026 * s)
        turn = math.degrees(math.atan2(-out[1], -out[0]))
        corners = [_turned((x, y, 0), degrees) for x in (spec["box"][0][0], spec["box"][1][0]) for y in (spec["box"][0][1], spec["box"][1][1])]
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
    origin, turn, _, intake, out, _ = _generator_fit(body, facing)
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
    _ring(col, "Comp_Seam", M("darkgrey"), (0, 0), radius + 0.002, base + can, 0.005)
    box(col, "Comp_Label", M("label"), (0.07, 0.002, 0.04), at=(0.0, -radius - 0.001, base + 0.04))
    box(col, "Comp_Relay", M("darkgrey"), (0.045, 0.07, 0.06), at=(-radius - 0.02, 0, base + 0.03), bevel=0.004)
    for (x, y), lean in (((0.04, 0.05), (0.05, 0.07)), ((0.06, -0.02), (0.08, -0.03)), ((-0.02, 0.06), (-0.03, 0.08))):
        tube(col, "Comp_Stub", M("copper"), [(x, y, base + can + 0.04), (x + lean[0] * 0.4, y + lean[1] * 0.4, base + can + 0.09),
                                             (x + lean[0], y + lean[1], base + can + 0.11)], 0.007, 8)


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
    inside = _around(GASIFIER_AT, angle, radius - 0.01)
    out = _around(GASIFIER_AT, angle, (clear or radius) + 0.03)
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
        _ring(col, name + "_BucketRib", M("bucket"), GASIFIER_FILTER_AT, foot + (rim - foot) * t + 0.003, height * t, 0.005)
    _ring(col, name + "_Seal", M("black"), GASIFIER_FILTER_AT, rim + 0.002, height, 0.008)
    cylinder(col, name + "_Lid", M("rawsteel"), rim + 0.012, 0.012, at=(fx, fy, height), segments=28)
    for angle in (-60, 60, 180):
        x, y = _around(GASIFIER_FILTER_AT, angle, rim + 0.012)
        box(col, name + "_Latch", M("weld"), (0.025, 0.012, 0.05), at=(x, y, height - 0.035), rotate=(0, 0, angle + 90))
    cylinder(col, name + "_Outlet", M("galvanised"), PIPE_RADIUS, OUTLET_STUB, at=(*FILTER_OUTLET, FILTER_TOP), segments=12)
    cylinder(col, name + "_OutletCap", M("galvanised"), PIPE_RADIUS + 0.006, 0.02, at=(*FILTER_OUTLET, FILTER_TOP + OUTLET_STUB - 0.012),
             segments=12)
    bx, by = FILTER_BLOWER
    cylinder(col, name + "_Blower", M("darkgrey"), 0.045, 0.05, at=(bx, by, FILTER_TOP), segments=16)
    cylinder(col, name + "_Stack", M("galvanised"), 0.02, 0.18, at=(bx, by, FILTER_TOP + 0.05), segments=12)
    cylinder(col, name + "_StackCap", M("red"), 0.026, 0.025, at=(bx, by, FILTER_TOP + 0.23), segments=12)
    cock = _around(GASIFIER_FILTER_AT, -80, foot + 0.02)
    box(col, name + "_DrainCock", M("brass"), (0.03, 0.03, 0.03), at=(*cock, 0.02))


def _facing(radius, z, out=0.0):
    """Where on the body's side, at `radius` and `z`, the fire door's face is, and the turn that lays
    a part's X along the side there; `out` stands it that much proud."""
    return (*_around(GASIFIER_AT, GASIFIER_DOOR_ANGLE, radius + out), z), (0, 0, GASIFIER_DOOR_ANGLE + 90)


def _along(point, offset):
    """`point` moved `offset` along the body's side at the door, to the viewer's right for positive."""
    dx, dy = _around((0, 0), GASIFIER_DOOR_ANGLE + 90, offset)
    return point[0] + dx, point[1] + dy, point[2]


def _disc_at(col, name, mat, at, disc):
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
        a, b = _around(GASIFIER_AT, angle - 12, pot_radius), _around(GASIFIER_AT, angle + 12, pot_radius)
        c, d = _around(GASIFIER_AT, angle - 8, pot_radius + 0.035), _around(GASIFIER_AT, angle + 8, pot_radius + 0.035)
        tube(col, "Prim_PotHandle", M("darkgrey"), [(*a, pot_height - 0.04), (*c, pot_height - 0.04), (*d, pot_height - 0.04),
                                                    (*b, pot_height - 0.04)], 0.007, 6)
    hole, _ = _facing(pot_radius, 0.07)
    _disc_at(col, "Prim_AirHole", M("black"), hole, 0.04)
    foot, rim, height = PRIMITIVE_BIN
    cylinder(col, "Prim_Bin", M("roundbin"), foot, height, at=(bx, by, pot_height), radius_top=rim, segments=28)
    _ring(col, "Prim_BinRim", M("roundbin"), GASIFIER_AT, rim + 0.004, pot_height + height, 0.01)
    cylinder(col, "Prim_Tape", M("ducttape"), foot + 0.006, 0.05, at=(bx, by, pot_height - 0.02), segments=28)
    top = pot_height + height
    cylinder(col, "Prim_Lid", M("rawsteel"), rim + 0.012, 0.012, at=(bx, by, top), segments=28)
    tube(col, "Prim_LidHandle", M("weld"), [(bx - 0.06, by, top + 0.01), (bx - 0.05, by, top + 0.05), (bx + 0.05, by, top + 0.05),
                                            (bx + 0.06, by, top + 0.01)], 0.008, 6)
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
        _drum_patch(col, "Drum_Tar", M("tar"), GASIFIER_AT, radius + 0.002, angle, height - rng.uniform(0.08, 0.16), (0.02, rng.uniform(0.06, 0.14)))
    cylinder(col, "Drum_Lid", M("rawsteel"), radius + 0.008, 0.02, at=(bx, by, height), segments=32)
    _ring(col, "Drum_Clamp", M("weld"), GASIFIER_AT, radius + 0.01, height + 0.01, 0.012)
    tube(col, "Drum_LidHandle", M("weld"), [(bx - 0.07, by, height + 0.02), (bx - 0.06, by, height + 0.07), (bx + 0.06, by, height + 0.07),
                                            (bx + 0.07, by, height + 0.02)], 0.008, 6)
    at, turn = _facing(radius, DRUM_DOOR_Z, 0.004)
    box(col, "Drum_AshDoor", M("rustysteel"), (0.22, 0.008, 0.14), at=at, rotate=turn, bevel=0.002)
    for side in (-1, 1):
        hinge, _ = _facing(radius, DRUM_DOOR_Z + 0.055 + side * 0.04, 0.012)
        box(col, "Drum_DoorHinge", M("weld"), (0.02, 0.02, 0.03), at=_along(hinge, -0.11), rotate=turn)
    latch, _ = _facing(radius, DRUM_DOOR_Z + 0.06, 0.012)
    box(col, "Drum_DoorLatch", M("weld"), (0.03, 0.012, 0.02), at=_along(latch, 0.09), rotate=turn)
    hole, _ = _facing(radius, DRUM_DOOR_Z + 0.09, 0.008)
    for offset in (-0.05, 0.0, 0.05):
        _disc_at(col, "Drum_DraftHole", M("black"), _along(hole, offset), 0.014)
    _gasifier_outlet(col, "Drum_Pipe", radius, 0.2)


def _welded_gasifier(col):
    """A body welded up from sheet steel and painted with stove black, the paint burnt off and rusting
    low round the fire: seams round it, a shoulder up to a clamped hopper lid, a forged grate door at
    its foot."""
    radius, height = WELDED
    bx, by = GASIFIER_AT
    cylinder(col, "Welded_Body", M("stovescorched"), radius, height, at=(bx, by, 0), segments=32)
    for z in (0.3, 0.6):
        _ring(col, "Welded_Seam", M("weld"), GASIFIER_AT, radius + 0.001, z, 0.005)
    cylinder(col, "Welded_Shoulder", M("stoveblack"), radius, 0.12, at=(bx, by, height), radius_top=0.13, segments=32)
    _ring(col, "Welded_ShoulderSeam", M("weld"), GASIFIER_AT, radius + 0.001, height, 0.005)
    neck = height + 0.12
    cylinder(col, "Welded_Neck", M("rawsteel"), 0.13, 0.05, at=(bx, by, neck), segments=24)
    cylinder(col, "Welded_Lid", M("weld"), 0.145, 0.025, at=(bx, by, neck + 0.05), segments=24)
    box(col, "Welded_LidClamp", M("weld"), (0.03, 0.08, 0.02), at=(bx + 0.13, by, neck + 0.05), bevel=0.004)
    tube(col, "Welded_LidHandle", M("weld"), [(bx - 0.05, by, neck + 0.075), (bx - 0.04, by, neck + 0.12), (bx + 0.04, by, neck + 0.12),
                                              (bx + 0.05, by, neck + 0.075)], 0.008, 6)
    at, turn = _facing(radius, 0.06, 0.002)
    box(col, "Welded_GrateOpening", M("black"), (0.2, 0.004, 0.16), at=at, rotate=turn)
    for z in (0.045, 0.22):
        rail, _ = _facing(radius, z, 0.006)
        box(col, "Welded_GrateFrame", M("weld"), (0.23, 0.012, 0.015), at=rail, rotate=turn)
    bar, _ = _facing(radius, 0.06, 0.008)
    for offset in (-0.105, -0.05, 0.0, 0.05, 0.105):
        box(col, "Welded_GrateBar", M("weld"), (0.014, 0.012, 0.16), at=_along(bar, offset), rotate=turn)
    _gasifier_outlet(col, "Welded_Pipe", radius, 0.2)


def _gasifier_glow(col, tier):
    """The fire showing at the door, a little proud of what it shows through, so a lit overlay drawn
    over the gasifier's tile keeps it: the pot's air hole, the drum door's draft holes and the gap
    under it, the welded body's grate opening behind its bars."""
    if tier == "primitive":
        hole, _ = _facing(PRIMITIVE_POT[0], 0.07, 0.002)
        _disc_at(col, "Glow_AirHole", M("flame"), hole, 0.036)
    elif tier == "standard":
        hole, _ = _facing(DRUM[0], DRUM_DOOR_Z + 0.09, 0.011)
        for offset in (-0.05, 0.0, 0.05):
            _disc_at(col, "Glow_DraftHole", M("flame"), _along(hole, offset), 0.012)
        gap, turn = _facing(DRUM[0], DRUM_DOOR_Z - 0.012, 0.004)
        box(col, "Glow_DoorGap", M("flame"), (0.2, 0.006, 0.01), at=gap, rotate=turn)
    else:
        at, turn = _facing(WELDED[0], 0.065, 0.005)
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
    _, _, branch, _, _, box_ = _generator_fit(body, facing)
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
        u, v = _around((0, 0), 40 + i * 95, spread)
        mound(col, "Tarry_Patch", M("tarstraw"), (rng.uniform(0.012, 0.018), rng.uniform(0.008, 0.012), 0.008),
              at=(u * rx, v * ry, height * math.sqrt(1 - spread * spread) * 1.05), rotate=(0, 0, rng.uniform(0, 180)),
              lumps=0.1, seed=63 + i, segments=10, rings=3)
    for k in range(18):
        angle, reach = rng.uniform(0, 360), rng.uniform(0.5, 0.85)
        ux, uy = _around((0, 0), angle, 1)
        z = height * math.sqrt(1 - reach * reach) + 0.003
        start = (ux * rx * reach, uy * ry * reach, z)
        length = rng.uniform(0.04, 0.07)
        end = (start[0] + ux * length, start[1] + uy * length, max(0.004, z + rng.uniform(-0.03, 0.01)))
        # Thicker than a decal (models.DECAL_THICKNESS), so the ground model keeps them standing out.
        beam(col, "Tarry_Strand", M("straw" if k % 3 == 0 else "tarstraw"), start, end, (0.006, 0.003))


# A government digest-size pamphlet. Its pages are thick enough to be modelled (models.py
# DECAL_THICKNESS) for what is printed on its cover to be baked onto.
PAMPHLET = (0.14, 0.215, 0.004)


def fema_pamphlet(col):
    """The 1989 FEMA plans for a wood gas generator as a government office printed them: a thin
    pamphlet, two staples in its spine, a plain white cover with a blue band and the agency's seal."""
    width, depth, height = PAMPHLET
    box(col, "Pamphlet_Pages", M("white"), (width - 0.003, depth - 0.003, height - 0.0008))
    box(col, "Pamphlet_Cover", M("white"), (width, depth, 0.0008), at=(0, 0, height - 0.0008))
    top = height + 0.0003
    flat = (0, 0, 0)
    box(col, "Pamphlet_Band", M("marine"), (width, 0.05, 0.0004), at=(0, depth / 2 - 0.035, height))
    text(col, "Pamphlet_Agency", M("white"), "FEMA", 0.022, at=(0, depth / 2 - 0.045, top + 0.0002), rotate=flat)
    for i, (line, size) in enumerate((("CONSTRUCTION OF A", 0.0085), ("SIMPLIFIED WOOD GAS", 0.0105),
                                      ("GENERATOR", 0.0105))):
        text(col, "Pamphlet_Title", M("ink"), line, size, at=(0, 0.025 - i * 0.016, top), rotate=flat)
    _ring(col, "Pamphlet_Seal", M("marine"), (0, -0.05), 0.02, top, 0.001)
    _ring(col, "Pamphlet_SealInner", M("marine"), (0, -0.05), 0.012, top, 0.0008)
    text(col, "Pamphlet_Date", M("ink"), "MARCH 1989", 0.0065, at=(0, -0.095, top), rotate=flat)
    for y in (-0.055, 0.055):
        box(col, "Pamphlet_Staple", M("galvanised"), (0.002, 0.018, 0.0006), at=(-width / 2 + 0.006, y, height))


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
            x, y = _around(centre, a, radius + out)
            box(col, name, M(mat), (chord + 0.004, thick, height), at=(x, y, z), rotate=(0, 0, a + 90))
        for rise in (height / 3, 2 * height / 3):
            x, y = _around(centre, a, radius + 0.006)
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
        box(col, name + "_Gusset", M("weld"), (0.1, 0.008, 0.12), at=(*_around((0, 0), angle, 0.09), 0.092), rotate=(0, 0, angle))
    cylinder(col, name + "_Mast", M("galvanised"), 0.045, top - 0.092, at=(0, 0, 0.092), segments=14)
    for z in (top / 3, 2 * top / 3):
        _ring(col, name + "_MastWeld", M("weld"), (0, 0), 0.046, z, 0.006)
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
        x, z = _around((0, 0), a, 0.024)
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
            x, z = _around((0, 0), a, radius - 0.0015)
            parts.append(box(col, name + "Slot", M("black"), (0.02, 0.022, 0.003), at=(x, y, z), rotate=(0, 90 - a, 0)))
    for k in range(4):
        x, z = _around((0, 0), 90 * k + 45, radius - 0.002)
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
        return [_around(centre, math.degrees(start + span * i / count), radius + thick / 2) for i in range(count + 1)]

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
        x, z = _around((0, hub), 60 * k, big * 0.6)
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
        x, z = _around((0, 0), 72 * k + 90, 0.055)
        parts.append(cylinder(col, rotor + "Stud", M("galvanised"), 0.007, 0.025, at=(x, 0.002, z), rotate=(90, 0, 0), segments=6))
    for name, y in (("Front", 0.072), ("Rear", 0.133)):
        parts.append(cylinder(col, rotor + "MagnetDisc" + name, M("rawsteel"), 0.2, 0.012, at=(0, y, 0), rotate=(90, 0, 0), segments=28))
    for k in range(6):
        x, z = _around((0, 0), 60 * k + 30, 0.15)
        parts.append(cylinder(col, rotor + "DiscBolt", M("galvanised"), 0.009, 0.006, at=(x, 0.06, z), rotate=(90, 0, 0), segments=6))
    parts.append(cylinder(col, "Alt_Stator", M("resin"), 0.23, 0.035, at=(0, 0.115, 0), rotate=(90, 0, 0), segments=28))
    for k in range(9):
        x, z = _around((0, 0), 40 * k, 0.205)
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
    feet = [_around((0, 0), angle, 0.42) for angle in (90, 210, 330)]
    heads = [_around((0, 0), angle, 0.07) for angle in (90, 210, 330)]

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


# How far apart blades of each kind stack in a bundle: their roots' thickness, or a pipe blade's curve.
BUNDLE_SPACING = {"wood": 2.4 * PROPELLER_BLADE[2], "pipe": 0.03, "steel": 3.2 * ALTERNATOR_BLADE[2]}


def _blade_bundle(col, name, kind, size):
    """Three blades of `kind` stacked flat and tied with twine at two places."""
    length, chord, thick = size
    spacing = BUNDLE_SPACING[kind]
    for i in range(3):
        # Span along X, chord along Y, flat side up.
        group(col, name, _blade(col, name, kind, size), at=(-length / 2, 0, spacing * (0.5 + i)), rotate=(90, 0, 90))
    for x in (-length * 0.2, length * 0.25):
        box(col, name + "_Twine", M("tape"), (0.012, chord + 0.02, spacing * 3.2), at=(x, chord * 0.1, 0))


def wooden_blades(col):
    """Three propeller blades carved from planks, tied in a bundle."""
    _blade_bundle(col, "WoodBlades", "wood", PROPELLER_BLADE)


def pipe_blades(col):
    """Three propeller blades sawn from grey plastic pipe, tied in a bundle."""
    _blade_bundle(col, "PipeBlades", "pipe", PROPELLER_BLADE)


def steel_blades(col):
    """Three blades hammered out of sheet steel at the forge, tied in a bundle."""
    _blade_bundle(col, "SteelBlades", "steel", ALTERNATOR_BLADE)


def _broken_blades(col, name, kind, size):
    """Three blades of `kind` a storm snapped, their root ends lying splayed in a loose heap."""
    length, chord, _ = size
    spacing = BUNDLE_SPACING[kind]
    for i, (kept, turn) in enumerate(((3, 0), (2, 25), (4, -20))):
        group(col, name, _blade(col, name, kind, size, kept=kept),
              at=(-length * 0.3, chord * 0.4 * (i - 1), spacing * (0.5 + i)), rotate=(90, 0, 90 + turn))


def broken_wooden_blades(col):
    """What a storm left of a set of carved propeller blades."""
    _broken_blades(col, "BrokenWoodBlades", "wood", PROPELLER_BLADE)


def broken_pipe_blades(col):
    """What a storm left of a set of plastic pipe blades."""
    _broken_blades(col, "BrokenPipeBlades", "pipe", PROPELLER_BLADE)


def broken_steel_blades(col):
    """What a storm left of a set of forged steel blades."""
    _broken_blades(col, "BrokenSteelBlades", "steel", ALTERNATOR_BLADE)


def homemade_alternator(col):
    """The homemade alternator lying on its back, the hub's face up."""
    group(col, "AltItem", _alternator_head(col, "AltItem_"), at=(0, 0, 0.27), rotate=(-90, 0, 0))


def car_alternator(col):
    """A car's alternator, loose, standing on its mounting ears, its pulley on."""
    group(col, "CarAltItem", _car_alternator(col, "CarAltItem_"), at=(0, -0.085, CAR_ALTERNATOR_RADIUS + 0.035))


# The sprite model's yaw that turns a south-facing model to face each way. The game draws an
# exported model half a turn round from how it was built, so these are tiles.FACING_TURN's turned
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
    frame over the front, and a padlocked battery box on the tongue. Red and white reflective tape
    runs along its sides and back, reflectors mark its corners, amber at the front and red at the
    back, and it carries the county's name and a Kentucky plate."""
    width, length = TRAILER_DECK
    front, rear = TRAILER_DECK_Y + length / 2, TRAILER_DECK_Y - length / 2
    axle_y, axle_z = TRAILER_AXLE
    paint = M("safety")
    for sign in (-1, 1):
        side = sign * (width / 2 + 0.0008)
        box(col, "Trailer_Rail", paint, (0.05, length, 0.13), at=(sign * (width / 2 - 0.025), TRAILER_DECK_Y, -0.13), bevel=0.005)
        box(col, "Trailer_Spring", M("darkgrey"), (0.05, 0.6, 0.04), at=(sign * (width / 2 - 0.025), axle_y, axle_z - 0.02))
        # A fender over each wheel, outside the rails.
        box(col, "Trailer_Fender", M("black"), (0.24, 0.66, 0.025), at=(sign * 0.69, axle_y, 0.12), bevel=0.008)
        for y in (axle_y - 0.32, axle_y + 0.32):
            box(col, "Trailer_FenderSkirt", M("black"), (0.24, 0.025, 0.17), at=(sign * 0.69, y, -0.05))
        box(col, "Trailer_TailLight", M("red"), (0.1, 0.02, 0.05), at=(sign * (width / 2 - 0.08), rear - 0.01, -0.1), bevel=0.005)
        for y, name, colour in ((front - 0.1, "Trailer_Reflector", "amberlamp"), (rear + 0.1, "Trailer_ReflectorRear", "red")):
            box(col, name, M(colour), (0.004, 0.06, 0.03), at=(side + sign * 0.0012, y, -0.09))
        # The tape in two runs, ahead of and behind the wheel.
        for start, end in ((rear + 0.03, axle_y - 0.37), (axle_y + 0.37, front - 0.03)):
            _tape(col, "Trailer_Tape", start, end, lambda at, w: ((0.0016, w, 0.022), (side, at, -0.122)))
        text(col, "Trailer_Stencil", M("ink"), "KNOX CO", 0.045, at=(side + sign * 0.0006, (rear + axle_y - 0.37) / 2 + 0.05, -0.085),
             rotate=(90, 0, 90 * sign))
    _tape(col, "Trailer_TapeRear", -0.42, 0.42, lambda at, w: ((w, 0.0016, 0.02), (at, rear - 0.0008, -0.045)))
    for y in (rear + 0.025, axle_y, front - 0.025):
        box(col, "Trailer_CrossMember", paint, (width - 0.1, 0.05, 0.1), at=(0, y, -0.12))
    box(col, "Trailer_Deck", M("rawsteel"), (width, length, 0.012), at=(0, TRAILER_DECK_Y, 0))
    tube(col, "Trailer_Axle", M("darkgrey"), [(-0.62, axle_y, axle_z), (0.62, axle_y, axle_z)], 0.035, 8)
    _trailer_plate(col, rear)
    _trailer_tongue(col, front)
    _trailer_battery_box(col)
    _arrow_board(col, rear)
    _trailer_modules(col, front)
    # The lamps' cable from the battery box, along the deck to the mast and up it.
    mast_back = rear + 0.175
    tube(col, "Trailer_Cable", M("black"), [(-0.3, TRAILER_BOX_AT[0] - TRAILER_BOX[1] / 2, TRAILER_BOX_AT[1] + 0.06),
                                            (-0.3, front - 0.02, 0.02), (-0.3, mast_back + 0.1, 0.02), (-0.03, mast_back, 0.02),
                                            (-0.03, mast_back, 0.4)], 0.008)


def _tape(col, name, start, end, piece):
    """Reflective tape from `start` to `end` in alternating red and white pieces about 10 cm long;
    `piece(centre, length)` gives each piece's size and where it goes."""
    count = max(1, round((end - start) / 0.1))
    length = (end - start) / count
    for i in range(count):
        size, at = piece(start + (i + 0.5) * length, length)
        box(col, name, M("red" if i % 2 == 0 else "white"), size, at=at)


def _trailer_plate(col, rear):
    """A Kentucky plate of the day, its county along the bottom, on a bracket under the back."""
    width, height, z = 0.3, 0.15, -0.28
    box(col, "Trailer_PlateBracket", M("darkgrey"), (0.05, 0.03, 0.17), at=(0, rear + 0.015, z + 0.02))
    box(col, "Trailer_Plate", M("white"), (width, 0.004, height), at=(0, rear - 0.002, z), bevel=0.004)
    face = rear - 0.0045
    for body, size, dz in (("KENTUCKY", 0.022, 0.118), ("RD 4417", 0.055, 0.045), ("KNOX", 0.02, 0.012)):
        text(col, "Trailer_Stencil", M("navy"), body, size, at=(0, face, z + dz))


def _trailer_tongue(col, front):
    """The A-frame tongue from the deck's front corners to the coupler, its safety chains slung
    from it, and the jack stand."""
    hitch = TRAILER_HITCH_Y
    for sign in (-1, 1):
        beam(col, "Trailer_Tongue", M("safety"), (sign * 0.5, front - 0.05, -0.09), (sign * 0.03, hitch - 0.1, -0.12),
             (0.06, 0.07), bevel=0.005)
        tube(col, "Trailer_Chain", M("galvanised"), [(sign * 0.14, hitch - 0.35, -0.15), (sign * 0.12, hitch - 0.24, -0.28),
                                                     (sign * 0.07, hitch - 0.11, -0.24), (sign * 0.05, hitch - 0.07, -0.18)], 0.007)
    box(col, "Trailer_Coupler", M("darkgrey"), (0.1, 0.22, 0.08), at=(0, hitch - 0.12, -0.16), bevel=0.01)
    cylinder(col, "Trailer_CouplerCap", M("darkgrey"), 0.05, 0.08, at=(0, hitch - 0.02, -0.16), segments=12)
    jack_x, jack_y = 0.33, front + 0.45
    cylinder(col, "Trailer_Jack", M("darkgrey"), 0.03, 0.55, at=(jack_x, jack_y, TRAILER_GROUND), segments=10)
    box(col, "Trailer_JackFoot", M("darkgrey"), (0.12, 0.12, 0.01), at=(jack_x, jack_y, TRAILER_GROUND))
    top = TRAILER_GROUND + 0.55
    tube(col, "Trailer_JackCrank", M("darkgrey"), [(jack_x, jack_y, top), (jack_x + 0.1, jack_y, top), (jack_x + 0.1, jack_y, top + 0.06)],
         0.008)


TRAILER_BOX = (0.72, 0.42, 0.34)  # width, depth and height of the battery box
TRAILER_BOX_AT = (TRAILER_DECK_Y + TRAILER_DECK[1] / 2 + 0.3, -0.05)  # y and z of its bottom centre
# The lid's hinge pins run along X at the back of the box's top, and the lid turns about them.
# Open TRAILER_LID_OPEN degrees, it just clears the panels' undersides; much further and it meets
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
# The board's lamps on one grid, (across, along) from its centre: a shaft across the board and a
# head each side pointing left, each head lamp in a shaft lamp's column. The outer head lamps
# clear the frame by a couple of centimetres.
LAMP_PITCH = (0.15, 0.105)
ARROW_LAMPS = ([(LAMP_PITCH[0] * (4 - i), 0.0) for i in range(9)]
               + [(LAMP_PITCH[0] * (i - 4), sign * LAMP_PITCH[1] * i) for i in (1, 2, 3) for sign in (-1, 1)])


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
    # Each lamp a lens in a grey bezel, standing just proud of the frame: a hood standing up beside
    # it would hide the lamp behind it from some sides and not from others.
    for x, y in ARROW_LAMPS:
        cylinder(col, "Board_Bezel", M("darkgrey"), 0.052, 0.012, at=(x, centre_y + y, top), segments=16)
        cylinder(col, "Board_Lamp", M("amberlampdark"), 0.045, 0.006, at=(x, centre_y + y, top + 0.012), segments=16)


# The trailer's panels are vehicle parts the player can take off, each shown whole, lightly cracked
# or cracked by its module's condition, so each is a model of its own: TrailerN_ the whole module N
# (0 on the left, at -X), TrailerLightCrackedN_ the lightly cracked one, TrailerCrackedN_ the
# cracked one. The cracked pairs are built this far off, each its own distance, and moved back
# after baking, because the bake takes each surface's colour from the nearest detail and the pairs
# would otherwise lie in one place.
TRAILER_CRACKED_OFFSET = (0.0, 0.0, 4.0)
TRAILER_LIGHT_CRACKED_OFFSET = (0.0, 0.0, 8.0)


def _trailer_modules(col, front):
    """Two modules side by side, long sides front to back, on rails over the front of the deck and
    the battery box, raised a little at the front, on posts from the deck."""
    tilt, centre_y, height = 10, 0.2, 0.72
    for prefix, cracked, light, offset in (("Trailer", False, False, (0, 0, 0)),
                                           ("TrailerLightCracked", True, True, TRAILER_LIGHT_CRACKED_OFFSET),
                                           ("TrailerCracked", True, False, TRAILER_CRACKED_OFFSET)):
        modules = [group(col, "Trailer_Module", solar_module(col, "%s%d" % (prefix, i), cracked=cracked, light_cracks=light),
                         at=(x, 0, 0),
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
# model's scale in Models.txt when it isn't models.GROUND_SCALE.
#
# The game's car battery mesh at its model script's scale is 0.19 x 0.13 x 0.14 m, about three
# quarters of a real one's 0.26 x 0.17 x 0.20, and the game draws it through the same 1.5 as ours
# (models.GROUND_SCALE), a little larger than life. A battery at real size would lie on the ground
# smaller than the car battery beside it, so the batteries, their cases and the plates and molds
# sized to fit them take the car battery's own scale instead; the parts stay real size for the
# icons and the battery storage tiles.
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
    "JarBattery": {"model": jar_battery, "ground_scale": BATTERY_GROUND_SCALE},
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
    "HomesteadPowerMag3": {"model": magazine_3, "icon_elevation": 70},
    "HomesteadPowerMag4": {"model": magazine_4, "icon_elevation": 70},
    "WoodAsh": {"model": wood_ash, "icon_elevation": 25},
    "GasConversionKit": {"model": gas_conversion_kit, "icon_elevation": 45},
    "FridgeCompressor": {"model": fridge_compressor},
    "GasHeater": {"model": gas_heater},
    "TarryPacking": {"model": tarry_packing, "icon_elevation": 35},
    "FemaPamphlet": {"model": fema_pamphlet, "icon_elevation": 70},
    "TreadmillMotor": {"model": treadmill_motor},
    "WoodenBlades": {"model": wooden_blades, "icon_elevation": 50},
    "PipeBlades": {"model": pipe_blades, "icon_elevation": 50},
    "SteelBlades": {"model": steel_blades, "icon_elevation": 50},
    "BrokenWoodenBlades": {"model": broken_wooden_blades, "icon_elevation": 50},
    "BrokenPipeBlades": {"model": broken_pipe_blades, "icon_elevation": 50},
    "BrokenSteelBlades": {"model": broken_steel_blades, "icon_elevation": 50},
    "HomemadeAlternator": {"model": homemade_alternator, "icon_elevation": 40},
    "CarAlternator": {"model": car_alternator, "icon_elevation": 35},
}

# Vanilla items with no ground model of their own, which the game drops as a flat icon: the drums
# the digesters are built from. Lua (RenewableEnergy/Drums.lua) points the items at these, and
# they get no icon.
GROUND_MODELS = {look: {"model": lying(dropped_drum, look=look)} for look in DRUM_LOOKS}

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
            "_PanelLeftLightCracked": (("TrailerLightCracked0_",), TRAILER_LIGHT_CRACKED_OFFSET),
            "_PanelRightLightCracked": (("TrailerLightCracked1_",), TRAILER_LIGHT_CRACKED_OFFSET),
        },
        "hinged": {
            "_Lid": {"pivot": TRAILER_LID_HINGE, "axis": (1, 0, 0), "open": TRAILER_LID_OPEN, "clip": "Lid_closing"},
        },
    },
}
