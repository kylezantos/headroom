#!/bin/bash
# Validate the iOS source configuration or a signed archive before TestFlight export/upload.
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="source"
PROJECT="${HEADROOM_IOS_PROJECT:-Headroom.xcodeproj}"
ARCHIVE_PATH="${HEADROOM_IOS_ARCHIVE_PATH:-dist/ios-testflight/HeadroomIOS.xcarchive}"
LAST_UPLOADED_BUILD="${HEADROOM_IOS_LAST_UPLOADED_BUILD:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) MODE="source" ;;
    --archive) MODE="archive" ;;
    --archive-path)
      shift
      ARCHIVE_PATH="${1:?Missing archive path}"
      ;;
    --last-uploaded-build)
      shift
      LAST_UPLOADED_BUILD="${1:?Missing last uploaded build}"
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
  shift
done

fail() {
  echo "iOS release preflight failed: $1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing $2"
}

require_build_baseline() {
  [[ "$LAST_UPLOADED_BUILD" =~ ^[0-9]+$ ]] \
    || fail "set HEADROOM_IOS_LAST_UPLOADED_BUILD to the highest build already uploaded to App Store Connect"
}

build_setting() {
  local target="$1"
  local key="$2"
  xcodebuild -project "$PROJECT" -target "$target" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

verify_identity() {
  local host_version="$1"
  local host_build="$2"
  local extension_version="$3"
  local extension_build="$4"

  [[ -n "$host_version" && "$host_version" == "$extension_version" ]] \
    || fail "host and widget marketing versions do not match"
  [[ "$host_build" =~ ^[0-9]+$ && "$host_build" == "$extension_build" ]] \
    || fail "host and widget build numbers do not match"
  (( host_build > LAST_UPLOADED_BUILD )) \
    || fail "candidate build must be greater than the last uploaded build"
}

verify_source() {
  require_build_baseline
  require_file "$PROJECT/project.pbxproj" "generated Xcode project"
  require_file "Sources/HeadroomIOS/PrivacyInfo.xcprivacy" "companion privacy manifest"
  require_file "Sources/HeadroomIOSWidgets/PrivacyInfo.xcprivacy" "widget privacy manifest"
  require_file "Sources/HeadroomIOS/HeadroomIOS.entitlements" "companion entitlements"
  require_file "Sources/HeadroomIOSWidgets/HeadroomIOSWidgets.entitlements" "widget entitlements"
  require_file "Scripts/ExportOptions-TestFlight.plist" "TestFlight export options"

  local host_version host_build extension_version extension_build
  host_version="$(build_setting HeadroomIOS MARKETING_VERSION)"
  host_build="$(build_setting HeadroomIOS CURRENT_PROJECT_VERSION)"
  extension_version="$(build_setting HeadroomIOSWidgets MARKETING_VERSION)"
  extension_build="$(build_setting HeadroomIOSWidgets CURRENT_PROJECT_VERSION)"
  verify_identity "$host_version" "$host_build" "$extension_version" "$extension_build"

  [[ "$(build_setting HeadroomIOS PRODUCT_BUNDLE_IDENTIFIER)" == "com.kylezantos.headroom.ios" ]] \
    || fail "unexpected companion bundle identifier"
  [[ "$(build_setting HeadroomIOSWidgets PRODUCT_BUNDLE_IDENTIFIER)" == "com.kylezantos.headroom.ios.widgets" ]] \
    || fail "unexpected widget bundle identifier"
  [[ "$(build_setting HeadroomIOS TARGETED_DEVICE_FAMILY)" == "1,2" ]] \
    || fail "companion must target iPhone and iPad"
  [[ "$(build_setting HeadroomIOSWidgets TARGETED_DEVICE_FAMILY)" == "1,2" ]] \
    || fail "widget must target iPhone and iPad"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :iCloudContainerEnvironment' Scripts/ExportOptions-TestFlight.plist)" == "Production" ]] \
    || fail "TestFlight export must use the production iCloud environment"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' Sources/HeadroomIOS/Info.plist)" == "false" ]] \
    || fail "companion export-compliance declaration is missing"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' Sources/HeadroomIOSWidgets/Info.plist)" == "false" ]] \
    || fail "widget export-compliance declaration is missing"
  local ipad_orientations
  ipad_orientations="$(plutil -extract 'UISupportedInterfaceOrientations~ipad' json -o - Sources/HeadroomIOS/Info.plist)"
  [[ "$ipad_orientations" == *"UIInterfaceOrientationPortrait"* \
      && "$ipad_orientations" == *"UIInterfaceOrientationPortraitUpsideDown"* \
      && "$ipad_orientations" == *"UIInterfaceOrientationLandscapeLeft"* \
      && "$ipad_orientations" == *"UIInterfaceOrientationLandscapeRight"* ]] \
    || fail "companion must support all iPad interface orientations"

  echo "✓ iOS source preflight passed for version ${host_version} build ${host_build}."
}

plist_value() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

verify_archive() {
  require_build_baseline
  [[ -d "$ARCHIVE_PATH" ]] || fail "archive not found"

  local app extension app_info extension_info
  app="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
  [[ -n "$app" ]] || fail "archive does not contain an iOS app"
  extension="$(find "$app/PlugIns" -maxdepth 1 -type d -name '*.appex' -print -quit 2>/dev/null || true)"
  [[ -n "$extension" ]] || fail "archive does not embed the widget extension"
  app_info="$app/Info.plist"
  extension_info="$extension/Info.plist"

  [[ "$(plist_value "$app_info" CFBundleIdentifier)" == "com.kylezantos.headroom.ios" ]] \
    || fail "archived companion bundle identifier is incorrect"
  [[ "$(plist_value "$extension_info" CFBundleIdentifier)" == "com.kylezantos.headroom.ios.widgets" ]] \
    || fail "archived widget bundle identifier is incorrect"
  verify_identity \
    "$(plist_value "$app_info" CFBundleShortVersionString)" \
    "$(plist_value "$app_info" CFBundleVersion)" \
    "$(plist_value "$extension_info" CFBundleShortVersionString)" \
    "$(plist_value "$extension_info" CFBundleVersion)"

  local app_families extension_families
  app_families="$(plutil -extract UIDeviceFamily json -o - "$app_info")"
  extension_families="$(plutil -extract UIDeviceFamily json -o - "$extension_info")"
  [[ "$app_families" == "[1,2]" ]] \
    || fail "archived companion is not universal"
  [[ "$extension_families" == "[1,2]" ]] \
    || fail "archived widget is not universal"
  [[ "$(plist_value "$app_info" ITSAppUsesNonExemptEncryption)" == "false" ]] \
    || fail "archived companion export-compliance declaration is missing"
  [[ "$(plist_value "$extension_info" ITSAppUsesNonExemptEncryption)" == "false" ]] \
    || fail "archived widget export-compliance declaration is missing"
  local ipad_orientations
  ipad_orientations="$(plutil -extract 'UISupportedInterfaceOrientations~ipad' json -o - "$app_info")"
  [[ "$ipad_orientations" == *"UIInterfaceOrientationPortrait"* \
      && "$ipad_orientations" == *"UIInterfaceOrientationPortraitUpsideDown"* \
      && "$ipad_orientations" == *"UIInterfaceOrientationLandscapeLeft"* \
      && "$ipad_orientations" == *"UIInterfaceOrientationLandscapeRight"* ]] \
    || fail "archived companion does not support all iPad orientations"
  require_file "$app/PrivacyInfo.xcprivacy" "archived companion privacy manifest"
  require_file "$extension/PrivacyInfo.xcprivacy" "archived widget privacy manifest"

  # ASC 90626 rejected build 36: Siri intent descriptions cannot name Mac.
  local intent_metadata intent_description
  intent_metadata="$app/Metadata.appintents/extract.actionsdata"
  require_file "$intent_metadata" "compiled App Intents metadata"
  intent_description="$(plist_value "$intent_metadata" actions.UsageLeftIntent.descriptionMetadata.descriptionText.key)" \
    || fail "cannot read compiled Usage Left intent description"
  if printf '%s\n' "$intent_description" | grep -Eiq '\bmac\b'; then
    fail "Usage Left intent description contains Mac (App Store Connect error 90626)"
  fi

  local app_entitlements extension_entitlements
  app_entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null)" \
    || fail "cannot read archived companion entitlements"
  extension_entitlements="$(codesign -d --entitlements :- "$extension" 2>/dev/null)" \
    || fail "cannot read archived widget entitlements"
  [[ "$app_entitlements" == *"group.com.kylezantos.headroom"* \
      && "$app_entitlements" == *"com.apple.developer.ubiquity-kvstore-identifier"* ]] \
    || fail "archived companion is missing App Group or iCloud KVS entitlements"
  [[ "$extension_entitlements" == *"group.com.kylezantos.headroom"* \
      && "$extension_entitlements" == *"com.apple.developer.ubiquity-kvstore-identifier"* ]] \
    || fail "archived widget is missing App Group or iCloud KVS entitlements"

  echo "✓ iOS archive preflight passed."
}

case "$MODE" in
  source) verify_source ;;
  archive) verify_archive ;;
esac
