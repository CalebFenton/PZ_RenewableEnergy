#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.3.0"]
# ///
"""Lays out the README and Workshop images from the captures that extract.py saved, with the
harness's lib/promo.py (dev/harness/docs/workshop-page.md, "Laying out the images"). Rerun it after
editing a layout; recapture only when the game's look or the mod's names change:

    art/promo/compose.py

Writes images/{banner,setup,bank,biogas,woodgas,wind,treadmill,items,recipes,trailer,gardenlights}.png;
the Workshop gallery, gallery/NN-<name>.jpg in upload order; and the mod's poster,
Contents/mods/RenewableEnergy/42/poster.png, with the Workshop preview, preview.png. The item models
are framed from the box extract.py found around each. Item, recipe and skill names come from
captures/promo.json, which the game wrote in its own words; the setup captions are the README's.
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "dev" / "harness" / "lib"))
import promo  # noqa: E402
from promo import PAGE, WIDTH  # noqa: E402

HERE = Path(__file__).resolve().parent
CAPTURES = promo.Captures(HERE / "captures")
IMAGES = HERE / "images"
GALLERY = HERE / "gallery"
# The same picture serves as the mod list's poster and the Workshop preview.
POSTER_FILES = [REPO / "Contents/mods/RenewableEnergy/42/poster.png", REPO / "preview.png"]
TITLE = CAPTURES.strings["modName"]
TAGLINE = "Off-grid power, 1993"

SOLAR = (86, 140, 214)
# Each setup shot's caption, and where it is cropped, in capture pixels, around what the promo run
# built in it; a reshoot that frames a shot differently needs its box moved. The setup shots share a
# shape so that they line up side by side.
SETUP_SHOTS = {"stage0": ("A first battery box", (230, 0, 1230, 847)), "homestead": ("A homestead", (190, 80, 1190, 927))}
BANK_CROP = (80, 222, 552, 704)
MENU_CROP = (206, 105, 726, 385)
TRAILER_CROP = (0, 140, 1260, 660)
# banner.png: rows of the world capture above the homestead's wind charger, left out.
BANNER_TOP = 70
# biogas.png and woodgas.png: the world shot around the digesters or gasifiers, with the status
# window of the brick dome or the gasifier set into the corner GAS_CORNERS names ("left" or
# "right", at the top), over ground with nothing built on it, at GAS_WINDOW_SCALE.
GAS_CROPS = {"biogas": (110, 0, 1110, 506), "woodgas": (200, 20, 1100, 480)}
GAS_CORNERS = {"biogas": "left", "woodgas": "right"}
GAS_WINDOW_SCALE = 1.4
# wind.png: the four chargers, rotor tips to feet; treadmill.png: the runner and the battery box in
# the room around them.
WIND_CROP = (0, 90, 1260, 720)
TREADMILL_CROP = (260, 130, 1260, 690)
# bank.png: the status window's size against its capture, as large as leaves room for the menu.
STATUS_SCALE = 1.25
# items.png: one row per kind of thing, with its caption, wrapped at ITEM_COLUMNS; each card is the
# item's model as it lies on the ground over its icon and name.
ITEM_ROWS = [
    ("Panels and mounts", ["RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule",
                           "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWallWood",
                           "RenewableEnergy.SolarWallMetal", "RenewableEnergy.SolarRackWood",
                           "RenewableEnergy.SolarRackMetal"]),
    ("Battery storage", ["RenewableEnergy.BatteryBoxWood", "RenewableEnergy.BatteryBoxMetal",
                         "RenewableEnergy.BatteryRackWood", "RenewableEnergy.BatteryRackMetal",
                         "RenewableEnergy.BatteryBankWood", "RenewableEnergy.BatteryBankMetal"]),
    ("Parts", ["RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
               "RenewableEnergy.MakeshiftInverter", "RenewableEnergy.HomemadeInverter",
               "RenewableEnergy.MicrowaveTransformer", "RenewableEnergy.ChargeController",
               "RenewableEnergy.SolarFailsafe"]),
    ("Batteries and what rebuilds them", ["Base.CarBattery1", "RenewableEnergy.DeepCycleBattery",
                                          "RenewableEnergy.L16Battery", "RenewableEnergy.JarBattery",
                                          "RenewableEnergy.CarBatteryCase",
                                          "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
                                          "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates",
                                          "RenewableEnergy.WoodenBatteryPlatePattern",
                                          "RenewableEnergy.BatteryPlateMoldUnfired", "RenewableEnergy.BatteryPlateMold",
                                          "RenewableEnergy.BatteryElectrolyte"]),
    ("Gadgets, cells and magazines", ["RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger",
                                      "RenewableEnergy.SolarGardenLight", "RenewableEnergy.SolarCells",
                                      "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2"]),
    ("Biogas", ["RenewableEnergy.GasConversionKit", "RenewableEnergy.FridgeCompressor", "RenewableEnergy.GasHeater",
                "RenewableEnergy.HomesteadPowerMag3"]),
    ("Wood gas", ["RenewableEnergy.WoodAsh", "RenewableEnergy.TarryPacking", "RenewableEnergy.FemaPamphlet"]),
    ("Wind and treadmills", ["RenewableEnergy.TreadmillMotor", "RenewableEnergy.CarAlternator",
                             "RenewableEnergy.HomemadeAlternator", "RenewableEnergy.WoodenBlades",
                             "RenewableEnergy.PipeBlades", "RenewableEnergy.SteelBlades",
                             "RenewableEnergy.BrokenWoodenBlades", "RenewableEnergy.BrokenPipeBlades",
                             "RenewableEnergy.BrokenSteelBlades", "RenewableEnergy.HomesteadPowerMag4"]),
]
ITEM_COLUMNS = 6
# recipes.png: the recipes by what they're for, under these titles.
STORAGE, MOUNTS = "Battery storage", "Panel mounts, and taking them down"
MODULES, CARE, ELECTRONICS = "Modules: repair, homemade, and solar cells", "Battery care and rebuilding", "Electronics"
BIOGAS = "Biogas: digesters in the build menu, the gas kit and the heater"
WOODGAS = "Wood gas: gasifiers in the build menu, drums and sprays"
WIND = "Wind: chargers in the build menu, blades and the alternator"
RECIPE_SECTIONS = [
    (STORAGE, ["RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy_MakeBatteryBoxMetal",
               "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy_BuildBatteryRackMetal",
               "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal"]),
    (MOUNTS, ["RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWallWood",
              "RenewableEnergy_MakeSolarWallMetal", "RenewableEnergy_MakeSolarRackWood",
              "RenewableEnergy_MakeSolarRackMetal", "RenewableEnergy_UnmountSolarFlat",
              "RenewableEnergy_UnmountSolarWallWood", "RenewableEnergy_UnmountSolarWallMetal",
              "RenewableEnergy_UnmountSolarRackWood", "RenewableEnergy_UnmountSolarRackMetal"]),
    (MODULES, ["RenewableEnergy_RepairCrackedModule", "RenewableEnergy_RepairCrackedModuleWithGlue",
               "RenewableEnergy_ReglazeModule", "RenewableEnergy_MakeHomemadeSolarModule",
               "RenewableEnergy_TakeApartCalculator", "RenewableEnergy_TakeApartSolarGardenLight",
               "RenewableEnergy_TakeApartSolarCellCharger", "RenewableEnergy_TakeApartSolarMaintainer",
               "RenewableEnergy_TakeApartShatteredModule"]),
    (CARE, ["RenewableEnergy_ServiceBattery", "RenewableEnergy_ReconditionBattery",
            "RenewableEnergy_StripCarBattery", "RenewableEnergy_StripDeepCycleBattery",
            "RenewableEnergy_StripL16Battery", "RenewableEnergy_MakeBatteryPlatePattern",
            "RenewableEnergy_PressBatteryPlateMold", "RenewableEnergy_FireBatteryPlateMold",
            "RenewableEnergy_RecastBatteryPlates", "RenewableEnergy_CastBatteryPlatesFromLeadPipe",
            "RenewableEnergy_RebuildCarBattery", "RenewableEnergy_RebuildDeepCycleBattery",
            "RenewableEnergy_RebuildL16Battery", "RenewableEnergy_MakeJarBattery", "RenewableEnergy_StripJarBattery"]),
    (ELECTRONICS, ["RenewableEnergy_MakeMakeshiftInverter", "RenewableEnergy_MakeHomemadeInverter",
                   "RenewableEnergy_MakeChargeController", "RenewableEnergy_MakeSolarFailsafe"]),
    (BIOGAS, ["RenewableEnergy_BarrelDigester", "RenewableEnergy_InsulatedDigester", "RenewableEnergy_BrickDome",
              "RenewableEnergy_MakeGasConversionKit", "RenewableEnergy_MakeGasHeater", "RenewableEnergy_RefillPropaneBottle"]),
    (WOODGAS, ["RenewableEnergy_PrimitiveGasifier", "RenewableEnergy_Gasifier", "RenewableEnergy_AdvancedGasifier",
               "RenewableEnergy_WeldMetalDrum", "RenewableEnergy_MakeVinegarMildewSpray",
               "RenewableEnergy_MakeVinegarAphidSpray"]),
    (WIND,
     ["RenewableEnergy_ScoopRotor", "RenewableEnergy_PropellerWood", "RenewableEnergy_PropellerPipe",
      "RenewableEnergy_PropellerSteel", "RenewableEnergy_CarAlternatorWood", "RenewableEnergy_CarAlternatorPipe",
      "RenewableEnergy_CarAlternatorSteel", "RenewableEnergy_TurbineWood", "RenewableEnergy_TurbinePipe",
      "RenewableEnergy_AlternatorWindCharger", "RenewableEnergy_CarveWoodenBlades",
      "RenewableEnergy_CutPipeBlades", "RenewableEnergy_ForgeSteelBlades",
      "RenewableEnergy_MakeHomemadeAlternator"]),
]
# The accent along the top of each section's recipe cards; the solar recipes take the panels' blue.
SECTION_ACCENTS = {BIOGAS: (112, 168, 92), WOODGAS: (214, 132, 64), WIND: (120, 196, 204)}
# The result shown for a recipe whose OnCreate gives it, which no output line names. A recipe that
# improves an item it keeps shows that item.
RECIPE_RESULTS = {"RenewableEnergy_RebuildCarBattery": "Base.CarBattery1"}

ITEMS = promo.ItemSheet(CAPTURES, ITEM_ROWS, models=True)
RECIPES = promo.RecipeSheet(CAPTURES, RECIPE_SECTIONS, SOLAR, SECTION_ACCENTS, RECIPE_RESULTS)

# The world shots go in at their captured size, which keeps their pixels; the trailer's crop is the
# garden lights' height, around the trailer and the cones behind it.
GALLERY_TRAILER_CROP = (0, 32, 1260, 944)
# The bank's status window, as large as leaves the room and its menu as tall beside it.
GALLERY_STATUS_SCALE = 1.86
# The digester's and gasifier's windows, as large as leaves the world shot most of the page.
GALLERY_GAS_WINDOW_SCALE = 1.8
# The treadmill's room at its captured size, clear of the black past the rooms the character saw.
GALLERY_TREADMILL_CROP = (0, 40, 1260, 650)
# The item and recipe sheets drawn this many times the README's size: as large as the fullest page
# allows, which keeps their smallest text readable.
ITEM_K = 1.1
RECIPE_K = 1.33
# The item sheet's pictures, with how many cards to a line on each.
GALLERY_ITEMS = [
    ("items-power", "Panels to mount, banks to fill, parts to wire in", [title for title, _ in ITEM_ROWS[:3]], 8),
    ("items-batteries", "Batteries to rebuild, gadgets to take apart", [title for title, _ in ITEM_ROWS[3:5]], 7),
    ("items-gas", "Gas kits, heaters, and the books that teach them", [title for title, _ in ITEM_ROWS[5:7]], 6),
    ("items-wind", "Generators and blades for the wind chargers", [title for title, _ in ITEM_ROWS[7:]], 6),
]
# The recipe sheet over as few pictures as its cards fit at RECIPE_K: for each picture, the
# sections it shows by title, and which of each section's recipes.
GALLERY_RECIPES = [
    ("recipes-storage", "Recipes: battery boxes and racks", [(STORAGE, slice(0, 4))]),
    ("recipes-mounts", "Recipes: flat and wall panel mounts", [(MOUNTS, slice(0, 3))]),
    ("recipes-banks-racks", "Recipes: battery banks and panel racks",
     [(STORAGE, slice(4, None)), (MOUNTS, slice(3, 5))]),
    ("recipes-unmounting", "Recipes: taking panels down", [(MOUNTS, slice(5, None))]),
    ("recipes-electronics", "Recipes: homemade inverters, the controller, the failsafe", [(ELECTRONICS, slice(None))]),
    ("recipes-modules", "Recipes: sealing, reglazing and homemade modules", [(MODULES, slice(0, 4))]),
    ("recipes-solar-cells", "Recipes: solar cells from what you take apart", [(MODULES, slice(4, None))]),
    ("recipes-battery-care", "Recipes: servicing and stripping batteries", [(CARE, slice(0, 5))]),
    ("recipes-plates", "Recipes: casting battery plates", [(CARE, slice(5, 10))]),
    ("recipes-rebuilding", "Recipes: rebuilding batteries, jar batteries", [(CARE, slice(10, None))]),
    ("recipes-digesters", "Build menu: the four digesters", [(BIOGAS, slice(0, 4))]),
    ("recipes-gas-kit", "Recipes: the gas kit, the heater, propane", [(BIOGAS, slice(4, None))]),
    ("recipes-woodgas", "Build menu: gasifiers. Recipes: drums and sprays", [(WOODGAS, slice(None))]),
    ("recipes-wind-treadmill", "Build menu: the scoop rotor, the treadmill wind charger", [(WIND, slice(0, 2))]),
    ("recipes-wind-treadmill-blades", "Build menu: treadmill chargers, pipe and steel blades",
     [(WIND, slice(2, 4))]),
    ("recipes-wind-car-alternator", "Build menu: the car alternator wind charger", [(WIND, slice(4, 6))]),
    ("recipes-wind-car-alternator-turbine", "Build menu: car alternator and wind turbine",
     [(WIND, slice(6, 8))]),
    ("recipes-wind-turbine", "Build menu: wind turbines, pipe and steel blades", [(WIND, slice(8, 10))]),
    ("recipes-wind-parts", "Recipes: blades and the homemade alternator", [(WIND, slice(10, None))]),
]


# Images ------------------------------------------------------------------------------------------


def banner():
    """The mod's name over the homestead, which the world capture holds against its right edge,
    less the grass above the wind charger's rotor."""
    image = promo.full_width(CAPTURES("world"))
    image = image.crop((0, BANNER_TOP, image.width, image.height))
    promo.title_over(image, TITLE, 84, TAGLINE)
    return image


def setup_shots():
    """The setup's shots, each cropped to its SETUP_SHOTS box, with their captions."""
    return [(CAPTURES(name).crop(crop), label) for name, (label, crop) in SETUP_SHOTS.items()]


def setup():
    """The first battery box and the homestead side by side, each under its caption, scaled to share
    the width."""
    gap = 12
    width = (WIDTH - gap) // 2
    shots = [(promo.scaled(crop, width / crop.width), label) for crop, label in setup_shots()]
    image = promo.canvas(max(shot.height for shot, _ in shots))
    for i, (shot, label) in enumerate(shots):
        left = i * (width + gap)
        image.alpha_composite(shot, (left, 0))
        promo.caption(image, (left + 16, 16), label)
    return image


def bank(width=WIDTH, status_scale=STATUS_SCALE, height=None):
    """The homestead's bank indoors over its right-click menu, beside its status window, centred
    in height if given. The menu's text is drawn larger than the status window's, so it is scaled
    down to about the same size, and cropped to the bank's own submenu and Wire In. The room fills
    the column, or less where the room and menu would stand taller than the status window, or than
    the height."""
    margin, gap = 20, 16
    status = promo.scaled(CAPTURES("status"), status_scale)
    column = width - 2 * margin - gap - status.width
    menu = CAPTURES("menu").crop(MENU_CROP)
    menu = promo.scaled(menu, column / menu.width)
    room = CAPTURES("bank").crop(BANK_CROP).convert("RGBA")
    tallest = max(status.height, height - 2 * margin if height else 0)
    room = promo.scaled(room, min(column / room.width, (tallest - gap - menu.height) / room.height))
    inner = max(status.height, room.height + gap + menu.height)
    image = promo.canvas(height or inner + 2 * margin, width)
    top = (image.height - inner) // 2
    assert top >= margin, "the bank's status window and menu are too tall for the page"
    promo.paste(image, room, (margin + column / 2, top + room.height / 2))
    promo.paste(image, menu, (margin + column / 2, top + room.height + gap + menu.height / 2))
    promo.paste(image, status, (width - margin - status.width / 2, top + inner / 2))
    return image


def trailer():
    """The arrow board trailer and the car towing it, cropped to a strip."""
    return promo.full_width(CAPTURES("trailer")).crop(TRAILER_CROP)


def gardenlights():
    return promo.full_width(CAPTURES("gardenlights"))


def gas_shot(name, window, width=WIDTH, window_scale=GAS_WINDOW_SCALE, height=None):
    """The world shot `name` cropped to GAS_CROPS, as wide as the image and centred in its height if
    given, with the status window `window` of one of the things in it set into its GAS_CORNERS
    corner."""
    margin = 20
    world = CAPTURES(name).crop(GAS_CROPS[name])
    factor = width / world.width
    if height:
        factor = min(factor, height / world.height)
    world = promo.scaled(world, factor)
    image = promo.canvas(height or world.height, width)
    left, top = (width - world.width) // 2, (image.height - world.height) // 2
    image.alpha_composite(world, (left, top))
    status = promo.scaled(CAPTURES(window), window_scale)
    x = left + margin if GAS_CORNERS[name] == "left" else left + world.width - margin - status.width
    promo.paste(image, status, (x + status.width / 2, top + margin + status.height / 2))
    return image


def wind():
    """The four wind chargers turning, cropped to a strip."""
    return promo.full_width(CAPTURES("wind")).crop(WIND_CROP)


def treadmill():
    """The character running on the treadmill wired to a battery box, at the images' width."""
    shot = CAPTURES("treadmill").crop(TREADMILL_CROP)
    return promo.scaled(shot, WIDTH / shot.width)


# What the poster's yard runs on, under the name.
POSTER_LINE = "Solar · Wind · Biogas · Wood gas"


# Gallery -----------------------------------------------------------------------------------------


def progression():
    """The setup's two shots, an arrow leading from the first battery box to the homestead, both as
    large as fit the page side by side, no larger than captured."""
    image = promo.canvas(PAGE[1], PAGE[0])
    shots = setup_shots()
    gap, margin = 72, 40
    factor = min(1, (PAGE[0] - gap - 2 * margin) / sum(shot.width for shot, _ in shots),
                 (PAGE[1] - 2 * margin) / max(shot.height for shot, _ in shots))
    shots = [(promo.scaled(shot, factor), label) for shot, label in shots]
    left = (PAGE[0] - sum(shot.width for shot, _ in shots) - gap) // 2
    for i, (shot, label) in enumerate(shots):
        top = (PAGE[1] - shot.height) // 2
        if i:
            promo.arrow(image, (left - gap / 2, PAGE[1] / 2), k=1.5)
        promo.paste(image, shot, (left + shot.width / 2, top + shot.height / 2))
        promo.caption(image, (left + 16, top + 16), label)
        left += shot.width + gap
    return image


def gallery():
    """The gallery's pictures in upload order, the hero first, each with its file's name."""
    page, shot_page = promo.page, promo.shot_page
    pictures = [
        ("hero", page(TAGLINE, promo.hero(CAPTURES("world"), TITLE))),
        ("progression", page("Start with a car battery in a box. End with a homestead.", progression())),
        ("bank", page("Every bank tells you what it's doing, panel by panel",
                      bank(PAGE[0], GALLERY_STATUS_SCALE, PAGE[1]))),
        ("biogas", page("Digesters turn manure into gas for the generator",
                        gas_shot("biogas", "digester", PAGE[0], GALLERY_GAS_WINDOW_SCALE, PAGE[1]))),
        ("woodgas", page("Gasifiers run a generator on wood. Mind the tar.",
                         gas_shot("woodgas", "gasifier", PAGE[0], GALLERY_GAS_WINDOW_SCALE, PAGE[1]))),
        ("wind", page("Wind chargers from scrap and a treadmill motor", shot_page(CAPTURES("wind")))),
        ("treadmill", page("No wind? Wire up the treadmill and run for it",
                           shot_page(CAPTURES("treadmill").crop(GALLERY_TREADMILL_CROP)))),
        ("gardenlights", page("Garden lights charge by day and glow after dark",
                              shot_page(CAPTURES("gardenlights")))),
        ("trailer", page("Road crews left their solar arrow boards running",
                         shot_page(CAPTURES("trailer").crop(GALLERY_TRAILER_CROP)))),
    ]
    pictures += ITEMS.pages(GALLERY_ITEMS, ITEM_K)
    pictures += RECIPES.pages(GALLERY_RECIPES, RECIPE_K)
    return pictures


def main():
    for name, make in [("banner", banner), ("setup", setup), ("bank", bank),
                       ("biogas", lambda: gas_shot("biogas", "digester")),
                       ("woodgas", lambda: gas_shot("woodgas", "gasifier")), ("wind", wind), ("treadmill", treadmill),
                       ("items", lambda: ITEMS.draw(columns=ITEM_COLUMNS)), ("recipes", RECIPES.draw),
                       ("trailer", trailer), ("gardenlights", gardenlights)]:
        promo.save(make(), IMAGES / f"{name}.png")
    promo.save_poster(promo.poster(CAPTURES("poster"), TITLE, POSTER_LINE, SOLAR), POSTER_FILES)
    promo.save_gallery(gallery(), GALLERY)


if __name__ == "__main__":
    main()
