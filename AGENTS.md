# Renewable Energy

## Commands

- After every change: `dev/static-check.sh`. It compiles every Lua file with the game's compiler and cross-checks scripts, translations, textures and API names in seconds. After a change to `Contents/`, also run `dev/validate-server.sh`.
- While you iterate: `dev/run-debug-client.sh --test --changed --stay`, adding `--mp` when the change touches what the server does or sends.
- Before committing: `dev/run-debug-client.sh --test` and `dev/run-debug-client.sh --test --mp`.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts, and decompiled Java, not web docs or memory. Most published modding docs describe Build 41, and their APIs fail silently in Build 42.
- Add in-game tests to `dev/RenewableEnergyDevHarness/42/media/lua/client/RenewableEnergy/Debug/RenewableEnergyTests*.lua`, with this mod's fixtures in `RenewableEnergyTestLib.lua`. Don't write standalone Lua tests with stubbed game APIs; the stubs encode guesses about the game, which is what the tests must check.
- Test a chance by setting the roll on either side of it (`T.forceRoll`, `Helpers.forceRolls`), never by rolling many times and comparing the share; new chances go through `RenewableEnergy.Chance.hit`. Test the mod's decisions, not the game's systems: feed the mod's function its inputs rather than driving vehicle physics, vanilla loot rolls or vanilla odds. Probing how the game behaves is a one-off investigation; its findings go in `DEVELOPMENT.md`, not the suite.
- Give a new file under `Contents/` or the dev mod a `TEST_MAP` line in `dev/harness.conf` naming the tests that reach its code; without one, `--changed` runs every test.
- Comments say why, without repeating values from the code: a copied value goes stale when the code changes and nothing fails.
- When a test or check contradicts what you were asked to do, or fails on uncommitted work that isn't yours, stop and report it. Don't edit the test, or the other person's work, to make it pass.

## STOP

- Hand edits to generated files; the next run overwrites them. `art/models/make.sh` builds every model, icon and tile from `art/models/items.py` (parts), `art/models/tiles.py` (tile layout), `tools/make_tiles.py` (tile properties) and `art/models/mod_icon.py` (mod list icon); edit those, never the models, textures, tiles, depth maps, `renewable_energy.tiles`, `renewable_energy.pack` or `42/renewable_energy_icon.png`. Edit `art/promo/compose.py` and `dev/RenewableEnergyDevHarness/42/media/lua/client/RenewableEnergyDevPromo.lua`, never the images they produce, `42/poster.png` and `preview.png` among them.
- Hand edits to `workshop.txt`'s description: `dev/workshop-txt.sh` writes it from `README.md`.

## Read when needed

- Before running in-game tests, handing them to subagents, or debugging a failure or a `LEAK`, read `dev/harness/docs/debugging.md`: which run answers which question, and the traps that cost reruns.
- Before changing anything under `dev/harness`, read `dev/harness/AGENTS.md`: other mods share it.
- Before changing scripts, translations, multiplayer sync, loot, tests, art or the promo shots, read `DEVELOPMENT.md` for the Build 42 behavior that fails silently, the command to decompile the game, and the art, promo and loot commands. Before editing `DEVELOPMENT.md`, read its opening on what belongs there.
- Before changing `README.md`, the Workshop page, read `dev/harness/docs/workshop-page.md`.
- Before designing or balancing a feature, read `docs/design.md`: the principles every cost, payoff and repair is weighed against.
