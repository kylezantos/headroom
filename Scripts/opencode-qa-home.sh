#!/bin/bash
# OpenCode QA homes for Headroom (plan U12, KTD18).
#
# Downloads a pinned OpenCode 2.x release into .context/, verifies its SHA-256
# BEFORE extracting or running it, and builds scratch OpenCode homes that point
# at the stub Console (Scripts/opencode-stub-console.py).
#
# Safety rules this script enforces:
#   - OpenCode 2.x migrates a 1.x home one way. Every run exports all four XDG
#     variables (plus HOME) to a scratch home, through `env -i`, so no inherited
#     OPENCODE_* or XDG_* variable reaches the client.
#   - Homes must live under this repo's .context/ and must not resolve to, or
#     contain, a default OpenCode home (~/.local/share/opencode and friends).
#   - `opencode service` is refused; server-backed commands must pass --standalone.
#   - The stub is only ever started inside this script's own process, behind an
#     EXIT trap, so it never outlives the command.
#
# Usage:
#   opencode-qa-home.sh fetch [--archive <zip>]       verify (and extract) the pinned build; prints the binary path
#   opencode-qa-home.sh seed-empty <home>                 a signed-out home (no credential)
#   opencode-qa-home.sh seed-key <home> [--port P] [--integration opencode|opencode-go] [--no-org]
#   opencode-qa-home.sh seed-device <home> [--port P] [--no-workspace] [--token-lifetime S]
#   opencode-qa-home.sh run <home> [--cwd <dir>] -- <opencode args...>
#   opencode-qa-home.sh usage <home>                   run `api --standalone experimental.usage.limits`
#   opencode-qa-home.sh env <home>                     print the environment a run uses
#
# Exit codes: 0 ok, 2 usage error, 3 checksum mismatch, 4 refused path or command,
# 5 download or extraction failure; `run`/`usage` return the client's own status.

set -u

PIN_VERSION="2.2.5"
PIN_ASSET="opencode-darwin-arm64.zip"
PIN_SHA256="25ba9908979fa7d764792c82589b4b5768ab1511154e0317d98aa77d216ce767"
PIN_URL="https://github.com/anomalyco/opencode/releases/download/v${PIN_VERSION}/${PIN_ASSET}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
CONTEXT_DIR="$REPO_ROOT/.context"
QA_ROOT="$CONTEXT_DIR/opencode-qa"
DL_DIR="$QA_ROOT/dl/v$PIN_VERSION"
BIN_DIR="$QA_ROOT/bin/v$PIN_VERSION"
BIN="$BIN_DIR/opencode"
BIN_SHA_FILE="$BIN_DIR/opencode.sha256"
STUB="$SCRIPT_DIR/opencode-stub-console.py"
DEFAULT_PORT=48765

die() { local code=$1; shift; echo "opencode-qa-home: $*" >&2; exit "$code"; }

realpath_py() { /usr/bin/python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

sha256_of() { /usr/bin/shasum -a 256 "$1" | awk '{print $1}'; }

# ---------------------------------------------------------------------------
# Pinned build
# ---------------------------------------------------------------------------

verify_archive() {
  local archive=$1 actual
  [ -f "$archive" ] || die 5 "archive not found: $archive"
  actual=$(sha256_of "$archive")
  if [ "$actual" != "$PIN_SHA256" ]; then
    echo "opencode-qa-home: SHA-256 mismatch for $archive" >&2
    echo "  expected $PIN_SHA256" >&2
    echo "  actual   $actual" >&2
    echo "  nothing was extracted or run" >&2
    exit 3
  fi
}

cmd_fetch() {
  local archive=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --archive) archive=${2:-}; shift 2 || die 2 "--archive needs a path" ;;
      *) die 2 "fetch: unknown argument $1" ;;
    esac
  done
  mkdir -p "$DL_DIR" "$QA_ROOT/bin"
  if [ -z "$archive" ]; then
    archive="$DL_DIR/$PIN_ASSET"
    if [ ! -f "$archive" ]; then
      echo "downloading $PIN_URL" >&2
      /usr/bin/curl -fL --proto '=https' --max-time 600 -o "$archive.partial" "$PIN_URL" \
        || { rm -f "$archive.partial"; die 5 "download failed"; }
      mv "$archive.partial" "$archive"
    fi
  fi
  # Verify first. A tampered or substituted archive is never extracted or run.
  verify_archive "$archive"

  if [ -x "$BIN" ] && [ -f "$BIN_SHA_FILE" ] && [ "$(sha256_of "$BIN")" = "$(cat "$BIN_SHA_FILE")" ]; then
    binary_stamp > "$BIN_DIR/opencode.stamp"
    echo "$BIN"
    return 0
  fi
  local staging
  staging=$(mktemp -d "$QA_ROOT/bin/.extract.XXXXXX") || die 5 "mktemp failed"
  /usr/bin/ditto -x -k "$archive" "$staging" || { rm -rf "$staging"; die 5 "extraction failed"; }
  local entries
  entries=$(cd "$staging" && ls -A)
  if [ "$entries" != "opencode" ] || [ ! -f "$staging/opencode" ] || [ -L "$staging/opencode" ]; then
    rm -rf "$staging"
    die 5 "unexpected archive contents: $entries"
  fi
  chmod 755 "$staging/opencode"
  rm -rf "$BIN_DIR"
  mkdir -p "$BIN_DIR"
  mv "$staging/opencode" "$BIN"
  rmdir "$staging"
  sha256_of "$BIN" > "$BIN_SHA_FILE"
  binary_stamp > "$BIN_DIR/opencode.stamp"
  echo "$BIN"
}

binary_stamp() { /usr/bin/stat -f '%i %z %m' "$BIN"; }

require_binary() {
  # `fetch` hashed the binary when it extracted it; a run checks the cheap stamp
  # (inode, size, mtime) recorded then, so a replaced binary is still refused.
  [ -x "$BIN" ] && [ -f "$BIN_SHA_FILE" ] && [ -f "$BIN_DIR/opencode.stamp" ] \
    || die 4 "pinned binary missing; run: $0 fetch"
  [ "$(binary_stamp)" = "$(cat "$BIN_DIR/opencode.stamp")" ] \
    || die 3 "extracted binary changed since it was verified; run: $0 fetch"
}

# ---------------------------------------------------------------------------
# Home guard
# ---------------------------------------------------------------------------

# Default OpenCode homes (and the roots that contain them). A scratch home may not
# resolve to any of these, sit inside one, or contain one.
default_homes() {
  local h; h=$(realpath_py "$HOME")
  printf '%s\n' "$h/.local/share/opencode" "$h/.config/opencode" "$h/.cache/opencode" \
    "$h/.local/state/opencode" "$h/.opencode" "$h/Library/Application Support/opencode" \
    "$h/Library/Caches/opencode" "$h/Library/Preferences/opencode"
}

path_within() { # $1 inside-or-equal $2
  case "$1/" in "$2"/*) return 0 ;; esac
  return 1
}

guard_home() {
  local raw=$1 home sub resolved d
  case "$raw" in /*) ;; *) raw="$PWD/$raw" ;; esac
  # Resolve without creating anything: a refused path must never be touched.
  home=$(realpath_py "$raw")
  path_within "$home" "$(realpath_py "$CONTEXT_DIR")" \
    || die 4 "refusing $home: scratch homes must live under $CONTEXT_DIR"
  [ "$home" != "$(realpath_py "$CONTEXT_DIR")" ] || die 4 "refusing the .context root itself"
  for sub in "" /data /config /cache /state /home; do
    resolved=$(realpath_py "$home$sub")
    while IFS= read -r d; do
      if path_within "$resolved" "$d" || path_within "$d" "$resolved"; then
        die 4 "refusing $home$sub: it resolves to or contains the default OpenCode home $d"
      fi
    done < <(default_homes)
  done
  echo "$home"
}

new_home() {
  local home
  home=$(guard_home "$1") || exit $?
  if [ -e "$home" ] && [ -n "$(ls -A "$home" 2>/dev/null)" ]; then
    die 4 "refusing to seed $home: it already exists and is not empty"
  fi
  mkdir -p "$home/data" "$home/config" "$home/cache" "$home/state" "$home/home"
  # Re-check after creation, so a symlink planted in the meantime is caught.
  guard_home "$home" >/dev/null || exit $?
  echo "$home"
}

existing_home() {
  local home
  home=$(guard_home "$1") || exit $?
  [ -d "$home/data" ] && [ -d "$home/state" ] || die 4 "$home is not a seeded QA home"
  echo "$home"
}

# ---------------------------------------------------------------------------
# Running the client
# ---------------------------------------------------------------------------

qa_cwd() {
  # Outside any git repo (KTD2.3): inside one the client runs git and records the repo.
  local dir="${TMPDIR:-/tmp}"; dir="${dir%/}/headroom-opencode-qa-cwd"
  mkdir -p "$dir"
  if /usr/bin/git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    die 4 "QA cwd $dir is inside a git repo"
  fi
  echo "$dir"
}

client_env() { # prints NAME=value lines for env -i
  local home=$1
  printf '%s\n' \
    "HOME=$home/home" \
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
    "TMPDIR=${TMPDIR:-/tmp}" \
    "LANG=en_US.UTF-8" \
    "TERM=${QA_TERM:-dumb}" \
    "XDG_DATA_HOME=$home/data" \
    "XDG_CONFIG_HOME=$home/config" \
    "XDG_CACHE_HOME=$home/cache" \
    "XDG_STATE_HOME=$home/state" \
    "OPENCODE_DISABLE_MODELS_FETCH=1" \
    "OPENCODE_DISABLE_AUTOUPDATE=1"
}

guard_args() {
  [ $# -gt 0 ] || die 2 "no opencode arguments given"
  local first=$1 a standalone=0
  for a in "$@"; do [ "$a" = "--standalone" ] && standalone=1; done
  case "$first" in
    service) die 4 "refusing 'opencode service' (KTD2)" ;;
    --version|-v|--help|-h|serve) return 0 ;;
    upgrade|update|uninstall) die 4 "refusing '$first' in a QA home" ;;
  esac
  for a in "$@"; do
    case "$a" in export) [ "$first" = auth ] && die 4 "refusing 'opencode auth export'" ;; esac
  done
  [ $standalone -eq 1 ] || die 4 "refusing '$first' without --standalone (KTD2)"
}

run_client() { # home cwd args...
  local home=$1 cwd=$2; shift 2
  require_binary
  guard_args "$@"
  local envs=() line
  while IFS= read -r line; do envs+=("$line"); done < <(client_env "$home")
  (cd "$cwd" && exec /usr/bin/env -i "${envs[@]}" "$BIN" "$@")
}

cmd_run() {
  [ $# -ge 1 ] || die 2 "run needs a home"
  local home cwd=""
  home=$(existing_home "$1") || exit $?; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --cwd) cwd=${2:-}; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  [ -n "$cwd" ] || cwd=$(qa_cwd) || exit $?
  run_client "$home" "$cwd" "$@" </dev/null
}

cmd_usage() {
  [ $# -eq 1 ] || die 2 "usage needs exactly one home"
  cmd_run "$1" -- api --standalone experimental.usage.limits
}

cmd_env() {
  local home; home=$(existing_home "${1:-}") || exit $?
  client_env "$home"
}

# ---------------------------------------------------------------------------
# Seeding
# ---------------------------------------------------------------------------

cmd_seed_key() {
  [ $# -ge 1 ] || die 2 "seed-key needs a home"
  local raw=$1; shift
  local port=$DEFAULT_PORT integration=opencode org=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port=$2; shift 2 ;;
      --integration) integration=$2; shift 2 ;;
      --no-org) org=0; shift ;;
      *) die 2 "seed-key: unknown argument $1" ;;
    esac
  done
  case "$integration" in opencode|opencode-go) ;; *) die 2 "integration must be opencode or opencode-go" ;; esac
  local home; home=$(new_home "$raw") || exit $?
  local seed="$home/seed-credential.json"
  /usr/bin/python3 -I - "$seed" "$integration" "$port" "$org" <<'PY'
import json, sys
path, integration, port, org = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
value = {"type": "key", "key": "stub-fake-api-key-not-a-secret"}
if integration == "opencode":
    # A Console key names its server and, unless --no-org, the workspace the key belongs to.
    value["metadata"] = {"server": "http://127.0.0.1:%s/console" % port}
    if org:
        value["metadata"].update({"orgID": "wrk_stub", "orgName": "Stub Workspace"})
# An opencode-go key is a plain key login: no Console server, no workspace.
entry = {
    "id": "cred_stub_" + integration.replace("-", "_"),
    "integrationID": integration,
    "label": "stub",
    "active": True,
    "value": value,
}
with open(path, "w") as handle:
    json.dump([entry], handle, indent=1)
PY
  require_binary
  run_client "$home" "$(qa_cwd)" auth import --standalone "$seed" </dev/null
}

cmd_seed_device() {
  [ $# -ge 1 ] || die 2 "seed-device needs a home"
  local raw=$1; shift
  local port=$DEFAULT_PORT mode=device lifetime=3600
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port=$2; shift 2 ;;
      --no-workspace) mode=device-noworkspace; shift ;;
      --token-lifetime) lifetime=$2; shift 2 ;;
      *) die 2 "seed-device: unknown argument $1" ;;
    esac
  done
  require_binary
  local home; home=$(new_home "$raw") || exit $?
  if /usr/bin/nc -z 127.0.0.1 "$port" 2>/dev/null; then
    die 4 "port $port is already in use; stop whatever is listening there first"
  fi
  /usr/bin/python3 -I "$STUB" --port "$port" --mode "$mode" --token-lifetime "$lifetime" \
    --log "$home/stub-device.log" 2>>"$home/stub-device.log" &
  # Global, not local: the EXIT trap runs after this function returns.
  QA_STUB_PID=$!
  trap 'kill "$QA_STUB_PID" 2>/dev/null; wait "$QA_STUB_PID" 2>/dev/null' EXIT
  local i
  for i in $(seq 1 50); do /usr/bin/nc -z 127.0.0.1 "$port" 2>/dev/null && break; sleep 0.1; done
  /usr/bin/nc -z 127.0.0.1 "$port" 2>/dev/null || die 5 "stub did not start on port $port"
  # No TTY on stdin/stdout, so the client prints the verification URL and never opens a browser.
  run_client "$home" "$(qa_cwd)" auth login --standalone opencode --method device \
    --answer "server=http://127.0.0.1:$port/console" </dev/null
  local status=$?
  if [ "$status" -eq 0 ] && [ "$lifetime" -lt 60 ]; then
    # Age the stored token past its expiry, so the next read must refresh it.
    sleep $((lifetime + 1))
  fi
  return $status
}

cmd_seed_empty() {
  [ $# -eq 1 ] || die 2 "seed-empty needs exactly one home"
  new_home "$1"
}

main() {
  local cmd=${1:-}; [ $# -gt 0 ] && shift
  case "$cmd" in
    fetch) cmd_fetch "$@" ;;
    seed-empty) cmd_seed_empty "$@" ;;
    seed-key) cmd_seed_key "$@" ;;
    seed-device) cmd_seed_device "$@" ;;
    run) cmd_run "$@" ;;
    usage) cmd_usage "$@" ;;
    env) cmd_env "$@" ;;
    -h|--help|help|"") awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; [ -n "$cmd" ] ;;
    *) die 2 "unknown command $cmd" ;;
  esac
}

main "$@"
