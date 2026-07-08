#!/usr/bin/env bash
#
# capture-demo-screenshots.sh — clean, repeatable product screenshots for the
# headroom.zantos.co landing page, using the built-in `--demo` fixture mode.
#
# `--demo` swaps the live providers for fixed sample data (Claude Max 72/38,
# Codex Prolite 91/64, API spend $142.67 / $58.90, renewals Jul 28 / Jul 15) across
# every surface, so the popover, macOS widgets, and iPhone mirror all agree. Demo
# preferences live in a private UserDefaults suite, so this never touches your real
# settings, keys, or usage.
#
# The iOS captures are fully automated and headless (no Simulator GUI, no screen
# takeover). The macOS captures (popover / menu bar / widgets) need the app live in
# your real menu bar plus a click or two, so this script builds + launches the demo
# app and prints the exact capture commands.
#
# Usage:  Scripts/capture-demo-screenshots.sh [output-dir]
#         (default output dir: ~/Desktop/headroom-shots)

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-$HOME/Desktop/headroom-shots}"
IOS_BUNDLE="com.kylezantos.headroom.ios"
mkdir -p "$OUT"

# The app targets iOS 26 (macOS 26 era), so an iOS-26 simulator is required. iPhone 16
# Pro (Dynamic Island, Pro) fits the portfolio's MagicUI iPhone frame with a negligible
# object-cover crop. Create a dedicated device on the newest installed iOS-26 runtime.
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
SIM_NAME="Headroom 16 Pro"
RUNTIME="$(xcrun simctl list runtimes 2>/dev/null | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-26[0-9-]*' | tail -1)"
[ -z "$RUNTIME" ] && { echo "✗ No iOS 26 simulator runtime installed (needed for Headroom's iOS target)." >&2; exit 1; }

echo "▸ Output → $OUT"

# ─────────────────────────────────────────────────────────────────────────────
# iOS — automated, headless: build → install → 9:41 status bar → --demo → shoot
# ─────────────────────────────────────────────────────────────────────────────
UDID="$(xcrun simctl list devices | grep "$SIM_NAME (" | grep -oE '[0-9A-Fa-f-]{36}' | head -1 || true)"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")"
  echo "▸ iOS: created $SIM_NAME ($UDID) on $RUNTIME"
fi

echo "▸ iOS: building HeadroomIOS…"
xcodebuild build \
  -project Headroom.xcodeproj \
  -scheme HeadroomIOS \
  -destination "id=$UDID" \
  -derivedDataPath .build/ios-demo \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -quiet
APP_PATH="$(find .build/ios-demo/Build/Products -maxdepth 3 -name 'HeadroomIOS.app' | head -1)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b || true
xcrun simctl install "$UDID" "$APP_PATH"

shoot_ios() {   # $1 = light|dark
  xcrun simctl ui "$UDID" appearance "$1" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$IOS_BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 --operatorName " "
  xcrun simctl launch "$UDID" "$IOS_BUNDLE" --demo
  sleep 8   # let the first-boot "Apple Intelligence" system banner auto-dismiss
  xcrun simctl io "$UDID" screenshot "$OUT/ios-usage-$1.png"
  echo "  ✓ $OUT/ios-usage-$1.png"
}
echo "▸ iOS: capturing light + dark…"
shoot_ios dark
shoot_ios light
echo "  (drop into the MagicUI Iphone frame; keep the default Dynamic Island)"

# ─────────────────────────────────────────────────────────────────────────────
# macOS — build the real .app (with widget extension) and launch it in --demo
# ─────────────────────────────────────────────────────────────────────────────
echo "▸ macOS: building Headroom.app (widget-discoverable bundle)…"
Scripts/build-app.sh
echo "▸ macOS: launching Headroom.app --demo…"
killall Headroom 2>/dev/null || true   # ensure a fresh instance picks up --demo
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
