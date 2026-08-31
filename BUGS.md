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

## Reliability (carried from earlier review)

- **No backoff on repeated failures.** Both providers retry every cycle at the fixed
  interval. Exponential backoff on consecutive transient failures would be gentler on a
  down endpoint. Design choice — deferred.

- **Menu bar stays silent when a CLI is dead.** Provider capability failures are transient
  reasons, so `MenuBarLabel.needsAttention` does not light up for a missing or undiscoverable
  CLI. This is an explicit current product decision: recovery remains in the popover and
  Settings rather than adding persistent menu-bar attention. Revisit only with a deliberate
  cross-surface attention design.

- **Grok can report success before readable auth appears.** Codex maps this wrapper-success /
  auth-absent case to the typed `codexStorageMismatch` recovery. Grok has no equivalent typed
  storage-mismatch diagnosis yet, so the user can fall back to generic reconnect/check behavior.
  Add the analog only after characterizing where supported Grok CLI versions store credentials
  under both the built-in home and an isolated `GROK_HOME`. Checked 2026-08-30: no Grok CLI
  install (and no `~/.grok/auth.json`) on the dev machine, so the characterization needs a
  machine with the CLI installed and signed in.

- **Grok subscription overage is decoded but deliberately unsurfaced.** `GrokDTOs` reads
  `onDemandCap`/`onDemandUsed`/`prepaidBalance` from the billing config additively, but no
  surface renders Grok subscription overage (Cursor's on-demand row ships via
  `CursorOnDemandSpendProvider`; xAI *API* credit balance ships via `XAIAPISpendProvider`).
  This is a recorded decision, not an oversight: we have no verified live capture of a
  subscription account with on-demand active, so any UI would be speculative — the same
  trap the original Codex DTO field names fell into. Revisit only with such a capture.

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

## Contrast — severity bar colors in light mode (pre-existing, shared tokens)

- `HeadroomSeverityColorValues` has one value per severity used in both schemes. As bar fills
  in **light** mode they miss WCAG 1.4.11 non-text contrast (≥3:1) against the composited
  bar track on a white card: healthy 1.69:1, low 1.57:1, critical 2.59:1; the track itself
  is only 1.32:1 against the card. In **dark**, critical is marginal at 2.81:1 (healthy 4.31,
  low 4.63 pass). Mitigating: the adjacent percent text (AA-passing) carries the same value,
  so the bars are reinforcement, not the sole indicator. Fix would be scheme-aware severity
  variants (darker greens/ambers/reds for light), which touches the popover, companion, and
  widgets together — do it as one deliberate pass, not a widget-only patch. Found during the
  2026-07-08 widget contrast audit; text tokens were fixed in that pass, bars deferred.

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
