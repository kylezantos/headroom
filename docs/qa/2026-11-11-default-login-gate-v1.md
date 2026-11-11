# Gate V1: does Claude's account file change with its credential?

Plan: `docs/plans/2026-11-10-1315-feat-follow-default-login-plan.md` (Verification Contract, V1).
Run 2026-11-11 on Kyle's Mac Studio, Claude Code 2.1.322, with Kyle approving each sign-in.

## Result

| Case | Result |
|---|---|
| `claude auth login` to another account | **Pass.** The account block changes with the credential. |
| Claude Desktop signing in | Not run. |
| A default-login switcher (ccswap) | **Pass by source reading**, not by a run. Both projects named ccswap write the credential and then replace `oauthAccount`. See below. |

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
running under account A while the login changes to B.
