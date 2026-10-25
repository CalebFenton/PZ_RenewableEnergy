"""Where the mod's art goes, for models.py, render.py and preview.py."""
import os

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOD = os.path.join(REPO, "Contents/mods/RenewableEnergy")
MEDIA = os.path.join(MOD, "common/media")
# render.py's tile sprites and icons, which tools/pack_textures.py packs.
TILE_DIR = os.path.join(REPO, "tools/tiles")
ICON_DIR = os.path.join(REPO, "tools/textures")
# The game finds a packed icon by its sprite name: Item_ and the item's name for an item's Icon,
# and any name for a build-menu icon, each carrying the mod's name to keep clear of other mods'.
ICON_PREFIX, BUILD_ICON_PREFIX = "Item_RenewableEnergy_", "RenewableEnergy_Build_"
