#!/usr/bin/env bash
# Starts the game client in debug mode (no Steam) with its own cache dir and only this mod enabled.
#
#   dev/run-debug-client.sh          play by hand: main menu > Scenarios > Renewable Energy
#                                    starts a test world, and Debug menu > Dev > Unit Tests >
#                                    Timed Actions runs the renewable_energy_* tests
#   dev/run-debug-client.sh --test   also loads dev/RenewableEnergyDevHarness, which starts the scenario, runs
#                                    every renewable_energy_* test and quits the game. Runs
#                                    unattended: dev/ClickToStart.java presses "Click to start", and
#                                    the display is kept awake. Prints the results and exits 1 if a
#                                    test failed or any Lua error was logged.
#   dev/run-debug-client.sh --test --stay
#                                    the same, but the game stays open after the run, and the next
#                                    --test --stay reruns the tests in it, after reloading the test
#                                    files, instead of starting the game again. A change outside the
#                                    test files (Debug/RenewableEnergyTest*.lua) restarts the game.
#                                    While it waits it shows and logs "RETest IDLE"; it quits after
#                                    10 minutes without a run, or when another run needs the game.
#   dev/run-debug-client.sh --promo  the same as --test, but instead of the tests the harness builds a
#                                    working array and captures the art for the README and the
#                                    Workshop page, and art/promo/extract.py crops it into
#                                    art/promo/captures (needs uv, https://docs.astral.sh/uv/);
#                                    art/promo/compose.py then lays out art/promo/images
#   dev/run-debug-client.sh --art    the same, but instead of the tests the harness drops every item
#                                    on the ground and places every tile, and saves close-ups as
#                                    art_*.png in the screenshots folder, to check the models and tiles
#   dev/run-debug-client.sh --loot   the same, but instead of the tests the harness measures how
#                                    often each of the mod's items spawns in each loot list and
#                                    room container it is in, and the script prints one line per
#                                    list (a few minutes)
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-renewable-energy-client), JAVAC the compiler for
# ClickToStart.java (default: javac from PATH; any JDK from 8 on works), TIMEOUT the seconds a
# harness run may take (default 1200), and TESTS, a comma-separated list of test name prefixes,
# limits --test to those tests (e.g. TESTS=renewable_energy_loot_).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

CACHE="${CACHE:-$TMP_REAL/pz-renewable-energy-client}"
usage() {
    echo "usage: $0 [--test [--stay] | --promo | --art | --loot]" >&2
    exit 2
}
MODE= STAY=
for arg in "$@"; do
    case "$arg" in
        --test) MODE=test ;;
        --promo) MODE=promo ;;
        --art) MODE=art ;;
        --loot) MODE=loot ;;
        --stay) STAY=1 ;;
        *) usage ;;
    esac
done
if [ -n "$STAY" ] && [ "$MODE" != test ]; then
    usage
fi
TIMEOUT=${TIMEOUT:-1200}
LOG="$CACHE/console.txt"
# The harness reads its mode from the first file and, with --stay, rerun requests from the second
# (RenewableEnergyDevHarness.lua).
HARNESS_FILE="$CACHE/Lua/RenewableEnergyDevHarness.txt"
REQUEST_FILE="$CACHE/Lua/RenewableEnergyDevRerun.txt"
# The files a kept game loads again for a rerun, relative to the mod folder; TestLib sorts first.
TEST_FILES='42/media/lua/client/RenewableEnergy/Debug/RenewableEnergyTest*.lua'

# Why a kept game can't rerun the tests: it belongs to another cache dir, or something it loaded
# only at start changed since. Prints nothing if it can.
session_stale() {
    if [ "$SESSION_CACHE" != "$CACHE" ]; then
        echo "it runs with the cache dir $SESSION_CACHE"
        return
    fi
    local changed
    changed=$(find "$REPO/dev/RenewableEnergyDevHarness" -newer "$HARNESS_FILE" -type f | head -1)
    if [ -n "$changed" ]; then
        echo "${changed#"$REPO/"} changed"
        return
    fi
    # "Files <ours> and <copy> differ" or "Only in <folder>: <name>", for every changed file.
    changed=$(diff -rq "$MOD_DIR" "$CACHE/mods/RenewableEnergy" \
        | grep -v -E '/Debug/RenewableEnergyTest[^/ ]*\.lua and |/Debug: RenewableEnergyTest[^/ ]*\.lua$' \
        | head -1 || true)
    if [ -n "$changed" ]; then
        echo "a file outside the tests changed: $changed"
    fi
}

acquire_game_lock reuse
if [ -n "$SESSION_PID" ]; then
    reason=
    if [ -z "$STAY" ]; then
        reason="this run doesn't use --stay"
    else
        reason=$(session_stale)
    fi
    if [ -n "$reason" ]; then
        echo "stopping the game kept open by --stay: $reason"
        stop_session
    fi
fi

# Sends a kept game the tests to run and the files to load again. The id names the run in console.txt.
request_rerun() {
    RUN_ID="$$-$(date +%s)"
    {
        echo "$RUN_ID"
        echo "${TESTS:-}"
        # TestLib first: the test files register their tests through it.
        for file in "$CACHE/mods/RenewableEnergy/"$TEST_FILES; do
            echo "$file"
        done
    } > "$REQUEST_FILE.tmp"
    mv "$REQUEST_FILE.tmp" "$REQUEST_FILE" # whole, so the game never reads half a request
}

# Reuse your game settings (resolution, language, accepted terms of service) so a fresh cache
# dir doesn't stop at first-run screens.
prepare_cache() {
    if [ ! -f "$CACHE/options.ini" ] && [ -f "$HOME/Zomboid/options.ini" ]; then
        cp "$HOME/Zomboid/options.ini" "$CACHE/options.ini"
    fi
    # Harness runs play no sound, so they don't blare while you work. Only the volumes are zeroed:
    # the sound engine still runs, so code that plays sounds runs the same. A plain run keeps your
    # volumes.
    if [ -n "$MODE" ] && [ -f "$CACHE/options.ini" ]; then
        for key in soundVolume musicVolume ambientVolume vehicleEngineVolume jumpScareVolume voiceVolumePlayers; do
            sed -i '' "s/^$key=.*/$key=0/" "$CACHE/options.ini"
        done
    fi
    # Without this file the client empties mods/default.txt on start, as it does the first time a
    # cache dir runs a new major release (ZomboidFileSystem.resetDefaultModsForNewRelease).
    echo "If this file does not exist, default.txt will be reset to empty (no mods active)." > "$CACHE/mods/reset-mods-42_00.txt"
    local mods="    mod = $MOD_ID,"
    if [ -n "$MODE" ]; then
        ln -sfn "$REPO/dev/RenewableEnergyDevHarness" "$CACHE/mods/RenewableEnergyDevHarness"
        mods="$mods
    mod = cf_renewable_energy_devharness,"
        mkdir -p "$CACHE/Lua"
        rm -f "$REQUEST_FILE"
        # Then TESTS, comma-separated name prefixes that limit which tests run, and "stay" for --stay.
        printf '%s\n%s\n%s\n' "$MODE" "${TESTS:-}" "$([ -n "$STAY" ] && echo stay || true)" > "$HARNESS_FILE"
    else
        rm -f "$CACHE/mods/RenewableEnergyDevHarness"
    fi
    cat > "$CACHE/mods/default.txt" <<EOF
VERSION = 1,

mods
{
$mods
}

maps
{
}
EOF
    # The harness scenario sets forceLaunch; this debug option lets it start from the main menu.
    printf 'Version=1\nDebugScenario.ForceLaunch=%s\n' "$([ -n "$MODE" ] && echo true || echo false)" > "$CACHE/debug-options.ini"
}

install_mod
# This run's part of console.txt: all of it after a launch; in a kept game, from this run's request
# on, copied to RUN_LOG on every poll. The checks read files rather than pipes into grep -q, whose
# early exit would make pipefail report a match as a miss.
RUN_ID=
RUN_LOG=$LOG
if [ -n "$SESSION_PID" ]; then
    PID=$SESSION_PID
    request_rerun
    RUN_LOG="$CACHE/console-rerun.txt"
    echo "rerunning the tests in the game kept open by --stay (pid $PID)"
else
    prepare_cache
    GAME=("$JAVA" "${JVM_COMMON[@]}" -XstartOnFirstThread -Xmx3072m -XX:+UseZGC)
    GAME_ARGS=(-debug -nosteam -cachedir="$CACHE")
    cd "$PZ/Java"
    if [ -z "$MODE" ]; then
        exec "${GAME[@]}" -cp "$GAME_CLASSPATH" zombie.gameStates.MainScreenState "${GAME_ARGS[@]}"
    fi

    LAUNCHER="$CACHE/launcher"
    compile_java "$REPO/dev/ClickToStart.java" "$LAUNCHER"

    # GLFW finds no monitor while the display sleeps, and the game can't open its window.
    # caffeinate -u wakes the display, and -d -i keep it and the computer awake until this script
    # exits.
    caffeinate -d -i -u -w $$ &
    for _ in $(seq 10); do
        system_profiler SPDisplaysDataType | grep -q "Display Asleep: Yes" || break
        sleep 1
    done

    # Only this mode's captures go, so an --art run doesn't delete the last --promo captures.
    rm -f "$LOG" "$CACHE/Screenshots/${MODE:-none}"_*.png
    # Neither the game nor its caffeinate holds this script's stdin or output, so a caller reading
    # that output sees it end when the script exits, even if the game stays open with --stay.
    "${GAME[@]}" -cp "$LAUNCHER:$GAME_CLASSPATH" ClickToStart "${GAME_ARGS[@]}" < /dev/null > "$CACHE/stdout.txt" 2>&1 &
    PID=$!
    if [ -n "$STAY" ]; then
        # Keeps the display awake for the kept game, after this script exits.
        caffeinate -d -i -w "$PID" < /dev/null > /dev/null 2>&1 &
    fi
fi
if [ -n "$STAY" ]; then
    keep_game_on_exit "$PID"
else
    stop_game_on_exit "$PID"
fi

case "$MODE" in
    promo) MARK=REPromo ;;
    art) MARK=REArt ;;
    loot) MARK=RELootReport ;;
    *) MARK=RETest ;;
esac
update_run_log() {
    if [ -n "$RUN_ID" ]; then
        sed -n "/> RETest RUN $RUN_ID\$/,\$p" "$LOG" > "$RUN_LOG" 2>/dev/null || true
    fi
}
# Whether this run's log has a line matching the extended regex $1, at or after the harness's
# first $MARK line if $2 is "harness".
logged() {
    [ -f "$RUN_LOG" ] || return 1
    RE=$1 FROM=$([ "${2:-}" = harness ] && echo "> $MARK " || true) awk '
        BEGIN { started = ENVIRON["FROM"] == "" }
        !started && index($0, ENVIRON["FROM"]) { started = 1 }
        started && $0 ~ ENVIRON["RE"] { found = 1; exit }
        END { exit !found }' "$RUN_LOG"
}
# In debug mode a Lua error stops the game at the error, so it never quits on its own. A stack
# trace through this mod's Lua, or any failure once the harness has started, ends the run at once
# instead of at the timeout. Stack trace frames are indented; a require warning names the mod on a
# WARN line instead.
lua_stopped() {
    logged "^[[:space:]]+Lua\\($MOD_ERROR" \
        || logged '^Lua fail|dumping Lua stack trace|Error found in LUA file' harness
}
# A game without --stay quits when it is done; a kept one prints the DONE line and waits.
STOPPED= DONE=
SECONDS=0
while [ "$SECONDS" -lt "$TIMEOUT" ]; do
    kill -0 "$PID" 2>/dev/null || break
    update_run_log
    if lua_stopped; then
        STOPPED=1
        sleep 2 # lets the rest of the stack trace reach the log
        update_run_log
        break
    fi
    if [ -n "$STAY" ] && logged "> RETest DONE "; then
        DONE=1
        break
    fi
    sleep 0.5
done
if [ -n "$STOPPED" ]; then
    echo "FAIL: a Lua error stopped the game; the stack trace from $LOG:"
    grep -n -A20 'dumping Lua stack trace' "$RUN_LOG" | grep -v -E '^[0-9]+-\s+(se\.krka|java\.|zombie\.)' | head -40
    stop_game
    exit 1
fi
if [ -z "$DONE" ] && kill -0 "$PID" 2>/dev/null; then
    echo "FAIL: no result after ${TIMEOUT}s; stopping the game"
    stop_game
    exit 1
fi

echo "log: $LOG"
if ! logged "$MARK"; then
    echo "FAIL: the game stopped before the harness ran; the end of $CACHE/stdout.txt:"
    tail -n 20 "$CACHE/stdout.txt"
    exit 1
fi
grep -o "$MARK.*" "$RUN_LOG" | grep -v "^RETest RUN " | uniq || true
# Anything the mod logs counts, from loading on. A mod mistake can also surface as an error in
# vanilla Lua, such as a crafting window drawing an item the mod defined badly, so every Lua error
# counts once the harness has started; before that, vanilla logs errors of its own.
if grep -n -E "$MOD_ERROR" "$RUN_LOG" | grep -v 'Dev Harness' \
    || sed -n "/> $MARK /,\$p" "$RUN_LOG" | grep -n -E "^ERROR: Lua|LuaManager.*Exception|-- file: "; then
    echo "FAIL: Lua errors were logged"
    exit 1
fi
if [ "$MODE" = promo ] || [ "$MODE" = art ] || [ "$MODE" = loot ]; then
    if ! logged "$MARK DONE"; then
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
if ! logged "RETest DONE passed=[1-9][0-9]* failed=0$"; then
    echo "FAIL: not every test passed"
    exit 1
fi
echo "PASS"
