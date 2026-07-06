#!/bin/bash
# Render the Headroom DMG installer background from dmg-background.html into
# dmg-background.png (@1x, 680x440) and dmg-background@2x.png (@2x, 1360x880).
#
# Uses headless Google Chrome so the committed PNGs exactly match the approved
# "Instrument" design (real TX-02 type + vessel app icon). The release script
# (Scripts/release-app.sh) consumes the committed PNGs and never runs a browser.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
HTML="${PWD}/dmg-background.html"

if [[ ! -x "${CHROME}" ]]; then
  echo "Google Chrome not found at: ${CHROME}" >&2
  echo "Set CHROME=/path/to/chrome and rerun." >&2
  exit 69
fi

# Chrome's new headless mode writes --screenshot but does not reliably self-exit,
# so launch it in the background, wait for the PNG to land, then terminate it.
render() {
  local dsf="$1" out="$2" profile pid waited=0
  rm -f "${out}"
  profile="$(mktemp -d)"
  "${CHROME}" \
    --headless=new \
    --hide-scrollbars \
    --disable-gpu \
    --force-color-profile=srgb \
    --user-data-dir="${profile}" \
    --force-device-scale-factor="${dsf}" \
    --window-size=680,440 \
    --screenshot="${out}" \
    "file://${HTML}" >/dev/null 2>&1 &
  pid=$!
  while [[ ! -s "${out}" && ${waited} -lt 200 ]]; do sleep 0.2; waited=$((waited + 1)); done
  sleep 0.6   # let Chrome finish flushing the PNG
  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" 2>/dev/null || true
  pkill -f "user-data-dir=${profile}" >/dev/null 2>&1 || true
  rm -rf "${profile}"
  [[ -s "${out}" ]] || { echo "render failed (no output): ${out}" >&2; return 1; }
}

render 1 "${PWD}/dmg-background.png"
render 2 "${PWD}/dmg-background@2x.png"

echo "→ generated:"
sips -g pixelWidth -g pixelHeight dmg-background.png    | sed 's/^/    dmg-background.png /'
sips -g pixelWidth -g pixelHeight dmg-background@2x.png | sed 's/^/    dmg-background@2x.png /'
