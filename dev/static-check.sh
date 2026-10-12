#!/usr/bin/env bash
# Checks the mod against the installed game without launching it: dev/check/GameProbe.java
# compiles every Lua file with the game's own Kahlua compiler, then dev/check/check.py
# cross-checks translations, scripts, textures, tiles, sandbox options, Lua names and stash
# houses (dev/check/README.md lists every check). Needs a JDK's javac (or JAVAC) and python3.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

BUILD="${CACHE:-$TMP_REAL/pz-renewable-energy-check}"
JAR="$PZ/Java/projectzomboid.jar"
API="$BUILD/game-api.txt"
mkdir -p "$BUILD"

if [ "$REPO/dev/check/GameProbe.java" -nt "$BUILD/GameProbe.class" ]; then
    "${JAVAC:-javac}" -nowarn -source 8 -target 8 -d "$BUILD" "$REPO/dev/check/GameProbe.java" 2>&1 \
        | grep -v -e 'bootstrap class path' -e '^1 warning$' >&2 || true
fi
# What Lua can reach changes only with the game, so the probe's API file is rebuilt with the jar.
probe_api=()
if [ "$JAR" -nt "$API" ] || [ "$BUILD/GameProbe.class" -nt "$API" ]; then
    probe_api=(--api "$JAR" "$API")
fi

# One "path<TAB>name" per Lua file; the name, from the mod's folder, is what errors show.
(cd "$MOD_DIR" && find 42 common -name '*.lua' | sort | while read -r file; do
    printf '%s\t%s\n' "$MOD_DIR/$file" "$file"
done) > "$BUILD/lua-files.txt"

status=0
# Kahlua reads stdlib.lua from the working directory.
(cd "$PZ/Java" && "$JAVA" -cp "$BUILD:$JAR" GameProbe ${probe_api[@]+"${probe_api[@]}"} "@$BUILD/lua-files.txt") \
    || status=1
PYTHONDONTWRITEBYTECODE=1 python3 "$REPO/dev/check/check.py" "$PZ/Java" "$API" "$BUILD" \
    "$MOD_DIR/42" "$MOD_DIR/common" || status=1
exit $status
