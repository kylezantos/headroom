---
artifact_contract: "ce-handoff/v1"
created_at: "2026-09-21T18:05:28Z"
title: "Headroom per-account polling: PR #128 merged, follow-ups and verification status"
summary: "The per-account due-queue scheduler (tested envelope of 20 accounts) shipped in PR #128; this handoff carries the unverified-on-Mac status, the parked review findings, and the unscoped side-by-side layout ask."
keywords: ["headroom", "polling", "scheduler", "multi-account", "duty-cycle", "LaneSchedule", "AccountProbeScheduler", "PR-128", "follow-ups"]
cwd: "/home/user/headroom"
resume_focus: "Confirm the Mac verification of the merged scheduler, then pick up the parked follow-ups from PR #128 or the side-by-side provider layout ask"
repository: "kylezantos/headroom"
repo_root_sha: "653113a158171fde603705bdef1c76d3b04c1c01"
branch: "claude/multi-account-layout-feedback-p6m3et"
head: "f2f2c29e35c589e96f4d11c264e211886ef12cc8"
---

# Headroom per-account polling — handoff

## Objective and where it stands

The session started from Twitter feedback asking for (a) more than 5 accounts per provider and
(b) side-by-side provider columns in the popover. The user chose to pursue (a) first with these
decisions, all the user's: no fixed cap; the poll interval becomes a per-account promise; when
overloaded, stretch the interval and say so in Settings; a due-queue scheduler; and a **product
principle saved to AGENTS.md** — every change applies to all four providers (Claude, Codex, Grok,
Cursor) and every account unless the transport genuinely prevents it, and any exception must be
stated explicitly.

That work shipped as **PR #128** (`feat(engine): per-account polling schedule with a tested
envelope of 20 accounts`), merged by the user into `main` at 8d50272 on 2026-09-21. Item (b),
side-by-side columns, was **never scoped or started**.

## Verification status — read this first

The implementing session ran in a Linux container with **no Swift toolchain**. Nothing on the
branch was compiled or run there; correctness rests on six read-only review passes traced from
source (their findings and fixes are listed in the PR body). The PR body asked the user to run
`swift build`, `swift test`, the `HeadroomAppTests` Xcode scheme, `swift run Headroom --demo
multi-20`, and `--probe-claude` on the Mac before merging. **The user merged without reporting
results in the session**, so whether that run happened, and whether it passed, is unknown here.
Treat `main` as unverified until someone confirms it; the most likely first failures would be
Swift 6 concurrency diagnostics in `Sources/HeadroomCore/Engine/AccountProbeScheduler.swift` or
test-timing assumptions in `Tests/HeadroomCoreTests/AccountProbeSchedulerTests.swift`.

## Authoritative references (repository-relative, at main 8d50272)

- `docs/plans/2026-09-19-2217-feat-per-account-polling-schedule-plan.md` — the unified plan.
  R1–R21 are the product contract, KTD1–KTD14 the technical decisions; KTD5 (backoff), KTD7
  (priority requests, with a 2026-09-21 session-settled note on user-only passes) and KTD8
  (generations per lane pass) are the ones follow-ups touch.
- `docs/solutions/architecture-patterns/per-account-polling-measured-duty-cycle.md` — why the
  gate is measured rather than estimated, why the scheduler keeps its own attempt clock, and
  why only user work bypasses the gate. Read before changing any due-time logic.
- `AGENTS.md` — "Product principles (Sep 2026)" (parity rule), the Engine architecture lines,
  and the rewritten polling gotcha ("Polling is per account, not per sweep").
- `Sources/HeadroomCore/Engine/LaneSchedule.swift` — pure decisions: `nextDue` (backoff floored
  at the effective interval), `effectiveInterval` with the 90 s `cadenceTolerance`,
  `mayStartTimerProbe` / `budgetReopens` (the duty-cycle gate).
- `Sources/HeadroomCore/Engine/AccountProbeScheduler.swift` — the engine: `markAllDue`,
  `requestPriority`, `withdraw`, `nextSerialKey` (gate + user-only narrowing), `probe`.
- `Sources/HeadroomCore/Engine/UsageStore.swift` — `refreshAll`, `setSurfaceEnabled`, and the
  `AccountProbeSchedulerHost` conformance at the end of the file.
- `BUGS.md` — the backoff item is closed with follow-ups; the "widget snapshot read blocks the
  main thread" item now notes the export runs per primary merge.
- PR #128 body — "Review" (applied) and "Unapplied review findings" (parked) sections.

## Parked follow-ups (from the review, not started)

These are my reading of the review output, not user decisions; the user has not prioritised
them. Listed in the order I would take them:

1. **Launch and every Refresh bypass the gate** (KTD2, by design). At 20 Claude accounts on the
   PTY path that is up to ~27 min of back-to-back CLI load with the Refresh button hidden. Option:
   let the launch refresh mark accounts due without `userPending` so the gate applies, primary
   first. Touches `UsageStore.start()` / `refreshAll()` and `AccountProbeScheduler.markAllDue`.
2. **Widget/phone export I/O on the main actor** now fires after every primary merge, not once per
   sweep. Fix is the BUGS.md item: move `WidgetSnapshotCache.write` container I/O off the main
   actor.
3. **Permanent non-never-signed-in states never back off** (reauth, trust required): such an extra
   can take a PTY probe every interval. Candidate: apply the 4× extra rule to all permanent states
   on non-primary rows (`LaneSchedule.nextDue`; KTD5 would need amending).
4. **Popover provider-level "Check Again" still triggers a full refresh**
   (`Sources/HeadroomApp/UI/PopoverView.swift`, `onRetrySetup`). One-line change to
   `dispatchDueNow(for:)` if wanted; Settings already does this.
5. Smaller: a hung provider fetch parks its lane (bounded only by provider deadlines; Claude
   worst case ≈ 90 s, the stop-loss comment says ~80 s); a priority probe's capability verdict
   reaches the coordinator twice (idempotent); README could state that under overload extras
   refresh slower than the primary and the popover header shows it.

## Wrong paths already rejected — do not retry

- An **estimated** stretch factor (mean probe duration × account count) instead of the measured
  gate: one slow PTY probe inflates it for hours and it cannot tell the user what happened.
- Using `UsageSnapshot.capturedAt` as "when did we last try": failures deliberately keep the old
  capture time (continuity), so a failing account would look ever more overdue and starve others.
- Letting a single-account request (Check Now, Make Main, setup check) start a normal lane pass:
  it fans out to every due sibling and breaks the AGENTS.md "refreshes only it" contract.
- Filtering the reset deadline against `now` instead of the account's last attempt: the engine
  wakes at deadline + grace and finds nothing due.
- Rounding the effective interval up without a tolerance: every healthy provider reads as
  "stretched" because probe starts trail the interval by wake jitter.
- Reintroducing Claude OAuth/Keychain reads is prohibited (AGENTS.md hard constraint).

## Local state

- Clean working tree. The designated branch `claude/multi-account-layout-feedback-p6m3et` is
  fully merged; per the session rules any follow-up must restart it from `origin/main` rather
  than stacking on the merged history.
- The Compound Engineering plugin used for the workflow (ce-brainstorm, ce-plan, ce-work,
  ce-code-review, ce-compound, ce-handoff) is installed in the user's Claude desktop app; the
  clone this session used lived in a container scratchpad and does not persist.

## Plausible next steps

- **If the Mac verification has not run**: run it before anything else; fix forward on a branch
  restarted from `main` if it fails. (My inference; the user has not said whether they ran it.)
- **Then either** take the parked follow-ups above (sequential, start with 1), **or** scope the
  original item (b), side-by-side provider columns in the popover, which has no plan yet and
  would start at ce-brainstorm. These are the two open directions; the user has not chosen.
