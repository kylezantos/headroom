#!/bin/bash
# Build, Developer ID sign, notarize, staple, and package Headroom for website distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/macos-compatibility.sh
source Scripts/sparkle-release-notes.sh
source Scripts/codesign-identity.sh

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
SPARKLE_RELEASE_NOTES_DIR="docs/release/sparkle"
LATEST_DMG_NAME="Headroom.dmg"
LATEST_JSON_NAME="latest.json"
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
  - Versioned release notes at docs/release/sparkle/Headroom-<version>-<build>.html.
  - Notary credentials, provided either as:
      HEADROOM_NOTARY_PROFILE=<keychain-profile>
    or:
      HEADROOM_APPLE_ID=<apple-id>
      HEADROOM_TEAM_ID=<team-id>
      HEADROOM_APP_SPECIFIC_PASSWORD=<app-specific-password>

Optional:
  HEADROOM_DEVELOPER_ID_APPLICATION=<SHA-1 or "Developer ID Application: Name (TEAMID)">
    (default: the Developer ID Application identity that expires last)
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

# Icon positions in the 680x440 install window; they sit either side of the background's arrow.
DMG_APP_POSITION="196,176"
DMG_APPLICATIONS_POSITION="484,176"
# Dot-files are parked past the window so someone showing hidden files (⌘⇧.) still sees
# only the two icons (a friend's 1.5 install window listed all three).
DMG_HIDDEN_ITEMS=(".background" ".VolumeIcon.icns")
DMG_HIDDEN_POSITION="1200,1200"

stage_dmg_volume_icon() {
  # The volume icon doubles as the window's title-bar proxy icon.
  if [[ -f "${APP}/Contents/Resources/AppIcon.icns" ]] && command -v SetFile >/dev/null 2>&1; then
    if cp "${APP}/Contents/Resources/AppIcon.icns" "${DMG_MOUNT_DIR}/.VolumeIcon.icns" \
        && SetFile -a C "${DMG_MOUNT_DIR}" \
        && SetFile -a V "${DMG_MOUNT_DIR}/.VolumeIcon.icns"; then
      echo "  ✓ volume icon staged (title-bar proxy icon)"
    else
      echo "  ! volume icon staging failed — DMG will show the generic disk icon" >&2
    fi
  else
    echo "  ! AppIcon.icns or SetFile unavailable — skipping volume icon" >&2
  fi
}

# Reads the .DS_Store Finder saved and checks every icon position.
verify_dmg_layout() {
  local volume="$1"
  if [[ ! -f "${volume}/.DS_Store" ]]; then
    echo "  ✗ DMG layout: Finder saved no .DS_Store" >&2
    return 1
  fi
  local hidden=() item
  for item in "${DMG_HIDDEN_ITEMS[@]}"; do
    if [[ -e "${volume}/${item}" ]]; then
      hidden+=("${item}")
    fi
  done
  python3 Scripts/dmg-layout-check.py "${volume}/.DS_Store" \
    "Headroom.app=${DMG_APP_POSITION}" \
    "Applications=${DMG_APPLICATIONS_POSITION}" \
    --offscreen ${hidden[@]+"${hidden[@]}"}
}

style_dmg_window() {
  osascript - "$(cd "${DMG_MOUNT_DIR}" && pwd)" "${DMG_APP_POSITION}" "${DMG_APPLICATIONS_POSITION}" \
    "${DMG_HIDDEN_POSITION}" "${DMG_HIDDEN_ITEMS[@]}" <<'APPLESCRIPT'
on xy(pair)
  set AppleScript's text item delimiters to ","
  set parts to text items of pair
  set AppleScript's text item delimiters to ""
  return {(item 1 of parts) as integer, (item 2 of parts) as integer}
end xy

on placeIcons(dmgFolder, argv)
  tell application "Finder"
    set position of item "Headroom.app" of dmgFolder to my xy(item 2 of argv)
    set position of item "Applications" of dmgFolder to my xy(item 3 of argv)
    repeat with i from 5 to count of argv
      try
        set position of item (item i of argv) of dmgFolder to my xy(item 4 of argv)
      end try
    end repeat
  end tell
end placeIcons

on run argv
  set mountPath to item 1 of argv
  tell application "Finder"
    activate
    set dmgFolder to POSIX file mountPath as alias
    set dmgWindow to make new Finder window to dmgFolder
    delay 1

    set current view of dmgWindow to icon view
    try
      set toolbar visible of dmgWindow to false
    end try
    try
      set statusbar visible of dmgWindow to false
    end try
    -- 680 x 440 content area + 28px title bar = 468 tall
    set bounds of dmgWindow to {180, 120, 860, 588}

    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set label position of viewOptions to bottom

    -- A custom Finder background is always treated as light appearance, so labels draw
    -- black even in Dark Mode. The dark background paints a gold chip under each label
    -- (dmg-background.html) so the black names stay legible and read as branding.
    set background picture of viewOptions to (POSIX file (mountPath & "/.background/background.tiff") as alias)
  end tell
  placeIcons(dmgFolder, argv)

  -- Tahoe Finder ignores the toolbar/statusbar AppleScript properties for DMG windows
  -- and instead shows a tab bar + path bar + status bar. Their View-menu toggles are the
  -- only working switch, and the hidden state persists into the DMG's .DS_Store (verified
  -- across remounts). Menu items read "Hide …" only when the bar is visible, so this is
  -- naturally idempotent. Needs Accessibility access for the calling terminal; tolerated
  -- (with a warning) when unavailable so CI-ish runs still produce a usable DMG.
  tell application "System Events"
    tell process "Finder"
      repeat with itemName in {"Hide Tab Bar", "Hide Path Bar", "Hide Status Bar"}
        try
          click menu item (itemName as text) of menu "View" of menu bar 1
          delay 0.4
        on error errMsg
          log "  chrome toggle skipped (" & itemName & "): " & errMsg
        end try
      end repeat
    end tell
  end tell

  tell application "Finder"
    -- Re-assert the frame after the chrome collapse so the saved content area is 680x440.
    set bounds of dmgWindow to {180, 120, 860, 588}
  end tell
  -- Hiding the tab/path/status bars shifts saved icon positions down by the bars' height
  -- (1.5 build 35 saved y=221, putting the icons 45pt below the background's arrow), so
  -- place the icons again on the final frame.
  placeIcons(dmgFolder, argv)
  tell application "Finder"
    update dmgFolder without registering applications
    delay 1
    close dmgWindow
  end tell
end run
APPLESCRIPT
}

create_drag_install_dmg() {
  rm -f "${DMG_RW_PATH}" "${DMG_PATH}"
  rm -rf "${DMG_MOUNT_DIR}"
  mkdir -p "${DMG_MOUNT_DIR}"

  echo "→ staging installer window background"
  if [[ ! -f "${DMG_BACKGROUND_1X}" || ! -f "${DMG_BACKGROUND_2X}" ]]; then
    echo "Missing DMG background: run Assets/Release/make-dmg-background.sh" >&2
    exit 66
  fi
  mkdir -p "${STAGING_DIR}/.background"
  # One HiDPI TIFF holding @1x + @2x so Retina Finder renders it crisp.
  tiffutil -cathidpicheck "${DMG_BACKGROUND_1X}" "${DMG_BACKGROUND_2X}" \
    -out "${STAGING_DIR}/.background/background.tiff" >/dev/null

  echo "→ creating writable installer image"
  hdiutil create \
    -volname "Headroom Installer" \
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

  # Staged before styling so Finder can park it off-window. Finder's background/update writes
  # were once seen deleting a pre-staged icon, so it is checked again after styling.
  stage_dmg_volume_icon

  # Finder's saved layout is intermittent: 1.5 build 41 shipped with Finder's default icon
  # positions although this pass saves the right ones on most runs. Read the .DS_Store back
  # and retry rather than publish a broken install window.
  local attempt
  for attempt in 1 2 3; do
    style_dmg_window
    sleep 2
    if verify_dmg_layout "${DMG_MOUNT_DIR}"; then
      echo "  ✓ install window layout saved"
      break
    fi
    if [[ "${attempt}" == 3 ]]; then
      echo "DMG install window layout did not persist after ${attempt} attempts" >&2
      exit 70
    fi
    echo "  ! install window layout not saved (attempt ${attempt}); styling again" >&2
  done

  if [[ ! -f "${DMG_MOUNT_DIR}/.VolumeIcon.icns" ]]; then
    echo "  ! Finder styling removed the volume icon; staging it again" >&2
    stage_dmg_volume_icon
  fi
  # A read-only image needs no fseventsd log, and a user showing hidden files would see it.
  rm -rf "${DMG_MOUNT_DIR}/.fseventsd"
  chflags hidden "${DMG_MOUNT_DIR}/.background"

  # A plain detach lets the volume flush; force only if it refuses.
  sync
  hdiutil detach "${DMG_MOUNT_DIR}" >/dev/null 2>&1 || detach_dmg_mount
  trap - RETURN

  echo "→ compressing installer image"
  hdiutil convert "${DMG_RW_PATH}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${DMG_PATH}" >/dev/null
  rm -f "${DMG_RW_PATH}"

  # The compressed image is what ships, so check the layout it actually carries.
  local verify_mount="${WORK_DIR}/dmg-verify"
  rm -rf "${verify_mount}"
  mkdir -p "${verify_mount}"
  hdiutil attach "${DMG_PATH}" -mountpoint "${verify_mount}" -readonly -nobrowse -noverify >/dev/null
  local verified=0
  verify_dmg_layout "${verify_mount}" && verified=1
  hdiutil detach "${verify_mount}" >/dev/null 2>&1 || hdiutil detach "${verify_mount}" -force >/dev/null 2>&1 || true
  if [[ "${verified}" != 1 ]]; then
    echo "Compressed DMG lost the install window layout" >&2
    exit 70
  fi
  echo "  ✓ compressed DMG carries the install window layout"
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
  set_plist_bool "${app_info}" SUAllowsAutomaticUpdates true
  # Bundle default only; never overwrite Sparkle's saved user preference.
  set_plist_bool "${app_info}" SUAutomaticallyUpdate false
}

resign_exported_info_mutations() {
  echo "→ re-signing exported app after Info.plist stamping"
  codesign \
    --force \
    --sign "${DEVELOPER_ID_SIGNING_SHA}" \
    --timestamp \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    "${WIDGET_APPEX}"
  codesign \
    --force \
    --sign "${DEVELOPER_ID_SIGNING_SHA}" \
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
  local sparkle_minimum

  signature_line="$(cat "${DMG_PATH}.sparkle-signature.txt")"
  ed_signature="$(printf '%s\n' "${signature_line}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  archive_length="$(printf '%s\n' "${signature_line}" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
  pub_date="$(LC_ALL=C date -R)"
  sparkle_minimum="$(headroom_sparkle_minimum_from_app "${APP}")"

  if [[ -z "${ed_signature}" || -z "${archive_length}" ]]; then
    echo "Could not parse Sparkle signature metadata from ${DMG_PATH}.sparkle-signature.txt" >&2
    exit 65
  fi

  headroom_write_minimal_sparkle_appcast \
    "${appcast_path}" \
    "${HEADROOM_SPARKLE_FEED_URL}" \
    "${VERSION}" \
    "${BUILD}" \
    "${pub_date}" \
    "${sparkle_minimum}" \
    "${download_url}" \
    "${ed_signature}" \
    "${archive_length}" \
    "${RELEASE_NOTES_URL}"
}

write_sha256_file() {
  local source_path="$1"
  local output_path="$2"

  shasum -a 256 "${source_path}" | awk '{print $1}' > "${output_path}"
}

write_latest_manifest() {
  local manifest_path="${HEADROOM_SPARKLE_UPDATES_DIR}/${LATEST_JSON_NAME}"
  local dmg_sha256
  local dmg_length
  local published_at

  dmg_sha256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
  dmg_length="$(stat -f '%z' "${DMG_PATH}")"
  published_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  cat > "${manifest_path}" <<EOF
{
  "name": "Headroom",
  "version": "${VERSION}",
  "build": "${BUILD}",
  "publishedAt": "${published_at}",
  "downloadUrl": "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}${LATEST_DMG_NAME}",
  "versionedDownloadUrl": "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}${DMG_NAME}",
  "appcastUrl": "${HEADROOM_SPARKLE_FEED_URL}",
  "sha256": "${dmg_sha256}",
  "size": ${dmg_length}
}
EOF
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

# Prints the SHA-1 to sign with. A display name is ambiguous once a renewed certificate
# shares it, so a name override resolves to the newest identity carrying that name.
select_developer_id_signing_sha() {
  if [[ "${HEADROOM_DEVELOPER_ID_APPLICATION}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    printf '%s\n' "${HEADROOM_DEVELOPER_ID_APPLICATION}" | tr '[:lower:]' '[:upper:]'
    return
  fi
  headroom_newest_identity_sha "${HEADROOM_DEVELOPER_ID_APPLICATION:-Developer ID Application:}"
}

for tool in security codesign curl ditto hdiutil xcrun plutil tiffutil python3; do
  require_tool "${tool}"
done
require_tool xcodegen

DEVELOPER_ID_SIGNING_SHA="$(select_developer_id_signing_sha)"
DEVELOPER_ID_APPLICATION=""
if [[ -n "${DEVELOPER_ID_SIGNING_SHA}" ]]; then
  DEVELOPER_ID_APPLICATION="$(headroom_identity_name_for_sha "${DEVELOPER_ID_SIGNING_SHA}")"
fi
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
headroom_validate_sparkle_url_prefix "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}"

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
headroom_verify_macos_bundle "${APP}" "${WIDGET_APPEX}"

if [[ "${HEADROOM_RELEASE_BUILD_ONLY}" == "1" ]]; then
  echo "✓ Developer ID app ready: ${APP}"
  exit 0
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
DMG_NAME="Headroom-${VERSION}-${BUILD}.dmg"
RELEASE_NOTES_NAME="$(headroom_sparkle_release_notes_filename "${VERSION}" "${BUILD}")"
RELEASE_NOTES_URL="${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}${RELEASE_NOTES_NAME}"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
DMG_RW_PATH="${WORK_DIR}/Headroom-${VERSION}-${BUILD}-rw.dmg"
DMG_MOUNT_DIR="${WORK_DIR}/dmg-mount"
STAGING_DIR="${WORK_DIR}/dmg-root"

mkdir -p "${WORK_DIR}" "${STAGING_DIR}" "${DIST_DIR}"

if [[ -n "${HEADROOM_SPARKLE_UPDATES_DIR}" ]]; then
  echo "→ validating Sparkle release notes"
  headroom_stage_sparkle_release_notes \
    "${VERSION}" \
    "${BUILD}" \
    "${SPARKLE_RELEASE_NOTES_DIR}" \
    "${HEADROOM_SPARKLE_UPDATES_DIR}"
fi

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
# The root-targeted symlink is the conventional, portable Finder drag-install target.
ln -s /Applications "${STAGING_DIR}/Applications"
create_drag_install_dmg

echo "→ signing DMG"
codesign --force --timestamp --sign "${DEVELOPER_ID_SIGNING_SHA}" "${DMG_PATH}"
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
  generate_appcast_status=0
  # 1.5 needed 104s to build deltas against 81 archived binaries; 120s fell back to the
  # history-less minimal feed. Leave room for the archive to keep growing.
  headroom_generate_appcast_with_timeout \
    "${SPARKLE_GENERATE_APPCAST}" \
    "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}" \
    "${HEADROOM_SPARKLE_DOWNLOAD_URL_PREFIX}" \
    "${HEADROOM_SPARKLE_UPDATES_DIR}" \
    "600" || generate_appcast_status="$?"
  if (( generate_appcast_status == 124 )); then
    echo "→ Sparkle generate_appcast timed out; writing minimal signed appcast"
    write_minimal_appcast
  elif (( generate_appcast_status != 0 )); then
    echo "Sparkle generate_appcast failed with status ${generate_appcast_status}; refusing to replace the feed." >&2
    exit "${generate_appcast_status}"
  fi
  headroom_verify_appcast_minimum \
    "${HEADROOM_SPARKLE_UPDATES_DIR}/appcast.xml" \
    "${APP}" \
    "${BUILD}"
  headroom_verify_appcast_release_notes \
    "${HEADROOM_SPARKLE_UPDATES_DIR}/appcast.xml" \
    "${HEADROOM_SPARKLE_UPDATES_DIR}" \
    "${BUILD}" \
    "${RELEASE_NOTES_NAME}" \
    "${RELEASE_NOTES_URL}"
  ditto "${DMG_PATH}" "${LATEST_DMG_PATH}"
  write_sha256_file "${DMG_PATH}" "${HEADROOM_SPARKLE_UPDATES_DIR}/${DMG_NAME}.sha256"
  write_sha256_file "${DMG_PATH}" "${HEADROOM_SPARKLE_UPDATES_DIR}/${LATEST_DMG_NAME}.sha256"
  write_latest_manifest
fi

echo "✓ Release artifact ready: ${DMG_PATH}"
echo "  Website assets: ${HEADROOM_SPARKLE_UPDATES_DIR}"
echo "  Download link: https://headroom.zantos.co/${LATEST_DMG_NAME}"
echo "  Latest manifest: ${HEADROOM_SPARKLE_UPDATES_DIR}/${LATEST_JSON_NAME}"
echo "  Sparkle signature: ${DMG_PATH}.sparkle-signature.txt"
