---
title: Cursor Agent usage is available through the official /usage panel
date: 2026-08-01
category: provider-integration
tags: [cursor, cli, usage, pty, compliance]
---

# Cursor Agent usage feasibility

## Decision

Cursor is feasible as a Headroom provider through the official `cursor-agent` CLI. Headroom
drives the CLI's interactive `/usage` panel in a pseudo-terminal, reads its rendered status,
and does not submit a model prompt. This follows the same official-client boundary used for
Claude: the vendor client owns authentication and the request; Headroom only parses output.

The prohibited alternatives remain prohibited: do not reuse `WorkosCursorSessionToken`, read
the IDE's `state.vscdb`, or call private dashboard endpoints.

## Verified surface

Verified on 2026-08-01 with Cursor Agent `2026.07.23-e383d2b` and an authenticated Pro+
account:

- `cursor-agent status --format json` reports authentication state but no usage; its
  `userInfo.email` field carries the signed-in address (verified 2026-08-01, used by
  `CursorStatusEmailProbe` for the account-identity display).
- `cursor-agent about --format json` reports plan metadata but no usage.
- The interactive `/usage` panel reports the plan, monthly included percentage, displayed
  reset day, and on-demand state/spend.
- Opening `/usage` does not send a model request.
- The permanent `swift run Headroom --probe-cursor` diagnostic parsed the live panel.

The redacted capture used by parser tests is
`Tests/HeadroomCoreTests/Fixtures/cursor-usage.txt`.

Reverified on 2026-08-31 with Cursor Agent `2026.08.25-3e8eec8`: the authenticated Pro+
panel still parsed as a live monthly window with on-demand disabled. The same probe succeeded
with `PATH=/usr/bin:/bin`, resolving the native `~/.local/bin/cursor-agent` install from a
Finder-like environment. An Apple Development-signed Headroom bundle on macOS 26.5.1 also
returned the live panel under that sparse path. Deterministic resolver tests pin
version-manager precedence, Homebrew fallback selection, missing and non-executable candidates,
and an executable disappearing before PTY input. Actual Homebrew/version-manager installs and
macOS 15 Sequoia remain separate runtime characterization work in `BUGS.md`.

## PTY details that are load-bearing

Cursor Agent uses Ink and enables the Kitty keyboard protocol. A raw pseudo-terminal must:

- answer the OSC 11 terminal-background query or the initial paint can stall;
- send Enter as Kitty CSI-u (`ESC [ 13 u`), including a pause between accepting slash-command
  autocomplete and executing the command;
- impose hard boot and panel deadlines; and
- terminate the process group with a bounded nonblocking reap, because the bundled Node
  runtime can linger while exiting.

Removing any of these can turn a valid authenticated session into a timeout or an unbounded
probe.

## Data limitations

The panel renders reset precision only as `MMM d`. Headroom keeps that label verbatim and uses
the end of the displayed UTC day as the continuity-expiry boundary. This avoids discarding a
last-known meter at midnight on the reset day while not inventing a user-visible time.

Cursor remains single-account because this verification found no supported config-home
isolation equivalent to `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, or `GROK_HOME`.

## Official references

- [Cursor CLI installation](https://docs.cursor.com/en/cli/installation)
- [Cursor CLI authentication](https://docs.cursor.com/en/cli/reference/authentication)
- [Cursor CLI overview](https://docs.cursor.com/en/cli/overview)
