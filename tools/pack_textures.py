#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.3.0"]
# ///
"""Builds the mod's texture pack, common/media/texturepacks/renewable_energy.pack.

    tools/pack_textures.py

art/models/make.sh runs it after rendering. It packs every PNG in tools/tiles (the tile sprites)
and tools/textures (the item icons) onto one fresh atlas page, so a deleted source leaves no stale
sprite behind. It needs uv (https://docs.astral.sh/uv/), which brings Pillow. The pack format is
dev/harness/check/packs.py's, which the static check reads packs with.

The game knows a packed sprite by its bare name, globally. So a sprite named after the file it
replaces resolves with no code change, `Icon = X` finds Item_X, and every name carries the mod's
to keep clear of other mods'. A tile sprite is trimmed to its visible pixels and records where
they sat in the full cell; an icon is stored whole, so it reports the size a loose PNG would.
Model textures stay loose (the static check's model-texture explains why).
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dev", "harness", "check"))
from packs import Page, Sprite, read_index, write_pack  # noqa: E402

PACK_FILE = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "common", "media",
                         "texturepacks", "renewable_energy.pack")
PAGE_NAME = "renewable_energy0"
TRIMMED_SOURCES = os.path.join(HERE, "tiles")
WHOLE_SOURCES = os.path.join(HERE, "textures")

# Transparent pixels between sprites, so texture filtering never samples a neighbour.
GAP = 2
# The base game's own pages stop at this width.
PAGE_WIDTH = 1024


def load_sources(folder, trim):
    """(sprite name, image, offset in its cell, cell size) for every PNG in folder."""
    from PIL import Image

    sources = []
    for file_name in sorted(os.listdir(folder)):
        if not file_name.endswith(".png"):
            continue
        image = Image.open(os.path.join(folder, file_name)).convert("RGBA")
        cell = image.size
        offset = (0, 0)
        if trim:
            box = image.getbbox()
            if box is None:
                raise SystemExit("%s has no visible pixels" % file_name)
            image = image.crop(box)
            offset = box[:2]
        sources.append((file_name[:-len(".png")], image, offset, cell))
    return sources


def shelve(sizes):
    """Top-left corners for rects of these sizes, filled into rows across a page PAGE_WIDTH wide,
    and the page size that holds them. A row takes rects while each fits with a gap after it."""
    corners = []
    row_top = row_height = row_used = page_width = 0
    for width, height in sizes:
        if row_used and row_used + width + GAP > PAGE_WIDTH:
            row_top += row_height + GAP
            row_height = row_used = 0
        corners.append((row_used, row_top))
        page_width = max(page_width, row_used + width)
        row_used += width + GAP
        row_height = max(row_height, height)
    return corners, (page_width, row_top + row_height)


def main():
    from PIL import Image

    sources = load_sources(TRIMMED_SOURCES, trim=True) + load_sources(WHOLE_SOURCES, trim=False)
    names = [source[0] for source in sources]
    repeated = sorted({name for name in names if names.count(name) > 1})
    if repeated:
        raise SystemExit("sprites named twice: %s" % ", ".join(repeated))
    # Tallest first, so each row's height is set by its first sprite and wastes little.
    sources.sort(key=lambda source: (-source[1].height, source[0]))
    corners, page_size = shelve([source[1].size for source in sources])

    atlas = Image.new("RGBA", page_size, (0, 0, 0, 0))
    page = Page(PAGE_NAME, True)
    for (name, image, offset, cell), corner in zip(sources, corners):
        atlas.paste(image, corner)
        page.sprites.append(Sprite(name, *corner, *image.size, *offset, *cell))
    png = io.BytesIO()
    atlas.save(png, format="PNG", optimize=True)

    old_size = os.path.getsize(PACK_FILE) if os.path.exists(PACK_FILE) else 0
    write_pack(PACK_FILE, page, png.getvalue())
    # Read the index back, so a pack the game would misread never ships.
    (written,) = read_index(PACK_FILE)
    assert written.sprites == page.sprites and written.image_length == len(png.getvalue()), \
        "the pack does not read back as written"
    print("%d sprites on a %dx%d page; %s %d -> %d bytes"
          % (len(page.sprites), page_size[0], page_size[1], os.path.basename(PACK_FILE), old_size,
             os.path.getsize(PACK_FILE)))


if __name__ == "__main__":
    main()
