#!/usr/bin/env bash
# Starts the game client with this mod, its dev mod and the harness mod; dev/harness/docs/running.md
# lists the flags and environment variables. Its scenarios, under the main menu's Scenarios:
# Renewable Energy, a test world, and Renewable Energy QA, with toolboxes in hand and everything of
# the mod laid out by system. Its modes, --promo, --art and --loot, are described at MODES in
# harness.conf. Tests are named renewable_energy_*.
. "$(dirname "$0")/harness/bin/run-client.sh"
