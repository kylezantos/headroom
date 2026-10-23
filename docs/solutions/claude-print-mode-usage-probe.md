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
tags: [claude, fable, probe, print-mode, pty, reliability, remote-control, diagnostics]
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

## The PTY fallback opts out of Remote Control (October 2026)

With Remote Control auto-connect on (CLI `/config` "Enable Remote Control for all
sessions", the Desktop app's "Connect new sessions to Remote Control", or VS Code's
toggle), **every interactive `claude` process registers a session at claude.ai/code**. A
user on Headroom 1.0.9 (PTY-only) collected about 50 stray "<hostname>-<adjective>-<noun>" sessions
overnight. Print mode is not interactive and the docs tie auto-connect to interactive
processes, so only the PTY fallback was exposed; the owner's own 2.1.218 boot capture in
`ClaudeProviderTests` even shows `/rc connecting…`.

Two layers, both session- or workspace-scoped, never touching the user's settings:

1. **Per launch:** `interactiveArguments(claudePath:versionOutput:)` adds
   `--settings '{"disableRemoteControl":true,"remoteControlAtStartup":false}'`.
   `disableRemoteControl` refuses auto-start whatever enabled it. In 2.1.303,
   `remoteControlAtStartup` resolves project/local `false` first, then policy, flag and
   user settings in that order, so the flag value beats a user-scope `true` but not a
   managed one. Inline-JSON `--settings` exists in 1.0.90, 1.0.128, 2.0.77, 2.1.216 and
   2.1.303, and all of them keep unknown settings keys (passthrough schema); 1.0.50 has no
   such flag. A readable version below 1.0.90 launches bare. An unreadable one keeps the
   flag, because it is almost always a slow or reformatted current CLI.
2. **Per workspace:** `ClaudeUsageWorkspace.ensureDirectory(at:)` writes
   `.claude/settings.local.json` with `remoteControlAtStartup: false` (0600, directory 0700,
   other keys kept, a non-object file left alone, best effort). A local `false` outranks
   every source, managed settings included. It may not be read before workspace trust,
   which is why it is the second layer.

The PTY also sets `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` (documented in the Claude Code
environment-variable reference), the interactive counterpart of `--no-session-persistence`.

**The print path's arguments are unchanged.** It is every user's hot path. Real 2.1.303
accepted `--settings` under `-p` and still printed a parseable report, but no evidence says
`-p` registers sessions, and an older or future CLI that rejected the flag would stop all
Claude polling. **Its inputs did change, though:** `claude -p` runs in the same workspace,
so it now also reads the workspace's `.claude/settings.local.json` with
`remoteControlAtStartup: false`. One real 2.1.303 print run in a folder holding that file
exited 0 with a parseable report and no stderr; a recheck in the real workspace is tracked
in `BUGS.md`. Never use `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` for this: it also turns
off feature-flag fetching, which can change `/usage` itself.

## Telling the failures apart (October 2026)

"Claude opened an unrecognized setup screen" now has one producer: the PTY boot classifier
returning `.unknown` (the `auth status` preflight that also produced it was removed in #192).
`ClaudeUsageCLIProbe.captureWithTrace()` records which stage decided the result, and
`--probe-claude` prints it through `ClaudeCapabilityDiagnostic`:

- `print-stage=` `report | timedOutAfterReport | signedOut | versionUnavailable |
  versionUnreadable | versionBelowFloor | timedOut | launchFailed | unparseable`, plus
  `print-retry-stage=`;
- `pty-remote-control-opt-out=applied|omitted`, `pty-boot=`, and after a ready prompt
  `pty-panel=parsed|unparseable|empty|signedOut`;
- for an unrecognized screen, `pty-boot-fingerprint bytes=… prompt-marker=… try-placeholder=…
  banner=… remote-control-text=… first-line-sha256=<8 hex>`, never the text. The hashed line
  skips escape residue, border rows, the "Claude Code" banner, welcome lines and lines with
  an "@" or a path, which can carry a name, email or home folder;
- `failed-stage=` naming the stage that kept usage from being read. It is decided from the
  trace, so an unparseable PTY panel is named even though the result still reaches the
  provider as panel text (and becomes its transient stale state there).

**Timeouts keep what was already printed.** Some CLIs print the whole report and then hang
on shutdown (hooks, MCP servers, the exit limitation above). On a deadline the probe kills
the process, reads whatever stdout is already in the pipe without waiting for EOF (a hook
or MCP process can still hold the write end), and classifies it like normal output. A usable
report is accepted as `timedOutAfterReport`, with no retry and no PTY. Only when nothing
usable was printed is `-p` retried once with a 40 s deadline before the PTY: a cold start
would slow the PTY too, and the retry avoids an interactive session. Unparseable output is
not retried. The worst-case lane hold grows from about 81 s to about 121 s (5 s version +
20 s + 40 s print + 30 s boot + 26 s panel), only when print produced nothing; the
duty-cycle gate measures it like any other probe. The same non-blocking read now serves a
normal exit, which previously waited for EOF and could hang behind such a process.

## Prevention

- When scraping a TUI proves flaky, check whether the same CLI exposes the command
  non-interactively (`-p`/print mode, `--json`, screen-reader/a11y flags) before hardening
  the scrape. `--ax-screen-reader` was the runner-up here: flat text, but still interactive.
- Gate new CLI surfaces on the oldest *verified* version when the miss-behavior is costly,
  and validate output shape before trusting it.
- Keep the old path as fallback until telemetry/time proves the new one universal.
