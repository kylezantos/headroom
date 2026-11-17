---
title: Antigravity quota comes from the official agy CLI's no-turn /usage answer
date: 2026-11-16
category: provider-integration
module: HeadroomCore/AntigravityUsageSource
problem_type: integration_feasibility
component: provider_probe
tags: [antigravity, agy, gemini, cli, usage, print-mode, no-turn, sign-in]
---

# Antigravity CLI usage feasibility

## Decision

Antigravity is feasible as a Headroom subscription provider with one account, off by default.
Headroom runs the official Antigravity CLI's read-only print-mode slash commands and parses the
JSON result each prints:

```
agy -p "/usage" --output-format json
agy -p "/credits" --output-format json
```

The CLI answers both without starting an agent turn. Headroom never reads an Antigravity
credential, cookie or Keychain item, never talks to the IDE's local language server, and never
calls a Google endpoint itself.

Each claim below is marked: (live) was observed with the real CLI on the contributor's Mac,
(source) comes from `agy changelog` or `agy help`, and (synthetic) is a fixture that was not
printed by the CLI as-is.

One known limitation, stated up front: a signed-out `agy` answers `/usage` by opening an
interactive Google sign-in in the browser. The CLI documents no way to turn that off. Headroom
ends the read at the prompt and stops spawning `agy` on routine polls, so a sign-out costs at
most one browser tab (see "Sign-in" and BUGS.md).

## Verified build

- `agy` **1.5.9** from Homebrew (`/opt/homebrew/bin/agy`, a plain binary). `agy --version`
  prints a bare `1.5.9` (live).
- The no-turn print-mode answer was added in 1.1.11: "Added non-interactive answers for the
  read-only slash commands in print mode, so `-p "/usage"`, `/quota`, `/credits` ... emit ... a
  structured payload under `--output-format json` ... without starting an agent turn, spending
  quota, or leaving a conversation behind" (source). 1.2.15 notes that "piped and `--json` output
  still use UTC timestamps" (source).
- Headroom's floor is **1.5.9**, the version the bucket shape was captured on
  (`AntigravityCLIUsageSource.minimumVersion`). The bucket shape before 1.5.9 is unverified.
  Lower the floor only after an older version's `/usage` JSON is captured and matches. Below the
  floor the card reads "Antigravity usage needs agy 1.5.9 or newer" with **Update Antigravity
  CLI**.
- The version verdict is memoized per symlink-resolved path plus modification date. A user
  request (Refresh, Check Now, a setup check) resolves the executable again.

## How a read runs (as built)

`AntigravityCLIUsageSource` (`Sources/HeadroomCore/Providers/AntigravityUsageSource.swift`):

1. The command set is closed (`AntigravityCommand`): `--version`, `-p "/usage" --output-format
   json` and `-p "/credits" --output-format json`. No caller can pass a prompt, a path or another
   argument.
2. `--disable-slash-commands` is never passed. Slash expansion is what routes `/usage` and
   `/credits` to the no-turn answer; without it the text would go to the model as a prompt.
3. The working folder is `~/Library/Application Support/Headroom/AntigravityProbe`
   (`AntigravityCLI.defaultWorkingDirectory`), created if missing, because print mode treats its
   working folder as the workspace (live: the log names it as `workspaceDirs`).
4. `PATH` comes from the login shell (`CLIExecutableResolver`). Finder launches fall back to
   `/opt/homebrew/bin/agy`, `/usr/local/bin/agy` and `~/.local/bin/agy`.
5. Every spawn goes through `StdioChildProcess` in its own session with stdin from `/dev/null`,
   on the serial lane `antigravity-cli`. Deadline 20 s for `/usage` and `/credits`, 10 s for
   `--version`; at the deadline, or when the read ends, the whole process group is terminated.
   stdout is capped at 64 KB (4 KB for `--version`); the live usage answer is about 2 KB.
6. Stderr is watched only for the fixed marker `Authentication required`
   (`AntigravitySignInPromptScanner`, which keeps only a short tail to catch a marker split
   across reads). Its bytes are never kept, logged or returned.
7. `/credits` runs only after a successful `/usage`. A credits failure never fails the usage
   reading; it only leaves no badge.

### Runtime no-turn guard

Every `/usage` and `/credits` result is checked before anything else: `num_turns` must be 0 and
every token count must be 0, and a `SUCCESS` result must carry a `command` block. Otherwise the
capture fails as `unsupportedClient`, and the failure is sticky: no routine poll spawns `agy`
again until its resolved path or modification date changes. A user request runs only the local
`--version` print, and clears the stop only if the version changed (the one way to notice a
version swapped behind an unchanged file). The card reads "Headroom paused Antigravity reads
after an agy change. Contact support" with **Check Now**. This guards against a future CLI change,
or a user skill that takes over `/usage`, turning every poll into a paid agent turn. Fixtures
`usage-one-turn` and `usage-output-tokens` (derived from the live capture) pin it.

## Classification as implemented

From exit status, stdout and whether stderr showed the sign-in prompt. Signed out comes only from
positive evidence; everything unmatched is transient.

| Evidence | Result |
|---|---|
| `agy` not found | CLI missing |
| `--version` older than 1.5.9 | update required |
| `--version` fails, times out or prints no version | transient (`unreadableVersion`) |
| stderr shows `Authentication required` | signed out (sticky, see "Sign-in") |
| stdout over the cap | transient (`outputTooLarge`) |
| no decodable result, exit 0 | format changed (`output`) |
| no decodable result, timed out | transient (`deadline`) |
| no decodable result, other exit | transient (`unexpectedExit`) |
| `num_turns` not 0 or any token count above 0 | unsupported client (sticky) |
| `status` not `SUCCESS`, error mentions "authentication failed" | transient (`authenticationFailed`) |
| `status` not `SUCCESS`, any other error | transient (`clientError`) |
| `SUCCESS` with no `command` | unsupported client (sticky) |
| `command.name` not `usage` | format changed (`commandName`) |
| full answer, then a nonzero exit without a timeout | transient (`unexpectedExit`) |
| `command.data` does not decode | format changed (`usageData`) |
| no bucket of a known pool and window | format changed (`usageValues`) |
| otherwise | live |

The whole stdout is decoded first, then each non-empty line from the last, so a line a plugin
prints before the result does not hide it. An `ERROR` result that says authentication failed
stays transient because it is what a sign-in wait prints when it ends without the prompt being
seen, and that alone does not prove the account is signed out (synthetic fixture
`usage-signed-out`).

### Mapping

- Live shape (1.5.9): `command.data.groups[]`, each with `name`, `description` and `buckets[]`;
  each bucket has `id` (`gemini-5h`, `gemini-weekly`, `3p-5h`, `3p-weekly`), `window` (`5h`,
  `weekly`), `remaining_fraction` (0 to 1) and `reset_time` (ISO 8601 UTC) (live).
- Buckets map by `id` prefix and `window`, never by display text. `gemini-*` is the Gemini pool,
  `3p-*` the other pool. Unknown prefixes or windows are skipped rather than guessed.
- Rows are `.other("Gemini 5h")`, `.other("Gemini weekly")`, `.other("Other 5h")` and
  `.other("Other weekly")`. These labels are stored window IDs and must never change. The `3p`
  pool is the group Antigravity calls "Claude and GPT models" (Claude Opus 5.5, Claude Sonnet 5.5,
  GPT-OSS 120B); it is named "Other", as Cursor names its second pool, because "Claude & GPT"
  truncated in the Standard card. Compact columns and Lock Screen captions use the short forms
  "Gemini wk" and "Other wk"; tooltips and VoiceOver keep the full names.
- `utilization = (1 - remaining_fraction) * 100`, clamped to 0 to 100. A bucket without a finite
  fraction is absent, never 0% or 100%. A missing or unreadable `reset_time` is an unresolved
  reset, never an invented one.
- Pools keep the order the CLI first reports them; within a pool the row with less left comes
  first. So the Compact popover shows one meter per pool (each pool's tighter row, all four rows
  in the tooltip), and single-slot surfaces (small and Lock Screen widgets, the menu bar pill,
  the phone summary, Siri) headline the row with the least left across both pools.
- `/credits` `command.data.remaining_credits` becomes the plan badge (`planLabel`), formatted for
  the locale (for example "1,200 credits"), only when above zero. Zero or unavailable credits
  draw no badge (live: the contributor's account reads 0).
- What the Gemini pool covers: the live group description reads "Models within this group:
  Gemini 4 Carbon, Gemini 4 Argon, Gemini 4 Hydrogen, Orchestrator (Carbon), Orchestrator (Argon),
  Gemini 3.8 Flash" (live). This is the evidence that the pool governs Gemini 4 Argon. The Gemini
  app, Gemini CLI and Gemini API allowances are different allowances and are not measured.

## Single account

`accountCapacity` is 1. `agy` keeps its sign-in in its own home (`~/.gemini/antigravity-cli`)
and the Keychain (live: the log reads `keyringAuth: loaded token`), and isolating a second
account is unproven. Probing an isolated `HOME` is not a safe experiment either: on a signed-out
home `/usage` opens a browser sign-in. So there is no Add Account and no extra-account home.

## Timing

- First live capture: exit 0 in about 1.2 s (live).
- The startup check run: about 3.8 s from start to shutdown, including the CLI's own silent
  sign-in from the Keychain and its model and experiment refreshes (live, one run).
- The 20-second deadline is a bound, not a measured need.

## Concurrency

Not characterized. Headroom's lane is serial, so Headroom never runs two `agy` reads at once.
Whether a read started while the user's own `agy` session is open interferes with it (or the
other way round) has not been tested.

## Startup side effects (check run 2026-11-16)

Run once from the source's working folder with the user's existing configuration, `agy` 1.5.9:
`agy -p "/usage" --output-format json --log-file <scratch>`. Before the run, the configuration
had one named hook group in `~/.gemini/config/hooks.json` with `PreInvocation`,
`PostInvocation`, `Stop` and `PostToolUse` entries; an empty `~/.gemini/config/mcp_config.json`;
`agy mcp list` printed "No MCP servers configured."; `agy plugin list --json` printed `[]`.

Observed (live):

- Exit 0, empty stderr, `status: SUCCESS`, `num_turns: 0`, every token count 0.
- The log reads "loaded 1 named hooks from 1 hooks.json file(s)" and then "Print mode: running
  slash command /usage". It shows no hook run and no hook failure. Process samples taken about
  every 0.2 s during the run showed no hook command and no MCP server process.
- The log reads "Not reloading plugin MCP servers: cannot get the signed-in user" before the
  CLI's silent sign-in succeeded; no MCP server or plugin started afterwards.
- Every run logs "Print mode: not authenticated, trying silent auth", even when signed in. On a
  signed-in Mac it reads the Keychain token and logs "silent auth succeeded"; no sign-in page
  opened.
- `agy` spawned its own background updater (`agy --bg-updater`), which exited during the run and
  wrote `updater/update_status.json` ("Already on the latest version") and
  `last_check.timestamp`.
- Files changed, all inside `~/.gemini/antigravity-cli`: `conversation_summaries.db` (the log
  reads "summary store: reconciliation complete"), `cache/onboarding.json`, the two updater files
  above, and the `crashes` folder's timestamp. `conversations/` and `history.jsonl` were
  unchanged, so no conversation was left behind. `~/.gemini/config` was unchanged. Nothing was
  written in Headroom's working folder.
- Without `--log-file` (Headroom passes none), each run writes its own log of about 15 KB under
  `~/.gemini/antigravity-cli/log/`. The log names the signed-in account's email. It is the CLI's
  own file; Headroom never reads it.

Inferred, not observed:

- The configured hooks did not fire. `PreInvocation` is documented as running before the model
  is called (source: 1.5.x changelog, "returning `terminate` stops the turn before the model is
  called"), and the run started no turn. A successful hook run may not be logged, and a hook
  shorter than the sampling interval could be missed, so this rests on the no-turn answer.
- A `SessionStart` hook was not configured, so whether one fires on a print-mode slash command is
  unknown. MCP servers configured in `mcp_config.json` or brought by a plugin were not present to
  test.
- With an expired Keychain token the silent sign-in presumably refreshes it, writing the
  Keychain. That is the CLI managing its own login; it was not observed.
- Whether the background updater can replace the binary during a poll, and whether it stays in
  the process group Headroom terminates, is unverified. A replaced binary changes its
  modification date, which re-checks the version and clears a no-turn stop.

## Sign-in

- **A signed-out read opens a browser sign-in (live, 2026-11-16).** With an isolated empty
  `HOME`, `agy -p "/usage"` printed "Authentication required. Please visit the URL to log in:"
  and a Google sign-in URL on stderr, then "Waiting for authentication (timeout 60s)...". Its log
  read "Print mode: not authenticated, trying silent auth", then "silent auth failed", then
  "triggering interactive OAuth", and a sign-in page opened in the browser. The CLI documents no
  way to disable this.
- Headroom watches stderr for `Authentication required`, ends the read at once by terminating the
  process group, and records signed out. The state is sticky: routine polls never spawn `agy`
  again until a user request (Refresh, Check Now, or the check after the sign-in handoff). So a
  sign-out opens at most one browser tab. The same holds when `/credits` shows the prompt.
- Sign-in runs `agy acp --login` in Terminal through `SetupSessionCoordinator`. `agy help acp`
  documents it as "Log in with Google interactively, then exit" (source). Headroom waits for the
  process to exit (exit-signalled, like OpenCode) and runs no check while Terminal is open,
  because a check on a signed-out `agy` would open another browser sign-in. Headroom observes
  only the wrapper's exit marker and never reads the stored login.
- Not live-verified: that `agy acp --login` stores the login where `agy -p` reads it. The 1.5.x
  changelog says `agy acp` falls back to "your saved login" after `agy acp --login` (source),
  which suggests a shared store.
- Demos, the render and bench harnesses and the XCTest host never start `agy`
  (`AppComposition.usesInertAntigravity`).

## Live checks, 2026-11-16

On the contributor's Mac with `agy` 1.5.9:

- **Shape and no-turn evidence.** `/usage` and `/credits` both answered with `num_turns: 0` and
  every token count 0. Fixtures `usage-live`, `credits-live` and `version-live` are those
  captures; they contain no email, token or account identifier.
- **Headroom matches the CLI.** `swift run Headroom --probe-antigravity` matched
  `agy -p "/usage"`: the four percentages were equal after rounding and the resets were equal.
- **An unused pool's reset moves with the clock.** An unused window reports its reset as now plus
  the window length, so it moves forward on every read until something is used.
- **Signed out** (isolated `HOME`): the browser sign-in described above.
- **Startup side effects**: see above.

Synthetic or derived: `usage-signed-out` (modelled on the signed-out run, URL replaced by a
placeholder, exit status a stand-in), `usage-missing-3p-5h`, `usage-one-turn`,
`usage-output-tokens` and `credits-1200` (live captures with the named fields edited).

## Still unverified

- That `agy acp --login` stores the login where `agy -p` reads it, end to end through Headroom's
  Terminal handoff.
- A nonzero credits balance on a real account (the badge rests on the derived `credits-1200`).
- A partly used pool against Antigravity's own usage view beyond the rounding match above, and a
  pool at its limit.
- `/usage` output on versions before 1.5.9.
- An expired or revoked Keychain token: whether silent sign-in refreshes it quietly or opens the
  browser sign-in.
- Hooks, MCP servers and plugins on a configuration that has them enabled for print mode,
  including `SessionStart` (see "Startup side effects").
- The background updater's process group and whether it can replace the binary mid-poll.
- Retention of the per-run logs in `~/.gemini/antigravity-cli/log/` (38 files from four days were
  present on the check machine).
- Reads racing the user's own `agy` session.

## Re-diagnosis

Never run `agy` signed out or with an isolated empty `HOME` on a machine where a browser tab
opening is a problem: any read starts the interactive sign-in. Never run `agy -p` with any prompt
other than `/usage` or `/credits`, and never pass `--disable-slash-commands`.

1. **Probe through Headroom.** Prints the parsed rows and the credits badge, or the outcome name
   with its stage or cause only, never raw output, stderr, an email or anything identifying:

   ```bash
   swift run Headroom --probe-antigravity
   ```

2. **Compare with the CLI's own text answer**, from Headroom's working folder:

   ```bash
   cd "$HOME/Library/Application Support/Headroom/AntigravityProbe"
   agy -p "/usage"
   ```

3. **See the raw JSON** when a format change needs diagnosing. Check `num_turns` and `usage`
   first:

   ```bash
   agy -p "/usage" --output-format json --log-file "$TMPDIR/agy-usage.log"
   ```

   The log names the account's email and the response may too in future versions: sanitize as
   `Tests/HeadroomCoreTests/Fixtures/antigravity/antigravity-fixtures.json` describes before
   anything goes near a commit.

4. **Afterwards**, confirm nothing is left running:

   ```bash
   ps -axo pid,ppid,command | grep -E '[a]gy '
   ```
