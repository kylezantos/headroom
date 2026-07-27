# Deferred / Follow-up

Non-blocking items. The earlier OAuth/Keychain-token approach and its U9 spike are **obsolete** —
Anthropic prohibits and blocks third-party subscription-OAuth use, so Claude now reads the
official `claude` CLI's `/usage` panel instead.

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
  - **No alternate CLI surface exists.** There is no `claude usage` subcommand and no JSON
    output for limits; the interactive `/usage` panel is the only source. The only way to
    recover the value would be the usage endpoint / claude.ai session directly — prohibited
    and server-side-blocked (see the hard constraint in AGENTS.md). Not an option.
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
- **Each poll spawns a full `claude` session (~20–30s, some CPU).** Claude accounts now run
  in one serial lane and the interval has an enforced 2-minute floor. Caching or adaptive
  cadence could still reduce cost for users who configure several accounts.
- **No live integration test for the PTY probe.** Provider tests use a fixture panel +
  mock source (fast, deterministic). The real `ClaudeUsageCLIProbe` is verified manually
  via `--probe-claude`; a machine-dependent integration test would need the CLI logged in.

## Reliability (carried from earlier review)

- **No backoff on repeated failures.** Both providers retry every cycle at the fixed
  interval. Exponential backoff on consecutive transient failures would be gentler on a
  down endpoint. Design choice — deferred.
- **The locked Codex demo fixture and its parity tests disagree.** `DemoFixture.codexSnapshot`
  still includes a 5-hour window with 91% remaining, while
  `DemoFixtureTests.codexDemoMatchesCurrentReality` and
  `DemoScenarioParityTests.iOSDemoCoversCurrentMacScenario` require the July 2026
  weekly-only scenario. The full `swift test` suite therefore fails at those two
  assertions. Decide which demo reality is authoritative and update the fixture plus
  any matching screenshot data together. Found during the 2026-07-27 TerminalGraph
  control-room verification; no product/demo files were changed by that tooling work.

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
