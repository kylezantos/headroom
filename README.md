# Headroom

A macOS menu bar app that shows how much of your AI-subscription usage remains — the
5-hour and weekly windows, when each resets, and a manually-entered monthly renewal
date — for **Anthropic Claude** and **ChatGPT/Codex**, side by side. It can also show
optional API dollar spend in a separate section for users who use metered OpenAI or
Anthropic APIs, bundles macOS widgets for small, medium, and large glanceable desktop /
Notification Center views, and includes an iPhone companion app + widgets that read a
redaction-safe snapshot synced from the Mac through iCloud Key-Value Store.

## How it gets the data (and why this way)

- **Claude** — reads the real 5-hour and weekly windows by driving the official
  `claude` CLI's `/usage` panel in a pseudo-terminal and parsing what it prints. This is
  the **compliant** path: the official client makes the request (a free status fetch, no
  model call), and Headroom only reads its output. It deliberately does **not** reuse or
  mint Claude subscription OAuth tokens — Anthropic's Feb 2026 policy prohibits that and
  enforces it server-side, and those tokens get blocked. The CLI panel itself notes the
  figures are "approximate, based on local sessions on this machine," but it carries the
  official reset windows.
- **Codex/ChatGPT** — reads `~/.codex/auth.json` and calls the `wham/usage` endpoint
  (the same data Codex's `/status` shows).

> **First launch:** macOS asks "Headroom would like to access data from other apps" —
> that's Headroom reading the Codex CLI's local `auth.json` (and driving the `claude`
> CLI). Click **Allow**; if you click Don't Allow, Codex usage will never appear and the
> app will sit idle. Re-grant later in System Settings → Privacy & Security if needed.
- **API spend** — optional and off by default. When enabled in Settings, Headroom stores
  provider admin/reporting keys in the macOS Keychain and reads official cost-report
  endpoints for the selected period: OpenAI organization costs and Anthropic organization
  cost reports. These keys are separate from CLI subscription login, and Headroom never
  uses Claude subscription OAuth credentials for API spend.

## Build & test

```bash
swift build          # builds HeadroomCore + Headroom + HeadroomWidgets
swift test
./Scripts/build-app.sh   # produces Headroom.app (menu bar / LSUIElement), then: open Headroom.app
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .xcode-derived build
```

Requires Xcode 26 / Swift 6.3 on macOS 26 (Tahoe). The app bundle build also requires
`xcodegen` because macOS widget discovery expects a real Xcode app-extension target:
`brew install xcodegen`. Claude usage requires the `claude` CLI installed and logged in.
Codex subscription usage requires `~/.codex/auth.json`. API spend rows require the
relevant OpenAI/Anthropic admin keys entered in Settings. Diagnostic:
`swift run Headroom --probe-claude` prints the live parsed windows so you can confirm the
Claude path works on your machine.

## Structure

- `Sources/HeadroomCore` — testable logic: domain model, the Claude `/usage` PTY probe
  (`ClaudeUsageCLIProbe`) + parser (`ClaudeUsageParser`), the Codex provider, optional API
  spend providers, the polling engine/`@Observable` store, widget cache/export models,
  credentials, and preferences.
- `Sources/HeadroomApp` — the SwiftUI `MenuBarExtra` shell and the Tahoe / Liquid Glass
  popover, cards, settings, and menu bar label.
- `Sources/HeadroomWidgets` — the WidgetKit extension. It reads only the redaction-safe
  App Group cache written by the app; it never spawns `claude`, reads credentials, or
  calls provider endpoints.
- `Sources/HeadroomIOS` — the iPhone companion shell. It reads the synced snapshot only;
  no subscription credentials or provider probes ship to iOS.
- `Sources/HeadroomIOSWidgets` — the iPhone WidgetKit extension, backed by the same synced
  snapshot contract as the companion app.

## Widgets

Headroom includes one WidgetKit extension with size-specific layouts:

- **Small** — weekly percentage left for Claude and Codex, provider-by-provider.
- **Medium** — weekly and 5-hour usage for both providers.
- **Large** — adds reset, freshness, and renewal-date context.

The widgets share the iPhone companion's card and background system (same tokens, same
ring-shadow elevation), and all text and bar colors meet WCAG AA contrast in both light
and dark. One rendering note: OS 26 composites a Liquid Glass sheen over the widget
`containerBackground` layer, which unevenly brightens the top of small tiles — Headroom
draws its background in the content layer instead (with system content margins re-applied)
so both provider cards sit on an identical surround. See the comment in
`HeadroomWidgetView` before changing that structure.

Enable or pause widget data in Headroom Settings with **Share data with widgets**. Add,
remove, and resize widgets from macOS itself; Settings controls data export, not OS
installation. Widget data sharing uses an App Group, so the app and extension need
matching entitlements under a stable signing identity for persistent real-world use. Local
development and release builds both use the iOS-style App Group
`group.com.kylezantos.headroom`; Xcode's Developer ID export embeds the Direct
provisioning profiles that authorize that group for website distribution. If the App Group
is unavailable, widgets show a setup state rather than reading provider credentials
directly. Local manual-signed builds also mirror the redaction-safe widget snapshot into
the widget extension container as a development fallback while App Group provisioning is
being finished.

## iPhone companion

Enable **Sync snapshot to iPhone** in Headroom Settings to publish the same widget-safe
summary through iCloud Key-Value Store. The synced payload contains provider names,
window labels, percentages, reset labels, freshness, and update time; it does not include
Claude/Codex credentials, API keys, raw auth files, or provider endpoints. The iPhone app
and iPhone widgets are read-only views over that snapshot. The companion app mirrors the
Mac popover with provider tiles, session/weekly bars, stale/attention treatments, and a
small About sheet for sync status and device-local appearance.

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

## Robustness (the PTY scrape is inherently fragile, so it's contained)

- Hard wall-clock deadlines on capture + a guaranteed process-group kill on every exit
  path — a hung `claude` can never stall the app.
- "Quiet-period" capture that survives the panel's several re-renders; the settled
  (last) value for each window wins.
- Login-shell PATH resolution, so a Finder-launched app (bare environment) still finds a
  node/nvm/homebrew `claude` — verified against a stripped environment.
- Graceful degrade: CLI missing → "install Claude Code"; not logged in → "run `claude`";
  transient read failure → keeps last-known data and retries next cycle.
- Reset times are shown **verbatim** from the panel ("Resets Jul 9 at 10am"), so the app
  can't drift from what Claude Code itself displays.
- The probe runs off the main actor, on the poll timer (default 5 min) — never per-render.

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

## Website release build

For a public website download, local Apple Development signing is not enough. macOS
Gatekeeper expects a Developer ID-signed and notarized artifact. `Scripts/release-app.sh`
builds the release app with hardened runtime, submits the app and DMG to Apple's notary
service, staples the tickets, signs the DMG for Sparkle updates, and verifies both with
`spctl` / `stapler`.

One-time requirements:

- Active Apple Developer Program membership.
- A **Developer ID Application** certificate installed in Keychain.
- Xcode signing access for the Mac app and widget App IDs, including iCloud Key-Value
  Store and App Groups. The release script uses Xcode's `developer-id` archive export so
  the app contains `Mac Team Direct Provisioning Profile` files and profile-derived
  entitlements.
- Notary credentials stored in the local keychain, or supplied through environment
  variables.
- A Sparkle EdDSA key pair, with the private key in your login Keychain and the public key
  stamped into the release app as `SUPublicEDKey`.

Recommended one-time notary setup:

```bash
xcrun notarytool store-credentials headroom-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "<app-specific-password>"
```

Recommended one-time Sparkle setup:

```bash
./.xcode-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

That stores the private EdDSA key in your login Keychain and prints the public key. Keep
the private key backed up; use the printed public key as `HEADROOM_SPARKLE_PUBLIC_ED_KEY`.
The current public key is:

```text
VkSwNYbBn5WJUbqYFyhewIFZt4DIfCwiWmTNiGGDorM=
```

Then build the website DMG:

```bash
HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh
```

By default, the release app is stamped with the Sparkle feed URL
`https://headroom.zantos.co/appcast.xml`, matching the public download page hosted at
`https://headroom.zantos.co`. Override `HEADROOM_SPARKLE_FEED_URL` only if the appcast
moves.

The script writes `dist/Headroom-<version>-<build>.dmg` and signs
`dist/Headroom-<version>-<build>.dmg.sparkle-signature.txt`. By default it also prepares
the website payload in `dist/headroom.zantos.co/`: a versioned DMG for Sparkle appcast
history, `appcast.xml`, a stable `Headroom.dmg` for the download button at
`https://headroom.zantos.co/Headroom.dmg`, SHA-256 sidecars for both DMG names, and
`latest.json` for the public download page to read the current version, build, size,
hash, and URLs. The DMG opens as a drag installer with `Headroom.app` next to an
`/Applications` alias.
If multiple Developer ID Application certificates are installed, pin one:

```bash
HEADROOM_DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
HEADROOM_NOTARY_PROFILE=headroom-notary \
  ./Scripts/release-app.sh
```

The host app intentionally remains non-sandboxed for 1.0 so it can spawn the official
`claude` CLI and read Codex's local auth file. The widget extension remains sandboxed and
uses only the App Group cache. By default, `Scripts/release-app.sh` uses
`group.com.kylezantos.headroom`, matching the app and widget entitlements managed in the
Apple Developer account; override `HEADROOM_APP_GROUP_IDENTIFIER` only if you intentionally
use another App Group id. Before publishing a new DMG, run a clean download-style smoke
test: open the DMG, drag Headroom to `/Applications`, launch it, verify the menu bar item
appears, confirm Claude/Codex setup or live states, and check that widgets can be added and
read the app's exported cache.

## iOS distribution

The iPhone companion app and iOS widgets are distributed through Apple's normal iOS
channels, not through Sparkle, DMG packaging, or Developer ID notarization: TestFlight
for betas, then the **App Store** (the public distribution channel) via the same
`com.kylezantos.headroom.ios` App Store Connect app record. Ad Hoc builds are only for
registered-device testing and are not the update mechanism for users.

Build a local App Store Connect export:

```bash
./Scripts/release-ios-testflight.sh
```

Upload the archive to App Store Connect for TestFlight processing:

```bash
HEADROOM_IOS_UPLOAD=1 ./Scripts/release-ios-testflight.sh
```

The upload path requires an App Store Connect app record for
`com.kylezantos.headroom.ios` and either an authenticated Xcode account or App Store
Connect API credentials. If upload fails with `Error Downloading App Information`, create
or confirm the App Store Connect app record for that bundle ID first.

```bash
HEADROOM_ASC_KEY_PATH="/path/to/AuthKey_KEYID.p8" \
HEADROOM_ASC_KEY_ID="KEYID" \
HEADROOM_ASC_ISSUER_ID="ISSUER-ID" \
HEADROOM_IOS_UPLOAD=1 \
  ./Scripts/release-ios-testflight.sh
```

## Status

Working end-to-end: live Claude 5h/weekly windows via the CLI probe (verified against a
real account and from a bare launch environment), Codex via its endpoint, optional
OpenAI/Anthropic API spend rows, manual renewal dates, launch-at-login, the Tahoe popover,
widget cache export, app icon, the bundled macOS widget extension, and the iPhone
companion/widget targets with live Mac → iPhone iCloud sync. Widget design parity with the
companion is pixel-verified on device in both appearances, and text/bar colors pass a
numeric WCAG AA contrast audit in both schemes (macOS build 10, iOS build 12). Remaining:
App Store submission for the iOS companion (TestFlight record exists) and the next
notarized DMG cut for the Mac download page.
