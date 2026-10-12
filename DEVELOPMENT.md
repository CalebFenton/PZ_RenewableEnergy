# Developer notes

What to run for each job, and Project Zomboid Build 42 behavior that the mod's code can't show you. Each game fact names its source in the decompiled 42.21.0 Java or the vanilla Lua, so you can check it again after a game update. Published modding docs mostly describe Build 41; when they disagree with the game files, trust the game files.

## Commands

The scripts use the macOS Steam install (set `PZ_APP` to another `Contents` folder) and their own cache under `$TMPDIR` (set `CACHE` to use another), so they never touch your saves, settings, or mod list. They copy the mod into the cache's `mods` folder before every run, rather than linking it, and resolve `$TMPDIR` to its real path, because the game loses the tiles' depth maps otherwise (see [Art](#art)). Only one game, client or server, started by `dev/run-debug-client.sh` or `dev/validate-server.sh` runs at a time; another run waits for it, and takes over a lock its dead owner left (`$TMPDIR/pz-renewable-energy-game.lock`).

- `dev/static-check.sh`: run after every change; it takes seconds. It compiles every Lua file with the game's Kahlua compiler, then `dev/check/check.py` cross-checks the mod against the installed game: translation keys, textures, item and recipe fields, sandbox options, method and global names, requires, and stash house coordinates. `dev/check/README.md` lists every check.
- `dev/validate-server.sh`: boots a dedicated server with only this mod and fails if the mod logs an error.
- `dev/run-debug-client.sh --test`: runs every `renewable_energy_*` test unattended and exits nonzero on a failure or any Lua error. It needs a JDK's `javac`, any version from 8 on. `TESTS=renewable_energy_power_,renewable_energy_client_window` runs only the tests whose names start with one of those prefixes.
- The client runs stop at the first stack trace through the mod's Lua, or at any Lua failure once the harness has started, and print the trace, instead of waiting for the timeout: in debug mode a Lua error stops the game in the error handler, so it never quits on its own.
- `dev/run-debug-client.sh --loot`: measures how often each of the mod's items spawns in each loot list and room container it is in, and prints one line per list. Run it after changing loot, and update the README's tables from it.
- `art/models/make.sh`: rebuilds with Blender (5.2) every item's ground model and texture, the 32 x 32 item icons, the tile sprites and their depth map, `renewable_energy.tiles` and the pack, then writes review sheets of the models, the tiles over a floor diamond, and the icons to `$TMPDIR/renewable-energy-previews`. Edit the parts in `art/models/items.py`, the tile layout in `art/models/tiles.py` and the tile properties in `tools/make_tiles.py`, never the files they write. Keep the tile numbers the same in those two files and in `shared/RenewableEnergy/Sprites.lua`.
- `dev/run-debug-client.sh --art`: builds a stage on open ground near the scenario start (walls with wall panels, every tile and overlay, and every item dropped next to a vanilla car battery for scale) and saves `art_tiles.png`, `art_overlays.png` and `art_items.png` to `<cache>/Screenshots`.
- `dev/run-debug-client.sh --promo`, then `art/promo/compose.py`: builds a homestead battery bank against a house and a stage-0 battery box on open ground at a clear noon, captures them, the status window, every icon and every recipe's names into `art/promo/captures`, then lays them out into `art/promo/images`. Commit the captures, so that a layout change needs only `compose.py`. Both scripts need [uv](https://docs.astral.sh/uv/). The README links the images by relative path. The repository isn't public yet, so `workshop.txt` has no images; once it is, link them from its raw URLs, and remember that renaming an image then breaks the Workshop page.
- `dev/run-debug-client.sh`: starts the debug client with the mod enabled and stops at the main menu.
- `python3 tools/pack_textures.py`: rebuilds `renewable_energy.pack` from the tile sprites in `tools/tiles` and the icons and UI art in `tools/textures`; `art/models/make.sh` runs it. `python3 tools/tiledefs.py <file.tiles> all` prints every tile's properties.

## Debugging by hand

Add `-debug` to the game's Steam launch options to get these in a normal game.

- The **Renewable Energy** scenario under **Scenarios** on the main menu starts a zombie-free world in the morning with an electrician and carpenter who knows every recipe, a screwdriver and a table.
- To run one test, open the debug menu with the bug icon, then **Dev**, **Unit Tests**, **Timed Actions**.
- To see the loot of vanilla lists, right-click the world and choose **UI**, then **Generate Loot UI**.
- Restart the client after changing Lua. `reloadLuaFile()`, which the debug Lua file browser uses, runs the file again but ignores its `Events.*.Add` calls (`LuaCompiler.rewriteEvents`), so the old handlers keep running.
- A dedicated server has no `-debug` argument; it reads only the JVM property `-Ddebug`.
- In debug mode a Lua error stops the game in the error handler, even inside `pcall`.
- In debug mode, vanilla logs errors about fonts, `FluidContainerScript` names, a mannequin zone, missing tiles, and missing icons. None come from this mod.
- `getCore():TakeFullScreenshot("name.png")` writes to `<cachedir>/Screenshots/` without macOS Screen Recording permission.

## Writing tests

- The timed action test runner empties the inventory and calls `clearWornItems()` before each test. Perks, known recipes, modData, world objects, and sandbox options carry over to the next test, and `EveryOneMinute` keeps firing. Write tests with the helpers in `RenewableEnergyTestLib.lua`.
- `ISInventoryPaneContextMenu.OnNewCraft` crafts through the same path as a right-click, and when the game refuses, it queues nothing and says nothing. `HandcraftLogic` can tell you why.
- A table for an `AnySurfaceCraft` recipe must come from `IsoObject.new(square, spriteName, name)`. `IsoObject.new(square, spriteName)` builds a new sprite from the texture alone, so the object looks like a table but has no `Surface`. `findCraftSurface` also skips squares the character can't reach, such as the far side of a wall.
- `getScriptManager():getCraftRecipe(name)` and `instanceItem` return nil for a name that doesn't resolve; check before you index the result.
- A vehicle spawned this frame joins `IsoCell.vehicles` only on the next cell update, so wait a tick before looking for it.

## Ground truth

The game ships its Lua, scripts, and assets unpacked, and its Java decompiles cleanly. The bundled Java has no `jar` tool, so `unzip` and `zip` pick out the `zombie` packages; decompiling them takes about 20 seconds:

```sh
PZC="$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents"
cat ~/Zomboid/version.txt                     # installed version, such as 42.21.0 4a0e9546ec
ln -sfn "$PZC/Java/media" /tmp/pzmedia        # vanilla lua/, scripts/generated/, clothing/, models_X/
mkdir -p /tmp/pztools /tmp/pzclasses /tmp/pzsrc && cd /tmp/pzclasses
curl -sSL -o /tmp/pztools/vineflower.jar https://repo1.maven.org/maven2/org/vineflower/vineflower/1.11.1/vineflower-1.11.1.jar
unzip -q "$PZC/Java/projectzomboid.jar" 'zombie/*' && zip -qr /tmp/pztools/zombie.jar zombie
"$PZC/PlugIns/jre-aarch64/Contents/Home/bin/java" -jar /tmp/pztools/vineflower.jar -dgs=1 -thr=8 -log=WARN \
    "-e=$PZC/Java/projectzomboid.jar" /tmp/pztools/zombie.jar /tmp/pzsrc
```

Start from these files:

- Lua globals are the `@LuaMethod(name = ...)` methods in `zombie/Lua/LuaManager.java`; exposed classes are its `setExposed(X.class)` calls.
- `zombie/Lua/LuaEventManager.java` lists the Lua events. Search for `triggerEvent("Name"` in both the Java and the vanilla Lua to see which side fires each one.
- Script keys are parsed in `zombie/scripting/objects/Item.java` (`DoParam`) and in `CraftRecipe.java`, `InputScript.java`, and `OutputScript.java` under `zombie/scripting/entity/components/crafting/`.
- Vanilla patterns are in `/tmp/pzmedia/lua/shared/TimedActions/` and `/tmp/pzmedia/scripts/generated/`.
- Subscribed Workshop mods, some already ported to Build 42, are in `~/Library/Application Support/Steam/steamapps/workshop/content/108600/`.

## Mod layout and loading

Build 42 lists a mod folder only if it has `common/mod.info` or `<version folder>/mod.info`, and ignores files at the mod root.

- The game uses the child folder with the highest numeric name that is at least 42.0 and at most the game version, comparing major × 1000 + minor and ignoring the patch number. A folder named `42` works for every 42.x release.
- `common/media` loads first, and the version folder overrides files at the same relative path. A mod Lua file at the same relative path as a vanilla file replaces the vanilla file, so keep every Lua file under a `RenewableEnergy` folder. Texture, model and pack sprite names are just as global across mods, which is why every one of them carries the mod's name.
- `tiledef=<file> <number>` gives the tiledef file a number from 100 to 8189 (`ChooseGameInfo`). The number alone decides the tiles' sprite ids, `1048576 + (number - 2) × 262144 + (tileset - 1) × 512 + tile` (`IsoWorld.getSpriteID`), and vanilla uses 1 to 8, so two mods' tiles share ids only if the mods pick the same number. The mod uses 6142, away from the round numbers and the low hundreds other mods tend to pick.
- `versionMin` and `versionMax` in `mod.info` are the only compatibility check (`ChooseGameInfo.Mod.isAvailableSelf`). The mod list shows them as `min - max`, in red when the game is outside the range, and the game doesn't load such a mod. The "unsupported mods" filter only hides mods made for versions before 42.0 (`Core.getBreakModGameVersion()`).
- With Steam running, the game finds mods in `~/Zomboid/mods/*`, in Workshop staging folders (`~/Zomboid/Workshop/*/Contents/mods/*`), and in subscriptions. With `-nosteam` it reads only `<cachedir>/mods`. Two copies with the same `id` conflict, so unsubscribe from the Workshop copy while you develop.
- Leaving a game re-initializes Lua (`IngameState.exit()` calls `LuaManager.init()`), so module-level Lua state starts fresh for every loaded game.

## Scripts

Item and recipe scripts are in `media/scripts/*.txt`. Only `/* */` comments work in them; `//` and `--` don't.

- Set `ItemType = base:normal` (or `base:drainable`, `base:moveable`, and so on). The Build 41 key `Type = Normal` becomes an unknown parameter, and the item has no class.
- An unknown item parameter is copied into every new item's modData (`Item.DoParam`, `defaultModData`), with a `DetailedInfo` warning.
- A `base:moveable` item needs an `Icon`. The inventory draws the tile it places, but the crafting window draws the script item's icon, which is nil without one: an empty square, and `ISCraftInventoryPanel` throws when it lists the item as a possible input. Vanilla gives every moveable an `Icon`.
- Every item that a recipe outputs can be researched for that recipe (`OutputMapper`), and nothing else is offered unless the item lists `ResearchableRecipes`. Research needs two thirds of the recipe's highest skill level (`CraftRecipe.getResearchSkillLevel`).
- A heavy item dropped on the floor, as `Actions.addOrDropItem` does when a craft's output doesn't fit (the main inventory holds 50), turns into an `IsoGenerator` if the item has the `base:generator` tag and a `WorldObjectSprite` (`IsoGridSquare.AddWorldInventoryItem`).
- `ItemName.json` (key `Module.Item`) overwrites `DisplayName`, and vanilla items have no `DisplayName`.
- A bare name resolves only in `module Base` (`ScriptBucketCollection.getScript`): a model in `WorldStaticModel`, and a recipe in `getCraftRecipe(name)`. The game looks recipes up by bare name when researching an item and in the magazine's recipe list, so craftRecipes go in `module Base`, with a prefix against name clashes.
- The item `OnCreate = Some.Lua.func` calls `func(item)` on every instantiation: loot, crafting outputs, debug spawns, loading a save, and a multiplayer client receiving the item. When loading, `item:load()` then replaces the modData, but only if the saved modData isn't empty, so always write at least one key. Uses set on a drainable item in OnCreate are overwritten afterwards.

### craftRecipe

Build 41 `recipe` blocks no longer load.

- Lines without `=`, such as the Build 41 `Time:30`, are skipped without an error. Unknown keys log an error, and throw in debug mode.
- Input flags in `flags[...]` are case-sensitive enum names, and `[...]` lists must not contain spaces. `NoBrokenItems` has no effect; broken items are always refused unless an input sets `AllowDestroyedItem`.
- Use `tags[base:screwdriver]` for tool tags and `mode:keep` for tools. An input line can list items and tags together, `[Base.Glasses_Reading] tags[base:magnifier]`, and accepts any of them (`InputScript.OnPostWorldDictionaryInit`).
- An input of a drainable item counts uses: `item 1 [Base.Glue]` takes one of the tube's five uses. `flags[ItemCount]` takes whole items instead.
- Worn items count as inputs, and a worn `mode:keep` tool stays worn. `flags[IsNotWorn]` refuses worn and equipped items.
- `Tags = AnySurfaceCraft` needs a table or counter within 3 tiles (`HandcraftLogic`), and the craft walks the character to it. A tag other than `InHandCraft`, `AnySurfaceCraft`, `EntityRecipe`, and `Outdoors`, on a recipe without one of them, makes it need a crafting bench entity (`CraftRecipe.requiresSpecificWorkstation`). The `Electrical` tag does nothing else; `category = Electrical` sets the crafting window category.
- Every recipe needs light unless it has the `CanBeDoneInDark` tag (`CraftRecipeData`, `IsoPlayer.tooDarkToRead`).
- `xpAward = Electricity:10` and `SkillRequired = Electricity:2` replace Build 41 `OnGiveXP` and `SkillRequired:`.
- `OnCreate(craftRecipeData, character)` runs once, locally in single player and on the server in multiplayer, after the outputs were sent to the client. Call `result:syncItemFields()` after changing an output.
- `OnTest(item, character)` runs for every candidate input item, tools included.
- `OnTest` and `OnCreate` accept dotted Lua paths (`LuaManager.getFunctionObject`). `OnAddToMenu(params)` must be a plain global name, because the crafting window reads it with a raw `_G` lookup.
- `craftRecipeData:getAllConsumedItems()` excludes `mode:keep` inputs, and `getFirstCreatedItem()` returns the output. No flag copies modData to the output, and vanilla adds per-input counter keys to the output's modData after OnCreate.
- Recipes can't be switched on and off at runtime. To gate one with a sandbox option, use OnTest, which blocks crafting on the server too, and OnAddToMenu, which hides the recipe.
- `CraftRecipe:clearRequiredSkills()` and `addRequiredSkill(perk, level)` change a recipe's skill requirement in place, and the can-craft check, craft time, and every crafting window read that list. Single player, the server, and each client hold their own recipe objects, rebuilt from the scripts whenever Lua reloads, so apply the change on every side. No event fires when an admin changes sandbox options mid-game (`GameServer.receiveSandboxOptions`).
- Build 41 `fixing` blocks still parse, but only with `=`: `Require = ...`, `Fixer = ...`.

### Sandbox options

`media/sandbox-options.txt` must start with `VERSION = 1,`. Option types are `boolean`, `integer`, `double`, `enum`, and `string`. The translation keys are `Sandbox_<translation>` and `Sandbox_<translation>_tooltip` for an option, `Sandbox_<valueTranslation>_option<N>` for enum values numbered from 1, and `Sandbox_<page>` for the page title.

`valueTranslation` is read only for `enum` options (`SandboxOptions.java`, `CustomEnumSandboxOption`).

`SandboxVars.<Table>.<Key>` holds every option of every active mod as soon as Lua loads (`shared/Sandbox/SandboxVars.lua` calls `initSandboxVars()`), and the setters reject values outside `min` and `max` (`DoubleConfigOption.setValue`). Read options without Lua defaults, which would hide a misspelled option name.

## Translations

The game loads only JSON translations, from `media/lua/shared/Translate/<LANG>/<File>.json`, and ignores `.txt` translation files.

- File names that load include `ItemName`, `Recipes`, `IG_UI`, `Tooltip`, `ContextMenu`, `Sandbox`, and `UI` (`Translator.java`).
- Item keys are `"Module.Item"`, and craftRecipe keys are the bare recipe name. Prefixed keys go in the matching file: `IGUI_` keys in `IG_UI.json`, `Tooltip_` keys in `Tooltip.json`.
- Debug builds parse strict JSON, without comments or trailing commas. Write `%%` for a literal percent sign.
- Vanilla keys such as `ContextMenu_Turn_On`, `ContextMenu_AddBattery`, and `ContextMenu_Remove_Battery` are already translated into every language.

## Lua runtime

### Who runs what

| Context | `isClient()` | `isServer()` | Lua that runs |
|---|---|---|---|
| Single player | false | false | Client, shared, and server Lua in one state |
| Multiplayer client | true | false | Client, shared, and server Lua; guard server handlers with `isClient()` |
| Dedicated server | false | true | Shared and server Lua; client Lua is only checksummed |

- Server Lua loads after client Lua, so client Lua can't `require` a server file at load time. It has to require it at runtime, when `require` hands back the loaded file's table.
- `getVehicleById` returns nil in single player, because vehicles are registered with `VehicleManager` only on a server (`BaseVehicle.createPhysics`). Find a vehicle through the squares it stands on instead.

### State and syncing

- `item:syncItemFields()` sends an item's modData, uses, and condition to the other side: from the server to the player whose inventory holds it, or from a client to the server. The global `syncItemFields(player, item)` does the same for that player. Both do nothing in single player.
- On the server, `Actions.addOrDropItem(character, item)` adds and syncs an item. To remove one, call `container:Remove(item)` and then `sendRemoveItemFromContainer(container, item)`; the send does nothing outside the server.
- A client sends its whole player modData to the server (`transmitModData`), and the server replaces its copy with it. ISHotbar does this after every clothing change, so anything the server writes to player modData can disappear.
- The Global Object System (`zombie/globalObjects`) saves each object's modData keys with the world even while its chunk is unloaded, and `setObjectSyncKeys` sends those keys to every client, in single player too.
- A system registered with `SGlobalObjects.registerSystem` must put a `getInitialStateForClient` function in its modData, or the game throws when a client connects (`SGlobalObjectSystem.getInitialStateForClient`). `SGlobalObjectSystem.lua` defines one for the systems derived from it.
- A container's `AcceptItemFunction` filter is not saved with the container. Set it again whenever the object loads (`MapObjects.OnLoadWithSprite`) and whenever it is placed (`OnObjectAdded`), on every side.

### Timed actions in multiplayer

- If an action class has `complete()`, the client runs `start()`, `update()`, and `perform()`, and the server runs `complete()`. Single player runs `perform()` and then `complete()` in the same tick (`IsoGameCharacter`'s action loop).
- The server rebuilds the action by calling `<Class>:new()` with the values of the fields named like `new()`'s parameters, in parameter order (`NetTimedAction`). Parameter names must equal field names, and every argument must be serializable. Items are sent as container plus id, so they must be in a container. An unsupported argument type is dropped and shifts the arguments after it.
- The server never calls `isValid()`, `update()`, or `perform()`, so check the action again in `complete()`; returning `false` rejects it.
- On the client, fetch items again by id in `start()`, as vanilla does, because server syncs can replace the item objects.

### Events

| Event | Where it fires |
|---|---|
| `EveryOneMinute` | Single player, multiplayer client, and server. It fires at most once per tick however much game time passed, so compute elapsed time from `getGameTime():getWorldAgeHours()`. |
| `OnInitGlobalModData` | Single player, server, and multiplayer client, once per loaded game, after the sandbox options load. A client has received the server's options by then. |
| `OnLoadedMapZones` | Every side, after `StashSystem.load` (`IsoWorld.init`). |
| `OnGameStart` | Only where `IngameState.enter()` runs, which a dedicated server never calls, so never on a dedicated server. |
| `OnObjectAboutToBeRemoved` | Whenever `IsoGridSquare.RemoveTileObject` runs: picking an object up, destroying it, and lifting it to reorder a square. |
| `OnServerCommand` | Multiplayer clients, for `sendServerCommand()` from the server. |
| `OnFillContainer` | Room containers, corpses, zombies and vehicle containers (`BaseVehicle.randomizeContainer`), but not `ItemPickerJava.fillContainerType` fills such as stashes and `RBSafehouse`. Two callers pass a bag's loot table instead of a container (`ItemPickerJava.fillContainerInternal` and `doRollItemInternal`). |

### Generators

A battery bank is an `IsoGenerator`, so everything a generator does applies to it.

- `setActivated` is not a plain setter: it plays the start or stop sound (prefixed by the tile's `GeneratorSound` property, else `Generator`), updates every fridge in range, sets the building's toxicity, and syncs. Measure the load with `setSurroundingElectricity()` and `getTotalPowerUsing()`, which work whether or not the generator runs.
- `getTotalPowerUsing()` is multiplied by the GeneratorFuelConsumption sandbox option (default 0.1).
- Toxicity belongs to the whole building, and gas generators set it when they start and once an in-game hour after. Restore only what your own `setActivated` changed.
- Squares stay powered after a running generator is removed, until `setSurroundingElectricity()` runs on it switched off (`IsoChunk.isGeneratorPoweringSquare`). Switch it off before it leaves the square.
- `IsoGenerator.update()` is what acts on `chunkLoaded`'s request to repower squares in newly loaded chunks; a generator taken out of the cell's process list has to call `setSurroundingElectricity()` itself.
- `setConnected`, `setCondition` and `setFuel` sync on the server. Call them after `transmitCompleteItemToClients()`, because a sync names the object by its index on the square.
- An overlay changed with `addAttachedAnimSpriteByName` reaches clients only through `transmitUpdatedSpriteToClients()`.
- Vanilla's generator context menu shows on any `IsoGenerator`, so hide it on banks: its **Take Generator** would hand back a `Base.Generator`.

### UI

- To add inventory context menu options, handle `Events.OnFillInventoryObjectContextMenu(playerNum, context, items)` and pass `items` through `ISInventoryPane.getActualItems(items)`, which unpacks stacks.
- `ISToolTipInv` also shows things that aren't items, such as fluid containers and energy resources. Check `instanceof(x, "InventoryItem")` before calling item methods.

## Art

- Build 42 draws tiles from 128 x 256 sprites (2x; the mod ships only those), in an orthographic projection 30 degrees above the horizon: a square's floor is a 128 x 64 diamond at the bottom of the cell, its centre at pixel (64, 224). A metre across the floor is 64√2 pixels, and a storey is 2.44949 metres, drawn 192 pixels tall (`TileDepthTexture`, `TileGeometryUtils`). Every one of the game's 4,304 item icons is 32 x 32 (in `UI.pack` and `UI2.pack`).
- Since Build 42 each tile pixel is drawn at a depth read from a depth map. A mod's `common/media/depthmaps/DEPTH_<tileset>.png`, eight tiles wide like the tileset, loads only if the mod has a `common/media/tileGeometry.txt` (`TileDepthTextureManager.init`), which may hold no geometry; the game then logs that the mod overrides `media/tilegeometry.txt`, which is harmless, because the game reads its own by absolute path. A depth pixel is 1 − (east + south) / 4 − height / storey / 2, measured from the square's north-west floor corner in squares and storeys (`TileGeometryUtils.getNormalizedDepth`), and a sprite pixel whose depth pixel is transparent is not drawn at all (`tileWithDepth.frag`). A tile without a depth map is drawn as a box filling its square to the ceiling, unless it is a floor or a wall overlay (`IsoSprite.setupTileDepth`).
- The game reads depth maps by absolute path and refuses any path outside the mod folders, the cache dir and the game (`ZomboidFileSystem.validatePrefix`). It compares the paths without resolving symlinks, so a symlinked mod folder, or a cache dir under macOS's `/var`, which is `/private/var`, loses its depth maps.
- A wall-hung moveable has `MoveType = WallObject` and hangs on its own square: `Facing = S` with `attachedN` on the north wall, `Facing = E` with `attachedW` on the west wall (`ISMoveableSpriteProps.getWallForFacing`). `Noffset`, `Soffset`, `Eoffset` and `Woffset` give the tile number offsets of the other facings, which the placing cursor rotates through, and `CustomItem` names the item that picking the tile up gives.
- A container holds at most 100 weight units, whatever its `ContainerCapacity` (`ItemContainer.MAX_CAPACITY`).
- Ground models exported from Blender in metres with HearingAid's FBX settings and `scale = 1` in the model script are drawn at their real size next to the game's own items.

## Loot

`IsoWorld.init` fires `OnDistributionMerge` and `OnPostDistributionMerge`, then loads the save's sandbox options, then calls `ItemPickerJava.Parse()`, then fires `OnInitGlobalModData`. When a single player game is continued, the merge events therefore see the sandbox options of the default preset. Loot that depends on sandbox options has to be added in `OnInitGlobalModData`, followed by another `ItemPickerJava.Parse()`.

- The chance per roll is ⌈weight × 100 × loot category multiplier + zombie density bonus⌉ in 10,000, and a container rolls `rolls` times (`ItemPickerJava.getActualSpawnChance`). Every positive chance rounds up to at least 1 in 10,000, so at the default multiplier of 0.6 a weight below 1/60 spawns more often than it says. The multiplier is a float a little above 0.6, so a product that should come out whole rounds up too: a weight of 0.25 gives 16 in 10,000. The density bonus is added, not multiplied, so it's the same for every entry whatever its weight. The Lucky and Unlucky traits no longer affect loot.
- `items` lists are flat name and weight pairs, so always append both. Unknown item names are dropped, with a message only in debug logs.
- `junk` lists roll with the loot category multiplier fixed at 1.0 and weights × 1.4, so the loot rarity settings don't scale them. They are often shared by reference (`ClutterTables.*`), so don't add to them.
- A corpse rolls its loot when it's first opened or its square first loads: `SuburbsDistributions.all.Outfit_<outfit>`, and then `inventorymale` or `inventoryfemale` unless the outfit table sets `defaultInventoryLoot = false`. The comment in vanilla `Distributions.lua` that says outfit tables replace the gendered ones is wrong.
- `ItemPickerJava.fillContainer(container, nil)` works without a player, as loot respawn does. A container marked explored is never filled again, so fill one before `setExplored(true)`.
- Loot respawn refills any explored container below `MaxItemsForLootRespawn` in a town or trailer park zone, generators' containers included (`LootRespawn.respawnInContainer`). Give a container type that players stock an empty loot table.
- `ZombRand(min, max)` never returns `max`.

## Workshop page

- The description is limited to 8000 bytes, BBCode included. `[table]` renders there.
- The in-game Workshop screen uploads `Contents/` and `preview.png`, which must be a square PNG of 256 or 512 pixels and at most 1 MB. The other files at the repository root aren't uploaded. Tags must come from the game's `media/WorkshopTags.txt`.

## Release checklist

1. `dev/static-check.sh`, `dev/validate-server.sh` and `dev/run-debug-client.sh --test` must pass.
2. Bump `modversion` in `42/mod.info`. Raise `versionMin` when the mod starts depending on a newer game version.
3. Update `workshop.txt` and `README.md`, and run `dev/run-debug-client.sh --promo` and `art/promo/compose.py` if the look or the names changed.
4. Upload from the in-game Workshop screen.
