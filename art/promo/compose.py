#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Lays out the README and Workshop images from the captures that extract.py saved. Rerun it after
editing a layout; recapture only when the game's look or the mod's names change:

    art/promo/compose.py

Writes images/{banner,setup,bank,items,recipes,trailer,gardenlights}.png, and the mod's poster,
Contents/mods/RenewableEnergy/42/poster.png, with the Workshop preview, preview.png. Every image is
1260 pixels wide, which the Workshop page shows at 630, so it stays sharp on high-density screens;
the poster and preview are 512 square. Icons are scaled by whole numbers with nearest-neighbour
sampling, so their pixels stay crisp. The item models are framed from the box extract.py found
around each. Item, recipe and skill names come from captures/promo.json, which the game wrote in
its own words; the setup captions are the README's.
Also writes gallery/NN-<name>.jpg, the Workshop's 1920x1080 screenshot gallery, in upload order.
"""
import json
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CAPTURES = HERE / "captures"
OUT = HERE / "images"
# The same picture serves as the mod list's poster and the Workshop preview.
POSTER_FILES = [REPO / "Contents/mods/RenewableEnergy/42/poster.png", REPO / "preview.png"]
# The Workshop takes a square preview of 256 or 512 pixels, at most this many bytes
# (SteamWorkshopItem.validatePreviewImage).
POSTER_SIZE = 512
PREVIEW_BYTES = 1_024_000
FONT = HERE / "fonts" / "NotoSans.ttf"
PROMO = json.loads((CAPTURES / "promo.json").read_text())

WIDTH = 1260
BACKGROUND = (24, 26, 31)
PANEL = (36, 39, 46)
TEXT = (232, 234, 238)
MUTED = (160, 166, 176)
SOLAR = (86, 140, 214)
FIRST_BOX = "A first battery box"
HOMESTEAD = "A homestead"
# Where each world shot is cropped, in capture pixels, around what the promo run built in it; a
# reshoot that frames a shot differently needs its box moved. The setup shots share a shape so
# that they line up side by side.
SETUP_CROPS = {"stage0": (330, 50, 1230, 812), "homestead": (260, 0, 1160, 762)}
BANK_CROP = (0, 180, 464, 592)
MENU_CROP = (206, 105, 726, 385)
TRAILER_CROP = (0, 140, 1260, 660)
# bank.png: the status window's size against its capture, as large as leaves room for the menu.
STATUS_SCALE = 1.25
# items.png: one row per kind of thing, with its caption, wrapped at ITEM_COLUMNS.
ITEM_ROWS = [
    ("Panels and mounts", ["RenewableEnergy.SolarModule", "RenewableEnergy.HomemadeSolarModule",
                           "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWallWood",
                           "RenewableEnergy.SolarWallMetal", "RenewableEnergy.SolarRackWood",
                           "RenewableEnergy.SolarRackMetal"]),
    ("Battery storage", ["RenewableEnergy.BatteryBoxWood", "RenewableEnergy.BatteryBoxMetal",
                         "RenewableEnergy.BatteryRackWood", "RenewableEnergy.BatteryRackMetal",
                         "RenewableEnergy.BatteryBankWood", "RenewableEnergy.BatteryBankMetal"]),
    ("Parts", ["RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter", "RenewableEnergy.InverterCharger",
               "RenewableEnergy.ChargeController", "RenewableEnergy.SolarFailsafe"]),
    ("Batteries and what rebuilds them", ["Base.CarBattery1", "RenewableEnergy.DeepCycleBattery",
                                          "RenewableEnergy.L16Battery", "RenewableEnergy.CarBatteryCase",
                                          "RenewableEnergy.DeepCycleBatteryCase", "RenewableEnergy.L16BatteryCase",
                                          "RenewableEnergy.WornBatteryPlates", "RenewableEnergy.BatteryPlates",
                                          "RenewableEnergy.WoodenBatteryPlatePattern",
                                          "RenewableEnergy.BatteryPlateMoldUnfired", "RenewableEnergy.BatteryPlateMold",
                                          "RenewableEnergy.BatteryElectrolyte"]),
    ("Gadgets, cells and magazines", ["RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger",
                                      "RenewableEnergy.SolarGardenLight", "RenewableEnergy.SolarCells",
                                      "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2"]),
]
ITEM_COLUMNS = 6
# recipes.png: the recipes by what they're for.
RECIPE_SECTIONS = [
    ("Battery storage", ["RenewableEnergy_MakeBatteryBoxWood", "RenewableEnergy_MakeBatteryBoxMetal",
                         "RenewableEnergy_BuildBatteryRackWood", "RenewableEnergy_BuildBatteryRackMetal",
                         "RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal"]),
    ("Panel mounts, and taking them down", ["RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWallWood",
                                            "RenewableEnergy_MakeSolarWallMetal", "RenewableEnergy_MakeSolarRackWood",
                                            "RenewableEnergy_MakeSolarRackMetal", "RenewableEnergy_UnmountSolarFlat",
                                            "RenewableEnergy_UnmountSolarWallWood",
                                            "RenewableEnergy_UnmountSolarWallMetal",
                                            "RenewableEnergy_UnmountSolarRackWood",
                                            "RenewableEnergy_UnmountSolarRackMetal"]),
    ("Modules: repair, homemade, and solar cells", ["RenewableEnergy_RepairCrackedModule",
                                                    "RenewableEnergy_MakeHomemadeSolarModule",
                                                    "RenewableEnergy_TakeApartCalculator",
                                                    "RenewableEnergy_TakeApartSolarGardenLight",
                                                    "RenewableEnergy_TakeApartSolarCellCharger",
                                                    "RenewableEnergy_TakeApartSolarMaintainer",
                                                    "RenewableEnergy_TakeApartShatteredModule"]),
    ("Battery care and rebuilding", ["RenewableEnergy_ServiceBattery", "RenewableEnergy_ReconditionBattery",
                                     "RenewableEnergy_StripCarBattery", "RenewableEnergy_StripDeepCycleBattery",
                                     "RenewableEnergy_StripL16Battery", "RenewableEnergy_MakeBatteryPlatePattern",
                                     "RenewableEnergy_PressBatteryPlateMold", "RenewableEnergy_FireBatteryPlateMold",
                                     "RenewableEnergy_RecastBatteryPlates", "RenewableEnergy_RebuildCarBattery",
                                     "RenewableEnergy_RebuildDeepCycleBattery", "RenewableEnergy_RebuildL16Battery"]),
    ("Electronics", ["RenewableEnergy_MakeChargeController", "RenewableEnergy_MakeSolarFailsafe"]),
]
# The result shown for a recipe whose OnCreate gives it, which no output line names. A recipe that
# improves an item it keeps shows that item.
RECIPE_RESULTS = {"RenewableEnergy_RebuildCarBattery": "Base.CarBattery1"}

GALLERY = HERE / "gallery"
# The Workshop's screenshot gallery shows pictures at 16:9 and enlarges one to its own size; each file
# must stay under a megabyte (ISteamUGC::AddItemPreviewFile).
GALLERY_SIZE = (1920, 1080)
GALLERY_BYTES = 1_000_000
# Every picture's caption sits centred in a band across its top, the same on every mod's gallery;
# PAGE is what's left below it.
CAPTION_BAND = 150
CAPTION_SIZE = 60
PAGE = (GALLERY_SIZE[0], GALLERY_SIZE[1] - CAPTION_BAND)
# The world shots go in at their captured size, which keeps their pixels; the trailer's crop is the
# garden lights' height, around the trailer and the cones behind it.
GALLERY_TRAILER_CROP = (0, 32, 1260, 944)
# The bank's status window, as large as leaves the room and its menu as tall beside it.
GALLERY_STATUS_SCALE = 1.94
# The item and recipe sheets drawn this many times the README's size: as large as the fullest page
# allows, which keeps their smallest text at 18 and 16 pixels.
ITEM_K = 1.1
RECIPE_K = 1.33
# The item sheet over two pictures, with how many cards to a line on each.
GALLERY_ITEMS = [
    ("items-power", "Panels to mount, banks to fill, parts to wire in", ITEM_ROWS[:3], 7),
    ("items-batteries", "Batteries to rebuild, gadgets to take apart", ITEM_ROWS[3:], 6),
]
# The recipe sheet over as few pictures as its cards fit at RECIPE_K: for each picture, the
# sections it shows by title, and which of each section's recipes.
MOUNTS, CARE = "Panel mounts, and taking them down", "Battery care and rebuilding"
GALLERY_RECIPES = [
    ("recipes-storage", "Recipes: battery boxes, racks and banks", [("Battery storage", slice(None))]),
    ("recipes-mounts", "Recipes: building panel mounts", [(MOUNTS, slice(0, 5))]),
    ("recipes-unmounting-electronics", "Recipes: taking panels down, and electronics",
     [(MOUNTS, slice(5, None)), ("Electronics", slice(None))]),
    ("recipes-modules", "Recipes: modules and solar cells", [("Modules: repair, homemade, and solar cells",
                                                              slice(None))]),
    ("recipes-battery-care", "Recipes: servicing and stripping batteries", [(CARE, slice(0, 5))]),
    ("recipes-rebuilding", "Recipes: casting plates, rebuilding batteries", [(CARE, slice(5, None))]),
]


def font(size, weight="Regular"):
    face = ImageFont.truetype(str(FONT), size)
    face.set_variation_by_name(weight)
    return face


def capture(name):
    return Image.open(CAPTURES / f"{name}.png").convert("RGBA")


def full_width(name):
    """A world capture at the images' width; on a high-density display it comes out larger."""
    image = capture(name)
    if image.width != WIDTH:
        image = image.resize((WIDTH, round(image.height * WIDTH / image.width)), Image.LANCZOS)
    return image


def icon_key(full_type):
    return "icon_" + full_type.replace(".", "_")


def pixels(image, factor):
    return image.resize((image.width * factor, image.height * factor), Image.NEAREST)


def icon(key, size):
    """An icon scaled by the largest whole number that keeps it within size."""
    image = capture(key)
    return pixels(image, max(1, size // max(image.size)))


def canvas(height, width=WIDTH):
    """A dark card with a faint vertical gradient."""
    image = Image.new("RGBA", (width, height), BACKGROUND + (255,))
    shade = Image.linear_gradient("L").resize((width, height)).point(lambda v: v * 0.35)
    image.paste(Image.new("RGBA", (width, height), (12, 13, 16, 255)), (0, 0), shade)
    return image


def sized(n, k):
    """n pixels of a README layout drawn k times its size, for the gallery's larger pages."""
    return round(n * k)


def paste(base, image, centre, shadow=True):
    """Pastes image centred on centre, over a soft shadow of itself."""
    x, y = round(centre[0] - image.width / 2), round(centre[1] - image.height / 2)
    if shadow:
        alpha = image.getchannel("A").point(lambda a: a * 0.6)
        blur = Image.new("RGBA", (image.width + 40, image.height + 40), (0, 0, 0, 0))
        blur.paste(Image.new("RGBA", image.size, (0, 0, 0, 255)), (20, 20), alpha)
        blur = blur.filter(ImageFilter.GaussianBlur(10))
        base.alpha_composite(blur, (x - 20 + 4, y - 20 + 8))
    base.alpha_composite(image, (x, y))


def wrap(string, face, width, split_words=False):
    """Splits string into lines no wider than width, breaking at spaces, and with split_words also
    after the hyphens and slashes of a word too wide for a line of its own."""
    lines = []
    for word in string.split():
        parts = [word]
        if split_words and face.getlength(word) > width:
            parts = [part for part in re.split(r"(?<=[-/])", word) if part]
        for i, part in enumerate(parts):
            joined = lines[-1] + ("" if i else " ") + part if lines else None
            if joined and face.getlength(joined) <= width:
                lines[-1] = joined
            else:
                lines.append(part)
    return "\n".join(lines)


def text(base, xy, string, size, weight="Regular", fill=TEXT, anchor="la", width=None):
    face = font(size, weight)
    if width:
        string = wrap(string, face, width)
    ImageDraw.Draw(base).multiline_text(xy, string, font=face, fill=fill, anchor=anchor,
                                        align="center" if anchor[0] == "m" else "left", spacing=3)
    return ImageDraw.Draw(base).multiline_textbbox(xy, string, font=face, anchor=anchor, spacing=3)


def panel(base, box, accent=None, k=1):
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle(box, sized(18, k), fill=PANEL + (255,))
    if accent:
        draw.rectangle((box[0] + sized(28, k), box[1], box[2] - sized(28, k), box[1] + sized(5, k)),
                       fill=accent + (255,))


def badge(base, xy, string, k=1):
    """A small pill with string in it, its top right corner at xy."""
    face = font(sized(16, k), "Bold")
    w = face.getlength(string) + sized(14, k)
    box = (xy[0] - w, xy[1], xy[0], xy[1] + sized(22, k))
    ImageDraw.Draw(base).rounded_rectangle(box, sized(11, k), fill=(14, 15, 18, 235))
    ImageDraw.Draw(base).text(((box[0] + box[2]) / 2, box[1] + sized(11, k)), string, font=face, fill=TEXT,
                              anchor="mm")


def caption(base, xy, string):
    """A dark pill with a caption in it, its top left corner at xy, to sit on a world capture."""
    face = font(24, "SemiBold")
    w = face.getlength(string) + 36
    box = (xy[0], xy[1], xy[0] + w, xy[1] + 44)
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle(box, 22, fill=(12, 13, 16, 215))
    base.alpha_composite(overlay)
    ImageDraw.Draw(base).text((box[0] + 18, box[1] + 22), string, font=face, fill=TEXT, anchor="lm")


def arrow(base, centre, colour=MUTED, k=1):
    x, y = centre
    draw = ImageDraw.Draw(base)
    draw.rectangle((x - sized(22, k), y - sized(4, k), x + sized(6, k), y + sized(4, k)), fill=colour)
    draw.polygon([(x + sized(4, k), y - sized(14, k)), (x + sized(22, k), y), (x + sized(4, k), y + sized(14, k))],
                 fill=colour)


def save(image, name):
    OUT.mkdir(exist_ok=True)
    image.convert("RGB").save(OUT / f"{name}.png", optimize=True)
    print(f"compose: images/{name}.png {image.width}x{image.height}")


# Images ------------------------------------------------------------------------------------------


def mod_title(image, size):
    """The mod's name over the world capture's left side, darkened behind it and clear by the
    middle, where the homestead starts. Returns the name's box."""
    shade = Image.linear_gradient("L").rotate(90, expand=True).resize(image.size)
    shade = shade.point(lambda v: max(0, min(235, round((140 - v) * 3.3))))
    image.paste(Image.new("RGBA", image.size, (12, 13, 16, 255)), (0, 0), shade)
    title = "\n".join(PROMO["strings"]["modName"].split())
    xy = (round(size * 5 / 7), image.height / 2 - round(size * 5 / 21))
    face = font(size, "Bold")
    ImageDraw.Draw(image).multiline_text(xy, title, font=face, fill=TEXT, anchor="lm", spacing=round(size / 14))
    return ImageDraw.Draw(image).multiline_textbbox(xy, title, font=face, anchor="lm", spacing=round(size / 14))


def banner():
    """The mod's name over the homestead, which the world capture holds against its right edge."""
    image = full_width("world")
    box = mod_title(image, 84)
    text(image, (64, box[3] + 22), "Off-grid power, 1993", 30, "Medium", MUTED)
    return image


def scaled(image, factor):
    """image scaled by factor, through a whole-number nearest-neighbour enlargement first when it
    grows, which keeps captured UI text sharper than scaling straight to it."""
    if factor > 1:
        image = pixels(image, math.ceil(factor * 2))
        factor /= math.ceil(factor * 2)
    return image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)


def setup():
    """The first battery box and the homestead side by side, each under its caption. Each shot is
    cropped to SETUP_CROPS around what was built, then both are scaled to share the width."""
    gap = 12
    width = (WIDTH - gap) // 2
    shots = []
    for name, label in [("stage0", FIRST_BOX), ("homestead", HOMESTEAD)]:
        crop = capture(name).crop(SETUP_CROPS[name])
        shots.append((scaled(crop, width / crop.width), label))
    image = canvas(max(shot.height for shot, _ in shots))
    for i, (shot, label) in enumerate(shots):
        left = i * (width + gap)
        image.alpha_composite(shot, (left, 0))
        caption(image, (left + 16, 16), label)
    return image


def bank(width=WIDTH, status_scale=STATUS_SCALE, height=None):
    """The homestead's bank indoors over its right-click menu, beside its status window, centred
    in height if given. The menu's text is drawn larger than the status window's, so it is scaled
    down to about the same size, and cropped to the bank's own submenu and Wire In."""
    margin, gap = 20, 16
    status = scaled(capture("status"), status_scale)
    column = width - 2 * margin - gap - status.width
    menu = capture("menu").crop(MENU_CROP)
    menu = scaled(menu, column / menu.width)
    room = capture("bank").crop(BANK_CROP).convert("RGBA")
    room = scaled(room, column / room.width)
    inner = max(status.height, room.height + gap + menu.height)
    image = canvas(height or inner + 2 * margin, width)
    top = (image.height - inner) // 2
    assert top >= margin, "the bank's status window and menu are too tall for the page"
    paste(image, room, (margin + column / 2, top + room.height / 2))
    paste(image, menu, (margin + column / 2, top + room.height + gap + menu.height / 2))
    paste(image, status, (width - margin - status.width / 2, top + inner / 2))
    return image


# items.png: each card is the item's model as it lies on the ground, with MODEL_PADDING of its size
# around it and no taller than MODEL_H, over its inventory icon and its name side by side.
MODEL_PADDING = 0.12
MODEL_H = 120
ITEM_PAD = 8
ICON = 64
NAME_SIZE = 16


def on_floor(image, item_box, margin):
    """image on a canvas margin wider on every side, the extra laid with tiles of the bare floor
    above the item, so that a frame can run past the capture's edges."""
    tile = image.crop((0, 0, image.width, item_box[1]))
    floor = Image.new("RGB", (image.width + 2 * margin, image.height + 2 * margin))
    for y in range(0, floor.height, tile.height):
        for x in range(0, floor.width, tile.width):
            floor.paste(tile, (x, y))
    floor.paste(image, (margin, margin))
    return floor


def framed_model(key, item_box, size):
    """The model capture around the item's box, with MODEL_PADDING on every side, scaled to fit
    inside size and centred in it."""
    image = capture(key).convert("RGB")
    left, top, right, bottom = item_box
    scale = min(size[0] / ((right - left) * (1 + 2 * MODEL_PADDING)),
                size[1] / ((bottom - top) * (1 + 2 * MODEL_PADDING)))
    w, h = size[0] / scale, size[1] / scale
    x, y = (left + right - w) / 2, (top + bottom - h) / 2
    margin = math.ceil(max(0, -x, -y, x + w - image.width, y + h - image.height))
    if margin:
        image = on_floor(image, item_box, margin)
    return image.resize(size, Image.LANCZOS, box=(x + margin, y + margin, x + margin + w, y + margin + h))


def name_block(name, width, k=1):
    """The item's name wrapped to width, and how tall it stands."""
    face = font(sized(NAME_SIZE, k), "SemiBold")
    wrapped = wrap(name, face, width, split_words=True)
    box = ImageDraw.Draw(Image.new("L", (1, 1))).multiline_textbbox((0, 0), wrapped, font=face, spacing=3)
    assert box[2] <= width, f"{name} is too wide for its card"
    return wrapped, box[3]


def item_card(image, full_type, name, box, boxes, k=1):
    """The item's model over its icon and its name, name being name_block's."""
    pad, icon_size, model_h = sized(ITEM_PAD, k), sized(ICON, k), sized(MODEL_H, k)
    left, top = round(box[0]) + pad, box[1] + pad
    size = (round(box[2]) - pad - left, model_h)
    key = "model_" + full_type.replace(".", "_")
    picture = framed_model(key, boxes[key], size).convert("RGBA")
    corners = Image.new("L", size, 0)
    ImageDraw.Draw(corners).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), sized(12, k), fill=255)
    image.paste(picture, (left, top), corners)
    row = top + model_h + pad
    paste(image, icon(icon_key(full_type), icon_size), (left + icon_size / 2, row + icon_size / 2), shadow=False)
    wrapped, height = name
    text(image, (left + icon_size + pad, row + max(0, (icon_size - height) / 2)), wrapped, sized(NAME_SIZE, k),
         "SemiBold")


def items():
    names = {item["fullType"] for item in PROMO["items"]}
    missing = names - {full_type for _, full_types in ITEM_ROWS for full_type in full_types}
    assert not missing, f"items.png has no place for {sorted(missing)}"
    return item_sheet(ITEM_ROWS)


def item_sheet(rows, width=WIDTH, columns=ITEM_COLUMNS, k=1, height=None):
    """Every item in rows, each kind under its caption, each line of cards as tall as its longest
    name needs, drawn k times the README's size and centred in height if given."""
    names = {item["fullType"]: item["name"] for item in PROMO["items"]}
    boxes = {model["name"]: model["box"] for model in PROMO["models"]}
    pad, icon_size, inset = sized(ITEM_PAD, k), sized(ICON, k), sized(6, k)
    column = (width - 20) // columns
    name_width = column - 2 * inset - 3 * pad - icon_size
    heading, gap = sized(44, k), sized(12, k)
    sections = []
    for title, full_types in rows:
        lines = []
        for start in range(0, len(full_types), columns):
            cards = [(full_type, name_block(names[full_type], name_width, k))
                     for full_type in full_types[start:start + columns]]
            line_height = 3 * pad + sized(MODEL_H, k) + max(icon_size, *(name[1] for _, name in cards))
            lines.append((cards, line_height))
        sections.append((title, lines))
    needed = 20 + heading * len(sections) + sum(h + gap for _, lines in sections for _, h in lines)
    image = canvas(height or needed, width)
    assert needed <= image.height, f"{rows[0][0]} and the rest are too tall for the page"
    top = 20 + (image.height - needed) // 2
    for title, lines in sections:
        text(image, (30, top + heading / 2), title, sized(22, k), "SemiBold", MUTED, "lm")
        top += heading
        for cards, line_height in lines:
            left0 = (width - column * len(cards)) / 2
            for c, (full_type, name) in enumerate(cards):
                left = left0 + c * column
                box = (left + inset, top, left + column - inset, top + line_height)
                panel(image, box, k=k)
                item_card(image, full_type, name, box, boxes, k)
            top += line_height + gap
    return image


def trailer():
    """The arrow board trailer and the car towing it, cropped to a strip."""
    return full_width("trailer").crop(TRAILER_CROP)


def gardenlights():
    return full_width("gardenlights")


def poster():
    """The lit house at night under the mod's name, in the banner's type. The name is set large
    enough to read where Steam shows the preview smallest, about 196 pixels across."""
    image = capture("poster").resize((POSTER_SIZE, POSTER_SIZE), Image.LANCZOS)
    # Dark from the house's yard down, behind the title; the night above stays as it was shot.
    shade = Image.linear_gradient("L").resize(image.size)
    shade = shade.point(lambda v: round(210 * min(1, max(0, (v / 255 - 0.55) / 0.45)) ** 0.8))
    image.paste(Image.new("RGBA", image.size, (12, 13, 16, 255)), (0, 0), shade)
    title = "\n".join(PROMO["strings"]["modName"].split())
    ImageDraw.Draw(image).multiline_text((30, POSTER_SIZE - 30), title, font=font(68, "Bold"), fill=TEXT,
                                         anchor="ld", spacing=4)
    return image


def save_poster(image):
    for path in POSTER_FILES:
        image.convert("RGB").save(path, optimize=True)
        assert path.stat().st_size <= PREVIEW_BYTES, f"{path.name} is over the Workshop's {PREVIEW_BYTES} bytes"
        print(f"compose: {path.relative_to(REPO)} {image.width}x{image.height}")


# Recipe cards: the recipe's name, skills, how it's learned and its tools in a column on the left,
# then a slot per input, an arrow and a slot per result. Cards share a row wherever they fit, and
# each row is as tall as its tallest card's contents.
CARD_GAP = 12
CARD_PAD = 16
NAME_W = 168
SLOT = 72
ARROW_W = 30


def unique_names(items):
    """The items, dropping any whose name an earlier one already shows."""
    seen, kept = set(), []
    for item in items:
        if item["name"] not in seen:
            seen.add(item["name"])
            kept.append(item)
    return kept


def alternatives(items):
    """What else an input line takes instead of its first item: "or Glue", or "or 4 more"."""
    others = unique_names(items)[1:]
    if not others:
        return ""
    return f"or {others[0]['name']}" if len(others) == 1 else f"or {len(others)} more"


def recipe_parts(recipe, items_by_type):
    """The recipe's tools, by name, and its inputs and results as slots, { item, count, uses,
    others, fluid, litres }. Tools are what it keeps without working on. Lines that take the same
    fluid from the same container make one slot, lines that pour a fluid into an empty container
    are results, and a recipe without an output line shows what it gives back: its RECIPE_RESULTS
    entry, or the item it keeps and works on."""
    no_output = not recipe["outputs"] and not any(entry.get("fills") for entry in recipe["inputs"])
    subject = None
    if no_output and recipe["id"] not in RECIPE_RESULTS:
        subject = next((e for e in recipe["inputs"] if e["keep"] and not e["tag"] and not e.get("fluid")), None)
        assert subject, f"{recipe['id']} has no output and keeps nothing it works on: add it to RECIPE_RESULTS"
    tools, inputs, results = [], [], []
    for entry in recipe["inputs"]:
        fluid = entry.get("fluid") or entry.get("fills")
        item = entry["items"][0]
        if fluid:
            target = results if entry.get("fills") else inputs
            last = target[-1] if target else None
            if last and last.get("fluid") == fluid["name"] and last["item"]["icon"] == item["icon"]:
                last["litres"] += fluid["litres"]
            else:
                target.append({"item": item, "fluid": fluid["name"], "litres": fluid["litres"]})
        elif entry["keep"] and entry is not subject:
            tools.append(" ".join(filter(None, [item["name"], alternatives(entry["items"])])))
        else:
            inputs.append({"item": item, "count": item.get("count") or entry["count"], "uses": entry["uses"],
                           "others": alternatives(entry["items"])})
    if no_output:
        given = RECIPE_RESULTS.get(recipe["id"])
        results.insert(0, {"item": items_by_type[given] if given else subject["items"][0]})
    outputs = [{"item": item, "count": item["count"]} for item in recipe["outputs"]]
    return tools, inputs, outputs + results


def slot_caption(slot):
    """What goes under an item's name: the fluid it holds or the uses of a drainable item it takes,
    and what else the line takes instead."""
    words = []
    if slot.get("fluid"):
        words.append(f"{slot['litres']:g} L {slot['fluid']}")
    elif slot.get("uses"):
        words.append(f"{slot['count']} uses")
    if slot.get("others"):
        words.append(slot["others"])
    return ", ".join(words)


def draw_slot(base, slot, x, top, k=1):
    """A slot's icon centred on x with its name below, a badge with how many whole items, and a
    caption. Returns the bottom of what it drew."""
    item, count = slot["item"], slot.get("count")
    slot_w = sized(SLOT, k)
    paste(base, icon(item["icon"], sized(64, k)), (x, top + sized(46, k)), shadow=False)
    if count and count > 1 and not slot.get("uses"):
        badge(base, (x + sized(38, k), top + sized(10, k)), f"×{count}", k)
    box = text(base, (x, top + sized(84, k)), item["name"], sized(13, k), "Medium", TEXT, "ma",
               width=slot_w - sized(6, k))
    caption_text = slot_caption(slot)
    if caption_text:
        box = text(base, (x, box[3] + sized(3, k)), caption_text, sized(12, k), "Medium", MUTED, "ma",
                   width=slot_w - sized(4, k))
    return box[3]


def card_width(parts, k=1):
    _, inputs, results = parts
    return (2 * sized(CARD_PAD, k) + sized(NAME_W, k) + sized(14, k) + (len(inputs) + len(results)) * sized(SLOT, k)
            + sized(ARROW_W, k))


def learn_line(recipe):
    """How the recipe is learned: the magazines that teach it, the items whose research teaches
    it, among them often its own result, and the skill level at which a character works it out
    alone."""
    learn = recipe["learn"]
    if not learn["needed"]:
        return "No need to learn it"
    ways = []
    if learn["magazines"]:
        ways.append("from " + ", or ".join(name.split(":")[0] for name in learn["magazines"]))
    results = {item["name"] for item in recipe["outputs"]}
    research = [name for name in learn["research"] if name not in results]
    if len(research) < len(learn["research"]):
        research.append("what it makes")
    if research:
        ways.append("by researching " + " or ".join(research))
    ways += [f"at {s['name']} {s['level']}" for s in learn["auto"]]
    return "Learn " + ", or ".join(ways)


def recipe_card(base, recipe, parts, box, k=1):
    """Draws the card into box and returns how far down its contents reach."""
    left, top, right, bottom = box
    panel(base, box, SOLAR, k)
    tools, inputs, results = parts
    pad, name_w, slot_w, arrow_w = sized(CARD_PAD, k), sized(NAME_W, k), sized(SLOT, k), sized(ARROW_W, k)
    x = left + pad
    lines = text(base, (x, top + sized(16, k)), recipe["name"], sized(17, k), "Bold", width=name_w)
    skills = "  ·  ".join(f"{s['name']} {s['level']}" for s in recipe["skills"])
    for line, size in [(skills, 13), (learn_line(recipe), 12), ("Tools: " + ", ".join(tools) if tools else "", 12)]:
        if line:
            lines = text(base, (x, lines[3] + sized(6, k)), line, sized(size, k), "Medium", MUTED, width=name_w)
    lowest = lines[3]
    x = left + pad + name_w + sized(14, k) + slot_w / 2
    for slot in inputs:
        lowest = max(lowest, draw_slot(base, slot, x, top, k))
        x += slot_w
    arrow(base, (x - slot_w / 2 + arrow_w / 2, top + sized(46, k)), k=k)
    x += arrow_w
    for slot in results:
        lowest = max(lowest, draw_slot(base, slot, x, top, k))
        x += slot_w
    assert lowest <= bottom - sized(10, k), f"{recipe['id']} runs past the bottom of its card"
    assert x - slot_w / 2 <= right - pad + 1, f"{recipe['id']} is too wide for its card"
    return lowest


def card_height(recipe, parts, width, k=1):
    """How tall the card must be to hold its contents, found by drawing it on a scratch image."""
    scratch = Image.new("RGBA", (width, sized(1000, k)))
    return round(recipe_card(scratch, recipe, parts, (0, 0, width, sized(1000, k)), k)) + sized(CARD_PAD, k)


def first_fit(cards, row_w, gap):
    """Packs (order, (recipe, parts, width)) pairs into rows as wide as row_w, each into the first
    row with room for it, and returns the rows and the cards in each in their order."""
    rows = []
    for order, card in cards:
        assert card[2] <= row_w, f"{card[0]['id']} is too wide for the image"
        row = next((row for row in rows if row[1] + gap + card[2] <= row_w), None)
        if row:
            row[0].append((order, card))
            row[1] += gap + card[2]
        else:
            rows.append([[(order, card)], card[2]])
    return [[card for _, card in sorted(row)] for row, _ in sorted(rows, key=lambda row: min(row[0]))]


def card_rows(cards, row_w, gap):
    """The section's cards in rows, in the section's order unless packing the widest first takes
    fewer rows."""
    in_order = first_fit(list(enumerate(cards)), row_w, gap)
    widest_first = first_fit(sorted(enumerate(cards), key=lambda pair: -pair[1][2]), row_w, gap)
    return widest_first if len(widest_first) < len(in_order) else in_order


def recipes():
    placed = [i for _, ids in RECIPE_SECTIONS for i in ids]
    game = [r["id"] for r in PROMO["recipes"]]
    assert sorted(placed) == sorted(game), f"recipes.png places {sorted(placed)}, the game has {sorted(game)}"
    return recipe_sheet(RECIPE_SECTIONS)


def recipe_sheet(sections, width=WIDTH, k=1, height=None):
    """The sections' recipe cards, each section under its title unless that is None, drawn k times
    the README's size and centred in height if given."""
    by_id = {r["id"]: r for r in PROMO["recipes"]}
    items_by_type = {item["fullType"]: item for item in PROMO["items"]}
    row_w, gap = width - 40, sized(CARD_GAP, k)
    laid = []
    for title, ids in sections:
        cards = []
        for i in ids:
            parts = recipe_parts(by_id[i], items_by_type)
            cards.append((by_id[i], parts, card_width(parts, k)))
        laid.append((title, card_rows(cards, row_w, gap)))
    heading = sized(52, k)
    heights = [[max(card_height(*card, k) for card in row) for row in rows] for _, rows in laid]
    needed = 20 + sum(heading for title, _ in laid if title) + sum(h + gap for hs in heights for h in hs)
    image = canvas(height or needed, width)
    assert needed <= image.height, f"the recipes from {sections[0][1][0]} on are too tall for the page"
    top = 20 + (image.height - needed) // 2
    for (title, rows), row_heights in zip(laid, heights):
        if title:
            text(image, (30, top + heading / 2), title, sized(22, k), "SemiBold", MUTED, "lm")
            top += heading
        for row, row_height in zip(rows, row_heights):
            # The row's spare width goes to its cards evenly, so every row spans the image.
            spare = (row_w - sum(card[2] for card in row) - gap * (len(row) - 1)) / len(row)
            left = 20
            for recipe, parts, card_w in row:
                recipe_card(image, recipe, parts, (left, top, left + card_w + spare, top + row_height), k)
                left += card_w + spare + gap
            top += row_height + gap
    return image


# Gallery -----------------------------------------------------------------------------------------


def page(caption_text, content):
    """A gallery picture: its caption in the band across the top, over content the size of PAGE."""
    assert content.size == PAGE, f"{caption_text!r} has a page of {content.size}"
    image = Image.new("RGBA", GALLERY_SIZE, BACKGROUND + (255,))
    image.alpha_composite(content, (0, CAPTION_BAND))
    face = font(CAPTION_SIZE, "Bold")
    assert face.getlength(caption_text) <= GALLERY_SIZE[0] - 120, f"{caption_text!r} is too wide for the band"
    ImageDraw.Draw(image).text((GALLERY_SIZE[0] / 2, CAPTION_BAND / 2), caption_text, font=face, fill=TEXT,
                               anchor="mm")
    return image


def hero():
    """The banner at 16:9: the world capture across the page's width, standing on its foot, under the
    mod's name."""
    shot = capture("world")
    shot = scaled(shot, PAGE[0] / shot.width)
    mod_title(shot, 132)
    image = canvas(PAGE[1], PAGE[0])
    image.alpha_composite(shot, (0, PAGE[1] - shot.height))
    return image


def progression():
    """The setup's two shots at their captured size, an arrow leading from the first battery box to
    the homestead."""
    image = canvas(PAGE[1], PAGE[0])
    shots = [(capture(name).crop(SETUP_CROPS[name]), label) for name, label in [("stage0", FIRST_BOX),
                                                                                ("homestead", HOMESTEAD)]]
    gap = 72
    left = (PAGE[0] - sum(shot.width for shot, _ in shots) - gap) // 2
    for i, (shot, label) in enumerate(shots):
        top = (PAGE[1] - shot.height) // 2
        if i:
            arrow(image, (left - gap / 2, PAGE[1] / 2), k=1.5)
        paste(image, shot, (left + shot.width / 2, top + shot.height / 2))
        caption(image, (left + 16, top + 16), label)
        left += shot.width + gap
    return image


def shot_page(shot):
    """A world capture at its captured size, centred on the page."""
    assert shot.height <= PAGE[1] and shot.width <= PAGE[0], "the shot is larger than the page"
    image = canvas(PAGE[1], PAGE[0])
    paste(image, shot, (PAGE[0] / 2, PAGE[1] / 2))
    return image


def gallery():
    """The gallery's pictures in upload order, the hero first, each with its file's name."""
    by_title = dict(RECIPE_SECTIONS)
    recipe_pages = [(name, caption_text, [(None, by_title[title][part]) for title, part in parts])
                    for name, caption_text, parts in GALLERY_RECIPES]
    shown = sorted(i for _, _, sections in recipe_pages for _, ids in sections for i in ids)
    assert shown == sorted(i for _, ids in RECIPE_SECTIONS for i in ids), "the gallery must show every recipe once"
    assert [row for _, _, rows, _ in GALLERY_ITEMS for row in rows] == ITEM_ROWS, "the gallery must show every item"
    pictures = [
        ("hero", page("Off-grid power, 1993", hero())),
        ("progression", page("Start with a car battery in a box. End with a homestead.", progression())),
        ("bank", page("Every bank tells you what it's doing, panel by panel",
                      bank(PAGE[0], GALLERY_STATUS_SCALE, PAGE[1]))),
        ("gardenlights", page("Garden lights charge by day and glow after dark", shot_page(capture("gardenlights")))),
        ("trailer", page("Road crews left their solar arrow boards running",
                         shot_page(capture("trailer").crop(GALLERY_TRAILER_CROP)))),
    ]
    pictures += [(name, page(caption_text, item_sheet(rows, PAGE[0], columns, ITEM_K, PAGE[1])))
                 for name, caption_text, rows, columns in GALLERY_ITEMS]
    pictures += [(name, page(caption_text, recipe_sheet(sections, PAGE[0], RECIPE_K, PAGE[1])))
                 for name, caption_text, sections in recipe_pages]
    return pictures


def save_gallery(pictures):
    """Writes the pictures as NN-<name>.jpg, numbered in upload order, and deletes anything else in
    the folder, since the whole folder is uploaded."""
    GALLERY.mkdir(exist_ok=True)
    written = set()
    for number, (name, picture) in enumerate(pictures, 1):
        path = GALLERY / f"{number:02d}-{name}.jpg"
        # Full-resolution colour keeps the captions' and icons' edges clean.
        picture.convert("RGB").save(path, quality=90, subsampling=0, optimize=True)
        assert path.stat().st_size < GALLERY_BYTES, f"{path.name} is over the Workshop's {GALLERY_BYTES} bytes"
        written.add(path)
        print(f"compose: gallery/{path.name} {picture.width}x{picture.height} {path.stat().st_size} bytes")
    for path in GALLERY.iterdir():
        if path not in written:
            path.unlink()


def main():
    for name, make in [("banner", banner), ("setup", setup), ("bank", bank), ("items", items),
                       ("recipes", recipes), ("trailer", trailer), ("gardenlights", gardenlights)]:
        save(make(), name)
    save_poster(poster())
    save_gallery(gallery())


if __name__ == "__main__":
    main()
