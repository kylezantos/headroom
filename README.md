# Headroom

A macOS menu bar app that shows how much of your AI-subscription usage remains — the
5-hour and weekly windows, when each resets, and a manually-entered monthly renewal
date — for **Anthropic Claude**, **ChatGPT/Codex**, **Grok**, **Cursor**, **GitHub Copilot**,
and **OpenCode Go**, side by side.
It can also show optional API dollar spend in a separate section for users who use
metered OpenAI, Anthropic, or xAI APIs, bundles macOS widgets for small, medium, and large
glanceable desktop / Notification Center views, and includes an iPhone/iPad companion app +
widgets that read a redaction-safe snapshot synced from the Mac through iCloud Key-Value Store.

## Website and releases

Download official builds at **https://headroom.zantos.co**. This repository contains the app
source, build tooling and canonical [release notes](docs/release/sparkle). The maintainer
manages website deployment and official release operations in the private `headroom-site`
repository; signed DMGs and Sparkle deltas are stored in `headroom-downloads`.

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
  (the same data Codex's `/status` shows). If that local session is missing or expires,
  Headroom shows a guided **Connect/Reconnect Codex** action that opens Terminal and runs
  the official `codex login` flow. Sign-in stays in the Codex CLI and browser; Headroom
  never receives passwords, browser callbacks, or tokens from the flow.
- **Grok** — asks the official `grok` CLI for billing-period usage, preferring its ACP
  billing method and falling back to the CLI's billing HTTP transport. Sign-in remains in
  `grok login`; Headroom only reads the CLI-owned auth and redacted usage result.
- **Cursor** — drives the official `cursor-agent` `/usage` panel in a pseudo-terminal and
  parses its included-usage period. Headroom does not read Cursor's app database or reuse
  private dashboard sessions.
- GitHub Copilot: off by default; turn it on in Settings → Accounts. Shows one monthly
  AI credit meter for the account signed in to the official `copilot` CLI. Headroom asks the
  CLI's local server for the monthly allowance (no prompt, no session, no credits spent) and
  scans the CLI's session logs under `~/.copilot/session-state/` on your Mac for usage
  records. Those logs also hold your prompts and tool output: Headroom decodes only the usage
  records and keeps no prompt or tool content. It never reads a Copilot or `gh` token. The
  logs advance only when the CLI runs, so a reading more than 15 minutes old shows as last
  known with its age, and use from VS Code or github.com appears only once the CLI next
  records a quota snapshot or its server count catches up; until then the meter can show more
  room left than you have. Before the first reading the row shows its label with no number.
- OpenCode: off by default; turn it on in Settings → Accounts. Shows the OpenCode Go 5-hour,
  weekly and monthly windows for each Console account signed in to the official `opencode` CLI,
  version 2.2 or newer. Headroom runs the CLI's own usage read
  (`opencode api --standalone experimental.usage.limits`); the CLI makes the request to OpenCode,
  and Headroom never reads an OpenCode credential, calls OpenCode itself, or sends a model
  request. A window OpenCode reports as limited reads as fully used, and the popover card says
  which limit is reached until when. A workspace without a Go plan says so, with a link to the
  plans. An OpenCode 1.x install shows **About OpenCode 2** instead: going to 2.x is a one-way
  upgrade of your OpenCode data, so Headroom never runs the usage read on 1.x and leaves the
  upgrade to you. Each read adds an ordinary log entry to your OpenCode home. Phones need the
  matching iPhone build to show OpenCode.

> **First launch:** macOS asks "Headroom would like to access data from other apps" —
> that's Headroom reading CLI-owned files and driving the official status surfaces. Click
> **Allow**; if you click Don't Allow, affected usage will not appear. Re-grant later in
> System Settings → Privacy & Security if needed.

- **API spend** — optional and off by default. When enabled in Settings, Headroom stores
  provider admin/reporting keys in the macOS Keychain and reads official cost-report
  endpoints: OpenAI organization costs, Anthropic organization cost reports, and xAI team
  billing/balance. These keys are separate from CLI subscription login, and Headroom never
  uses Claude subscription OAuth credentials for API spend.

## Multiple subscription accounts

Headroom can show any number of Claude, Codex, Grok, and OpenCode subscriptions side by side, tested up to 20 per provider. Each account is refreshed on its own schedule, so one slow probe delays the others by at most one probe, and Settings → General shows when a provider's accounts run slower than the chosen interval.
The built-in account keeps using the CLI's normal `~/.claude`, `~/.codex`, `~/.grok`, or
`~/.local/share/opencode` home, so existing installs need no migration. Additional accounts use
Headroom-owned, owner-only config homes selected with `CLAUDE_CONFIG_DIR`, `CODEX_HOME`,
`GROK_HOME`, or (for OpenCode) the four `XDG_*_HOME` variables, and sign in through the same
official CLIs in Terminal; Headroom never copies one account's credentials into another home.
Codex and Grok also offer device-code sign-in for each account; OpenCode signs in with the
Console device code. OpenCode reports only the active Console workspace, so track a second
workspace as a second account. Cursor is deliberately single-account because Cursor Agent has no equivalent
isolated config-home mechanism. Copilot is single-account too: its usage comes from the
session logs of the CLI's default home, which a separate Headroom-owned home would never
receive.

Add, rename, or remove accounts in **Settings → Accounts**. Removing an additional account
deletes only that Headroom-owned local CLI home; it does not touch the subscription, built-in
CLI login, or sibling accounts. The popover shows every account and becomes scrollable at
higher counts. The menu bar, macOS widgets, and iPhone/iPad snapshot intentionally continue
to follow each provider's selected main account so compact surfaces keep one stable meaning.

## Menu bar pills

In **Settings → Menu Bar**, add a pill for each provider you want to see. Drag the cards
or use their left/right arrows to arrange the pills. The preview updates with your choices.
Choose **Pills + percentages** for exact readings or **Pills only** to save space, especially
on laptops with a notch. Each pill follows its provider's main account and preferred usage
window. Removing a pill does not disconnect the account; keep at least one pill or switch
back to the automatic summary.

Menu bar order is independent of the popover. Choose widget providers separately in
**Settings → Widgets & iPhone**; existing widget selections are preserved when upgrading.

## Troubleshooting provider setup

Headroom delegates subscription sign-in to each provider's official CLI. For extra
accounts, start the flow from **Settings → Accounts** so Headroom supplies the correct
isolated home; running a plain command yourself targets the built-in account.

| Provider | Official CLI and login | Extra-account isolation | Diagnostic |
|---|---|---|---|
| Claude | [Install Claude Code](https://code.claude.com/docs/en/installation). Run `claude`, then `/login` when needed. There is no device-code flow. | `CLAUDE_CONFIG_DIR` | `swift run Headroom --probe-claude` |
| Codex | [Install Codex CLI](https://developers.openai.com/codex/cli/). Standard: `codex login`. Device code: `codex -c cli_auth_credentials_store=file login --device-auth` (Headroom also uses file-backed CLI auth for standard sign-in). | `CODEX_HOME` | `swift run Headroom --probe-codex` |
| Grok | [Install Grok Build](https://x.ai/news/grok-build). Standard: `grok login`. Device code: `grok login --device-auth`. | `GROK_HOME` | `swift run Headroom --probe-grok` |
| Cursor | [Install Cursor Agent](https://docs.cursor.com/en/cli/installation). Run `cursor-agent login`. Device-code and additional-account flows are unavailable. | None; one account only | `swift run Headroom --probe-cursor` |
| Copilot | [Install Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli). Run `copilot login`; Headroom's Terminal handoff clears `COPILOT_HOME`, `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` and `GITHUB_TOKEN` first so it signs in to the default home it reads. "Couldn't read Copilot session logs" retries on its own; choose Check Now after fixing file access. A row with no number means no usage is recorded yet this month: run the CLI once. | None; one account only | `swift run Headroom --probe-copilot` |
| OpenCode | [Install OpenCode](https://opencode.ai/docs/) 2.2 or newer (Homebrew's `opencode` and npm's `@opencode/cli` are 2.x; the `opencode.ai/install` script and npm's `opencode-ai` are still 1.x). Upgrade a 1.x install with `opencode upgrade --major`. Sign in with `opencode auth login opencode --method device`; for the built-in account Headroom asks first, because this adds a Console login to your own OpenCode and makes it the active one. "Go usage needs OpenCode 2.2 or newer" while a 2.x is installed means an older `opencode` comes first on your login shell's `PATH`. "Sign in to OpenCode Console to see Go usage" means only an API key is connected. Headroom ignores `OPENCODE_*` variables, including `OPENCODE_API_KEY`, and XDG settings from your shell profile. | `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME` | `swift run Headroom --probe-opencode` (reads your default OpenCode home with the CLI on your `PATH`; on a 1.x home a 2.x CLI upgrades its data one way) |

### Where Headroom looks for the Claude CLI

Headroom finds `claude` through your login shell first, then the fixed native and Homebrew
locations — including the legacy `~/.claude/local` install. If none of those match, it asks
npm for the active global prefix (`npm prefix -g`) and checks for a launcher there, so a
custom `.npmrc` prefix that never reaches Headroom's inherited `PATH` now works. Anthropic
recommends the native or Homebrew installer for new installs; an existing usable npm-global
launcher stays supported. After moving or reinstalling the CLI, choose **Check Again** —
Headroom rediscovers it without a relaunch or a new sign-in.

The setup and recovery messages map to these actions:

| What Headroom says | What to do |
|---|---|
| CLI not found, location unconfirmed, or waiting for the CLI | Use the provider's install action or link and finish installation. If Headroom shows **Check Again** or an account-level **Check Now**, use it afterward. For Claude, provider-level Check Again bypasses the held negative discovery result, searches again, and refreshes the built-in account without sweeping every account. |
| Not logged in, expired, malformed, or unsafe sign-in | Use **Connect**, **Reconnect**, or **Open Setup** for that account. Codex and Grok also offer **Use Device Code**. Claude may instead ask you to approve Headroom's CLI workspace. |
| Couldn't prepare the handoff / Terminal didn't open | Try again. If Headroom copied the official CLI command, open Terminal and paste it; if copying also failed, retry from Headroom. |
| Setup window still open | Close the Terminal/setup window, then retry. Headroom refuses the action with “Close setup, then retry” instead of silently opening a competing handoff. |
| Privacy denial / sign-in file cannot be read | Choose **Privacy & Security Help**, allow Headroom access in macOS System Settings, then choose **Check Now**. Codex can also offer **Resolve Storage** when its CLI saved credentials somewhere Headroom cannot read. |
| Couldn't read usage / unrecognized CLI screen | Choose **Check Again**. If it persists, run that provider's probe above; probes print redacted classifications and parsed usage, not credentials. |
| Sign-in wasn't confirmed / verification timed out | Choose **Check Now** or reopen setup. Verification has a bounded stop-loss (four minutes, covering one in-flight probe plus the check's own worst case), so it settles to a typed failure instead of spinning forever. |

## Troubleshooting API spend

Subscription login cannot authorize organization spend. Add a separate reporting key in
Settings; use a dedicated key with the narrowest access the provider console offers so it
can be revoked independently.

| Spend provider | Required key and where to get it | Known limitation |
|---|---|---|
| Anthropic | [Anthropic admin key](https://platform.claude.com/settings/admin-keys) | The live request currently returns HTTP 400, likely because of the request date format. |
| OpenAI | [OpenAI organization admin key](https://platform.openai.com/settings/organization/admin-keys) | The spend request has not yet been live-verified with a real admin key. |
| xAI | [xAI management key](https://console.x.ai/team/default/settings/management-keys) with only the required ACLs | Validated for one team; multi-team/multi-organization reporting is not supported. |

Headroom stores one key per provider in the macOS Keychain; multiple organizations or keys
per provider are not supported. Diagnose a configured path with
`swift run Headroom --probe-spend <openai|anthropic|xai> [--key-file <path>]`.

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
See the troubleshooting tables above for commands, diagnostics, and current limitations.

## Structure

- `Sources/HeadroomCore` — testable logic: domain model, subscription providers and their
  CLI probes/parsers, optional API
  spend providers, the polling engine/`@Observable` store, widget cache/export models,
  credentials, and preferences.
- `Sources/HeadroomApp` — the SwiftUI `MenuBarExtra` shell with Liquid Glass on Tahoe and
  native material on Sequoia, plus cards, settings, and the menu bar label.
- `Sources/HeadroomWidgets` — the WidgetKit extension. It reads only the redaction-safe
  App Group cache written by the app; it never spawns `claude`, reads credentials, or
  calls provider endpoints.
- `Sources/HeadroomIOS` — the iPhone/iPad companion shell. It reads the synced snapshot only;
  no subscription credentials or provider probes ship to iOS.
- `Sources/HeadroomIOSWidgets` — the iOS/iPadOS WidgetKit extension, backed by the same synced
  snapshot contract as the companion app.

## Widgets

Headroom includes one WidgetKit extension with size-specific layouts:

- **Small** — the primary subscription meter for each enabled provider.
- **Medium** — the available rolling or billing-period meters, provider-by-provider.
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

## iPhone and iPad companion

Enable **Sync snapshot to iPhone** in Headroom Settings to publish the same widget-safe
summary through iCloud Key-Value Store. The synced payload contains provider names,
window labels, percentages, reset labels, freshness, and update time; it does not include
CLI credentials, API keys, raw auth files, or provider endpoints. The iPhone/iPad
app and widgets are read-only views over that snapshot. The companion app mirrors the
Mac popover with provider tiles, session/weekly bars, stale/attention treatments, and a
small Settings sheet for sync status and device-local appearance. A production **Explore
Demo** action shows clearly labeled bundled sample data without a Mac, login, or network
request; its separate App Group flag also makes the widgets demo safely. Exiting demo
restores the untouched real waiting/synced state.

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
  node/nvm/homebrew `claude` or `codex` — verified against a stripped environment.
- Codex connect/reconnect delegates to the official `codex login` command in Terminal with
  an account-scoped readable-file storage override,
  retries the normal usage fetch, and keeps last-known usage dimmed while reauthentication
  is in progress. Headroom does not write or refresh the Codex auth file itself.
- Graceful degrade: CLI missing → "install Claude Code"; not logged in → "run `claude`";
  transient read failure → keeps last-known data and retries next cycle.
- Reset times are shown **verbatim** from the panel ("Resets Jul 9 at 10am"), so the app
  can't drift from what Claude Code itself displays.
- Claude probes run off the main actor in one serial lane while Codex/network fetches can
  overlap. The poll timer defaults to 5 minutes and enforces a 2-minute floor — never per-render.

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

## Official releases

Official macOS downloads and updates are published at **https://headroom.zantos.co**.
The iPhone/iPad companion uses TestFlight and the App Store, independently of Sparkle.
The maintainer's signing, notarization, App Store and website publishing procedures live
in the private `headroom-site` repository. See [release documentation](docs/release/README.md)
for the boundary between public build tooling and maintainer operations.

## Status

Working end-to-end: live Claude, Codex, Grok, Cursor, and Copilot subscription usage through their
documented provider paths (OpenCode Go has one real reading, an unused subscription, with its
other states checked against a local stub Console), optional OpenAI/Anthropic/xAI API spend rows, manual renewal dates,
launch-at-login, the adaptive macOS popover,
widget cache export, app icon, the bundled macOS widget extension, and the iPhone
companion/widget targets with live Mac → iPhone iCloud sync. Widget design parity with the
companion is pixel-verified on device in both appearances, and text/bar colors pass a
numeric WCAG AA contrast audit in both schemes (macOS build 10, iOS build 12). Remaining:
App Store submission for the iOS companion (TestFlight record exists) and the next
notarized DMG cut for the Mac download page.

## Contributing

Outside code PRs need a GitHub contribution proposal labeled `accepted` by the maintainer first.
Tiny documentation fixes can come directly. Start with [CONTRIBUTING.md](CONTRIBUTING.md);
[AGENTS.md](AGENTS.md) explains the architecture and the rules every change follows.
For a new provider, follow [Adding a provider](docs/adding-a-provider.md) before implementation.
Send bug reports and feature requests to **support@zantos.co**; customer feedback is tracked
privately. Report security problems as described in [SECURITY.md](SECURITY.md).

## License

Headroom is licensed under the [GNU General Public License v3.0](LICENSE). Contributions are
accepted under the [Contributor License Agreement](CLA.md).

The Headroom name and app icon are not licensed under the GPL. Forks are welcome, but a fork you
publish needs its own name and icon, and must not suggest it is Headroom or made by its maintainer.
