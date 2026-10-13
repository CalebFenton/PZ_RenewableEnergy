# Renewable Energy

## Commands

- After every change: `dev/static-check.sh`. It compiles every Lua file with the game's compiler and cross-checks scripts, translations, textures and API names in seconds. After a change to `Contents/`, also run `dev/validate-server.sh`.
- While you iterate: `dev/run-debug-client.sh --test --changed --stay`, adding `--mp` when the change touches what the server does or sends. Before committing: `dev/run-debug-client.sh --test` and `dev/run-debug-client.sh --test --mp`.
- README and Workshop art: `PROMO=<group> dev/run-debug-client.sh --promo` reshoots one group of screenshots, such as `PROMO=trailer` or `PROMO=models`, and replaces only that group's captures (a wrong name lists the groups); `art/promo/compose.py` then lays out the images in seconds. Reshoot only the group you are changing; a layout change needs only `compose.py`.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add in-game tests to the dev mod's `dev/RenewableEnergyDevHarness/42/media/lua/client/RenewableEnergy/Debug/RenewableEnergyTests*.lua`, with this mod's fixtures in `RenewableEnergyTestLib.lua`. Debug and test code stays out of `Contents/`, which is published. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- Give a new file under `Contents/` or the dev mod a `TEST_MAP` line in `dev/harness.conf` naming the tests that reach its code; without one, `--changed` runs every test.
- `art/models/make.sh` builds every model, icon and tile: edit the parts in `art/models/items.py`, the tile layout in `art/models/tiles.py` and the tile properties in `tools/make_tiles.py`, never the models, textures, tiles, depth maps, `renewable_energy.tiles` or `renewable_energy.pack` they write. Likewise edit `art/promo/compose.py` and `dev/RenewableEnergyDevHarness/.../RenewableEnergyDevPromo.lua`, not the images they produce. The next run overwrites hand edits.
- `.agent/` holds the design docs (`design-ideas.md`, the Release 1 spec, measured loot); it is gitignored, so nothing published may depend on it.
- Comments say why, without repeating values from the code. `DEVELOPMENT.md` holds commands, tips, and game behavior; don't describe the mod's code there.
- Don't add `CLAUDE.md` files; the `AGENTS.md` files hold the agent instructions.

## Read when needed

- Before running in-game tests, handing them to subagents, or debugging a failure or a `LEAK`, read `dev/harness/docs/debugging.md`: which run answers which question, and the traps that cost reruns.
- Before changing anything under `dev/harness`, read `dev/harness/AGENTS.md`: other mods share it.
- Before changing scripts, translations, multiplayer sync, loot, tests, or art, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo and loot commands.
- Before designing a feature, read `.agent/design-ideas.md`.
