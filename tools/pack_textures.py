#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.3.0"]
# ///
"""Builds the mod's texture pack, common/media/texturepacks/renewable_energy.pack, and reads .pack
files for dev/check.

    tools/pack_textures.py

art/models/make.sh runs it after rendering. It packs every PNG in tools/tiles (the tile sprites)
and tools/textures (the item icons) onto one fresh atlas page, so a deleted source leaves no stale
sprite behind. Building needs uv (https://docs.astral.sh/uv/), which brings Pillow; reading a pack
needs neither.

The game knows a packed sprite by its bare name, globally: Texture.getSharedTexture drops the
directory and the .png from whatever it is asked for and tries the packs first. So a sprite named
after the file it replaces resolves with no code change, `Icon = X` finds Item_X, and every name
carries the mod's to keep clear of other mods'. A tile sprite is trimmed to its visible pixels and
records where they sat in the full cell; an icon is stored whole, so it reports the size a loose
PNG would. Model textures stay loose (dev/check's model-texture explains why).

The layout, from TexturePackDevice.initMetaData and TexturePackPage.loadFromPackFile; integers are
little endian int32, strings an int32 length then that many bytes, each read as one char:

    "PZPK", version 1            absent in old packs, which start at the page count
    page count
    each page:
        string name, sprite count, alpha flag
        each sprite: string name, x, y, w, h (its rect on the page), offset x, offset y (where
                     that rect sits in the full cell), cell width, cell height
        version 1: int32 length, then the page's PNG
        old:       the PNG, then the bytes EF BE AD DE

This writes only version 1. The old end marker is found by scanning for it, so an image whose
compressed bytes happened to contain it would be cut short.
"""
import io
import os
import struct
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
PACK_FILE = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "common", "media",
                         "texturepacks", "renewable_energy.pack")
PAGE_NAME = "renewable_energy0"
TRIMMED_SOURCES = os.path.join(HERE, "tiles")
WHOLE_SOURCES = os.path.join(HERE, "textures")

MAGIC = b"PZPK"
OLD_END_MARKER = b"\xef\xbe\xad\xde"
# Transparent pixels between sprites, so texture filtering never samples a neighbour.
GAP = 2
# The base game's own pages stop at this width.
PAGE_WIDTH = 1024

_INT = struct.Struct("<i")
_RECT = struct.Struct("<8i")


@dataclass
class Sprite:
    name: str
    x: int
    y: int
    width: int
    height: int
    offset_x: int
    offset_y: int
    cell_width: int
    cell_height: int


@dataclass
class Page:
    name: str
    has_alpha: bool
    sprites: list = field(default_factory=list)
    # Where the page's PNG sits in the file, so a reader can skip it or slice it out.
    image_start: int = 0
    image_length: int = 0


def read_index(path):
    """The pages of a .pack and their sprites, without reading any image. Raises ValueError or
    EOFError on anything the game could not load either."""
    with open(path, "rb") as f:
        def take(n):
            data = f.read(n)
            if len(data) != n:
                raise EOFError("%s ends at byte %d" % (os.path.basename(path), f.tell()))
            return data

        def number():
            return _INT.unpack(take(4))[0]

        def string():
            return take(number()).decode("latin-1")

        version = 0
        if take(4) == MAGIC:
            version = number()
            if version != 1:
                raise ValueError("pack version %d, the game reads only 1" % version)
        else:
            f.seek(0)
        pages = []
        for _ in range(number()):
            page = Page(string(), False)
            count = number()
            page.has_alpha = number() != 0
            for _ in range(count):
                name = string()
                page.sprites.append(Sprite(name, *_RECT.unpack(take(_RECT.size))))
            if version:
                page.image_length = number()
                page.image_start = f.tell()
                f.seek(page.image_length, os.SEEK_CUR)
            else:
                page.image_start = f.tell()
                page.image_length = _find_end_marker(f) - page.image_start
                f.seek(len(OLD_END_MARKER), os.SEEK_CUR)
            pages.append(page)
        if f.tell() > os.fstat(f.fileno()).st_size:
            raise EOFError("%s is cut short inside its last image" % os.path.basename(path))
        return pages


def _find_end_marker(f):
    """Offset of the next old-style end marker, leaving the file there."""
    start = f.tell()
    tail = b""
    while True:
        chunk = f.read(1 << 16)
        if not chunk:
            raise EOFError("an old-style pack image has no end marker")
        window = tail + chunk
        found = window.find(OLD_END_MARKER)
        if found >= 0:
            at = f.tell() - len(window) + found
            f.seek(at)
            return at
        # Keep enough to catch a marker split across two chunks.
        tail = window[-(len(OLD_END_MARKER) - 1):]
        if f.tell() - start > 1 << 30:
            raise EOFError("no end marker in the first GiB of an old-style image")


def write_pack(path, page, png):
    """Write a single-page version 1 pack."""
    out = [MAGIC, _INT.pack(1), _INT.pack(1), _string(page.name),
           _INT.pack(len(page.sprites)), _INT.pack(1 if page.has_alpha else 0)]
    for s in page.sprites:
        out += [_string(s.name), _RECT.pack(s.x, s.y, s.width, s.height, s.offset_x, s.offset_y,
                                            s.cell_width, s.cell_height)]
    out += [_INT.pack(len(png)), png]
    with open(path, "wb") as f:
        f.write(b"".join(out))


def _string(text):
    data = text.encode("latin-1")
    return _INT.pack(len(data)) + data


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
