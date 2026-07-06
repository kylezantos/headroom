#!/bin/bash
# Build, Developer ID sign, notarize, staple, and package Headroom for website distribution.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Headroom.app"
WIDGET_APPEX="${APP}/Contents/PlugIns/HeadroomWidgets.appex"
DMG_BACKGROUND_1X="Assets/Release/dmg-background.png"
DMG_BACKGROUND_2X="Assets/Release/dmg-background@2x.png"
DIST_DIR="dist"
WORK_DIR="${DIST_DIR}/release-work"
APP_ZIP="${WORK_DIR}/Headroom-app-notary.zip"
ARCHIVE_PATH="${WORK_DIR}/Headroom.xcarchive"
EXPORT_DIR="${WORK_DIR}/export"
EXPORT_OPTIONS_PLIST="${WORK_DIR}/ExportOptions-DeveloperID.plist"
DEFAULT_SPARKLE_UPDATES_DIR="${DIST_DIR}/headroom.zantos.co"
LATEST_DMG_NAME="Headroom.dmg"
SPARKLE_VERSION="2.9.4"
SPARKLE_ARTIFACT_ZIP=".xcode-derived/SourcePackages/artifacts/sparkle/Sparkle-for-Swift-Package-Manager.zip"
SPARKLE_ARTIFACT_DIR=".xcode-derived/SourcePackages/artifacts/sparkle/Sparkle"
SPARKLE_ARTIFACT_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"
HEADROOM_DEVELOPER_ID_APPLICATION="${HEADROOM_DEVELOPER_ID_APPLICATION:-}"
HEADROOM_NOTARY_PROFILE="${HEADROOM_NOTARY_PROFILE:-}"
HEADROOM_APPLE_ID="${HEADROOM_APPLE_ID:-}"
HEADROOM_TEAM_ID="${HEADROOM_TEAM_ID:-}"
HEADROOM_APP_SPECIFIC_PASSWORD="${HEADROOM_APP_SPECIFIC_PASSWORD:-}"
HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER:-}"
HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL:-https://headroom.zantos.co/appcast.xml}"
HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY:-VkSwNYbBn5WJUbqYFyhewIFZt4DIfCwiWmTNiGGDorM=}"
HEADROOM_SPARKLE_UPDATES_DIR="${HEADROOM_SPARKLE_UPDATES_DIR:-${DEFAULT_SPARKLE_UPDATES_DIR}}"
HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX="${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
HEADROOM_RELEASE_BUILD_ONLY="${HEADROOM_RELEASE_BUILD_ONLY:-0}"
XCODE_DERIVED_DATA="${XCODE_DERIVED_DATA:-.xcode-derived-release}"

usage() {
  cat >&2 <<'EOF'
Usage: ./Scripts/release-app.sh

Required:
  - A Developer ID Application certificate installed in Keychain.
  - Notary credentials, provided either as:
      HEADROOM_NOTARY_PROFILE=<keychain-profile>
    or:
      HEADROOM_APPLE_ID=<apple-id>
      HEADROOM_TEAM_ID=<team-id>
      HEADROOM_APP_SPECIFIC_PASSWORD=<app-specific-password>

Optional:
  HEADROOM_DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
  HEADROOM_APP_GROUP_IDENTIFIER="group.com.kylezantos.headroom"
  HEADROOM_SPARKLE_UPDATES_DIR="dist/headroom.zantos.co"
  HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX="https://headroom.zantos.co/"
  HEADROOM_RELEASE_BUILD_ONLY=1

Defaults for public releases with in-app update prompts:
  HEADROOM_SPARKLE_FEED_URL="https://headroom.zantos.co/appcast.xml"
  HEADROOM_SPARKLE_PUBLIC_ED_KEY="<base64-public-key-from-Sparkle-generate_keys>"

One-time notary profile setup:
  xcrun notarytool store-credentials headroom-notary \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "<app-specific-password>"

Then:
  HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh
EOF
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 69
  fi
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

find_sparkle_tool() {
  local tool="$1"
  local candidate
  candidate="$(find .xcode-derived/SourcePackages "${XCODE_DERIVED_DATA}/SourcePackages" .build -path "*/bin/${tool}" -type f 2>/dev/null | head -n 1 || true)"
  if [[ -z "${candidate}" ]]; then
    echo "Missing Sparkle tool: ${tool}" >&2
    echo "Build once so SwiftPM resolves Sparkle, then rerun this script." >&2
    exit 69
  fi
  printf '%s\n' "${candidate}"
}

detach_dmg_mount() {
  hdiutil detach "${DMG_MOUNT_DIR}" -force >/dev/null 2>&1 || true
}

create_drag_install_dmg() {
  rm -f "${DMG_RW_PATH}" "${DMG_PATH}"
  rm -rf "${DMG_MOUNT_DIR}"
  mkdir -p "${DMG_MOUNT_DIR}"

  echo "→ staging installer window background"
  local background_ready=0
  if [[ -f "${DMG_BACKGROUND_1X}" ]]; then
    mkdir -p "${STAGING_DIR}/.background"
    if [[ -f "${DMG_BACKGROUND_2X}" ]] && command -v tiffutil >/dev/null 2>&1; then
      # Combine @1x + @2x into one HiDPI TIFF so Retina Finder renders it crisp.
      tiffutil -cathidpicheck "${DMG_BACKGROUND_1X}" "${DMG_BACKGROUND_2X}" \
        -out "${STAGING_DIR}/.background/background.tiff" >/dev/null
    else
      cp "${DMG_BACKGROUND_1X}" "${STAGING_DIR}/.background/background.tiff"
    fi
    background_ready=1
  else
    echo "  ! ${DMG_BACKGROUND_1X} not found — building without a custom background" >&2
  fi

  echo "→ creating writable installer image"
  hdiutil create \
    -volname "Headroom" \
    -srcfolder "${STAGING_DIR}" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "${DMG_RW_PATH}" >/dev/null

  echo "→ styling DMG install window"
  hdiutil attach "${DMG_RW_PATH}" \
    -mountpoint "${DMG_MOUNT_DIR}" \
    -readwrite \
    -noverify \
    -nobrowse >/dev/null
  trap detach_dmg_mount RETURN

  # Give the mounted volume the Headroom app icon (optional polish; never fatal).
  if [[ -f "${APP}/Contents/Resources/AppIcon.icns" ]] && command -v SetFile >/dev/null 2>&1; then
    cp "${APP}/Contents/Resources/AppIcon.icns" "${DMG_MOUNT_DIR}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "${DMG_MOUNT_DIR}" 2>/dev/null || true
  fi

  osascript - "$(cd "${DMG_MOUNT_DIR}" && pwd)" "${background_ready}" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  set backgroundReady to item 2 of argv
  tell application "Finder"
    set dmgFolder to POSIX file mountPath as alias
    open dmgFolder
    delay 1

    set current view of container window of dmgFolder to icon view
    set toolbar visible of container window of dmgFolder to false
    set statusbar visible of container window of dmgFolder to false
    -- 680 x 440 background bitmap + 28px title bar = 468 tall
    set bounds of container window of dmgFolder to {180, 120, 860, 588}

    set viewOptions to icon view options of container window of dmgFolder
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13

    if backgroundReady is "1" then
      set background picture of viewOptions to (POSIX file (mountPath & "/.background/background.tiff") as alias)
    end if

    set position of item "Headroom.app" of dmgFolder to {196, 240}
    set position of item "Applications" of dmgFolder to {484, 240}

    update dmgFolder without registering applications
    delay 1
    close container window of dmgFolder
  end tell
end run
APPLESCRIPT

  sync
  detach_dmg_mount
  trap - RETURN

  echo "→ compressing installer image"
  hdiutil convert "${DMG_RW_PATH}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_PATH}" >/dev/null
  rm -f "${DMG_RW_PATH}"
}

set_plist_string() {
  local plist="$1"
  local key="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "${plist}"
}

set_plist_bool() {
  local plist="$1"
  local key="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${plist}" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${key} bool ${value}" "${plist}"
}

stamp_exported_info() {
  local app_info="${APP}/Contents/Info.plist"
  local widget_info="${WIDGET_APPEX}/Contents/Info.plist"

  echo "→ stamping release Info.plist values"
  set_plist_string "${app_info}" HeadroomAppGroupIdentifier "${HEADROOM_APP_GROUP_IDENTIFIER}"
  set_plist_string "${widget_info}" HeadroomAppGroupIdentifier "${HEADROOM_APP_GROUP_IDENTIFIER}"
  set_plist_string "${app_info}" SUFeedURL "${HEADROOM_SPARKLE_FEED_URL}"
  set_plist_string "${app_info}" SUPublicEDKey "${HEADROOM_SPARKLE_PUBLIC_ED_KEY}"
  set_plist_bool "${app_info}" SUEnableAutomaticChecks true
  set_plist_bool "${app_info}" SUAllowsAutomaticUpdates false
}

resign_exported_info_mutations() {
  echo "→ re-signing exported app after Info.plist stamping"
  codesign \
    --force \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    --timestamp \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    "${WIDGET_APPEX}"
  codesign \
    --force \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    --timestamp \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    "${APP}"
}

verify_profile_kind() {
  local profile="$1"
  local profile_name

  if [[ ! -f "${profile}" ]]; then
    echo "Missing embedded provisioning profile: ${profile}" >&2
    exit 65
  fi

  profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin <<< "$(security cms -D -i "${profile}")")"
  case "${profile_name}" in
    "Mac Team Direct Provisioning Profile:"*) ;;
    *)
      echo "Expected a Mac Team Direct provisioning profile, got: ${profile_name}" >&2
      exit 65
      ;;
  esac
}

verify_release_entitlements() {
  local entitlements="${WORK_DIR}/Headroom.entitlements.plist"
  local expected_application_identifier="${DEVELOPER_ID_TEAM_ID}.com.kylezantos.headroom"
  local expected_kvs_identifier="${DEVELOPER_ID_TEAM_ID}.com.kylezantos.headroom"

  echo "→ verifying release entitlements"
  codesign -d --entitlements :- "${APP}" > "${entitlements}" 2>/dev/null

  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "${entitlements}")" == "${expected_application_identifier}" ]] || {
    echo "Unexpected application identifier in signed app." >&2
    exit 65
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "${entitlements}")" == "${DEVELOPER_ID_TEAM_ID}" ]] || {
    echo "Unexpected developer team identifier in signed app." >&2
    exit 65
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.ubiquity-kvstore-identifier' "${entitlements}")" == "${expected_kvs_identifier}" ]] || {
    echo "Missing or unexpected iCloud KVS entitlement in signed app." >&2
    exit 65
  }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "${entitlements}")" == "${HEADROOM_APP_GROUP_IDENTIFIER}" ]] || {
    echo "Missing or unexpected App Group entitlement in signed app." >&2
    exit 65
  }

  verify_profile_kind "${APP}/Contents/embedded.provisionprofile"
  verify_profile_kind "${WIDGET_APPEX}/Contents/embedded.provisionprofile"
}

write_minimal_appcast() {
  local appcast_path="${HEADROOM_SPARKLE_UPDATES_DIR}/appcast.xml"
  local signature_line
  local ed_signature
  local archive_length
  local download_url="${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}${DMG_NAME}"
  local pub_date

  signature_line="$(cat "${DMG_PATH}.sparkle-signature.txt")"
  ed_signature="$(printf '%s\n' "${signature_line}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  archive_length="$(printf '%s\n' "${signature_line}" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
  pub_date="$(LC_ALL=C date -R)"

  if [[ -z "${ed_signature}" || -z "${archive_length}" ]]; then
    echo "Could not parse Sparkle signature metadata from ${DMG_PATH}.sparkle-signature.txt" >&2
    exit 65
  fi

  cat > "${appcast_path}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Headroom Updates</title>
    <link>${HEADROOM_SPARKLE_FEED_URL}</link>
    <description>Headroom release feed</description>
    <item>
      <title>Headroom ${VERSION}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="${download_url}" sparkle:edSignature="${ed_signature}" length="${archive_length}" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
}

run_generate_appcast_with_timeout() {
  local pid
  local elapsed=0
  local timeout_seconds=120

  "${SPARKLE_GENERATE_APPCAST}" \
    --download-url-prefix "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}" \
    "${HEADROOM_SPARKLE_UPDATES_DIR}" &
  pid="$!"

  while kill -0 "${pid}" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
      kill -TERM "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  wait "${pid}"
}

write_export_options_plist() {
  cat > "${EXPORT_OPTIONS_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${DEVELOPER_ID_TEAM_ID}</string>
</dict>
</plist>
EOF
}

archive_and_export_developer_id_app() {
  rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"
  mkdir -p "${WORK_DIR}"
  write_export_options_plist

  echo "→ xcodegen generate"
  xcodegen generate

  echo "→ archiving app for Developer ID export"
  xcodebuild \
    -project Headroom.xcodeproj \
    -scheme Headroom \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${XCODE_DERIVED_DATA}" \
    -allowProvisioningUpdates \
    HEADROOM_APP_GROUP_IDENTIFIER="${HEADROOM_APP_GROUP_IDENTIFIER}" \
    HEADROOM_SPARKLE_FEED_URL="${HEADROOM_SPARKLE_FEED_URL}" \
    HEADROOM_SPARKLE_PUBLIC_ED_KEY="${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${DEVELOPER_ID_TEAM_ID}" \
    ENABLE_HARDENED_RUNTIME=YES \
    archive

  echo "→ exporting Developer ID signed app"
  xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    -allowProvisioningUpdates

  rm -rf "${APP}"
  ditto "${EXPORT_DIR}/${APP}" "${APP}"
  stamp_exported_info
  resign_exported_info_mutations
}

select_developer_id_application() {
  if [[ -n "${HEADROOM_DEVELOPER_ID_APPLICATION}" ]]; then
    printf '%s\n' "${HEADROOM_DEVELOPER_ID_APPLICATION}"
    return
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^.*"\(Developer ID Application:[^"]*\)".*$/\1/p' \
    | head -n 1
}

for tool in security codesign curl ditto hdiutil xcrun plutil; do
  require_tool "${tool}"
done
require_tool xcodegen

DEVELOPER_ID_APPLICATION="$(select_developer_id_application)"
if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
  echo "No Developer ID Application identity found in Keychain." >&2
  echo "Install one from your Apple Developer account, then rerun this script." >&2
  exit 65
fi

DEVELOPER_ID_TEAM_ID="$(printf '%s\n' "${DEVELOPER_ID_APPLICATION}" | sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\))$/\1/p')"
if [[ -z "${DEVELOPER_ID_TEAM_ID}" ]]; then
  echo "Couldn't derive Team ID from Developer ID Application identity:" >&2
  echo "  ${DEVELOPER_ID_APPLICATION}" >&2
  echo "Set HEADROOM_APP_GROUP_IDENTIFIER explicitly and rerun." >&2
  exit 65
fi
if [[ -z "${HEADROOM_APP_GROUP_IDENTIFIER}" ]]; then
  HEADROOM_APP_GROUP_IDENTIFIER="group.com.kylezantos.headroom"
fi
if [[ -z "${HEADROOM_SPARKLE_FEED_URL}" || -z "${HEADROOM_SPARKLE_PUBLIC_ED_KEY}" ]]; then
  echo "Sparkle release configuration is required before building a public DMG." >&2
  echo "Set HEADROOM_SPARKLE_FEED_URL, then rerun." >&2
  exit 64
fi
if [[ -z "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}" ]]; then
  HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX="${HEADROOM_SPARKLE_FEED_URL%/*}/"
fi

notary_args=()
if [[ "${HEADROOM_RELEASE_BUILD_ONLY}" == "1" ]]; then
  notary_args=()
elif [[ -n "${HEADROOM_NOTARY_PROFILE}" ]]; then
  notary_args=(--keychain-profile "${HEADROOM_NOTARY_PROFILE}")
elif [[ -n "${HEADROOM_APPLE_ID}" && -n "${HEADROOM_TEAM_ID}" && -n "${HEADROOM_APP_SPECIFIC_PASSWORD}" ]]; then
  notary_args=(
    --apple-id "${HEADROOM_APPLE_ID}"
    --team-id "${HEADROOM_TEAM_ID}"
    --password "${HEADROOM_APP_SPECIFIC_PASSWORD}"
  )
else
  usage
  exit 64
fi

echo "→ building Developer ID signed app"
prepare_sparkle_artifact
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${DIST_DIR}"
archive_and_export_developer_id_app

echo "→ verifying signed app bundle"
codesign --verify --deep --strict --verbose=2 "${APP}"
verify_release_entitlements

if [[ "${HEADROOM_RELEASE_BUILD_ONLY}" == "1" ]]; then
  echo "✓ Developer ID app ready: ${APP}"
  exit 0
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
DMG_NAME="Headroom-${VERSION}-${BUILD}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DMG_RW_PATH="${WORK_DIR}/Headroom-${VERSION}-${BUILD}-rw.dmg"
DMG_MOUNT_DIR="${WORK_DIR}/dmg-mount"
STAGING_DIR="${WORK_DIR}/dmg-root"

mkdir -p "${WORK_DIR}" "${STAGING_DIR}" "${DIST_DIR}"

echo "→ creating app notarization archive"
ditto -c -k --keepParent "${APP}" "${APP_ZIP}"

echo "→ notarizing app bundle archive"
xcrun notarytool submit "${APP_ZIP}" "${notary_args[@]}" --wait

echo "→ stapling app bundle"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
spctl -a -vvv -t open --context context:primary-signature "${APP}"

echo "→ assembling DMG"
ditto "${APP}" "${STAGING_DIR}/${APP}"
ln -s /Applications "${STAGING_DIR}/Applications"
create_drag_install_dmg

echo "→ signing DMG"
codesign --force --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${DMG_PATH}"
codesign --verify --verbose=2 "${DMG_PATH}"

echo "→ notarizing DMG"
xcrun notarytool submit "${DMG_PATH}" "${notary_args[@]}" --wait

echo "→ stapling DMG"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
spctl -a -vvv -t open --context context:primary-signature "${DMG_PATH}"

echo "→ signing Sparkle update archive"
SPARKLE_SIGN_UPDATE="$(find_sparkle_tool sign_update)"
"${SPARKLE_SIGN_UPDATE}" "${DMG_PATH}" > "${DMG_PATH}.sparkle-signature.txt"

if [[ -n "${HEADROOM_SPARKLE_UPDATES_DIR}" ]]; then
  echo "→ updating Sparkle appcast"
  SPARKLE_GENERATE_APPCAST="$(find_sparkle_tool generate_appcast)"
  LATEST_DMG_PATH="${HEADROOM_SPARKLE_UPDATES_DIR}/${LATEST_DMG_NAME}"
  mkdir -p "${HEADROOM_SPARKLE_UPDATES_DIR}"
  rm -f "${LATEST_DMG_PATH}"
  ditto "${DMG_PATH}" "${HEADROOM_SPARKLE_UPDATES_DIR}/${DMG_NAME}"
  if ! run_generate_appcast_with_timeout; then
    echo "→ Sparkle generate_appcast timed out; writing minimal signed appcast"
    write_minimal_appcast
  fi
  ditto "${DMG_PATH}" "${LATEST_DMG_PATH}"
fi

echo "✓ Release artifact ready: ${DMG_PATH}"
echo "  Website assets: ${HEADROOM_SPARKLE_UPDATES_DIR}"
echo "  Download link: https://headroom.zantos.co/${LATEST_DMG_NAME}"
echo "  Sparkle signature: ${DMG_PATH}.sparkle-signature.txt"
