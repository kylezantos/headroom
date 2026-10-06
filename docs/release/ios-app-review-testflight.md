# iOS App Review and TestFlight Runbook

Release candidate: iOS **1.5** (`com.kylezantos.headroom.ios`) with its widget extension
(`com.kylezantos.headroom.ios.widgets`), shipped together with Mac 1.5 (KTD23). The release build
is **35** for every target (the U15 spike takes iOS 34; see "Build numbers" in
`release-operations.md`). Still confirm the highest build App Store Connect actually
shows as `HEADROOM_IOS_LAST_UPLOADED_BUILD`, never a number from this file.

Marks used below: **[adoption]** needs `CompanionLoaderAdoption.isEnabled` on, which waits for
the KVS scope-marker device check and Kyle's KTD22 sign-off; with it off, the phone shows each
provider's main account only and pull-to-refresh re-reads. **[U15]** needs the CloudKit reminders
spike to pass and U16 to land. **[U17]** needs the Lock Screen and Control Center work to land.
Record an unmet condition as "not run (condition)", never as a pass.

## Why the 1.0 resubmission existed (history)

On July 15, 2026, App Review rejected build 14 under Guideline 2.1(a) because the
reviewer could not access connected functionality without a Mac/iCloud publisher.
Submission ID: `3472c833-11a3-4815-82d0-816b291dab60`. Apple explicitly accepted a
demonstration mode as the resolution.

Build 24 includes the production, one-tap demo introduced in build 21, needs no login,
Mac, iCloud payload, or provider account, and carries the latest companion/widget fixes.
The host and widget extension remain universal on iPhone/iPad. Demo data is bundled and
read-only; a separate App Group flag coordinates the widget and never replaces the real
snapshot cache.

## Automated release gates

```bash
swift test
xcodegen generate

# Run HeadroomIOSUITests on an iPhone simulator (and, for 1.5, an iPad simulator; see below).

HEADROOM_IOS_LAST_UPLOADED_BUILD=<highest uploaded> Scripts/verify-ios-release.sh --source
```

For 1.5 the iPad pass is a release gate, because the iPad layout changed (R24): run
`HeadroomIOSUITests` on iPhone 17 Pro **and** iPad Pro 13-inch simulators, plus the headless
`xcrun simctl` captures at the default size and xxLarge in both appearances.

The release script repeats source preflight, archives, validates the signed host and
embedded widget, and only then exports/uploads:

```bash
HEADROOM_IOS_LAST_UPLOADED_BUILD=<highest uploaded> ./Scripts/release-ios-testflight.sh

HEADROOM_IOS_LAST_UPLOADED_BUILD=<highest uploaded> \
HEADROOM_IOS_UPLOAD=1 \
  ./Scripts/release-ios-testflight.sh
```

If using API-key authentication, set all three `HEADROOM_ASC_KEY_PATH`,
`HEADROOM_ASC_KEY_ID`, and `HEADROOM_ASC_ISSUER_ID` variables. Never paste their values
into this document or command output. The export sets `iCloudContainerEnvironment` to
Production (`Scripts/ExportOptions-TestFlight.plist`); every TestFlight build reads Production.

## Efficient App Store Connect path

Preflight App Store Connect access and the physical acceptance device before archiving. Follow one
path per state transition:

1. Prefer `release-ios-testflight.sh` for archive validation and upload.
2. If CLI upload reaches an Xcode account-state error, open the same fresh archive in Xcode
   Organizer and upload it once. Do not alternate repeatedly between export methods or rebuild a
   candidate that already passed archive validation.
3. Record **uploaded** only when the upload completes. Processing, export compliance, internal
   group assignment, TestFlight availability, clean-device acceptance, and App Review submission
   remain separate states.
4. Treat Xcode Organizer's **Uploaded** status only as upload evidence. Verify processing and
   group assignment through an already configured App Store Connect API/CLI or the user's logged-in
   App Store Connect browser; the TestFlight app can independently confirm device availability.
   Ask before opening visible logged-in Chrome.
5. Prefer a tester operating the physical iPhone from the checklist below. Do not configure
   iPhone Mirroring during the release or use it as a workaround for physical-device access. Use
   it only when already configured and explicitly chosen by the user.
6. Never enter or automate a Mac login password, device unlock, passkey, two-factor code, or
   privacy confirmation. State the exact handoff and wait for the user.

If processing or device acceptance cannot be verified, leave the exact state pending. An uploaded
build is not yet an available or accepted TestFlight build.

## Internal TestFlight acceptance

Keep the currently accepted build available while validating the candidate. Pair it with a signed
Mac 1.5 build that has the iCloud key-value entitlement, on the same Apple ID; run that Mac's
`Headroom.app/Contents/MacOS/Headroom --dump-phone-sync` whenever a step asks which keys exist.

1. Wait for App Store Connect processing and export-compliance completion.
2. Assign the candidate to the internal Headroom group first.
3. Delete prior development/App Store copies before installing from TestFlight.
4. On an iPhone, launch with no Mac publisher available: the Waiting for Mac screen offers
   Explore Demo.
5. Tap **Explore Demo**. The default "Multiple accounts" sample shows Claude Personal, Work and
   Studio and Codex Personal and Work stacked inside their provider cards, main first, in the
   meter style the sample Mac uses. Check red numerals on critical rows, bare countdowns
   ("3d 23h"), no "Low" chip, the Codex plan capsule (tap opens it; it opens on its own while a
   live 5-hour or weekly limit is critical), API spend, light/dark, portrait/landscape.
6. In Settings (one sheet: About, Appearance, Widgets and iPhone sync), check
   Match my Mac and its overrides on the live specimen, the widgets gallery, the "What syncs
   through your iCloud" list, and About's "Get Headroom for Mac" row with no tip jar. Use launch fixtures during simulator QA to walk every state: No recent update ("No update from your Mac since
   …"), Past reset ("Reset at … · waiting for your Mac", no number), Older Mac app ("Update
   Headroom on your Mac to see every account"), Sync paused, Waiting for Mac, More than 20
   accounts ("N more on your Mac"), Account states, Banked resets, Display choices.
7. Add small, medium, and large widgets. Each shows a visible DEMO label, follows the sample's
   main accounts only, and opens `headroom://usage` back to the labeled demo.
8. Terminate/relaunch the app; app and widget must remain in demo. The card entrance plays once
   on launch, not on a refresh or rotation.
9. Exit through the Demo Mode banner on Usage; app and widget must return to the real waiting/synced state.
10. **Accounts on a real Mac [adoption].** On the Mac, add a second account to a provider,
    rename it, make it fail (sign it out), Make Main, then remove it; also give two accounts the
    same name. After each change, within one Mac publish (about a minute):
    - the phone shows every Mac account inside its provider card, in the Mac's order with the
      main account first, titled with the name chosen on the Mac (duplicates read "Work" and
      "Work · 2", and Make Main never swaps the suffixes); no email ever appears;
    - the failed account reads a typed line in neutral ink that says what to do on the Mac
      (for example "Sign in again on your Mac"), with no sign-in action on the phone;
    - Home Screen widgets show only each provider's main account and switch when Make Main
      moves it; they never show an extra account's name or setup state.
    With adoption off, record "main accounts only (adoption off)" and continue; that result is
    expected, not a pass.
11. **Old Mac.** With a 1.4.1 Mac publishing, the phone shows each provider's main account and
    "Update Headroom on your Mac to see every account"; pull-to-refresh only re-reads.
12. **Check now [adoption].** Pull to refresh on the usage screen: "Asking your Mac…", then
    "Checking N accounts…" with per-account progress, then "Just now". With the Mac asleep or
    Headroom quit, after 60 seconds the phone reads "Your Mac hasn't answered. It may be asleep,
    or Headroom isn't open." and keeps the last numbers. Five pulls within ten seconds start one
    Mac refresh. A second pull within a minute of a finished check reads "Checked a moment ago".
    In Explore Demo, a pull plays the sample receipt and writes nothing. Timing constants stay
    provisional until `docs/qa/2026-10-check-now-latency-spike.md` is filled in; record the
    observed acknowledgement time.
13. **Freshness.** Quit Headroom on the Mac. The app dims and says "No update from your Mac
    since <time>" once the Mac has been quiet past max(15 minutes, twice its interval); widgets
    dim no sooner than 60 minutes. A window ten minutes past its reset with no newer reading
    hides its number on every surface. A healthy Mac never dims anything.
14. **Siri and Shortcuts.** Ask "How much Claude is left in Headroom" (repeat for Codex, Grok,
    Cursor) and run "Usage Left" from the Shortcuts app. Answers use "left", name the main
    account's tightest window (plus weekly when different, plus any tighter account) with its
    age, open with "No update from your Mac since …" when dimmed, speak a past-reset window as
    "reset at <time>, waiting for your Mac", and omit account names while the phone is locked.
    Demo answers say they are sample data. Siri never changes anything.
15. **Reminders [U15, deferred].** Phone reminders are deferred to a future version: the
    Reminders section says "Reminders come from Headroom on your Mac" and no phone
    notification exists.
16. **Lock Screen and Control Center [U17].** Add each Lock Screen accessory family and the
    control. They follow the main account, show DEMO in demo, and dim (the small families and the
    control as the dimmed treatment plus the bare time). Repeat
    `docs/qa/2026-10-03-widget-config-upgrade-spike.md` with the Lock Screen family over a
    previously placed widget.
17. **iPad.** On an iPad (or iPad simulator if no device is at hand; say which), cards fill the
    width in flowing columns: 13-inch portrait 2, landscape 3, 11-inch and mini portrait 1. Resize
    with Stage Manager and change the text size: columns re-plan with no overflow and VoiceOver
    order follows provider order. Settings, demo and widgets behave as on iPhone.
18. **Sync off.** Turn off "Sync usage to iPhone" on the Mac. The phone shows "Companion Sync
    Paused", and `--dump-phone-sync` lists only `headroom.sync.v4.manifest` (the tombstone) under
    `headroom.sync.v4.`. Turning sync back on restores every account.
19. Check stale/offline/setup states and confirm no provider credential action exists on iOS.

Only after this gate passes: assign the same build to the intended external group,
submit for Beta App Review when required, and enable broader invitations after approval.

## TestFlight “What to Test”

Draft for 1.5. Drop each bracketed sentence whose condition did not ship.

```text
New in 1.5: the iPhone and iPad app now looks like Headroom's Mac popover and shows every
account your Mac tracks, in your Mac's meter style. Pull down to ask your Mac to check now.
Widgets dim when your Mac hasn't updated in a while. Siri answers "How much Claude is left
in Headroom". iPad fills its width with columns. [Reminders can arrive on your iPhone from
Headroom for Mac.] [Lock Screen widgets and a Control Center control are new.]

Please pair this build with Headroom 1.5 for Mac on the same Apple ID, then check that every
Mac account appears, names match, and pulling down updates the numbers. Try Explore Demo from
a clean launch with no Mac; leave it using Exit in the Demo Mode banner. Add small, medium
and large widgets. If you still run Headroom 1.4.1 on your Mac, the app shows main accounts
and asks you to update the Mac.

Report device, OS version, widget size, appearance, and reproduction steps with feedback.
```

## Notes for App Review (1.5 draft)

Paste into App Store Connect › App Review Information › Notes once Kyle approves it; the 1.0
block in `appstore-listing.md` is superseded for 1.5. Drop each bracketed sentence whose
condition did not ship. The sync sentence follows KTD22's what-syncs list.

```text
Headroom has no login or Headroom account. Please leave "Sign-in required" off.

To review every feature without a Mac or provider account:
1. Launch Headroom on iPhone or iPad and tap "Explore Demo".
2. Review the usage screen: Claude and Codex with several accounts, meter rows, reset
   countdowns, the Codex plan capsule (tap it) and API spend. Pull down to see the
   check-now sequence play from sample data.
3. Open Settings (gear) to inspect About, Appearance, Widgets and iPhone sync.
4. Add a small, medium, or large Headroom widget[, or a Lock Screen widget]. Widgets show
   the same clearly labeled sample data while Demo is on.
5. Ask Siri "How much Claude is left in Headroom", or run "Usage Left" in Shortcuts.
6. In Settings, tap "Exit Demo" to return to the real companion state.

Demo uses bundled sample data, makes no network request and never writes to iCloud. Live
data comes from Headroom for Mac through the user's own iCloud: account names the user
chose, plan names, usage, reset times, API spend, display choices, check-now requests and
a random ID for the Mac and for each iPhone or iPad[, plus reminder text in the user's
private iCloud database]. Sign-ins, emails and API keys never leave the Mac. The iOS app
and widgets are read-only and never contact an AI provider.[ Reminders are sent by the
Mac app and cannot be triggered from Demo.]

There is no hidden functionality, dynamic code, analytics, or data collection.
Contact kylezantos@gmail.com if any assistance is needed.
```

## App Privacy

Stays **Data Not Collected** for 1.5. Apple defines "collect" as "transmitting data off the
device in a way that allows you and/or your third-party partners to access it for a period
longer than what is necessary to service the transmitted request in real time"
(developer.apple.com/app-store/app-privacy-details, checked 2026-10-05). Synced data moves only
between the user's own devices through their iCloud key-value store [and private CloudKit
database]; the developer cannot read either, and the app has no analytics or third-party SDKs.
Re-check if any data ever reaches a developer server or the CloudKit public database.

## App Review fields

- Sign-in required: **Off**. Headroom has no login or account.
- Review Notes: the 1.5 draft above, once approved.
- Screenshots: the Graphite set from `Scripts/capture-appstore-shots.sh` composed in
  `design/appstore/compositor.html` from `design/appstore/shots.json` (frame table and captions
  await Kyle's sign-off): iPhone 6.9-inch 1320 × 2868 and iPad 13-inch 2064 × 2752, sRGB, no
  alpha. Turn off Mac availability for the iOS app (R33).
- Support URL: `https://headroom.zantos.co`
- Privacy URL: `https://headroom.zantos.co/privacy`
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` in host and extension.

## Reply to the unresolved App Review message (1.0, July 2026 — history)

```text
Hello,

Thank you for the guidance regarding Guideline 2.1(a). We added a demonstration mode
that exposes the app's complete display functionality without a login, Mac, iCloud
snapshot, or provider account.

In the new build, launch Headroom and tap “Explore Demo” on the first screen. You can
then review Claude and Codex usage, the Weekly (Fable) model limit, API Spend, Settings,
and all Headroom widget sizes. Demo content is clearly labeled. In Settings, tap “Exit
Demo” to return to the real companion state.

Headroom has no login or developer-hosted account, so “Sign-in required” is disabled.
The Review Notes contain the same step-by-step instructions.

This update addresses submission 3472c833-11a3-4815-82d0-816b291dab60. Thank you.
```

## Resubmission record

After the gates pass, record here: processed build, internal group/date, external Beta
Review status (if applicable), clean-device acceptance result, selected App Store build,
review-thread reply date, and final resubmission status. Do not mark the release shipped
until those facts are verified in App Store Connect.

- 2026-07-15: Fresh reviewed build 21 signed archive and archive preflight passed. Xcode
  Organizer uploaded the host app and embedded widget to App Store Connect at 12:31 PM PT;
  processing, internal-group assignment, and clean TestFlight acceptance remain pending.
- 2026-07-18: Build 23 passed the source, signed-archive, iPhone, and iPad release gates.
  Xcode Organizer uploaded the host app and embedded widget to App Store Connect at
  1:22 PM PT; App Store Connect processing and TestFlight group assignment remain pending.
- 2026-07-20: Build 24 was confirmed unused, then passed source preflight, host/widget archive
  preflight, strict code-sign validation, and all 6 iPhone UI tests. The archive is retained at
  `dist/ios-testflight/HeadroomIOS.xcarchive`. After explicit confirmation, Xcode created an Apple
  Distribution certificate and fresh App Store profiles, then exported an Apple
  Distribution-signed local IPA at `dist/ios-testflight/export-24/Headroom.ipa`. Host and widget
  both report 1.0 (24) and pass strict signature validation. Build 24 has not been uploaded or
  assigned to a TestFlight group.
