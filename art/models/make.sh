#!/usr/bin/env bash
# Rebuilds every model, texture, icon and tile of the mod with Blender (made with 5.2), from the
# parts in items.py and the tile layout in tiles.py:
#
#   models.py    ground models and their baked textures (common/media/models_X and textures/
#                WorldItems) and scripts/RenewableEnergy/Models.txt
#   render.py    tile sprites (tools/tiles), their depth map (common/media/depthmaps) and the
#                32 x 32 item icons (tools/textures)
#   tools/make_tiles.py and tools/pack_textures.py   renewable_energy.tiles and the pack
#   preview.py   review sheets of all of it, read back from the written files
#
# BLENDER overrides the Blender binary, PREVIEWS the preview folder (default
# $TMPDIR/renewable-energy-previews).
set -euo pipefail
cd "$(dirname "$0")"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
"$BLENDER" -b --factory-startup -P models.py
"$BLENDER" -b --factory-startup -P render.py
"$BLENDER" -b --factory-startup -P mod_icon.py
python3 ../../tools/make_tiles.py
python3 ../../tools/pack_textures.py
"$BLENDER" -b --factory-startup -P preview.py
