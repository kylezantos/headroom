# Development

How to build, test and run Headroom from source. Start with
[CONTRIBUTING.md](../CONTRIBUTING.md) if you plan to send a change.

## Build & test

```bash
swift build          # builds HeadroomCore + Headroom + HeadroomWidgets
swift test
./Scripts/build-app.sh --deps-only && xcodebuild -project Headroom.xcodeproj \
  -scheme HeadroomAppTests -destination 'platform=macOS' \
  -derivedDataPath ./.xcode-derived test   # deterministic macOS app-boundary interactions
# --deps-only unpacks the Sparkle XCFramework the project references; the pinned derived data avoids a cached "no XCFramework found" build description.
./Scripts/build-app.sh   # produces Headroom.app (menu bar / LSUIElement), then: open Headroom.app
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .xcode-derived build
```

Building requires Xcode 27.0 / Swift 6.4. The Mac app targets macOS 15 Sequoia and later on
Apple silicon: Tahoe uses Liquid Glass, while Sequoia uses a native material popover
surface. A macOS 15 Apple-silicon runtime smoke remains the release gate before this is
advertised as supported. Intel slices may be present in generic Xcode artifacts, but Intel
runtime support is not currently validated or advertised. The app bundle build also requires
`xcodegen` because macOS widget discovery expects a real Xcode app-extension target:
`brew install xcodegen`. Subscription usage requires the corresponding official CLI installed
and logged in. API spend rows require the relevant admin or management key entered in Settings.
See [Troubleshooting](troubleshooting.md) for diagnostics and current limitations.

## Structure

- `Sources/HeadroomCore`: all testable logic, with no SwiftUI: models, providers and their CLI
  reads and parsers, API spend, the polling engine and `@Observable` store, settings, and the
  iPhone sync format.
- `Sources/HeadroomSharedUI`: the stateless popover components shared by the Mac app, the
  iPhone app and both widget extensions.
- `Sources/HeadroomApp`: the SwiftUI `MenuBarExtra` shell, popover, cards, settings and menu bar
  label.
- `Sources/HeadroomWidgets`: the macOS WidgetKit extension. It reads only the App Group cache the
  app writes; it never runs a CLI, reads credentials or calls a provider.
- `Sources/HeadroomIOS`, `Sources/HeadroomIOSWidgets`: the read-only iPhone and iPad app and its
  widgets, backed by the synced snapshot.

[AGENTS.md](../AGENTS.md) is the full architecture guide and the rules every change follows.

## Local app build

`./Scripts/build-app.sh` generates `Headroom.xcodeproj` from `project.yml`, builds a real
macOS app target with an embedded WidgetKit app-extension target, then signs both the app
and extension with the first local **Apple Development** identity it finds. If no Apple
signing identity is installed, it falls back to an ad-hoc signature so the app can still
launch locally.

To use a specific certificate:

```bash
security find-identity -v -p codesigning
HEADROOM_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./Scripts/build-app.sh debug
```

A stable Apple Development signature keeps macOS permission grants and App Group sharing
from re-prompting or failing after each rebuild. Leave App Sandbox **off** for the host
app (needed to spawn `claude` and read `~/.codex/auth.json`); the widget extension is
sandboxed and reads only the App Group cache. Notarization isn't needed for a locally
built/run app.

## Widgets

Every widget style decision is a pure, tested recipe in Core; the views only lay recipes out.
`swift run Headroom --render-widgets <dir>` renders every style, size, fixture and appearance
headlessly and fails if any element overflows its tile. Run it after touching a widget view.

Widget data reaches the extension through the App Group `group.com.kylezantos.headroom`, so the
app and extension need matching entitlements under a stable signing identity. If the App Group
is unavailable, widgets show a setup state rather than reading provider credentials. Local
manually signed builds also mirror the widget snapshot into the extension's container as a
development fallback. On OS 26, draw widget backgrounds in the content layer, not
`containerBackground` (which gets an uneven Liquid Glass sheen); see the comment in
`HeadroomWidgetView` before changing that.

## iPhone and iPad companion

The phone app and widgets read only the snapshot the Mac publishes to iCloud Key-Value Store.
**Explore Demo** in the phone app shows bundled sample data with no Mac, login or network.

Local simulator smoke test:

```bash
xcodegen generate
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .xcode-derived build
xcrun simctl boot "iPhone 17" || true
xcrun simctl install booted .xcode-derived/Build/Products/Debug-iphonesimulator/HeadroomIOS.app
xcrun simctl launch booted com.kylezantos.headroom.ios
```

The simulator can verify build/install/launch, entitlements, and empty/setup states. Full
Mac-to-iPhone sync requires both the Mac app and iPhone build to be signed with the same
Apple team, iCloud Key-Value Store enabled for `com.kylezantos.headroom`, and the same
iCloud account on both devices. After the Mac publishes a snapshot, open the iPhone app
or add the Headroom iPhone widget to confirm the synced usage summary appears.

`Scripts/build-app.sh debug` strips the iCloud KVS entitlement by default so a local
manually assembled app can launch without a provisioning profile. To test real iCloud
sync from that script, use a provisioned signing setup and opt in explicitly:

```bash
HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1 ./Scripts/build-app.sh debug
```

## Official releases

Official macOS downloads and updates are published at **https://headroom.zantos.co**.
The iPhone/iPad companion uses TestFlight and the App Store, independently of Sparkle.
The maintainer's signing, notarization, App Store and website publishing procedures live
in the private `headroom-site` repository. See [release documentation](release/README.md)
for the boundary between public build tooling and maintainer operations.
