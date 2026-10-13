"""Draws the mod list icon, 42/renewable_energy_icon.png: a solar panel seen straight on, its cells
in a 3 x 2 grid, with the sun breaking its top right corner.

    python3 art/models/mod_icon.py

The mod list draws the icon at the height of a line of small text plus a little, about 22 pixels,
and the load order list at about 28, with linear filtering and no mipmaps (getTexture loads it
without them). So it is drawn pixel by pixel at 32, like the mod's item icons (one object, a dark
one-pixel outline, no background), and shipped doubled with hard edges: shrunk from 64, each
screen pixel blends at most two of the drawing's pixels across, and the grid lines stay crisp,
where shrunk from 32 they smear into the cells. Larger fonts draw it larger, which 64 also covers.

It is drawn from the shapes below rather than kept as an edited image, so a rerun writes the same
file. Needs Pillow.
"""
import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ICON = os.path.join(REPO, "Contents/mods/RenewableEnergy/42/renewable_energy_icon.png")
SIZE = 32
SCALE = 2

# Darker than the item icons' outline, which sits on the lighter inventory: the mod list is dark.
OUTLINE = (22, 24, 28)
FRAME = (206, 214, 226)
FRAME_SHADE = (150, 160, 178)
CELL_TOP, CELL_BOTTOM = (64, 98, 184), (30, 52, 122)
GLINT = (112, 146, 220)
SUN = (255, 204, 48)
SUN_LIGHT = (255, 238, 140)
SUN_RIM = (232, 140, 24)

# The panel's outline box, inclusive, then its cells: each is as wide and tall as the frame leaves
# for it between one-pixel bars.
PANEL = (1, 12, 27, 30)
COLUMNS, ROWS = 3, 2
# The sun's centre and radius in pixels, its outline included.
SUN_CENTRE, SUN_RADIUS = (25.0, 9.0), 7.6


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def panel(pixels):
    left, top, right, bottom = PANEL
    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            edge = x in (left, right) or y in (top, bottom)
            pixels[x, y] = OUTLINE + (255,) if edge else FRAME + (255,)
    # The frame's lower and right bars in shade, so the panel has a little depth.
    for x in range(left + 1, right):
        pixels[x, bottom - 1] = FRAME_SHADE + (255,)
    for y in range(top + 1, bottom):
        pixels[right - 1, y] = FRAME_SHADE + (255,)
    inner_w, inner_h = right - left - 1, bottom - top - 1
    cell_w, cell_h = (inner_w - COLUMNS - 1) // COLUMNS, (inner_h - ROWS - 1) // ROWS
    assert (cell_w + 1) * COLUMNS + 1 == inner_w and (cell_h + 1) * ROWS + 1 == inner_h, "cells don't fit the frame"
    for row in range(ROWS):
        for column in range(COLUMNS):
            x0 = left + 2 + column * (cell_w + 1)
            y0 = top + 2 + row * (cell_h + 1)
            for dy in range(cell_h):
                colour = mix(CELL_TOP, CELL_BOTTOM, dy / (cell_h - 1))
                for dx in range(cell_w):
                    pixels[x0 + dx, y0 + dy] = colour + (255,)
            # A glint across the glass's top left corner.
            for dx, dy in [(1, 1), (2, 1), (1, 2)]:
                pixels[x0 + dx, y0 + dy] = GLINT + (255,)


def sun(pixels):
    cx, cy = SUN_CENTRE
    for y in range(SIZE):
        for x in range(SIZE):
            # Distance from the pixel's centre; the light comes from the top left.
            d = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            if d > SUN_RADIUS:
                continue
            if d > SUN_RADIUS - 1.2:
                colour = OUTLINE
            elif d > SUN_RADIUS - 2.2:
                colour = SUN_RIM
            elif (x + 0.5 - cx) + (y + 0.5 - cy) < -4.5:
                colour = SUN_LIGHT
            else:
                colour = SUN
            pixels[x, y] = colour + (255,)


def main():
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = image.load()
    panel(pixels)
    sun(pixels)
    image.resize((SIZE * SCALE, SIZE * SCALE), Image.NEAREST).save(ICON, optimize=True)
    print(f"mod icon written: {os.path.relpath(ICON, REPO)}")


if __name__ == "__main__":
    main()
