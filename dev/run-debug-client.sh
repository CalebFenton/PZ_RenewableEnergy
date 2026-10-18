#!/usr/bin/env bash
# Starts the game client in debug mode (no Steam) with its own cache dir, this mod, its dev mod
# dev/RenewableEnergyDevHarness and the shared harness mod (dev/harness, see its README.md).
#
#   dev/run-debug-client.sh          play by hand: on the main menu, hover over the SCENARIOS
#                                    header in the middle (-debug shows it) and pick Renewable
#                                    Energy for a test world, or Renewable Energy QA for one with
#                                    toolboxes in hand and everything of the mod laid out by
#                                    system; Debug menu > Dev > Unit Tests > Timed Actions runs
#                                    the renewable_energy_* tests
#   dev/run-debug-client.sh --test   starts the scenario, runs every renewable_energy_* test and
#                                    quits the game. Runs unattended: ClickToStart presses "Click
#                                    to start", and the display is kept awake. Prints the results
#                                    and exits 1 if a test failed or any Lua error was logged.
#   dev/run-debug-client.sh --test --stay
#                                    the same, but the game stays open after the run, and the next
#                                    --test --stay reruns the tests in it, after reloading the test
#                                    files, instead of starting the game again. A change outside the
#                                    test files (Debug/RenewableEnergyTest*.lua in the dev mod)
#                                    restarts the game. While it waits it shows and logs "RETest
#                                    IDLE"; it quits after a long idle spell, or when another run
#                                    needs the game.
#   dev/run-debug-client.sh --test --mp [--stay]
#                                    the same tests in multiplayer: a dedicated server and a client
#                                    that joins it as the admin (dev/harness/docs/multiplayer.md);
#                                    with --stay both stay open, and the next
#                                    --test --mp --stay reruns the tests in about a second
#   dev/run-debug-client.sh --promo  the same as --test, but instead of the tests the harness builds a
#                                    working array and captures the art for the README and the
#                                    Workshop page, and art/promo/extract.py crops it into
#                                    art/promo/captures (needs uv, https://docs.astral.sh/uv/);
#                                    art/promo/compose.py then lays out art/promo/images.
#                                    PROMO=<group>,... shoots only those groups and replaces only
#                                    their captures (e.g. PROMO=trailer); a bad name lists the
#                                    groups. There is no --promo --stay: a rerun in the same world
#                                    would shoot what the last run built.
#   dev/run-debug-client.sh --art    the same, but instead of the tests the harness drops every item
#                                    on the ground and places every tile, and saves close-ups as
#                                    art_*.png in the screenshots folder, to check the models and tiles
#   dev/run-debug-client.sh --loot   the same, but instead of the tests the harness measures how
#                                    often each of the mod's items spawns in each loot list and
#                                    room container it is in, and the script prints one line per
#                                    list, then the modules and watts a thorough player finds per
#                                    town and per solar site, and the arrow boards per map (a few
#                                    minutes)
#
# CACHE overrides the cache dir, JAVAC the compiler for ClickToStart.java (default: javac from
# PATH), TIMEOUT the seconds a harness run may take, TESTS, a comma-separated list of test name
# prefixes, limits --test to those tests (e.g. TESTS=renewable_energy_loot_), and PROMO, a
# comma-separated list of groups, limits --promo to those groups.
. "$(dirname "$0")/harness/bin/run-client.sh"
