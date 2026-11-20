# AGENTS.md — Headroom

Project-specific guidance for AI agents working in this repo. Read this before making
changes.

## What this is

A native macOS 15+ menu bar app (Swift 6 / SwiftUI) showing remaining AI-subscription
usage — 5-hour and weekly windows, reset times, manual renewal dates — for **Claude**,
**ChatGPT/Codex**, Grok, Cursor, Antigravity, GitHub Copilot and OpenCode (Go), behind one provider
abstraction so more can be added. Tahoe uses Liquid
Glass; Sequoia uses a native material popover surface.

The repository is open source under GPL-3.0, with contributions accepted under `CLA.md`. Outside
contributors start from `CONTRIBUTING.md`; this file stays the full guide. Design explorations,
plans and QA records are kept outside the repo, so plan anchors in comments (`KTD7`, `R12`) have
no in-repo definition.

## Product principles (Sep 2026)

- **The goal is real-time usage data for every provider and every account, as smoothly,
  reliably, and solidly as possible.** A growing number of people rely on Headroom to manage
  their usage; reliability and honesty of the numbers come before new surface area.
- **Provider parity by default.** Any feature, enhancement, or behavior change applies to all
  providers (Claude, Codex, Grok, Cursor, Antigravity, Copilot, OpenCode) and to every account of each, unless a provider's
  transport or official-client boundary genuinely prevents it. When parity is not possible,
  say so explicitly in the plan, PR, or reply, with the reason, rather than silently scoping
  the change to one provider. "Cheap for this provider" is never a reason to leave it out.

## Adding a provider

Before implementing any new provider, read [docs/adding-a-provider.md](docs/adding-a-provider.md).
An accepted issue welcomes investigation and implementation within the existing patterns.
Document the official read path and sanitized evidence in the issue/PR; discuss a different
authentication/data-access mechanism or significant architecture change before implementing it.
Reuse the existing provider/source, polling, account/setup, shared UI and phone-sync seams. Do
not invent token reuse, private HTTP fallbacks, scraping, a second polling engine or a separate
provider-specific UI.
If an approved official-client source cannot provide trustworthy quota, stop and report the gap.

## ⚠️ Hard constraint — do NOT reintroduce Claude subscription-OAuth

Claude usage is read by driving the **official `claude` CLI's `/usage` panel** in a
pseudo-terminal and parsing it (`ClaudeUsageCLIProbe` + `ClaudeUsageParser`). This is a
deliberate, load-bearing choice.

**Do not** "improve" this by calling `api.anthropic.com/api/oauth/usage`, reusing the
`Claude Code-credentials` Keychain token, minting tokens via a "Sign in with Claude" OAuth
flow, or spoofing a `claude-code` User-Agent. Anthropic's Feb 2026 policy **prohibits**
third-party use of subscription OAuth credentials and **enforces it server-side** (it broke
OpenClaw/OpenCode/Roo/Goose and CodexBar's OAuth path). That approach is both non-compliant
and non-functional. The earlier git history contains a removed OAuth/Keychain implementation
— that was retired for these reasons; do not resurrect it.

The compliant principle: let the **official client** make the request; we only read its
output. `/usage` is a free status fetch (no model call), so polling it costs no usage.

## Architecture

- `Sources/HeadroomCore` — all testable logic (no SwiftUI):
  - `Models/` — `UsageSnapshot`/`UsageWindow` (with `resetLabel`), `FailureReason`,
    snapshot `Freshness` (`.pending`/`.live`/`.stale`), per-window
    `UsageWindowFreshness` (`.live`/`.stale`/`.unavailable`), `UsageProvider` protocol,
    `Countdown`, `Account` (`AccountID`/`AccountKey`/`ProviderAccount`), and the pure
    `MeterStyle`/`MeterRecipe` rendering contract.
  - `Providers/` — `ClaudeProvider` (via `ClaudeUsageSource`), `ClaudeUsageCLIProbe`
    (openpty + posix_spawn), `ClaudeUsageParser`, `CodexProvider` (+ `UsageHTTPClient`,
    DTOs), `CodexConnection`, the Grok, Cursor and Copilot sources, `OpenCodeProvider` (via
    `OpenCodeUsageSource`, `OpenCodeConnection`), `AntigravityProvider` (via
    `AntigravityUsageSource`, `AntigravityConnection`), shared login-shell `CLIExecutableResolver`,
    `RedirectBlocker`, `AccountStorage` (per-account config homes).
  - `Credentials/` — `CredentialStore` (Codex-only), `CodexAuthReader`, `Redaction`.
  - `Engine/` — `PollingEngine` (wake timer), `LaneSchedule` (pure cadence decisions),
    `AccountProbeScheduler` (per-lane due queue), `UsageStore` (`@MainActor @Observable`).
  - `Settings/` — `Preferences` (UserDefaults), `AccountRegistry` (persisted account
    catalog, capacity-aware; the tested envelope is 20 per provider), `LaunchAtLogin` (SMAppService).
  - `Sync/` — the phone contract both platforms compile: v4 models and codec
    (`CompanionSyncModels`, `CompanionSyncCodec`), `CompanionSnapshotResolver`,
    `CompanionSnapshotLoader` with its scoped App Group cache, `CompanionPhoneSnapshotSource`,
    the phone half of check-now (`CheckNowProtocol`) and demo replay. The Mac-only halves
    (`CompanionPublisher`, `CheckNowCoordinator`, `CompanionAttentionMapping`) live in `Engine/`.
- `Sources/HeadroomSharedUI` — the popover's stateless components, compiled into the Mac app,
  the iPhone app and both widget extensions: `MeterGauge`, `UsageBarView`, `IdentityRow`,
  `APISpendRow`, `PlanCapsule`, `StatusSentence`, `SkeletonMeter`, `ProviderStyle`, the
  AppKit-free `HeadroomMotion`, `Layout/FlowingColumnsLayout` and `Settings/MeterStyleTile`.
  SwiftPM builds it as a public module (Mac files `#if SWIFT_PACKAGE import HeadroomSharedUI
  #endif`); Xcode compiles the folder straight into each target. Run both `swift build` and an
  xcodebuild after touching it: the first catches a missing `public`, the second a name collision.
- `Sources/HeadroomIOS`, `Sources/HeadroomIOSWidgets` — the read-only iPhone/iPad companion
  and its widgets. Nothing on the phone talks to a provider or signs in.
- `Sources/HeadroomApp` — SwiftUI `MenuBarExtra(.window)` shell + adaptive popover (Liquid
  Glass on Tahoe, native material on Sequoia), cards, settings, menu bar label.
  `MeterGauge` is the popover's single format × shape × fill renderer; `AppComposition` is
  the one place providers are wired. Settings (Sep 2026) is a fixed-frame
  `NavigationSplitView`: `SettingsView` owns every root state and dialog, `SettingsSidebar`
  lists the six `SettingsPane` destinations, and the stateless panes live in
  `SettingsPanes.swift`; Appearance previews choices with an inert `AppearanceSpecimen`.

Data flow: `PollingEngine` wakes at the earliest due account → `AccountProbeScheduler`
drains each CLI lane one probe at a time (most overdue first) and fetches the HTTP lane's
due accounts concurrently → `UsageStore` merges with continuity → menu bar label + popover
bind to the `@Observable` store, the Mac widgets read the App Group file, and the phone publisher
(`CompanionPhoneSync` → `CompanionPublisher`) writes iCloud KVS → every phone surface resolves it
through `CompanionSnapshotResolver`.

**Loading language (Oct 2026).** `UserRefreshRun` retains per-account origins and outcomes;
`VisibleRefreshWork` drives the footer through subscription and spend work without treating
setup verification as a user refresh. `ReprintRecipe` derives wipe, ghost, fresh print and
end hold from that record on every frame. `SetupMotion` chooses slosh for app work and the
approved drip for a user wait; successful Settings removal uses the row's drain transition.
Shared vessel views own paused `LoadingTimeline` clocks and accept `loadingDate` for captures;
the native menu label keeps its bounded clock exception described below. iPhone and widget
waiting placeholders use uniform ghosts, with outlines in monochrome rendering; schema stays 3.
`--demo loading` uses controlled fixture sources, inert account storage and a typed setup
coordinator. All native demos keep setup, account management, credentials, duplicate detection
and launch-at-login isolated from the user's CLI files and system services.

**Popover account layout (Oct 2026).** Settings › Appearance offers **Account layout:
Standard / Compact** (`AccountLayout`, Mac-only: it never reaches the phone, the widgets or the
menu bar, KTD8). Both layouts share one column rule: one 384pt column until the single-column
cards would pass the 640pt cap, then exactly two (750pt), read down then across, never three
(`AccountColumnsPlanner` in Core). With **Scroll vertically** chosen
(`expandAccountsHorizontally` off) there is no second column: the list grows until it reaches the
space on the popover's screen or 900pt, whichever is smaller, then scrolls
(`PopoverCardMetrics.verticalCardsHeightCap`, planned on close like the columns). A provider whose accounts span both columns draws as two card
fragments; only the first carries a capability-recovery header. Compact draws one line per
account (`CompactAccountRow`, decided by Core `CompactAccountRowRecipe`) and keeps the Standard
section for any account whose state needs an action. The plan is made when the popover closes,
from the heights it last drew, and on an account-set change; heights never replan while it is
open. `MenuBarExtra` grows its window with the content but never shrinks it, so `PopoverView`
fits a narrower window itself, while it is hidden. See
`docs/solutions/ui/popover-account-columns.md`.

The popover meter style is one global `MeterStyle`, persisted as three independent
UserDefaults-backed preferences (format, shape, fill) and mirrored by `UsageStore`. Widget and
menu-bar projections intentionally carry no style. The phone's v4 manifest does (Oct 2026): its
display block carries meter style, percentage mode, account-name ink and the in-app Spark switch,
which the phone follows under one "Match my Mac" switch (`PhoneDisplayPreferencesStore`, KTD11).

**Widget styles (Oct 2026).** Each placed widget chooses its own **Style** (Nested Meter —
the default — Vessel Hero, Tightest First, Liquid Level) and **Color** (Always colored, Only
when low) in Edit Widget. Both extensions use one `AppIntentConfiguration` with
`HeadroomWidgetConfigurationIntent` (`Sources/HeadroomWidgets/HeadroomWidgetConfigurationIntent.swift`,
compiled into both extensions only) and keep their original kind strings so placed widgets
survive the update. Style and color are Foundation enums in Core (`WidgetLayoutStyle`,
`WidgetColorMode`) with an unknown-value fallback to the defaults; nothing about style is in
the widget envelope (schema stays 3). Every per-style decision — shown providers, primary and
tightest windows (`WidgetWindowRanking`: lowest displayed value first, stale alongside live,
unavailable last), shedding ladders, Liquid Level's wash segments, large-only spend and footer
— is a pure, tested `WidgetStyleRecipe`; the shared views in `HeadroomWidgetSharedUI` only lay
recipes out through `HeadroomWidgetStyledBody` plus the full-bleed `HeadroomWidgetStyledBackground`,
which every caller (both hosts, Settings, the harness) draws under the padded content. Settings ›
Widgets & iPhone previews the styles but never sets them.
**Lock Screen widgets (Oct 2026).** A second widget in the iOS extension, kind
`HeadroomIOSLockScreenWidget` with its own `HeadroomLockScreenConfigurationIntent`, offers circle,
rectangle and inline sizes on the iPhone and iPad Lock Screens. Edit Widget offers **Style** (the
same four names, default **Liquid Level**) and **Provider** (Automatic, Claude, Codex, Grok,
Cursor, Copilot, OpenCode, Antigravity); there is no Color. Each style draws one approved design per size.
Every decision — which provider (circle: home R6 pick;
rectangle and inline: the two widget providers; Tightest First on Automatic: every synced provider),
the R8 state order, captions, Cursor and Antigravity pool names, demo labels, status forms, inline text candidates
and the stepped inline image — is the pure, tested `LockScreenWidgetRecipe`; the shared
`HeadroomWidgetLockScreenBody` only lays it out in one ink of opaque grays (`LockScreenWidgetTokens`).
A pinned provider missing from the envelope shows "Off" and never falls back to another provider.
Like the home widgets, it shows each provider's main account only (schema 3 carries no others) —
the stated multi-account parity exception. `--render-widgets` also renders every Lock Screen
style × size × provider × fixture at three phone geometries, normal, Always On and privacy
(`--widget-family lock|home` filters). The inline vessel images are generated from Core geometry
with `swift run Headroom --generate-lock-screen-vessels`.
Tube remains a stored shape when Full is selected, but `GaugeShape.resolved(for:)` renders it
as Chip until the user returns to Micro.

**Widget freshness (Oct 2026).** Every phone surface dims from one pure rule,
`CompanionFreshnessRule` (KTD15): past max(15 min, 2 × the largest effective interval the Mac
reports), 120 min when only v3 is known, with a 60-minute floor for widgets, Lock Screen and
Control; ten minutes past a reset with no newer reading the number hides. Widgets take it as
`WidgetFreshnessTreatment`, a recipe input that turns past-reset windows unavailable and demotes
a dimmed widget's windows to stale once (never stacked opacity). `HeadroomWidgetFreshnessFrame`
lays out the "Reset at <time>" notes (dropped first) and the "No update … since" line (never
dropped) for every style; `CompanionTimelineSchedule` adds entries at the dim moment and each
reset + 10 min. The Mac widget dims against its own export time on the 120-minute threshold.

### iPhone and iPad companion (Oct 2026)

Durable reasoning:
`docs/solutions/architecture-patterns/companion-sync-v4-multi-key.md`.

- **Two sync formats in one publish.** The Mac writes v4 under `headroom.sync.v4.`: a manifest
  (`…manifest`: lineage, generation, status, provider order, per-provider generation + SHA-256
  digest + effective interval, display block, widget selection, reminder summary, answered
  check-now IDs, ladder level), one key per provider (`…provider.<id>`: every account in Make Main
  order with Mac-resolved titles (the name the Mac shows, so a captured email when "Use email as
  account name" is on; never an email in any other field), typed attention, banked resets,
  flagged Spark rows, API spend),
  one store-wide `…receipt` and one `…request.<deviceUUID>` per phone install. It keeps writing
  the primary-only schema-3 key `headroom.syncedWidgetSnapshot` alongside, with the same
  `generatedAt` plus `companionSourceID`/`companionGeneration`, so build-33 phones keep working.
- **One resolver for every phone surface.** `CompanionSnapshotResolver` decides v4 versus v3
  (a disabled tombstone always wins; a v3 that names the manifest's lineage is a mirror and never
  wins while the manifest is readable; a lineage-less, newer v3 is an older Mac and adds "Update
  Headroom on your Mac to see every account"), assembles providers per KTD6.3, and hands widgets
  `primaryProjection()`. The app, the iOS widget extension and Siri load through
  `CompanionPhoneSnapshotSource`; the Mac widget still reads its local App Group file.
- **Cached loading is scoped by the KVS marker.** `CompanionLoaderAdoption.isEnabled` is `true`
  (Oct 5): phones load through `CompanionSnapshotLoader`, which never serves a cache written under
  another iCloud account. The scope is the KVS marker `headroom.scope.v1`
  (`CompanionKVSScopeMarker`), a random UUID that lives in the iCloud store itself, so an account
  change swaps it. Every phone process's loader creates it when the store has none (a placed widget
  can run before the app after an update); none ever rewrites one. The first candidate,
  `ubiquityIdentityToken`, failed on device (it differs between app and widget and is nil with
  iCloud Drive off). The marker and everyday-use acceptance were approved in place of the DEBUG
  probe; the on-device account-switch check remains a U20 item. Turning the switch off restores build 33's loading path.
- **The Mac publisher coalesces (KTD8).** `UsageStore` hands a fresh capture to
  `CompanionPhoneSync` on every phone-bound change; it stamps a generation on the main actor and
  forwards to the serial `CompanionPublisher` actor. Flushes write changed provider keys, the
  manifest and the v3 key together, at most once per 60 s; a heartbeat rewrites manifest + v3
  once per chosen interval; status, account set, main account, titles, display block, intervals
  and widget selection force an immediate flush. Change detection ignores timestamps, but a key is
  rewritten once any observation in it advances by a chosen interval, so "Updated" stays honest.
  One flush writes at most one key per provider plus the manifest and v3: nine with seven
  providers. The publisher test derives that bound from the provider count rather than pinning
  it. The multi-20 publisher test with Antigravity as the seventh provider (one account), on a
  2-minute interval, averages 5.4 key writes a minute with a busiest minute of 7 and a largest
  flush of 7 under the test's provider-by-provider pacing. With six providers, interleaving the
  multi-account providers' reads, so every key changes every minute, measured 6.93 a minute with
  a busiest minute of 8: above the 6.5 average target, and unresolved (BUGS.md). Real iCloud
  throttling is unmeasured until the check-now spike runs.
- **Budget ladder (KTD7).** `CompanionPayloadBudget` measures the whole v4 namespace before
  every write (requests and receipt included): 15,000 bytes per provider key, 64,000 for the set.
  Level 1 drops extra accounts' model rows; level 2 caps extras only above 20 per provider. Over
  budget after that, the publisher writes nothing and keeps the last good content. Multi-20 with
  Spark rows, the single Copilot account, 20 OpenCode accounts and the single Antigravity account
  measures 35,779 bytes for the whole set at level 0 and 28,126 at level 1. OpenCode's monthly
  window is a window, not a model row, so level 1 keeps it.
- **Sync off sweeps.** The disabled v3 envelope, then a two-field manifest tombstone, then every
  other key under the namespace. The sweep repeats on every launch while sync is off, which also
  repairs keys a downgraded 1.4.1 Mac cannot delete. Diagnostics (key names and sizes, ladder
  level, last failure) come from `--dump-phone-sync`, run from the signed bundle.
- **Demo isolation.** The Mac's publisher and check-now observer exist only in a real launch
  (`AppComposition.usesInertPhoneSync`: off under `--demo`, the render and bench harnesses and
  the XCTest host). The phone's Explore Demo replays bundled `CompanionDemoVariant` fixtures
  (snapshots and a check-now receipt) and never writes iCloud or the snapshot caches. `--demo
  --demo-variant <name> --demo-screen <usage|settings|widgets>` launches a screenshot pose.

### Multi-account (Jul 2026)

Claude, Codex, Grok and OpenCode each carry any number of signed-in accounts up to a **tested
envelope** of 20 (`AccountRegistry.testedEnvelope`, Sep 2026 — the bound the suites and the
`multi-20` demo exercise, not an advertised limit); Cursor is deliberately
single-account because its CLI exposes no isolated config-home mechanism, and Copilot is
single-account because a Headroom-owned `COPILOT_HOME` would never receive the session logs
its meter reads, and Antigravity is single-account because `agy` keeps its sign-in in its own
home and the Keychain, isolating a second account is unproven, and a probe of a signed-out home
opens a browser sign-in. Snapshots are keyed
by `AccountKey` (provider + account); one `UsageProvider` instance exists per account. The
**built-in** `.primary` account reads the CLI's default config (`~/.claude`, `~/.codex`,
`~/.grok`, `~/.local/share/opencode`) exactly as before — zero migration for existing installs. **Extra** accounts get
Headroom-owned config homes under `~/Library/Application Support/Headroom/Accounts/…` and
route the same compliant paths there: the Claude probe runs with `CLAUDE_CONFIG_DIR` set,
Codex reads the `auth.json` that official `codex login` wrote under that account's
`CODEX_HOME`, Grok reads the `auth.json` that `grok login` wrote under `GROK_HOME`, and
OpenCode's usage read runs with `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and
`XDG_STATE_HOME` pointed at `…/Accounts/opencode/<id>/{data,config,cache,state}` (all four, so
the refresh lock under state always pairs with its data; the built-in account unsets all four).
Codex and Grok offer account-scoped device-code handoffs as well as standard login; OpenCode's
only sign-in is the Console device-code flow. Sign-in
is always a Terminal handoff to the official CLI
through the account-scoped `SetupSessionCoordinator` — the OAuth
constraint above applies to every account. An abandoned handoff can be force-cancelled with
**Stop waiting**: Headroom clears its durable markers and releases the coordinator slot, while
the user remains responsible for closing the still-visible Terminal process. Every visible
**built-in** row can also **Sign Out & Set Up Again**; that reset targets the CLI's default
config, so changing its login is machine-wide (including Terminal), and old/mid-handoff usage
is generation-rejected until a fresh post-handoff capture arrives.

Claude's handoff has two script kinds, chosen at staging (Sep 2026). **Sign In** runs the
`signIn` script: it reads the `loggedIn` field of `claude auth status --json`, runs `claude auth
login` when the account is signed out, prints one result line, and exits with sign-in's own
status. That process exit is the completion signal, so nothing polls while Terminal is open;
waiting is bounded by a 5-minute timeout whose **Try Again** fronts the open Terminal and
resumes. **Open Claude Workspace** (purpose `.trust`), an unreadable CLI version, and an extra
account below the print-mode floor keep the `interactive` bare launch, which is polled after
each result lands. A readable version below 2.1.41 opens no Terminal and reads **Update Claude
Code**. Codex, Grok and Cursor keep their 3/7/15/30-second ladder. OpenCode's sign-in and
reset scripts, like Claude's Sign In, end with the login's own status and complete on process
exit with the same 5-minute timeout (a device login can outlast the ladder). Antigravity's
`agy acp --login` completes on process exit too, and no check runs while its Terminal is open:
a read on a signed-out `agy` would open another browser sign-in.

**Follow the default login (Nov 2026).** Every Claude, Codex, Grok, Cursor and
Copilot reading carries the identity of the account it came from (`AccountIdentity`, a SHA-256
digest of the CLI's own metadata, never the upstream id). Claude, Codex and Grok read their account file
before and after the usage read; if the two reads disagree or exactly one fails, the reading is refused
on `UsageProviderFetchResult.discard` and read again at the lane's next turn, with no backoff
and no dimmed row. After two refusals in a row the next one merges as an ordinary transient
failure. A file unreadable on both sides is a steady state, so that reading is kept under no
account's name (Claude refuses it instead, see below). A row is a slot bound to one identity (`SlotRecord` in `Engine/DefaultLoginRecords.swift`,
stored under `defaultLoginRecords.v1`). When the built-in row's default login becomes a different
account, the row takes that account's name, or "Main", and none of the previous account's
history or reminder state; the previous account's label, last reading and reminder state are
kept in the record store and return if that account does. Parity, forced by what each client exposes:

| Provider | Identity | Mid-change refusal | Relabel and history reset | Remembered |
|---|---|---|---|---|
| Codex | `account_id`, strong | Yes | Yes | Yes |
| Grok | email, weak | Yes | Yes | No |
| Cursor | email from `status`, weak | No (the read runs beside the capture) | Yes | No |
| Copilot | login, weak, up to an hour old | No | Yes | No |
| Claude | `accountUuid` + `organizationUuid` from `.claude.json`, strong | Yes | Yes | Yes |

OpenCode is not in this table: its readings carry no identity yet (the usage read's workspace
block is never decoded, KTD19 of the OpenCode plan), so a change of the built-in home's Console
login is not followed. Tracked in BUGS.md. Antigravity is not in it either: single account,
and its `/usage` and `/credits` answers are read for quota only, so its readings carry no
identity and a change of `agy`'s default login is not followed.

**One row for one account (Phase 3).** When the default login is the same account as exactly
one added account, every display surface shows one row for the pair: the added account's row
stands for both (`DisplayMergePlanner`, the display list's `mergeMap`). Both config homes keep
being read. The merge needs a known, equal, strong identity on both rows (so Claude and Codex
only; a weak identity never merges), a live or transiently stale reading on the added row, and
no setup in progress on either; in any other case both rows show as before. It is a display
decision made fresh from current readings, never stored, and it removes or signs out nothing.
`--demo merged` and `--render-scenario merged` pose it.

**Remembered accounts (Phase 2).** The account the default login left keeps a dimmed row with
its last reading: a "Last read …" tag where "Stale" would be, and, once a window's reset has
passed, one line "Reset Tue 3:32 PM · not read since" with no gauge and no number
(`Countdown.lastReadLabel` and `Countdown.resetNotReadLine`, the same wording on the Mac and the
phone; the row draws the compact form because the sentence form, "Reset yesterday at 12:32 AM ·
not read since", does not fit a Micro row, and the tooltip and VoiceOver keep the sentence). The
reset lines of one account share a label column (`UsageBarView.resetLine(peers:compact:)`), so
they start at one x, and their ink sits one step under the dimmed label. In the Full meter style
the reset row is the line alone, with no band kept open for the gauge; when a reset passes while
the popover is open, the popover's layout signature (`PopoverCardLayoutSignature.resetLines`)
closes the row on `valueSpring` while the gauge and the line cross-fade. Micro keeps its row height. It is never probed,
never the main account and never fires a reminder, and it does not count toward add-account
capacity. An unnamed one is numbered like an added account ("Account 2") while it is remembered
and is "Main" again when it is the default login; a name the user chose travels both ways. Rename
and Remove live on `UsageStore.renameRememberedAccount` / `removeRememberedAccount`; Remove only
hides the row until that account is the default login again. A remembered row yields while an
extra row reads the same account and returns when that extra is removed.

Two lists, and every consumer belongs to one (KTD8). `UsageStore.accounts(for:)` is the **engine
list**: what is read. Merge acceptance, scheduling, setup, the promote write, the duplicate-login
scan and feedback diagnostics read it. `UsageStore.displayAccounts(for:)` / `displayPrimaryKey(for:)`
(`DisplayAccountsResolver` in `Engine/DisplayAccounts.swift`) is the **display list**: engine rows,
then visible remembered rows. The popover, Settings, the menu bar, notification labels and the
phone capture read it. A new surface reads the display list; anything that decides what to probe
reads the engine list. `store.snapshot(for:)` serves a remembered row's reading already aged
(`UsageContinuityPolicy.rememberedSnapshot`, run at launch, on each engine wake and on popover
open), so no view ages one. The phone learns a row is remembered from one optional v4 account key,
`k`, written only when true: a setup with no remembered rows writes the bytes it wrote before, and
a phone that predates the key shows the row as an ordinary stale extra. Widgets and the v3 key
show each provider's main account only. `--demo remembered` poses the states from an in-memory
record store.

Claude is wired on gate V1's one recorded case:
after `claude auth login` to another account, the `oauthAccount` block of `.claude.json` changed
with the Keychain credential, and after `claude auth logout` it was gone. Identity is
`oauthAccount.accountUuid` plus `oauthAccount.organizationUuid` (`AccountIdentity.claude`; one
account in two organizations is two identities, a null organization is a value, a non-UUID id is
no identity), read as metadata only. Each row reads its own file: the built-in row
`~/.claude.json`, an extra the root of its `CLAUDE_CONFIG_DIR`. `ClaudeProvider` reads it before
and after the `/usage` capture; unlike Grok, a file undecodable on both sides is refused, so the
refusal bound turns it into a transient failure. An inherited `CLAUDE_CODE_OAUTH_TOKEN`
(`ClaudeUsageCLIProbe.launchesWithInheritedOAuthToken`, presence only) makes every Claude row
Absent. `AppComposition.claudeIdentityReader` wires the reader in a real launch only; demos,
harnesses and the XCTest host read no file. A session left running under one account while
`claude auth login` changed the folder to another did not write the old account back (same
record, one CLI version, a few minutes). One switcher is verified by a run: `errhythm/ccswap`
at `8bf7b9b` kept the file and the credential together through five switches and a switch
under a running session, and Headroom followed three more end to end (same record,
2026-11-12, in a VM). **What a release may say (Kyle, 2026-11-12):** Headroom follows the
default login when it changes the standard way, with the credential and the CLI's account
record swapped together, which is how account switchers work. All six Claude switchers read
in source do that; one is proven by a run. Do not name a tool as supported. A switcher that
leaves `.claude.json` alone would file readings under the wrong account, and that limit goes
in any support answer about a switcher that misbehaves. A Claude Desktop sign-in is not
checked and will not be (Kyle: people who switch accounts are not using Desktop for it).
Codex has no real-switch run: its account id and its token live in the one `auth.json` that
the request reads, so there is no second place to fall out of step, and that is reasoning,
not a test. Never read the Keychain item or run `claude auth status` for identity.

Each provider has a persisted primary selection. **Make Main** reorders the selected row to the
top, refreshes only it, and immediately reroutes the menu bar, widgets, phone projection,
capability recovery, and the never-signed-in timer exemption. A dangling primary pointer falls
back to canonical order without writing defaults and is retained in case the row resurfaces.
The popover still shows all accounts at the regular meter scale and the card list scrolls past
its cap (640pt with two columns, up to 900pt with Scroll vertically). Account management lives in Settings → Accounts (`AccountsSettingsTile`), where each
provider group header also carries the subscription on/off switch (off means not fetched, never
unmanageable); removing
an **extra** account deletes its Headroom-owned config home, while the **built-in** account can
only be *stop-tracked* (Aug 2026): a persisted registry tombstone hides the row without touching
the CLI's own config or login, allowed only while another account exists, undone via "Show CLI
Account" in the provider header. Claude rows signed in to the same upstream login (matched by
the default-login identity, `accountUuid` plus `organizationUuid`, metadata only, so the badge
and the records never disagree) get a detection-only "Same login as X" badge. Rows are never
merged in storage; the only merge is the display-only one-row rule above, between the built-in
row and one added account with the same strong identity.

## Commands

```bash
swift build                        # HeadroomCore + Headroom
swift test                         # unit suite (fast, all mocked — no CLI/network/Keychain)
xcodegen generate                  # regenerate the project after project.yml changes
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
# Required pre-PR iOS build (app + extension), alongside swift build and swift test.
./Scripts/build-app.sh --deps-only && xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' -derivedDataPath ./.xcode-derived test
# --deps-only unpacks the Sparkle XCFramework the project references (package resolution alone doesn't); the pinned derived data avoids a cached "no XCFramework found" build description.
# Without the maintainer's Apple team (contributors, CI), append CODE_SIGNING_ALLOWED=NO to both xcodebuild commands: the app tests and the iOS build pass unsigned. `.github/workflows/ci.yml` runs all three checks on the `xcode-27` runner.
swift run Headroom --probe-claude  # diagnostic: prints live parsed /usage windows
swift run Headroom --probe-antigravity  # one Antigravity read through agy's no-turn /usage and /credits: parsed rows, credits badge, or the outcome name only. On a signed-out agy it opens one browser sign-in; see docs/solutions/antigravity-cli-usage-feasibility.md
swift run Headroom --probe-opencode [--opencode-home <dir>] [--opencode-executable <path>]  # one OpenCode usage read: parsed windows or the outcome name only. Without --opencode-home it reads the built-in default home (a 2.x client migrates a 1.x home one way: never run it bare on a home that must stay 1.x). --opencode-executable is DEBUG-only and needs --opencode-home; see docs/solutions/opencode-cli-usage-feasibility.md
Headroom.app/Contents/MacOS/Headroom --dump-phone-sync  # what the Mac published for the phone: key names, sizes, ladder level (signed bundle only; `swift run` has no KVS entitlement)
swift run Headroom --render-widgets <dir> [--widget-style <id>] [--widget-fixture <name>] [--widget-quick] [--widget-transparent]  # headless widget-style renders + overflow sweep; --widget-transparent renders on transparent backgrounds at 4× for compositing
swift run Headroom --render-popover <dir> --loading-only  # pinned, offscreen loading checkpoints; native acceptance remains separate
swift run Headroom --render-popover <dir> [--render-scenario <name>] [--account-layout standard|compact]  # one scenario (light + dark) at the popover's real column width; `--render-scenario remembered` poses remembered rows, `--render-scenario merged` the one-row merge
swift run Headroom --demo [loading|multi-2|multi-3|multi-5|multi-7|multi-20|multi-mixed|spend-states|spend-retained|banked-resets|five-providers|six-providers|copilot-no-reading|opencode-no-go|opencode-update|opencode-limited|remembered|merged]  # fixture data; loading exercises delayed probes/spend and inert setup; multi-20 is the tested envelope; six-providers is the every-provider demo and now carries all seven providers, Antigravity included, in registry order with Antigravity directly above Copilot (five-providers stays Claude, Codex, Grok, Cursor and Copilot); opencode-no-go, opencode-update and opencode-limited pose the no-Go card, the update-required state and a limited monthly window; remembered shows a live default plus a dimmed and a fully reset remembered row for Claude and Codex, from an in-memory record store; merged shows the default login and the extra that reads the same account as one live row, beside a dimmed remembered row (mock scenario B)
swift build -c release -Xswiftc -DHEADROOM_BENCH && .build/release/Headroom --bench-ui <popover|scroll|settings|switch|counts|scene|all> [--scenario single|multi3|multi5|multi7|multi20] [--account-layout standard|compact] [--pane <pane>] [--runs n] [--json <path>]  # offscreen perf bench: main-thread CPU, frame-by-frame probes, body counts
# Release builds only. Without -DHEADROOM_BENCH the body counters and the Settings pane seam compile to nothing: timings still run, counts and pane switches don't. Scripts/bench-trace-summary.py slices a Time Profiler trace by its signposts.
./Scripts/build-app.sh             # → Headroom.app (LSUIElement), then: open Headroom.app
Scripts/dialkit.sh [scenario]      # live-tune the popover with DialKit: inspector + demo with a pinned popover (HEADROOM_DIALKIT=1; values in HeadroomSharedUI/HeadroomTuning.swift, defaults = shipped literals)
```

## Official release operations

The maintainer's release runbooks and `release-website-dmg` skill live in the private
`kylezantos/headroom-site` repository. For an official release request, use that checkout's
`docs/release/release-operations.md` and `.agents/skills/release-website-dmg/SKILL.md`.
Keep source/build scripts and canonical Sparkle notes here. Normal contributor builds do
not require access to the private repository. Never publish an official release from an
unmerged branch or change public download/update URLs as part of routine development.

Building requires Xcode 27.0 / Swift 6.4 (iOS 27 SDK). The iOS deployment target remains
26.0; guard any iOS 27 API with an availability check. The app targets macOS 15+ on Apple
silicon; a real macOS 15 Apple-silicon runtime smoke is required before advertising Sequoia support. Claude
requires the `claude` CLI logged in; Codex requires its CLI-managed `~/.codex/auth.json`.
When Codex auth is missing or rejected, the app delegates recovery to official `codex login`
in Terminal and never owns the browser callback, token refresh, or auth-file writes.

## Conventions

- **UI work starts from [DESIGN.md](DESIGN.md)**: where every token lives (motion, colour,
  spacing, type), which component does which job, and the rules for adding a new token.
- **Reduce Motion and accessibility are best-effort for now (Sep 2026).** Keep the existing
  S2A policy and don't knowingly regress it, but don't hold a change back, or expand its
  scope, over Reduce Motion or accessibility polish. Reviews should report such gaps at low
  priority rather than as blockers.
- **Both iOS targets include Core by whole folder**: `Models/`, `Notifications/`,
  `Settings/` (except `LaunchAtLogin.swift`), `Sync/`, and `Widgets/` (except
  `WidgetSnapshotProjector.swift`). Files in those folders reference only types in the
  same five folders; Mac-only logic belongs in `Engine/`, `Providers/`, `Credentials/`
  or the Mac app. Do not replace this with a hand-picked file list (KTD4, iOS parity plan).
- **Swift 6 strict concurrency is on.** `CredentialStore` is an `actor`; `UsageStore` is
  `@MainActor`; models and providers are `Sendable`. Keep it compiling clean under complete
  concurrency checking.
- **Everything is injectable for tests.** Providers take a source/HTTP/`now` seam; tests use
  fixtures + mocks (`Mocks.swift`) and never touch the real CLI, network, or Keychain. Add
  new behavior behind a seam and test it the same way.
- **Failures are the typed `FailureReason` enum, never interpolated errors** (no token/PII
  leakage). Providers never throw — they return a stale snapshot (`.stale(for:reason:)`).
- **Reset times use the shared semantic formatter** from `UsageWindow.resetSchedule` on
  every surface. Source labels and valid IANA zones are non-visible provenance only.
- Comments cite plan/decision anchors (e.g. `KTD7`, `R12`) as WHY notes — keep those; drop
  comments that just narrate WHAT the next line does.
- Don't commit build artifacts (`.build/`, `Headroom.app/`) — already gitignored.

## Gotchas

- **Widget style views must pass the render sweep.** `swift run Headroom --render-widgets <dir>`
  renders every style × family × fixture × appearance at macOS and 6.1″ sizes and exits non-zero
  if any probed element (`.headroomWidgetProbe()`) leaves its tile's content box (WCF7: drop whole
  elements, then truncate text; never `minimumScaleFactor`). New payload views carry the probe.
  WidgetKit's rendering mode is read through `@HeadroomWidgetRendering` so the harness can pose
  the monochrome and stripped branches; don't read `widgetRenderingMode` directly in a style view.
  `ImageRenderer` ignores Dynamic Type, so xxLarge still needs a device look.
- **Lock Screen views stay one-ink and platform-neutral.** Shared UI never names a WidgetKit
  accessory family or `AccessoryWidgetBackground` (they don't compile for macOS); the iOS host maps
  sizes to `LockScreenWidgetFamily` and injects marks and backdrops through
  `HeadroomWidgetLockScreenArt`. Never default the Lock Screen style through
  `WidgetLayoutStyle.default` (that is the home default, Nested Meter); use
  `LockScreenWidgetChoices`. Ink is opaque gray lightness (`Color(white:)` from
  `LockScreenWidgetTokens`), never white with opacity — vibrant rendering maps lightness, not alpha
  (KTD5).
- **Pill-shelf drag positions come from `PillShelfLayout`, never an `.offset`.** The layout
  places the dragged card at the pointer and, on release, at its drop slot in one animation;
  the store commits after it lands. Every offset-based handover jumped. See
  `docs/solutions/ui/swiftui-layout-owned-drag-position.md`.
- **Meter visual acceptance must use the live `MenuBarExtra` window.** Drive deterministic
  fixtures with `swift run Headroom --demo <scenario> --meter-style
  <format>.<shape>.<fill>` and inspect the native popover in both appearances. Do not accept
  `--render-popover` output as final evidence while the offscreen capture limitations tracked in
  `BUGS.md` remain; Core recipe tests prove decisions, not SwiftUI rendering or window sizing. The
  harness does honour `--meter-style`, so `--render-popover <dir> --meter-style full.segmented.ghost`
  is the way to sanity-check the Settings swatches and specimen in a non-default style headlessly.

- **DialKit tuning needs the pinned popover (Oct 2026).** The `MenuBarExtra` popover closes as
  soon as focus moves to the DialKit inspector, so a `HEADROOM_DIALKIT` build always shows a pinned,
  floating copy of the popover (`PopoverTuningModel.showPinnedPopover`). Keep it: every tuning session
  depends on it, including new panels. It has no MenuBarExtra host, so it always draws the Headroom
  shell; judge the Surface panel's **System glass** in the real menu-bar popover.

- **Snappiness is measured, not eyeballed (Oct 2026).** A still render proves the settled layout,
  not motion or re-render cost. Changes that add an animation, a scroll or geometry callback, a
  timer, an `onAppear` correction, a per-row formatter, or a fast-changing store read in the
  popover, Settings or the scene body should be checked with body counts and back-to-back
  before/after runs (`--bench-ui`, see Commands; its `scene` section measures a stand-in for
  `HeadroomApp.body`, so mirror scene-body changes into `BenchSceneStandIn` first). The method and the hot-spot checklist (implicit animation over a measured
  container, per-frame `@State` in a big body, store reads in `App.body`/scene closures) are in
  `docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md`.

- **The Claude probe is print-first, PTY-fallback.** `ClaudeUsageCLIProbe` first runs
  `claude -p "/usage" --no-session-persistence` (non-interactive, ~2s, atomic report — no
  TUI repaints to garble labels, no partial paint of the separately fetched model rows).
  That path is version-gated to ≥ 2.1.217, the oldest CLI verified to dispatch `/usage`
  locally in print mode — below the floor an unverified CLI might forward "/usage" to the
  model as a paid prompt, so older CLIs use the PTY panel path unchanged. Any print miss
  (timeout, cost-report shape, unparseable output) also falls back to the PTY. Don't remove
  the PTY path, and don't lower the version floor without verifying against that binary.
  Routine capture must not launch `auth status` as a preflight or to fill the plan pill:
  that short-lived command can abandon renewal. Use a plan label in the captured text or
  omit it. This reduction does not resolve the upstream print/PTY shutdown limitation.
  **The PTY launch must carry the Remote Control opt-out** (`interactiveArguments`: inline
  `--settings` with `disableRemoteControl`/`remoteControlAtStartup:false`, plus the workspace's
  `.claude/settings.local.json`): with auto-connect on, every bare interactive `claude`
  registers a claude.ai session. Keep the print path's argv unchanged. See
  `docs/solutions/claude-print-mode-usage-probe.md`.
- **`ClaudeUsageParser` is pinned to the current `/usage` layouts.** It keys on stable shapes
  ("Current session", "Current week (…)", "N% used", "Resets …"), not line positions, and
  fails safe (empty → transient stale). It reads both the interactive panel (label line, then
  bar/percent lines) and the print-mode report ("Current week (Fable): 7% used · resets …"
  on one line). If Claude redesigns either, update the parser and the fixtures in
  `ClaudeProviderTests.swift`; use `--probe-claude` to see the live capture.
- **Claude `/usage` captures can be valid but partial.** The current-session and overall-weekly
  windows may be fresh while a separately rendered or rate-limited model row such as
  `Weekly (Fable)` is absent. Do not mark the whole snapshot stale, silently stamp a retained
  row with the new capture time, or keep its numeric value past reset. `UsageContinuityPolicy`
  owns the per-window lifecycle: retain the row as `.stale` with its original observation time,
  change it to `.unavailable` (and hide the old percentage) after its validity window, then
  remove it after the bounded fallback lifetime. Only a fresh source row returns it to `.live`.
  Preserve this provenance through the continuity cache and widget projection; bump the widget
  schema for any incompatible freshness semantics. See
  `docs/solutions/logic-errors/claude-partial-usage-window-freshness.md`.
- **Codex window kind comes from `limit_window_seconds`, NOT the primary/secondary slot**
  (`#codex-window-kind`, `CodexWindowClassifier`). Slot position is plan-dependent: the
  `prolite` plan returns its *weekly* window in `primary_window` with `secondary_window: null`,
  so the old slot-based mapping mislabeled it "5-hour" and dropped the weekly row. Codex tags
  each window with `limit_window_seconds` (18000 = 5h, 604800 = 7d); classify off that, falling
  back to the slot only when the field is absent. Verify fixtures against a live capture with
  `--probe-codex` (or curl `chatgpt.com/backend-api/wham/usage` with the `~/.codex/auth.json`
  token) — the DTO field names in `UsageDTOs.swift` were originally speculative.
- **Codex banked resets come from `wham/usage` only.** `rate_limit_reset_credits.available_count`
  is Codex-only metadata on that same poll. A missing key is not reported; a present JSON
  `null` is reported zero. The plan capsule opens on its own only while a live 5-hour or
  weekly window is Critical (≤15% remaining), not at Low. The credits endpoint is unused:
  Headroom never redeems. Inspect every capsule state with `--demo banked-resets`. See
  `docs/solutions/codex-banked-resets.md`.
- **PTY probe robustness is intentional** — hard deadlines, guaranteed process-group kill,
  quiet-period capture across re-renders, login-shell PATH resolution (works from a bare
  Finder-launch env), off-main-actor. Preserve these when editing `ClaudeUsageCLIProbe`;
  the PTY path is the live fallback for CLIs below the print-mode version floor.
- **Claude's `.trust` and `.setup` handoffs must stay different scripts.** Until Sep 2026 both ran
  bare `claude`, because one launch covered first sign-in and the workspace-approval prompt. Bare
  `claude` only shows a login screen on a never-onboarded config, so a returning user landed on a
  prompt with a small "Not logged in · Run /login" footer. The `signIn` script fixed that, but its
  already-signed-in guard exits before the approval prompt can appear — route approval recovery
  through it and the card re-detects the approval need forever. Keep `.claudeTrustRequired` on
  `.openClaudeWorkspace` → `beginWorkspaceTrust`. Two more rules in the same script: the
  invocation must END with sign-in's saved status (`SetupCompletionCommand.wrap` records the last
  command's status, so a trailing `echo` would record every failed sign-in as succeeded), and the
  guard reads the `loggedIn` JSON field, never the status command's exit code, which was verified
  on one CLI version only. Script and manual command share one exported-subshell routing: a
  one-command env prefix would send an extra account's `auth login` to the default login.
  Startup questions (CLI 2.1.312's Chrome onboarding, and the unrecognized-screen fallback)
  reuse the `.trust` interactive launch, distinguished by
  `ClaudeInteractiveLaunchReason.startupQuestion`; never add a purpose or answer them for the user.
- **Codex setup must remain a CLI handoff.** Keep `CodexCLI.loginCommand`, provider recovery
  copy, Terminal execution, and clipboard fallback on `codex login`. Resolve the executable
  through `CLIExecutableResolver` so Finder launches still support Homebrew/NVM/asdf/mise
  installs; never place auth-file contents, provider responses, or caught errors in the
  generated script.
- **Codex keep-alive is not shipped.** A 2026-08-20 live gate ran official Codex CLI 0.147.0
  against a real isolated `CODEX_HOME` just over 8 days old with `codex exec --sandbox
  read-only --skip-git-repo-check --ephemeral`; the command succeeded but `last_refresh` did
  not advance. Never treat process success as token refresh. Revisit only with an account old
  enough to clear the CLI's actual threshold and require the auth timestamp to advance before
  adding warning or scheduler UI; see `BUGS.md`.
- **Compare `Date`s with `<` and `>` only (Nov 2026).** The macOS 27.2 SDK back-deploys
  concrete `Date <=`/`>=` behind a runtime "macOS ≥ 27.2" check; pre-release 27.2 build
  26B5086k passes the check but its Foundation lacks the symbols, so 1.6 (44) segfaulted
  ~4s after launch. Write `!(a > b)` / `!(a < b)`. `headroom_verify_macos_bundle` fails a
  build whose binaries import those operators.
- **ANSI stripping uses ICU escapes (`\x1B`), not Swift's `\u{1B}`** — the latter silently
  fails inside `.regularExpression`.
- Each Claude poll spawns a full `claude` process (print path ~3–5s including the auth and
  version pre-checks; the PTY fallback ~20–30s). Fine at the 5-min default; don't
  poll aggressively. **Polling is per account, not per sweep (Sep 2026).** Every account has
  its own due time (last attempt + the chosen interval, with growing backoff after transient
  failures and a four-interval wait for never-signed-in extras); each CLI lane (Claude, Grok,
  Cursor, Antigravity, Copilot, OpenCode) drains one probe at a time, primary first then most overdue, behind a **measured
  duty-cycle gate** — timer probes start only while the lane has been busy for at most half of
  the trailing window of twice the chosen interval. Codex's HTTP lane fetches its due accounts
  concurrently and is not gated. User actions (Refresh, Check Now, Try Again, Make Main, setup
  checks) are front-of-queue requests that bypass the gate; a full user refresh drains
  everything back to back by design. Settings → General shows a provider's effective interval
  when its accounts run slower than the chosen one. `isRefreshing` means user-initiated work
  only; timer passes never show "Refreshing…". Don't reintroduce a sweep-per-tick path or a
  computed stretch factor: the gate is measured from the probe log (`LaneSchedule`), so an
  outage clears within one normal pass. See
  `docs/solutions/architecture-patterns/per-account-polling-measured-duty-cycle.md`. **Export rule
  (amended Oct 2026, iPhone parity KTD8):** a main account's merge writes the Mac widget file and
  reloads its timelines; every merge, extras included, marks the phone path dirty
  (`exportPhoneSyncSnapshot()`), and an extra's merge never reloads Mac WidgetKit timelines. A
  full refresh exports once at its end. The publisher coalesces, so this is never a write per merge.
- **Every `UsageStore` change the phone can see must call `exportPhoneSyncSnapshot()`.** Account
  add/rename/remove/Make Main, the display setters, `reschedulePolling`, widget selection, the
  Spark, provider and reminder switches and "Use email as account name" all do; nothing calls it for you. `PhoneExportTriggerTests`
  covers them, so add a case there with any new phone-visible setting.
- **Per-account isolation is env-var based and verified**: a fresh `CLAUDE_CONFIG_DIR`
  reports "Not logged in · Please run /login" and a fresh `CODEX_HOME` reports "Not
  logged in"; a fresh `GROK_HOME` is isolated the same way, and a fresh OpenCode home (all four
  XDG variables set) reads `data: null`, signed out, while a signed-in one reads only its own
  workspace. The CLIs never fall back to
  the default login. Don't "simplify" account
  probes by dropping the env override; that would silently read the wrong account.
- **Provider capability stays separate from account login state.** `UsageStore` withholds
  capability-failure snapshots from the ordinary account-completion path and instead sends
  `ProviderCapabilityState` through the typed `receiveCapabilityFailure(_:for:)` coordinator
  channel. `confirmedAbsent` immediately fails only sessions awaiting final verification;
  `inconclusive` remains verifying until a live result or the scheduler-driven stop-loss.
  Don't re-enable snapshot notifications or translate capability failures into generic retry
  exhaustion; that loses provider scope and Codex's typed completion outcomes.
- **Claude executable discovery is refresh-generation/epoch scoped.** Timer probes in one
  Claude lane pass share one negative search; a user-requested probe served inside a pass
  runs under its own generation (KTD8, 2026-09-19 polling plan). A user action (`Check Now`, provider
  `Check Again`, opening setup, or adding an account) advances the locator epoch and forces a
  fresh search at the app boundary. Results may publish hints, negative memo state, or
  launch-race state only while their starting epoch is current, and every search started in
  an invalidation generation stays inconclusive even if it completes after that generation.
  Keep this in-memory and Claude-only; do not replace it with a wall-clock TTL or extend it
  to Grok/Cursor without the characterization fixtures tracked in BUGS.md.
- **Grok billing is ACP-first with an HTTP fallback (transport swap, not a parser fix).**
  `GrokFallbackUsageSource` tries the `grok agent stdio` ACP `x.ai/billing` method, then
  the CLI billing HTTP path (some CLI versions return JSON-RPC `-32601` for the method).
  Both hit the same free status method. The source model requires a genuine period end;
  if it's absent Headroom fails safe to a transient stale snapshot because
  `UsageWindow.resetSchedule` must contain genuine scheduled evidence rather than an
  invented deadline. Decode
  preferred+fallback fields (schema migrated recently, deprecated cent fields) — don't
  "fix" the parser when the source changed. `GROK_HOME` isolation is verified the same way
  as Claude/Codex; re-diagnose with `--probe-grok`.
- **Cursor usage comes from driving the official `cursor-agent` `/usage` TUI panel in a
  PTY** (`CursorUsageCLIProbe`), same official-client boundary as Claude — never reuse
  `WorkosCursorSessionToken`, read `state.vscdb`, or call private dashboard endpoints (ToS
  §1.5). Load-bearing PTY details: answer the OSC 11 background query or the first paint
  stalls, but only once the query appears in the output — the signed-out screen ("Press any
  key to log in...") sends no query and opens a browser login on any byte, and `status` can
  still report signed in while the TUI shows it (2026-09-30), so classify it as login-required
  before writing anything; send Enter as Kitty CSI-u (`ESC [ 13 u`); two positive gates before that single
  Enter — the `Ask (shift+tab to cycle)` ready prompt **and** the arrow-selected `/usage`
  autocomplete row. The selection gate matches `/→\s+\/usage(?:\s|$)/`: the live TUI pads
  the arrow with a *variable* number of spaces (`→  /usage`), so match whitespace-count-
  tolerantly but keep `/usage` a whole token — never relax it to bare substring presence,
  which would let a stray Enter submit a model prompt. The probe passes `--trust` for
  its own empty `CursorProbe` workspace only; a trust or MCP screen that still appears
  (older CLIs, or a gate painted after the ready frame) is classified and handed to the
  user in Terminal, never typed into. **The current subscription table has two named source
  rows:** `Auto` maps empirically to the customer-facing **Cursor Models** pool and `API` maps
  to **Other Models**. Cursor Agent `2026.09.18-9a7762b` returned 1% and 3% respectively, which
  matched the same account's Plan & Usage screen; Cursor documents the product pools but not
  those CLI source-label mappings. Parse the rows only from one coherent panel candidate whose
  later On-Demand row proves the table completed. Both rows produce two lanes, one recognized
  row produces that one lane, and a completed parent-only layout falls back to `Included`.
  Incomplete, cross-repaint, or unknown-sibling layouts fail stale. Never render `Included`
  alongside named pools or claim it is their sum, maximum, or authoritative aggregate.
  `--probe-cursor` must list every parsed subscription window without exposing the raw panel,
  credentials, account email, or account identifier. Cursor is single-account (no
  config-home isolation equivalent to `CLAUDE_CONFIG_DIR`/`CODEX_HOME`/`GROK_HOME` was
  found). Re-diagnose the panel with `--probe-cursor`; see
  `docs/solutions/cursor-agent-usage-feasibility.md`.
- **Grok/Cursor bill as period pools, not rolling windows.** Both use
  `.billingPeriod(label:duration:)` (`BillingPeriodWindowClassifier`), which the widget
  projector maps to `.other(label)`. Their brand marks are **monochrome**, so unlike the
  single-color Claude/Codex SVGs they ship a light/dark pair: the macOS popover selects by
  `ColorScheme` (`ProviderStyle.svgResourceName(for:scheme:)` → `grok-light`/`grok-dark`,
  `cursor-*`), and the `BrandIcons.xcassets` imagesets carry a `luminosity` dark appearance
  so iOS and the widgets adapt natively. Accent/text-accent/optical-scale values are
  first-pass identity (Phase 2 owns visual density). OpenCode's mark is monochrome too and ships
  the same pair (`opencode-light`/`opencode-dark`), and so does Antigravity's
  (`antigravity-light`/`antigravity-dark`, LobeHub `@lobehub/icons-static-svg` 1.102.0, MIT). The
  every-provider demo is `--demo six-providers` (popover) / the `sixProviders`
  `DemoScreenshotData` and companion demo variant (iOS widget and the Lock Screen demo); it now
  carries all seven providers, Antigravity included, under the old name.
  `five-providers`/`fiveProviders` keep Claude, Codex, Grok, Cursor and Copilot, and `multi-4`/`fourProviders` Claude, Codex, Grok and Cursor. `multi-5`
  means five accounts, not five providers.
- Copilot reads the official CLI's own output and never sends a prompt (Nov 2026).
  `CopilotProvider` combines two things the official `copilot` CLI produces: the
  `session.usage_record` and `quotaSnapshots` events in its session logs under
  `~/.copilot/session-state/` (`CopilotUsageLedger`), and `ping`, `auth.getStatus` and
  `account.getQuota` on its local stdio server (`CopilotStatusSource`, hour-long cache). The
  shown figure is the newest dated count plus every credit recorded after it; a server reading
  is only a lower bound (it is rounded to 0.5% and cached upstream), and a cached 0 never counts.
  Those logs also hold prompts and tool output: the ledger decodes only usage records and keeps
  no prompt or tool content, and the privacy policy says so. Never call `copilot -p` or open a
  session to refresh usage (that spends credits), never read a Copilot or `gh` token, and never
  call GitHub's private `copilot_internal` endpoints. The server and the sign-in handoff clear
  `COPILOT_HOME`, `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` and `GITHUB_TOKEN` so they read the same
  default login. No reading yet (fresh sign-in, no logs this month, zero or unlimited
  entitlement) is a `.live` snapshot with one `.unavailable(since: monthStart)` row, so setup
  completes and the row prints no number; `--demo copilot-no-reading` poses it. Sign-in is
  `copilot login` in Terminal through `SetupSessionCoordinator` (`CopilotCLI`). Re-diagnose
  with `--probe-copilot`; see `docs/solutions/copilot-cli-usage-feasibility.md`.
  Parity exceptions, each forced by the CLI boundary:
  - Single account: a Headroom-owned `COPILOT_HOME` never receives the session logs.
  - No API spend row: Copilot bills credits inside the subscription, and GitHub's published
    user billing endpoint needs a `gh` scope Headroom does not ask for and is unevaluated.
  - No plan label: the CLI reports an entitlement, not a plan name.
  - Use-it-up reminders fire only near a fresh reading: the row turns last known 15 minutes
    after the newest log or server evidence, and reminders never evaluate stale rows.
  - Use from other clients (VS Code, github.com) is missing until a quota snapshot or a server
    reading includes it, so the meter can overstate the room left.
- **OpenCode reads the official 2.x client's own usage read and nothing else (Nov 2026).**
  `OpenCodeCLIUsageSource` runs `opencode api --standalone experimental.usage.limits` and parses
  its one JSON line: Go's `rolling`, `weekly` and `monthly` windows, mapped by name to 5-hour,
  weekly and `.billingPeriod("Monthly", 30 d)`, with `resetsAt` in milliseconds. The client makes
  the Console requests; Headroom never reads OpenCode's credential store, never calls
  `opencode.ai` itself, never runs `opencode service`, never runs `opencode auth export`, and never
  runs any `opencode api` operation other than the usage read and the operation list
  (`api --standalone GET /openapi.json`, only after an exit-1 run with empty stdout). The one
  other read is `auth list --standalone --format json` after a `data: null` reading, decoding only
  each connection's `type` and `method`. `OpenCodeCommand` is that closed set; keep it closed.
  Rules that are load-bearing:
  - Every server-backed command passes `--standalone` (a private child server on 127.0.0.1 that
    refuses any request without its per-run password). Only `--version` runs without it.
  - The floor is 2.2.0. Below it Headroom shows "Go usage needs OpenCode 2.2 or newer" with
    **About OpenCode 2** and never runs `api` or `auth`: on 1.x they fall through to the TUI.
    Even a 1.x `--version` writes to its home, and a 2.x client migrates a 1.x home one way, so
    never point a 2.x binary at a real 1.x home in testing. The version verdict is memoized per
    symlink-resolved path and modification date both ways, so an unchanged too-old binary is not
    asked again on timer polls; a user request (Check Now, setup checks) always asks again, which
    is the only way a version-manager shim that swaps versions behind an unchanged file is seen.
  - Classify from exit status and stdout only (`OpenCodeUsageClassifier`); stderr is discarded.
    Error messages match fixed phrases pinned to captured fixtures, and every unmatched case is
    transient, never a sign-in prompt. The message carries the Console URL: never log or show it.
  - Every spawn clears all inherited `OPENCODE_*` and XDG variables, then sets only
    `OPENCODE_DISABLE_MODELS_FETCH=1`, `OPENCODE_DISABLE_AUTOUPDATE=1`, the account's four XDG
    values and the login PATH, from a working folder outside any git repo. The sign-in script
    shares that rule (`OpenCodeCLI.shellEnvironmentLines`). A user who signs in only through
    `OPENCODE_API_KEY` therefore reads as signed out.
  - A workspace without Go is a `.live` reading with one unavailable Monthly row and
    `planStatus = .noActivePlan`: setup completes, the card shows "No Go plan on this workspace"
    with **See Go Plans** and no meter, and the phone shows the plan name "No Go plan".
  - `limited: true` forces a window to 100% used. The Standard card adds a red
    `UsageLimitSentence` for a live limited window with a future reset; it never says what Go does
    at a limit. Compact (KTD15, every provider): a live or stale window at 100% takes a shown slot
    from the shown window with the most room, and the row stays one line; a usage state never
    switches it to the Standard section.
  - Every built-in sign-in path (Sign In, Sign In Again, Try Again, Sign Out & Set Up Again) shows
    `BuiltInSignInConfirmation` first, every time, because it adds a Console login to the user's
    own OpenCode and makes it active (a saved key stays saved). Extra accounts never ask.
  - The DEBUG-only `--opencode-executable <path>` reaches extra accounts and a probe with
    `--opencode-home`, never the built-in home. Agents test with the official client against
    `Scripts/opencode-stub-console.py` in scratch homes made by `Scripts/opencode-qa-home.sh`
    (pinned 2.2.5, SHA-256 checked); demos, harnesses and the XCTest host never start the client
    (`AppComposition.usesInertOpenCode`).
  - The response carries a workspace ID, name and Console URL; none is decoded, stored or shown
    (KTD19), and the privacy policy says so. Each built-in poll leaves OpenCode's normal log entry
    in `~/.local/share/opencode`.
  OpenCode reaches the phone, widgets, the Lock Screen provider choice and Siri like the others;
  phones need the paired iOS build to show it. The fixtures are stub-derived except `go-real`, a real Go response captured 2026-11-13 at 0%
  used; a non-zero percentage, a limited window and a lapsed subscription have not been seen on a
  real account (BUGS.md). Re-diagnose with
  `--probe-opencode`; see `docs/solutions/opencode-cli-usage-feasibility.md`. Parity exceptions:
  - No API spend entry (D1): OpenCode exposes no pay-as-you-go balance.
  - One workspace per home: the client reports only the active Console workspace, so a second
    workspace is a second Headroom account.
  - No limited sentence on the phone: the sync format carries no limited flag, so a limited window
    reaches the phone, widgets and Lock Screen as 100% used with its reset.
  - No default-login identity yet (see the table above).
- **Antigravity reads the official `agy` CLI's no-turn slash-command answers and nothing else
  (Nov 2026).** `AntigravityCLIUsageSource` runs `agy -p "/usage" --output-format json`, then
  `agy -p "/credits" --output-format json`, from Headroom's own working folder
  (`AntigravityCLI.defaultWorkingDirectory`), and parses each JSON result: two quota pools, each with a 5-hour and a weekly
  bucket, plus the AI-credits balance. `agy` answers both without an agent turn (1.1.11 and
  later). Headroom never reads an Antigravity credential, cookie or Keychain item, never talks to
  the IDE's language server and never calls Google itself. `AntigravityCommand` (`--version`,
  `/usage`, `/credits`) is a closed set; keep it closed and never run `agy -p` with any other
  prompt. Rules that are load-bearing:
  - Never pass `--disable-slash-commands`. Slash expansion is what routes `/usage` to the no-turn
    answer; without it the text is a model prompt.
  - Every capture checks `num_turns` and every token count. A nonzero one, or a `SUCCESS` result
    with no `command`, is `unsupportedClient` and sticky: no routine poll spawns `agy` again until
    its resolved path or modification date changes, and a user request runs only `--version`
    ("Headroom paused Antigravity reads after an agy change. Contact support", **Check Now**).
  - A signed-out `agy` answers `/usage` by opening an interactive Google sign-in in the browser
    and waiting up to 60 s; the CLI documents no way to turn that off. Stderr is watched only for
    `Authentication required`: at that marker the process group is killed and the account is
    signed out, sticky until a user request (Refresh, Check Now, or the check after the sign-in
    handoff). So a sign-out costs at most one browser tab (BUGS.md). Never add a routine path
    that spawns `agy` while signed out, and never probe it with an isolated empty `HOME`.
  - Signed out only from that marker. Everything else unmatched, including an `ERROR` result
    that says authentication failed, is transient.
  - Map buckets by `id` prefix (`gemini-*`, `3p-*`) and `window` (`5h`, `weekly`), never by
    display text. The rows are `.other("Gemini 5h")`, `.other("Gemini weekly")`,
    `.other("Other 5h")` and `.other("Other weekly")`; these labels are stored IDs and must never
    change. "Other" is Antigravity's "Claude and GPT models" group ("Claude & GPT" truncated in
    the Standard card). The Gemini group's own description names Gemini 4 Argon; Gemini app,
    Gemini CLI and Gemini API allowances are not measured. Within a pool the row with less left
    comes first, so Compact shows one meter per pool and single-slot surfaces headline the row
    with the least left across both pools.
  - Credits become the plan badge (for example "1,200 credits") only when above zero. A credits
    failure never fails the usage reading.
  - Sign-in is `agy acp --login` in Terminal ("Log in with Google interactively, then exit"),
    exit-signalled; no check runs while it is open. That it stores the login where `agy -p` reads
    it is not live-verified.
  - The floor is 1.5.9, the version the bucket shape was captured on; older shapes are
    unverified. Demos, harnesses and the XCTest host never start `agy`
    (`AppComposition.usesInertAntigravity`).
  - Seven providers: Settings pill wells wrap four over three above six cards (six or fewer keep
    one row, so every user sees the wrap because Antigravity is always registered),
    `HalftonePillRow` draws up to seven pills, and the companion flush bound is the provider count
    plus two.
  Antigravity registers between Cursor and Copilot, so its card sits directly above Copilot
  and OpenCode stays last; the append-only stored enums (`UsageSurface`,
  `LockScreenProviderChoice`, `PlanStatus` raw values) keep it appended at the end.
  Antigravity is off by default and reaches the phone, widgets, the Lock Screen provider choice
  and Siri like the others. The fixtures come from a live 1.5.9 capture except the synthetic
  signed-out one. Re-diagnose with `--probe-antigravity`; see
  `docs/solutions/antigravity-cli-usage-feasibility.md`. Parity exceptions:
  - Single account: `agy` keeps its login in its own home and the Keychain, isolating a second
    account is unproven, and probing a signed-out home opens a browser sign-in.
  - No API spend entry: `GEMINI_API_KEY` billing is a different allowance.
  - No default-login identity (see the table above).
  - A sign-out shows once per user request rather than being re-checked on every poll.
- **The menu bar sloshes and prints its first live reading (Oct 2026).** A pill's liquid surface travels
  while its provider's main account is being probed, timer polls included
  (`UsageStore.menuBarUpdatingProviders` → `MenuBarSlosh` → `VesselGlyph` wave frames). The
  level never moves and the numeral still hard-cuts (M10A); a pill finishes its wave before
  going flat. A pending main shows a 3×6 halftone ghost; its first live reading prints in
  four frames at 10fps, while stale results and main-account switches never print (KTD13).
  Reduce Motion keeps the wave flat and blends ghost to solid uniformly. Settings previews
  use the same ghost image path with motion disabled. Keep this label one rasterized Image:
  nesting `LoadingTimeline` in `MenuBarExtra` reproduced an endless status-button update loop
  during App test bootstrap. `MenuBarSlosh` owns its small bounded clock instead, deriving
  frames from Core's wall clock and stopping after the wave/print deadline (KTD17 exception).
  The popover footer's stamp turns into a
  per-account receipt during a user refresh (`refreshProgress`, Core `RefreshReceiptPresentation`, shared with the phone's check-now line). Both come
  from the scheduler's probe and user-progress callbacks (decisions S2 and W4).
- **Check-now (Oct 2026, iPhone parity U6) joins one full refresh.** `refreshAll()` keeps one
  in-flight full-refresh task (`fullRefreshStartedAt`); every other caller — popover, launch, a
  phone request — awaits it, and `lastFullRefreshCompletedAt` starts a 60 s cooldown. A phone
  request (`headroom.sync.v4.request.<deviceUUID>`) reaches `CheckNowCoordinator` through the
  iCloud observer and one launch scan, never under `--demo` or a test host. Finish is a forced
  publish whose manifest echoes the stamped answer, then the finished receipt (KTD14.5); never
  write the receipt first. The phone matches its own request ID only and shows "Just now" only
  after assembling `finishedGeneration` (`Sync/CheckNowProtocol.swift`). Single-account checks,
  setup checks and spend-only refreshes never answer a request. Timing constants are
  provisional until the two-device check-now latency spike runs. The phone sends requests
  only when the resolver's winner is v4; a Mac on 1.4.1 or older only gets a re-read.
- **The v3 key must stay readable by build 33.** `Build33DecoderGoldenTests` runs the Mac's v3
  output through a frozen copy of that decoder; never weaken it. The Mac's random lineage UUID
  goes only in `companionSourceID`, never in v3's `sourceID`, which build 33 prints as "<sourceID>
  on Mac". Retire v3 later by writing a higher inner schema, never by deleting the key.
- **Digests cover the exact stored bytes.** The manifest's per-provider SHA-256
  (`CompanionSyncCodec.digest`) is computed over the raw `Data` written to, or read from, the key.
  Hashing a decoded-and-re-encoded payload breaks as soon as a newer Mac adds a field.
- **The scope marker lives outside the v4 namespace on purpose.** `headroom.scope.v1` must never
  match a `headroom.sync.v4.` prefix sweep, sync-off cleanup or launch scan. Phone processes
  write it only when absent and the Mac never does; never write a remembered value from memory or
  the sidecar, or a marker could carry one account's scope into another's store.
- **Feedback is an email the user sends, never a request Headroom makes (Nov 2026).**
  Settings › About › Send Feedback on the Mac (`FeedbackMail`; the row reads "Email ↗" like the
  other About links, and copies the email when no mail app opens) and the iPhone About row
  open a pre-filled `mailto:` to `support@zantos.co`, which Google
  Workspace forwards into Linear's email intake. Core `FeedbackEmail` builds every email from
  closed enums and shape-checked CLI versions (`FeedbackCLIVersion`, `CLIVersionReader`,
  `FeedbackDiagnosticsCollector`); it never takes a `UsageSnapshot`, so emails, account
  names, plan names and `FailureReason` messages cannot reach it. Keep it that way, and keep
  the `mailto:` under 1,800 characters (the clipboard fallback carries the full text). Demos
  and harnesses read no CLI and open no mail app (`AppComposition.usesInertFeedback`). Don't
  add an in-app sender, an
  endpoint or analytics without a new plan: the privacy policy promises Headroom sends
  nothing itself.
- **An account change is one record commit, then its mirrors (Nov 2026).** `UsageStore.merge`
  calls `defaultLoginPrior` first, before the reliability note and the sign-out edge. A change
  commits `defaultLoginRecords.v1` once with a `pendingMirror`, then writes the registry label,
  the row's reminder entries and the continuity record, then clears the marker. The launch
  repair finishes a change a crash interrupted and drops a saved reading another build rewrote
  (a continuity record is the bound account's when it carries that digest, or carries none and
  has the capture time the slot last accepted). Keep that order, keep the reminder stores keyed
  by `AccountKey`, and add no field to `ProviderAccount`: `Release162FrozenStores` decodes every
  existing store the way 1.6.2 does. Any new per-account state needs a park-and-restore path
  here, or it carries from one account to the next.
- **Notifications (Sep 2026) are local Mac banners posted by the running app** — the use-it-up
  reminders (all providers and accounts) and the Codex-only banked-reset notice, set in Settings →
  Notifications. `NotificationCoordinator` (Core) runs only from `UsageStore.merge` on a `.live`
  snapshot and, per limit, only on a live window with a scheduled reset (KTD2); launch restore,
  lifecycle presets and failed polls never evaluate. Its ledgers (`UseItUpLedger`,
  `BankedResetNotificationBaseline`) are written only after the poster accepts a request (KTD6),
  and the banked baseline is **separate** from the capsule's `BankedResetAcknowledgements`, which
  counts a first-ever count as a rise (KTD7). `UNUserNotificationCenter.current()` raises an
  uncatchable exception without an `.app` bundle, so `UserNotificationClient` stays inert under
  `swift run`, `--demo`, `--render-popover` and `HeadroomAppTests` (KTD9) — verify real banners and
  the permission prompt on a built `Headroom.app`. The popover can't be opened programmatically,
  so a tap only activates the app (KTD8). Core never imports UserNotifications.

## Follow-ups

See `BUGS.md` for deferred items (backoff, Xcode signing for persistent permission grants).
Durable learnings live in `docs/solutions/`, filed by category (`ui/`, `logic-errors/`,
`architecture-patterns/`, …) with YAML frontmatter (`module`, `tags`, `problem_type`): provider
parsing, continuity, polling, setup handoffs, and SwiftUI layout and motion. Relevant before
changing those areas. `CONCEPTS.md` holds the shared domain vocabulary (pill, automatic
summary, pill value, shelf).
Codex field names are now verified against a live `wham/usage` capture — see the
`#codex-window-kind` gotcha above and `docs/solutions/codex-window-kind-mislabel.md`.
Banked reset credits on that same response are recorded in
`docs/solutions/codex-banked-resets.md`.
