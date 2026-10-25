# Project Viewpoint compatibility: research notes

Research for a later plan to make the mod work well under [Project Viewpoint](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528), a ZombieBuddy Java mod (mod id `Viewpoint`) that draws the game in true 3D, first and third person. Nothing here has been built or tried in game yet. The facts come from reading Viewpoint **0.1.6.1** (`viewpoint/build.properties`, dated 2026-10-16) decompiled, its Lua, and two packs that already target it. Paths like `world/TileMeshes.java:119` are in the decompiled `viewpoint` package; recheck them after a Viewpoint update, since it is alpha and changes often. `[INFERENCE]` marks what was reasoned rather than read.

We read Viewpoint's code only to interoperate with it. Its licence (proprietary, all rights reserved) forbids redistributing, modifying or "decompiling for reuse", so copy nothing from it into this repository; a pack of our own assets registered through its public Lua call bundles none of its files.

## Getting the sources again

Viewpoint and the example packs download anonymously; the game's bundled Java runs Vineflower (see `DEVELOPMENT.md`, Ground truth, for `/tmp/pztools/vineflower.jar`):

```sh
mkdir -p /tmp/steamcmd && cd /tmp/steamcmd
curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz | tar xz
./steamcmd.sh +force_install_dir /tmp/steamcmd/dl +login anonymous \
    +workshop_download_item 108600 3809306528 +workshop_download_item 108600 3810302175 +quit
W=/tmp/steamcmd/dl/steamapps/workshop/content/108600
"$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/PlugIns/jre-aarch64/Contents/Home/bin/java" \
    -jar /tmp/pztools/vineflower.jar -dgs=1 --silent "$W/3809306528/mods/Viewpoint/42/media/java/client/Viewpoint.jar" /tmp/steamcmd/vpsrc/
```

- `3809306528`: Viewpoint. Lua in `mods/Viewpoint/42/media/lua/client/` (`Viewpoint_Interact.lua` is the menu harvester).
- `3810302175`: "6244 3D models for Viewpoint" (mod id `PZVoxelStudioViewpoint`, 450 MB), the pack Viewpoint's page links. `common/media/lua/client/PZVoxelStudioViewpoint.lua` registers 16 manifests in `common/media/voxel-studio/`.
- Plysken Solar Revolution (`3725311427`, subscribed locally): `42.1/media/lua/client/PSR/PSR_Viewpoint.lua` and `common/media/viewpoint/psr.properties`, the smallest working example, and a solar mod like ours.

## Loading and platform

- Client-only Java mod: mod.info has `require=\ZombieBuddy`, `ZBVersionMin=2.3.0`, `javaJarFile=media/java/client/Viewpoint.jar`, `versionMin=versionMax=42.21`. Servers don't need it; ZombieBuddy skips `media/java/client/` jars on dedicated servers.
- Pinned to one game build: `platform/BuildPin.java:13-14` compares `projectzomboid.jar`'s SHA-256 with Build 42.21.0's, and first person stays off on a mismatch. Our installed 42.21.0 matches (checked).
- ZombieBuddy is a Java agent: `ZombieBuddy.jar` in the game's `Contents/Java/` plus `-javaagent:ZombieBuddy.jar` on the JVM, and both mods enabled. It asks once to approve Viewpoint.jar's hash (`~/.zombie_buddy/mod_approvals.json`). Our harness (`dev/harness/bin/run-client.sh`, `lib/harness.sh`) passes no agent and writes a fixed three-mod `default.txt`, so it can't load Viewpoint as it stands.
- macOS is unsupported: nothing refuses, but the setup window warns (`platform/UnsupportedGraphics.java:14-39`). Shaders are GLSL 330 and some texture unit numbers exceed 140 (`Gl.java:~107`) [INFERENCE: beyond Apple's GL 4.1]. The unofficial Apple Silicon patch (Workshop `3812168749`, replaces the jar and adds an OpenGL bridge) is titled outdated and its author stopped updating it. In-game checks therefore need Windows or Linux.
- O toggles 3D, Shift+O first/third person, middle mouse toggles the cursor, Delete opens settings. With 3D off vanilla `IsoCell.render` runs (`FP.java:140-149`), so one session can compare both views.
- Lua API, global `Viewpoint` (no Lua events at all):
  - `Viewpoint.ModelPacks.register(modId, manifestPath) -> boolean` (`ModelPacksLua.java`).
  - `Viewpoint.View.next()`: `"first"` means 3D is off, `"third"` first person is on, `"isometric"` third person is on; `View.cycle()` (`ViewLua.java`, `FP.java:286-292`).
  - `Viewpoint.Mouse.worldX()/worldY()`: the 3D hit, cursor mode only. `Viewpoint.Loot.setEnabled(bool)`.
  - Detect it with `Viewpoint and Viewpoint.ModelPacks`.

## How Viewpoint draws a tile object

Per object, in order (`world/WorldMesher.java:157-172`, `world/TileMeshes.java:59-137`):

1. **A model-pack bind on the main sprite** wins over everything, including a sprite model (`PackGather.object`, `world/PackGather.java:34-50`).
2. **A vanilla sprite model** (`getSpriteModel()` with a model script): drawn every frame through vanilla `IsoObjectModelDrawer.renderMain` (`models/Models.java:36-72`), the whole object including its attached sprites. Only objects that had the model when their chunk level was gathered, and only within about 5 chunks (`ChunkWalk`).
3. **Floor-layer sprites** (`renderLayer == 1` or `solidfloor`): flattened, with their overlay and attached sprites, into baked floor art (`world/FloorGather.java:139-165`).
4. **Everything else**: plants become crossed cards; walls, windows and doors edge quads; otherwise the tile's **vanilla `"game"` tile geometry** (`TileMeshes.java:119-136`), with the sprite texture mapped on. Viewpoint never reads a mod's own geometry, although vanilla loads it under the mod's id (`zombie/tileDepth/TileGeometryManager.java:30-56, 102`). Depth maps are unused.
5. **No geometry**: a vertical quad on the N or W edge if the sprite has `cutN/W` or a DoorWall, Window, collide, Hoppable, TallHoppable or transparent N/W flag; otherwise `TileMesh.EMPTY`, and the object is **not drawn** (`TileMeshes.java:101-116`, `WorldMesher.java:125`). Its attached and overlay sprites go with it. `IsHigh`/`IsLow` are never read.

Attached anim sprites and `overlaySprite` (container overlays too):
- On an **unbound** object they are painted onto the parent's tile mesh (`WorldMesher.java:212-275`); pixels outside the parent's shape are lost.
- On a **bound** object each is drawn only if its own sprite name has a bind, placed by its own bind in the square's frame; unbound ones are dropped (`PackGather.java:38-45, 52-60`). The parent bind's rotation and offset are not inherited, nor the sprite instance's offsets, tint, alpha or frame.

Rebuilds (`Patch_InvalidateLevel`, `Patch_InvalidateAll`, `world/ChunkCache.java:~371`): vanilla's `FBORenderLevels` invalidations rebuild the whole 8×8 chunk level on worker threads, then crossfade over about 400 ms (`ChunkBuilds.rebuild`). `setSprite(IsoSprite)`, `addAttachedAnimSpriteInstance`, `RemoveAttachedAnim(s)` and `setOverlaySprite` invalidate (OBJECT_MODIFY), on the game thread and, for attached sprites, only with `PerformanceSettings.fboRenderChunk` on. **`setSpriteModelName` does not invalidate** (`zombie/iso/IsoObject.java:6274-6278`); switching between models of an object already drawn as one is picked up every frame, since `getSpriteModel()` is re-resolved.

Ground items (`IsoWorldInventoryObject`) use vanilla `WorldItemModelDrawer` when 3D ground items are on and the item has a model, else a flat decal (`world/FloorDecals.java:43-71`). Vehicles come from vanilla's prepared render data (`models/VehicleCapture.java`) [INFERENCE: part `setModelVisible` is honoured].

## Model packs

Registration (`packs/ModelPacks.java:37-63, 179-199`):
- `modId` must be the mod.info `id`, ours `cf_renewable_energy`. A leading `media/` is stripped and the file is looked for under `42/media`, then `common/media`.
- Each (modId, path) registers once; a manifest is never re-read. All of a mod's manifests share one on/off setting, `packs.<modId>`, labelled with the mod's name.
- Later registrations win on the same sprite name (`ModelPacks.rebind`, :147-157); within one file the last line wins.
- Register on `OnGameBoot`, `OnGameStart` and at file load, inside `pcall`, as both example packs do.

Manifest grammar (`packs/PackManifest.java:25-90`); every other key, `version` included, is ignored silently; `#` comments; at most 5 errors are logged as `[Viewpoint] model pack <id>: ...`:

```properties
id=renewable-energy
name=Renewable Energy
model.<modelId>=<obj path relative to this file>
bind.<exact IsoSprite name>=<modelId>,<degrees>,<x>,<y>,<z>,<scale>
```

- Exact, case-sensitive `IsoSprite.name` lookup; no wildcards or ranges. Mod tilesets work (PSR binds `solarmod_tileset_01_0..38`). A bind naming an undeclared model is dropped. Roof sprites can't be bound.
- `degrees` turns about the vertical: positive sends east to south (clockwise from above) [compass wording INFERENCE; algebra checked in `shaders/lib/pack_model.glsl`]. Ignored on stairs.
- `x, y, z`: added after rotation, world east, south, up, in tile units; one storey is 2.4494896 (√6) units (`Recipe.java:124-142`).
- `scale` > 0, applied before rotation.
- One bind line per facing sprite; no facing field.

Mesh and texture (`packs/ObjReader.java`, `PackLoads.java:72-96`, `ArtReader.java`, `render/PackArt.java`, `render/PackArena.java`):
- OBJ only, read for `v`, `vt`, `vn`, `f`, `mtllib`. OBJ +X east, +Y south, +Z up; 1 unit = one tile width; origin at the tile centre on the floor. A mesh lying inside 0..1 and spanning over 0.7 in X and Y is shifted by −0.5 (corner-origin models re-centred).
- Faces are drawn one-sided (`FLAG_SINGLE_SIDED`); Voxel Studio ships a reversed copy where both sides show.
- One material: the first `map_Kd` PNG of the `mtllib`. `Kd`, vertex colours, normal, roughness and emissive maps are ignored; no PBR or glow. A palette PNG with UVs on swatches works (PSR).
- UVs map into a shared atlas, so no tiling or wrapping outside 0..1. Texture at most 2040×2040; a model at most 131,072 vertices.
- A model with no `mtllib`, no `map_Kd` or no triangles fails to load and its sprites keep the tile path.
- Settings: `graphics.modelPacks` (on), `lod.packRing` (models within 6 chunks; beyond it bound sprites go back to the tile path, where ours are empty), GPU pool `memory.packMiB` 768 MiB.

## Interaction

**Look mode** (default; cursor captured and parked at screen centre, `input/MouseButtons.java:28-60`):
- A ray from the view picks among boxes for objects on the player's 3×3 squares that `canReachTo` (`interact/LootTargets.java:89-124, 259-312`). Excluded: floor-flagged objects (solidfloor, FloorOverlay, attachedFloor, IsFloorAttached, transparentFloor), wall flags unless a door, window, thumpable, switch or hoppable, and ground items. IsoGenerator and IsoThumpable are fine.
- Box for an object with an empty mesh: 1×1, a third of a storey tall; an N/W edge owner gets a slab (`interact/LootBoxes.java:57-102`). A bound object uses its model's bounds.
- When the aim rests on an object, `ViewpointInteract.harvest` (`Viewpoint_Interact.lua:245-271`) calls vanilla `ISWorldObjectContextMenu.createMenu(playerNum, {object}, isoX, isoY)`, so `OnPreFill`/`OnFillWorldObjectContextMenu` fire, hidden, every time the aim settles or the object's sprite changes. Not while paused, nor while a placement cursor is out.
- The menu is flattened into Viewpoint's own list, run with F. Kept: options whose `target` or `param1..10`, or a plain table among them one level deep, is the aimed object (`whose`, `Viewpoint_Interact.lua:82-98`). Options referencing only another IsoObject (characters excepted) or a vehicle are dropped; options referencing no object are kept only inside a submenu, and a submenu group is dropped unless one entry is owned. **Tooltips are dropped**; `notAvailable` options show greyed. Walk-to, sit, grab, debug and every `ISVehicleMenu` function are skipped.
- Vehicles: `harvestVehicle` calls `ISVehicleMenu.showRadialMenuOutside(player)` with `getPlayerRadialMenu` replaced by a recorder of `addSlice` and `ISVehicleMenu.getVehicleToInteractWith` returning the aimed vehicle (`Viewpoint_Interact.lua:290-338`). World-menu options built from `IsoObjectPicker:PickVehicle` are lost in this mode.

**Cursor mode** (middle mouse; also while paused): the depth under the cursor picks the object (`interact/MouseTargets.java:121-247`); `IsoObjectPicker.ContextPick` and the `Pick*` methods, `PickVehicle` among them, return what was hit (`Hooks.java:141-182`), and the real vanilla menu shows with tooltips and every hook. Only drawn geometry can be hit; a hit on the floor returns the floor tile, whose square still carries the objects.

Not supported in 3D: placement. `IsoCell.render` and `IsoCursor.render` are skipped, so no ghost tile, and the placed square comes from the isometric unprojection of the mouse (`UIManager.getPickedTile`); ISMoveableCursor and the build-entity cursor need the isometric view. `IsoObject.setHighlighted` is never read. Lua `isoToScreenX/Y` are unpatched (isometric answers).

## Lights, weather, UI

- `IsoCell.getLamppostPositions()` lamps and room lights are drawn as per-tile flood-fill light and, for the 48 nearest within 24 tiles, per-pixel lights, some with shadows (`light/LightSources.java:39-70`, `light/Lights.java`). Radius capped at 20. Each colour channel is doubled and clamped, so 0.5 or more is full (`LightSources.java:78-80`). On/off comes from vanilla `active`, so generator-powered light switches follow vanilla; `Patch_SwitchPower` caches `hasElectricityAround` 250 ms.
- Vehicle headlights are spot lights from `VehicleLight` parts (`light/Headlights.java`). `setWindowLightsOn` only makes the lights texture glow on the glass; it casts no light.
- No surface snow of its own: vanilla ground snow decals on exterior floors, snow sprite variants on unbound objects, its own 3D falling snow. Bound models ignore snow sprites.
- Re-projected UI: the player's halo note (`HaloTextHelper`), chat, radio text, player 0's progress bar (`game/WorldText.java`, `game/ProgressBar.java`). Screen-space windows are unaffected.
- Single-player loot rolls for unexplored containers are deferred and filled nearest first even with 3D off, followed by `ItemPickerJava.updateOverlaySprite` (`game/LootRolls.java`).

## What it means for this mod

### Drawn today

| Thing | Under Viewpoint, unchanged | Why |
|---|---|---|
| Battery boxes, racks, banks; ground racks; wall panels; gas heater; digesters; gasifiers; crate; garden light; failsafe; cell charger | Invisible nearby, with their overlays | Empty mesh: no `"game"` geometry, no edge flags (step 5 above) |
| Flat panel (`RenderLayer=Floor`) | Flat, baked into the floor with its cracks and snow | Floor path |
| Wind chargers | Drawn and turning, near only | Sprite models; a freshly built one may stay invisible until its level rebuilds, since `setSpriteModelName` doesn't invalidate; nothing beyond about 5 chunks |
| Gas kit and pipes on vanilla generators | Painted onto the generator's shape; dropped when a pack (Voxel Studio) binds `appliances_misc_01_0..15` | Overlay rules |
| Ground items, the arrow-board trailer, garden lights and the trailer's ground light, bank-powered lamps, halo notes, our windows | Work [INFERENCE for items and trailer parts] | Vanilla paths Viewpoint reuses |
| Status window's source highlight | Not drawn | `setHighlighted` unread |

Sprite names in `RenewableEnergy/Sprites.lua`: tilesets `renewable_energy_01` (104 placed tiles with properties in `tools/make_tiles.py`, the legacy save-compatibility tiles among them, plus about 308 overlays) and `renewable_energy_02` (444 bank-fill overlays for the E, N and W facings). About 860 names in all. Runtime changes: overlays through `RenewableEnergy.showOverlays/showOverlay` (`Utilities.lua`), tile swaps through `showTile`/`setEntityTile`, the crate through container overlays, rotors through `WindSpin.lua`.

### Menus

- Our options pass the bank, source, light, digester or gasifier as a parameter, so look mode keeps them. Refusals made with no arguments (`Needs.refuse(menu:addOption(label))`) survive only inside a submenu, and their tooltip reasons are lost.
- Look mode targets one object. Our hooks find their object by scanning the square (`Needs.findClicked`), so aiming at another object on the same square (a generator under a failsafe, a vanilla object beside a bank) builds our options referencing our object, not the aimed one, and they are dropped.
- Lost in look mode: Seal Cracked Panel, Repair Frame and Attach/Detach Solar Maintainer (`UI/Menu.lua`, found with `PickVehicle`). Kept: the trailer's radial slices (`UI/BatteryBoxLid.lua` uses the globals at call time and `addSlice`).
- The hooks have no side effects (no commands, sounds or state), which matters because harvest runs them unseen and often.
- The pre-fill hook in `!_RenewableEnergy_ContextMenu.lua` still runs, so banks keep hiding vanilla's generator menu.

### Requirements found so far

1. A model pack, generated by `art/models/make.sh` from the same Blender scenes as the tiles (generated files are never hand-edited): OBJ + MTL + PNG per model, a manifest, and a client Lua file that registers it when `Viewpoint.ModelPacks` exists. Lives under `common/media/viewpoint/` [proposed].
2. Binds for every placed sprite and every state (lit/off, digester tiers and barrels, blade materials, legacy tiles), each facing its own line.
3. Binds for every overlay that should show on a bound object: battery slots, meters, snow, cracks, gas holders, scrubbers, glow, crate container overlays, and the gas kit and pipes on vanilla generators (exported in the tile's frame, so `,0,0,0,0,1`).
4. No bind on wind-charger tiles (it would replace the sprite model). Invalidate the level once after first setting a rotor's sprite model on a new charger.
5. Static checks: every sprite in `Sprites.lua` that is placed or overlaid has a bind; every bind's model is declared and exists; every OBJ has `mtllib` and `map_Kd`, the PNG is within 2040×2040.
6. Player guide: placement needs the isometric view; cursor mode for the vehicle options and tooltips.

### Open questions for the plan

- Scope: placed tiles only (objects visible, state not), or the full set with overlays (about 860 binds). The charge meter and battery fill are how players read a bank.
- Models: reuse one mesh across facings with `degrees`, or export each sprite pre-transformed with `,0,0,0,0,1` as Voxel Studio does. Texture: per-model PNG, or a palette or atlas shared by many models. Single-sided faces need closed, outward-facing meshes.
- Generator overlays: binding them gives a gas kit that may not line up with another pack's generator model. Measure against Voxel Studio's models.
- Distant objects: beyond the pack ring, bound sprites fall back to empty meshes. Can anything be done short of geometry Viewpoint reads? [Writing our tiles into vanilla's `"game"` geometry set at runtime would be a hack against vanilla's tile editor data; untested whether Lua can reach `TileGeometryManager`.]
- Menus: move or duplicate the vehicle options into the radial menu? Pass the aimed object as well, so options from a square scan survive when aiming at a neighbour? Put refusal reasons in the label rather than the tooltip under Viewpoint?
- Rebuild cost: every overlay change rebuilds an 8×8 level. Banks change meter and fill as charge moves, so check how often a bank's overlays change and whether that causes visible crossfades.
- Verification: a Windows or Linux machine with ZombieBuddy and Viewpoint, or a harness option for a Java agent and extra mods. On this Mac, static checks only.
