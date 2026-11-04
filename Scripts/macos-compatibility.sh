#!/bin/bash
# Shared build/release checks for the supported macOS floor. This file is sourced by
# build-app.sh and release-app.sh; it intentionally performs no work on its own.

HEADROOM_SUPPORTED_MACOS_MINIMUM="${HEADROOM_SUPPORTED_MACOS_MINIMUM:-15.0}"

headroom_normalize_macos_version() {
  local version="$1"
  awk -F. '
    NF < 1 || NF > 3 { exit 1 }
    {
      for (i = 1; i <= NF; i++) {
        if ($i !~ /^[0-9]+$/) exit 1
      }
      printf "%d.%d.%d\n", $1, (NF >= 2 ? $2 : 0), (NF >= 3 ? $3 : 0)
    }
  ' <<< "${version}"
}

headroom_plist_macos_minimum() {
  local plist="$1"
  /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${plist}" 2>/dev/null
}

headroom_verify_plist_macos_minimum() {
  local plist="$1"
  local label="$2"
  local expected
  local actual

  expected="$(headroom_normalize_macos_version "${HEADROOM_SUPPORTED_MACOS_MINIMUM}")" || {
    echo "Invalid supported macOS minimum: ${HEADROOM_SUPPORTED_MACOS_MINIMUM}" >&2
    return 65
  }
  actual="$(headroom_plist_macos_minimum "${plist}")" || {
    echo "Missing LSMinimumSystemVersion in ${label}: ${plist}" >&2
    return 65
  }
  actual="$(headroom_normalize_macos_version "${actual}")" || {
    echo "Malformed LSMinimumSystemVersion in ${label}: ${plist}" >&2
    return 65
  }

  if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected macOS minimum for ${label}: ${actual} (expected ${expected})" >&2
    return 65
  fi
}

headroom_binary_macos_minimums() {
  local binary="$1"
  otool -l "${binary}" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { build = 1; legacy = 0; next }
    build && $1 == "minos" { print $2; build = 0; next }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { legacy = 1; build = 0; next }
    legacy && $1 == "version" { print $2; legacy = 0 }
  '
}

headroom_verify_binary_compatibility() {
  local binary="$1"
  local label="$2"
  local architectures
  local expected
  local minimums
  local minimum
  local normalized

  [[ -f "${binary}" ]] || {
    echo "Missing ${label} executable: ${binary}" >&2
    return 65
  }
  command -v lipo >/dev/null 2>&1 || {
    echo "lipo is required to verify ${label}." >&2
    return 69
  }
  command -v otool >/dev/null 2>&1 || {
    echo "otool is required to verify ${label}." >&2
    return 69
  }

  architectures="$(lipo -archs "${binary}")"
  case " ${architectures} " in
    *" arm64 "*) ;;
    *)
      echo "${label} is missing the required arm64 slice: ${architectures}" >&2
      return 65
      ;;
  esac

  expected="$(headroom_normalize_macos_version "${HEADROOM_SUPPORTED_MACOS_MINIMUM}")"
  minimums="$(headroom_binary_macos_minimums "${binary}")"
  [[ -n "${minimums}" ]] || {
    echo "Could not read the macOS load-command minimum for ${label}: ${binary}" >&2
    return 65
  }

  while IFS= read -r minimum; do
    normalized="$(headroom_normalize_macos_version "${minimum}")" || {
      echo "Malformed macOS load-command minimum for ${label}: ${minimum}" >&2
      return 65
    }
    if [[ "${normalized}" != "${expected}" ]]; then
      echo "Unexpected macOS load-command minimum for ${label}: ${normalized} (expected ${expected})" >&2
      return 65
    fi
  done <<< "${minimums}"

  headroom_verify_no_back_deployed_date_comparisons "${binary}" "${label}"
}

# The macOS 27.2 SDK adds concrete `Date <=` and `>=` operators back-deployed behind a runtime
# "macOS >= 27.2" check. macOS 27.2 pre-release build 26B5086k passes that check but its
# Foundation does not export the symbols, so the weak import binds to null and the app
# segfaults on the first concrete `Date` `<=`/`>=` (Headroom 1.6 (44) crashed ~4s after launch).
# Write `!(a > b)` / `!(a < b)` for `Date` instead; this check keeps the symbols out of releases.
headroom_verify_no_back_deployed_date_comparisons() {
  local binary="$1"
  local label="$2"
  local imports

  command -v nm >/dev/null 2>&1 || {
    echo "nm is required to verify ${label}." >&2
    return 69
  }
  imports="$(nm -m "${binary}" 2>/dev/null \
    | grep -E 'external _\$s10Foundation4DateV2(le|ge)oiySbAC_ACtFZ' || true)"
  if [[ -n "${imports}" ]]; then
    echo "${label} imports back-deployed Foundation Date <= / >= operators, which crash on" >&2
    echo "macOS 27.2 pre-release builds. Use !(a > b) / !(a < b) for Date comparisons:" >&2
    echo "${imports}" >&2
    return 65
  fi
}

headroom_verify_macos_bundle() {
  local app="$1"
  local widget="$2"

  echo "→ verifying macOS ${HEADROOM_SUPPORTED_MACOS_MINIMUM}+ bundle compatibility"
  headroom_verify_plist_macos_minimum "${app}/Contents/Info.plist" "Headroom.app"
  headroom_verify_plist_macos_minimum "${widget}/Contents/Info.plist" "HeadroomWidgets.appex"
  headroom_verify_binary_compatibility "${app}/Contents/MacOS/Headroom" "Headroom.app"
  headroom_verify_binary_compatibility \
    "${widget}/Contents/MacOS/HeadroomWidgets" \
    "HeadroomWidgets.appex"
}

headroom_sparkle_minimum_from_app() {
  local app="$1"
  local minimum

  minimum="$(headroom_plist_macos_minimum "${app}/Contents/Info.plist")" || {
    echo "Cannot derive Sparkle minimum from ${app}." >&2
    return 65
  }
  headroom_normalize_macos_version "${minimum}"
}

headroom_appcast_item_for_build() {
  local appcast="$1"
  local build="$2"

  awk -v build="${build}" '
    /<item>/ { in_item = 1; item = "" }
    in_item { item = item $0 "\n" }
    /<\/item>/ && in_item {
      element = "<sparkle:version>" build "</sparkle:version>"
      attribute = "sparkle:version=\"" build "\""
      if (index(item, element) || index(item, attribute)) {
        printf "%s", item
        exit
      }
      in_item = 0
    }
  ' "${appcast}"
}

headroom_verify_appcast_minimum() {
  local appcast="$1"
  local app="$2"
  local build="$3"
  local item
  local actual
  local expected

  [[ -f "${appcast}" ]] || {
    echo "Missing Sparkle appcast: ${appcast}" >&2
    return 65
  }
  item="$(headroom_appcast_item_for_build "${appcast}" "${build}")"
  [[ -n "${item}" ]] || {
    echo "Sparkle appcast has no item for build ${build}: ${appcast}" >&2
    return 65
  }

  actual="$(printf '%s\n' "${item}" | sed -n 's@.*<sparkle:minimumSystemVersion>\([^<]*\)</sparkle:minimumSystemVersion>.*@\1@p' | head -n 1)"
  [[ -n "${actual}" ]] || {
    echo "Sparkle item ${build} has no minimumSystemVersion: ${appcast}" >&2
    return 65
  }
  actual="$(headroom_normalize_macos_version "${actual}")" || {
    echo "Sparkle item ${build} has a malformed minimumSystemVersion: ${appcast}" >&2
    return 65
  }
  expected="$(headroom_sparkle_minimum_from_app "${app}")"

  if [[ "${actual}" != "${expected}" ]]; then
    echo "Sparkle item ${build} requires ${actual}; exported app requires ${expected}." >&2
    return 65
  fi
  echo "→ verified Sparkle build ${build} supports macOS ${expected}+"
}
