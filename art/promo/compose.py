#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Lays out the README and Workshop images from the captures that extract.py saved. Rerun it after
editing a layout; recapture only when the game's look or the mod's names change:

    art/promo/compose.py

Writes images/{banner,setup,bank,items,recipes,trailer,gardenlights}.png. Every image is 1260 pixels
wide, which the Workshop page shows at 630, so it stays sharp on high-density screens. Icons are
scaled by whole numbers with nearest-neighbour sampling, so their pixels stay crisp. The item models
are framed from the box extract.py found around each. Item, recipe and skill names come from
captures/promo.json, which the game wrote in its own words; the setup captions are the README's.
"""
import json
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
CAPTURES = HERE / "captures"
OUT = HERE / "images"
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


def canvas(height):
    """A dark card with a faint vertical gradient."""
    image = Image.new("RGBA", (WIDTH, height), BACKGROUND + (255,))
    shade = Image.linear_gradient("L").resize((WIDTH, height)).point(lambda v: v * 0.35)
    image.paste(Image.new("RGBA", (WIDTH, height), (12, 13, 16, 255)), (0, 0), shade)
    return image


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


def panel(base, box, accent=None):
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle(box, 18, fill=PANEL + (255,))
    if accent:
        draw.rectangle((box[0] + 28, box[1], box[2] - 28, box[1] + 5), fill=accent + (255,))


def badge(base, xy, string):
    """A small pill with string in it, its top right corner at xy."""
    face = font(16, "Bold")
    w = face.getlength(string) + 14
    box = (xy[0] - w, xy[1], xy[0], xy[1] + 22)
    ImageDraw.Draw(base).rounded_rectangle(box, 11, fill=(14, 15, 18, 235))
    ImageDraw.Draw(base).text(((box[0] + box[2]) / 2, box[1] + 11), string, font=face, fill=TEXT, anchor="mm")


def caption(base, xy, string):
    """A dark pill with a caption in it, its top left corner at xy, to sit on a world capture."""
    face = font(24, "SemiBold")
    w = face.getlength(string) + 36
    box = (xy[0], xy[1], xy[0] + w, xy[1] + 44)
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle(box, 22, fill=(12, 13, 16, 215))
    base.alpha_composite(overlay)
    ImageDraw.Draw(base).text((box[0] + 18, box[1] + 22), string, font=face, fill=TEXT, anchor="lm")


def arrow(base, centre, colour=MUTED):
    x, y = centre
    draw = ImageDraw.Draw(base)
    draw.rectangle((x - 22, y - 4, x + 6, y + 4), fill=colour)
    draw.polygon([(x + 4, y - 14), (x + 22, y), (x + 4, y + 14)], fill=colour)


def save(image, name):
    OUT.mkdir(exist_ok=True)
    image.convert("RGB").save(OUT / f"{name}.png", optimize=True)
    print(f"compose: images/{name}.png {image.width}x{image.height}")


# Images ------------------------------------------------------------------------------------------


def banner():
    """The mod's name over the homestead, which the world capture holds against its right edge."""
    image = full_width("world")
    # Dark behind the title on the left, clear by the middle, where the homestead starts.
    shade = Image.linear_gradient("L").rotate(90, expand=True).resize(image.size)
    shade = shade.point(lambda v: max(0, min(235, round((140 - v) * 3.3))))
    image.paste(Image.new("RGBA", image.size, (12, 13, 16, 255)), (0, 0), shade)
    title = "\n".join(PROMO["strings"]["modName"].split())
    box = ImageDraw.Draw(image).multiline_textbbox((60, image.height / 2 - 20), title, font=font(84, "Bold"),
                                                   anchor="lm", spacing=6)
    ImageDraw.Draw(image).multiline_text((60, image.height / 2 - 20), title, font=font(84, "Bold"), fill=TEXT,
                                         anchor="lm", spacing=6)
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


def bank():
    """The homestead's bank indoors over its right-click menu, beside its status window. The
    menu's text is drawn larger than the status window's, so it is scaled down to about the same
    size, and cropped to the bank's own submenu and Wire In."""
    margin, gap = 20, 16
    status = scaled(capture("status"), STATUS_SCALE)
    column = WIDTH - 2 * margin - gap - status.width
    menu = capture("menu").crop(MENU_CROP)
    menu = scaled(menu, column / menu.width)
    room = capture("bank").crop(BANK_CROP).convert("RGBA")
    room = scaled(room, column / room.width)
    height = max(status.height, room.height + gap + menu.height)
    image = canvas(height + 2 * margin)
    paste(image, room, (margin + column / 2, margin + room.height / 2))
    paste(image, menu, (margin + column / 2, margin + room.height + gap + menu.height / 2))
    paste(image, status, (WIDTH - margin - status.width / 2, margin + height / 2))
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


def name_block(name, width):
    """The item's name wrapped to width, and how tall it stands."""
    face = font(NAME_SIZE, "SemiBold")
    wrapped = wrap(name, face, width, split_words=True)
    box = ImageDraw.Draw(Image.new("L", (1, 1))).multiline_textbbox((0, 0), wrapped, font=face, spacing=3)
    assert box[2] <= width, f"{name} is too wide for its card"
    return wrapped, box[3]


def item_card(image, full_type, name, box, boxes):
    """The item's model over its icon and its name, name being name_block's."""
    left, top = round(box[0]) + ITEM_PAD, box[1] + ITEM_PAD
    size = (round(box[2]) - ITEM_PAD - left, MODEL_H)
    key = "model_" + full_type.replace(".", "_")
    picture = framed_model(key, boxes[key], size).convert("RGBA")
    corners = Image.new("L", size, 0)
    ImageDraw.Draw(corners).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), 12, fill=255)
    image.paste(picture, (left, top), corners)
    row = top + MODEL_H + ITEM_PAD
    paste(image, icon(icon_key(full_type), ICON), (left + ICON / 2, row + ICON / 2), shadow=False)
    wrapped, height = name
    text(image, (left + ICON + ITEM_PAD, row + max(0, (ICON - height) / 2)), wrapped, NAME_SIZE, "SemiBold")


def items():
    """Every item in ITEM_ROWS, each kind under its caption, each line of cards as tall as its
    longest name needs."""
    names = {item["fullType"]: item["name"] for item in PROMO["items"]}
    missing = set(names) - {full_type for _, full_types in ITEM_ROWS for full_type in full_types}
    assert not missing, f"items.png has no place for {sorted(missing)}"
    boxes = {model["name"]: model["box"] for model in PROMO["models"]}
    column = (WIDTH - 20) // ITEM_COLUMNS
    name_width = column - 12 - 3 * ITEM_PAD - ICON
    heading, gap = 44, 12
    sections = []
    for title, full_types in ITEM_ROWS:
        lines = []
        for start in range(0, len(full_types), ITEM_COLUMNS):
            cards = [(full_type, name_block(names[full_type], name_width))
                     for full_type in full_types[start:start + ITEM_COLUMNS]]
            height = 3 * ITEM_PAD + MODEL_H + max(ICON, *(name[1] for _, name in cards))
            lines.append((cards, height))
        sections.append((title, lines))
    image = canvas(20 + heading * len(sections) + sum(h + gap for _, lines in sections for _, h in lines))
    top = 20
    for title, lines in sections:
        text(image, (30, top + heading / 2), title, 22, "SemiBold", MUTED, "lm")
        top += heading
        for cards, height in lines:
            left0 = (WIDTH - column * len(cards)) / 2
            for c, (full_type, name) in enumerate(cards):
                left = left0 + c * column
                box = (left + 6, top, left + column - 6, top + height)
                panel(image, box)
                item_card(image, full_type, name, box, boxes)
            top += height + gap
    return image


def trailer():
    """The arrow board trailer and the car towing it, cropped to a strip."""
    return full_width("trailer").crop(TRAILER_CROP)


def gardenlights():
    return full_width("gardenlights")


# Recipe cards: the recipe's name, skills, how it's learned and its tools in a column on the left,
# then a slot per input, an arrow and a slot per result. Cards share a row wherever they fit, and
# each row is as tall as its tallest card's contents.
CARD_GAP = 12
CARD_PAD = 16
NAME_W = 168
SLOT = 72
ARROW_W = 30
ROW_W = WIDTH - 40


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


def draw_slot(base, slot, x, top):
    """A slot's icon centred on x with its name below, a badge with how many whole items, and a
    caption. Returns the bottom of what it drew."""
    item, count = slot["item"], slot.get("count")
    paste(base, icon(item["icon"], 64), (x, top + 46), shadow=False)
    if count and count > 1 and not slot.get("uses"):
        badge(base, (x + 38, top + 10), f"×{count}")
    box = text(base, (x, top + 84), item["name"], 13, "Medium", TEXT, "ma", width=SLOT - 6)
    caption_text = slot_caption(slot)
    if caption_text:
        box = text(base, (x, box[3] + 3), caption_text, 12, "Medium", MUTED, "ma", width=SLOT - 4)
    return box[3]


def card_width(parts):
    _, inputs, results = parts
    return CARD_PAD + NAME_W + 14 + (len(inputs) + len(results)) * SLOT + ARROW_W + CARD_PAD


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


def recipe_card(base, recipe, parts, box):
    """Draws the card into box and returns how far down its contents reach."""
    left, top, right, bottom = box
    panel(base, box, SOLAR)
    tools, inputs, results = parts
    x = left + CARD_PAD
    lines = text(base, (x, top + 16), recipe["name"], 17, "Bold", width=NAME_W)
    skills = "  ·  ".join(f"{s['name']} {s['level']}" for s in recipe["skills"])
    for line, size in [(skills, 13), (learn_line(recipe), 12), ("Tools: " + ", ".join(tools) if tools else "", 12)]:
        if line:
            lines = text(base, (x, lines[3] + 6), line, size, "Medium", MUTED, width=NAME_W)
    lowest = lines[3]
    x = left + CARD_PAD + NAME_W + 14 + SLOT / 2
    for slot in inputs:
        lowest = max(lowest, draw_slot(base, slot, x, top))
        x += SLOT
    arrow(base, (x - SLOT / 2 + ARROW_W / 2, top + 46))
    x += ARROW_W
    for slot in results:
        lowest = max(lowest, draw_slot(base, slot, x, top))
        x += SLOT
    assert lowest <= bottom - 10, f"{recipe['id']} runs past the bottom of its card"
    assert x - SLOT / 2 <= right - CARD_PAD + 1, f"{recipe['id']} is too wide for its card"
    return lowest


def card_height(recipe, parts, width):
    """How tall the card must be to hold its contents, found by drawing it on a scratch image."""
    scratch = Image.new("RGBA", (width, 1000))
    return round(recipe_card(scratch, recipe, parts, (0, 0, width, 1000))) + CARD_PAD


def first_fit(cards):
    """Packs (order, (recipe, parts, width)) pairs into rows as wide as the image allows, each into
    the first row with room for it, and returns the rows and the cards in each in their order."""
    rows = []
    for order, card in cards:
        assert card[2] <= ROW_W, f"{card[0]['id']} is too wide for the image"
        row = next((row for row in rows if row[1] + CARD_GAP + card[2] <= ROW_W), None)
        if row:
            row[0].append((order, card))
            row[1] += CARD_GAP + card[2]
        else:
            rows.append([[(order, card)], card[2]])
    return [[card for _, card in sorted(row)] for row, _ in sorted(rows, key=lambda row: min(row[0]))]


def card_rows(cards):
    """The section's cards in rows, in the section's order unless packing the widest first takes
    fewer rows."""
    in_order = first_fit(list(enumerate(cards)))
    widest_first = first_fit(sorted(enumerate(cards), key=lambda pair: -pair[1][2]))
    return widest_first if len(widest_first) < len(in_order) else in_order


def recipes():
    by_id = {r["id"]: r for r in PROMO["recipes"]}
    items_by_type = {item["fullType"]: item for item in PROMO["items"]}
    placed = [i for _, ids in RECIPE_SECTIONS for i in ids]
    assert sorted(placed) == sorted(by_id), f"recipes.png places {sorted(placed)}, the game has {sorted(by_id)}"
    sections = []
    for title, ids in RECIPE_SECTIONS:
        cards = []
        for i in ids:
            parts = recipe_parts(by_id[i], items_by_type)
            cards.append((by_id[i], parts, card_width(parts)))
        sections.append((title, card_rows(cards)))
    heading = 52
    heights = [[max(card_height(*card) for card in row) for row in section_rows] for _, section_rows in sections]
    image = canvas(20 + len(sections) * heading + sum(h + CARD_GAP for hs in heights for h in hs))
    top = 20
    for (title, section_rows), row_heights in zip(sections, heights):
        text(image, (30, top + heading / 2), title, 22, "SemiBold", MUTED, "lm")
        top += heading
        for row, height in zip(section_rows, row_heights):
            # The row's spare width goes to its cards evenly, so every row spans the image.
            spare = (ROW_W - sum(card[2] for card in row) - CARD_GAP * (len(row) - 1)) / len(row)
            left = 20
            for recipe, parts, width in row:
                recipe_card(image, recipe, parts, (left, top, left + width + spare, top + height))
                left += width + spare + CARD_GAP
            top += height + CARD_GAP
    return image


def main():
    for name, make in [("banner", banner), ("setup", setup), ("bank", bank), ("items", items),
                       ("recipes", recipes), ("trailer", trailer), ("gardenlights", gardenlights)]:
        save(make(), name)


if __name__ == "__main__":
    main()
