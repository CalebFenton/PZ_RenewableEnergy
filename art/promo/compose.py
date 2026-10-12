#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Lays out the README and Workshop images from the captures that extract.py saved. Rerun it after
editing a layout; recapture only when the game's look or the mod's names change:

    art/promo/compose.py

Writes images/{banner,setup,status,items,recipes}.png. Every image is 1260 pixels wide, which the
Workshop page shows at 630, so it stays sharp on high-density screens. Icons are scaled by whole
numbers with nearest-neighbour sampling, so their pixels stay crisp. Item, recipe and skill names
come from captures/promo.json, which the game wrote in its own words; the stage captions are the
README's.
"""
import json
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
AMBER = (232, 168, 64)
STAGE0 = "Stage 0 · Scavenger"
STAGES12 = "Stages 1 and 2 · RV / Cabin and Homestead"
# items.png: one row per kind of thing, with its caption.
ITEM_ROWS = [
    ("Panels and mounts", ["RenewableEnergy.SolarModule", "RenewableEnergy.SolarFlat", "RenewableEnergy.SolarWall",
                           "RenewableEnergy.SolarRack"]),
    ("Banks and what goes in them", ["RenewableEnergy.BatteryBox", "RenewableEnergy.BatteryBank",
                                     "RenewableEnergy.PlugInInverter", "RenewableEnergy.PowerInverter",
                                     "RenewableEnergy.InverterCharger", "RenewableEnergy.ChargeController",
                                     "RenewableEnergy.SolarFailsafe"]),
    ("Batteries", ["Base.CarBattery1", "RenewableEnergy.DeepCycleBattery", "RenewableEnergy.L16Battery"]),
    ("Gadgets and magazines", ["RenewableEnergy.SolarMaintainer", "RenewableEnergy.SolarCellCharger",
                               "RenewableEnergy.HomesteadPowerMag1", "RenewableEnergy.HomesteadPowerMag2"]),
]
# recipes.png: the recipes by stage. Expanded recipes follow, under their sandbox option.
RECIPE_SECTIONS = [
    (STAGE0, ["RenewableEnergy_MakeBatteryBox"]),
    (STAGES12, ["RenewableEnergy_BuildBatteryBankWood", "RenewableEnergy_BuildBatteryBankMetal",
                "RenewableEnergy_MakeSolarFlat", "RenewableEnergy_MakeSolarWall", "RenewableEnergy_MakeSolarRack",
                "RenewableEnergy_MakeChargeController", "RenewableEnergy_MakeSolarFailsafe"]),
    ("Moving modules to another mount", ["RenewableEnergy_UnmountSolarFlat", "RenewableEnergy_UnmountSolarWall",
                                         "RenewableEnergy_UnmountSolarRack"]),
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


def wrap(string, face, width):
    """Splits string into lines no wider than width, breaking at spaces."""
    lines = []
    for word in string.split():
        if lines and face.getlength(lines[-1] + " " + word) <= width:
            lines[-1] += " " + word
        else:
            lines.append(word)
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


def setup():
    """Stage 0 above the homestead, each under its caption."""
    stage0, homestead = full_width("stage0"), full_width("homestead")
    gap = 12
    image = canvas(stage0.height + gap + homestead.height)
    image.alpha_composite(stage0, (0, 0))
    image.alpha_composite(homestead, (0, stage0.height + gap))
    caption(image, (24, 24), STAGE0)
    caption(image, (24, stage0.height + gap + 24), STAGES12)
    return image


def status():
    """The status window at one and a half times its size if that fits: three times with
    nearest-neighbour sampling, then halved, which keeps the text sharper than scaling straight
    to it."""
    window = capture("status")
    margin = 40
    if window.width * 3 // 2 <= WIDTH - 2 * margin:
        window = pixels(window, 3)
        window = window.resize((window.width // 2, window.height // 2), Image.LANCZOS)
    image = canvas(window.height + 2 * margin)
    paste(image, window, (WIDTH / 2, image.height / 2))
    return image


def items():
    names = {item["icon"]: item["name"] for item in PROMO["items"]}
    shown = {key for _, row in ITEM_ROWS for key in map(icon_key, row)}
    missing = set(names) - shown
    assert not missing, f"items.png has no place for {sorted(missing)}"
    columns = max(len(row) for _, row in ITEM_ROWS)
    column = (WIDTH - 20) // columns
    heading, row = 44, 276
    image = canvas(20 + (heading + row) * len(ITEM_ROWS))
    top = 20
    for title, full_types in ITEM_ROWS:
        text(image, (30, top + heading / 2), title, 22, "SemiBold", MUTED, "lm")
        top += heading
        left0 = (WIDTH - column * len(full_types)) / 2
        for c, full_type in enumerate(full_types):
            key = icon_key(full_type)
            left = left0 + c * column
            panel(image, (left + 8, top, left + column - 8, top + row - 16))
            x = left + column / 2
            paste(image, icon(key, 128), (x, top + 84))
            text(image, (x, top + 160), names[key], 18, "SemiBold", anchor="ma", width=column - 30)
        top += row
    return image


def recipe_slot(base, item, x, top, count=None, keep=False, uses=False):
    """An item's icon centred on x with its name below, and how many the recipe takes or gives:
    whole items in a badge, uses of a drainable item and kept tools under the name."""
    image = icon(item["icon"], 64)
    paste(base, image, (x, top + 52), shadow=False)
    if count and count > 1 and not uses:
        badge(base, (x + 46, top + 14), f"×{count}")
    box = text(base, (x, top + 92), item["name"], 15, "Medium", TEXT, "ma", width=104)
    if keep or uses:
        text(base, (x, box[3] + 3), "kept" if keep else f"{count} uses", 14, "Medium", MUTED, "ma")


def learn_line(recipe):
    """How the recipe is learned: the magazines that teach it, and the skill level at which a
    character works it out alone."""
    learn = recipe["learn"]
    if not learn["needed"]:
        return "No need to learn it"
    ways = [name.split(":")[0] for name in learn["magazines"]]
    ways += [f"at {s['name']} {s['level']}" for s in learn["auto"]]
    return "Learn from " + ", or ".join(ways) if learn["magazines"] else "Learn " + ", or ".join(ways)


def recipe_card(base, recipe, top, height):
    panel(base, (20, top, WIDTH - 20, top + height), AMBER if recipe["expanded"] else SOLAR)
    box = text(base, (46, top + 24), recipe["name"], 22, "Bold", width=250)
    skills = "  ·  ".join(f"{s['name']} {s['level']}" for s in recipe["skills"])
    box = text(base, (46, box[3] + 8), skills, 17, "Medium", MUTED, width=250)
    text(base, (46, box[3] + 8), learn_line(recipe), 14, "Medium", MUTED, width=250)
    slot = 112
    x = 360
    for entry in recipe["inputs"]:
        for i, item in enumerate(entry["items"]):
            if i > 0:
                text(base, (x - slot / 2, top + 52), "or", 16, "Medium", MUTED, "mm")
            recipe_slot(base, item, x, top, entry["count"], entry["keep"], entry["uses"])
            x += slot
    arrow(base, (x - slot / 2 + 12, top + 52))
    x += 24
    for item in recipe["outputs"]:
        recipe_slot(base, item, x, top, item["count"])
        x += slot
    assert x - slot / 2 <= WIDTH - 20, f"{recipe['id']} is too wide for its card"


def recipes():
    by_id = {r["id"]: r for r in PROMO["recipes"]}
    sections = [(title, [by_id[i] for i in ids]) for title, ids in RECIPE_SECTIONS]
    expanded = [r for r in PROMO["recipes"] if r["expanded"]]
    if expanded:
        sections.append((f"Off by default: turn on {PROMO['strings']['expandedOption']} in the sandbox options", expanded))
    placed = [r["id"] for _, section in sections for r in section]
    assert sorted(placed) == sorted(by_id), f"recipes.png places {sorted(placed)}, the game has {sorted(by_id)}"
    card, gap, heading = 172, 12, 60
    image = canvas(20 + len(placed) * (card + gap) + len(sections) * heading)
    top = 20
    for title, section in sections:
        expanded_section = section[0]["expanded"]
        text(image, (46, top + heading / 2), title, 22, "SemiBold", AMBER if expanded_section else MUTED, "lm")
        top += heading
        for recipe in section:
            recipe_card(image, recipe, top, card)
            top += card + gap
    return image


def main():
    for name, make in [("banner", banner), ("setup", setup), ("status", status), ("items", items),
                       ("recipes", recipes)]:
        save(make(), name)


main()
