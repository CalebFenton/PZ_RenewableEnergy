#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""Crops the screenshots that `dev/run-debug-client.sh --promo` saves into the named images that
compose.py lays out, and saves the item, recipe and skill names the game reported as
captures/promo.json. The client script runs it; by hand:

    art/promo/extract.py <cache dir>

Every file in captures/ is replaced. The harness takes each shot of something other than the world
twice, on black and on white: a pixel that reads k on black and w on white has alpha a = 1 - (w - k)
and colour k / a.

Each item lies alone on a plain floor for its model shots, one per zoom, closest first, and the
floor is shot empty at each zoom too. Where a shot differs from the empty floor is the item: the
closest shot whose item stays inside the window the harness named is cropped around it into
captures/model_<module>_<Type>.png, and promo.json gives the item's box in that crop.
"""
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

CAPTURES = Path(__file__).resolve().parent / "captures"
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


def model(screenshots, scale, entry, floors):
    """Saves the closest of an item's shots that holds the whole item, cropped around it, and
    returns its promo.json entry. Falls back on the last shot, with a warning, if none does."""
    for i, shot in enumerate(entry["shots"]):
        window = pixel_box(shot["window"], scale)
        if shot["floor"] not in floors:
            floors[shot["floor"]] = load(screenshots / f"{shot['floor']}.png")
        image = Image.open(screenshots / f"{shot['file']}.png").convert("RGB").crop(window)
        floor = floors[shot["floor"]][window[1]:window[3], window[0]:window[2]]
        box = item_box(np.asarray(image, dtype=np.float32) / 255, floor)
        if box is None:
            sys.exit(f"extract: no item in {shot['file']}.png")
        touches = box[0] <= 1 or box[1] <= 1 or box[2] >= image.width - 1 or box[3] >= image.height - 1
        if touches and i + 1 < len(entry["shots"]):
            continue
        if touches:
            print(f"extract: {entry['name']} runs past the window of {shot['file']}.png")
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


def main():
    cache = Path(sys.argv[1])
    screenshots = cache / "Screenshots"
    manifest = json.loads((cache / "Lua" / "REPromo.json").read_text())
    if CAPTURES.exists():
        shutil.rmtree(CAPTURES)
    CAPTURES.mkdir()
    count = 0
    # Screenshots are in pixels and regions in UI units, which differ on a HiDPI display.
    scale = None
    for shot in manifest.pop("shots"):
        name = shot["name"]
        if shot["matte"]:
            image = matte(load(screenshots / f"promo_{name}_k.png"), load(screenshots / f"promo_{name}_w.png"))
        else:
            image = Image.open(screenshots / f"promo_{name}.png").convert("RGB")
        scale = image.width / manifest["screen"]["w"]
        for r in shot["regions"]:
            image.crop(pixel_box(r, scale)).save(CAPTURES / f"{r['name']}.png", optimize=True)
            count += 1
    floors = {}
    manifest["models"] = [model(screenshots, scale, entry, floors) for entry in manifest["models"]]
    count += len(manifest["models"])
    del manifest["screen"]
    (CAPTURES / "promo.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"extract: {count} images and promo.json in {CAPTURES}")


main()
