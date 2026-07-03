#!/bin/bash
# Build Headroom.app as a real macOS app with an embedded WidgetKit extension.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG_INPUT="${1:-release}"
case "${CONFIG_INPUT}" in
  debug|Debug) XCODE_CONFIG="Debug" ;;
  release|Release) XCODE_CONFIG="Release" ;;
  *)
    echo "Usage: $0 [debug|release]" >&2
    exit 64
    ;;
esac

APP="Headroom.app"
DERIVED_DATA=".xcode-derived"
BUILT_APP="${DERIVED_DATA}/Build/Products/${XCODE_CONFIG}/Headroom.app"
WIDGET_APPEX="${APP}/Contents/PlugIns/HeadroomWidgets.appex"
HEADROOM_CODESIGN_IDENTITY="${HEADROOM_CODESIGN_IDENTITY:-}"

select_codesign_identity() {
  if [[ -n "${HEADROOM_CODESIGN_IDENTITY}" ]]; then
    printf '%s\n' "${HEADROOM_CODESIGN_IDENTITY}"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  local identity
  identity="$(printf '%s\n' "${identities}" | sed -n 's/^.*"\(Apple Development:[^"]*\)".*$/\1/p' | head -n 1)"
  if [[ -z "${identity}" ]]; then
    identity="$(printf '%s\n' "${identities}" | sed -n 's/^.*"\(Developer ID Application:[^"]*\)".*$/\1/p' | head -n 1)"
  fi

  printf '%s\n' "${identity:--}"
}

sign_path() {
  local path="$1"
  shift
  codesign --force --timestamp=none --sign "${CODESIGN_IDENTITY}" "$@" "${path}"
}

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build the WidgetKit-discoverable app bundle." >&2
  echo "Install with: brew install xcodegen" >&2
  exit 69
fi

CODESIGN_IDENTITY="$(select_codesign_identity)"

echo "→ xcodegen generate"
xcodegen generate

echo "→ xcodebuild Headroom (${XCODE_CONFIG}, unsigned product)"
xcodebuild \
  -project Headroom.xcodeproj \
  -scheme Headroom \
  -configuration "${XCODE_CONFIG}" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "→ assembling ${APP}"
rm -rf "${APP}"
ditto "${BUILT_APP}" "${APP}"

# Interrupted codesign runs can leave temporary files inside the bundle. Remove them
# before sealing, or codesign treats the temp file as a malformed nested component.
find "${APP}" -name '*.cstemp' -delete

if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "→ codesign ad-hoc (set HEADROOM_CODESIGN_IDENTITY to use an Apple certificate)"
else
  echo "→ codesign with ${CODESIGN_IDENTITY}"
fi

while IFS= read -r dylib; do
  sign_path "${dylib}"
done < <(find "${APP}" -type f -name '*.dylib')

sign_path "${WIDGET_APPEX}" --entitlements Sources/HeadroomWidgets/HeadroomWidgets.entitlements
sign_path "${APP}" --entitlements Sources/HeadroomApp/HeadroomApp.entitlements
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "✓ Built ${APP}"
echo "  Launch:  open ${APP}    (look for the vessel icon in the menu bar)"
echo "  Quit:    click the icon → Quit"
