#!/usr/bin/env bash
#
# capture-appstore-shots.sh — the Graphite App Store set (U18, R31), headless end to end.
#
#   Scripts/capture-appstore-shots.sh [--frames I1,I2] [--device iphone69|ipad13|all]
#                                     [--out DIR] [--skip-build] [--keep-booted]
#
# For every frame in design/appstore/shots.json (or the --frames subset) it:
#   1. builds HeadroomIOS once (Debug: the widget wall behind `--demo-screen widgets` is
#      DEBUG-only),
#   2. boots dedicated simulators it creates by name if missing — "AppStore iPhone 17 Pro Max"
#      (6.9″, 1320×2868) and "AppStore iPad Pro 13" (13″, 2064×2752) — never the shared
#      booted iPhone 17 Pro,
#   3. fixes the status bar (9:41 on a fixed date, full battery with no charging bolt, full
#      bars), sets the frame's appearance, launches `--demo --demo-variant <v> --demo-screen
#      <s>` and waits until two consecutive screenshots are identical (motion settled),
#   4. composes the frame in design/appstore/compositor.html with
#      `dev-browser --headless --browser agent-qa`,
#   5. converts to sRGB, strips alpha, and verifies pixel size, `hasAlpha: no` and the sRGB
#      profile with `sips -g`.
#
# Output: DIR (default dist/appstore/, gitignored): raw/ holds the simulator captures,
# <device>/ the composed frames, verify.txt the sips report.
#
# Safety (R38, release-operations): this script never quits, kills or launches the Mac app —
# no killall, no pkill, no `open`. It only terminates HeadroomIOS inside its own simulators,
# and shuts down only the simulators it booted itself (unless --keep-booted).
#
# TODO(U18, Mac frame): frames of kind "mac" (I3, P3 "Your Mac does the reading") are skipped
# until shots.json's `macCapture` names an approved Mac image. `swift run Headroom
# --render-popover <dir>` cannot supply it yet: its multi-account path renders `multi-4` as a
# plain two-provider popover (BUGS.md, "The harness's multi-account path renders neither
# Grok/Cursor nor the spend card"). Fix that harness gap, or take one live `--demo multi-4`
# capture that Kyle explicitly approves, then set macCapture.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

SHOTS="$ROOT/design/appstore/shots.json"
COMPOSITOR="$ROOT/design/appstore/compositor.html"
IOS_BUNDLE="com.kylezantos.headroom.ios"
DERIVED="$ROOT/.build/appstore-ios"
SRGB_PROFILE="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
# 9:41 on a fixed date: an ISO instant also fixes the date the iPad status bar shows (research
# appstore.md §1). simctl accepts only a UTC instant with fractional seconds and draws it in
# the host's time zone, so 9:41 local on STATUS_DATE is converted to UTC here.
STATUS_DATE="${HEADROOM_APPSTORE_STATUS_DATE:-2026-01-13}"
STATUS_TIME="$(python3 -c "import datetime as d,sys; t=d.datetime.strptime(sys.argv[1]+' 09:41','%Y-%m-%d %H:%M').astimezone(d.timezone.utc); print(t.strftime('%Y-%m-%dT%H:%M:%S.000Z'))" "$STATUS_DATE")"
SETTLE_MIN_SECONDS="${HEADROOM_APPSTORE_SETTLE_MIN:-4}"
SETTLE_MAX_SECONDS="${HEADROOM_APPSTORE_SETTLE_MAX:-25}"
BROWSER_PAGE="headroom-appstore-u18"

OUT="$ROOT/dist/appstore"
FRAMES_FILTER=""
DEVICE_FILTER="all"
SKIP_BUILD=0
KEEP_BOOTED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --frames) FRAMES_FILTER="$2"; shift 2 ;;
    --device) DEVICE_FILTER="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --keep-booted) KEEP_BOOTED=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "✗ Unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac

for tool in xcrun xcodebuild sips python3 ffmpeg dev-browser cmp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "✗ $tool is required." >&2; exit 1; }
done
# sips converts color and verifies, but cannot drop a PNG alpha channel losslessly; ffmpeg's
# rgb24 pass does (research appstore.md §6.5).

RUNTIME="${HEADROOM_APPSTORE_RUNTIME:-$(xcrun simctl list runtimes 2>/dev/null | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-26[0-9-]*' | tail -1)}"
[ -n "$RUNTIME" ] || { echo "✗ No iOS 26 simulator runtime installed (set HEADROOM_APPSTORE_RUNTIME)." >&2; exit 1; }

mkdir -p "$OUT/raw" "$OUT/iphone69" "$OUT/ipad13"
LOG="$OUT/capture.log"
: > "$LOG"
echo "▸ Output → $OUT  (runtime $RUNTIME)"

# ── Frame table → job list ──────────────────────────────────────────────────────────────
# One TSV row per frame: id, device, kind, appearance, variant, screen, wall, output,
# simulator name, simulator device type, mac capture.
JOBS="$(python3 - "$SHOTS" "$FRAMES_FILTER" "$DEVICE_FILTER" <<'PY'
import json, sys
shots_path, frame_filter, device_filter = sys.argv[1], sys.argv[2], sys.argv[3]
table = json.load(open(shots_path))
wanted = [f.strip() for f in frame_filter.split(",") if f.strip()]
pool = table["frames"] + table.get("reserve", [])
frames = [f for f in pool if f["id"] in wanted] if wanted else table["frames"]
missing = set(wanted) - {f["id"] for f in frames}
if missing:
    sys.exit("unknown frame id(s): " + ", ".join(sorted(missing)))
for f in frames:
    if device_filter != "all" and f["device"] != device_filter:
        continue
    d = table["devices"][f["device"]]
    row = [f["id"], f["device"], f["kind"], f["appearance"], f["variant"], f["screen"],
           f.get("widgetWall") or "-", f["output"], d["simulatorName"], d["simulatorDeviceType"],
           f.get("macCapture") or "-"]
    print("\t".join(row))
PY
)"
[ -n "$JOBS" ] || { echo "✗ No frames selected." >&2; exit 1; }

# ── Simulators ──────────────────────────────────────────────────────────────────────────
BOOTED_BY_US=()
udid_for() {   # exact-name lookup among available devices
  python3 - "$1" <<'PY'
import json, subprocess, sys
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
for runtime, entries in devices.items():
    for d in entries:
        if d["name"] == sys.argv[1]:
            print(d["udid"]); sys.exit(0)
PY
}
state_of() {
  xcrun simctl list devices -j | python3 -c "import json,sys; u=sys.argv[1]; print(next((d['state'] for e in json.load(sys.stdin)['devices'].values() for d in e if d['udid']==u), ''))" "$1"
}
ensure_device() {   # $1 name, $2 device type → prints udid
  local udid
  udid="$(udid_for "$1")"
  if [ -z "$udid" ]; then
    udid="$(xcrun simctl create "$1" "$2" "$RUNTIME")"
    echo "  created $1 ($udid)" >&2
  fi
  echo "$udid"
}
cleanup() {
  [ "$KEEP_BOOTED" = 1 ] && return 0
  for udid in "${BOOTED_BY_US[@]:-}"; do
    [ -n "$udid" ] && xcrun simctl shutdown "$udid" >>"$LOG" 2>&1 || true
  done
}
trap cleanup EXIT

PREPARED=" "
prepare_device() {   # $1 udid — boot, install, status bar; once per run
  local udid="$1"
  case "$PREPARED" in *" $udid "*) return 0 ;; esac
  if [ "$(state_of "$udid")" != "Booted" ]; then
    xcrun simctl boot "$udid" >>"$LOG" 2>&1
    BOOTED_BY_US+=("$udid")
  fi
  xcrun simctl bootstatus "$udid" -b >>"$LOG" 2>&1
  xcrun simctl install "$udid" "$APP_PATH"
  # Full battery reported as discharging: the simulator draws a charging bolt for
  # `charging`/`charged` states (seen on the published iPad set).
  xcrun simctl status_bar "$udid" override \
    --time "$STATUS_TIME" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName '' \
    --batteryState discharging --batteryLevel 100
  PREPARED="$PREPARED$udid "
}

# ── Build once ──────────────────────────────────────────────────────────────────────────
if [ "$SKIP_BUILD" = 0 ]; then
  echo "▸ Building HeadroomIOS (Debug, simulator)…"
  xcodebuild build -project Headroom.xcodeproj -scheme HeadroomIOS -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO >"$OUT/build.log" 2>&1 \
    || { echo "✗ Build failed; see $OUT/build.log" >&2; exit 1; }
fi
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/HeadroomIOS.app"
[ -d "$APP_PATH" ] || { echo "✗ $APP_PATH missing (drop --skip-build)." >&2; exit 1; }

# ── Capture ─────────────────────────────────────────────────────────────────────────────
# A frame whose content area (below the status bar) is one flat color is the launch frame,
# not the app: a slow relaunch once "settled" on two identical black frames.
is_flat() {   # $1 png
  local stats ymin ymax
  stats="$(ffmpeg -nostdin -i "$1" -vf "crop=iw:ih*0.85:0:ih*0.15,signalstats,metadata=print" -f null - 2>&1)"
  ymin="$(grep -oE 'signalstats.YMIN=[0-9]+' <<< "$stats" | head -1 | cut -d= -f2)"
  ymax="$(grep -oE 'signalstats.YMAX=[0-9]+' <<< "$stats" | head -1 | cut -d= -f2)"
  [ -n "$ymin" ] && [ -n "$ymax" ] && [ $((ymax - ymin)) -lt 8 ]
}
app_running() {   # $1 udid
  xcrun simctl spawn "$1" launchctl list 2>/dev/null | grep -q "UIKitApplication:$IOS_BUNDLE"
}
settle_capture() {   # $1 udid, $2 output — app up, then two identical, non-flat screenshots
  local udid="$1" output="$2" previous="$2.prev.png" waited=0
  until app_running "$udid"; do
    sleep 1; waited=$((waited + 1))
    [ "$waited" -ge "$SETTLE_MAX_SECONDS" ] && return 1
  done
  sleep "$SETTLE_MIN_SECONDS"; waited=$((waited + SETTLE_MIN_SECONDS))
  xcrun simctl io "$udid" screenshot --type=png "$previous" >>"$LOG" 2>&1
  while :; do
    sleep 1; waited=$((waited + 1))
    xcrun simctl io "$udid" screenshot --type=png "$output" >>"$LOG" 2>&1
    if cmp -s "$previous" "$output" && ! is_flat "$output"; then rm -f "$previous"; return 0; fi
    if [ "$waited" -ge "$SETTLE_MAX_SECONDS" ]; then rm -f "$previous"; return 1; fi
    mv "$output" "$previous"
  done
}

COMPOSE_JOBS="$OUT/compose-jobs.tsv"
: > "$COMPOSE_JOBS"
SKIPPED=()
UNSETTLED=()
# The job list rides on fd 3 so simctl and ffmpeg can never swallow it from stdin.
while IFS=$'\t' read -r -u 3 id device kind appearance variant screen wall output sim_name sim_type mac; do
  if [ "$kind" = "mac" ] && [ "$mac" = "-" ]; then
    SKIPPED+=("$id (Mac capture pending: BUGS.md render-popover multi-4 gap)")
    continue
  fi
  udid="$(ensure_device "$sim_name" "$sim_type")"
  prepare_device "$udid"
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl terminate "$udid" "$IOS_BUNDLE" >>"$LOG" 2>&1 || true
  args=(--demo --demo-variant "$variant" --demo-screen "$screen")
  [ "$wall" != "-" ] && args+=(--widget-wall "$wall")
  echo "▸ $id  $device  $appearance  ${args[*]}"
  xcrun simctl launch "$udid" "$IOS_BUNDLE" "${args[@]}" >>"$LOG" 2>&1
  raw="$OUT/raw/$id-$device-$appearance.png"
  if ! settle_capture "$udid" "$raw"; then
    UNSETTLED+=("$id")
    echo "  ! $id did not settle within ${SETTLE_MAX_SECONDS}s; kept the last capture" >&2
  fi
  xcrun simctl terminate "$udid" "$IOS_BUNDLE" >>"$LOG" 2>&1 || true
  # Tabs are IFS whitespace, so an empty field would collapse: "-" stands for "no Mac image".
  [ "$mac" = "-" ] && mac_path="-" || mac_path="$ROOT/$mac"
  printf '%s\t%s\t%s\t%s\n' "$id" "$raw" "$mac_path" "$OUT/$device/$output" >> "$COMPOSE_JOBS"
done 3<<< "$JOBS"

[ -s "$COMPOSE_JOBS" ] || { echo "✗ Nothing to compose."; exit 1; }

# ── Compose (headless Chromium via dev-browser) ─────────────────────────────────────────
# The dev-browser sandbox can only write ~/.dev-browser/tmp, so the job list is inlined into
# the script and the frames are copied out afterwards. The shared agent-qa daemon is left
# running for other work; only this run's named page is closed.
RUN_TAG="appstore-$(date +%Y%m%d-%H%M%S)"
COMPOSE_JS="$OUT/compose.js"
python3 - "$SHOTS" "$COMPOSE_JOBS" "$COMPOSITOR" "$RUN_TAG" "$BROWSER_PAGE" > "$COMPOSE_JS" <<'PY'
import json, sys, pathlib
shots, jobs_path, compositor, tag, page_name = sys.argv[1:6]
table = json.load(open(shots))
by_id = {f["id"]: f for f in table["frames"] + table.get("reserve", [])}
jobs = []
for line in open(jobs_path):
    fid, raw, mac, out = line.rstrip("\n").split("\t")
    frame = by_id[fid]
    w, h = table["devices"][frame["device"]]["width"], table["devices"][frame["device"]]["height"]
    jobs.append({
        "frame": frame,
        "assets": {"capture": pathlib.Path(raw).as_uri(), "mac": pathlib.Path(mac).as_uri() if mac != "-" else None},
        "size": [w, h],
        "name": f"{tag}-{pathlib.Path(out).name}",
    })
print(f"const JOBS = {json.dumps(jobs)};")
print(f"const URL = {json.dumps(pathlib.Path(compositor).as_uri() + '?pipeline=1')};")
print(f"const PAGE = {json.dumps(page_name)};")
print(r"""
const page = await browser.getPage(PAGE);
for (const job of JOBS) {
  await page.setViewportSize({ width: job.size[0], height: job.size[1] });
  await page.goto(URL);
  const result = await page.evaluate(([frame, assets]) => window.composeShot(frame, assets), [job.frame, job.assets]);
  const buf = await page.locator('#canvas').screenshot({ animations: 'disabled', scale: 'css' });
  const path = await saveScreenshot(buf, job.name);
  console.log(JSON.stringify({ id: job.frame.id, path, result }));
}
await browser.closePage(PAGE);
""")
PY
echo "▸ Composing $(wc -l < "$COMPOSE_JOBS" | tr -d ' ') frame(s) in headless Chromium…"
dev-browser --headless --browser agent-qa --timeout 300 run "$COMPOSE_JS" > "$OUT/compose.log" 2>&1 \
  || { echo "✗ Compositor run failed; see $OUT/compose.log" >&2; exit 1; }

# ── sRGB, no alpha, verify ──────────────────────────────────────────────────────────────
VERIFY="$OUT/verify.txt"
: > "$VERIFY"
FAILED=()
while IFS=$'\t' read -r -u 3 id raw mac out; do
  rendered="$HOME/.dev-browser/tmp/$RUN_TAG-$(basename "$out")"
  [ -f "$rendered" ] || { FAILED+=("$id (no render)"); continue; }
  device="$(basename "$(dirname "$out")")"
  expected="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1]))['devices'][sys.argv[2]]; print(d['width'], d['height'])" "$SHOTS" "$device")"
  tmp="$out.tmp.png"
  sips --matchTo "$SRGB_PROFILE" "$rendered" --out "$tmp" >>"$LOG" 2>&1
  ffmpeg -nostdin -loglevel error -i "$tmp" -vf format=rgb24 -y "$out"
  sips --embedProfile "$SRGB_PROFILE" "$out" >>"$LOG" 2>&1
  rm -f "$tmp" "$rendered"
  report="$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g space -g profile "$out")"
  echo "$report" >> "$VERIFY"
  width="$(awk '/pixelWidth/ {print $2}' <<< "$report")"
  height="$(awk '/pixelHeight/ {print $2}' <<< "$report")"
  alpha="$(awk '/hasAlpha/ {print $2}' <<< "$report")"
  profile="$(sed -n 's/^ *profile: //p' <<< "$report")"
  if [ "$width $height" != "$expected" ] || [ "$alpha" != "no" ] || [[ "$profile" != sRGB* ]]; then
    FAILED+=("$id (${width}×${height}, hasAlpha $alpha, profile $profile)")
  else
    echo "  ✓ $id → ${out#$ROOT/} (${width}×${height}, hasAlpha no, $profile)"
  fi
done 3< "$COMPOSE_JOBS"

echo
echo "▸ sips report → ${VERIFY#$ROOT/}"
for s in "${SKIPPED[@]:-}"; do [ -n "$s" ] && echo "  – skipped $s"; done
for u in "${UNSETTLED[@]:-}"; do [ -n "$u" ] && echo "  ! unsettled $u"; done
if [ "${#FAILED[@]}" -gt 0 ]; then
  for f in "${FAILED[@]}"; do echo "  ✗ $f"; done
  exit 1
fi
[ "${#UNSETTLED[@]}" -eq 0 ] || exit 3
