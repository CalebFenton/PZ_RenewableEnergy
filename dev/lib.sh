# shellcheck shell=bash
# Sourced by the dev scripts. PZ_APP overrides the game's Contents folder, and CACHE the cache dir
# that the calling script defaults to.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PZ="${PZ_APP:-$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents}"
JAVA="$PZ/PlugIns/jre-$(uname -m | sed 's/arm64/aarch64/')/Contents/Home/bin/java"
MOD_DIR="$REPO/Contents/mods/RenewableEnergy"
MOD_ID=cf_renewable_energy

# JVM arguments shared by the client and the dedicated server. Both run from "$PZ/Java", which
# GAME_CLASSPATH is relative to.
JVM_COMMON=(-Djava.awt.headless=true -Djava.library.path=. --enable-native-access=ALL-UNNAMED
    --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED -Dzomboid.steam=0 -Dzomboid.znetlog=1
    -XX:-OmitStackTraceInFastThrow)
GAME_CLASSPATH=.:projectzomboid.jar

# Lua stack traces name the mod as "(MOD:<name in mod.info>)".
MOD_ERROR='\(MOD:Renewable Energy'

# The game reads depth maps by absolute path and refuses paths outside the mod folders and the
# cache dir without resolving symlinks (ZomboidFileSystem.validatePrefix), so a symlinked mod, or a
# cache under macOS's /var (really /private/var), loses its tile depth maps. Hence a real copy, in
# a cache dir under a path with no symlink in it.
TMP_REAL="$(cd "${TMPDIR:-/tmp}" && pwd -P)"

# Compiles a dev Java file into a directory when the source is newer than its class. The game's
# own Java has no compiler, so it needs a JDK's javac (or JAVAC); class files for Java 8 run on
# the game's newer JVM, and any JDK from 8 on can write them.
compile_java() {
    local source=$1 dir=$2
    local class
    class="$dir/$(basename "$source" .java).class"
    if [ "$source" -nt "$class" ]; then
        mkdir -p "$dir"
        "${JAVAC:-javac}" -nowarn -Xlint:-options -source 8 -target 8 -d "$dir" "$source"
    fi
}

install_mod() {
    mkdir -p "$CACHE/mods"
    # rsync copies only what changed; an old symlink in its place has to go first.
    if [ -L "$CACHE/mods/RenewableEnergy" ]; then
        rm "$CACHE/mods/RenewableEnergy"
    fi
    rsync -a --delete "$MOD_DIR/" "$CACHE/mods/RenewableEnergy/"
}

# Only one game process started by these scripts runs at a time, client or server: several copies
# of the scripts may run at once, and parallel games starve each other of memory and fight over the
# display and the shared cache dirs. macOS has no flock, so the lock is a directory, which mkdir
# creates atomically, holding the owner's PID. A lock whose owner has died is taken over: a script
# killed outright never runs its EXIT trap, and the manual client execs into the game.
#
# A game kept open by run-debug-client.sh --test --stay owns the lock itself once its script exits:
# the lock's "session" file holds its PID and cache dir. The next script to want the game takes the
# lock and the game over; with the argument "reuse" it leaves the game running and sets SESSION_PID
# and SESSION_CACHE, and otherwise it stops the game.
GAME_LOCK="${TMPDIR:-/tmp}/pz-renewable-energy-game.lock"

acquire_game_lock() {
    local owner said=
    SESSION_PID= SESSION_CACHE=
    until mkdir "$GAME_LOCK" 2>/dev/null; do
        owner=$(cat "$GAME_LOCK/pid" 2>/dev/null || true)
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            # Moving the lock aside first means two waiters can't both remove it, and the second
            # remove the lock the first then took.
            mv "$GAME_LOCK" "$GAME_LOCK.stale.$$" 2>/dev/null && rm -rf "$GAME_LOCK.stale.$$"
            continue
        fi
        # No pid yet: the owner is between mkdir and writing it, or died there.
        if [ -z "$owner" ] && [ -d "$GAME_LOCK" ] \
            && [ $(( $(date +%s) - $(stat -f %m "$GAME_LOCK" 2>/dev/null || date +%s) )) -gt 30 ]; then
            mv "$GAME_LOCK" "$GAME_LOCK.stale.$$" 2>/dev/null && rm -rf "$GAME_LOCK.stale.$$"
            continue
        fi
        if claim_session; then
            break
        fi
        if [ -z "$said" ]; then
            echo "waiting for the game another dev script started (pid ${owner:-unknown}) to exit"
            said=1
        fi
        sleep 2
    done
    echo $$ > "$GAME_LOCK/pid"
    trap release_game_lock EXIT
    if [ -n "$SESSION_PID" ] && [ "${1:-}" != reuse ]; then
        echo "stopping the game kept open by --stay"
        stop_session
    fi
}

# Takes over the lock of a kept game nobody is using: its session file names it, and the lock's pid
# is the game's own. The claim directory lets only one of several waiters do so.
claim_session() {
    [ -f "$GAME_LOCK/session" ] && mkdir "$GAME_LOCK/claim" 2>/dev/null || return 1
    local pid cache
    { read -r pid && read -r cache; } < "$GAME_LOCK/session" 2>/dev/null || true
    if [ -z "$pid" ] || [ "$(cat "$GAME_LOCK/pid" 2>/dev/null)" != "$pid" ]; then
        rmdir "$GAME_LOCK/claim"
        return 1
    fi
    SESSION_PID=$pid SESSION_CACHE=$cache
    echo $$ > "$GAME_LOCK/pid"
    rm -f "$GAME_LOCK/session"
    rmdir "$GAME_LOCK/claim"
}

release_game_lock() {
    if [ "$(cat "$GAME_LOCK/pid" 2>/dev/null)" = "$$" ]; then
        rm -rf "$GAME_LOCK"
    fi
}

# Stops the game with PID $1 and waits until it has exited, whether or not this script started it.
stop_pid() {
    kill "$1" 2>/dev/null || true
    wait "$1" 2>/dev/null || true
    while kill -0 "$1" 2>/dev/null; do
        sleep 0.5
    done
}

stop_session() {
    stop_pid "$SESSION_PID"
    SESSION_PID=
}

# Background jobs of a script ignore Ctrl-C, so a game started in the background would outlive the
# script. Stops the game with PID $1 when the script exits, and releases the lock only once the
# game has exited.
stop_game_on_exit() {
    GAME_PID=$1
    trap 'stop_pid "$GAME_PID"; release_game_lock' EXIT
}

# For --stay: when the script exits, hands the lock to the game with PID $1 if it still runs.
keep_game_on_exit() {
    GAME_PID=$1
    trap hand_lock_to_game EXIT
}

hand_lock_to_game() {
    if kill -0 "$GAME_PID" 2>/dev/null && [ "$(cat "$GAME_LOCK/pid" 2>/dev/null)" = "$$" ]; then
        printf '%s\n%s\n' "$GAME_PID" "$CACHE" > "$GAME_LOCK/session"
        echo "$GAME_PID" > "$GAME_LOCK/pid"
        echo "the game stays open (pid $GAME_PID); the next --test --stay reruns the tests in it"
    else
        release_game_lock
    fi
}

stop_game() {
    stop_pid "$GAME_PID"
}
