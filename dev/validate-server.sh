#!/usr/bin/env bash
# Boots a throwaway dedicated server (no Steam, isolated cache dir) with only this mod enabled,
# waits for it to finish loading, stops it, and fails if the mod logged a problem. The server
# loads the tiles, scripts, sandbox options, shared and server Lua, and the loot tables.
#
# CACHE overrides the cache dir (default: $TMPDIR/pz-renewable-energy-server).
set -euo pipefail
. "$(dirname "$0")/lib.sh"

CACHE="${CACHE:-$TMP_REAL/pz-renewable-energy-server}"
NAME=renewable_energy
TIMEOUT=${TIMEOUT:-900}

acquire_game_lock
install_mod
mkdir -p "$CACHE/Server"
cat > "$CACHE/Server/$NAME.ini" <<EOF
Mods=$MOD_ID
Map=Muldraugh, KY
UPnP=false
Public=false
EOF
# The in-game tests run the default options, so the server runs the ones that switch on more of
# the mod: stash houses with map items and houses stocked from the start, the expanded recipes,
# the other drain method and charge frequency, and the most battery banks. A new world each time,
# so the stash houses known from the start are prepared again.
cat > "$CACHE/Server/${NAME}_SandboxVars.lua" <<EOF
SandboxVars = {
    RenewableEnergy = {
        StashMode = 3,
        enableExpandedRecipes = true,
        DrainCalc = 1,
        ChargeFreq = 2,
        BatteryBankSpawn = 4,
    },
}
EOF
rm -rf "$CACHE/Saves/Multiplayer/$NAME"

LOG="$CACHE/server-console.txt"
rm -f "$LOG"
FIFO="$CACHE/stdin"
rm -f "$FIFO"
mkfifo "$FIFO"

cd "$PZ/Java"
"$JAVA" "${JVM_COMMON[@]}" -cp "$GAME_CLASSPATH" -Ddebug -Xmx4g zombie.network.GameServer \
    -cachedir="$CACHE" -servername "$NAME" -adminpassword admin -nosteam -debuglog=Mod,Lua \
    < "$FIFO" > "$CACHE/stdout.txt" 2>&1 &
SERVER=$!
# Background jobs of a script ignore Ctrl-C, so the server would outlive the script. The lock goes
# only once the server has exited.
trap 'kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; rm -f "$FIFO"; release_game_lock' EXIT
exec 3>"$FIFO"

started=0
for _ in $(seq "$TIMEOUT"); do
    if grep -q "SERVER STARTED" "$LOG" 2>/dev/null; then started=1; break; fi
    if ! kill -0 "$SERVER" 2>/dev/null; then break; fi
    sleep 1
done
if kill -0 "$SERVER" 2>/dev/null; then
    echo quit >&3
    for _ in $(seq 120); do kill -0 "$SERVER" 2>/dev/null || break; sleep 1; done
fi
exec 3>&-

echo "log: $LOG"
if [ "$started" != 1 ]; then
    echo "FAIL: server did not start"
    exit 1
fi
# Lua errors carry the mod name in their stack trace, script and tile warnings name the item,
# recipe or tileset, and Distributions.lua prints "RenewableEnergy: missing" for unknown loot
# lists. The RenewableEnergy_* battery fields are unknown item params on purpose: the game copies
# them into modData.
if grep -n -E "$MOD_ERROR|RenewableEnergy: missing|^(WARN|ERROR).*(RenewableEnergy[._ ]|renewable_energy)" "$LOG" \
    | grep -v 'adding unknown item param "RenewableEnergy_'; then
    echo "FAIL: the mod logged problems"
    exit 1
fi
echo "PASS: server started and the mod logged no problems"
