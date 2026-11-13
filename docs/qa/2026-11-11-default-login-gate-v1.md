# Gate V1: does Claude's account file change with its credential?

Plan: `docs/plans/2026-11-10-1315-feat-follow-default-login-plan.md` (Verification Contract, V1).
Run 2026-11-11 on Kyle's Mac Studio, Claude Code 2.1.322, with Kyle approving each sign-in.

## Result

| Case | Result |
|---|---|
| `claude auth login` to another account | **Pass.** The account block changes with the credential. |
| Claude Desktop signing in | Not run. |
| A default-login switcher (ccswap) | **Pass by a run** for `errhythm/ccswap` (2026-11-12), including under a running session. `Dudude-bit/ccswap` by source reading only. See "The switcher run". |
| Headroom following a real switch (gate V3) | **Pass** for Claude with that ccswap. See "The switcher run". |
| A session left running while the login changes | **Pass.** The running session kept writing the file and never put the old account back. See "The open-session case". |

Claude identity work (U1, U2) can start on the strength of the first case. The switcher case rests
on reading the switchers' source, with two edge cases noted below; no switch was run.

## What was run

A throwaway `CLAUDE_CONFIG_DIR` under `/tmp`, with a clean environment, so the default login and
the two profile folders were never touched. The Keychain entry list was identical before and after.

1. `claude auth login` as a personal Max account.
2. `claude auth login` again, on the same folder, as a Team account. No logout in between.
3. `claude auth logout`, then the folder was deleted.

After each sign-in, two things were read and compared as short SHA-256 digests (no id, email or
token was printed or stored):

- the `oauthAccount` block of `<config dir>/.claude.json`;
- `claude auth status --json`, which is the official client's own answer about the credential.

## Findings

- **Field paths.** `oauthAccount.accountUuid` and `oauthAccount.organizationUuid` are both present,
  in the throwaway folder and in all three of Kyle's real config homes.
- **A personal plan has an organization id.** The Max login carried one, and it differed from the
  Team login's.
- **The block follows the credential.** After the second sign-in, `accountUuid`,
  `organizationUuid` and the email in the file all changed, and each matched what
  `claude auth status --json` reported (`email`, `orgId`).
- **A custom config folder has its own Keychain entry** (`Claude Code-credentials-<hash>`). The
  second sign-in reused that entry; it did not add one.
- **Signed out, the block is gone.** After `claude auth logout`, `oauthAccount` is absent from the
  file, which is the plan's Absent outcome.

## Not measured

- The order of the two writes during a sign-in (credential first or file first), and so how long a
  reading could see one without the other. The before-and-after read refuses a reading that
  straddles a change; how often that fires for Claude is unknown.
- A real switch by either ccswap. The section below is from their source.

## The switcher case, from source (2026-11-11)

Read, not run. Nothing was installed.

- **`errhythm/ccswap`** at `8bf7b9b` (Python; the one whose `list --json --provider claude` and
  `run` commands PR #216 used). `src/claude_swap/switcher.py`, the switch transaction: step 3
  writes the target credential, step 4 sets `oauthAccount` in `~/.claude.json` to the target's
  saved block, with rollback, all while holding Claude Code's own `~/.claude.lock` and
  `~/.claude.json.lock`. A saved account with no `oauthAccount` aborts the switch.
- **`Dudude-bit/ccswap`** at `4a85aac` (Go). `internal/switcher/switcher.go` writes the Keychain
  entry, then calls `claudecode.SwapOAuthAccount` on `~/.claude.json`.

So in both, the account block follows the credential, credential first.

Edge cases where the file can name the wrong account:

- In `Dudude-bit/ccswap`, a saved account with no `oauthAccount`, or a failed file write, leaves
  the old block in place and only prints a warning. Headroom would then file that account's
  readings under the previous account until the CLI rewrites the block.
- Both write the credential before the file. A reading whose two identity reads both fall in that
  gap would be attributed to the old account. The gap is local file I/O and the usage read takes
  seconds, so the before-and-after read should straddle it and refuse; this is reasoning, not a
  measurement.

## Contrary evidence, unverified (2026-11-11)

Third-party sources say the account block and the credential can drift apart on their own. None of
this was reproduced here, and none of it is from Anthropic.

- **A running session can rewrite the block.** CCSwitcher's source
  (`CCSwitcher/Services/CredentialAnchor.swift`) says every running Claude Code session rewrites
  `oauthAccount` from its own cached profile, so the file can name account B seconds after a
  switch while the Keychain holds account A's token. That tool keys on a credential fingerprint
  for this reason.
- **The CLI does not correct a stale block at startup.** `clauth`'s source comments say so, and
  `anthropics/claude-code` issue 81231 (CLI 2.1.220, macOS) reports a Keychain token for one
  account while `oauthAccount` and `claude auth status` named another, uncorrected.
- Other switchers read in source (`ipfans/ccswap`, `realiti4/claude-swap`, `blutarche/ccauth`,
  `XueshiQiao/CCSwitcher`) all write `oauthAccount` with the credential, credential first.
  `ipfans/ccswap` writes only the credentials file and no Keychain item, so on macOS it may change
  the block without changing the live credential (inferred, not tested).

This is the plan's stop condition for Claude: if the file and the credential can change apart,
Claude's identity work is revisited. The case to reproduce before a release is a session left
running under account A while the login changes to B. It was run the same day; see below.

## The open-session case (2026-11-11, run)

Same method as the first case: a throwaway `CLAUDE_CONFIG_DIR` under `/tmp`, a clean environment,
Claude Code 2.1.322, Kyle approving both sign-ins, digests only. The Keychain entry list was
identical before and after, and the folder was signed out and deleted.

1. `claude auth login` as the personal account (A). File and `claude auth status --json` agreed.
2. An interactive `claude` session was started in that folder, taken past first-run screens, and
   sent one prompt, so it held a live profile for A.
3. With that session still running, `claude auth login` as the Team account (B). The file's
   `accountUuid`, `organizationUuid` and email changed to B within one 2-second sample.
4. The file was sampled every 2 seconds for about 3.5 minutes while session A sat idle for 45
   seconds, answered a second prompt, opened `/usage`, and exited with `/exit`.

Result: every sample after the sign-in named B (101 of 101). Session A did rewrite `.claude.json`
three times after the switch (the file's modification time moved after the prompt, after `/usage`
and at exit), and each rewrite kept B's `oauthAccount`. `claude auth status --json` named B at the
end. The claim that a running session writes its cached account back did not reproduce on this
CLI version.

Limits: one CLI version, one session, one config folder with its own Keychain entry (not the
default `~/.claude`), a few minutes rather than hours, and no token refresh inside the old
session. A switcher that swaps the Keychain item under a running session was run the next day;
see below.

## The switcher run (2026-11-12)

Run in a throwaway macOS 15.7.7 VM (tart clone, deleted afterwards), so no real default login
was touched. Claude Code 2.1.322 and `errhythm/ccswap` at `8bf7b9b` were installed in it, and
Kyle signed two real subscriptions in (a personal Max plan and a Team plan), each added with
`ccswap add`. Both were signed out and `ccswap purge` run before the VM was deleted. Digests
only, as before.

Three things were compared after each switch: the `oauthAccount` block of the default
`~/.claude.json`, `claude auth status --json`, and the usage report from `claude -p "/usage"`.
The last is the independent check: it is fetched from the server with the live credential, and
the two accounts have different weekly reset times, so it shows whose credential is in use
whatever the file says.

- **Five plain switches** (`ccswap switch 1` / `2`): after every one, the file and the status
  named the account switched to. The usage report was read after two of them and showed that
  account's reset times both times.
- **A switch under a running session.** An interactive `claude` session was started under
  account A and sent a prompt. `ccswap switch 2` ran from another shell. The file was sampled
  every second for 110 seconds while the session sat idle for 45 seconds, answered a prompt,
  opened `/usage` and exited. Every sample after the switch named B (104 of 104). The session
  rewrote the file four times after the switch and kept B each time, and its own `/usage`
  panel showed B's reset times, so it had taken up the new credential.
- **Headroom, end to end (gate V3).** A build of `main` (`22a3fea0`, 1.6.2 (46)) was launched
  in the VM with the default login on B: one "Claude" row with B's numbers. After `ccswap
  switch 1` and Refresh: the row read "Main" with A's numbers, and B was kept as a dimmed row
  "Account 2 · Last read 1 min ago" with its last reading. After `ccswap switch 2` and
  Refresh: "Main" with B's numbers, and A dimmed as "Account 3". A third switch gave the
  second state again, with B as "Account 2". No reading appeared under the wrong account and
  no window from one account was carried onto the other's row.

Limits: one switcher at one commit, one CLI version, macOS 15.7.7, Claude only (no Codex
switch), no added account present (so the one-row merge was not exercised with real logins),
minutes rather than hours, and no token refresh during the run. Captures are local files under
`.context/qc/phase3-vm/` and show real account emails, so they are not committed.
