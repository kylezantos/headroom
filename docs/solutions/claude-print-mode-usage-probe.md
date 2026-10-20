---
title: Claude usage capture is print-first — `claude -p "/usage"` beats the PTY panel
date: 2026-07-31
category: integrations
module: HeadroomCore/ClaudeUsageCLIProbe
problem_type: reliability
component: provider_probe
symptoms:
  - The "Weekly (Fable)" row intermittently missing or stale in the popover/widgets while claude.ai showed it fine
  - Occasional whole-capture parse failures after CLI TUI redesigns
  - 20–30s per Claude poll
root_cause: fragile_capture_surface
resolution_type: capture_path_change
severity: medium
tags: [claude, fable, probe, print-mode, pty, reliability]
---

# Claude usage capture is print-first — `claude -p "/usage"` beats the PTY panel

## Problem

Headroom read Claude usage by driving the interactive `claude` CLI in a pseudo-terminal,
typing `/usage`, and parsing the TUI panel. The panel is repainted several times via cursor
positioning, renders the per-model weekly rows ("Current week (Fable)") in a later paint
than the main limits, and redesigns occasionally (2.1.218 boot screen). Each of those is an
intermittent way to lose a row — most visibly the Fable sub-limit, which claude.ai displayed
reliably the whole time.

## What didn't work (all previously tried)

- **Longer quiet windows** (2.5s → 4s) bridged the model-row settle pause but remained a
  timing bet, not a guarantee.
- **Per-window continuity/freshness** (`UsageContinuityPolicy`) made partial captures honest
  — retained rows show as stale, then unavailable — but could not make captures complete.
- **Boot-screen reclassification** (2.1.218) fixed one redesign; the next one would break
  capture again.
- Server-side omissions (Jul 12–17, 2026) are unfixable client-side on any path; the row
  data simply isn't sent to the CLI.

## Solution

Claude Code dispatches slash commands **locally in print mode**: `claude -p "/usage"
--no-session-persistence` prints the full settled usage report to stdout in ~2s, with no
model call (`$0.0000` cost), including per-model rows and reset labels, one window per line:

```
You are currently using your subscription to power your Claude Code usage

Current session: 6% used · resets Jul 31 at 5:20pm (America/Los_Angeles)
Current week (all models): 4% used · resets Aug 6 at 10am (America/Los_Angeles)
Current week (Fable): 7% used · resets Aug 6 at 10am (America/Los_Angeles)
```

The probe now tries this first and keeps the PTY panel as fallback. Details that matter:

- **Same compliance posture.** The official client makes the request; we read its stdout.
  No OAuth reuse, no endpoint calls.
- **Version-gated to ≥ 2.1.217** (oldest binary verified to dispatch `/usage` locally under
  `-p`). Below the floor a CLI might forward "/usage" to the model as a *paid prompt* every
  poll — so unknown/old versions stay on the PTY path. Don't lower the floor without
  verifying against that exact binary.
- **Output-validated.** The print result is accepted only if `ClaudeUsageParser` finds at
  least one window. A logged-out or API-key login prints a `Total cost: $0.0000` report
  instead — parse-empty, so it falls through to the existing typed degrade paths.
- **Plan pill.** Routine captures no longer launch `auth status` to obtain a tier.
  Panel text supplies it when present; a print report without a tier omits the pill.
  Missing metadata must not cause another credential-mutating process to start.
- **Multi-account unchanged.** The same `CLAUDE_CONFIG_DIR` override routes print-mode runs;
  a print miss falls through to the PTY's recognized login/trust/unknown-screen checks.
  Unknown screens never receive input.
- Print mode skips the workspace-trust dialog, and `--no-session-persistence` stops the
  5-minute polls from accreting transcript files.

## Why this works

The PTY failure class was *rendering*: repaint garbling, late-arriving rows versus quiet
windows, boot-screen drift. Print mode has no rendering — the CLI fetches utilization once
and writes the finished report atomically. What remains is only the honest failure mode
(server omits a row), which `UsageContinuityPolicy` already presents truthfully
(see `logic-errors/claude-partial-usage-window-freshness.md`).

**Session-lifecycle limit (October 2026).** Rendering completeness does not establish
credential persistence. Controlled tests on official CLI 2.1.302 and 2.1.303 found normal
exit could abandon an in-flight synthetic renewal even after valid cached usage. Removing
the redundant auth-status preflight reduces one exposure; print/PTY termination remains
subject to the upstream limitation. See `docs/qa/2026-10-20-safe-provider-session-fixes.md`.

## Prevention

- When scraping a TUI proves flaky, check whether the same CLI exposes the command
  non-interactively (`-p`/print mode, `--json`, screen-reader/a11y flags) before hardening
  the scrape. `--ax-screen-reader` was the runner-up here: flat text, but still interactive.
- Gate new CLI surfaces on the oldest *verified* version when the miss-behavior is costly,
  and validate output shape before trusting it.
- Keep the old path as fallback until telemetry/time proves the new one universal.
