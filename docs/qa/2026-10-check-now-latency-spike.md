# Check-now latency spike (U6) — protocol

Plan: `docs/plans/2026-10-04-0923-feat-ios-parity-round-plan.md` (U6, KTD14, KTD8, stop
condition 3). Field contract: `docs/plans/2026-10-04-ios-parity-sync-field-contract.md`
(check-now request and receipt, Decision 2).

**Question:** on Kyle's signed Mac and physical iPhone, how long does a phone check-now
request take to reach the Mac and come back, how often does iCloud key-value storage let the
Mac write while it publishes at the 20-account envelope, how long does one probe take per
lane, and does the menu bar Mac receive phone-written changes while its display sleeps?

This file is instructions and empty result tables only. Nothing here has been measured yet.

## Provisional constants (in code until this spike replaces them)

All in `Sources/HeadroomCore/Sync/CheckNowProtocol.swift` (`CheckNowTiming`):

| Constant | Value | Source |
|---|---|---|
| Acknowledgement timeout (phone) | 60 s | KTD14.7 |
| Request age limit (phone resume; Mac launch backstop) | 10 min | AE2, KTD14.3 |
| Clock skew allowed at the Mac's launch scan | 2 min | KTD14.3 |
| Finish window | ack + max(3 min, largest lane's accounts × per-probe time) | KTD14.7 |
| **Per-probe time** | **30 s — provisional** | Claude PTY fallback upper bound (AGENTS.md: print path ~3–5 s, PTY ~20–30 s) |
| Cooldown (Mac) | 60 s | KTD14.4 |
| Receipt spacing while a check runs (Mac) | 15 s | KTD8 |
| Request-key retention (Mac prune) | 30 days | KTD14.8 |

**Fallback rule (plan stop condition):** if the Mac does not receive phone-written request
changes while running in the background (display asleep, system awake), or request→ack p95
exceeds 60 s with the 20-account fixture publishing, U9 ships pull-to-re-read for 1.5
instead of check-now, and this is reported to Kyle.

## Prerequisites (decide before running)

1. **Signed builds with the iCloud key-value entitlement on both devices, same Apple ID.**
   A dedicated test Apple ID is preferable: the spike writes request and receipt keys.
2. **A phone that can issue requests.** Today the phone cannot: `CompanionLoaderAdoption`
   is off (the P5 identity gate failed), so phone surfaces resolve the v3 key, the
   resolver's winner is never v4, and `CheckNowClient.pull` correctly answers
   `.rereadOnly`. The spike needs a DEBUG-only harness on the phone (U9's pull, or a spike
   branch) that resolves the live KVS keys **with an empty cache** — never the App Group
   cache, so no cached account content is served — calls `CheckNowClient.pull(snapshot:)`,
   and calls `update(snapshot:)` on every `didChangeExternallyNotification` and at each
   `nextDeadline`. Do not flip `CompanionLoaderAdoption` for this.
3. **The 20-account publishing load.** `--demo multi-20` never writes iCloud (R37, KTD21), so
   it cannot produce the write pattern. Either sign 20 accounts into one provider on the test
   Mac, or approve a DEBUG-only publisher harness that feeds the multi-20 fixture into the
   real `CompanionPublisher` against the test Apple ID. This needs Kyle's decision.
4. **Logs.** Both sides log one line per step under subsystem `com.kylezantos.headroom`,
   category `checknow` (request IDs shortened to 8 characters):
   - phone: `phone request <id> written`, then `phone request <id> <phase> after <s>s` on each
     phase change (`checking` = acknowledged, `finished`/`cooldown` = complete).
   - Mac: `mac request <id> admitted (live|launch)`, `mac receipt <state> for <ids>`,
     `mac landed <provider> <n>/<total>`.
   Stream them with
   `log stream --level info --predicate 'subsystem == "com.kylezantos.headroom" AND category == "checknow"'`
   on the Mac, and Console.app with the iPhone selected for the phone. Phone durations are
   measured on the phone clock from `askedAt`; never subtract a Mac timestamp from a phone
   timestamp.

## Runs

Run each scenario **20 times** (p95 needs at least 20 samples). Wait at least 70 s between
pulls so each lands outside the Mac's 60 s cooldown, unless the scenario is about cooldown.

### A. Request → acknowledgement and finish, Mac awake

1. Mac: Headroom running, sync on, popover closed, display on.
2. Phone: pull. Record the phone's `checking after` seconds (request → ack) and
   `finished after` seconds (request → Just now).
3. Mac: note the time between `admitted` and the finished `mac receipt`.

### B. Same, phone → Mac direction under load

Repeat A while the Mac publishes the 20-account load (prerequisite 3). Also record the
Mac's write cadence: from `--dump-phone-sync` before and after a 10-minute window, count
publishes (generation delta) and receipt writes (log lines), and note any quota event.

### C. Mac display asleep, system awake

1. Mac: `caffeinate -s` in Terminal (keeps the system awake), then sleep the display only
   (`pmset displaysleepnow`).
2. Phone: pull. Record whether `admitted (live)` appears on the Mac at all, and the ack and
   finish times.
3. Repeat with the Mac fully asleep: expect "Your Mac hasn’t answered…" at 60 s; wake the Mac
   within 10 minutes and record whether it runs one refresh and the phone finishes (AE2).

### D. Per-probe time per lane

During runs A and B, take consecutive `mac landed <provider>` lines for the same provider:
the gap is that lane's per-probe time. Record Claude (CLI, serial), Grok and Cursor (CLI,
serial) separately; Codex is the concurrent HTTP lane and is listed for completeness.

### E. Both directions with two phones (V19)

iPhone and iPad pull 2 s apart. Record that the Mac logs one refresh (one set of `landed`
lines) and both devices reach `finished`.

## Results

### Latency (seconds, phone clock)

| Scenario | n | request→ack p50 | request→ack p95 | request→finish p50 | request→finish p95 | Notes |
|---|---|---|---|---|---|---|
| A. Mac awake | | | | | | |
| B. Under 20-account load | | | | | | |
| C. Display asleep, system awake | | | | | | |
| C. Mac asleep, woken < 10 min | | | | | | |
| E. iPhone + iPad | | | | | | |

### Write throttling (10-minute window, 20-account load)

| Metric | Value | Notes |
|---|---|---|
| Publishes (generation delta) | | |
| Receipt writes | | |
| Writes per minute | | target ≤ ~6 (KTD8) |
| Quota events | | |
| Largest receipt gap while running | | expect ≤ 15 s spacing |

### Per-probe time by lane (seconds)

| Lane | n | p50 | p95 | max | Notes |
|---|---|---|---|---|---|
| Claude (serial CLI) | | | | | |
| Grok (serial CLI) | | | | | |
| Cursor (serial CLI) | | | | | |
| Codex (concurrent HTTP) | | | | | |

### Background delivery

| Mac state | Request received? | Notes |
|---|---|---|
| Display asleep, system awake | | |
| Fully asleep, then woken | | |

## After measuring

- Replace `CheckNowTiming.provisionalPerProbeSeconds` with the measured p95 of the slowest
  serial lane, and revisit the 60 s acknowledgement timeout against the request→ack p95.
- If background delivery fails or request→ack p95 > 60 s under load: stop U9's check-now
  path, ship pull-to-re-read for 1.5, and report to Kyle (plan stop condition).
