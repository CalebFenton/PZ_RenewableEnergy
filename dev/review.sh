#!/usr/bin/env bash
# Builds a playtest and review copy without launching the game: lays out the README images from
# the committed captures (art/promo/compose.py), renders README.md the way GitHub shows it to a
# self-contained HTML page and a PDF, and zips the mod folder the way players install it, with the
# libraries it requires (the conf's LIBRARY_MODS) beside it, each library on its own too, and the
# dev mods (this mod's and the shared test harness) the same way. All of it lands in REVIEW_DIR
# (default ~/Nextcloud):
#
#   RenewableEnergy-<modversion>.zip    unzip into ~/Zomboid/mods (or the Windows equivalent)
#   <library>-<modversion>.zip          each library alone, as the Workshop publishes it
#   RenewableEnergyDevMods.zip          the same, for the debug scenario and the tests
#   RenewableEnergy-README.html, .pdf
#   RenewableEnergy-player-guide.html
#   RenewableEnergy-art/index.html      with --art: every model, tile and icon, named, read back
#                                       from the files the game loads (art/models/preview.py)
#
# Needs uv, pandoc and Google Chrome (CHROME overrides its path), and for --art Blender (BLENDER
# overrides its path). Takes a few seconds, --art about a minute more; rerun it after every README,
# layout, mod or art change. New captures need dev/run-debug-client.sh --promo first.
set -euo pipefail
. "$(dirname "$0")/harness/lib/harness.sh"

REVIEW_DIR="${REVIEW_DIR:-$HOME/Nextcloud}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
ART=false
[ "${1:-}" = --art ] && ART=true
VERSION="$(sed -n 's/^modversion=//p' "$MOD_DIR/42/mod.info")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$REPO/art/promo/compose.py"

# The page's images are embedded, so the HTML and the PDF stand alone wherever they are copied.
pandoc "$REPO/README.md" -f gfm -t html5 --standalone --embed-resources \
    --resource-path="$REPO" --css="$REPO/dev/review.css" \
    --metadata pagetitle="Renewable Energy $VERSION" -o "$WORK/RenewableEnergy-README.html"
pandoc "$REPO/docs/player-guide.md" -f gfm -t html5 --standalone --embed-resources \
    --resource-path="$REPO/docs" --css="$REPO/dev/review.css" \
    --metadata pagetitle="Renewable Energy $VERSION: player's guide" -o "$WORK/RenewableEnergy-player-guide.html"
# A throwaway profile, so the run neither touches nor waits on a Chrome that is already open.
"$CHROME" --headless --disable-gpu --no-pdf-header-footer --user-data-dir="$WORK/chrome" \
    --print-to-pdf="$WORK/page.pdf" "file://$WORK/RenewableEnergy-README.html" 2>/dev/null
# review.css prints onto one tall page; crop it below the last text or image.
uv run -q --with pymupdf python - "$WORK/page.pdf" "$WORK/RenewableEnergy-README.pdf" <<'EOF'
import sys
import pymupdf
doc = pymupdf.open(sys.argv[1])
page = doc[-1]
bottom = max([b[3] for b in page.get_text("blocks")] + [i["bbox"][3] for i in page.get_image_info()])
page.set_cropbox(pymupdf.Rect(0, 0, page.rect.width, min(page.rect.height, bottom + 36)))
doc.save(sys.argv[2], garbage=3, deflate=True)
EOF
# The folder layout players unzip into their mods folder, each library beside the mod, as a player
# subscribed to both has them; Finder's .DS_Store files stay out. The shared harness goes in under
# the folder name the game runs it from (HARNESS_MOD_FOLDER).
mkdir "$WORK/mods"
ln -s "$MOD_DIR" "$WORK/mods/$MOD_FOLDER"
PLAYTEST=("$MOD_FOLDER/") LIBRARY_ZIPS=()
for library in ${LIBRARY_DIRS[@]+"${LIBRARY_DIRS[@]}"}; do
    folder="$(basename "$library")"
    library_zip="$folder-$(mod_info "$library" modversion).zip"
    ln -s "$library" "$WORK/mods/$folder"
    (cd "$WORK/mods" && zip -qrX "$WORK/$library_zip" "$folder/" -x '*.DS_Store')
    PLAYTEST+=("$folder/") LIBRARY_ZIPS+=("$library_zip")
done
(cd "$WORK/mods" && zip -qrX "$WORK/RenewableEnergy-$VERSION.zip" "${PLAYTEST[@]}" -x '*.DS_Store')
mkdir "$WORK/dev"
ln -s "$DEV_MOD_DIR" "$WORK/dev/$DEV_MOD_FOLDER"
ln -s "$HARNESS_MOD_DIR" "$WORK/dev/$HARNESS_MOD_FOLDER"
(cd "$WORK/dev" && zip -qrX "$WORK/RenewableEnergyDevMods.zip" "$HARNESS_MOD_FOLDER/" "$DEV_MOD_FOLDER/" -x '*.DS_Store')

mkdir -p "$REVIEW_DIR"
for file in "RenewableEnergy-$VERSION.zip" ${LIBRARY_ZIPS[@]+"${LIBRARY_ZIPS[@]}"} RenewableEnergyDevMods.zip \
    RenewableEnergy-README.html RenewableEnergy-README.pdf RenewableEnergy-player-guide.html; do
    mv "$WORK/$file" "$REVIEW_DIR/$file"
    echo "wrote $REVIEW_DIR/$file"
done
if $ART; then
    PREVIEWS="$REVIEW_DIR/RenewableEnergy-art" PYTHONHASHSEED=0 \
        "$BLENDER" -b --factory-startup --python-use-system-env -P "$REPO/art/models/preview.py" >/dev/null
    echo "wrote $REVIEW_DIR/RenewableEnergy-art/index.html"
fi
