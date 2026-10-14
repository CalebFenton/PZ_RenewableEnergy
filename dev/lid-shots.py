#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Crops the arrow board trailer out of the screenshots the lid test takes and lays them out in one
sheet, to see what a game drew while the battery box lid swung:

    TESTS=renewable_energy_world_arrow_board_lid_swings dev/run-debug-client.sh --test --mp
    dev/lid-shots.py            # the --mp client's cache; give a cache dir for another run

The test takes the shots only when TESTS names it exactly, not by a prefix. The top row holds the
lid held shut, open after this client opened it, shut again, open after the server opened it as
another player would, and shut again by the server; the row under it the first frame between shut
and open of each swing. Writes <cache>/Screenshots/test_lid_sheet.png, which the next --test run
clears with the shots.

It also fails when the box looks the same open as shut, or open after the server shut it. Grass,
leaves and fog move between shots, so around the box each open shot must differ from the first
shut one by well more than the second shut one does, and the one the server shut by well less than
either open one.
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
    ("4_someone_else_closing_it", "shut by the server"),
]
SWINGING = [
    ("1_opening_it_swinging", "opening here"),
    ("2_closing_it_swinging", "shutting here"),
    ("3_someone_else_opening_it_swinging", "opening, server"),
    ("4_someone_else_closing_it_swinging", "shutting, server"),
]
# How much more an open box must differ from the first shut one than a shut one does.
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


def default_cache():
    """The --mp client's cache, which the harness names after harness.conf's CACHE_NAME."""
    conf = (Path(__file__).parent / "harness.conf").read_text()
    name = re.search(r"^CACHE_NAME=(\S+)$", conf, re.MULTILINE).group(1)
    return Path(os.path.realpath(os.environ.get("TMPDIR", "/tmp"))) / f"{name}-mpclient"


def main():
    cache = Path(sys.argv[1]) if len(sys.argv) > 1 else default_cache()
    screenshots = cache / "Screenshots"
    places = shot_places(cache / "console.txt")
    rows = [[(load(screenshots, places, name), label) for name, label in row] for row in (HELD, SWINGING)]
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

    shut, opened_here, shut_again, opened_by_server, shut_by_server = held
    shut_box = shut.crop(shut.box, BOX)

    def moved(shot):
        return difference(shut_box, shot.crop(shot.box, BOX))

    still = moved(shut_again)
    failed = False
    opened = []
    for name, shot in (("opened here", opened_here), ("opened by the server", opened_by_server)):
        opened.append(moved(shot))
        print(f"box {name}: differs from shut by {opened[-1]:.2f}; shut again, by {still:.2f}")
        if opened[-1] < OPEN_MARGIN * still:
            print(f"FAIL: the box {name} looks as it does shut")
            failed = True
    # The mirror of the open check: the sync bug this sheet exists for draws a lid the server shut
    # still open on this client.
    closed = moved(shut_by_server)
    print(f"box shut by the server: differs from shut by {closed:.2f}")
    if closed * OPEN_MARGIN > min(opened):
        print("FAIL: the box shut by the server looks as it does open")
        failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
