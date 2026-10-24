#!/usr/bin/env bash
# Rebuilds every model, texture, icon and tile of the mod, with Blender (made with 5.2) but for the
# mod list icon, from the parts in items.py and the tile layout in tiles.py:
#
#   models.py    ground and sprite models and their baked textures (common/media/models_X and
#                textures/WorldItems), scripts/RenewableEnergy/Models.txt and SpriteModels.txt
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
# A rebuild from unchanged sources writes the same bytes, so git shows only what a change touched:
# - Blender's FBX exporter gives each object the id hash() makes of its name (fbx_utils.py
#   _key_to_uuid) and writes a hinge's animation curves in the order of a set hashed the same way
#   (export_fbx_bin.py fbx_animations_do), and Python salts that hash per process unless
#   PYTHONHASHSEED fixes it, which Blender reads only with --python-use-system-env. models.py
#   refuses to run without it.
# - The exporter stamps each file with the time of writing; models.py hands it a fixed one. It
#   also writes a texture's absolute path, so the files carry no texture.
# - A render saves the date and Cycles' timings into its PNG, so render.py saves the tile sprites
#   from the rendered pixels, as it does the icons.
# - Two builds of Pillow can compress the same pixels to different bytes, so mod_icon.py and
#   tools/pack_textures.py pin the version uv installs.
set -euo pipefail
cd "$(dirname "$0")"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
export PYTHONHASHSEED=0
blender() { "$BLENDER" -b --factory-startup --python-use-system-env -P "$1"; }
blender models.py
blender render.py
./mod_icon.py
python3 ../../tools/make_tiles.py
../../tools/pack_textures.py
blender preview.py
