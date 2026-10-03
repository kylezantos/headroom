# AGENTS.md — Headroom

Project-specific guidance for AI agents working in this repo. Read this before making
changes.

## What this is

A native macOS 15+ menu bar app (Swift 6 / SwiftUI) showing remaining AI-subscription
usage — 5-hour and weekly windows, reset times, manual renewal dates — for **Claude** and
**ChatGPT/Codex**, behind one provider abstraction so more can be added. Tahoe uses Liquid
Glass; Sequoia uses a native material popover surface.

## Product principles (Sep 2026)

- **The goal is real-time usage data for every provider and every account, as smoothly,
  reliably, and solidly as possible.** A growing number of people rely on Headroom to manage
  their usage; reliability and honesty of the numbers come before new surface area.
- **Provider parity by default.** Any feature, enhancement, or behavior change applies to all
  providers (Claude, Codex, Grok, Cursor) and to every account of each, unless a provider's
  transport or official-client boundary genuinely prevents it. When parity is not possible,
  say so explicitly in the plan, PR, or reply, with the reason, rather than silently scoping
  the change to one provider. "Cheap for this provider" is never a reason to leave it out.

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
    DTOs), `CodexConnection`, shared login-shell `CLIExecutableResolver`, `RedirectBlocker`,
    `AccountStorage` (per-account config homes).
  - `Credentials/` — `CredentialStore` (Codex-only), `CodexAuthReader`, `Redaction`.
  - `Engine/` — `PollingEngine` (wake timer), `LaneSchedule` (pure cadence decisions),
    `AccountProbeScheduler` (per-lane due queue), `UsageStore` (`@MainActor @Observable`).
  - `Settings/` — `Preferences` (UserDefaults), `AccountRegistry` (persisted account
    catalog, capacity-aware; the tested envelope is 20 per provider), `LaunchAtLogin` (SMAppService).
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
bind to the `@Observable` store.

The popover meter style is one global `MeterStyle`, persisted as three independent
UserDefaults-backed preferences (format, shape, fill) and mirrored by `UsageStore`. It affects
only the macOS popover: widget, phone, and menu-bar projections intentionally carry no style.

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
Widgets & iPhone previews the styles but never sets them. Plan:
`docs/plans/2026-10-02-1247-feat-widget-styles-plan.md`.
Tube remains a stored shape when Full is selected, but `GaugeShape.resolved(for:)` renders it
as Chip until the user returns to Micro.

### Multi-account (Jul 2026)

Claude, Codex, and Grok each carry any number of signed-in accounts up to a **tested
envelope** of 20 (`AccountRegistry.testedEnvelope`, Sep 2026 — the bound the suites and the
`multi-20` demo exercise, not an advertised limit); Cursor is deliberately
single-account because its CLI exposes no isolated config-home mechanism. Snapshots are keyed
by `AccountKey` (provider + account); one `UsageProvider` instance exists per account. The
**built-in** `.primary` account reads the CLI's default config (`~/.claude`, `~/.codex`,
`~/.grok`) exactly as before — zero migration for existing installs. **Extra** accounts get
Headroom-owned config homes under `~/Library/Application Support/Headroom/Accounts/…` and
route the same compliant paths there: the Claude probe runs with `CLAUDE_CONFIG_DIR` set,
Codex reads the `auth.json` that official `codex login` wrote under that account's
`CODEX_HOME`, and Grok reads the `auth.json` that `grok login` wrote under `GROK_HOME`.
Codex and Grok offer account-scoped device-code handoffs as well as standard login. Sign-in
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
Code**. Codex, Grok and Cursor keep their 3/7/15/30-second ladder.

Each provider has a persisted primary selection. **Make Main** reorders the selected row to the
top, refreshes only it, and immediately reroutes the menu bar, widgets, phone projection,
capability recovery, and the never-signed-in timer exemption. A dangling primary pointer falls
back to canonical order without writing defaults and is retained in case the row resurfaces.
The popover still shows all accounts at the regular meter scale and the card list scrolls past a
640pt cap. Account management lives in Settings → Accounts (`AccountsSettingsTile`), where each
provider group header also carries the subscription on/off switch (off means not fetched, never
unmanageable); removing
an **extra** account deletes its Headroom-owned config home, while the **built-in** account can
only be *stop-tracked* (Aug 2026): a persisted registry tombstone hides the row without touching
the CLI's own config or login, allowed only while another account exists, undone via "Show CLI
Account" in the provider header. Claude rows signed in to the same upstream login (matched by
`oauthAccount.accountUuid`, metadata only) get a detection-only "Same login as X" badge —
never auto-merged.

## Commands

```bash
swift build                        # HeadroomCore + Headroom
swift test                         # unit suite (fast, all mocked — no CLI/network/Keychain)
./Scripts/build-app.sh --deps-only && xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' -derivedDataPath ./.xcode-derived test
# --deps-only unpacks the Sparkle XCFramework the project references (package resolution alone doesn't); the pinned derived data avoids a cached "no XCFramework found" build description.
swift run Headroom --probe-claude  # diagnostic: prints live parsed /usage windows
swift run Headroom --render-widgets <dir> [--widget-style <id>] [--widget-fixture <name>] [--widget-quick]  # headless widget-style renders + overflow sweep
swift run Headroom --demo [multi-2|multi-3|multi-5|multi-20|multi-mixed|spend-states|spend-retained|banked-resets]  # live app with fixture data (screenshots, multi-account preview; multi-20 is the tested envelope)
./Scripts/build-app.sh             # → Headroom.app (LSUIElement), then: open Headroom.app
```

## Website DMG releases

For any request to prepare, publish, or ship a new public Headroom DMG, use the repo-local
`release-website-dmg` skill. Its authoritative runbook is
`docs/release/website-dmg-release.md`; it covers Developer ID signing, notarization, the
Sparkle appcast, Headroom website deployment, and the required installed-app update acceptance test.
The public domain is `headroom.zantos.co`. Its dedicated Vercel project and private website
repository are both `headroom-site`; `kz-portfolio` no longer publishes Headroom releases.

For a coordinated release that also includes TestFlight or App Store work, begin with
`docs/release/release-operations.md`. Keep macOS publication, Sparkle acceptance, TestFlight
upload, TestFlight availability, device acceptance, and App Review submission as separate states;
never collapse them into a generic “released.” Preflight dedicated test environments and manual
security/browser handoffs before publishing. Do not brute-force menu-bar UI, configure iPhone
Mirroring during a release, or use broad process termination to clean up QA copies.

Building requires Xcode 26.6 / Swift 6.3.3. The app targets macOS 15+ on Apple silicon; a real
macOS 15 Apple-silicon runtime smoke is required before advertising Sequoia support. Claude
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

- **The Claude probe is print-first, PTY-fallback.** `ClaudeUsageCLIProbe` first runs
  `claude -p "/usage" --no-session-persistence` (non-interactive, ~2s, atomic report — no
  TUI repaints to garble labels, no partial paint of the separately fetched model rows).
  That path is version-gated to ≥ 2.1.217, the oldest CLI verified to dispatch `/usage`
  locally in print mode — below the floor an unverified CLI might forward "/usage" to the
  model as a paid prompt, so older CLIs use the PTY panel path unchanged. Any print miss
  (timeout, cost-report shape, unparseable output) also falls back to the PTY. Don't remove
  the PTY path, and don't lower the version floor without verifying against that binary.
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
- **ANSI stripping uses ICU escapes (`\x1B`), not Swift's `\u{1B}`** — the latter silently
  fails inside `.regularExpression`.
- Each Claude poll spawns a full `claude` process (print path ~3–5s including the auth and
  version pre-checks; the PTY fallback ~20–30s). Fine at the 5-min default; don't
  poll aggressively. **Polling is per account, not per sweep (Sep 2026).** Every account has
  its own due time (last attempt + the chosen interval, with growing backoff after transient
  failures and a four-interval wait for never-signed-in extras); each CLI lane (Claude, Grok,
  Cursor) drains one probe at a time, primary first then most overdue, behind a **measured
  duty-cycle gate** — timer probes start only while the lane has been busy for at most half of
  the trailing window of twice the chosen interval. Codex's HTTP lane fetches its due accounts
  concurrently and is not gated. User actions (Refresh, Check Now, Try Again, Make Main, setup
  checks) are front-of-queue requests that bypass the gate; a full user refresh drains
  everything back to back by design. Settings → General shows a provider's effective interval
  when its accounts run slower than the chosen one. `isRefreshing` means user-initiated work
  only; timer passes never show "Refreshing…". Don't reintroduce a sweep-per-tick path or a
  computed stretch factor: the gate is measured from the probe log (`LaneSchedule`), so an
  outage clears within one normal pass. See
  `docs/plans/2026-09-19-2217-feat-per-account-polling-schedule-plan.md`.
- **Per-account isolation is env-var based and verified**: a fresh `CLAUDE_CONFIG_DIR`
  reports "Not logged in · Please run /login" and a fresh `CODEX_HOME` reports "Not
  logged in"; a fresh `GROK_HOME` is isolated the same way. The CLIs never fall back to
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
  stalls; send Enter as Kitty CSI-u (`ESC [ 13 u`); two positive gates before that single
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
  first-pass identity (Phase 2 owns visual density). The four-provider demo is
  `--demo multi-4` (popover) / the `fourProviders` `DemoScreenshotData` variant (iOS widget).
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
  so a tap only activates the app (KTD8). Core never imports UserNotifications. See
  `docs/plans/2026-09-26-1111-feat-notifications-pane-plan.md`.

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
