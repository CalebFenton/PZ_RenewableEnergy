"""The static check's rules holding Lua and the scripts to the tile numbers in
art/models/tile_numbers.py (dev/harness/docs/static-check.md, "Plugins").

| Check | What it catches |
| --- | --- |
| `sprite-tiles` | `SpriteTiles.lua` not what `tools/make_tiles.py` writes from the tile numbers now: run it. |
| `tile-picture` | A tile `SpriteTiles.lua` names, overlays included, that isn't in the mod's tilesets or has no picture in its packs. |
| `item-tile` | An item's `WorldObjectSprite` that isn't its first tile facing S: of the tiles whose `CustomItem` gives the item back, the lowest-numbered with `Facing = S`, or the lowest-numbered when none turns. |
| `entity-tile` | An entity's `SpriteConfig` rows that aren't the tiles its meaning has (`ENTITY_TILES`), or an entity on the mod's tiles that `ENTITY_TILES` doesn't name. |
"""
import importlib.util
import os

from moddata import check

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_spec = importlib.util.spec_from_file_location("make_tiles", os.path.join(REPO, "tools", "make_tiles.py"))
make_tiles = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_tiles)

TILE_PREFIX = "renewable_energy_"
# Each entity's place in make_tiles.sprite_tiles(), Sprites.lua's fields: a tile it stands on facing
# S, or its tiles by face.
ENTITY_TILES = {
    "RenewableEnergy_BarrelDigester": ("digester", "barrel", "MetalDrum"),
    "RenewableEnergy_BarrelDigester_OrangeBarrel": ("digester", "barrel", "Mov_OrangeBarrel"),
    "RenewableEnergy_BarrelDigester_DarkGreenBarrel": ("digester", "barrel", "Mov_DarkGreenBarrel"),
    "RenewableEnergy_BarrelDigester_LightGreenBarrel": ("digester", "barrel", "Mov_LightGreenBarrel"),
    "RenewableEnergy_InsulatedDigester": ("digester", "insulated"),
    "RenewableEnergy_BrickDome": ("digester", "dome"),
    "RenewableEnergy_PrimitiveGasifier": ("gasifier", "primitive"),
    "RenewableEnergy_Gasifier": ("gasifier", "standard"),
    "RenewableEnergy_AdvancedGasifier": ("gasifier", "advanced"),
    "RenewableEnergy_ScoopRotor": ("windScoop",),
    "RenewableEnergy_PropellerWood": ("windCharger", "propeller", "wood"),
    "RenewableEnergy_PropellerPipe": ("windCharger", "propeller", "pipe"),
    "RenewableEnergy_PropellerSteel": ("windCharger", "propeller", "steel"),
    "RenewableEnergy_CarAlternatorWood": ("windCharger", "carAlternator", "wood"),
    "RenewableEnergy_CarAlternatorPipe": ("windCharger", "carAlternator", "pipe"),
    "RenewableEnergy_CarAlternatorSteel": ("windCharger", "carAlternator", "steel"),
    "RenewableEnergy_TurbineWood": ("windCharger", "alternator", "wood"),
    "RenewableEnergy_TurbinePipe": ("windCharger", "alternator", "pipe"),
    "RenewableEnergy_AlternatorWindCharger": ("windCharger", "alternator", "steel"),
}


@check
def sprite_tiles_current(mod, game, report):
    with open(make_tiles.LUA, encoding="utf-8") as f:
        written = f.read()
    if written != make_tiles.sprite_tiles_lua():
        report.fail("sprite-tiles", make_tiles.LUA, None, "is not what the tile numbers make: run python3 tools/make_tiles.py")


def _item_tile(full_type):
    """The tile an item places, by the tile properties make_tiles.py gives; None for none."""
    gives = sorted(number for number, props in make_tiles.TILES.items() if props.get("CustomItem") == full_type)
    facing_s = [number for number in gives if make_tiles.TILES[number].get("Facing") == "S"]
    return "%s_%d" % (make_tiles.TILESETS[0][0], (facing_s or gives)[0]) if gives else None


@check
def item_tiles(mod, game, report):
    for full_type, item in sorted(mod.items.items()):
        value = item.block.get("WorldObjectSprite")
        if value is None or not value.value.startswith(TILE_PREFIX):
            continue
        report.saw("item tiles")
        expected = _item_tile(full_type)
        if value.value != expected:
            report.fail("item-tile", item.path, value.line, "%s places %s, but the tile numbers' tile for it is %s"
                        % (full_type, value.value, expected or "none: no tile gives it back"))


def _entity_rows(entity):
    """An entity's mod tiles by face."""
    rows = {}
    for component in entity.blocks("component"):
        if component.id != "SpriteConfig":
            continue
        for face in component.blocks("face"):
            for layer in face.blocks("layer"):
                for value in layer.all("row"):
                    if value.value.startswith(TILE_PREFIX):
                        rows[face.id] = value
    return rows


@check
def entity_tiles(mod, game, report):
    tiles = make_tiles.sprite_tiles()
    for path, root in mod.scripts:
        for block in root.walk():
            if block.type != "entity":
                continue
            rows = _entity_rows(block)
            if not rows:
                continue
            report.saw("entity tiles")
            where = ENTITY_TILES.get(block.id)
            if where is None:
                report.fail("entity-tile", path, block.line, "%s stands on the mod's tiles, but ENTITY_TILES in "
                            "dev/check/sprite_tiles.py doesn't say which" % block.id)
                continue
            expected = tiles
            for key in where:
                expected = expected[key]
            if isinstance(expected, str):
                expected = {"S": expected}
            found = {face: value.value for face, value in rows.items()}
            if found != expected:
                line = min(value.line for value in rows.values())
                report.fail("entity-tile", path, line, "%s stands on %s, but the tile numbers give it %s"
                            % (block.id, found, expected))


def _tile_names(value):
    """The mod's tiles `value`, part of make_tiles.sprite_tiles(), names, as keys or values at any depth."""
    if isinstance(value, dict):
        for key, inner in value.items():
            yield from _tile_names(key)
            yield from _tile_names(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from _tile_names(inner)
    elif isinstance(value, str) and value.startswith(TILE_PREFIX):
        yield value


@check
def tile_pictures(mod, game, report):
    # Overlays have no tile properties, so the harness's tile-sprite rule never sees them.
    for name in sorted(set(_tile_names(make_tiles.sprite_tiles()))):
        report.saw("tile pictures")
        if mod.tile(name) is None:
            report.fail("tile-picture", make_tiles.LUA, None, "%s is no tile of the mod's tilesets" % name)
        elif name not in mod.sprites:
            report.fail("tile-picture", make_tiles.LUA, None, "%s has no picture in the mod's packs" % name)
