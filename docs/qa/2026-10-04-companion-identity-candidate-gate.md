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
- Corrected device inspection: the earlier connected `iPhone18,1` was a simulator.
  A direct device-details query established a connection to physical `iPhone17,1`
  running iOS 27.0.1. The verified signed Debug 1.5 (33) app was installed with
  `devicectl` (exit 0); an exact-bundle query confirmed one installed app at 1.5 (33).
  Kyle opens the app and runs the manual baseline. No physical identity pass or
  account switch is claimed. Allowlisted installation receipts are in
  `.context/ios-parity-work/u4-physical-*-summary.json`.
- Subsequent device check after Kyle reported no probe: the same bundle identifier
  actually reported developer build **1.0 (33)**. The earlier 1.5 installation
  receipt did not establish the build Kyle was now opening; the cause of this
  change is unproven. Reinstalled the signed harness, then independently queried
  the phone again: install exit 0, one matching **1.5 (33)** developer app, query
  exit 0. Both actual Debug payload dylibs contain the probe (the main executable
  is a launcher stub). Receipt: `u4-physical-reinstall-summary.json` in the same
  local evidence directory. Kyle then confirmed that fully reopened Settings shows
  **1.5 (33)** and **Identity Candidate Probe · DEBUG**. Subsequent physical results
  are recorded below; no identity verdict is inferred from installation/UI alone.

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

Recorded physical results (Kyle's reports, signed Debug 1.5 (33)):

- Reopened Settings: version 1.5 (33), probe section visible.
- App `baseline`, usual Apple ID / Drive on / online, after Reset then Arm:
  **available / equal / written / coordinated**. App baseline passed.
- Placed widget screenshot: **Widget #3 · baseline**, **3:23:40 PM** on
  2026-10-04 (displayed local time), **available · different** and
  **readable · coordinated**. This is an actual provider sample, not a gallery
  placeholder. The archived app baseline and widget token did not compare equal.
- **Candidate gate failed at the same-account app/widget baseline.** Cache-loader
  adoption is stopped. Relaunch, Drive off, offline and empty-account exercises
  were not performed and must not proceed on this failed candidate. Cause remains
  unproven; this result does not establish a real Apple ID change or cache leak.
- Diagnosis read-through confirms the probe compares a restored NSCoding object
  using `current.isEqual(restored)` in both roles; the first app Arm also checks
  its immediate archive round trip. Neither token descriptions nor archive bytes
  determine equality. Apple documents that comparison method, but the observed
  mismatch is unresolved. Preserve the current baseline and do not reset it
  during diagnosis.
- Received enum-only report from
  `.context/attachments/UGJnKG/text-429B979FC14F-1.txt`: reset #1 at
  `2026-10-04T22:21:27Z`; app baseline #2 at `2026-10-04T22:21:31Z`
  (available/equal/written/coordinated); widget baseline #3 at
  `2026-10-04T22:23:40Z` (available/different/readable/coordinated).
  The widget read and compared the stored baseline 129 seconds after Arm, with
  no intervening reset in the report. The cause of inequality remains unproven.
- Kyle reports Mac Headroom is not running. The probe uses the iPhone app and
  iPhone extension's local App Group state and identity reads; it does not require
  the Mac publisher. A further app sample against the preserved baseline can
  distinguish an app-side reread mismatch from a widget-only mismatch; this is
  diagnosis, not continuation or passage of the adoption gate.

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

## Marker candidate

Instructions only; no results are recorded here yet. This checks the KVS scope marker that
replaces the failed token (`CompanionKVSScopeMarker`, key `headroom.scope.v1`, a random UUID
in the iCloud key-value store). See `.context/ios-parity-work/u4-identity-diagnosis.md` §4.
Adopting it also needs Kyle's sign-off on the KTD22 change: KTD22 names the token and says
the scope never syncs, but the marker does sync. It holds no identity.

Build and install the signed Debug build exactly as above. In Headroom → Settings →
**Identity Candidate Probe · DEBUG**, set **Candidate** to **KVS marker**. The widget samples
whichever candidate the app last selected, and its first line reads `Marker · Widget #N · <step>`.
Each candidate has its own baseline and rows, so the token evidence above is left alone. The
marker value is never shown or exported. Only enum verdicts appear, and the shared report adds
`"candidate": "kvsMarker"`.

### Short check (about 3 minutes)

1. Use the usual Apple ID, online, with iCloud Drive on, and exit Demo. Select step `baseline`,
   then **Reset probe only**, then **Arm baseline**. Require **Marker write: written** (or
   `present` if a marker already exists) and an app row of `available / equal / written /
   coordinated`.
2. Turn on Airplane Mode and turn **iCloud Drive off**, keeping the same Apple ID. Select step
   `offline` and choose **Sample app and request widget sample**. Require `available / equal /
   readable / coordinated`.
3. Force-quit the app. Remove the **Identity Probe · DEBUG** widget and add it again. Require a
   fresh row, `Marker · Widget #N · offline`, reading `available · equal` and `readable ·
   coordinated`. N must be higher than the last ordinal and the time must be after step 2.
4. Open the app, select step `relaunch` and sample. Require `available / equal / readable`.
5. Choose **Read bounded report**, then **Share enum-only report**. Restore iCloud Drive and the
   network.

Pass: every row reads `available · equal`. Any `unavailable` or `different` row means the
candidate failed. Any row without a fresh widget invocation is unverified. In either case,
stop and share the report.

### Account-boundary check (required before adoption; may be deferred)

Do this once, after the short check passes. Never press **Arm** while signed out or on
another Apple ID: Arm writes a marker into whatever store is current.

1. With the usual Apple ID's baseline armed, select step `emptyAccount`, sample once (this saves
   the step), then force-quit the app.
2. Sign out of iCloud, or switch to the empty Apple ID, and keep the app closed.
3. Remove and re-add the probe widget. Require a fresh widget row of either `unavailable ·
   notCompared` (no marker in the new store) or `available · different`. Either one means
   cached content would be blocked. **`available · equal` is a leak**, and the candidate fails.
   It means the local store still shows the old account's marker; this matters most for
   sign-out, which Apple does not document.
4. Open the app, keep step `emptyAccount` and **Sample** (do not Arm). Require the same: not
   `equal`.
5. Optional return check: sign back in to the usual Apple ID and give iCloud a minute. Select
   `returnAccount` and sample, then re-add the widget with the app closed. Expect `available ·
   equal` once the store has downloaded. `unavailable` while the download finishes is
   acceptable, so sample again. `different` would mean the original marker was replaced, so
   report it.

Share the enum-only report after each check. Record the build, device class and iOS version,
with no account or device identifiers.

### Cleanup

**Reset probe only** in marker mode clears only the marker baseline and rows. The KVS marker
itself stays in iCloud on purpose: nothing deletes it, and production readers will use the same
key. Set **Candidate** back to **Identity token** only if you are continuing the token
diagnosis. Remove the probe widget afterwards. As with token mode, the probe, its Settings
section and the widget registration are compiled out of Release.
