---
title: Per-account polling budgets on measured probe time and its own attempt clock
date: 2026-09-21
category: architecture-patterns
module: HeadroomCore/Engine
problem_type: architecture_pattern
component: service_object
severity: medium
applies_when:
  - Adding accounts, providers, or any work that lengthens a CLI lane's pass
  - Changing when an account is considered due, overdue, or backed off
  - Reporting a poll cadence to the user that the app may not be able to keep
  - Tempted to derive scheduling state from a snapshot's capture time
tags: [polling, scheduler, duty-cycle, backoff, multi-account, claude, codex, grok, cursor]
---

# Per-account polling budgets on measured probe time and its own attempt clock

## Context

Until Sep 2026 one global timer refreshed every account of every provider each interval, and the
account cap of 5 per provider was what kept a CLI lane's serial sweep inside that interval. Raising
the cap to a tested envelope of 20 (PR pending on `claude/multi-account-layout-feedback-p6m3et`)
made the sweep longer than the interval on the Claude lane at its floor, so the timer was replaced
by a per-account due queue (`LaneSchedule` decisions, `AccountProbeScheduler` engine). Three
choices in that design are not recoverable from the code alone and were each reached after a
worse first draft.

## Guidance

**1. Budget on measured busy time, not an estimated stretch.** The first draft computed an
"effective interval" up front from mean probe duration times account count and slowed every
account to it. That has two failure modes: a single slow PTY fallback (20–30 s against a 3–5 s
print-mode probe) inflates the mean for hours, and an estimate can never tell the user what
actually happened. `LaneSchedule.mayStartTimerProbe` instead keeps a per-lane log of real
`ProbeSpan`s and lets a timer-driven probe start only while busy time in the trailing window
(`2 × chosen`) is at most `dutyCycleCeiling` (0.5). The interval the Settings row reports,
`LaneSchedule.effectiveInterval`, is `max(chosen, longest on-cadence attempt gap)` rounded up
to a minute: a measurement of the cadence accounts really saw. A one-off outage therefore clears
within one normal pass instead of being averaged away.

**2. The scheduler owns its attempt clock.** `UsageSnapshot.markedStale` and the continuity merge
deliberately keep the prior `capturedAt` on a failed probe so the UI can show dimmed last-known
data (KTD7 in the original polling plan). That makes `capturedAt` unusable as "when did we last
try this account": a failing account would look older every tick and win the most-overdue race
forever, starving healthy siblings. `LaneSchedule.AccountRecord` carries `lastAttempt` and
`previousAttempt` written by the scheduler at probe start; `attemptGap` and all due-time
arithmetic read those, never the snapshot.

**3. User work bypasses the budget, timer work waits, and only user work spins the UI.** A closed
gate narrows a serial lane's candidates to the user-requested accounts instead of ending the pass
(`AccountProbeScheduler.nextSerialKey`), so Check Now, Make Main, Check Again and a surface
re-enable always run at once while their time still counts against the budget. `isRefreshing`
follows user-initiated work only; a timer pass that drains for a minute must not spin the header,
because at the envelope the lane is busy most of the time by design.

Two bounds keep the queue honest without a hard cap: per-account failure backoff
(`chosen × 2^n`, capped at `max(30 min, effective)`; a permanent setup state such as signed-out
or trust-required is not a failure, so it keeps its cadence instead of drifting to the cap), and a
never-signed-in extra account waiting `4 × chosen` unless it is the provider's selected primary.

## Why This Matters

The product goal is real-time, honest numbers for every provider and every account. A scheduler
that estimates rather than measures either under-reports the delay the user is living with or
throttles every account to protect against a transient. Deriving overdue-ness from a timestamp
that failure preserves silently starves the accounts that work. Both mistakes are invisible in
unit tests that mock a single fast provider; they only show up with many accounts and one slow
or broken one, which is exactly the envelope this design exists for.

## When to Apply

- Any new provider or transport must join a lane: `.serial("<name>")` for one-process-at-a-time
  CLIs, `.concurrent` for HTTP. Only serial lanes carry the duty-cycle log; a concurrent lane's
  cadence row reports the chosen interval because nothing queues behind another account there.
- Parity rule: a mechanism added here (backoff, priority, cadence row) applies to Claude, Codex,
  Grok and Cursor alike; document a transport exception in AGENTS.md rather than scoping it.
- When a demo or live check at `--demo multi-20` shows the Settings row stretched, that is the
  gate doing its job, not a bug: the fix is a longer chosen interval or fewer accounts, never a
  higher ceiling.

## Examples

Twenty Claude accounts, 5 s each, chosen interval 2 min: the first pass runs ~100 s of probes.
The second pass starts at the chosen 2 min while the trailing 4-minute window still holds all of
the first pass, so after ~20 s more busy time the budget (120 s) is spent, the gate closes, and it
reopens as the first pass's spans age out of the window. The reported effective interval settles
above 2 min. Halve the accounts and it reads exactly the chosen interval again. Tests: `LaneScheduleTests` (gate arithmetic and
`budgetReopens`), `AccountProbeSchedulerTests` (priority bypass, coalescing, idle waits),
`PollPhasingTests` (engine wake through the live scheduler).

## Related

- `docs/solutions/logic-errors/claude-partial-usage-window-freshness.md` (why `capturedAt` and
  per-window freshness are provenance, not scheduling state)
- `docs/solutions/claude-print-mode-usage-probe.md` (why one Claude probe can cost 3 s or 30 s)
- AGENTS.md → Gotchas → per-account polling
