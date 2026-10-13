# Renewable Energy

## Commands

- After every change: `dev/static-check.sh` (seconds; compiles every Lua file with the game's compiler and cross-checks scripts, translations, textures and API names) and `dev/validate-server.sh` (boots a headless dedicated server and fails on any error the mod logs).
- Before finishing: `dev/run-debug-client.sh --test`. It runs every in-game test unattended and needs a JDK's `javac` on `PATH` (or `JAVAC` set); `TESTS=<prefix>,...` runs only the tests whose names start with one of them. The dev scripts take a lock, so a run waits while another one's game is up; just run them.
- README and Workshop art: `PROMO=<group> dev/run-debug-client.sh --promo` reshoots one group of screenshots, such as `PROMO=trailer` or `PROMO=models`, in about half a minute and replaces only that group's captures (a wrong name lists the groups); `art/promo/compose.py` then lays out the images in seconds. Iterate on the one group you are changing, and never rerun every group to check one shot. A layout change needs only `compose.py`.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add in-game tests to the dev mod's `dev/RenewableEnergyDevHarness/42/media/lua/client/RenewableEnergy/Debug/RenewableEnergyTests*.lua`, with this mod's fixtures in `RenewableEnergyTestLib.lua` and the shared helpers it inherits from the harness submodule (`dev/harness`, whose README describes it); the game's own test runner executes them. Debug and test code stays out of `Contents/`, which is published. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- `art/models/make.sh` builds every model, icon and tile: edit the parts in `art/models/items.py`, the tile layout in `art/models/tiles.py` and the tile properties in `tools/make_tiles.py`, never the models, textures, tiles, depth maps, `renewable_energy.tiles` or `renewable_energy.pack` they write. Likewise edit `art/promo/compose.py` and `dev/RenewableEnergyDevHarness/.../RenewableEnergyDevPromo.lua`, not the images they produce. The next run overwrites hand edits.
- `.agent/` holds the design docs (`design-ideas.md`, the Release 1 spec, measured loot); it is gitignored, so nothing published may depend on it.
- Comments say why, without repeating values from the code. `DEVELOPMENT.md` holds commands, tips, and game behavior; don't describe the mod's code there.
- Don't add `CLAUDE.md`; this is the only agent instruction file.

## Read when needed

- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo and loot commands.
- Before designing a feature, read `.agent/design-ideas.md`.
