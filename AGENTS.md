# Renewable Energy

## Commands

- After every change: `dev/static-check.sh` (seconds; compiles every Lua file with the game's compiler and cross-checks scripts, translations, textures and API names). After a change to `Contents/`, also `dev/validate-server.sh` (boots a headless dedicated server and fails on any error the mod logs).
- While you iterate, run only the tests your change touches, in a kept game: `dev/run-debug-client.sh --test --changed --stay` picks them from the changed files (`TEST_MAP` in `dev/harness.conf`), `TESTS=<prefix>,...` names them, and `--failed` reruns the last run's failures. A kept game reruns in about a second but reloads only the test and handler files; a change to `Contents/` or the harness relaunches it. Add `--mp` for multiplayer. The runs need a JDK's `javac` on `PATH` (or `JAVAC` set) and take a lock, so a run waits while another one's game is up.
- Before committing: one plain `--test` and one `--test --mp`, the whole suites in fresh worlds. What only the server can do goes through `RenewableEnergyTest.server` and the dev mod's server handlers; `dev/harness/docs/multiplayer.md` explains it.
- README and Workshop art: `PROMO=<group> dev/run-debug-client.sh --promo` reshoots one group of screenshots, such as `PROMO=trailer` or `PROMO=models`, in about half a minute and replaces only that group's captures (a wrong name lists the groups); `art/promo/compose.py` then lays out the images in seconds. Iterate on the one group you are changing, and never rerun every group to check one shot. A layout change needs only `compose.py`.

## Spending game runs

A fresh multiplayer game costs most of a minute before the first test, and the whole suite a few minutes more; the `timing:` lines and `dev/.runs.log` show where each run's time went. A run is the most expensive thing you do, so each one must test something new:

- Before a run, check that your edits applied and `dev/static-check.sh` passes. Rerunning unchanged code tells you nothing, unless you are measuring a flake with `REPEAT=<n>`.
- A failure: read its reason and the log around it (both logs' paths print at the end), add the one diagnostic that decides between your explanations, and rerun only that test.
- Passes alone but fails in the suite: an earlier test leaked. Read the `LEAK` and `DESYNC` lines, which every run prints and which fail the test that leaked; `ORDER=reverse` or `ORDER=shuffle` confirms an order dependence. Never bisect by hand in a `--stay` game: it keeps every earlier run's leftovers.
- Three runs on one failure without narrowing it: stop, write down what each ruled out, and change approach.
- Subagents edit and run `dev/static-check.sh`; one agent runs the game, batching everyone's changes into one run.
- `dev/harness/docs/debugging.md` has the whole protocol and the harness's traps, such as a refused timed action clearing the action queue and a Lua error stopping the game.

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
