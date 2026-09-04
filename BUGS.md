# Deferred / Follow-up

Non-blocking items. The earlier OAuth/Keychain-token approach and its U9 spike are **obsolete** —
Anthropic prohibits and blocks third-party subscription-OAuth use, so Claude now reads the
official `claude` CLI's `/usage` panel instead.

## OpenAI API-spend request remains unverified against a real key

- **Anthropic resolved 2026-08-10.** The real-key `HTTP 400` was caused by sending bare dates
  where the cost-report endpoint requires RFC 3339 timestamps. The provider now sends explicit
  UTC timestamps, requests daily buckets, follows `has_more` / `next_page` pagination without
  publishing partial totals, converts Anthropic's fractional cents to dollars, and returns a
  live current-month total through
  `--probe-spend anthropic`. `OpenAIAPISpendProvider` (`/v1/organization/costs`, `start_time`
  epoch + `bucket_width=1d`) is still unverified because no OpenAI admin key was available.
  xAI validated separately. Diagnostic:
  `swift run Headroom --probe-spend <openai|anthropic|xai> [--key-file <path>]`.

## Codex extra-account persistence is blocked on a valid live refresh gate

- **Do not ship the proposed pre-expiry warning or weekly keep-alive yet.** On 2026-08-20,
  official Codex CLI 0.147.0 ran successfully against a real isolated `CODEX_HOME` whose
  `last_refresh` was 8.01 days old, from a fresh empty working directory with `--sandbox
  read-only --skip-git-repo-check --ephemeral` and file credential storage. The command exited
  0 but did not advance `last_refresh`; it also reported 11,442 tokens for the minimal gate,
  so the proposed "tiny" weekly cost is not established. The lifecycle-overhaul plan's stop
  condition therefore blocked U8–U9 rather than shipping a placebo. Retry only with an isolated
  account comfortably older than the source threshold (at least the plan's 8.25-day example).
  Success must mean the timestamp advances and polling survives the old expiry; process exit
  alone is insufficient. If that still fails, abandon `codex exec` as a keep-alive mechanism.

## Claude CLI probe

- **Resolved upstream on 2026-07-20: the per-model weekly row ("Weekly (Fable)") returned in
  Claude Code 2.1.216.** Headroom's signed live probe parsed it again without a parser change.
  The prior source-side disappearance remains documented here because it can recur: on 2026-07-16
  the panel emitted only `Current session` and
  `Current week (all models)`, followed by a new "What's contributing to your limits usage?"
  attribution section. `ClaudeUsageParser` is **correct and unchanged** — `parsesSettledWindows`
  still passes against a fixture containing `Current week (Fable)` → `.other("Weekly (Fable)")`,
  so the meter will light back up on its own if the line returns. Don't "fix" the parser.
  - **The limit still exists.** claude.ai shows Weekly limits → All models 1%, Fable 1%,
    both resetting Thu 9:59 AM, matching the CLI's session 61% / all-models 1% exactly. So
    this is not a low-usage or fresh-week-reset artifact.
  - **It's server-side; downgrading is not a workaround.** Verified against all three cached
    binaries (2.1.209 / 2.1.210 / 2.1.211, each confirmed by its version banner) — none emit
    the row. 2.1.210 is what was running when the meter last worked, and it doesn't produce
    the row now either, so the client is not the variable. Also ruled out: model selection
    (forcing `ANTHROPIC_MODEL=claude-fable-5` changes nothing but the header) and viewport
    truncation (tested 24×80, 45×140, 100×200 — the tall run captures well past the `↓` fold
    and still has no Fable row; the only "Fable" string anywhere is the model name in the
    banner).
  - **~~No alternate CLI surface exists.~~ Superseded 2026-07-31:** `claude -p "/usage"`
    (print mode) dispatches the command locally and prints the full settled report —
    including per-model rows — as flat single-line text in ~2s, with no model call
    (`$0.0000`). The probe now uses it first, version-gated to ≥ 2.1.217, with the PTY
    panel as fallback. This removes the TUI capture/garbling failure class entirely; a
    genuine server-side omission (as below) still surfaces through the continuity policy.
  - **Open product question:** the row currently just vanishes silently, which reads as a
    Headroom bug to users (independently reported by a second user). Decide whether to
    surface "unavailable" or stay silent. Possibly moot — Anthropic is reportedly narrowing
    this to API spend after 2026-07-19 (user-reported, unverified, and their plans have
    shifted before), so prefer waiting over building anything elaborate here.
- **Parser is pinned to the current `/usage` layout.** `ClaudeUsageParser` keys on stable
  shapes ("Current session", "Current week (…)", "N% used", "Resets …") rather than line
  positions, but a future Claude Code redesign of the panel could still break it. It fails
  safe (empty result → transient stale), and the `--probe-claude` diagnostic makes drift
  easy to spot. Add a version check / update the fixture if the panel changes.
- **Each poll spawns a full `claude` process (print path ~3–5s; PTY fallback ~20–30s).**
  Claude accounts still run in one serial lane and the interval has an enforced 2-minute
  floor. **Partially discharged 2026-08-08:** all accounts in one timer refresh generation
  now share a negative executable-discovery verdict, so a missing CLI triggers at most one
  full path search per cycle. Successful `/usage` probes still run once per configured
  account; result caching or adaptive cadence could reduce that remaining cost.
- **No live integration test for the PTY probe.** Provider tests use a fixture panel +
  mock source (fast, deterministic). The real `ClaudeUsageCLIProbe` is verified manually
  via `--probe-claude`; a machine-dependent integration test would need the CLI logged in.

## Grok/Cursor executable locator characterization

- **Characterize before migrating either provider to the refreshable generic locator.** Claude
  now revalidates persisted executable hints and rediscovers path changes without relaunching.
  Grok and Cursor still use their existing executable-resolution paths. Before sharing Claude's
  locator, capture sanitized behavior for native, Homebrew, and version-manager installs; launch
  races; missing versus inaccessible candidates; Finder's sparse `PATH`; and each provider's
  account-home isolation rules. Preserve Grok's ACP/HTTP transport boundary and Cursor's guarded
  PTY input gates. This follow-up is characterization only until those provider-specific fixtures
  and a signed installed-app matrix exist.
  - **Characterized 2026-08-31 on the current macOS runtime.** Cursor Agent
    `2026.08.25-3e8eec8` at `~/.local/bin/cursor-agent` resolved and parsed the live Pro+ `/usage`
    panel both normally and with `PATH=/usr/bin:/bin`. Grok Build `1.0.13` at
    `~/.grok/bin/grok` resolved under the same sparse path and returned a live free-plan weekly
    window through the HTTP fallback. A signed-in isolated `GROK_HOME` returned the same live
    window; after official `grok logout` removed that isolated credential, the same probe returned
    login-required rather than falling back to the built-in account. Deterministic tests now pin
    the exact fallback order, version-manager precedence, Homebrew recovery after a shell miss,
    missing and non-executable fail-closed behavior, and launch-race `.cliNotFound` results. An
    Apple Development-signed bundle on macOS 26.5.1 also returned both live snapshots with the
    sparse path. Real Homebrew/version-manager installs and macOS 15 Sequoia remain unverified, so
    this does not yet authorize the locator migration. See
    `docs/solutions/grok-build-usage-feasibility.md`.

## Reliability (carried from earlier review)

- **No backoff on repeated failures.** Both providers retry every cycle at the fixed
  interval. Exponential backoff on consecutive transient failures would be gentler on a
  down endpoint. Design choice — deferred.

- **Menu bar stays silent when a CLI is dead.** Provider capability failures are transient
  reasons, so `MenuBarLabel.needsAttention` does not light up for a missing or undiscoverable
  CLI. This is an explicit current product decision: recovery remains in the popover and
  Settings rather than adding persistent menu-bar attention. Revisit only with a deliberate
  cross-surface attention design.

- **Grok storage-mismatch diagnosis remains reproduction-gated.** Codex maps wrapper-success /
  auth-absent case to the typed `codexStorageMismatch` recovery. Grok has no equivalent typed
  storage-mismatch diagnosis yet, so the user can fall back to generic reconnect/check behavior.
  Add the analog only after characterizing where supported Grok CLI versions store credentials
  under both the built-in home and an isolated `GROK_HOME`.
  - **Characterized without reproduction 2026-08-31.** Official device-code login on Grok Build `1.0.13`
    wrote a mode-`0600` `auth.json` containing one first-party OIDC record under both the default
    home and an explicit isolated `GROK_HOME`; each produced a live Headroom snapshot. Official
    logout removed only the isolated file, after which Headroom returned the typed auth-absent
    result. Standard `grok login` in a fresh isolated home also wrote the mode-`0600` file before
    its successful process exit and immediately produced a live snapshot; logout again removed
    only the isolated credential. The wrapper-success/auth-absent mismatch did not reproduce in
    either supported login flow, so do not add a distinct diagnosis unless a genuine
    success-without-file capture establishes one is necessary.

- **Grok subscription overage is decoded but deliberately unsurfaced.** `GrokDTOs` reads
  `onDemandCap`/`onDemandUsed`/`prepaidBalance` from the billing config additively, but no
  surface renders Grok subscription overage (Cursor's on-demand row ships via
  `CursorOnDemandSpendProvider`; xAI *API* credit balance ships via `XAIAPISpendProvider`).
  This is a recorded decision, not an oversight: we have no verified live capture of a
  subscription account with on-demand active, so any UI would be speculative — the same
  trap the original Codex DTO field names fell into. A sanitized free-plan capture on 2026-08-31
  confirmed all three fields exist but are zero (`onDemandCap`, `onDemandUsed`, and
  `prepaidBalance`), which strengthens the decoder evidence but does not validate active overage
  semantics or presentation. Revisit only with a capture where on-demand is genuinely active.

- **Billing-period resets keep the countdown, not the source's date style.** Cursor's own
  panel shows day-precision dates ("Resets Sep 12"); Headroom renders its universal bare
  countdown ("21d") derived from `resetSchedule`, with the verbatim label retained as
  non-visible provenance. Explicit product decision (2026-08-30): cross-provider
  consistency wins over per-source display mimicry.

- **In-app troubleshooting sheet is deferred.** The README matrix is the shipping self-serve
  path for the four providers. A discoverable interactive sheet spanning setup states, probes,
  privacy guidance, and account isolation needs its own information-design and accessibility
  pass rather than being folded into recovery-state hardening.

## Polish

- ~~App icon — user to provide.~~ Done: Vessel `AppIcon.appiconset` (16–1024), wired via
  `ASSETCATALOG_COMPILER_APPICON_NAME`. The artwork is full-bleed square PNG output so iOS,
  iPadOS, and macOS can apply their native icon shape without a second baked-in frame.
  Regenerate all sizes with `node Scripts/gen-app-icon.mjs` (master:
  `design/vessel-app-icon.svg`).
- `MenuBarLabel` uses a fixed font size (menu bar height is OS-constrained).
- **`--demo` writes Settings preferences to the standard defaults domain.** `HeadroomApp.init`
  builds `Preferences()` (`.standard`) and hands it to `SettingsView`, while
  `AppComposition.store` routes the store to the isolated per-launch demo suite, so in demo
  mode `appearancePreference`, `settingsPane`, `showMenuBarPercentage`, and
  `menuBarFillSource` land in the real domain despite the comment saying demo runs never
  touch user settings. Harmless for the unsigned debug binary (its own `Headroom` domain),
  but `Headroom.app --demo` would write into the user's settings. Found during the sidebar
  acceptance pass (2026-09-03).
- **A focused, uncommitted account rename can still be lost on ⌘Q.** R12's backstop commits
  pending renames in `AccountsSettingsTile.onDisappear`, which fires on pane switch and
  window close but is not guaranteed on app termination. Add an `NSApplication.willTerminate`
  commit if it matters in practice (code-review residual, 2026-09-03).
- **Reopening Settings after ⌘W restores keyboard focus into a renamed account field.** The
  rename commits correctly (R12), but SwiftUI restores focus to the last focused
  `TextField`, so that row reopens with its editing chrome while siblings look static.
  Cosmetic; consider clearing `focusedLabel` on disappear.
- **Menu Bar pane still lists providers whose subscription is switched off.** "Priority
  providers" and "Preferred window" iterate `registeredProviderOrder`, which ignores the
  per-provider surface switches now living in Settings → Accounts, so an off provider can be
  chosen as a priority and renders a neutral meter. Pre-existing before the sidebar redesign
  (2026-09-02); filter both rows by `isSurfaceEnabled` or show the off state inline.
- **App-boundary tests emit an AppKit re-entrant-layout warning under Xcode 26.5.** All six
  `HeadroomAppTests` pass, but loading the app test bundle logs that `layoutSubtreeIfNeeded` was
  called while a view was already being laid out. No failure or production symptom was observed;
  isolate the responsible test-host/view initialization before a future AppKit release turns the
  warning into an error.
- **The offscreen popover render harness produces invalid appearance captures on Xcode 26.5.**
  Reproduced 2026-08-08 with `swift run Headroom --render-popover <dir>`: the command exits 0 and
  writes every expected PNG, but repeatedly logs `could not create image from window`; light-mode
  captures are blank/transparent and dark-mode captures render light-mode semantic ink over the
  dark surface. Runtime fixture tests still pass, so this blocks trustworthy visual evidence rather
  than app behavior. Re-characterize `NSWindow` capture and effective `NSAppearance` propagation
  on the current SDK before relying on these PNGs for design acceptance.

## iPhone sync — Mac needs the iCloud-KVS entitlement (provisioning-gated)

- **Confirmed root cause of "iPhone shows a stale snapshot".** The installed standalone
  `Headroom.app` publishes phone snapshots through `NSUbiquitousKeyValueStore`, which is inert
  without the `com.apple.developer.ubiquity-kvstore-identifier` entitlement. `Scripts/build-app.sh`
  **strips** that entitlement unless `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1`, so a default-built
  app can't publish at all — `iCloudSnapshotPublisher.export` swallows the failure (`try?`) and
  the iPhone freezes on the last snapshot that propagated while a properly-provisioned build ran.
  Verify with `Headroom.app/Contents/MacOS/Headroom --dump-phone-sync` (run from the **signed
  bundle**, not `swift run` — a bare CLI has no bundle id/entitlement and always reads empty).
- **The entitlement is provisioning-gated.** `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1` alone isn't
  enough: the restricted entitlement needs an embedded provisioning profile, or macOS SIGKILLs
  the app at launch (exit 137, verified). `build-app.sh` now accepts
  `HEADROOM_PROVISIONING_PROFILE=/path/to/*.provisionprofile` to embed one, and warns when the
  entitlement is on without a profile.
- **Fix path (needs the Apple Developer account — interactive):** enable the iCloud Key-Value
  storage capability for `com.kylezantos.headroom` (team `8D42S4MS38`), then either run/archive
  the macOS target from Xcode with managed signing (embeds the profile automatically) and install
  that build, or download a macOS development profile and rebuild with
  `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1 HEADROOM_PROVISIONING_PROFILE=… ./Scripts/build-app.sh`.
  The iOS host/widget entitlements already declare the key and are signed via Xcode, so the phone
  read side is fine — only the Mac publisher is blocked.

## Contrast — meter ghost and glass bodies are intentionally subtle

- The scheme-specific severity colors now clear WCAG 1.4.11 non-text contrast (≥3:1) against
  both flattened `RaisedTile` track endpoints: dark healthy 4.31–5.04:1, low 4.63–5.42:1,
  critical 3.06–3.58:1; light healthy 3.49–3.61:1, low 3.15–3.25:1, critical 3.61–3.73:1.
- The translucent bodies are characterization measurements, not blanket 3:1 passes. Ghost
  measures 1.23–1.37:1 in dark and 1.38–1.63:1 in light. Healthy glass measures 1.38–1.95:1
  in dark and 3.10–4.03:1 in light. Glass and ghost retain a full-severity reading-edge cap,
  and the adjacent percentage remains the primary numeric value. Revisit the body opacity or
  dark glass tokens only if live review shows the fill disappearing; keep the scheme-specific
  assertions in `BrandColorValuesTests` as the measurement source of truth.

## Companion platforms

- **watchOS companion is deferred.** It should probably reuse the iCloud snapshot contract,
  but it needs separate watch targets, signing/provisioning, widget complications or a
  Watch app surface, and real-device QA. Treat it as a follow-up rather than folding it
  into the iPhone companion branch.

- **Orphaned Claude account config homes (window narrowed 2026-08-20).**
  `~/Library/Application Support/Headroom/Accounts/claude/`
  holds ~15 UUID dirs (each with `config/` + `workspace/`) but the registry lists only one
  extra Claude account. Likely leftovers from repeated add/remove or demo/test runs that
  didn't clean up. Force-cancel now clears both completion markers, discards the prepared
  script, and PID-guards a late wrapper exit, so an abandoned handoff can no longer resurrect
  in app state. The official CLI process can still outlive force-cancel and write into its
  config home until the user closes Terminal; legacy homes also remain. Investigate those two
  residual sources before garbage-collecting homes absent from `providerAccounts.v1`.

## Stop-tracking / duplicate-badge review residuals (2026-08-14)

Soft-bucket items from the built-in stop-tracking + duplicate-login-badge review (all 8
primary findings were applied; these are the demoted coverage/advisory notes):

- **`providerFactory == nil` guard coverage is partial.** The lifecycle-overhaul interaction
  tests now construct factory-less demo stores and prove built-in reset and Make Main are inert.
  `canStopTrackingBuiltInAccount` / `resumeTrackingBuiltInAccount` / `attachBuiltInProvider`
  still lack a direct factory-less store assertion; keep this narrower residual until those
  paths explicitly prove `.notAllowed`/nil without changing registry state.
- **`readAccountUUID()` real file-read path untested.** Detector tests stub the read
  closure; only the pure `ClaudeAccountBlob.accountUUID(in:)` decoder is file-fixture
  tested. Mirror `readAccountEmail()`'s file-backed tests.
- **`resumeTrackingBuiltIn`'s `refreshAccountNow` side effect remains unasserted.** Promotion
  now has targeted-refresh coverage, but `AccountsSettingsInteractionTests` would still pass if
  the resume helper stopped refreshing. Add a counting provider at the app boundary before
  closing this residual.
- **`oauthAccount.accountUuid` decode is speculative** against a live `.claude.json`
  capture (repo convention is to verify JSON shapes against real captures). The
  fail-safe design means a shape change degrades to "no badge", not breakage.
- **Detector accepts any non-empty `accountUuid` string** without UUID-syntax validation;
  a hand-edited local file can create a false badge (detection-only, so no data risk).
- ~~**`UsageStore` account lifecycle needed extraction.**~~ Resolved 2026-08-20:
  add/remove/stop-track/resume/reset/promotion now live in
  `UsageStoreAccountLifecycle.swift`; the store retains polling and merge orchestration.

- **Orphaned npm grandchild on discovery timeout (review finding #7, 2026-08-12).**
  `CLIExecutableResolver.runLoginShell` signals only the shell PID on the 5s deadline
  (`terminate()` then `SIGKILL`), and the npm-prefix search is the first time the timed
  script runs a real external command (`npm prefix -g`). A hung npm survives as an orphan.
  Nuance from review validation: the shell runs interactively with job control, so npm
  gets its *own* process group — mirroring the PTY probe's process-group kill would still
  miss it; a full fix needs descendant enumeration (or disabling job control with
  `--no-monitor`-style flags per shell). Mitigating: an orphan writing to the closed pipe
  dies on SIGPIPE, so only a fully-hung, non-writing npm lingers; bounded to one process
  per user-triggered Check Again / uncached discovery. Deferred as low-impact vs. the risk
  of destabilizing the load-bearing shell probe.

## Video-review round residuals (2026-09-03)

- **Light-mode severity fills went vivid on 2026-09-03 (two-tier policy).** Meter fills now use
  `HeadroomSeverityColorValues.fill(for:dark:increasedContrast:)`: vivid in the default light
  appearance (amber 2.06:1 vs track, 2.71:1 vs card; green 2.26 / 2.97; red 3.11 / 4.09) on the
  argument that the percent numeral beside every bar is the accessible carrier, with the old
  3:1 text-safe tokens restored automatically under Increase Contrast. Text, pills, and icons
  stay on the text tier. Residuals: the Ghost recipe's light separation band dropped from
  1.38–1.63 to 1.26–1.55 and needs eyeballing; deepening the light track makes fill contrast
  *worse* (fills are darker than the track) and is now asserted in
  `noVividLightFillCanClearThreeToOneOnTheLightTrack`; `design/ridd-round4-meter-style.html`
  carries a dated note but its CSS specimen vars still show the pre-change values.
- **Unavailable rows are still narrower than live rows.** The percent column now reserves
  three digits, but an `.unavailable` row hides the "left"/"used" term entirely, so a card that
  mixes live and unavailable windows still won't share one gauge edge. Reserving the term's width
  would fix it at the cost of a visible hole in an all-unavailable card.
- **Rejected API key with a retained amount shows no CTA.** When continuity keeps a prior spend
  total, the card shows the amount and the corrected "Key rejected" badge but no "Replace key…"
  button; the button only appears when there is no amount to show. Decide whether the CTA should
  also appear beside a retained amount.
- **`APISpendPresentation.statusText` has no production callers** after the row-status refactor;
  it is exercised only by tests and can likely be deleted.
- ~~**Per-pane Settings heights are budgets, not measurements.**~~ Resolved by L9A: the window is
  a single resizable 800 × 700 frame (min 720 × 600) and `SettingsPane.preferredContentHeight`
  is gone. Verified live at 800 × 700, 1100 × 800 and the clamped floor.
- **`supergrokheavy` → "SuperGrok Heavy" plan mapping is unconfirmed** against a live Grok tier
  id; the fallback capitalization renders any real value sensibly either way.
- **`CredentialStore` still says "xAI API API key".** `APIKeyProvider.displayName` for `.xAI`
  is "xAI API", so the empty/unreadable-key messages double the word. The missing-key message
  was fixed via `APISpendCredentialDescriptor`; the other two were left alone.
- **Settings → API Spend guidance is stale.** The Anthropic field still warns of a "known
  request-format issue" (resolved 2026-08-10, see above) and OpenAI says "not live-verified";
  both undercut the now-precise failure copy on the popover card.
- **xAI missing-key line says "spend" for a prepaid balance.** "Add a management key to see
  xAI spend" follows the shared sentence shape; branching on `APISpendKind` would say "balance".

## L4B's 34pt right edge stops at the card's transient recovery rows

- **The Sep 2026 card margin (L4B) covers the identity rows, the meter rows and the pending
  skeletons.** Those now end 34pt from the card's right edge, mirroring the 34pt label column.
  The card's *transient* rows were deliberately left at the old 13pt: `StopWaitingButton`'s
  trailing `HStack` in `AccountSectionView` and `ProviderCardView`, the compact inline sign-in
  and "Check now" rows in `AccountSectionView.signInContent`, and the nested Connect/Waiting
  tiles (`ClaudeConnectCard`, `CodexConnectCard`, `ProviderSetupRecoveryCard`,
  `CodexAccessRecoveryCard`), which own their own backgrounds and would look shrunken inside
  the card if inset. The nested tiles are almost certainly right to stay full-width; the bare
  button rows are the open question — in a signed-out or waiting account they sit 21pt to the
  right of every percentage above them. Decide once those states have been seen live.
- **The L5D tooltip is unverified as rendered.** The main account's title carries
  `.help("Main account — shown in the menu bar and widgets")` and the VoiceOver label still
  says it, but AppKit's tooltip timer does not fire for synthetic (CGEvent-warped) pointer
  moves, so the popup itself was never observed. Confirm it by hovering the first row of a
  multi-account provider with a real pointer.

## Settings window residuals (2026-09-04, W4a / L9A–L11A)

- **A fresh worktree cannot run the `HeadroomAppTests` xcodebuild scheme without a manual
  Sparkle fetch.** `project.yml` points the framework at
  `.xcode-derived/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework`, which only
  `Scripts/build-app.sh` creates (curl + ditto of the 2.9.4 release zip);
  `-resolvePackageDependencies` does not produce it. Worse, once xcodebuild has cached a
  "no XCFramework found" build description in the *shared* DerivedData it keeps failing even
  after the framework exists — the run only succeeds with an explicit `-derivedDataPath`.
  Either give `build-app.sh` a deps-only mode the documented test command can call, or move the
  prefetch into the scheme's pre-action.
- **The measured vertical resize floor is 632pt, not the declared 600.** `SettingsView` asks for
  `minHeight: 600` and `.windowResizability(.contentSize)` clamps the live window at 632 — 32pt
  more, exactly the hidden title bar's height. Harmless (the effective floor is still above the
  600pt the sidebar column needs) but the constant reads 32pt lower than what ships.
- **The sidebar's version stamp cannot be visually accepted under `swift run`.** It reads
  `CFBundleShortVersionString`, which a SwiftPM binary has no Info.plist for, so L10A's 10.5pt
  monospaced-digit line is absent from every `--demo` capture. Accept it on a
  `Scripts/build-app.sh` bundle instead.
- **The demo fixture gives Cursor an account capacity of 5.** `--demo multi-4` renders Cursor
  with "1 of 5" and an "Add Account…" button, but the shipping Cursor provider is deliberately
  single-account (no config-home isolation), so its real header carries the switch alone. The
  fixture provider should declare a capacity of 1 or the demo misrepresents the pane.
