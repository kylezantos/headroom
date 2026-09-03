# AGENTS.md — Headroom

Project-specific guidance for AI agents working in this repo. Read this before making
changes.

## What this is

A native macOS 15+ menu bar app (Swift 6 / SwiftUI) showing remaining AI-subscription
usage — 5-hour and weekly windows, reset times, manual renewal dates — for **Claude** and
**ChatGPT/Codex**, behind one provider abstraction so more can be added. Tahoe uses Liquid
Glass; Sequoia uses a native material popover surface.

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
  - `Engine/` — `PollingEngine`, `UsageStore` (`@MainActor @Observable`).
  - `Settings/` — `Preferences` (UserDefaults), `AccountRegistry` (persisted account
    catalog, max 5 per provider), `LaunchAtLogin` (SMAppService).
- `Sources/HeadroomApp` — SwiftUI `MenuBarExtra(.window)` shell + adaptive popover (Liquid
  Glass on Tahoe, native material on Sequoia), cards, settings, menu bar label.
  `MeterGauge` is the popover's single format × shape × fill renderer; `AppComposition` is
  the one place providers are wired. Settings (Sep 2026) is a fixed-frame
  `NavigationSplitView`: `SettingsView` owns every root state and dialog, `SettingsSidebar`
  lists the six `SettingsPane` destinations, and the stateless panes live in
  `SettingsPanes.swift`; Appearance previews choices with an inert `AppearanceSpecimen`.

Data flow: `PollingEngine` → `UsageStore.refreshAll()` fetches providers concurrently →
merges with continuity → menu bar label + popover bind to the `@Observable` store.

The popover meter style is one global `MeterStyle`, persisted as three independent
UserDefaults-backed preferences (format, shape, fill) and mirrored by `UsageStore`. It affects
only the macOS popover: widget, phone, and menu-bar projections intentionally carry no style.
Tube remains a stored shape when Full is selected, but `GaugeShape.resolved(for:)` renders it
as Chip until the user returns to Micro.

### Multi-account (Jul 2026)

Claude, Codex, and Grok can each carry up to 5 signed-in accounts; Cursor is deliberately
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
xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' test
swift run Headroom --probe-claude  # diagnostic: prints live parsed /usage windows
swift run Headroom --demo [multi-2|multi-3|multi-5|multi-mixed]  # live app with fixture data (screenshots, multi-account preview)
./Scripts/build-app.sh             # → Headroom.app (LSUIElement), then: open Headroom.app
```

## Website DMG releases

For any request to prepare, publish, or ship a new public Headroom DMG, use the repo-local
`release-website-dmg` skill. Its authoritative runbook is
`docs/release/website-dmg-release.md`; it covers Developer ID signing, notarization, the
Sparkle appcast, portfolio deployment, and the required installed-app update acceptance test.
The public domain is `headroom.zantos.co`.

For a coordinated release that also includes TestFlight or App Store work, begin with
`docs/release/release-operations.md`. Keep macOS publication, Sparkle acceptance, TestFlight
upload, TestFlight availability, device acceptance, and App Review submission as separate states;
never collapse them into a generic “released.” Preflight dedicated test environments and manual
security/browser handoffs before publishing. Do not brute-force menu-bar UI, configure iPhone
Mirroring during a release, or use broad process termination to clean up QA copies.

Building requires Xcode 26 / Swift 6.3. The app targets macOS 15+ on Apple silicon; a real
macOS 15 Apple-silicon runtime smoke is required before advertising Sequoia support. Claude
requires the `claude` CLI logged in; Codex requires its CLI-managed `~/.codex/auth.json`.
When Codex auth is missing or rejected, the app delegates recovery to official `codex login`
in Terminal and never owns the browser callback, token refresh, or auth-file writes.

## Conventions

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

- **Meter visual acceptance must use the live `MenuBarExtra` window.** Drive deterministic
  fixtures with `swift run Headroom --demo <scenario> --meter-style
  <format>.<shape>.<fill>` and inspect the native popover in both appearances. Do not accept
  `--render-popover` output as evidence while the Xcode 26.5 appearance-capture bug remains in
  `BUGS.md`; Core recipe tests prove decisions, not SwiftUI rendering or window sizing.

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
- **PTY probe robustness is intentional** — hard deadlines, guaranteed process-group kill,
  quiet-period capture across re-renders, login-shell PATH resolution (works from a bare
  Finder-launch env), off-main-actor. Preserve these when editing `ClaudeUsageCLIProbe`;
  the PTY path is the live fallback for CLIs below the print-mode version floor.
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
  poll aggressively. Configured Claude accounts are probed **serially in one Claude lane** while
  Codex/network work can overlap; the account cap and enforced 2-min interval floor bound cost.
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
  store refresh generation share one negative search. A user action (`Check Now`, provider
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
  which would let a stray Enter submit a model prompt. Cursor is single-account (no
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

## Follow-ups

See `BUGS.md` for deferred items (backoff, Xcode signing for persistent permission grants).
Durable provider and debugging learnings live in `docs/solutions/`; check them before changing
provider parsing or continuity behavior.
Codex field names are now verified against a live `wham/usage` capture — see the
`#codex-window-kind` gotcha above and `docs/solutions/codex-window-kind-mislabel.md`.
