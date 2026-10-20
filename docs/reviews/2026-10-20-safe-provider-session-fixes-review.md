## Code Review Results

**Scope:** current main -> safe shipping subset; automatic-renewal prototypes excluded.
**Intent:** reduce unnecessary authentication commands and recover already-renewed Codex
sessions while preserving explicit manual sign-in.
**Mode:** report-only review; fixes applied separately by the shipping workflow.

Local passes: correctness, project standards (root AGENTS.md/CLAUDE.md), testing,
maintainability, security, reliability, Swift/iOS, agent-native diagnostics and learnings.
These ran sequentially in one context per repository instructions. They are not independent.

### Applied

| # | File | Fix | Evidence |
|---|------|-----|----------|
| 1 | `ClaudeUsageCLIProbe.swift` | Recognize returning-user signed-out footers before ready markers and directly from print output; send no usage input and skip unnecessary PTY fallback | New modern/legacy PTY and print fixtures failed before the fix |
| 2 | `SessionReliabilityRecord.swift` | Count unchanged-token Codex401 as rejected-request edges, separately from sign-out | New repeat/recovery test failed before the fix |

Both originated in the independent Claude adversarial pass. Fixes remain in the same
shipping commit; no credential refresh/writes were added.

### Actionable Findings

None remaining after the two fixes. The peer's proposed time-based forced Codex sign-in
was not adopted: elapsed time does not prove revocation. The approved retryable state
already offers Sign In Again on the Mac. Phone/widget escalation remains a documented
follow-up, not a claim of completed recovery.

### Learnings & Past Solutions

Print-mode version gating and the per-window freshness rules in
`docs/solutions/claude-print-mode-usage-probe.md` and
`docs/solutions/logic-errors/claude-partial-usage-window-freshness.md` remain intact.

### Coverage

- Cross-model route: `claude`; `model_requested=opus`; `model_actual=claude-opus-5-5`;
  `effort_requested=high`; `effort_actual=unverified`; `receipt_supported=true`;
  `independence_verified=true`.
- Findings mechanics ran before and after reconciliation; zero malformed findings.
  Three advisory observations cover persistent uncertainty, conservative coverage and
  the intentional absence of a Claude plan label when usage supplies none.
- Independent validator batch did not run: repository instructions map subagents to
  sequential main-thread work. Validation coverage is degraded; the regressions were
  reproduced and the fixes tested in-thread. No independent-validator claim is made.
- Remaining limitations: real persisted rotation and sign-out reduction are unproven;
  original Claude shutdown behavior remains; collector cost at multi-20 is unmeasured.
- CLI locator scheduling flake and attention/coverage follow-ups are recorded in BUGS.md.

---

### Verdict

Ready for the safe-subset PR: final checks passed (1,915 Core tests, 350 hosted
Mac tests, Swift build and iOS app/widget build). No open P0/P1 or actionable
finding remains. This review does not accept the unfinished automatic-renewal plan.
