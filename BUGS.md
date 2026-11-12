# Deferred / Follow-up

Non-blocking items. The earlier OAuth/Keychain-token approach and its U9 spike are **obsolete** —
Anthropic prohibits and blocks third-party subscription-OAuth use, so Claude now reads the
official `claude` CLI's `/usage` panel instead.

## Follow the default login: open items (2026-11-10)

Plan: `docs/plans/2026-11-10-1315-feat-follow-default-login-plan.md`. Phase 1 covers Claude,
Codex, Grok, Cursor and Copilot. Phases 2 (remembered-account rows on the Mac and the phone) and
3 (one row for the default login and a matching extra) cover Claude and Codex, the providers
with a strong identity.

- **Claude is wired on one of gate V1's three cases (2026-11-11).** Identity is
  `oauthAccount.accountUuid` plus `organizationUuid` from each row's own `.claude.json`, read
  before and after every `/usage` capture; relabel, refusal, remembered rows and the one-row
  merge now apply to Claude (`ClaudeIdentityTests`). Still assumed, not verified: that a Claude
  Desktop sign-in and a default-login switcher rewrite the `oauthAccount` block whenever they
  change the Keychain credential (see the V1 entry below). Third-party sources say a running
  Claude Code session can rewrite the block from its own cached profile; a run on 2026-11-11
  (CLI 2.1.322, one session, a few minutes) did not reproduce it: see the V1 record's "The
  open-session case". Also unmeasured: how often the CLI's
  own rewrite of `.claude.json` at launch makes the after-read meet a half-written file and
  refuses a reading (`identityRefusalTotals` counts it; the plan's probe-trace line for it is
  not added). Two choices made in the wiring: a file undecodable on both sides is refused, as
  KTD2 is written, where Grok keeps that reading under no name; and an inherited
  `CLAUDE_CODE_OAUTH_TOKEN` is detected by the variable's presence, so an empty value also
  makes every Claude row Absent.
- **Phase 3 (one row for the default login and a matching extra) is built for Claude and Codex**, the two
  providers with a strong identity.
- **A merged row dims when the added account's poll failed, even if the default login's own
  reading is live (accepted, KTD11).** While merged, the row shows the added account's reading,
  so a transient failure on that account dims the row. KTD11 keeps the merge through a transient
  failure so the row does not split and rejoin on every blip.
- **Gate V1 passed for `claude auth login`, with and without a session left running
  (2026-11-11).** See `docs/qa/2026-11-11-default-login-gate-v1.md`. Not run: Claude Desktop signing in, and a
  switcher that swaps the Keychain credential. A switcher that leaves `.claude.json` alone
  would put readings under the wrong account; get a before-and-after `.claude.json` from a
  ccswap setup before a release says it follows one.
- **Review residuals, Phase 3 and Claude (2026-11-11).** Not fixed: an added account that changes
  to another login while merged sets its reminder state aside under the old account, and the
  hand-over at unmerge skips it, so the built-in can post one of those reminders again. A setup
  that ends in `connected` with the popover closed holds the merge off until the popover next
  plays the Connected chip. The Claude provider decodes `.claude.json` twice per probe; the cost
  on a large file is unmeasured. The popover header builds the display projection per body
  (popover open at 20 accounts measures 741 or 742 view bodies run to run, against a recorded 741; the one that varies is `PopoverScrollIndicator`, 6 or 7). The Settings badge rule for a merged pair is
  tested in Core only. The cross-model adversarial review timed out with no output; an in-process
  adversarial pass ran after the merge and its one finding (a reminder repeated when two rows
  merge) is fixed. Its unverified risks: if the Claude CLI ever fills in `organizationUuid` for
  an account bound with none, the row is treated as a different account (relabelled, history
  and reminders set aside, the old binding shown as a remembered row); while merged, no
  reminder fires if the added account's polls keep failing while the default login reads
  live; a merged provider's Settings counter still counts both accounts above one row.
- **Gate V2 was not run; the risk is accepted (Kyle, 2026-11-11).** The one-row merge trusts
  that one Codex `account_id` is one account. Two teammates sharing an id would show as one
  row. Kyle's two logins have different ids.
- **Gate V3 has no result.** One real rotation on a switcher setup, before a public release.
- **Phase 2 has no live or device look.** The remembered rows were checked in `--render-popover`
  renders (Standard and Compact, light and dark). The Settings row, the iPhone row and the Micro
  meter style's reset line are covered by tests and builds only.
- **A phone that predates the `k` key treats a remembered row as an ordinary stale extra.** It
  counts the row as not updated after a check-now and Siri may name it, until that phone
  updates. Recorded in the sync field contract. Accepted (Kyle, 2026-11-10) over holding
  remembered rows back until the phone build ships.
- **First launch after upgrade differs from the plan's KTD7.** The plan says a never-bound row
  with the default label adopts the saved label and history. The code treats a cached email
  that differs from the first identity as another account even when the label is "Main", and
  keeps the saved reading as a remembered account. Kept as built (Kyle, 2026-11-10): it is the
  safer reading of R1, and this entry is the record that it differs from the plan's text.
- **A remembered reading ages on the Mac without a phone export.** Aging runs at launch, on
  each engine wake and on popover open. A window that passes its reset between exports reaches
  the phone in its unavailable form at the next publish. A current phone hides the number at
  the reset by itself; a phone that predates `k` waits its ten-minute grace.
- **The budget ladder strips live extras' model rows before it drops a remembered row.** At 20
  accounts plus 20 remembered on Claude and Codex the set fits at level 1 (34,711 bytes);
  remembered rows go first only at level 2. Dropping them before level 1 would protect live data.
- **Records written by a Phase 1 build can hold a remembered account labelled "Main".** It
  shows as a dimmed "Main" beside the live one until that account is the default login and
  leaves again. Phase 1 was never released, so this needs a build from `main` between #220 and
  this change.
- **A remembered account kept by email only never yields to an extra.** The first-launch entry
  has no identity digest until a strong identity claims it, and the yield compares digests.
- **A returned account renamed back to "Main" keeps its earlier chosen name when it leaves.**
  Follows "never renumber a name the user chose"; unconfirmed as the wanted behaviour.
- **A remembered row with no stored reading shows "No usage data".** Needs a stored window this
  build cannot decode; not seen.
- **Not measured: the popover with remembered rows.** The 20-account bench matches the baseline
  for a setup with none. `commitDefaultLogin` compares the remembered list on every merge.
- **Review residuals (2026-11-10), not applied.** The last-read date map is built in two views;
  the reset-passed test is written in both `CompactAccountRowRecipe` and `RememberedRowRecipe`;
  the remove-button wording is decided in the Settings view; default-label numbering has a
  second loop beside `AccountRegistry`; `displayPrimaryKey` rebuilds the projection per call;
  the Settings "Last read" line reads `Date()` and does not tick while Settings stays open.
- **Unmeasured: how often a reading is refused.** The CLI can rewrite its account file while
  Headroom reads it. `AccountProbeScheduler.identityRefusalTotals` counts refusals per account
  in memory; no diagnostic prints it yet.
- **A Grok `auth.json` Headroom cannot read keeps the row live under no account's name.**
  Decided 2026-11-10 (Kyle), amending the plan's KTD2: a file unreadable on both sides of the
  usage read counts as "no account named", and only a one-sided failure or a disagreement is
  refused. A row that was bound to an account shows under "Main" until the file is readable.
- **Every accepted reading with an identity rewrites `defaultLoginRecords.v1`.** The slot's
  capture time must stay current for KTD6 attribution. Correct, cost unmeasured; measure at
  `multi20` with remembered snapshots before Phase 2 adds rows that read this state.
- **A reminder post in flight when its account leaves is counted as delivered.** Its
  completion finds the row holding another account and writes nothing, so the parked state
  takes the pending entry. If that post is then refused, the account misses one reminder for
  that reset. The new account's alert for the same limit also waits for that post to return.
- **Grok names the file's account, not the billed one.** Its ACP path reads its login
  separately from `auth.json`. Remembered accounts for Grok wait for an identity check.
- **Cursor and Copilot cannot bracket a reading.** A Cursor status read that misses is no
  evidence either way, so one reading after a switch can sit under the old name. Copilot's
  login comes from a status cache up to an hour old.
- **The sign-out record logs a switcher's brief signed-out moment as a sign-out.** Diagnostics
  only.
- **No test for "an account change counts as two sessions" in `SessionReliabilityRecord`.** The
  change ends the observation; the day counters are not asserted.
- **Copilot keeps two identity records.** `CopilotLoginMemory` (log evidence cut-off) and the
  slot record both key on the login from the same status read, so they agree on a change, but
  they are two stores.

## Feedback by email follow-ups (2026-11-03)

- **Live acceptance outstanding.** Send one report from a built, signed Mac app and one from
  the iPhone, and confirm both land in Linear Triage with no account names or emails in the
  diagnostics. Waiting on `support@zantos.co` → Linear intake (Kyle's setup).
- **iPhone row untested in a simulator.** This Mac's CoreSimulator was older than Xcode's
  (1174.9.2 vs 1174.21.0), so U4 was verified with a device-SDK build only.
- **headroom-site (U6).** Footer "Feedback" link, a `/feedback` redirect to the `mailto:`
  with a `[Headroom Web]` subject, and the privacy page section, published before a release
  that ships the Mac sheet.
- **Daily triage routine.** A scheduled pass that labels Triage issues, flags likely
  duplicates and notes missing details, never closing or merging. Only once report volume
  justifies it.
- **Fake-CLI tests flake under the parallel suite.** `CopilotStatusSourceTests.nonRespondingCLIHitsTheDeadlineAndItsProcessGroupIsKilled`
  still fails about one full `swift test` run in five after its deadline went from 1 s to 3 s
  (2026-11-03), so slowness was not the cause. Likely cause: the test writes its fake `copilot`
  script and runs it while other tests spawn processes that inherit the open file, which
  can make the launch fail with "text file busy" (ETXTBSY). The feedback version-reader
  tests hit the same race and moved to system binaries (`/usr/bin/git`, `/usr/bin/yes`). Fix
  the Copilot (and any other) fake-CLI tests by writing their scripts once before the suite
  runs, or spawning `/bin/sh` with the script as an argument.
- **Overlap with the troubleshooting sheet.** The deferred in-app troubleshooting sheet
  should reuse `FeedbackDiagnosticsCollector` rather than read state a second way.

## Account names on the phone follow-ups (2026-11-10)

The phone now shows the account name the Mac shows, so an email used as a name syncs as
that name. Still to do:

- **headroom-site privacy page.** It needs the same wording as the app: "If you use an
  email address as an account name, that address syncs as the name. Sign-ins, passwords
  and API keys never sync." Separate repository; publish with the release that ships this.
- **App Store listing unchecked.** If the live description or privacy answers say emails
  never sync, they need the same change. The label itself should stand, since Headroom
  cannot read the user's iCloud data, but that is unconfirmed.
- **Two rows on one email read differently.** The phone shows "x" and "x · 2"; the Mac
  popover shows the bare email on both rows.
- **Long email titles end-truncate on phone cards.** The design docs recommend middle
  truncation for emails.

## Copilot provider follow-ups (2026-11-02)

- Live acceptance has not run. The plan's gates still need a signed Headroom.app with a real
  `copilot login` through the Terminal handoff, then one `-p` run and one interactive run,
  checking that the meter moves after each and that session and log counts match what those
  runs created. The R4 check (shown value within 5% of the account's own usage page, under
  `PATH=/usr/bin:/bin`) and the day-long flat session count also remain.
- The five-provider menu bar, Settings pill shelf and popover Refresh row were checked in
  offscreen renders only. Judge them on the live `MenuBarExtra` with `--demo five-providers`
  in both appearances before release.
- Use from VS Code or github.com is missing until a quota snapshot or a server reading
  includes it, so the meter can show more room left than the account has. The README says so;
  the row itself does not.
- Annual legacy plans billed in premium requests have no defined meter and no test account.
- GitHub publishes `GET /users/{username}/settings/billing/ai_credit/usage` for self-purchased
  plans (organization seats excluded). It is unevaluated: the local `gh` login lacks the
  `user` scope, so its data and lag are unmeasured.
- The updated privacy policy (`docs/release/privacy-policy.md`) must be published through
  `headroom-site` before any release that contains Copilot.

## Setup-session overlays reach the phone late (2026-10-30)

- **A setup session's phone attention only publishes on the next unrelated export.**
  `UsageStore.companionSession(for:)` reads the coordinator (and, since the Claude
  startup-question fix, the app's `companionInteractiveReasonLookup`) whenever a capture is
  built, but `SetupSessionCoordinator` state changes never call `exportPhoneSyncSnapshot()`.
  So "Finishing sign-in", "Approve the workspace" and the startup question's unknown-screen
  attention appear on the phone only when a merge, a setting or the heartbeat triggers the next
  capture, and can clear late the same way. Fix by exporting on coordinator state changes (the
  publisher already coalesces), with a `PhoneExportTriggerTests` case.

## Plan names on already-installed phones (2026-10-23)

- **Phones and iOS widgets on builds before the human-plan-names fix still show raw ids.** The
  Mac publishes the provider's verbatim `planLabel` (v3 `planLabel`, v4 `planName`); the fix
  humanizes it at render time, provider-aware, in `IdentityRow` and the widget identity row.
  An older phone build renders that raw value through its own, older formatter, so a Codex
  `self_serve_business_prolite` reads "Self_serve_business_prolite" there (and older widget
  extensions print the bare id) until the phone updates. Humanizing on the Mac before publish
  would fix old phones too, but changes the wire content and its digests; decide before the
  next phone release whether that is worth it.

## macOS 15 popover header clipping: device check outstanding (2026-10-23)

- The 1.5 report from macOS 15.0 ("the header 'Usage' is clipped", "other corners underneath")
  got an OS-independent fix: `PopoverTopPinnedLayout` keeps the header at the window's top when
  the window is shorter than the popover, and `PopoverWindowHeightFitter` fits the window height
  before macOS 26. Both are proven only by offscreen hosting tests on macOS 26 (the fitter forced
  on in DEBUG). Still unverified on a real macOS 15: that the `MenuBarExtra` window takes the
  fitted frame and keeps it (it may reset the height after the fit), that the top edge stays under
  the status item, whether the host reserves a top inset (brief H2), and whether the extra corners
  remain after 1.5.1's chrome changes. The `popover-window` hierarchy log answers the last two.
- **VM result (macOS 15.7.7, 2026-10-30):** the vertical clipping did not reproduce; the window
  matched the content on 1.5.1 and `main`, and no extra corners showed in 4x edge crops. The real
  defect was horizontal: PC1 rounded the header's own hosting-view leaves (title, status line,
  gear) at r22, drawing "Jsage", a trimmed status line and a diamond gear. Fixed by rounding only
  leaves that span the content (`PopoverHostBackdrop`, SQ2); see
  `docs/solutions/ui/popover-host-chrome-rounding-clipped-macos15-header.md`. Still unchecked:
  15.0 itself (the reporter's release) and the one-to-two-column widening below.
- **Widening from one column to two is unprotected on macOS 15.** The height fitter keeps the
  window's current width, and `fitPopoverWindow(columns:)` only narrows; growing to 750pt relies
  on `MenuBarExtra` widening the window itself, which is verified on 26 only. Device check: grow
  past the cap (or turn horizontal expansion on) and confirm the window widens with its left edge
  on the status item.
- **Live check on 26:** add an account while the popover is open and watch for a scroll-indicator
  flash. The card list can now give up height, so a frame where the window still has the old
  height lays the list out short (the bench saw two extra indicator bodies on open).

## macOS 15 five-provider popover on a short display (2026-11-03)

- Signed/notarized 1.6 (44), macOS 15.7.7 (24G720), Tart guest at 1152×720 points:
  `--demo five-providers` opens a 384×741-point native popover. The “Usage” header and gear
  remain intact, but the bottom spend rows and Refresh/Quit footer extend below the screen.
  Reproduces after a fresh app launch at that resolution, as well as after changing resolution.
  A scroll in the card stack does not reveal the footer; its native clip remains 620 points tall.
- At 1920×1200 points the whole five-provider popover fits. Native format, shape, fill and
  dark-theme changes completed without a crash. This is a short-display sizing gap, not evidence
  about macOS 15.0 itself. No sizing code was changed during release packaging.
- Evidence: `/tmp/headroom-16-vm-short-fresh.png`, `/tmp/headroom-16-vm-short-before.png`,
  `/tmp/headroom-16-vm-short-after.png`, `/tmp/headroom-16-vm-window.log`. Follow up by fitting
  the entire native window to the visible screen height and giving the cards the remaining room.

## SwiftPM tuning import warning (2026-10-13)

- `RaisedTile.swift:30` uses `HeadroomTuning` through its environment value without directly
  importing `HeadroomSharedUI`. Swift 6.4 reports a missing-module-import warning during
  `swift test`; the build and tests pass. Add the existing `#if SWIFT_PACKAGE` import pattern
  when addressing this warning; Xcode compiles the shared sources into the host directly.

## App Store capture script (2026-10-08)

- **`Scripts/capture-appstore-shots.sh` drops frames that never settle, then fails composing.**
  A `--device iphone69 --frames I1,I2,I4,I6,I8,I9,I10` run on iOS 26.5 logged "did not settle
  within 25s; kept the last capture" for I1, I2 and I9, but no raw PNG exists for them. The
  likely path is `settle_capture` returning 1 from its `app_running` wait before it takes any
  screenshot; the caller prints "kept the last capture" either way (unverified which branch
  fired). The compositor then failed with "could not load …/raw/I1-iphone69-dark.png" and
  composed nothing. A plain `simctl io screenshot` 9 s after launch captured all three
  cleanly. Fail the frame loudly when no raw file exists, and check `app_running` against the
  first launch of each appearance.

## iOS test-result collection (2026-10-05)

- **Multi-destination iOS test collection can stall (2026-10-05).** A single Xcode 27
  invocation targeting iPhone and iPad on iOS 26.5 stopped producing results with no UI-test
  runner left; cancellation reported an unfinished “Download and merge code coverage
  profiles” operation. The interrupted bundle had no readable summary. Run destinations
  separately while investigating; never count that interrupted run as passing evidence.

## Automatic-update installed-app acceptance (2026-10-09)

- **Opt-in policy and switch consistency are fixed; real installation acceptance is pending.**
  Packaging now permits automatic updates while defaulting them off, and Settings observes
  Sparkle's effective preferences and capability. Before release acceptance, prove background
  download followed by installation on quit, and the sidebar's restart action, between two
  suitable signed builds in an isolated environment. Follow the automatic-update acceptance
  gate in `docs/release/website-dmg-release.md`; passing preference tests does not prove an
  installed update cycle.

## App-target test host isolation (resolved 2026-10-04)

- The single-instance guard from #150 (`SingleInstance.otherRunningCopy()` in
  `HeadroomApp.swift`) also runs inside the XCTest host. With another Headroom.app running —
  e.g. a different Conductor workspace's build — the `HeadroomAppTests` host prints "already
  running" and exits 0, and xcodebuild reports "Early unexpected exit … before establishing
  connection" (2026-10-02). The shared `HeadroomAppTests` scheme now launches with `--demo`,
  using the existing isolated host and single-instance exemption. The production guard is
  unchanged. Verified with another workspace's app running: 263 App tests in 38 suites passed.

## Loading language follow-ups (2026-10-04)

- **Setup motion tests emit actor-isolation warnings (2026-10-08).** A clean
  `HeadroomAppTests` build reports `ActorIsolatedCall` in `SetupWaitingMotionTests.swift`
  when synchronous tests construct or call main-actor SwiftUI views. Give those tests
  the matching actor isolation; the assertions should remain unchanged. Observed while
  validating the Settings consolidation; deferred because it is outside that UI change.
- **Signed-out and all-unavailable menu pills still use the decorative level.** The ghost
  flag deliberately covers only a main account awaiting its first reading. Extend the neutral
  treatment separately; `fill == nil` must not become a pending-data signal.
- **An automatic neutral pill has no summary provider to slosh.** First-reading ghost and print
  work through its fixed identity, but neutral automatic work still needs an explicit motion
  source when no main has a usable reading. Deferred by the loading-language plan.
- **The loading-language CPU budget is unverified.** Kyle approved the native loading demo
  and requested merge. The back-to-back `--demo multi-20` main-thread CPU comparison and
  idle popover/Settings measurements have not run; the diagnostic builds alone prove no
  performance result. Do not claim the plan's two-percentage-point budget passed.

## Phone reminders deferred to a future version (2026-10-05, iPhone parity U15/U16)

- **Kyle deferred phone reminders out of 1.5.** He made this choice to keep the release
  manageable, so it is not a spike failure. 1.5 takes the R29 path: reminders stay Mac-only, the
  phone's Reminders section says "Reminders come from Headroom on your Mac", and the listing
  copy makes no phone-reminder claim. U16 doesn't run in 1.5. Pick the work up again from
  U15/U16 and KTD19 in `docs/plans/2026-10-04-0923-feat-ios-parity-round-plan.md`.
- **Where the spike stopped.** The runbook is `docs/qa/2026-10-cloudkit-reminders-spike.md`, on
  the unmerged branch `spike/u15-cloudkit-reminders`. Done on 2026-10-05:
  - The Mac build carries the CloudKit keys with environment `Production`, signed with the G2
    Developer ID identity and the P3 profile.
  - Notarization accepted it (`f46fbc9a…`) and Gatekeeper reports "Notarized Developer ID".
  - The app launched without an AMFI kill, and `--spike-cloudkit-status` printed
    `account=available`. This is half of check 1.
  - Spike TestFlight build 34 was uploaded.
  
  Not done:
  - The `ReminderEvent` schema is in neither Development nor Production; `cktool` rejected the
    management token.
  - No record was saved, and checks 2 and 3 and questions 4–7 weren't run.
- **Build 34 is taken.** Spike iOS build 34 was uploaded to App Store Connect. The 1.5 TestFlight
  and App Store upload must use build **35 or higher**. Expire build 34 in TestFlight.
- **The iPhone carries the spike's Debug build.** It was installed over Headroom on Kyle's
  iPhone for Step 3. Reinstall Headroom from TestFlight or the App Store.

## iPhone usage screen follow-ups (2026-10-05, iPhone parity U21/U9/U11)

- **Meter labels truncate to "…" at accessibility text sizes on a 390pt phone.** The shared
  Micro row's last rung truncates its label once `PhoneScale` clamps at xxxLarge, so "5-hour"
  and "Weekly" read "…" beside their countdowns (17e capture, AccessibilityXXXL). Pre-dates
  U21; the spend title now wraps by word instead. Needs a phone rung that drops the gauge or
  stacks the countdown before the label gives up.
- **Spend chip placement is decided per row.** On a 402pt phone at the default size "OpenAI
  API" holds its chip inline while "Anthropic API" drops it to the subline (KTD3's measured
  fit). A card-wide decision would read calmer; it needs the card's width before layout.
- **V38 has no one- or three-provider demo fixture.** The flowing-columns capture pass covers
  two (with and without spend) and four providers; one and three need fixtures.
- **"Last check" in Settings is session-only.** The round trip is recorded when this launch
  sees a real request complete; a relaunch starts without one.
- **Companion cache invalidation write failures have no tests** (review 2 testing gap): a failing
  first sidecar write (dirty marker), a failing final commit write in `invalidateLocked`, and the
  `.changed` guard returning nil when the first step fails. Only a failing removal is covered.

## Phone publisher follow-ups (2026-10-04, iPhone parity U5)

- **Two rare row kinds stay Mac-only.** The phone carries the widget row set plus flagged Spark
  rows, so the KTD13 parity holds. A Codex window whose `limit_window_seconds` is unrecognized
  (`.other(durationLabel)`) or a non-Spark Codex model row, and a Claude model row that is not
  weekly (none is produced today), show in the popover but not on the phone. Carrying them needs
  a wire flag the projection can filter, like `isSpark`.
- **A setup session's typed overlay reaches the phone on the next capture.** Starting or
  finishing a sign-in changes the account's attention line without a merge, so the phone sees it
  at the next merge, setting change or heartbeat (one chosen interval at most). A coordinator
  state hook would make it immediate.
- **The capture is built on the main actor for every phone-bound change.** At the multi-20
  envelope that is one full projection per merge (the publisher coalesces the writes, not the
  captures). Unmeasured; if `--bench-ui` shows a cost, capture lazily at flush time instead.
- **Two-device acceptance is pending (P5).** A signed Mac build with the KVS entitlement and the
  physical iPhone must show a new Mac account within one publish, and `--dump-phone-sync` on the
  signed build must list the keys and sizes. Only the unbundled dump has run.

- **Use-it-up reminders still round the raw window (review #16 residual).** The popover, menu
  bar, pill arranger and Settings tile print the normalized `UsageMeterReading` integer (KTD6.2),
  so 15.46% left reads 16%. `UseItUpEvaluator` still takes `Int(window.percentRemaining.rounded())`
  and gates `percentLeft >= rule.threshold` on it, so a banner can say 15% where the popover said
  16%, and a window can sit one point either side of a rule's threshold. Moving it changes when
  reminders fire, so it needs its own decision and tests.

## Check-now follow-ups (2026-10-05, iPhone parity U6)

- **Check-now is dormant on the phone until loader adoption.** `CompanionLoaderAdoption` is off
  (P5 identity gate failed), so phone surfaces resolve the v3 key, the resolver's winner is never
  v4, and `CheckNowClient.pull` answers `.rereadOnly` (KTD14.1). U9's pull shows re-read only
  until adoption flips. The Mac side is live as soon as a 1.5 phone writes a request.
- **The latency spike has not run.** `docs/qa/2026-10-check-now-latency-spike.md` holds the
  protocol and empty tables. Its 20-account write-throttling run needs either 20 real accounts
  on a test Mac or a DEBUG publisher harness: `--demo multi-20` never writes iCloud (R37). The
  per-probe constant (30 s) is provisional until then.
- **A failed answer reuses the not-finished line.** When the Mac's forced flush fails (over
  budget, write failure) it answers `failed`; the phone shows "Your Mac started checking but
  hasn’t finished. Pull again later." No dedicated copy exists.
- **Device UUID creation can race across processes.** `CheckNowDeviceIdentity` creates the
  install's UUID on first read through App Group defaults with no file coordination; an app and
  a widget extension reading it for the first time at once could each mint one, leaving one stale
  request key until the 30-day prune.
- **A launch with sync off skips the request scan.** Requests written before sync turns back on
  were swept by sync-off anyway; requests written after reach the Mac by live notification.

## Focused render acceptance needs Screen Recording for the launching shell

- `--menu-bar-only` and `--widgets-only` capture only through `screencapture -l` and fail
  rather than accept the `cacheDisplay` fallback. From a Conductor agent shell (2026-09-25)
  every capture failed, so both modes exit 1 there; the fallback images the full sweep saves
  in that environment show a black pane background and no preview well. Grant Screen
  Recording to the terminal that runs the harness, or treat those modes as unavailable there.

## Render harness setup-flow shots depend on wall-clock timing

- `--render-popover`'s `connected-*` and `dualWaiting-*` captures run the real setup clock
  (`openedSetupAt = Date()`) and snapshot after fixed sleeps, so how long the harness waits
  decides which state lands in the image. AR1 (2026-09-25) lengthened the meter arrival and the
  snapshot wait with it; `connected-used-light` then captured Connected mid-roll where it had
  captured Waiting before. Drive those states from an injected clock instead of sleeping.
- The new `--loading-only` path uses a pinned clock and held real requests, including Opening,
  Waiting and Confirming. Two 2026-10-04 runs matched all 26 decoded images. The legacy
  `connected-*` and `dualWaiting-*` path above remains outside that deterministic capture flow.

## Popover second corner on macOS 27 — confirm the shadow fix there (PC3)

- The thin second corner outside the r22 shell (faint rim on 26, a filled corner reported on 27
  on 2026-10-09) was the window server's shadow rim, drawn at the window's own tighter corner.
  Proven on 26 on 2026-10-13: with every host view and layer rounded to r22 the rim stayed, and
  turning `hasShadow` off removed it. The popover now ships without the system shadow. Still to
  do: confirm on a macOS 27 Mac that the filled corner is gone. If it isn't, read the per-window
  structure dump: `/usr/bin/log show --last 5m --predicate 'category == "popover-window"' --info`
  (`/usr/bin/log`: zsh's `log` builtin shadows it). PC2's host-chrome reshape found nothing to
  reshape on 26; remove it once 27 is confirmed without it.
- The replacement shadow (PS1, `PopoverShadowWindow`) is a click-through child window that mirrors
  the popover's frame, visibility and alpha. Checked on 26 in the DialKit demo for look only; still
  to watch in daily use: it leaves with the popover on close, on the fade into Settings, and on a
  Space switch, and it keeps up while the popover changes height.

## Test runs leave thousands of UserDefaults suites behind

- `~/Library/Preferences` holds thousands of `co.zantos.headroom.app-interactions.<UUID>` and
  `co.zantos.headroom.capability-demo.<UUID>` plists. The suites that create them call
  `removePersistentDomain(forName:)`, which clears the domain but leaves its plist file on disk.
  Point these at an in-memory or temp-directory store, or delete the files in teardown.

## Setup handoff launch still needs a bounded-stall design

- **The explicit Terminal open is asynchronous and has no timeout.** `NSWorkspace.open` normally
  returns promptly, and the handoff owns its script before suspending so **Stop Waiting** cleans
  up safely. A genuinely wedged LaunchServices request could still leave the row in Preparing and
  hold Codex's exclusive login slot. Do not add a naive timeout that reports failure while the
  uncancelled AppKit request later opens Terminal; first establish a cancellable or late-result-
  rejecting boundary, then cover it with a suspended-opener test. The dedicated QA host should
  also confirm a real installed build opens Terminal and advances the completion marker.

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

## Claude banked resets have no compliant source yet (2026-09-22)

- **Provider parity gap, not a deferral by choice.** Codex banked resets ship from
  `wham/usage` (`docs/solutions/codex-banked-resets.md`). Anthropic granted a Claude banked
  reset on 2026-09-22, but the print-mode `claude -p "/usage"` report on that day showed only
  `Current session`, `Current week (all models)`, and `Current week (Fable)` — no reset count.
  The OAuth usage endpoint is off-limits (AGENTS.md), so there is nothing to read. Next steps:
  capture the interactive PTY `/usage` panel on the same account to see whether it differs from
  the print report, find where Anthropic surfaces the grant (claude.ai settings, email, or the
  CLI), and recheck `/usage` on each CLI update. Only add a Claude capsule once the official
  client prints a count; update `ClaudeUsageParser` fixtures from a live capture at that point.

## Claude CLI probe

- **Provider session renewal remains incomplete (2026-10-20).** This PR reduces
  unnecessary Claude authentication commands and rereads Codex credentials once after
  a 401. Automatic Codex renewal remains unshipped: a stalled official-client request
  has no established finite safe settlement bound. Real persisted-renewal acceptance
  and production lifecycle integration are still required. Claude can exit before a
  pending renewal saves its replacement; the authorized reproduction is posted at
  https://github.com/anthropics/claude-code/issues/102265#issuecomment-6259274517.
  Eight-hour successful usage observation establishes continuity, not a rotation or
  a measured reduction in sign-outs. See `docs/qa/2026-10-20-safe-provider-session-fixes.md`.

- **Session diagnostic and attention follow-ups (2026-10-20 review).** Codex's
  unchanged-token 401 keeps Check Now and manual Sign In Again available on the Mac;
  phone attention remains retrying, and widgets do not escalate it to a confirmed
  sign-out. Any future attention escalation must preserve the distinction between an
  HTTP rejection and revoked login. Sampled account-seconds deliberately exclude gaps
  beyond twice the chosen interval, including scheduler backoff; compare rates only
  with comparable coverage. Collector cost at multi-20 has not been measured.

- **Remote Control opt-out: live acceptance mostly done (2026-10-23, checked 2026-11-02).** The
  PTY fallback launches with `--settings
  '{"disableRemoteControl":true,"remoteControlAtStartup":false}'` (versions ≥ 1.0.90 or
  unreadable) plus `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1`, and every Claude workspace carries
  `.claude/settings.local.json` with `remoteControlAtStartup: false`. Live check on CLI 2.1.312
  (Kyle's Mac, Desktop "Connect new sessions to Remote Control" on; offscreen PTY launches in
  the real `ClaudeProbe` workspace, judged by the CLI's own `--debug-file` log):
  - A launch forced to auto-connect (`--settings '{"remoteControlAtStartup":true}'`, local file
    moved aside) logged `[remote-bridge] Created session`, so the signal works.
  - Headroom's `--settings` opt-out alone: no session. The local file alone, even against that
    forced `true`: no session. Each layer blocks on its own.
  - A bare launch with only the Desktop toggle on created no session on 2.1.312.
  - With the opt-out the boot paint classified ready (no notice line, no modal).
  - Print mode in the real workspace with the local file present: exit 0, parseable report.
  Still unverified: a managed (organization) `remoteControlAtStartup: true`, and whether the
  local file is read before workspace trust (the probe workspace was already trusted); the
  `--settings` flag covers both. Also open, for Kyle: Brief 02 §5.4 proposed dropping the PTY
  fallback for CLIs ≥ 2.1.217; AGENTS.md currently forbids it, so it stays. A `--version`
  timeout is not retried and still sends the probe to the PTY.

- **Fixed for a switch the account file records (2026-11-11): an external Claude CLI account
  switch could retain a model row from the prior login.** Claude readings now carry their
  `.claude.json` identity, and the continuity merger retains a missing model row only from a
  reading of the same identity. Fixtures cover the in-memory and the relaunch path
  (`ClaudeDefaultLoginStoreTests`). Still open for a switch that changes the Keychain
  credential without rewriting `.claude.json` (gate V1's unverified cases). With an inherited
  `CLAUDE_CODE_OAUTH_TOKEN` every reading is Absent, so no model row is retained at all: a
  partial capture drops it instead of keeping it stale.


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
  floor. **Partially discharged 2026-08-08:** all accounts in one Claude lane pass share a
  negative executable-discovery verdict, so a missing CLI triggers at most one full path
  search per pass. **2026-09-21:** the adaptive part shipped as the measured duty-cycle gate
  (`LaneSchedule`), which bounds a CLI lane to half of its trailing window. Successful
  `/usage` probes still run once per configured account; result caching could reduce that
  remaining cost.
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

## Cursor intermittent local diagnostic (2026-09-18)

- One offscreen `--probe-cursor` run returned a transient capture failure despite an
  authenticated CLI. A later run on the same machine parsed the official `/usage` panel
  as a live Pro+ snapshot with 1% included usage and on-demand disabled. The cause of
  the first failure was not captured; do not attribute it to a missing `Included` row.
  If this recurs, add redacted stage diagnostics for auth, boot, autocomplete, and panel
  timeout before changing the parser or retry policy.
- **Cursor MCP approval handoff is unverified live.** Detection and the Review Cursor
  Tools handoff are exercised only by fake PTY fixtures built from a reported older
  screen. Unverified: that the current CLI still prints `MCP Server Approval Required`,
  and that an approval given in the Terminal session persists so the next background
  probe reaches `/usage` instead of the same dialog. On 2026-09-18, a throwaway
  `/usr/bin/true` server in `~/.cursor/mcp.json` did not open any approval gate;
  the probe returned live usage. Find a reproducible unapproved-server case before
  describing the path as supported; see
  `docs/solutions/cursor-agent-usage-feasibility.md`.
- **Killed probes can leave Cursor Agent housekeeping files behind (2026-09-30).** Cleaned
  up on one machine: 7 `~/.local/share/cursor-agent/versions/*/.running/<pid>` markers
  and 12 `~/.cursor/cli-config.json.<pid>.<uuid>.tmp` files, all from dead pids. The
  markers matched probe runs that stopped on the signed-out screen. A normal `/usage` run
  left none. They're harmless, but the probe's SIGTERM→SIGKILL teardown probably
  interrupts the CLI's own cleanup. Unverified: whether Ctrl-C (which the signed-out
  screen explicitly ignores as a login key) lets the CLI exit cleanly on the gate
  screens. Check that against a live gate before changing teardown.

## Sign-in handoff residuals (2026-09-19)

Deferred from `docs/plans/2026-09-19-1236-fix-claude-sign-in-handoff-plan.md`.

- **The widget snapshot read blocks the main thread behind a macOS permission prompt.**
  `UsageStore.refreshAll` → `exportWidgetSnapshot` → `WidgetSnapshotCache.write` →
  `containsIncompatiblePayload` reads the app-group container with a synchronous
  `Data(contentsOf:)` on the main actor. When macOS shows "Headroom would like to access data
  from other apps", `open()` blocks until the user answers, and the popover and menu bar freeze
  with it. Observed 2026-09-19 with `sample`: a debug test host sat in `open()` at 0% CPU for 14
  minutes. Move the container I/O off the main actor. Since the per-account scheduler
  (2026-09-21) the export runs after every primary account's merge — up to one per provider
  per interval plus one per user refresh — rather than once per sweep, so the multiplier on
  this block went up, not down.
- **Local builds re-prompt for the app-group container on every rebuild.** The Mac app is not
  sandboxed and uses the iOS-style group `group.com.kylezantos.headroom`, which macOS 15+ only
  treats as the app's own when an embedded provisioning profile lists it. `Scripts/build-app.sh`
  embeds a profile only when `HEADROOM_PROVISIONING_PROFILE` is set, so dev builds and the
  `HeadroomAppTests` host prompt, and each rebuild re-signs and asks again. It stalls
  `xcodebuild test` for 5–15 minutes per run. Candidate fixes: a Team-ID-prefixed group for the
  Mac build (already an env var, `HEADROOM_APP_GROUP_IDENTIFIER`; the widget extension must
  match), or a no-op widget exporter for the test host. Unverified: whether the shipped
  Developer ID DMG prompts too.
- **Reset leaks old-login usage through the store.** The coordinator ignores live results during
  a reset, but `UsageStore.merge` still publishes a timer poll that lands between Terminal
  opening and `auth logout` finishing, to the card, menu bar, widget and phone projection. The
  sign-in plan stopped coordinator checks during a reset handoff, which removes its own
  contribution. The same window can re-arm the sign-out record's flag, so a reset the user then
  abandons logs one phantom sign-out. Needs a store-level "suppress until handoff ends" gate.
- **Console (API billing) sign-in reads as a transient failure forever.** `auth status` reports
  signed in, `/usage` has no windows, and the outcome is "Couldn't read Claude usage — will
  retry" with `isPermanent == false`. The `auth status` JSON carries `authMethod` and
  `subscriptionType`, which could type this state.
- **Resolved, 2026-10-20: the usage probe ran `claude auth status` on every poll without
  a version gate.** Routine capture no longer launches that command. Existing version
  gating applies to print usage, and signed-out footers are classified without auth preflight.
- **Marker liveness trusts a bare PID.** `setupHandoffIsActive` treats `kill(pid, 0) == 0` as
  alive with no start-time check, so a recycled PID can pin a handoff as open.
- **The header waiting clock follows built-in accounts only** (`headerWaitingAccount`), so an
  extra account's handoff never shows "Waiting 31s".
- **`CLIExecutableLocatorTests.staleGenerationCompletionJoinsReplacementWithoutStartingThirdSearch`
  has an intermittent scheduling failure.** It recurred on 2026-10-20 during the safe
  provider-session checks. The test assumes 20 `Task.yield()` calls let the old completion
  join the replacement before that replacement finishes. If it runs later, it can return
  the same path from `.memoryHint` instead of `.loginShell`. The test and assertion remain
  unchanged. Add deterministic synchronization in a focused follow-up; do not weaken the
  expected result merely to turn the suite green.
- **Code review residuals (ce-code-review run `20260919-164120-47f26bfe`, deferred, none blocking):**
  - `ProviderCardView.swift` is ~1,250 lines and carries pure, non-View routing types
    (`SetupRowRecovery`, `SetupRowChip`, `setupRowChips`, `setupSessionOwnsSurface`,
    `claudeSingleAccountShell`). They belong in Core beside `SetupWaitingPhase`.
  - The sign-in script's `auth status --json` guard has no bound. A hang leaves Terminal blank
    until Headroom's 5-minute timeout; the probe bounds the identical call at 5 seconds.
    macOS has no `timeout(1)`, so this needs a background-and-kill construct that never caps
    `auth login`.
  - `ClaudeUsageCLIProbe.versionOutput` returns stdout without checking the child's
    termination status, so a failed `--version` that still prints a version string is
    classified as supported or too old rather than unreadable.
  - `openPreparedHandoff` writes the per-handoff record through `try?`. A failed write is
    silent, and an `interactive` `.setup` handoff then restores as exit-signalled and is never
    polled after a relaunch.
  - The polled chain re-arms only from a `.stale` result or a `.confirmedAbsent` /
    `.inconclusive` capability failure. A result that stays `.pending`, one rejected by
    `acceptsResult`, or a `.discovering` / `.unknown` capability leaves no check armed until
    the timeout.
  - A never-onboarded config whose `auth status` already reports signed in (login done,
    first-run theme screen not) can read as login-required on the PTY path. The sign-in script
    would say "already signed in" and exit. Staging only downgrades to `interactive` for extra
    accounts below the print-mode floor. Unverified: whether print mode skips that screen.
  - Try Again for a Cursor `.approval` handoff routes to `openSetup`, a login handoff, rather
    than the MCP approval it came from. Pre-existing, same class as the reset-purpose bug fixed
    here.
  - The test host composes a no-op widget exporter, so no app test exercises the signed app's
    app-group entitlement, container lookup, write, or widget read. That path needs a separate
    signed-app smoke.
  - A `.pending` account row that now prints a sentence keeps the 4pt meters gap; CMM4 gives a
    sentence 6pt.
- **Live QA still owed for the sign-in plan:** the fixed-port concurrency check (two Claude
  sign-ins at once; if the second cannot bind its callback, add `.claude` to
  `requiresExclusiveLoginSlot`), what `auth login` exits with when the browser tab is abandoned,
  and the visual acceptance of each waiting phase in both appearances.

## Reliability (carried from earlier review)

- **Unregistered account homes are never swept (2026-09-19).** Nothing reconciles
  `~/Library/Application Support/Headroom/Accounts/<provider>/` against `AccountRegistry`, so a
  home whose registry row is lost stays on disk forever. Found 14 empty Claude homes from
  2026-07-16 on the dev machine (created in same-minute pairs, consistent with tests that wrote
  to the real root before `baseDirectoryURL` injection); moved to Trash by hand. The shipped
  add/remove paths look balanced, so user impact is unproven. Related trap: running
  `claude auth status` with `CLAUDE_CONFIG_DIR` pointed at an empty home makes the CLI write a
  `.claude.json` stub there, so a diagnostic sweep must not probe homes it has not first matched
  to the registry. If a sweep is added, only remove homes that are unregistered **and** have no
  active setup marker.

- **Backoff on repeated failures — shipped 2026-09-21** with the per-account scheduler
  (`LaneSchedule`): consecutive transient failures double the account's spacing from the
  chosen interval, capped at the larger of 30 minutes and the lane's effective interval; a
  permanent setup state stays on cadence. Remaining probe-cost follow-ups from that plan:
  skip the PTY fallback after a print-mode timeout on a print-capable CLI (bounds one bad
  probe to about 25 seconds instead of 80); cache the `--version` band per executable per
  lane pass; and version-gate the per-poll `claude auth status` call.

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
- ~~**The iOS targets compile a hand-picked list of Core files, so a new Core file can break the
  phone build silently.**~~ Resolved 2026-10-04 (iPhone parity U1, `871d2a05`): both iOS targets
  include Core's `Models/`, `Notifications/`, `Settings/`, `Sync/` and `Widgets/` folders whole
  (KTD4), and the iOS simulator build is a pre-PR check in AGENTS.md. Original note:
  `HeadroomIOS` and `HeadroomIOSWidgets` enumerate individual
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
- **Settings captures can still be invalid when WindowServer capture fails.** On
  2026-09-17, the Settings capture path under the Swift 6.3.3 command-line toolchain
  printed `could not create image from window`; its bitmap fallback saved PNGs with a
  blank sidebar, cropped header, and incorrect dark material despite exiting 0. The new
  `--menu-bar-only` acceptance run now fails instead of using that fallback. Do not use
  general-harness fallback captures as visual acceptance. Reproduce with the full Xcode
  toolchain and use an explicitly authorized live Settings check until capture is reliable.
- ~~**The harness's multi-account path renders neither Grok/Cursor nor the spend card.**~~
  Resolved 2026-10-14: `PopoverRenderHarness.multiStore(for:)` now sets up the store the way
  `AppComposition.demoMultiAccountStore` does — every provider in the scenario gets its
  subscription surface, and `AppComposition.demoSpendProviders(for:)` is wired with each API
  surface enabled. `PopoverRenderHarnessStoreTests` pins it (multi-20, multi-4, four-default,
  spend-states). Note: `popover-multi-4` and `popover-four-default` still draw the same pixels by
  design — they differ only in account labels and emails, and a single-account card draws no
  identity row.
- **The harness's `connected` capture can show a Claude "Waiting for sign-in…" card.** Seen
  2026-10-03 on Kyle's machine: `popover-connected-{light,dark}.png` drew the Claude setup-waiting
  card above Codex instead of the connected Claude card. Suspected cause (unverified): the harness
  resets `openedSetupAt` but still restores the real durable handoff markers under
  `~/Library/Application Support/Headroom/Setup`, so a live machine's pending handoff leaks into a
  fixture. Isolate the harness from the real setup-marker directory.
- **`Scripts/capture-demo-screenshots.sh` quits the installed Headroom.** Its macOS half runs
  `killall Headroom` (line 113) before launching the `--demo` build, which also kills the user's
  live menu bar app — against the release-ops rule on broad process termination. Terminate only
  the worktree build's PID, or keep using `HEADROOM_IOS_ONLY=1` until it's fixed.
- **Changing widget providers on the Mac doesn't reach iPhone widgets.** `setWidgetPrioritySource`
  (`UsageStore.swift:485-490`) calls `exportWidgetSnapshot()` but not `exportPhoneSyncSnapshot()`,
  so the iPhone envelope's `widgetProviderSelection` stays stale until the next primary merge.
  Slated for the 2026-10 iPhone parity round.
- **The public iPhone app (1.0, build 24) can't read any current Mac's snapshot.** Built from
  `1f4acb53`, it requires sync schema 1 exactly and a `resetsAt` on every window. Mac 1.1.2
  (Jul 28) moved to schema 2 and today's Mac publishes schema 3 without `resetsAt`, so App Store
  phones paired with an updated Mac show "Snapshot Unreadable" / "Update Needed" — and the
  unreadable copy tells users to "publish a fresh snapshot", which can never help. Fix is shipping
  a current iPhone build (1.5); found 2026-10-04 (see
  `docs/plans/2026-10-04-ios-parity-research/repo-patterns.md`). Kyle accepted waiting for 1.5 over a
  Mac-side schema-1 stopgap because the iPhone app has few users.
- **A bare `--demo` Mac run publishes demo data to the real iCloud store.** `HeadroomApp.swift`
  (~861-890) wires the phone-sync exporter in demo mode, so a properly signed demo build (e.g. a
  screenshot run) overwrites the user's real phone snapshot. Demo must never write KVS (demo plan R3).

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
  `CFBundleShortVersionString`, which a SwiftPM binary has no Info.plist for, so L10A's 10pt
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
- **The automatic summary pill has no obvious way back (2026-09-22).** "Use one automatic
  summary pill instead…" discards the arranged pill list, and the only exit is pressing
  **Add pill** per provider — hinted at by one help line. A user who tried it could not find
  the way back. Remember the last `.providers` selection when switching to `.auto` and offer a
  direct "Restore separate pills" action in the summary state. *Partly addressed 2026-09-23
  (PS1, pill shelf):* the summary state now lists every provider as a card on the "Not shown"
  shelf with its own + and a "Drag a provider up" line, so the exit is visible. The switch still
  discards the arranged list, so restoring several pills is still one add per provider.
- **An Accounts row's actions can wrap onto a line of their own (type audit, 2026-09-24).**
  In the `accounts-multi` render, the Studio row (needs sign-in, capability recovery showing)
  pushes **Sign In** and **Check Now** below the row, right-aligned under the status sentence,
  where they read as belonging to no row. Out of scope for the type/spacing pass; the row's
  trailing cluster needs a stacking rule of its own.
- **Your Pills stacks three help lines (type audit, 2026-09-24).** One under each group label
  plus the "Uses each provider's main account…" footer. The footer states a rule for both
  groups, so it was left in place rather than duplicated into the auto and manual variants of
  the first line. Revisit with the copy for that tile.

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

- ~~**`ProviderSetupRecoveryCard`'s primary is still `.borderedProminent` beside a chip secondary.**~~
  Stale as of 2026-09-19: the card's primary and secondary both use `SetupChipButtonStyle`.
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
- ~~**The iOS mirror still shows its own "Low" chip.**~~ Resolved 2026-10-05 (iPhone parity U8,
  `89a20d57`): the phone draws the popover's shared rows with red critical ink, and
  `MirrorPresentation.showsLowChip` and the phone's own bar view are gone. Original note:
  AP1 removed the macOS popover chip in favour
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
- **Setup body prose still says "connect"** as Headroom's own act. The Claude approval body was
  fixed 2026-09-19 ("Headroom continues as soon as you approve"), when waiting copy came under the
  copy-rule tests. Still open in `CodexSetupViews.swift`: "Headroom reconnects automatically" and
  "Headroom will reconnect when Codex confirms it." One-line fixes if the verb should go everywhere.


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
- **Brand-tinted names are not plumbed to widgets (WCD1).** Widgets take the popover's default
  neutral `accountTitle`; the popover's `AccountTitleInk` preference does not reach the envelope.
  Stated decision, not an accident.
- **Envelope schema stays at 3.** Not built, by decision: percentage mode ("used"), `MeterStyle`
  (format/shape/fill), typed capability state (would let the attention glyph become a word),
  multi-account rows, interactive (`Button(intent:)`) widgets, widget-string localisation. The
  per-widget Style and Color options (widget-styles plan, 2026-10-02) are an App Intent
  *configuration*, not an interactive widget, and need no envelope change.
- **The render harness is macOS-only.** `swift run Headroom --render-widgets <dir>` renders the
  real style bodies with `ImageRenderer` and fails on any element outside its tile. iPhone line
  heights, `.accented`/StandBy as WidgetKit actually draws them, and **Dynamic Type at
  `xxLarge`** still need a device — macOS `ImageRenderer` ignores `.dynamicTypeSize`, so the
  harness's `shrunk` pass (85% tiles) stands in, and its findings are warnings, not failures.
  The 2026-10-04 loading sweep rendered 2,004 tiles with no real-geometry overflow. Its shrunk
  surrogate produced 89 warnings, including mixed-pending Tightest First medium tiles; these
  warnings do not establish actual device Dynamic Type fit.
- **`HeadroomWidgetSharedUI` view code is verified by renders, not tests.** The style decisions
  (ranking, shown providers, shedding ladders, wash segments, color resolver, vessel geometry)
  are Core recipes under `swift test`; the views that lay them out are checked by the
  `--render-widgets` sweep only. Follow-up: `WidgetFontMetricsTests` cross-checking the CoreText
  digit-ink and cap-height port against AppKit.

### Widget styles (2026-10-02)

Plan: `docs/plans/2026-10-02-1247-feat-widget-styles-plan.md`.

- **The Static → App Intent upgrade is unverified on device (KTD1).** Apple documents no
  supported path; developers report placed iPhone widgets freezing until a reboot. Kyle's spike
  check is `docs/qa/2026-10-03-widget-config-upgrade-spike.md`. If it fails, the fallback is a
  release note telling people to remove and re-add the widget.
- **Liquid Level's wash in accented, vibrant and StandBy is reasoned, not measured (KTD9).** It
  draws `.primary` at 0.12 with an accentable top edge; nobody has seen it on a tinted iPhone, a
  Tahoe desktop behind windows, or StandBy.
- ~~**Old data is not dimmed.**~~ Resolved 2026-10-04 (iPhone parity U13): every style takes
  `WidgetFreshnessTreatment` from the KTD15 rule, dims past its threshold (60-minute floor on the
  phone, 120 minutes against the Mac's own export time on the Mac) and hides a number ten minutes
  past its reset; `CompanionTimelineSchedule` schedules both moments. Original note:
  When the Mac sleeps, the envelope stays "live" and an iPhone widget
  can show hours-old numbers in full color, with no footer on small and medium (R14). Needs a
  threshold on `generatedAt` that applies to every style.
- **Per-widget provider choice.** Small Vessel Hero and small Liquid Level show the first widget
  provider (or the second when the first has no value yet). Choosing which provider a widget
  shows would be a third Edit Widget parameter. The Lock Screen widget has this Provider choice
  (2026-10-04 Lock Screen plan); adding it to the home widgets is a separate parity call.
- **The Settings gallery previews Always colored only.** Color mode is not previewed.
- **The status card's vessel keeps its old drawing.** `HeadroomVesselMark` fills by outer height
  and frames at 12×20, unlike `WidgetVesselGeometry` (11:18, inner-height liquid).
- **Liquid Level large can seat a countdown on the wash's top edge.** In the render sweep,
  Codex's "3d 2h" sits on the bright edge line when its level lands at that row's height.
- **AppEnum options mirror Core by hand.** `HeadroomWidgetStyleOption`/`ColorOption` raw values
  must equal `WidgetLayoutStyle`/`WidgetColorMode`; the intent compiles only into the extensions,
  so no test catches a missing case (it renders the default style). The Lock Screen intent
  (`HeadroomLockScreenStyleOption`/`ProviderOption`) maps through exhaustive `switch`es, so a new
  AppEnum case fails the iOS build — but a new Core case with no AppEnum case simply never
  appears in Edit Widget, and nothing catches that.
- **The render harness does not pose the iPhone DEMO 14pt top inset**, so App Store screenshot
  mode could overflow small tiles while the sweep stays green.

### Lock Screen widgets (2026-10-04)

Plan: `docs/plans/2026-10-04-1138-feat-lock-screen-widgets-plan.md`; QA record
`docs/qa/2026-10-04-lock-screen-spike.md`.

- **Two device answers are still owed (U2).** What the widget shows after a reboot before the
  first unlock (KTD13: add an "Unlock to update" status only if the cache read fails there), and
  whether system privacy redaction also blanks drawn shapes or only text. The bodies already draw
  every fill, arc, bar and vessel empty under `.privacy` and `.placeholder` redaction (R16), so
  either answer leaves the layouts unchanged.
- **One-ink grays are chosen from the mock, not measured (KTD5).** `LockScreenWidgetTokens` ink
  levels and the harness's plus-lighter backdrop stand in for vibrant rendering; Kyle's device look
  on dark, light and photo wallpapers, normal and Always On, is the judge.
- **The inline vessel SVGs use `clipPath`.** If CoreSVG drops it on a device, the liquid would
  draw square-cornered; regenerate with `swift run Headroom --generate-lock-screen-vessels`.
- **The macOS harness draws Lock Screen text about a fifth smaller than iOS does.** In the
  2026-10-05 Simulator pass, numerals and captions measured ~1.2× their harness width relative to
  the circle, so Nested Badge clipped "Demo", Grok's mark touched the Tightest Gauge number and
  Liquid Strip truncated "Codex" while the sweep stayed green. Those three were re-spaced; the
  sweep can't catch this class, so judge circle and rectangle fit on a device.
- **No Lock Screen previews in Settings → Widgets & iPhone.**
- **The Lock Screen dims through the stale state, with no "No update since" line.** It takes the
  home widgets' `WidgetFreshnessTreatment` (iPhone parity U13): dimmed data draws every window in
  half ink with the warning glyph, and a window ten minutes past its reset reads "—". There is no
  room for the home widgets' dimmed sentence or "Reset at" note in a circle or the inline line.
- **A lone Cursor pool on the home widgets reads "monthly left"** (`WidgetStyleCopy.leftCaption`),
  which reads as Cursor's whole allowance. The Lock Screen names the pool (R11); the home copy
  does not yet.
- **Nested Rows' two-provider rectangle prints no window names.** It follows the approved design
  05 (mark, nested bars, number); a Cursor row is identified by its mark and equal sibling bars,
  not by its pool name.
- **iPhone 17 and iPad accessory sizes are unpublished.** The harness bounds 68–76 pt circles,
  153–172 pt rectangles and 225–257 pt inline lines (KTD12); layouts flex, but nobody has seen
  them on those devices.

### Xcode 27 test compiler warnings (iOS parity U1, 2026-10-04)

- `NotificationCoordinatorTests.swift:278–279` ignores the result of `schedulerMerge`.
  `ProviderCardIdentityRowTests.swift:378–458` emits actor-isolation warnings. The U1
  Core and Mac suites pass (1,207 and 250 tests); keep these visible for the U20
  integration pass rather than weakening concurrency checking or assertions.
- ~~The iOS UI-test runner emits “Metadata extraction skipped, no AppIntents.framework
  dependency found”.~~ Closed 2026-10-04: re-checked after U14, expected, no action. The runner
  declares no intents; the app (`UsageLeftIntent`, `HeadroomAppShortcuts`) and the widget
  extension both write `Metadata.appintents`, and the app's `AppShortcuts.xcstrings` gives
  the SSU training step its phrase corpus (without it, the step logged “Could not archive SSU
  artifacts” and Siri lost flexible phrase matching).

## Settings sidebar app icon drops its `<feMerge>` filter (2026-10-03)

- `Sources/HeadroomApp/Resources/AppIcon/vessel-app-icon.svg` uses `<feMerge>`, which CoreSVG
  does not support ("Filter primitive: <feMerge> is currently not supported", logged during the
  popover/Settings perf bench). `AppIconGlyph` loads that SVG through `NSImage`, so the Settings
  sidebar's identity mark renders without whatever that filter adds. Flatten the filter into the
  paths or ship a pre-rendered PDF/PNG for the sidebar.

## Popover account layout follow-ups (2026-10-12)

From `docs/plans/2026-10-10-0836-feat-popover-account-layout-plan.md`.

- **The first open after launch draws one column, then two.** The column plan is made as the
  popover closes (the view survives reopening, U1 spike), but the very first open after launch
  has no plan yet, so it lays out one column, measures, and re-renders at two. At multi-20 that
  pass costs about +100ms main-thread CPU and ~290 extra bodies, once per launch; `--bench-ui
  popover` builds a fresh view per open, so every one of its warm opens pays it. A fix would
  persist the last plan (column count and split, keyed by the item IDs) and seed the model with
  it on launch.
- **Hosted App tests quit while the installed Headroom is running.** `HeadroomApp.main`'s
  single-instance guard runs before the XCTest host is recognised, so `xcodebuild test` for
  `HeadroomAppTests` exits at launch ("Headroom is already running … Quit it first") whenever
  `/Applications/Headroom.app` is open. Exempt the XCTest host (`XCTestConfigurationFilePath`,
  as `AppComposition.usesNoOpWidgetExporter` does).
- **Compact rows have no per-account loading pill.** The Standard identity row's pill would
  cost the row's width; the footer's refresh receipt carries progress instead (Kyle,
  2026-10-13). Banked resets moved into the row's tooltip.

## Popover & Settings snappiness residuals (2026-10-03 perf audit)

The audit's fixes 1–6 land in #157 (feather animation scope, scroll chrome out of `PopoverView`'s
body, `MenuBarStatusLabel`, Settings opening on its stored pane, batched Settings-open writes,
the spend month label). Measured offscreen; numbers in the PR. How to measure, and the hot-spot
checklist: `docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md`.

- **Pane switches build in the click's frame, then blur in.** Into Appearance, Widgets,
  Notifications or Accounts takes ~60–70ms (multi-5) before anything moves, ~259ms into Accounts
  at 20 accounts; then `settingsPane`'s 200ms fade from a 3pt blur plays. Candidates: instant or
  ≤120ms opacity-only for clicks (keyboard is already instant, KB1); a `LazyVStack` for the
  account rows; the Appearance specimen builds its card twice (hidden twin) and passes
  `now: Date()`, so it is never equal.
- **Every card re-renders on any store change.** `ProviderCardView` gets fresh closures and `now`
  each pass, so one account refresh re-runs all cards (after #157, ~240ms CPU per refresh at 20 accounts, ~140ms at 5;
  ~360ms / ~150ms before it).
  `PopoverView` also calls `appDisplaySnapshot` ~3× per account and builds `statusInput` twice.
- **First open per launch (M9A arrival) pegs the main thread** ~740ms at 20 accounts after #157 (~890ms before; ~135ms at 5): each meter row makes three state writes in its `.task`.
- **The duplicate-login scan reruns on every Claude capture** while Settings is open (its
  fingerprint carries `capturedAt`), reads every `.claude.json` even with one Claude account, and
  `Task.detached` ignores cancellation, so a 20-account refresh stacks ~20 overlapping scans.
- **The saved-key presence check reads the secret.** `refreshSavedKeyPresence` calls
  `CredentialStore.apiKey(for:)`, which returns key data; an attributes-only existence query
  would do.
- **`--render-popover`'s multi-account path never draws the spend card.** `renderMulti` builds its
  store with `apiSpendProviders: []`, so `spend-states` / `spend-retained` captures show only the
  provider cards, and the spend card (where the month-label formatter hot spot lived) is never
  rendered or measured there.
