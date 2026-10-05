# Lock Screen widget device spike — 2026-10-04

This is the U2 text scaffold from [the Lock Screen plan](../plans/2026-10-04-1138-feat-lock-screen-widgets-plan.md), not the final designs. Its purpose is to settle platform behavior before U5/U6. At Kyle's request, discovery, configuration and the custom inline image were checked in an isolated Simulator. Physical reboot and privacy observations remain pending.

## Build and install

Regenerate the project with `xcodegen generate`. Compile checks:

```sh
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath .context/lock-screen-spike-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOSWidgets -destination 'generic/platform=iOS Simulator' -derivedDataPath .context/lock-screen-spike-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -destination 'generic/platform=iOS' -derivedDataPath .context/lock-screen-spike-device build
```

Build logs: `.context/lock-screen-spike-{ios-simulator,widgets-simulator,device}.log`. The device build's expected app path is `.context/lock-screen-spike-device/Build/Products/Debug-iphoneos/HeadroomIOS.app`; confirm the build succeeds and the artifact exists before installing. Installation is a separate manual step:

```sh
xcrun devicectl list devices
xcrun devicectl device install app --device '<your device identifier>' .context/lock-screen-spike-device/Build/Products/Debug-iphoneos/HeadroomIOS.app
```

Do not reuse a device identifier from another QA document. Build success establishes compilation, not gallery placement, rendering or privacy behavior.

## Setup

Record device model, iOS/iPadOS version, build revision and wallpaper here: **pending**.

1. Open the installed companion app and enter demo mode. Lock Screen demos always use `fourProviders`, regardless of the Home Screen demo variant, and must visibly say “Demo”.
2. Customize the Lock Screen. Add **Headroom Lock Screen** in circle, rectangle and inline sizes. Leave any existing Home Screen widget in place to verify the two kinds stay separate.
3. On circle and rectangle, open Edit Widget. Confirm Style offers Nested Meter, Vessel Hero, Tightest First and Liquid Level, and Provider offers Automatic, Claude, Codex, Grok and Cursor. There must be no Color option. A newly placed widget defaults to Liquid Level and Automatic.
4. Pin each provider once and confirm its name appears. This scaffold uses plain text and one provider; the approved automatic multi-provider layouts and style drawings land later.
5. Exit demo mode and confirm both Home and Lock Screen kinds return to their normal state after WidgetKit reloads. Do not treat fixture values as synced usage.

## Four required answers

| Question | Reproducible check | Answer / evidence |
|---|---|---|
| Does inline offer Edit Widget? | Tap the placed inline widget during Lock Screen customization. Record whether Style and Provider controls open and persist after saving. Try a pinned provider and a different Style. | **Yes in Simulator.** Style changed to Tightest First and Provider to Codex; both persisted after saving. `.context/lock-screen-sim-inline-edit.png`, `lock-screen-sim-inline-style.png`, `lock-screen-sim-inline-provider.png`, `lock-screen-sim-demo-widgets.png`. Physical confirmation pending. |
| Does the custom inline template image render? | Inspect inline beside the date. The scaffold uses the `LockScreenInlineSpike` custom vessel silhouette. Check dark, light and photo wallpapers. Compare against a built-in widget using a system symbol. If custom art is absent while a system symbol renders, record that distinction. | **Yes in Simulator** on the default Collections wallpaper, beside the date. `.context/lock-screen-sim-signed-widgets.png` and `lock-screen-sim-demo-widgets.png`. Other wallpapers and physical confirmation pending. |
| What appears after reboot before first unlock? | First disable demo and obtain real synced usage. Reboot, keep the phone locked, and inspect every placed widget before the first unlock. Record whether it shows cached content, a neutral placeholder, waiting/corrupt copy, or nothing. Unlock once and record the change. | **Pending device check** |
| Does privacy redaction blank drawn shapes as well as text? | With demo or synced data visible, observe the rectangle's solid 12 × 24 pt diagnostic bar beside its text. Disable Lock Screen widget access under Settings → Face ID/Touch ID & Passcode → Allow Access When Locked → Lock Screen Widgets (wording may vary by OS). Lock the phone and inspect without biometric unlock. Record separately whether text, the diagnostic bar and the inline image disappear. The host marks content `privacySensitive`; its neutral placeholder has no number or filled shape. | **Pending device check** |

Save screenshots under `.context/`; attach evidence paths here without including account identifiers or credentials. Privacy observations should distinguish WidgetKit replacing the entire entry with a placeholder from only redacting text in the existing view.

## Decisions gated by these answers

- **KTD13:** Pending. Do not add an “Unlock to update” status unless the device reproduces a cache file-protection read failure before first unlock.
- **KTD14:** Simulator confirms inline can be configured; Tightest First inline is reachable. Physical confirmation pending.
- **Goal Capsule stop:** If no custom inline image renders even though a system symbol does, stop and report to Kyle. Kyle chooses system symbols, text-only inline or dropping inline. Do not silently substitute an option.
- **U5/U6 gate:** Remains closed under the plan's U2 execution note until the reboot and privacy answers are recorded. U3/U4 and the U7 primitive harness have proceeded and passed.

## Verification record

Executed on 2026-10-04 with Xcode 27.0 (27A266a): `xcodegen generate` exited 0. Both Simulator build commands above exited 0 with `** BUILD SUCCEEDED **`. The generic iOS device build also exited 0 with `** BUILD SUCCEEDED **`. No `warning:` or `error:` diagnostics appeared in these three logs.

The device app exists at `.context/lock-screen-spike-device/Build/Products/Debug-iphoneos/HeadroomIOS.app`, with `PlugIns/HeadroomIOSWidgets.appex` embedded. `codesign --verify --deep --strict` on that app exited 0. At Kyle's request, the parent session installed this signed U2 spike onto his connected iPhone 16 Pro with `devicectl`; installation exited 0 and reported “App installed” for `com.kylezantos.headroom.ios`. Gallery placement and all manual observations remain pending.

The first installed spike was replaced by another build before testing: when Kyle reported that no Headroom widgets appeared, the phone reported version 1.5 while the spike artifact is 1.0 (33). The parent reinstalled the spike and independently verified the phone's version 1.0 (33) and bundle location against the fresh install receipt. Who replaced the first build is unknown. Gallery retry is pending; the report does not yet establish a widget-code failure.

## Simulator verification — 2026-10-04

An isolated **Headroom Lock Screen QA** Simulator used iPhone 16 Pro / iOS 27.0, Xcode 27.0 (27A266a). QA stayed in the background using `simctl` and the official AXe 1.8.0 CLI stored under `.context/axe-1.8.0`; the installed AXe 1.7.1 could not load Xcode 27's relocated SimulatorKit. No live Mac screen was driven.

Headroom appeared in the Lock Screen picker. Circle, rectangle and inline widgets were placed. Circle/rectangle editing showed only Style and Provider, defaulting to Liquid Level / Automatic. Inline editing offered all four styles and all five provider choices. A saved inline widget retained Tightest First / Codex, and its custom vessel image rendered beside the date. Demo mode reloaded all three widgets with visible Demo text. The temporary inline scaffold truncates long text; U6's recipe-driven shortening is still required.

The compile-only `CODE_SIGNING_ALLOWED=NO` artifact appeared in the picker but could not run AppIntent timelines: `siriactionsd` rejected the extension for insufficient privileges, with empty entitlements. This was a QA build issue. Building normally for the Simulator preserved simulated entitlements and resolved it:

```sh
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -destination 'generic/platform=iOS Simulator' -derivedDataPath .context/lock-screen-sim-signed build
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOSWidgets -destination 'generic/platform=iOS Simulator' -derivedDataPath .context/lock-screen-sim-signed build
```

Both signed Simulator scheme builds exited 0 with `** BUILD SUCCEEDED **` (`.context/lock-screen-sim-signed-build.log`, `lock-screen-sim-signed-widgets-build.log`); the final app rebuild after the scaffold formatter reuse also succeeded (`lock-screen-sim-signed-final-build.log`). After normal installation and a demo toggle, all three timeline requests logged success (`.context/lock-screen-sim-signed-errors.log`). The custom image check therefore uses actual WidgetKit rendering, not only the offscreen harness. Screenshots: `.context/lock-screen-sim-gallery.png`, `lock-screen-sim-edit.png`, `lock-screen-sim-inline-edit.png`, and `lock-screen-sim-demo-widgets.png`. Exiting demo subsequently cleared fixture values in all three widgets and returned them to Waiting for Mac (`lock-screen-sim-demo-exit.png`); this Simulator has no signed-in iCloud account.

U3's full Core suite passed **1,233 tests in 89 suites**; the post-U4 run passed the same count (`.context/lock-screen-u4-core-tests.log`). U4's primitive sweep rendered **6,168 Lock Screen tiles with zero overflow**. The same sweep preserved all **864 Home Screen PNGs byte for byte**, including the existing 89 stress-only warnings. A temporary negative control produced 56 real overflows and exit 1, then was restored. Logs: `.context/lock-screen-u3-core-tests.log`, `lock-screen-u4-full-sweep.log`, `lock-screen-u4-home-compare.log`, `lock-screen-u4-probe-negative.log`.

Simulator observations establish discovery, configuration, custom-image support and demo reloads. They do not establish physical Always On, first-unlock cache behavior or OS privacy redaction. U2's remaining physical answers and U5/U6 remain pending.

The macOS app test gate also passed after U4: `./Scripts/build-app.sh --deps-only` exited 0, then the plan's `HeadroomAppTests` command exited 0 with **250 tests in 36 suites passed** and `** TEST SUCCEEDED **` (`.context/lock-screen-u4-macos-app-tests.log`). No Headroom.app was running at test start. Actor-isolation warnings in `ProviderCardIdentityRowTests.swift` are recorded in BUGS.md for follow-up. The isolated QA Simulator was shut down after evidence capture; other simulators were left untouched.
