"""The shared materials every builder paints its parts with, made on first use: M("name")."""
from art.shading import material

# The earth banked round the brick dome (biogas.DOME) is grassed over this far out from the dome's
# centre, and thins into the ground over this, in metres.
BANK_TURF = (0.36, 0.42)
BANK_FADE = (0.46, 0.53)

PALETTE = {
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
    # Transformer steel, a stack of laminations pale enough that the lines between them read,
    # and the dark red enamel of a microwave oven transformer's secondary winding.
    "lamination": lambda: material("RE_Lamination", "#71767a", roughness=0.55, metallic=0.55, grime=0.25),
    "enamel": lambda: material("RE_Enamel", "#8a3a22", roughness=0.35, metallic=0.5, grime=0.1),
    # The green hammertone enamel a homebuilder brushed on a chassis bent up from sheet steel.
    "hammertone": lambda: material("RE_Hammertone", "#577a5c", roughness=0.45, metallic=0.3, grime=0.15, scale=30,
                                   speckle=("#76977a", 0.35)),
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
    # dark: lit, the vehicle's lights texture draws them bright (vehicles.GLOWING).
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
}


def M(name):
    """The shared material `name`."""
    return PALETTE[name]()
