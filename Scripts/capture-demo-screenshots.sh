#!/usr/bin/env bash
#
# capture-demo-screenshots.sh — clean, repeatable product screenshots for the
# headroom.zantos.co landing page, using the built-in `--demo` fixture mode.
#
# `--demo` swaps the live providers for fixed sample data (Claude Max 72/38,
# Codex Prolite 91/64, API spend $142.67 / $58.90, renewals Jul 28 / Jul 15) across
# every surface, so the popover, macOS widgets, and iPhone mirror all agree. Demo
# content stays in memory, so this never touches your real settings, keys, or usage.
#
# The iOS captures are fully automated and headless (no Simulator GUI, no screen
# takeover). The macOS captures (popover / menu bar / widgets) need the app live in
# your real menu bar plus a click or two, so this script builds + launches the demo
# app and prints the exact capture commands.
#
# Usage:  Scripts/capture-demo-screenshots.sh [output-dir]
#         (default output dir: ~/Desktop/headroom-shots)
#         HEADROOM_IOS_ONLY=1 skips the interactive macOS capture handoff.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-$HOME/Desktop/headroom-shots}"
IOS_BUNDLE="com.kylezantos.headroom.ios"
mkdir -p "$OUT"
mkdir -p "$OUT/appstore-6.9" "$OUT/appstore-13"

# The app targets iOS 26 (macOS 26 era), so an iOS-26 simulator is required. iPhone 16
# Pro (Dynamic Island, Pro) fits the portfolio's MagicUI iPhone frame with a negligible
# object-cover crop. Create a dedicated device on the newest installed iOS-26 runtime.
PHONE_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
PHONE_SIM_NAME="Headroom 16 Pro Max"
IPAD_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"
IPAD_SIM_NAME="Headroom iPad Pro 13"
RUNTIME="$(xcrun simctl list runtimes 2>/dev/null | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-26[0-9-]*' | tail -1)"
[ -z "$RUNTIME" ] && { echo "✗ No iOS 26 simulator runtime installed (needed for Headroom's iOS target)." >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 \
  || { echo "✗ ffmpeg is required to remove the PNG alpha channel for App Store upload." >&2; exit 1; }

echo "▸ Output → $OUT"

# ─────────────────────────────────────────────────────────────────────────────
# iOS — automated, headless: build → install → 9:41 status bar → --demo → shoot
# ─────────────────────────────────────────────────────────────────────────────
ensure_device() {
  local name="$1"
  local type="$2"
  local udid
  udid="$(xcrun simctl list devices | grep "$name (" | grep -oE '[0-9A-Fa-f-]{36}' | head -1 || true)"
  if [ -z "$udid" ]; then
    udid="$(xcrun simctl create "$name" "$type" "$RUNTIME")"
    echo "▸ iOS: created $name ($udid) on $RUNTIME" >&2
  fi
  echo "$udid"
}

PHONE_UDID="$(ensure_device "$PHONE_SIM_NAME" "$PHONE_DEVICE_TYPE")"
IPAD_UDID="$(ensure_device "$IPAD_SIM_NAME" "$IPAD_DEVICE_TYPE")"

echo "▸ iOS: building HeadroomIOS…"
xcodebuild build \
  -project Headroom.xcodeproj \
  -scheme HeadroomIOS \
  -destination "id=$PHONE_UDID" \
  -derivedDataPath .build/ios-demo \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -quiet
APP_PATH="$(find .build/ios-demo/Build/Products -maxdepth 3 -name 'HeadroomIOS.app' | head -1)"

xcrun simctl boot "$PHONE_UDID" 2>/dev/null || true
xcrun simctl boot "$IPAD_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$PHONE_UDID" -b || true
xcrun simctl bootstatus "$IPAD_UDID" -b || true
xcrun simctl install "$PHONE_UDID" "$APP_PATH"
xcrun simctl install "$IPAD_UDID" "$APP_PATH"

shoot_ios() {   # $1 = udid, $2 = light|dark, $3 = output path
  local udid="$1"
  local appearance="$2"
  local output="$3"
  xcrun simctl ui "$udid" appearance "$appearance" 2>/dev/null || true
  xcrun simctl terminate "$udid" "$IOS_BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3
  xcrun simctl launch "$udid" "$IOS_BUNDLE" --demo
  sleep 8   # let the first-boot "Apple Intelligence" system banner auto-dismiss
  xcrun simctl io "$udid" screenshot "$output"
  local opaque="${output%.png}-opaque.png"
  ffmpeg -loglevel error -i "$output" -vf format=rgb24 -y "$opaque"
  mv "$opaque" "$output"
  echo "  ✓ $output"
}
echo "▸ iOS: capturing App Store iPhone + iPad sets…"
shoot_ios "$PHONE_UDID" dark "$OUT/appstore-6.9/ios-usage-dark-6.9.png"
shoot_ios "$PHONE_UDID" light "$OUT/appstore-6.9/ios-usage-light-6.9.png"
shoot_ios "$IPAD_UDID" dark "$OUT/appstore-13/ios-usage-dark-13.png"
shoot_ios "$IPAD_UDID" light "$OUT/appstore-13/ios-usage-light-13.png"
cp "$OUT/appstore-6.9/ios-usage-dark-6.9.png" "$OUT/ios-usage-dark.png"
cp "$OUT/appstore-6.9/ios-usage-light-6.9.png" "$OUT/ios-usage-light.png"
echo "  (drop into the MagicUI Iphone frame; keep the default Dynamic Island)"

if [ "${HEADROOM_IOS_ONLY:-0}" = "1" ]; then
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# macOS — build the real .app (with widget extension) and launch it in --demo
# ─────────────────────────────────────────────────────────────────────────────
echo "▸ macOS: building Headroom.app (widget-discoverable bundle)…"
Scripts/build-app.sh
echo "▸ macOS: launching Headroom.app --demo…"
# Only this worktree's earlier demo copy is ours to stop. Never quit the installed app
# (release-operations: no broad process termination); the single-instance guard makes a
# second bundled copy exit, so ask the user to quit it instead.
WORKTREE_BINARY="$PWD/Headroom.app/Contents/MacOS/Headroom"
for pid in $(pgrep -f "^${WORKTREE_BINARY}" || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1
if pgrep -x Headroom >/dev/null; then
  echo "✗ Another Headroom is running. Quit it from its menu, then rerun this script." >&2
  echo "  (Or set HEADROOM_IOS_ONLY=1 to capture only the iPhone set.)" >&2
  exit 1
fi
open ./Headroom.app --args --demo
sleep 2

cat <<EOF

────────────────────────────────────────────────────────────────────────────
macOS captures (a few clicks — the popover/widgets can't be posed headlessly,
they need the app live in your real menu bar):

1) POPOVER (hero, with API Spend):
     • Click the Headroom item in the menu bar so the popover opens.
     • Capture just that window, no drop shadow:
         screencapture -o -w "$OUT/mac-popover.png"
       (cursor becomes a camera — click the popover)

2) MENU BAR strip (icon + 38%):
     • screencapture -R=<x>,<y>,<w>,<h> "$OUT/mac-menubar.png"

3) WIDGETS (large / medium / small):
     • The demo app already wrote the fixture into the widget App Group,
       so Headroom widgets show demo data. Add them to the desktop (or
       Notification Center), then screencapture -R=<region> per size.
────────────────────────────────────────────────────────────────────────────
EOF
