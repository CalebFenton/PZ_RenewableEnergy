"""Renders the tile sprites, their depth maps, the inventory icons and the build-menu icons from the
models in items.py and tiles.py, with the harness's lib/art/render.py, which says how.

    blender -b --factory-startup --python-use-system-env -P art/models/render.py [-- tiles [INDEX ...]|icons ...]

Tiles go to tools/tiles as whole 128 x 256 cells, which tools/pack_textures.py trims and packs.
Icons go to tools/textures as Item_RenewableEnergy_<Item>.png, and the build-menu icons of
tiles.BUILD_ICONS as RenewableEnergy_Build_<Name>.png. Each tileset's depth map goes to
common/media/depthmaps.
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(os.path.dirname(os.path.dirname(HERE)), "dev", "harness", "lib")]
import items  # noqa: E402
import paths  # noqa: E402
import tiles  # noqa: E402
from art import render  # noqa: E402

ART = render.Art(media=paths.MEDIA, tile_dir=paths.TILE_DIR, icon_dir=paths.ICON_DIR,
                 scratch=os.path.join(tempfile.gettempdir(), "renewable-energy-render"), tilesets=tiles.TILESETS,
                 items=items.ITEMS, build_icons=tiles.BUILD_ICONS, icon_prefix=paths.ICON_PREFIX,
                 build_icon_prefix=paths.BUILD_ICON_PREFIX)

if __name__ == "__main__":
    render.main(ART)
