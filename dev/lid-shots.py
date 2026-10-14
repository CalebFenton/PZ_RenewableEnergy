#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Crops the arrow board trailer out of the screenshots the lid test takes and lays them out in one
sheet, to see what a game drew while the battery box lid swung:

    TESTS=renewable_energy_world_arrow_board_lid_swings dev/run-debug-client.sh --test --mp
    dev/lid-shots.py            # the --mp client's cache; give a cache dir for another run

The top row holds the lid held shut, open after this client opened it, shut again, and open after
the server opened it as another player would; the row under it the first frame between shut and
open of each swing; the last row the shut lid padlocked by the server, then unlocked. Writes <cache>/Screenshots/test_lid_sheet.png, which the next --test run
clears with the shots.

It also fails when the box looks the same open as shut. Grass, leaves and fog move between shots,
so around the box each open shot must differ from the first shut one by well more than the second
shut one does.
"""

import os
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat

# The crops, in UI units at zoom 1: (width, height, how far above the logged ground point the
# middle is). The trailer's crop is enlarged for the sheet.
TRAILER = (280, 260, 20)
BOX = (100, 90, 55)
ENLARGE = 1.5
TILE_W, TILE_H = round(TRAILER[0] * ENLARGE), round(TRAILER[1] * ENLARGE)
HELD = [
    ("0_shut", "shut"),
    ("1_opening_it", "opened here"),
    ("2_closing_it", "shut here"),
    ("3_someone_else_opening_it", "opened by the server"),
]
SWINGING = [
    ("1_opening_it_swinging", "opening here"),
    ("2_closing_it_swinging", "shutting here"),
    ("3_someone_else_opening_it_swinging", "opening, server"),
    ("4_someone_else_closing_it_swinging", "shutting, server"),
]
LOCKS = [
    ("5_padlocked_by_the_server", "padlocked, server"),
    ("6_unlocked_by_the_server", "unlocked, server"),
]
# How much more an open box must differ from the first shut one than the second shut one does.
OPEN_MARGIN = 3.0
LABEL_H = 24


def shot_places(console):
    """For each shot the test logged: the trailer's and the box's screen points, the zoom and the
    screen's width, from its RELidShot line."""
    places = {}
    number = r"(-?[\d.]+)"
    pattern = re.compile(r"RELidShot (\S+) " + " ".join([number] * 6))
    for line in console.read_text(errors="replace").splitlines():
        match = pattern.search(line)
        if match:
            file, tx, ty, bx, by, zoom, width = match.groups()
            places[file] = ((float(tx), float(ty)), (float(bx), float(by)), float(zoom), float(width))
    return places


class Shot:
    def __init__(self, image, place):
        self.image = image
        self.trailer, self.box, self.zoom, width = place
        # Screenshots are in pixels and the logged points in UI units, which differ on a HiDPI display.
        self.scale = image.width / width

    def crop(self, point, size):
        w, h, raised = size
        x, y = point
        k = self.scale / self.zoom
        cx, cy = x * self.scale, y * self.scale - raised * k
        return self.image.crop((round(cx - w * k / 2), round(cy - h * k / 2), round(cx + w * k / 2), round(cy + h * k / 2)))


def load(screenshots, places, name):
    file = f"test_lid_{name}.png"
    if file not in places or not (screenshots / file).exists():
        return None
    return Shot(Image.open(screenshots / file).convert("RGB"), places[file])


def difference(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def main():
    default = Path(os.path.realpath(os.environ.get("TMPDIR", "/tmp"))) / "pz-renewable-energy-mpclient"
    cache = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    screenshots = cache / "Screenshots"
    places = shot_places(cache / "console.txt")
    rows = [[(load(screenshots, places, name), label) for name, label in row] for row in (HELD, SWINGING, LOCKS)]
    held = [shot for shot, _ in rows[0]]
    missing = [name for (name, _), shot in zip(HELD, held) if shot is None]
    if missing:
        sys.exit(f"no shot or no RELidShot line for {', '.join(missing)} in {cache}; run the lid test first")

    sheet = Image.new("RGB", (TILE_W * len(HELD), (TILE_H + LABEL_H) * len(rows)), "white")
    draw = ImageDraw.Draw(sheet)
    for r, row in enumerate(rows):
        for c, (shot, label) in enumerate(row):
            x, y = c * TILE_W, r * (TILE_H + LABEL_H)
            if shot is not None:
                sheet.paste(shot.crop(shot.trailer, TRAILER).resize((TILE_W, TILE_H), Image.LANCZOS), (x, y + LABEL_H))
            draw.text((x + 6, y + 6), label if shot is not None else label + " (no shot)", fill="black")
    out = screenshots / "test_lid_sheet.png"
    sheet.save(out)
    print(out)

    shut, opened_here, shut_again, opened_by_server = held
    shut_box = shut.crop(shut.box, BOX)
    still = difference(shut_box, shut_again.crop(shut_again.box, BOX))
    failed = False
    for name, shot in (("opened here", opened_here), ("opened by the server", opened_by_server)):
        moved = difference(shut_box, shot.crop(shot.box, BOX))
        print(f"box {name}: differs from shut by {moved:.2f}; shut again, by {still:.2f}")
        if moved < OPEN_MARGIN * still:
            print(f"FAIL: the box {name} looks as it does shut")
            failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
