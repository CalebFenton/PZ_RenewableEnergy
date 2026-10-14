"""The static check's tile rules for this mod's tiles (dev/harness/docs/static-check.md, "Plugins").

| Check | What it catches |
| --- | --- |
| `tile-format` | A `tiledef=` or `pack=` line in mod.info naming no file or a file number outside 100..8189, or a `.tiles` file that does not read and write back byte for byte. |
| `tile-sprite` | A tile with properties but no packed sprite. |
| `tile-item` | A tile's `CustomItem` that is no item. |
| `tile-name` | A tile's `GroupName CustomName` without its `Moveables.json` key. |
| `tile-container` | A tile container without `IGUI_ContainerTitle_<type>`. |
"""
import tiledefs
from rules import check, has_entry, has_text, item_exists, read


@read
def tile_definitions(mod, report):
    # Fills mod.tilesets, where item-sprite also looks the mod's tile sprites up.
    for value in mod.info.get("tiledef", []):
        words = value.split()
        path = mod.media_file("media/%s.tiles" % words[0]) if words else None
        if len(words) != 2 or not words[1].isdigit() or not 100 <= int(words[1]) <= 8189:
            # ChooseGameInfo.readModInfo drops the line without these.
            report.fail("tile-format", mod.info_path, None, "tiledef=%s needs a file name and a "
                        "file number from 100 to 8189" % value)
        if path is None:
            report.fail("tile-format", mod.info_path, None, "tiledef=%s names no media/%s.tiles"
                        % (value, words[0] if words else ""))
            continue
        try:
            with open(path, "rb") as f:
                data = f.read()
            tilesets = tiledefs.loads(data)
        except ValueError as e:
            report.fail("tile-format", path, None, "the game could not read it: %s" % e)
            continue
        if tiledefs.dumps(tilesets) != data:
            report.fail("tile-format", path, None, "reads, but does not write back the same, so "
                        "dev/harness/check/tiledefs.py misreads something in it")
        mod.tilesets.extend((path, tileset) for tileset in tilesets)
    for value in mod.info.get("pack", []):
        if not mod.media_file("media/texturepacks/%s.pack" % value):
            report.fail("tile-format", mod.info_path, None, "pack=%s names no media/texturepacks/%s.pack"
                        % (value, value))


@check
def tiles(mod, game, report):
    for path, tileset in mod.tilesets:
        for index, properties in enumerate(tileset.tiles):
            if not properties:
                continue
            report.saw("tiles")
            sprite = "%s_%d" % (tileset.name, index)
            values = dict(properties)
            if sprite not in mod.sprites:
                report.fail("tile-sprite", path, None, "%s has properties but no pack has its sprite" % sprite)
            item = values.get("CustomItem")
            if item is not None and not item_exists(mod, game, item):
                report.fail("tile-item", path, None, "%s: CustomItem = %s is no item, so picking it up gives "
                            "nothing" % (sprite, item))
            # Translator.getMoveableDisplayName: "<GroupName> <CustomName>", spaces and dashes to
            # underscores and apostrophes dropped, looked up in Moveables.json.
            if values.get("CustomName"):
                name = (values["GroupName"] + " " if values.get("GroupName") else "") + values["CustomName"]
                key = name.replace(" ", "_").replace("-", "_").replace("'", "")
                if not has_entry(mod, game, "Moveables", key):
                    report.fail("tile-name", path, None, "%s is named %r, but Moveables.json has no %s"
                                % (sprite, name, key))
            # ISInventoryPage titles a container getText("IGUI_ContainerTitle_" .. type).
            if values.get("container"):
                key = "IGUI_ContainerTitle_" + values["container"]
                if not has_text(mod, game, key):
                    report.fail("tile-container", path, None, "%s holds a %s container, but IG_UI.json has no %s"
                                % (sprite, values["container"], key))
