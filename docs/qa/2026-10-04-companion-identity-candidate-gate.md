# Companion identity candidate gate — DEBUG only

This harness checks whether the app and widget independently obtain comparable
`FileManager.ubiquityIdentityToken` values with the existing KVS-only entitlements.
It does not validate cache isolation, synthetic writer races, KVS delivery, Siri,
controls, or the full P5 matrix. Production loaders are unchanged; adopting a
production identity gate remains blocked until physical evidence is reviewed.

Apple documents this token as an [iCloud Drive Documents identity](https://developer.apple.com/documentation/foundation/filemanager/ubiquityidentitytoken),
with NSCoding archiving and `isEqual` comparisons; it does not promise NSSecureCoding
or stable archive bytes. Its suitability for these KVS-only targets is the candidate
question. Apple directs CloudKit clients to `accountStatus` or `fetchUserRecordID`
instead of using this token to determine account login.

## Build and evidence

- Scheme: `HeadroomIOS`; Xcode 27.0 / Swift 6.4; iOS simulator 26.5.
- Local Debug generic-device build passed with cached Apple Development assets,
  version 1.5 (33). Product:
  `.context/ios-parity-work/u4-device-derived/Build/Products/Debug-iphoneos/HeadroomIOS.app`.
  The app and embedded `HeadroomIOSWidgets.appex` both passed strict signature
  verification, have development debugging enabled, and carry matching expected
  App Group/KVS entitlements; no Documents or CloudKit containers are present.
- Signed entitlement inspection: only App Group/KVS presence and matching values
  are reported; no provisioning profiles, identities, account or device IDs.
- Local logs: `.context/ios-parity-work/logs/u4-identity-*`.
- Corrected device inspection: physical iPhone `iPhone17,1` is disconnected. The
  earlier connected `iPhone18,1` was a simulator, not a physical-device state change.
  No install, launch, account switch or physical pass is claimed; reconnect first.

Build using cached signing assets only (no portal provisioning updates):

```sh
xcodegen generate
perl -e 'alarm 900; exec @ARGV' xcodebuild -quiet -project Headroom.xcodeproj -scheme HeadroomIOS -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .context/ios-parity-work/u4-device-derived build
```

After review and physical reconnection, root can install the verified signed `.app`
with `xcrun devicectl device install app --device <connected-device-ID> <verified-app-path>`
(placeholders must be resolved from current pairing/product inspection). Kyle opens
the app and adds the widget manually. Xcode's Devices and Simulators window is also
an install option. Filter device discovery by `visibilityClass != simulators` and
`properties.hardware.reality == physical`. A generic build is not installation proof;
verify the installed build/configuration and iOS version before collecting rows.
Do not substitute a simulator build or add capabilities to make the candidate pass.

## First physical pass — stop on candidate failure

1. With the original Apple ID online and Drive on, open Headroom → Settings →
   **Identity Candidate Probe · DEBUG**. Exit Demo. Select `baseline`, choose
   **Reset probe only**, then **Arm baseline**. Require app `available / equal /
   written / coordinated`. Add the separate **Identity Probe · DEBUG** small
   widget; require a fresh widget row `available / equal / readable / coordinated`.
   Relaunch the app and sample with `relaunch` to confirm archive survival; obtain
   another fresh widget invocation too.
2. Kyle turns Drive off while keeping the same Apple ID. Select `driveOff`, choose
   **Sample app and request widget sample**. Require both roles available and equal
   to the original baseline with readable archive and coordinated access.
3. With Drive still off and the same Apple ID, Kyle goes offline. Select `offline`
   and sample. Cold-launch the app, then obtain a fresh widget invocation while
   the app is closed. Both roles must remain available and equal.

A widget reload is only a request. Record a widget ordinal higher than the last
accepted row and a sample time after the action, with the intended step. Gallery
previews/placeholders say no identity sampled and are inert. If WidgetKit reuses an
old frame, wait or remove/re-add the probe widget; no fresh row means unverified.
The probe's ordinary timeline asks for refresh after 15 minutes, without promising
that WidgetKit will run on schedule. Re-adding must occur while the app is closed
when testing independent extension invocation.

If either role is unavailable, different during same-ID cases, unable to archive or
compare, or uncoordinated, export the enum-only report, record **candidate failed**
(or **unverified** when no fresh invocation occurred), and stop broader exercises.
Do not reinterpret a nil token as permission to reuse the archived identity.

## Only after availability passes

Arm compares any existing baseline; only Reset permits replacement. Set
`emptyAccount` and sample once to persist the step, close the app, then Kyle switches
to an empty Apple ID with Drive off. Before opening the app, obtain a fresh widget
row. A comparable different identity is the desired distinguishing evidence;
unavailable/notCompared fails the candidate. Open the app only afterward to sample
independently. This establishes token behavior only: no cache suppression is tested.
Other switch/transition cases need a separate reviewed scope; synthetic races and
production loader adoption are not implemented by this harness.

## Record and cleanup

Use **Read bounded report**, then **Share enum-only report**. It contains only
top-level coordination plus up to 32 rows of role, step, ordinal, time, availability,
equality, archive and coordination. Empty reports retain unavailable/failed verdicts;
rereads retain the failed app action until a subsequent app action commits or Reset
succeeds, even if an independent widget action commits in between.
Record exact configuration/build, device class and OS version without account or
device identifiers. One protected `companion-identity-probe/probe-state.json` contains
the local opaque archive and rows. A staged file receives protection/permissions
before atomic rename; failed writes leave the previous state intact. Never copy or
export this private file; only the enum report is shareable.

**Reset probe only** removes its baseline and resets its rows, leaving usage caches
alone. Remove the dedicated probe widget after testing. All helper, Settings UI and
probe-widget registration are compiled out of Release.
