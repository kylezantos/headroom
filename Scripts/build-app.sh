#!/bin/bash
# Build Headroom.app as a real macOS app with an embedded WidgetKit extension.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/macos-compatibility.sh
source Scripts/codesign-identity.sh

CONFIG_INPUT="${1:-release}"
# `--deps-only` prepares the vendored dependencies the Xcode project expects on disk
# and stops there. `-resolvePackageDependencies` does not unpack the Sparkle
# XCFramework, so a fresh checkout can't build the HeadroomAppTests scheme until this
# has run once.
DEPS_ONLY=0
case "${CONFIG_INPUT}" in
  --deps-only|prepare-deps) DEPS_ONLY=1; XCODE_CONFIG="Release" ;;
  debug|Debug) XCODE_CONFIG="Debug" ;;
  release|Release) XCODE_CONFIG="Release" ;;
  *)
    echo "Usage: $0 [debug|release|--deps-only]" >&2
    exit 64
    ;;
esac

APP="Headroom.app"
DERIVED_DATA=".xcode-derived"
BUILT_APP="${DERIVED_DATA}/Build/Products/${XCODE_CONFIG}/Headroom.app"
WIDGET_APPEX="${APP}/Contents/PlugIns/HeadroomWidgets.appex"
SIGNING_DIR="${DERIVED_DATA}/Signing"
APP_ENTITLEMENTS="${SIGNING_DIR}/HeadroomApp.entitlements"
WIDGET_ENTITLEMENTS="${SIGNING_DIR}/HeadroomWidgets.entitlements"
SPARKLE_VERSION="2.9.4"
SPARKLE_ARTIFACT_ZIP="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle-for-Swift-Package-Manager.zip"
SPARKLE_ARTIFACT_DIR="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle"
SPARKLE_ARTIFACT_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
HEADROOM_CODESIGN_IDENTITY="${HEADROOM_CODESIGN_IDENTITY:-}"
HEADROOM_CODESIGN_OPTIONS="${HEADROOM_CODESIGN_OPTIONS:---timestamp=none}"
HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER:-group.com.kylezantos.headroom}"
HEADROOM_ENABLE_ICLOUD_ENTITLEMENT="${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT:-0}"
HEADROOM_TEAM_IDENTIFIER="${HEADROOM_TEAM_IDENTIFIER:-}"
# Paths to the separate macOS provisioning profiles for the host and widget
# bundle IDs. REQUIRED alongside HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1: restricted
# entitlements must be authorized for each executable independently. Reusing the
# host profile for the widget makes WidgetKit registration succeed but amfid
# rejects the extension at launch with "No matching profile found".
HEADROOM_PROVISIONING_PROFILE="${HEADROOM_PROVISIONING_PROFILE:-}"
HEADROOM_WIDGET_PROVISIONING_PROFILE="${HEADROOM_WIDGET_PROVISIONING_PROFILE:-}"
HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL:-}"
HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY:-VkSwNYbBn5WJUbqYFyhewIFZt4DIfCwiWmTNiGGDorM=}"
read -r -a CODESIGN_OPTIONS <<< "${HEADROOM_CODESIGN_OPTIONS}"

select_codesign_identity() {
  if [[ -n "${HEADROOM_CODESIGN_IDENTITY}" ]]; then
    # A name may match a renewed certificate too; sign with the newest one's SHA-1.
    local resolved=""
    if [[ "${HEADROOM_CODESIGN_IDENTITY}" != "-" && ! "${HEADROOM_CODESIGN_IDENTITY}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
      resolved="$(headroom_newest_identity_sha "${HEADROOM_CODESIGN_IDENTITY}")"
    fi
    printf '%s\n' "${resolved:-${HEADROOM_CODESIGN_IDENTITY}}"
    return
  fi

  local identity
  identity="$(headroom_newest_identity_sha "Apple Development:")"
  if [[ -z "${identity}" ]]; then
    identity="$(headroom_newest_identity_sha "Developer ID Application:")"
  fi

  printf '%s\n' "${identity:--}"
}

sign_path() {
  local path="$1"
  shift
  codesign --force --sign "${CODESIGN_IDENTITY}" "${CODESIGN_OPTIONS[@]}" "$@" "${path}"
}

derive_team_identifier() {
  if [[ -n "${HEADROOM_TEAM_IDENTIFIER}" ]]; then
    printf '%s\n' "${HEADROOM_TEAM_IDENTIFIER}"
    return
  fi

  if [[ "${CODESIGN_IDENTITY}" != "-" ]] && command -v openssl >/dev/null 2>&1; then
    local subject
    subject="$(security find-certificate -c "${CODESIGN_IDENTITY_NAME}" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null \
      | head -n 1 || true)"
    local team
    team="$(printf '%s\n' "${subject}" | sed -n 's/.*OU=\([^,\/]*\).*/\1/p')"
    if [[ -n "${team}" ]]; then
      printf '%s\n' "${team}"
      return
    fi
  fi

  sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*\([^[:space:]]*\).*$/\1/p' project.yml | head -n 1
}

prepare_sparkle_artifact() {
  if [[ -d "${SPARKLE_ARTIFACT_DIR}/Sparkle.xcframework" ]]; then
    return
  fi

  echo "→ fetching Sparkle ${SPARKLE_VERSION}"
  mkdir -p "$(dirname "${SPARKLE_ARTIFACT_ZIP}")" "${SPARKLE_ARTIFACT_DIR}"
  curl -L --fail --show-error --silent \
    -o "${SPARKLE_ARTIFACT_ZIP}" \
    "${SPARKLE_ARTIFACT_URL}"
  ditto -x -k "${SPARKLE_ARTIFACT_ZIP}" "${SPARKLE_ARTIFACT_DIR}"
}

prepare_entitlements() {
  mkdir -p "${SIGNING_DIR}"
  cp Sources/HeadroomApp/HeadroomApp.entitlements "${APP_ENTITLEMENTS}"
  cp Sources/HeadroomWidgets/HeadroomWidgets.entitlements "${WIDGET_ENTITLEMENTS}"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${HEADROOM_APP_GROUP_IDENTIFIER}" "${APP_ENTITLEMENTS}"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${HEADROOM_APP_GROUP_IDENTIFIER}" "${WIDGET_ENTITLEMENTS}"

  if [[ "${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT}" == "1" ]]; then
    local team_identifier
    team_identifier="$(derive_team_identifier)"
    if [[ -z "${team_identifier}" ]]; then
      echo "Couldn't derive a Team ID for the iCloud KVS entitlement." >&2
      echo "Set HEADROOM_TEAM_IDENTIFIER and rerun." >&2
      exit 65
    fi
    /usr/libexec/PlistBuddy -c "Set :com.apple.developer.ubiquity-kvstore-identifier ${team_identifier}.com.kylezantos.headroom" "${APP_ENTITLEMENTS}"
    /usr/libexec/PlistBuddy -c "Set :com.apple.developer.ubiquity-kvstore-identifier ${team_identifier}.com.kylezantos.headroom" "${WIDGET_ENTITLEMENTS}"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${team_identifier}.com.kylezantos.headroom" "${APP_ENTITLEMENTS}"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${team_identifier}.com.kylezantos.headroom.widgets" "${WIDGET_ENTITLEMENTS}"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${team_identifier}" "${APP_ENTITLEMENTS}"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${team_identifier}" "${WIDGET_ENTITLEMENTS}"
  else
    # Delete BOTH restricted iCloud keys. `icloud-container-identifiers` counts as a
    # restricted entitlement even as an empty array — leaving it in an ad-hoc
    # signature gets the app SIGKILLed at spawn (exit 137) just like the KVS key.
    for key in \
      "com.apple.developer.ubiquity-kvstore-identifier" \
      "com.apple.developer.icloud-container-identifiers"
    do
      /usr/libexec/PlistBuddy -c "Delete :${key}" "${APP_ENTITLEMENTS}" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Delete :${key}" "${WIDGET_ENTITLEMENTS}" 2>/dev/null || true
    done
  fi
}

stamp_app_group_info() {
  for plist in \
    "${APP}/Contents/Info.plist" \
    "${WIDGET_APPEX}/Contents/Info.plist"
  do
    /usr/libexec/PlistBuddy -c "Set :HeadroomAppGroupIdentifier ${HEADROOM_APP_GROUP_IDENTIFIER}" "${plist}" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :HeadroomAppGroupIdentifier string ${HEADROOM_APP_GROUP_IDENTIFIER}" "${plist}"
  done
}

stamp_sparkle_info() {
  local plist="${APP}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL ${HEADROOM_SPARKLE_FEED_URL}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${HEADROOM_SPARKLE_FEED_URL}" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks true" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "${plist}"
  /usr/libexec/PlistBuddy -c "Set :SUAllowsAutomaticUpdates false" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUAllowsAutomaticUpdates bool false" "${plist}"
}

profile_value() {
  local profile="$1"
  local key="$2"
  local decoded
  decoded="$(security cms -D -i "${profile}" 2>/dev/null)" || return 1
  /usr/libexec/PlistBuddy -c "Print :${key}" /dev/stdin <<< "${decoded}" 2>/dev/null
}

validate_provisioning_profile() {
  local variable_name="$1"
  local profile="$2"
  local expected_bundle_identifier="$3"
  local team_identifier="$4"
  local expected_application_identifier="${team_identifier}.${expected_bundle_identifier}"

  if [[ -z "${profile}" ]]; then
    echo "${variable_name} is required when HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1." >&2
    exit 66
  fi
  if [[ ! -f "${profile}" ]]; then
    echo "${variable_name} not found: ${profile}" >&2
    exit 66
  fi

  local application_identifier
  application_identifier="$(profile_value "${profile}" "Entitlements:com.apple.application-identifier")" || {
    echo "Couldn't decode ${variable_name}: ${profile}" >&2
    exit 66
  }
  if [[ "${application_identifier}" != "${expected_application_identifier}" ]]; then
    echo "${variable_name} authorizes ${application_identifier}, expected ${expected_application_identifier}." >&2
    exit 66
  fi

  local profile_name
  profile_name="$(profile_value "${profile}" "Name")" || {
    echo "Couldn't read the name from ${variable_name}: ${profile}" >&2
    exit 66
  }
  case "${CODESIGN_IDENTITY_NAME}" in
    "Apple Development:"*)
      if [[ "${profile_name}" != "Mac Team Provisioning Profile:"* ]]; then
        echo "${variable_name} is not an Apple Development profile: ${profile_name}" >&2
        exit 66
      fi
      ;;
    "Developer ID Application:"*)
      if [[ "${profile_name}" != "Mac Team Direct Provisioning Profile:"* ]]; then
        echo "${variable_name} is not a Developer ID profile: ${profile_name}" >&2
        exit 66
      fi
      ;;
  esac
}

validate_provisioning_profiles() {
  if [[ "${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT}" != "1" ]]; then
    return
  fi

  local team_identifier
  team_identifier="$(derive_team_identifier)"
  validate_provisioning_profile \
    "HEADROOM_PROVISIONING_PROFILE" \
    "${HEADROOM_PROVISIONING_PROFILE}" \
    "com.kylezantos.headroom" \
    "${team_identifier}"
  validate_provisioning_profile \
    "HEADROOM_WIDGET_PROVISIONING_PROFILE" \
    "${HEADROOM_WIDGET_PROVISIONING_PROFILE}" \
    "com.kylezantos.headroom.widgets" \
    "${team_identifier}"
}

embed_provisioning_profiles() {
  # Only relevant when the restricted iCloud KVS entitlement is on. A local
  # codesign cannot grant it; both executables need their matching profile.
  if [[ "${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT}" != "1" ]]; then
    return
  fi

  echo "→ embedding host provisioning profile: ${HEADROOM_PROVISIONING_PROFILE}"
  cp "${HEADROOM_PROVISIONING_PROFILE}" "${APP}/Contents/embedded.provisionprofile"
  echo "→ embedding widget provisioning profile: ${HEADROOM_WIDGET_PROVISIONING_PROFILE}"
  cp "${HEADROOM_WIDGET_PROVISIONING_PROFILE}" "${WIDGET_APPEX}/Contents/embedded.provisionprofile"
}

verify_signed_identifier() {
  local signed_path="$1"
  local expected_application_identifier="$2"
  local entitlements_path="$3"

  codesign -d --entitlements :- "${signed_path}" > "${entitlements_path}" 2>/dev/null
  local application_identifier
  application_identifier="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "${entitlements_path}" 2>/dev/null || true)"
  if [[ "${application_identifier}" != "${expected_application_identifier}" ]]; then
    echo "Unexpected signed application identifier for ${signed_path}: ${application_identifier:-missing}" >&2
    exit 67
  fi
}

if [[ "${DEPS_ONLY}" == "1" ]]; then
  prepare_sparkle_artifact
  echo "✓ Sparkle ${SPARKLE_VERSION} ready at ${SPARKLE_ARTIFACT_DIR}/Sparkle.xcframework"
  echo "  Run tests with: xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests \\"
  echo "    -destination 'platform=macOS' -derivedDataPath ./${DERIVED_DATA} test"
  exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build the WidgetKit-discoverable app bundle." >&2
  echo "Install with: brew install xcodegen" >&2
  exit 69
fi

CODESIGN_IDENTITY="$(select_codesign_identity)"
CODESIGN_IDENTITY_NAME="${CODESIGN_IDENTITY}"
if [[ "${CODESIGN_IDENTITY}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  CODESIGN_IDENTITY_NAME="$(headroom_identity_name_for_sha "${CODESIGN_IDENTITY}")"
fi
if [[ "${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT}" == "1" && "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1 requires an Apple codesigning identity." >&2
  echo "Set HEADROOM_CODESIGN_IDENTITY to Apple Development or Developer ID Application." >&2
  exit 65
fi
validate_provisioning_profiles
prepare_sparkle_artifact

echo "→ xcodegen generate"
xcodegen generate

echo "→ xcodebuild Headroom (${XCODE_CONFIG}, unsigned product)"
xcodebuild \
  -project Headroom.xcodeproj \
  -scheme Headroom \
  -configuration "${XCODE_CONFIG}" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER}" \
  HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL}" \
  HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "→ assembling ${APP}"
if [[ -e "${APP}" ]]; then
  ARCHIVE_DIR="${DERIVED_DATA}/ArchivedApps"
  mkdir -p "${ARCHIVE_DIR}"
  ARCHIVED_APP="${ARCHIVE_DIR}/Headroom.app.$(date +%Y%m%d-%H%M%S)"
  echo "→ archiving existing ${APP} to ${ARCHIVED_APP}"
  mv "${APP}" "${ARCHIVED_APP}"
fi
ditto "${BUILT_APP}" "${APP}"
prepare_entitlements
stamp_app_group_info
stamp_sparkle_info
embed_provisioning_profiles
headroom_verify_macos_bundle "${APP}" "${WIDGET_APPEX}"

# Interrupted codesign runs can leave temporary files inside the bundle. Remove them
# before sealing, or codesign treats the temp file as a malformed nested component.
find "${APP}" -name '*.cstemp' -delete

if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "→ codesign ad-hoc (set HEADROOM_CODESIGN_IDENTITY to use an Apple certificate)"
else
  echo "→ codesign with ${CODESIGN_IDENTITY_NAME} (${CODESIGN_IDENTITY:0:8}…)"
fi
echo "→ codesign options: ${HEADROOM_CODESIGN_OPTIONS}"
echo "→ app group: ${HEADROOM_APP_GROUP_IDENTIFIER}"
echo "→ iCloud KVS entitlement: ${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT}"

while IFS= read -r dylib; do
  sign_path "${dylib}"
done < <(find "${APP}" -type f -name '*.dylib')

while IFS= read -r framework; do
  sign_path "${framework}" --deep
done < <(find "${APP}/Contents/Frameworks" -maxdepth 1 -type d -name '*.framework' 2>/dev/null)

sign_path "${WIDGET_APPEX}" --entitlements "${WIDGET_ENTITLEMENTS}"
sign_path "${APP}" --entitlements "${APP_ENTITLEMENTS}"
codesign --verify --deep --strict --verbose=2 "${APP}"

if [[ "${HEADROOM_ENABLE_ICLOUD_ENTITLEMENT}" == "1" ]]; then
  verify_signed_identifier \
    "${APP}" \
    "$(derive_team_identifier).com.kylezantos.headroom" \
    "${SIGNING_DIR}/SignedHeadroomApp.entitlements"
  verify_signed_identifier \
    "${WIDGET_APPEX}" \
    "$(derive_team_identifier).com.kylezantos.headroom.widgets" \
    "${SIGNING_DIR}/SignedHeadroomWidgets.entitlements"
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
  echo "→ registering ${APP} with LaunchServices"
  "${LSREGISTER}" -f -R -trusted "${APP}"
fi

echo "✓ Built ${APP}"
echo "  Launch:  open ${APP}    (look for the vessel icon in the menu bar)"
echo "  Quit:    click the icon → Quit"
