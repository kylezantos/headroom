#!/usr/bin/env bash
# Live-tune the popover with DialKit (https://github.com/mikelikesdesign/dialkit-macos).
# Usage: Scripts/dialkit.sh [demo-scenario]   (default: multi-3)
# Builds Headroom with HEADROOM_DIALKIT=1, starts the inspector, then the demo with a pinned
# popover. Ctrl-C stops both. A normal `swift build` never includes DialKit.
set -euo pipefail
cd "$(dirname "$0")/.."
scenario="${1:-multi-3}"

HEADROOM_DIALKIT=1 swift build --product Headroom
inspector_pkg=".build/checkouts/dialkit-macos"
swift build --package-path "$inspector_pkg" --product dialkit-macos

pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

if ! lsof -nP -iTCP:44777 -sTCP:LISTEN >/dev/null 2>&1; then
  "$inspector_pkg/.build/debug/dialkit-macos" > /tmp/dialkit-inspector.log 2>&1 &
  pids+=($!)
  sleep 1
fi
.build/debug/Headroom --demo "$scenario" > /tmp/headroom-dialkit.log 2>&1 &
pids+=($!)
echo "DialKit running (demo: $scenario). Ctrl-C to stop."
wait
