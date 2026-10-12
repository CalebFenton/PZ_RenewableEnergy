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

install_mod() {
    mkdir -p "$CACHE/mods"
    rm -rf "$CACHE/mods/RenewableEnergy" # no trailing slash: removes an old symlink, not its target
    rsync -a --delete "$MOD_DIR/" "$CACHE/mods/RenewableEnergy/"
}

# Only one game process started by these scripts runs at a time, client or server: several copies
# of the scripts may run at once, and parallel games starve each other of memory and fight over the
# display and the shared cache dirs. macOS has no flock, so the lock is a directory, which mkdir
# creates atomically, holding the owner's PID. A lock whose owner has died is taken over: a script
# killed outright never runs its EXIT trap, and the manual client execs into the game.
GAME_LOCK="${TMPDIR:-/tmp}/pz-renewable-energy-game.lock"

acquire_game_lock() {
    local owner said=
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
        if [ -z "$said" ]; then
            echo "waiting for the game another dev script started (pid ${owner:-unknown}) to exit"
            said=1
        fi
        sleep 2
    done
    echo $$ > "$GAME_LOCK/pid"
    trap release_game_lock EXIT
}

release_game_lock() {
    if [ "$(cat "$GAME_LOCK/pid" 2>/dev/null)" = "$$" ]; then
        rm -rf "$GAME_LOCK"
    fi
}
