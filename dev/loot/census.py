#!/usr/bin/env python3
"""Writes the dev mod's town census, which the --loot report reads, from the game's map with the
harness's lib/census.py: `dev/loot/census.py [PZ media folder]`."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.execv(sys.executable, [sys.executable, os.path.join(HERE, "..", "harness", "lib", "census.py"), "--by", "dev/loot/census.py",
                          "--out", os.path.join(HERE, "..", "RenewableEnergyDevHarness", "42", "media", "lua", "client",
                                                "RenewableEnergyDevTownCensus.lua"), *sys.argv[1:]])
