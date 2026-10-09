#!/usr/bin/env bash
#
# export-appstore-print.sh — renders the "Print" App Store set from design/appstore/print/compose.html.
#
#   Scripts/export-appstore-print.sh [--out DIR]      (default: dist/appstore/print, gitignored)
#
# Six iPhone 6.9″ frames (1320×2868) and six iPad 13″ frames (2064×2752), rendered in headless
# Chromium with `dev-browser --headless --browser agent-qa`, then converted to sRGB, stripped of
# alpha and verified with `sips -g` exactly as Scripts/capture-appstore-shots.sh does. The frames
# use the captures committed in design/appstore/print/assets/captures; see that folder's README
# for how to refresh them.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/dist/appstore/print"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "✗ Unknown argument: $1" >&2; exit 2 ;;
  esac
done
for tool in dev-browser sips ffmpeg; do
  command -v "$tool" >/dev/null 2>&1 || { echo "✗ $tool is required." >&2; exit 1; }
done

COMPOSE="$ROOT/design/appstore/print/compose.html"
SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
TAG="print-$$"
NAMES=(how-much-is-left every-account lock-screen widget-style pull-to-check-now know-your-limits)
mkdir -p "$OUT/iphone69" "$OUT/ipad13"

JS="$(mktemp -t appstore-print).js"
trap 'rm -f "$JS"' EXIT
cat > "$JS" <<EOF
const page = await browser.getPage("headroom-appstore-print");
for (const [device, w, h] of [["iphone", 1320, 2868], ["ipad", 2064, 2752]]) {
  await page.setViewportSize({ width: w, height: h });
  for (let n = 1; n <= 6; n++) {
    await page.goto("file://$COMPOSE?device=" + device + "&frame=" + n);
    await page.waitForFunction(() => document.body.dataset.ready === "1");
    await new Promise(r => setTimeout(r, 600));
    const broken = await page.evaluate(() => [...document.images].filter(i => !i.complete || i.naturalWidth === 0).length);
    if (broken) throw new Error(device + " frame " + n + ": " + broken + " image(s) failed to load");
    await saveScreenshot(await page.screenshot({ clip: { x: 0, y: 0, width: w, height: h } }), "$TAG-" + device + "-" + n + ".png");
  }
}
EOF
echo "▸ Rendering 12 frames in headless Chromium…"
dev-browser --headless --browser agent-qa --timeout 300 run "$JS" >/dev/null

FAILED=()
for device in iphone ipad; do
  if [ "$device" = iphone ]; then dir=iphone69; expected="1320 2868"; else dir=ipad13; expected="2064 2752"; fi
  for n in 1 2 3 4 5 6; do
    rendered="$HOME/.dev-browser/tmp/$TAG-$device-$n.png"
    out="$OUT/$dir/$dir-0$n-${NAMES[$((n - 1))]}.png"
    sips --matchTo "$SRGB_PROFILE" "$rendered" --out "$out.tmp.png" >/dev/null
    ffmpeg -nostdin -loglevel error -i "$out.tmp.png" -vf format=rgb24 -y "$out"
    sips --embedProfile "$SRGB_PROFILE" "$out" >/dev/null
    rm -f "$out.tmp.png" "$rendered"
    report="$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g profile "$out")"
    size="$(awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w, h}' <<< "$report")"
    alpha="$(awk '/hasAlpha/ {print $2}' <<< "$report")"
    profile="$(sed -n 's/^ *profile: //p' <<< "$report")"
    if [ "$size" != "$expected" ] || [ "$alpha" != "no" ] || [[ "$profile" != sRGB* ]]; then
      FAILED+=("$(basename "$out") ($size, hasAlpha $alpha, $profile)")
    else
      echo "  ✓ ${out#$ROOT/} ($size, hasAlpha no, $profile)"
    fi
  done
done
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '✗ %s\n' "${FAILED[@]}" >&2
  exit 1
fi
