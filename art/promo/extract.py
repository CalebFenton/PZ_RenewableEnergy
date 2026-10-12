#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""Crops the screenshots that `dev/run-debug-client.sh --promo` saves into the named images that
compose.py lays out, and saves the item, recipe and skill names the game reported as
captures/promo.json. The client script runs it; by hand:

    art/promo/extract.py <cache dir>

Only the captures of the groups the run shot are replaced; promo.json lists each group's captures,
so that a rerun of a group also removes the ones it no longer makes. The names come with every run.

The harness takes each shot of something other than the world twice, on black and on white: a
pixel that reads k on black and w on white has alpha a = 1 - (w - k) and colour k / a.

Each item lies alone on a plain floor for its model shot, and the floor is shot empty too. Where
the shot differs from the empty floor is the item: it is cropped around it into
captures/model_<module>_<Type>.png, and promo.json gives the item's box in that crop.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

CAPTURES = Path(__file__).resolve().parent / "captures"
PROMO = CAPTURES / "promo.json"
# A pixel belongs to the item where a channel differs from the empty floor's by more than this.
ITEM_DIFFERENCE = 0.06
# Rows and columns with fewer item pixels than this are noise.
ITEM_MIN_PIXELS = 3
# A model capture reaches this share of the item's longer side past it on every side, for
# compose.py to frame it, and keeps its longer side within MODEL_MAX pixels.
MODEL_MARGIN = 0.35
MODEL_MAX = 512


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255


def matte(black, white):
    alpha = np.clip(1 - (white - black).mean(axis=2), 0, 1)[..., None]
    colour = np.clip(black / np.maximum(alpha, 1 / 255), 0, 1)
    return Image.fromarray(np.round(np.dstack([colour, alpha]) * 255).astype(np.uint8), "RGBA")


def pixel_box(region, scale):
    """A manifest region, in UI units, as a crop box in screenshot pixels."""
    return [round(v * scale) for v in (region["x"], region["y"], region["x"] + region["w"], region["y"] + region["h"])]


def item_box(shot, floor):
    """The box (left, top, right, bottom) around what differs between shot and floor, or None."""
    differs = np.abs(shot - floor).max(axis=2) > ITEM_DIFFERENCE
    rows = np.flatnonzero(differs.sum(axis=1) >= ITEM_MIN_PIXELS)
    columns = np.flatnonzero(differs.sum(axis=0) >= ITEM_MIN_PIXELS)
    if not len(rows) or not len(columns):
        return None
    return [int(columns[0]), int(rows[0]), int(columns[-1]) + 1, int(rows[-1]) + 1]


def model(screenshots, screen_w, entry, floors):
    """Saves an item's shot cropped around the item and returns its promo.json entry."""
    image = Image.open(screenshots / f"{entry['file']}.png").convert("RGB")
    # Screenshots are in pixels and regions in UI units, which differ on a HiDPI display.
    window = pixel_box(entry["window"], image.width / screen_w)
    if entry["floor"] not in floors:
        floors[entry["floor"]] = load(screenshots / f"{entry['floor']}.png")
    image = image.crop(window)
    floor = floors[entry["floor"]][window[1]:window[3], window[0]:window[2]]
    box = item_box(np.asarray(image, dtype=np.float32) / 255, floor)
    if box is None:
        sys.exit(f"extract: no item in {entry['file']}.png")
    if box[0] <= 1 or box[1] <= 1 or box[2] >= image.width - 1 or box[3] >= image.height - 1:
        print(f"extract: {entry['name']} runs past the window of {entry['file']}.png")
    margin = round(max(box[2] - box[0], box[3] - box[1]) * MODEL_MARGIN)
    crop = [max(0, box[0] - margin), max(0, box[1] - margin),
            min(image.width, box[2] + margin), min(image.height, box[3] + margin)]
    image = image.crop(crop)
    box = [box[0] - crop[0], box[1] - crop[1], box[2] - crop[0], box[3] - crop[1]]
    factor = MODEL_MAX / max(image.size)
    if factor < 1:
        image = image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)
        box = [round(v * factor) for v in box]
    image.save(CAPTURES / f"{entry['name']}.png", optimize=True)
    return {"name": entry["name"], "box": box}


def missing_captures(promo):
    """The captures promo.json's names call for that no run has made, with the group that makes
    each."""
    icons = {item["icon"] for item in promo["items"]}
    for recipe in promo["recipes"]:
        for line in recipe["inputs"]:
            icons.update(item["icon"] for item in line["items"])
        icons.update(item["icon"] for item in recipe["outputs"])
    models = {model["name"] for model in promo["models"]}
    for icon in sorted(icons):
        if not (CAPTURES / f"{icon}.png").exists():
            yield icon, "icons"
    for item in promo["items"]:
        name = "model_" + item["fullType"].replace(".", "_")
        if name not in models:
            yield name, "models"


def main():
    cache = Path(sys.argv[1])
    screenshots = cache / "Screenshots"
    manifest = json.loads((cache / "Lua" / "REPromo.json").read_text())
    previous = json.loads(PROMO.read_text()) if PROMO.exists() else {}
    captures = previous.get("captures", {})
    ran = manifest.pop("groups")
    for group in ran:
        for name in captures.pop(group, []):
            (CAPTURES / f"{name}.png").unlink(missing_ok=True)
        captures[group] = []
    CAPTURES.mkdir(exist_ok=True)
    screen_w = manifest.pop("screen")["w"]
    for shot in manifest.pop("shots"):
        name = shot["name"]
        if shot["matte"]:
            image = matte(load(screenshots / f"promo_{name}_k.png"), load(screenshots / f"promo_{name}_w.png"))
        else:
            image = Image.open(screenshots / f"promo_{name}.png").convert("RGB")
        for r in shot["regions"]:
            image.crop(pixel_box(r, image.width / screen_w)).save(CAPTURES / f"{r['name']}.png", optimize=True)
            captures[shot["group"]].append(r["name"])
    floors = {}
    models = [model(screenshots, screen_w, entry, floors) for entry in manifest["models"]]
    for entry in manifest["models"]:
        captures[entry["group"]].append(entry["name"])
    # A run that shot no models keeps the boxes of the last one that did.
    manifest["models"] = models if models else previous.get("models", [])
    manifest["captures"] = {group: sorted(names) for group, names in sorted(captures.items())}
    PROMO.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    count = sum(len(captures[group]) for group in ran)
    print(f"extract: {count} images from {', '.join(ran)} and promo.json in {CAPTURES}")
    for name, group in missing_captures(manifest):
        print(f"extract: no capture {name}.png; run dev/run-debug-client.sh --promo with PROMO={group}")


main()
