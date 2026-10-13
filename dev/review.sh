#!/usr/bin/env bash
# Builds a playtest and review copy without launching the game: lays out the README images from
# the committed captures (art/promo/compose.py), renders README.md the way GitHub shows it to a
# self-contained HTML page and a PDF, and zips the mod folder the way players install it. All three
# land in REVIEW_DIR (default ~/Nextcloud):
#
#   RenewableEnergy-<modversion>.zip    unzip into ~/Zomboid/mods (or the Windows equivalent)
#   RenewableEnergy-README.html, .pdf
#
# Needs uv, pandoc and Google Chrome (CHROME overrides its path). Takes a few seconds; rerun it after
# every README, layout or mod change. New captures need dev/run-debug-client.sh --promo first.
set -euo pipefail
. "$(dirname "$0")/harness/lib/harness.sh"

REVIEW_DIR="${REVIEW_DIR:-$HOME/Nextcloud}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
VERSION="$(sed -n 's/^modversion=//p' "$MOD_DIR/42/mod.info")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$REPO/art/promo/compose.py"

# The page's images are embedded, so the HTML and the PDF stand alone wherever they are copied.
pandoc "$REPO/README.md" -f gfm -t html5 --standalone --embed-resources \
    --resource-path="$REPO" --css="$REPO/dev/review.css" \
    --metadata pagetitle="Renewable Energy $VERSION" -o "$WORK/RenewableEnergy-README.html"
# A throwaway profile, so the run neither touches nor waits on a Chrome that is already open.
"$CHROME" --headless --disable-gpu --no-pdf-header-footer --user-data-dir="$WORK/chrome" \
    --print-to-pdf="$WORK/page.pdf" "file://$WORK/RenewableEnergy-README.html" 2>/dev/null
# review.css prints onto 200-inch pages; the last one is cut off below the last text or image.
uv run -q --with pymupdf python - "$WORK/page.pdf" "$WORK/RenewableEnergy-README.pdf" <<'EOF'
import sys
import pymupdf
doc = pymupdf.open(sys.argv[1])
page = doc[-1]
bottom = max([b[3] for b in page.get_text("blocks")] + [i["bbox"][3] for i in page.get_image_info()])
page.set_cropbox(pymupdf.Rect(0, 0, page.rect.width, min(page.rect.height, bottom + 36)))
doc.save(sys.argv[2], garbage=3, deflate=True)
EOF
# The folder layout players unzip into their mods folder; Finder's .DS_Store files stay out.
(cd "$MOD_DIR/.." && zip -qrX "$WORK/RenewableEnergy-$VERSION.zip" "$(basename "$MOD_DIR")" -x '*.DS_Store')

mkdir -p "$REVIEW_DIR"
for file in "RenewableEnergy-$VERSION.zip" RenewableEnergy-README.html RenewableEnergy-README.pdf; do
    mv "$WORK/$file" "$REVIEW_DIR/$file"
    echo "wrote $REVIEW_DIR/$file"
done
