#!/usr/bin/env bash
# Starts the game client in debug mode (no Steam) with its own cache dir and only this mod enabled.
#
#   dev/run-debug-client.sh          play by hand: main menu > Scenarios > Renewable Energy
#                                    starts a test world, and Debug menu > Dev > Unit Tests >
#                                    Timed Actions runs the renewable_energy_* tests
#   dev/run-debug-client.sh --test   also loads dev/RenewableEnergyDevHarness, which starts the scenario, runs
#                                    every renewable_energy_* test, saves a screenshot and quits the game. Runs
#                                    unattended: dev/ClickToStart.java presses "Click to start", and
#                                    the display is kept awake. Prints the results and exits 1 if a
#                                    test failed or any Lua error was logged.
#   dev/run-debug-client.sh --promo  the same, but instead of the tests the harness builds a working
#                                    array and captures the art for the README and the Workshop
#                                    page, and art/promo/extract.py crops it into art/promo/captures
#                                    (needs uv, https://docs.astral.sh/uv/); art/promo/compose.py
#                                    then lays out art/promo/images
#   dev/run-debug-client.sh --art    the same, but instead of the tests the harness drops every item
#                                    on the ground and places every tile, and saves close-ups as
#                                    art_*.png in the screenshots folder, to check the models and tiles
#   dev/run-debug-client.sh --loot   the same, but instead of the tests the harness measures how
#                                    often each of the mod's items spawns in each loot list and
#                                    room container it is in, and the script prints one line per
#                                    list (a few minutes)
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-renewable-energy-client), JAVAC the compiler for
# ClickToStart.java (default: javac from PATH; any JDK from 8 on works), and TESTS, a comma-separated
# list of test name prefixes, limits --test to those tests (e.g. TESTS=renewable_energy_loot_).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

CACHE="${CACHE:-$TMP_REAL/pz-renewable-energy-client}"
case "${1:-}" in
    "") MODE= ;;
    --test) MODE=test ;;
    --promo) MODE=promo ;;
    --art) MODE=art ;;
    --loot) MODE=loot ;;
    *) echo "usage: $0 [--test | --promo | --art | --loot]" >&2; exit 2 ;;
esac
TIMEOUT=${TIMEOUT:-1200}

acquire_game_lock
install_mod
# Reuse your game settings (resolution, language, accepted terms of service) so a fresh cache
# dir doesn't stop at first-run screens.
if [ ! -f "$CACHE/options.ini" ] && [ -f "$HOME/Zomboid/options.ini" ]; then
    cp "$HOME/Zomboid/options.ini" "$CACHE/options.ini"
fi
# Without this file the client empties mods/default.txt on start, as it does the first time a cache
# dir runs a new major release (ZomboidFileSystem.resetDefaultModsForNewRelease).
echo "If this file does not exist, default.txt will be reset to empty (no mods active)." > "$CACHE/mods/reset-mods-42_00.txt"
MODS="    mod = $MOD_ID,"
if [ -n "$MODE" ]; then
    ln -sfn "$REPO/dev/RenewableEnergyDevHarness" "$CACHE/mods/RenewableEnergyDevHarness"
    MODS="$MODS
    mod = cf_renewable_energy_devharness,"
    mkdir -p "$CACHE/Lua"
    # Second line: TESTS, comma-separated name prefixes that limit which tests run.
    printf '%s\n%s\n' "$MODE" "${TESTS:-}" > "$CACHE/Lua/RenewableEnergyDevHarness.txt"
else
    rm -f "$CACHE/mods/RenewableEnergyDevHarness"
fi
cat > "$CACHE/mods/default.txt" <<EOF
VERSION = 1,

mods
{
$MODS
}

maps
{
}
EOF
# The harness scenario sets forceLaunch; this debug option lets it start from the main menu.
printf 'Version=1\nDebugScenario.ForceLaunch=%s\n' "$([ -n "$MODE" ] && echo true || echo false)" > "$CACHE/debug-options.ini"

GAME=("$JAVA" "${JVM_COMMON[@]}" -XstartOnFirstThread -Xmx3072m -XX:+UseZGC)
GAME_ARGS=(-debug -nosteam -cachedir="$CACHE")
if [ -z "$MODE" ]; then
    cd "$PZ/Java"
    exec "${GAME[@]}" -cp "$GAME_CLASSPATH" zombie.gameStates.MainScreenState "${GAME_ARGS[@]}"
fi

# The game's own Java has no compiler. Target 8 so that any JDK can build a class it can run.
LAUNCHER="$CACHE/launcher"
if [ "$REPO/dev/ClickToStart.java" -nt "$LAUNCHER/ClickToStart.class" ]; then
    mkdir -p "$LAUNCHER"
    "${JAVAC:-javac}" -source 8 -target 8 -Xlint:-options -d "$LAUNCHER" "$REPO/dev/ClickToStart.java"
fi

# GLFW finds no monitor while the display sleeps, and the game can't open its window. caffeinate -u
# wakes the display, and -d -i keep it and the computer awake until this script exits.
caffeinate -d -i -u -w $$ &
for _ in $(seq 10); do
    system_profiler SPDisplaysDataType | grep -q "Display Asleep: Yes" || break
    sleep 1
done

LOG="$CACHE/console.txt"
# Only this mode's captures go, so an --art run doesn't delete the last --promo captures.
rm -f "$LOG" "$CACHE/Screenshots/${MODE:-none}"_*.png
cd "$PZ/Java"
"${GAME[@]}" -cp "$LAUNCHER:$GAME_CLASSPATH" ClickToStart "${GAME_ARGS[@]}" > "$CACHE/stdout.txt" 2>&1 &
PID=$!
# Background jobs of a script ignore Ctrl-C, so the game would outlive the script. The lock goes
# only once the game has exited.
trap 'kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; release_game_lock' EXIT

case "$MODE" in
    promo) MARK=REPromo ;;
    art) MARK=REArt ;;
    loot) MARK=RELootReport ;;
    *) MARK=RETest ;;
esac
# In debug mode a Lua error stops the game at the error, so it never quits on its own. A stack
# trace through this mod's Lua, or any failure once the harness has started, ends the run at once
# instead of at the timeout.
lua_stopped() {
    [ -f "$LOG" ] || return 1
    # Stack trace frames are indented; a require warning names the mod on a WARN line instead.
    grep -q -E '^[[:space:]]+Lua\(\(MOD:Renewable Energy' "$LOG" && return 0
    sed -n "/> $MARK /,\$p" "$LOG" | grep -q -E '^Lua fail|dumping Lua stack trace'
}
STOPPED=
for _ in $(seq "$TIMEOUT"); do
    kill -0 "$PID" 2>/dev/null || break
    if lua_stopped; then
        STOPPED=1
        sleep 2 # lets the rest of the stack trace reach the log
        break
    fi
    sleep 1
done
if [ -n "$STOPPED" ]; then
    echo "FAIL: a Lua error stopped the game; the stack trace from $LOG:"
    grep -n -A20 'dumping Lua stack trace' "$LOG" | grep -v -E '^[0-9]+-\s+(se\.krka|java\.|zombie\.)' | head -40
    exit 1
fi
if kill -0 "$PID" 2>/dev/null; then
    echo "FAIL: no result after ${TIMEOUT}s; stopping the game"
    exit 1
fi

echo "log: $LOG"
if ! grep -q "$MARK" "$LOG" 2>/dev/null; then
    echo "FAIL: the game stopped before the harness ran; the end of $CACHE/stdout.txt:"
    tail -n 20 "$CACHE/stdout.txt"
    exit 1
fi
grep -o "$MARK.*" "$LOG" | uniq || true
# Anything the mod logs counts, from loading on. A mod mistake can also surface as an error in
# vanilla Lua, such as a crafting window drawing an item the mod defined badly, so every Lua error
# counts once the harness has started; before that, vanilla logs errors of its own.
if grep -n -E "$MOD_ERROR" "$LOG" | grep -v 'Dev Harness' \
    || sed -n "/> $MARK /,\$p" "$LOG" | grep -n -E "^ERROR: Lua|LuaManager.*Exception|-- file: "; then
    echo "FAIL: Lua errors were logged"
    exit 1
fi
if [ "$MODE" = promo ] || [ "$MODE" = art ] || [ "$MODE" = loot ]; then
    if ! grep -q "$MARK DONE" "$LOG"; then
        echo "FAIL: the harness didn't finish"
        exit 1
    fi
    if [ "$MODE" = promo ]; then
        "$REPO/art/promo/extract.py" "$CACHE"
        echo "PASS: captures are in $REPO/art/promo/captures"
    elif [ "$MODE" = art ]; then
        echo "PASS: screenshots are in $CACHE/Screenshots"
    fi
    exit 0
fi
if ! grep -q -E "RETest DONE passed=[1-9][0-9]* failed=0$" "$LOG"; then
    echo "FAIL: not every test passed"
    exit 1
fi
echo "PASS: screenshots are in $CACHE/Screenshots"
