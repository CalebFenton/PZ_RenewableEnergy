#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""Crops the screenshots that `dev/run-debug-client.sh --promo` saves into the named images that
compose.py lays out, and saves the item, recipe and skill names the game reported as
captures/promo.json. The client script runs it; by hand:

    art/promo/extract.py <cache dir>

The harness's dev/harness/lib/capture.py does the shots and promo.json, replacing only the
captures of the groups the run shot; this adds the item models and says which captures are missing.

Each item lies alone on a plain floor for its model shot, and the floor is shot empty too. Where
the shot differs from the empty floor is the item: it is cropped around it into
captures/model_<module>_<Type>.png, and promo.json gives the item's box in that crop.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "dev" / "harness" / "lib"))
from capture import Extraction, load, pixel_box  # noqa: E402

CAPTURES = HERE / "captures"
# A pixel belongs to the item where a channel differs from the empty floor's by more than this.
ITEM_DIFFERENCE = 0.06
# Rows and columns with fewer item pixels than this are noise.
ITEM_MIN_PIXELS = 3
# A model capture reaches this share of the item's longer side past it on every side, for
# compose.py to frame it, and keeps its longer side within MODEL_MAX pixels.
MODEL_MARGIN = 0.35
MODEL_MAX = 512


def item_box(shot, floor):
    """The box (left, top, right, bottom) around what differs between shot and floor, or None."""
    differs = np.abs(shot - floor).max(axis=2) > ITEM_DIFFERENCE
    rows = np.flatnonzero(differs.sum(axis=1) >= ITEM_MIN_PIXELS)
    columns = np.flatnonzero(differs.sum(axis=0) >= ITEM_MIN_PIXELS)
    if not len(rows) or not len(columns):
        return None
    return [int(columns[0]), int(rows[0]), int(columns[-1]) + 1, int(rows[-1]) + 1]


def model(run, entry, floors):
    """Saves an item's shot cropped around the item and returns its promo.json entry."""
    image = Image.open(run.screenshots / f"{entry['file']}.png").convert("RGB")
    window = pixel_box(entry["window"], run.scale(image))
    if entry["floor"] not in floors:
        floors[entry["floor"]] = load(run.screenshots / f"{entry['floor']}.png")
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
    run.save(image, entry["group"], entry["name"])
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
    run = Extraction(sys.argv[1], "REPromo", CAPTURES)
    floors = {}
    models = [model(run, entry, floors) for entry in run.manifest["models"]]
    # A run that shot no models keeps the boxes of the last one that did.
    run.manifest["models"] = models if models else run.previous.get("models", [])
    run.finish()
    for name, group in missing_captures(run.manifest):
        print(f"extract: no capture {name}.png; run dev/run-debug-client.sh --promo with PROMO={group}")


if __name__ == "__main__":
    main()
