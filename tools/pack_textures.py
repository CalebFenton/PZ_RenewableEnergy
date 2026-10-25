#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.3.0"]
# ///
"""Builds the mod's texture pack, common/media/texturepacks/renewable_energy.pack, with the
harness's lib/art/pack.py, which says how.

    tools/pack_textures.py

art/models/make.sh runs it after rendering. It packs every PNG in tools/tiles (the tile sprites)
and tools/textures (the item and build-menu icons). It needs uv (https://docs.astral.sh/uv/),
which brings Pillow.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "dev", "harness", "lib"))
from art.pack import pack  # noqa: E402

PACK_FILE = os.path.join(HERE, "..", "Contents", "mods", "RenewableEnergy", "common", "media",
                         "texturepacks", "renewable_energy.pack")
PAGE_NAME = "renewable_energy0"

if __name__ == "__main__":
    pack(PACK_FILE, PAGE_NAME, os.path.join(HERE, "tiles"), os.path.join(HERE, "textures"))
