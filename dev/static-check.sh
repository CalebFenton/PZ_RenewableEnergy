#!/usr/bin/env bash
# Checks the mod against the installed game without launching it: dev/check/GameProbe.java
# compiles every Lua file of the mod, its dev mod and the shared harness mod with the game's own
# Kahlua compiler, then dev/check/check.py cross-checks the mod's translations, scripts, textures,
# tiles, sandbox options, Lua names and stash houses (dev/check/README.md lists every check), and
# the Lua names of the tests and the rest of the dev mod. Needs a JDK's javac (or JAVAC) and
# python3.
set -euo pipefail
. "$(dirname "$0")/harness/lib/harness.sh"

BUILD="${CACHE:-$TMP_REAL/$CACHE_NAME-check}"
JAR="$PZ/Java/projectzomboid.jar"
API="$BUILD/game-api.txt"
mkdir -p "$BUILD"

compile_java "$REPO/dev/check/GameProbe.java" "$BUILD"
# What Lua can reach changes only with the game, so the probe's API file is rebuilt with the jar.
probe_api=()
if [ "$JAR" -nt "$API" ] || [ "$BUILD/GameProbe.class" -nt "$API" ]; then
    probe_api=(--api "$JAR" "$API")
fi

# One "path<TAB>name" per Lua file; the name, from the mod's folder or the repository, is what
# errors show.
list_lua() {
    (cd "$1" && find "${@:2}" -name '*.lua' | sort | while read -r file; do
        printf '%s\t%s\n' "$1/$file" "$file"
    done)
}
{ list_lua "$MOD_DIR" 42 common; list_lua "$REPO" "${DEV_MOD_DIR#"$REPO/"}" "${HARNESS_MOD_DIR#"$REPO/"}"; } > "$BUILD/lua-files.txt"

status=0
# Kahlua reads stdlib.lua from the working directory.
(cd "$PZ/Java" && "$JAVA" -cp "$BUILD:$JAR" GameProbe ${probe_api[@]+"${probe_api[@]}"} "@$BUILD/lua-files.txt") \
    || status=1
PYTHONDONTWRITEBYTECODE=1 python3 "$REPO/dev/check/check.py" "$PZ/Java" "$API" "$BUILD" \
    "$MOD_DIR/42" "$MOD_DIR/common" "$DEV_MOD_DIR/42" "$HARNESS_MOD_DIR/42" || status=1
exit $status
