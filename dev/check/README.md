# Renewable Energy checks

Static checks against the installed game, without launching it.

```bash
dev/static-check.sh
```

It needs a JDK's `javac` (any version from 8 on) and `python3`. Set `PZ_APP` if the game is not
in the macOS Steam folder, `CACHE` to move the cache (default `$TMPDIR/pz-renewable-energy-check`).

## How it works

- `GameProbe.java` runs on the game's own JVM with `projectzomboid.jar` on the class path. It
  compiles every Lua file of the mod, its dev mod (`dev/RenewableEnergyDevHarness`, where the
  tests are) and the shared harness mod (`dev/harness/mod`) with the game's Kahlua compiler
  (`lua-syntax`), and, once per game update, writes what Lua can reach: the classes
  `LuaManager$Exposer` hands to `setExposed`, with their methods, static members and
  constructors; the `@LuaMethod(global = true)` functions; the Kahlua standard library; and the
  string tables of `LuaEventManager`, `Translator`, `SandboxOptions` and `Item`.
- `gamedata.py` reads the rest from the game's files: what its Lua assigns, defines and requires,
  its items, tags, recipes and models, its English translations, packs and tile definitions. The
  result is cached next to the API file, keyed by the jar and the checker's source.
- `luasource.py` tokenises Lua (comments and strings never look like code), `scripts.py` parses
  scripts the way `ScriptParser` does, and `check.py` holds the checks, one function each.
  `tools/pack_textures.py` and `tools/tiledefs.py` read the `.pack` and `.tiles` files.

Without a type checker, Lua names are checked by name: a call site does not say what it calls on,
and a name declared local anywhere in a file counts as local in all of it. Both can hide a
mistake, never report a correct name. Run over the game's own 1,400 Lua files, `global-name` and
`global-member` flag about 140 reads, nearly all real slips in vanilla (`UIFont.Normal`,
`ItemType.Drainable`, unset globals).

## The checks

| Check | What it catches |
| --- | --- |
| `lua-syntax` | A file the game's compiler refuses. |
| `translation-file` | A `Translate/<LANG>/<Name>.json` whose name `Translator` never loads. |
| `translation-json` | Invalid JSON, a non-string value, or a key given twice (only the last counts). |
| `translation-key` | A literal `getText`/`getTextOrNull` key, or a string literal shaped like one of the mod's keys, that no translation answers. `getTextInternal` picks the file by the key's prefix, so an `IGUI_` key in `Tooltip.json` is reported as being in the wrong file. |
| `translation-extra` | A language with keys English lacks. Missing keys are a note. |
| `translation-placeholder` | A `%` other than `%1`..`%9` or `%%`, or a translation using a placeholder English does not pass. |
| `script-syntax` | Text after a block's last comma (dropped), a value whose comma is missing (it swallows the next line, or the next block's header), `//` (no comment in scripts), a block outside a module. |
| `item-field` | A key `Item.DoParam` does not know; it silently becomes item mod data. |
| `item-legacy-field` | `Type`, `DisplayName`, `TeachedRecipes`, build 41 fields. |
| `item-type` | A missing `ItemType`, or one no game item uses. |
| `item-tag` | A tag without a namespace, which no `tags[]` query matches. |
| `item-no-icon` | An item without `Icon`, moveables included: the crafting window throws listing it. |
| `item-icon` | `Icon = X` with no `Item_X` in a pack or `media/textures`. |
| `item-name` | An item without an `ItemName.json` entry. |
| `item-tooltip` | A `Tooltip` key no translation answers. |
| `item-model` | A `WorldStaticModel`/`StaticModel` naming no model script. |
| `item-sprite` | A `WorldObjectSprite` past the tileset's tiles, without a packed sprite, or in no tileset. |
| `learned-recipe` | `LearnedRecipes` or `ResearchableRecipes` naming no craftRecipe. |
| `model-texture` | A model texture that is packed (a model samples its whole texture, so it would draw a slice of the page) or missing. |
| `recipe-module` | A craftRecipe outside module Base: research and magazines look recipes up by bare name, which resolves only in Base. |
| `recipe-name` | A craftRecipe without a `Recipes.json` entry. |
| `recipe-item` | A recipe input or output that is no item. |
| `recipe-tag` | A `tags[...]` query no item carries. |
| `recipe-hook` | `OnCreate`/`OnTest` naming nothing defined; `OnAddToMenu` dotted (the window does one `rawget` on the globals) or undefined. |
| `sandbox-type` | An option type the parser rejects. |
| `sandbox-option` | No `VERSION = 1`, missing or non-numeric min/max/default/numValues (the option is dropped), a default out of range. |
| `sandbox-label` | A missing `Sandbox_` label for an option (its `translation`, else its short name), its page, or an enum value. |
| `sandbox-var` | `SandboxVars.<Mod>.x` (or `x` on a local alias) that is no declared option, or `SandboxVars.X` that is no vanilla option. |
| `method-name` | `obj:name()` that no exposed class, no Lua and no string function has. Build 42 dropped `PropertyContainer.Is`/`.Val`, and nothing failed until placing a battery bank. |
| `global-name` | A free name that is no local of its file and no global of the engine, the game's Lua or the mod's. `InventoryItemFactory` is a Java class build 42 does not expose. |
| `global-member` | `Class.x` on an exposed class that is none of its static members or nested classes, or `string.x`/`table.x`/`math.x` that the library lacks. |
| `event-name` | `Events.X` that no engine or Lua code registers. |
| `texture-path` | A literal `getTexture`/`tryGetTexture` path that resolves to no packed sprite or file, following `Texture.getSharedTexture`'s order. |
| `require-path` | A `require` naming no Lua file of the mod or game, or differing in case (Linux servers match exactly). |
| `timedaction-complete` | A client-only timed action with `complete()`, which never runs on a multiplayer client. |
| `pack-format` | A mod `.pack` the game could not read. |
| `pack-clash` | A mod sprite named like a vanilla one, which it replaces everywhere. |
| `tile-format` | A `tiledef=` or `pack=` line in mod.info naming no file or a file number outside 100..8189, or a `.tiles` file that does not read and write back byte for byte. |
| `tile-sprite` | A tile with properties but no packed sprite. |
| `tile-item` | A tile's `CustomItem` that is no item. |
| `tile-name` | A tile's `GroupName CustomName` without its `Moveables.json` key. |
| `tile-container` | A tile container without `IGUI_ContainerTitle_<type>`. |
| `stash-building` | A stash's `buildingX`, `buildingY` in no ground-floor room of a building, read from the game's `.lotheader` files. |
| `stash-crate` | A stash crate outside every room of that building: `doBuildingStash` stocks only containers in the house's rooms. |
| `no-input` | No Lua or script files found, so a wrong path cannot pass as a clean mod. |
