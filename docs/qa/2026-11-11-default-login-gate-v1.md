# Gate V1: does Claude's account file change with its credential?

Plan: `docs/plans/2026-11-10-1315-feat-follow-default-login-plan.md` (Verification Contract, V1).
Run 2026-11-11 on Kyle's Mac Studio, Claude Code 2.1.322, with Kyle approving each sign-in.

## Result

| Case | Result |
|---|---|
| `claude auth login` to another account | **Pass.** The account block changes with the credential. |
| Claude Desktop signing in | Not run. |
| A default-login switcher (ccswap) | Not run. Needs a before-and-after copy of `.claude.json` from a switcher setup. |

Claude identity work (U1, U2) can start on the strength of the first case. A release that claims to
follow a switcher still needs the third.

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
- Whether a tool that swaps the Keychain credential directly also rewrites the account block.
