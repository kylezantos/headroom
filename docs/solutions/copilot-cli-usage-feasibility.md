---
title: Copilot credit usage comes from the official CLI's session logs and local server
date: 2026-11-02
category: provider-integration
tags: [copilot, cli, usage, session-logs, ai-credits]
---

# GitHub Copilot CLI usage feasibility

## Decision

Copilot is feasible as a Headroom subscription provider with one account and one monthly AI
credit meter. Headroom reads only what the official `copilot` CLI produces: the session logs it
writes under `~/.copilot/session-state/<session>/events.jsonl`, and three calls to its local
stdio server (`ping`, `auth.getStatus`, `account.getQuota`). Polling never sends a prompt,
creates a session, or reads a Copilot or `gh` token.

No single official source is both live and exact. The logs are close but advance only when the
CLI runs. The server's count is coarse and cached. Headroom therefore shows the newest dated
count (a quota snapshot from the logs, or a nonzero server reading) plus every credit the logs
recorded after it, and shows the reading's age once it is more than 15 minutes old.

## Verified surface

Verified on 2026-11-02 with Copilot CLI `1.0.105` on an individual Max plan with a 20,000 credit
monthly allowance. No login, prompt or raw log line was retained.

- `session.usage_record` is written in every mode, interactive and `-p` alike. It carries
  `usage.copilotUsage.totalNanoAiu` and `usage.accounting.usageId`. 10^9 nanoAIU is one credit.
  Records are deduplicated on `usageId`.
- `quotaSnapshots.premium_interactions` appears only on `model.model_call_success` events in
  interactive sessions. Its `usedRequests` is the server's count and its `resetDate` is the real
  next reset (`YYYY-MM-01T00:00:00Z` in every observed case).
- `account.getQuota` over the stdio server returns `entitlementRequests`,
  `isUnlimitedEntitlement`, `tokenBasedBilling`, `usedRequests` and `resetDate`.

## account.getQuota is coarse and cached, not broken

- `usedRequests` follows GitHub's own percentage rounded to the nearest 0.5%, which is 100
  credits at a 20,000 allowance: a reading of 300 means true use between 250 and 350.
- It returned 0 for over an hour from 01:05 while true use reached 284, then returned 300 at
  02:14 when true use was 285.
- Its `resetDate` holds the time of the reading, not a reset.
- Cache lifetime: between 26 and 69 minutes. The reading stamped 01:05:30Z had been replaced by
  02:14:04Z, and that one was still served unchanged 26 minutes later across fresh server
  spawns, so the cache is upstream of the CLI process.

Headroom therefore treats a server reading as a lower bound, never as the figure. Half a
rounding step below the reading is the least use it proves. That bound counts only when it is
above zero, the reading's `resetDate` is at or before now, and that time is inside the current
UTC month. It then replaces the session logs' figure only when it, plus records after it, is
higher, which happens when other clients such as VS Code or github.com spent more than the
rounding hides. A cached 0 can never count, and it would have printed 100% left. A future `resetDate` would mean the CLI now
reports a real reset, so it is used as the reset and not as an anchor, because the reading's
time is then unknown.

## Accuracy against the server

Measured against a server count of 284:

- Ledger alone: 275.2 (3.1% low).
- Snapshot plus later records: 291.5 (2.6% high).
- Records before the 100 snapshot sum to 83.7 (16% low). Records after it sum to 191.5 against a
  rise of 184 (4% high).
- Cause of the gap: rounding explains part of it, because the snapshot of 100 stands for any
  true value from 50 to 150, and the server read 104 at about that time. The remaining 20 or so
  credits before the snapshot are unexplained. Session folders removed from `session-state`
  during testing are one candidate, since their records are gone.

`swift run Headroom --probe-copilot` prints the ledger-only sum and the value the provider
shows on separate lines, with the entitlement, reset, newest evidence age and the resulting
freshness. It never prints the login or a log line. Run under `PATH=/usr/bin:/bin` on
2026-11-02 at 02:40Z, while GitHub's own count was 285, it printed:

```
RESULT: live Copilot snapshot, 1 window(s)
  ledger only (this month's usage records, no snapshot or server count): 275.2 credits
  shown (logs, raised only by the server reading's lower bound): 291.4 credits
  newest evidence age: 3485 s
  entitlement: 20000
  reset: 2026-12-01T00:00:00Z  reset-evidence=scheduled age-seconds=3485
  freshness: stale (observed 3485 s ago)  1% used
```

291.4 is 2.2% above 285. Treating the server's 300 as the figure gave 5.3% above. The reset
comes from an interactive session's quota snapshot. The row is stale because the newest
evidence is the last CLI call about an hour earlier.

## Rejected and unevaluated sources

- The private `copilot_internal/user` endpoint is exact and live, and was used here as a
  reference only. Headroom does not call it: `AGENTS.md` forbids calling Cursor's private
  dashboard endpoints (Cursor ToS section 1.5), and the same rule applies here.
- The documented REST endpoint `GET /users/{username}/settings/billing/ai_credit/usage` exists.
  It needs the `user` scope on `gh` and excludes organization seats. Unevaluated.

## Data limitations

- The logs carry no login. After the CLI's login changes, Headroom shows the meter as
  unavailable until a dated count observed after the change, because the new account may
  already have spent credits elsewhere.
- Use from other clients (IDE, web) reaches the meter only through a server reading or an
  interactive session's quota snapshot.
- A signed-in account with nothing recorded this month, an unlimited allowance or a zero
  allowance shows an unavailable row rather than 100% left.
- A Headroom-owned `COPILOT_HOME` never receives the session logs, so Copilot stays
  single-account.
