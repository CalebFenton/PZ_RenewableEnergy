#!/usr/bin/env bash
# Rebuilds every model, texture, icon and tile of the mod, with Blender (made with 5.2) but for the
# mod list icon, from the builders items.py gathers and the tile layout in tiles.py and
# tile_numbers.py, on the harness's art library (dev/harness/docs/art.md):
#
#   models.py    ground and sprite models and their baked textures (common/media/models_X and
#                textures/WorldItems), scripts/RenewableEnergy/Models.txt and SpriteModels.txt,
#                and the trailer's body, part models and shader textures, with vehicles.py
#   render.py    tile sprites (tools/tiles), their depth maps (common/media/depthmaps), the
#                32 x 32 item icons and the 48 x 48 build-menu icons (tools/textures)
#   mod_icon.py  the mod list icon, drawn pixel by pixel with Pillow (the poster and the Workshop
#                preview.png are in-game shots that art/promo/compose.py lays out)
#   tools/make_tiles.py and tools/pack_textures.py   renewable_energy.tiles and the pack
#   preview.py   review sheets of all of it, and index.html naming each piece, read back from the
#                written files
#
# BLENDER overrides the Blender binary, PREVIEWS the preview folder (default
# $TMPDIR/renewable-energy-previews). mod_icon.py and tools/pack_textures.py run with uv
# (https://docs.astral.sh/uv/), which brings their Pillow.
#
# A rebuild from unchanged sources writes the same bytes, so git shows only what a change touched;
# the art library's docs say how.
set -euo pipefail
cd "$(dirname "$0")"
. ../../dev/harness/lib/blender.sh
blender models.py
blender render.py
./mod_icon.py
python3 ../../tools/make_tiles.py
../../tools/pack_textures.py
blender preview.py
