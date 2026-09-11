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
- ~~**`--demo` writes Settings preferences to the standard defaults domain.**~~ Resolved
  2026-09-10: `AppComposition.launchDefaults` resolves one domain per launch (`.standard` without
  `--demo`, the stable demo suite for a bare `--demo`, a per-launch suite per scenario) and the
  App, Settings, and both demo stores all read it. Verified: `defaults read Headroom` is
  byte-identical before and after a `--demo multi-2` run. The four keys earlier runs leaked into
  the debug binary's `Headroom` domain were left in place.
- **Each `--demo <scenario>` launch leaks a `co.zantos.headroom.demo.multi.<uuid>` defaults
  suite** (plus an accounts suite); ~1,170 such domains exist in `~/Library/Preferences` as of
  2026-09-10. Pre-existing and growing. Either name the suite per scenario or remove the
  persistent domain on quit.
- ~~**A focused, uncommitted account rename can still be lost on ⌘Q.**~~ Resolved 2026-09-10:
  the tile also commits on `NSApplication.willTerminateNotification` (R12).
- ~~**Reopening Settings after ⌘W restores keyboard focus into a renamed account field.**~~
  Resolved 2026-09-10: `focusedLabel` clears on disappear after the commit.
- ~~**Menu Bar pane still lists providers whose subscription is switched off.**~~ Corrected and
  resolved 2026-09-10. Two of the three claims were already handled before this batch: priority
  menu items are disabled for unfetched providers and Preferred-window rows render off providers
  dimmed with an "Off" badge (listed-but-greyed is deliberate). The remaining hole was the
  priority *label*, which named switched-off picks; `MenuBarPrioritySelection.label` now feeds
  from the fetched order and reads "None" when every pick is off. The stored preference keeps
  the off pick so re-enabling restores it.
- **The iOS targets compile a hand-picked list of Core files, so a new Core file can break the
  phone build silently.** `HeadroomIOS` and `HeadroomIOSWidgets` enumerate individual
  `Sources/HeadroomCore/Models/*.swift` paths in `project.yml`; the Sep 9 fill-tier split added
  a `UsageSeverity` overload in `UsageSeverityColorValues.swift` that the lists lacked, and
  `HeadroomIOS` did not build from 2026-09-09 until 2026-09-10. Nothing in `swift test` or the
  macOS app-test scheme exercises the iOS targets. Add an iOS simulator build to the pre-PR
  check, or move the shared Core files into a folder the targets include wholesale.
- **App-boundary tests emit an AppKit re-entrant-layout warning under Xcode 26.5.** All six
  `HeadroomAppTests` pass, but loading the app test bundle logs that `layoutSubtreeIfNeeded` was
  called while a view was already being laid out. No failure or production symptom was observed;
  isolate the responsible test-host/view initialization before a future AppKit release turns the
  warning into an error.
- ~~**The offscreen popover render harness produces invalid appearance captures on Xcode 26.5.**~~
  Re-characterized 2026-09-10 on Xcode 26.6 (17F113): `swift run Headroom --render-popover <dir>`
  exits 0, logs no `could not create image from window`, and both appearances render correctly
  (light ink on the light surface, dark ink on the dark surface; `multi-2` inspected by eye). The
  2026-08-08 symptom (blank light captures, light ink over dark) did not reproduce. AGENTS.md's
  "do not accept `--render-popover` output as evidence" gotcha can be relaxed once one more run
  confirms it; live `MenuBarExtra` acceptance stays the bar for window sizing.
- **The harness's multi-account path renders neither Grok/Cursor nor the spend card.**
  `renderMulti` in `PopoverRenderHarness.swift` passes `apiSpendProviders: []` and
  `renderPreferences` enables only the Anthropic/OpenAI spend surfaces, so
  `popover-multi-4`, `popover-four-default`, `popover-spend-states`, and `popover-spend-retained`
  come out as the plain two-provider Claude + Codex popover (the four light PNGs are
  byte-identical). The names promise scenarios the harness never draws; anything touching the
  Grok/Cursor cards or the spend rows has no headless visual evidence. Wire the fixture's spend
  providers and enable the Grok/Cursor surfaces in the multi path.

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

- ~~**`providerFactory == nil` guard coverage is partial.**~~ Resolved 2026-09-10: three
  factory-less `MultiAccountTests` prove stop-track is `.notAllowed` with no tombstone written,
  resume returns nil with the tombstone intact, and the reinstate path attaches no provider.
- ~~**`readAccountUUID()` real file-read path untested.**~~ Resolved 2026-09-10: temp-directory
  `.claude.json` tests in `AccountEmailTests` cover present, missing, malformed, and key-absent.
- ~~**`resumeTrackingBuiltIn`'s `refreshAccountNow` side effect remains unasserted.**~~ Resolved
  2026-09-10: a counting provider in `AccountsSettingsInteractionTests` asserts exactly one fetch
  for the resumed row and none for siblings.
- **`oauthAccount.accountUuid` decode is speculative** against a live `.claude.json`
  capture (repo convention is to verify JSON shapes against real captures). The
  fail-safe design means a shape change degrades to "no badge", not breakage.
- ~~**Detector accepts any non-empty `accountUuid` string**~~ Resolved 2026-09-10: the detector
  canonicalises through `UUID(uuidString:)` and treats a non-UUID as absent (no badge).
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
- ~~**`APISpendPresentation.statusText` has no production callers**~~ Deleted 2026-09-10 along
  with `qualifier(kind:)`; the `remoteHint` coverage moved onto `rowStatus`.
- ~~**Per-pane Settings heights are budgets, not measurements.**~~ Resolved by L9A: the window is
  a single resizable 800 × 700 frame (min 720 × 600) and `SettingsPane.preferredContentHeight`
  is gone. Verified live at 800 × 700, 1100 × 800 and the clamped floor.
- **`supergrokheavy` → "SuperGrok Heavy" plan mapping is unconfirmed** against a live Grok tier
  id; the fallback capitalization renders any real value sensibly either way.
- ~~**`CredentialStore` still says "xAI API API key".**~~ Resolved 2026-09-10: every
  `CredentialStore` message names the provider's own credential ("xAI management key",
  "Anthropic admin key") through the descriptor vocabulary; a guard test rejects "API API".
- ~~**Settings → API Spend guidance is stale.**~~ Resolved by PA2 (`SettingsPanes.swift`
  `apiKeyEditor`): the engineering-status sentences are gone; each field now says only what a
  regular key cannot do and links to the vendor console. Confirmed 2026-09-10.
- ~~**xAI missing-key line says "spend" for a prepaid balance.**~~ Resolved 2026-09-10:
  `rowStatus` takes the `APISpendKind` and says "balance" on prepaid rows; the iOS mirror passes
  `semanticKind` too.

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
  multi-account provider with a real pointer. **L11A's "Turn <Provider> on to add an account."
  tooltip is unverified for the same reason** — it is the `.help(_:)` on the disabled
  "Add Account…" button in a switched-off provider group header, and a disabled AppKit
  control plus synthetic hover is exactly the combination that never fires the tooltip
  timer, so it was never observed either. Confirm both in one real-pointer pass.

## Settings window residuals (2026-09-04, W4a / L9A–L11A)

- ~~**A fresh worktree cannot run the `HeadroomAppTests` xcodebuild scheme without a manual
  Sparkle fetch.**~~ Resolved 2026-09-10: `./Scripts/build-app.sh --deps-only` prepares the
  Sparkle artifact alone, and the documented test command (AGENTS.md, README) chains it with an
  explicit `-derivedDataPath ./.xcode-derived`. The shared-DerivedData cache trap still exists if
  the explicit path is dropped.
- **The measured vertical resize floor is 632pt, not the declared 600.** `SettingsView` asks for
  `minHeight: 600` and `.windowResizability(.contentSize)` clamps the live window at 632 — 32pt
  more, exactly the hidden title bar's height. Harmless (the effective floor is still above the
  600pt the sidebar column needs) but the constant reads 32pt lower than what ships.
- **The sidebar's version stamp cannot be visually accepted under `swift run`.** It reads
  `CFBundleShortVersionString`, which a SwiftPM binary has no Info.plist for, so L10A's 10.5pt
  monospaced-digit line is absent from every `--demo` capture. Accept it on a
  `Scripts/build-app.sh` bundle instead.
- ~~**The demo fixture gives Cursor an account capacity of 5.**~~ Resolved 2026-09-10:
  `DemoUsageProvider.accountCapacity` is 1 for Cursor.

- **The Widgets & iPhone preview strip has no iPhone tile (L9P).** L9P asked for one "if a
  shared, WidgetKit-free rendering path exists". None does: the companion tile lives in
  `HeadroomIOS`/`HeadroomIOSWidgets` (`ProviderTileView`, `HeadroomTheme`, `Elevation`), neither
  of which is in the SPM package or the macOS app target, so previewing it would mean either a
  cross-platform move of the iOS design system or a hand-drawn mock — the exact drift cost the
  options doc warned about. The strip therefore shows only the macOS small and medium widgets.
  Revisit if the iOS tile ever lands in a shared, platform-neutral library.
- **The preview strip cannot reflect "Show Codex Spark counters in widgets".** That switch adds
  an `.other(…Spark weekly)` window, and `.other` windows are not `isSubscriptionWindow`, so
  neither the small (`primarySubscriptionWindow`) nor the medium (`displaySubscriptionWindows`)
  family ever draws one — only the large widget and iOS do. The switch therefore sits under a
  preview that never responds to it. Either preview the large family too, or move the switch.

## Motion system residuals (2026-09-04, S1A–M11A)

- ~~**The live popover does not crossfade on a meter-style change.**~~ Resolved 2026-09-10: each
  card sits in a ZStack keyed by the shared `MeterRecipeKey` with an opacity transition under the
  Reduce Motion-aware crossfade scope; the M4A arrival registry is keyed by account, so a rebuilt
  row does not re-run its draw-in. Residual: a Full↔Micro change holds the taller height for the
  200ms fade and then settles rather than animating height travel.
- **The specimen's static-meter gate reuses `announcesAccessibilityEvents`.** `ProviderCardView`
  derives `meterArrivalKey` from the KTD4 inert-preview flag so the M4A draw-in never fires in the
  specimen. A dedicated `stagesArrival` parameter would be clearer; it was avoided only to keep the
  W2 follow-up out of W4's file.
- **M7A removals are instant under Reduce Motion, not faded.** The Accounts list is one `.movement`
  scope on purpose (splitting the row fade from the tile contraction is what made the contraction
  land late), so S2A's "crossfades survive" does not hold for that one list. Revisit only if a
  Reduce Motion user reports the hard cut.
- **M4A under Reduce Motion is not a true per-property split.** The skeleton → live body's
  `.transition(.opacity)` and the resize it causes share one transaction, so the body-driven card
  resize rides the crossfade scope; only the tile scope snaps. A ZStack crossfade slot would fix it
  but `staleContent`'s two-view branch needs restructuring first.
- **Unavailable → live rolls the numeral from "—".** The reverse direction is a crossfade. Forcing
  a crossfade both ways needs an `.id()` swap on the numeral that risks the layout shift M4A
  forbids; flag if it looks wrong in acceptance.

## Round-2 residuals (2026-09-06, T1A–S5A)

- **`ProviderSetupRecoveryCard`'s primary is still `.borderedProminent` beside a chip secondary.**
  B3A reassigned every bare `HoverButtonStyle` text button to the chip, but no anchor covered
  restyling a native prominent primary, so that one card foot still mixes languages. Decide
  whether the popover's primaries become a filled chip variant or the card keeps AppKit's button.
- ~~**`APISpendPresentation.qualifier(kind:)` has no call sites.**~~ Deleted 2026-09-10.
- **The stale and balance spend rows have no fixture outside `--demo spend-states`.** Every
  other scenario ships the same two live rows, so the state tags, wrapping message, and CTA row
  are only reviewable there or against the round-2 options doc.

## Round-3 residuals (2026-09-06, G1A–C6A)

- ~~**Demo mode reads the theme from the swift-run defaults domain, not the isolated suite.**~~
  Resolved 2026-09-10 by the same `launchDefaults` fix as the Polish entry above; demo now
  resolves `.system` and follows the OS appearance.
- ~~**The Brand account-title ink has no sanctioned visual review path.**~~ Resolved 2026-09-10:
  `--account-title-ink <neutral|brand>` is validated beside `--meter-style` and honoured by both
  demo stores and `--render-popover`. Like `--meter-style`, it is only validated when `--demo` is
  present, so a bad value under `--render-popover` silently falls back to the default.
- **The spend card's action row is far from the row it answers.** P4C collects every CTA at
  the card foot, so in a four-row spend card "Replace key" sits three rows below the rejected
  Anthropic line (and past the 640pt scroll cap in `spend-states`). Decide whether spend CTAs
  belong to the row or the card.
- **The rejected spend row double-codes severity.** X5 (Kyle) put the "Rejected" tag on the
  identity line and S2B inks the sentence, so that one row carries both. Drop one once Kyle
  has seen it live.
- ~~**`StatusSentenceSeverity` has no `.quiet` / `.neutral` cases**~~ Resolved 2026-09-10: the
  two cases exist and the spend sentence is a `StatusSentence`. One deliberate delta: the spend
  sentence now takes the OA1 optical-leading pad the local copy lacked (the spend title above it
  already had it). Eyeball on the next `--demo spend-states` look.
- ~~**`SetupChipButtonStyle.Size.regular` is unreferenced**~~ No longer true: the popover
  footer chip uses `.regular` (`PopoverView.swift`, CMM round). Struck 2026-09-10.

## Pre-ship craft audit residuals (2026-09-08)

- ~~**The `--demo` Claude fixture orders Weekly before 5-hour; the parser never does.**~~
  Resolved 2026-09-10, with the premise corrected: the popover *does* show Weekly first —
  `UsageStore.appDisplaySnapshot` re-ranks every snapshot weekly-first (PR #35, matching the
  widgets' `displaySubscriptionWindows`), so `--demo` captures and real popovers always agreed.
  The surface that drifted was the Settings `AppearanceSpecimen`, which rendered the raw fixture
  (5-hour first). Now: fixtures sort through the public `ClaudeUsageParser.sortedForDisplay`
  (provider order), and the specimen applies the new shared `UsageSnapshot.weeklyFirst()` that
  the store also uses. The `DemoScreenshotData` envelopes were re-sorted to provider order too;
  the phone mirror shows a projection as-is, so that is what a real phone shows.
- **`HoverButtonStyle` hover band vs hit band is unverified.** The `.padding(8) → contentShape →
  padding(-8)` trick grows the click target to the 40pt floor, but `.onHover` attaches after the
  negative padding, so the pill may not appear in the added 8pt band. Needs a live pointer check
  on the popover gear and spend `+`; no capture path exists for hover states.
- ~~"Anthropic API" truncates beside a "Last 30 days" period chip.~~ **Resolved 2026-09-09
  (R2C8):** the amount column now measures the widest total the card is showing (floor "$0.00")
  instead of reserving "$0,000.00"; amounts stay on one right edge and every spend title renders
  whole in the live `spend-states` capture. Re-check a "Last 30 days" chip on the next shoot.
- **The iOS mirror still shows its own "Low" chip.** AP1 removed the macOS popover chip in favour
  of red critical ink, but `Sources/HeadroomIOS/Views/UsageBarView.swift` keeps a `lowChip` driven by
  `MirrorPresentation.showsLowChip` (`MirrorPresentationTests.swift:70`). Bring the phone surface in line
  or decide it keeps the chip deliberately.

## Craft round 2 residuals (2026-09-09, R2M1–R2B4)

- **R2M4 deferred.** Kyle noted a signed-in account never shows Check Now (the chip is only on
  setup/recovery rows). The per-account "Checking…" capsule half of M4 (`refreshingAccounts` in the
  store, lit only for the serial Claude/Cursor/Grok lane) stands on its own; not built.
- ~~Spend `+` placement (R2C8).~~ **Resolved 2026-09-10 (CMM5):** the glyph sits left of the amount;
  spend rows now share the meter rows' figure / suffix / empty-gutter columns.
- **Setup disclosures under Reduce Motion (R2M7).** The chevron snaps and the well crossfades, but
  the container height rides the 200ms crossfade rather than snapping: SwiftUI resolves an
  insertion's layout and transition in one transaction. Same family as the M4A/M7A residuals.
- ~~**Waiting clock skips restored handoffs (R2M12).**~~ Resolved 2026-09-10: the generation
  state file carries the start (`active:<generation>:<epochSeconds>`), the zsh wrapper pins the
  whole line it read at startup, and `SetupSessions` seeds the clock from it on restore. Missing,
  legacy two-field, unparseable, cancelled, or future starts fall back to no clock. Accepted
  (Kyle, 2026-09-10): a build older than this one cannot parse the three-field active line, so
  a handoff started here and then opened on an older build stays "Waiting" until Stop Waiting
  or a manual marker cleanup. Sparkle only moves forward, so no compatibility shim is planned.
- **R2M1 window resize.** The setup-session tile now rides `valueSpring`; if the ~88pt NSWindow
  step looks wrong live, drop the tile's session scope to `settle` (one line, marked in the comment).
- **Glyph pills derive their radius (R2B3)** as `min(w,h) × 0.30` rather than pinning 26×26; sizes
  still vary by call site. One-line follow-up if uniform pills are wanted.
- **Unverified live:** Settings sidebar glyph ink (inactive-window dimming may explain the report's
  reading; forcing `.secondary` risks a grey glyph on the selected row), `HoverButtonStyle` hover
  pill on the Accounts `•••` `Menu` (R2C21), swatch hover/press bands (R2M6), sidebar focus on
  open (R2M8), and the dark menu-bar vessel, which brightens with the R2C4b dark critical fill.
- **Reduce Motion pass is Kyle's** (agents do not change accessibility settings).
- **Setup body prose still says "connect"** as Headroom's own act ("Headroom reconnects
  automatically", "Headroom connects as soon as you approve"); R2C6 scoped to status, buttons,
  header and card title. One-line fixes if the verb should go everywhere.


## Widget craft residuals (2026-09-11, WCF1–WCD3)

Plan: `docs/plans/2026-09-11-001-feat-widget-craft-plan.md`; decisions in
`design/widget-craft-options.html` and the folded mock `design/widget-proposed-design.html`.

- **Accented / vibrant rendering is reasoned, not measured (WCM7).** The `widgetAccentable` set was
  recut (bar fill, numeral, spend amounts in; provider names out; marks `.desaturated`) and a
  non-`.fullColor` branch draws fill `.primary` / track `.primary.opacity(0.20)`. Nobody has looked
  at it on a tinted iPhone Home Screen or a de-emphasised Mac desktop. Device look owed.
- **StandBy / stripped-background contexts (WCM8)** return full-strength neutrals when
  `showsWidgetContainerBackground == false`. Same: reasoned from the token derivations, not seen on
  a device in StandBy.
- **Fill-aware density selection (WCL1, option B).** Tiers still count rows (headers + meters).
  A `Scale` with estimated row/header heights that picks the roomiest tier fitting the tile height
  is the monotonic-by-construction follow-up; needs the tile height passed in.
- **Brand-tinted names are not plumbed to widgets (WCD1).** Widgets take the popover's default
  neutral `accountTitle`; the popover's `AccountTitleInk` preference does not reach the envelope.
  Stated decision, not an accident.
- **Envelope schema stays at 3.** Not built, by decision: percentage mode ("used"), `MeterStyle`
  (format/shape/fill), typed capability state (would let the attention glyph become a word),
  multi-account rows, interactive `AppIntent` widgets, widget-string localisation.
- **The render harness is macOS-only.** `.context/qc/widgets/render-harness/` renders the shared
  bodies with `ImageRenderer`; with WCF1's pinned points the type now matches across platforms, but
  iPhone line heights, `.accented`, StandBy, and **Dynamic Type at `xxLarge`** still need a
  Simulator or device — macOS `ImageRenderer` ignores `.dynamicTypeSize`, so the whole-ladder
  `@ScaledMetric` scaling (WCF1) and the vertical fit rungs it can trigger (WCF7) were verified by
  shrinking the tile instead of growing the type.
- **Medium countdown appears on single-provider tiles only (WCL9).** Measured in the mock: a
  two-column medium at the 28pt gutter cannot hold `label + countdown + reserved column + suffix`,
  so the two-rung ladder drops it whole there. If the countdown matters on two-column medium, the
  honest options are a wordless medium or exempting the label row from the content axis.
- **`HeadroomWidgetSharedUI` has no automated coverage.** The module is compiled into the
  `Headroom` app target that `HeadroomAppTests` imports, but no test touches it: the bar's
  fill/ink selection (WCM1–WCM3), the meter's `ViewThatFits` ladders (WCF7), the medium spend-air
  rung, and `HeadroomLargeRhythm`'s gap arithmetic are verified only by the offscreen harness
  sweep. Follow-up: lift the fill/ink selector into a Core `WidgetBarRecipe` and the rhythm gaps
  into `LargeWidgetDensity.rhythmGaps(blockHeights:available:)`, both testable; add
  `WidgetFontMetricsTests` cross-checking the CoreText port against `OpticalLeading`.
