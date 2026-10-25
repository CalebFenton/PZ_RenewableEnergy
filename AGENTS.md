# Renewable Energy

## Commands

- After every change: `dev/static-check.sh`, which compiles every Lua file with the game's compiler and cross-checks scripts, translations, textures and API names in seconds. After a change to `Contents/`, also `dev/validate-server.sh`.
- Each in-game test run pays for a game start, so batch: commit each logical change on its own, then run `dev/run-debug-client.sh --test --changed` once per batch, not after each edit. Before pushing or merging: `dev/run-debug-client.sh --test`. Before a release, also `dev/run-debug-client.sh --test --mp`.
- When agents work in parallel, they don't run the game; whoever merges their work runs the batch.

## Rules

- Check Build 42 APIs against the installed game's Lua, scripts and decompiled Java, not web docs or memory: most published modding docs describe Build 41, whose APIs fail silently in Build 42.
- Test in the game, in the dev mod's `RenewableEnergyTests*.lua`, never with standalone Lua and stubbed game APIs: the stubs encode guesses about the game, which is what the tests must check.
- Test a chance by setting the roll on either side of it (`T.forceRoll`, `Helpers.forceRolls`), never by rolling many times; new chances go through `RenewableEnergy.Chance.hit`. Feed the mod's functions their inputs rather than driving vehicle physics, vanilla loot rolls or vanilla odds; a probe of how the game behaves is a one-off whose findings go in `DEVELOPMENT.md`, not the suite.
- Don't test what a definition plainly says, such as a recipe's inputs or an item's script fields; test the mod's logic, and the game only where its behaviour isn't clear from the definition.
- Comments say why, without repeating values from the code: a copied value goes stale and nothing fails.
- Code another of Caleb's mods could use goes in the library mod cf_commonlib (`../cf_commonlib`), never in a copy here: look there before writing a helper, and change it there when a change here touches what it does.
- When a change alters how a mechanic plays or where something spawns, update `docs/player-guide.md` in the same commit: rarity tiers and rough sizes, exact figures only where players plan around them.
- When a test or check contradicts what you were asked to do, or fails on uncommitted work that isn't yours, stop and report it rather than editing the test or the other person's work.

## STOP

- Hand edits to generated files: the next run overwrites them. Edit the builders `art/models/make.sh`'s header names, never the models, textures, tiles, depth maps, tile definitions, pack or mod icon they write; edit `art/promo/compose.py` and the dev mod's `RenewableEnergyDevPromo*.lua`, never the images they produce.

## Read when needed

- Before running in-game tests, handing them to subagents, or debugging a failure or a `LEAK`, read `dev/harness/docs/debugging.md`: which run answers which question, and the traps that cost reruns.
- Before changing scripts, translations, multiplayer sync, loot, tests, art or the promo shots, read `DEVELOPMENT.md`: the Build 42 behaviour that fails silently, the command to decompile the game, and the art, promo and loot commands.
- Before changing anything under `dev/harness`, read `dev/harness/AGENTS.md`; before changing anything in `../cf_commonlib`, read its `AGENTS.md`. Other mods use both.
- Before changing `README.md`, the Workshop page, read `dev/harness/docs/workshop-page.md`.
- Before designing or balancing a feature, read `docs/design.md`: the principles every cost, payoff and repair is weighed against.
- Before working on Project Viewpoint compatibility, read `docs/viewpoint.md`: how Viewpoint draws and picks objects, and its model-pack format.
