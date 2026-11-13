---
title: OpenCode Go usage comes from the official 2.x client's own usage read
date: 2026-11-12
category: provider-integration
module: HeadroomCore/OpenCodeUsageSource
problem_type: integration_feasibility
component: provider_probe
tags: [opencode, opencode-go, cli, usage, account-isolation, xdg, stub-console]
---

# OpenCode CLI usage feasibility

## Decision

OpenCode is feasible as a Headroom subscription provider with any number of accounts. Headroom
runs the official OpenCode 2.x client's own usage read and parses the one JSON line it prints:

```
opencode api --standalone experimental.usage.limits
```

The client fetches the Console config, the Console budgets and the Go allowance
(`/console/api/v2/config`, `/console/api/policies/current-budgets`, `/zen/go/v1/usage`, one
request each, as the stub's request log shows), validates them against its own schema and
prints the result. Headroom never reads OpenCode's credential store, never calls `opencode.ai`
itself, never starts `opencode service`, and never sends a model request. Plan:
`docs/plans/2026-11-04-1002-feat-opencode-provider-plan.md` (KTD1–KTD22).

**Everything below was verified against a local stub Console, not a real Go subscription.**
The fixtures in `Tests/HeadroomCoreTests/Fixtures/opencode/` are stub-derived. A real Go response
has not been captured yet; see "Still unverified" and the release-blocker entry in `BUGS.md`.

## Verified build

- OpenCode **2.2.5** (`opencode --version` prints `opencode v2.2.5`), from
  `https://github.com/anomalyco/opencode/releases/download/v2.2.5/opencode-darwin-arm64.zip`,
  SHA-256 `25ba9908979fa7d764792c82589b4b5768ab1511154e0317d98aa77d216ce767` (matches the
  release's published digest). Newer releases exist (2.2.6, 2.2.7); the QA pin stays at 2.2.5.
- The usage read was added in 2.2.0 (PR #58694). Headroom gates on **2.2.0 or newer** and never
  runs `api` on anything older: on 1.x, `opencode api …` falls through to the TUI. 1.x prints a
  bare version (`1.1.53`); both forms parse with `^(?:opencode )?v?(\d+)\.(\d+)\.(\d+)`. The
  verdict is memoized per symlink-resolved path plus modification date, both ways. A passing
  version skips `--version` until the key changes; a deadline, overflow or non-JSON stdout clears
  that memo. A below-floor version returns update required without spawning while the key is
  unchanged, because a 1.x `--version` is not side-effect free (it appends to the user's real
  OpenCode log and can reset `~/.cache/opencode`, observed 2026-11-12); a user request (Check Now,
  a setup check) always runs it again. An unreadable version is never memoized. Limit: a
  version-manager shim whose own file does not change when it switches versions is noticed only
  on a user request.
- Source references below are at tag `v2.2.5` of `anomalyco/opencode`.

## How a read runs (KTD2, as built)

`OpenCodeCLIUsageSource` (`Sources/HeadroomCore/Providers/OpenCodeUsageSource.swift`) and the
shared environment rule in `OpenCodeCLI` (`OpenCodeConnection.swift`):

1. Every command that talks to the server passes `--standalone`, so the client runs a private
   child server that exits with it. `--version` is the only command without it.
2. Every inherited `OPENCODE_*` variable and all four XDG variables are removed from the child's
   environment. Then only these are set:
   - `OPENCODE_DISABLE_MODELS_FETCH=1`: without it every run downloads an 11 MB model catalog
     that is cached for five minutes.
   - `OPENCODE_DISABLE_AUTOUPDATE=1`: without it a background poll could upgrade the user's own
     CLI. The 2.2.5 binary reads it.
   - The account's four XDG values (extra accounts only, KTD10).
   - `PATH` from the login shell (`CLIExecutableResolver`).
3. The working folder is `~/Library/Application Support/Headroom/OpenCodeProbe`, outside any git
   repo. Inside a repo the client runs seven git commands and records the repo as a project.
4. The Terminal sign-in script uses the same rule (`OpenCodeCLI.shellEnvironmentLines`), so the
   probe and the handoff cannot drift.
5. The command set is closed (`OpenCodeCommand`): `--version`, the usage read, and the two
   follow-up reads below. No caller can pass an operation ID, a path or another argument.
6. 50-second hard deadline, then the process group is terminated. A client that printed a valid
   line and then hung still returns that line. stdout is capped at 64 KB (4 MB for the operation
   list); stderr is discarded by `StdioChildProcess`.

### Follow-up reads

- **After `data: null`** (KTD20), once, never memoized:
  `opencode auth list --standalone --format json`. Only each integration's `id` and each
  connection's `type` and `method` are decoded, never labels. An `opencode` connection with method
  `oauth` or `external` (or type `external`) is a Console sign-in with no workspace and reads as
  no Go plan. Any other connection on `opencode` or `opencode-go` (a stored key) reads as "sign in
  to OpenCode Console". No connection reads as signed out. A failed read (non-zero exit,
  deadline, overflow or undecodable output) is transient (`authListUnreadable`), never signed
  out: every `--standalone` command can fail on its own (see "Concurrency"), and signed out is
  a permanent "Sign in" state.
- **After exit 1 with empty stdout** (KTD4), once: `opencode api --standalone GET /openapi.json`
  (about 350 KB on 2.2.5). The client resolves operation names from this same document
  (`packages/cli/src/commands/handlers/api.ts:62-76`), and a missing operation prints
  `Operation not found: <id>` to stderr only (`:59`). If neither the path
  `/api/experimental/usage/limits` nor the operation ID is present, the result is format changed;
  otherwise it is transient.

## Classification as implemented

Exit status and stdout only. Every unmatched case is transient, never a sign-in prompt.

| Exit | stdout (captured on 2.2.5 against the stub) | Result |
|---|---|---|
| 0 | `{"location":{…},"data":null}` | follow-up `auth list` (above): signed out, Console sign-in required or no Go plan from a decoded list; transient (`authListUnreadable`) when the list read fails |
| 0 | `data` with a `go` block of `rolling`, `weekly`, `monthly` | live, three windows |
| 0 | `data` with `workspace` and `budgets` but no `go` (the Go route answered 403) | live, no Go plan |
| 0 | a `go` block whose percentage or `resetsAt` is not finite and positive | format changed (`usageValues`) |
| 0 | no line decodable as the envelope (the whole stdout is tried first, then each non-empty line from the last; a plugin on the built-in home can print text before the client's line) | format changed (`usageOutput`) |
| 1 | message contains `Reconnect OpenCode Console` (`"Reconnect OpenCode Console to continue."`, refresh grant rejected) or `(401 GET` (`…(401 GET …/zen/go/v1/usage)`; revoked also fails `…(401 GET …/current-budgets)` first) | sign-in expired (permanent) |
| 1 | message contains `Location plugins did not finish activating` (`"service":"plugin"`) | transient (`pluginsNotActivated`) |
| 1 | message contains `timed out` (`"OpenCode Console usage limits timed out"`), `Transport error` (`…budgets are unavailable: Transport error (GET …)`), or `(5` + two digits + space (`…(500 GET …)`) | transient (`consoleUnavailable`) |
| 1 | message contains `Decode error` (`…Decode error (200 GET …/zen/go/v1/usage)`) or `Missing key` (`…Missing key\n  at ["usage"]["rolling"]["status"]`) | format changed (`clientDecode`) |
| 1 | stdout begins `Error: Standalone server exited before reporting readiness` followed by a stack (not JSON; the child server died, see "Concurrency") | transient (`serverStartFailed`) |
| 1 | empty stdout | follow-up operation list (above) |
| 1 | any other JSON `message` | transient (`unrecognizedError`) |
| 1 | JSON of another shape (no `message`) | format changed (`usageOutput`) |
| 1 | non-empty stdout that is not JSON (a crash stack from ENOSPC, EACCES…) | transient (`clientFailed`) |
| none | still running at 50 s, valid line already printed | that line's result |
| none | still running at 50 s, otherwise | transient (`deadline`) |
| other | anything | transient (`unexpectedExit`) |
| — | stdout over the cap | format changed (`outputTooLarge`) |

Two transient rows were added during implementation and are not in the plan's KTD4 table: the
"Standalone server exited before reporting readiness" stack (without its own row it would have
read as format changed and told the user to contact support) and "Location plugins did not finish
activating". The error line's `message` is matched against these fixed phrases only and never
logged or shown, because it carries the Console URL.

The stderr line of every exit-1 run is `HTTP 503 Service Unavailable`; it is never read.

### Mapping

- Windows by name, never position: `rolling` → 5-hour, `weekly` → weekly, `monthly` →
  `.billingPeriod("Monthly", 30 days)`. `percent` is percent used. `resetsAt` is milliseconds
  since the epoch. All three windows are required by the schema; a missing one fails decoding.
- `limited: true` forces the window to 100% used whatever `percent` says; `limited` is the
  authority. The card's red sentence ("Go's monthly limit is reached until …",
  `UsageLimitSentence`) names the limited window that resets last and shows only while it is live
  with a future reset.
- No Go plan is a `.live` snapshot with one Monthly `.unavailable(since: UTC month start)` row
  and `planStatus = .noActivePlan`, so setup completes and the phone key is not rewritten on every
  poll.
- The response's workspace ID, name and Console URL are never decoded (KTD19). Budgets are not
  decoded either.

## Isolation (KTD10)

- An extra account's home is `~/Library/Application Support/Headroom/Accounts/opencode/<id>/`
  with `data`, `config`, `cache` and `state`, exported as `XDG_DATA_HOME`, `XDG_CONFIG_HOME`,
  `XDG_CACHE_HOME` and `XDG_STATE_HOME`. The token-refresh lock lives under state, so data and
  state always come from the same root.
- Verified in scratch homes: a fresh home reads `data: null`, and a device-signed-in home reads
  only its own workspace. Runs set `HOME` to an empty scratch folder as a precaution, and that
  folder stayed empty, so the 2.x client keeps its state under the XDG folders.
- The built-in account unsets all four XDG variables, so it reads `~/.local/share/opencode`, the
  home a default Terminal `opencode` uses.
- **Limitation: XDG set in a shell profile.** A user who sets XDG variables in their shell profile
  uses a different home in Terminal. For them the built-in account reads as signed out, and a
  sign-in through Headroom lands in `~/.local/share/opencode`, which their Terminal does not use.
- **Limitation: `OPENCODE_API_KEY` only.** Every inherited `OPENCODE_*` variable is cleared, so a
  user who authenticates OpenCode only through `OPENCODE_API_KEY` reads as signed out. Go usage
  needs a stored Console sign-in anyway.

## The child server is private (KTD2)

`--standalone` cannot be used by other local processes without a per-run secret.

- `packages/cli/src/services/standalone.ts:37` mints `randomBytes(32).toString("base64url")`.
  `:20-24` spawns `opencode serve --stdio --port 0` with it as `OPENCODE_PASSWORD`. `:53` the
  client authenticates with Basic auth `opencode:<password>`.
- `packages/cli/src/server-process.ts:72`: the default hostname is `127.0.0.1`. `:85-96`: stdio
  mode removes the password from the environment that tools inherit.
- `packages/server/src/process.ts:177-205` (`dispatch`) and
  `packages/server/src/middleware/authorization.ts:74-104` reject every request without valid
  credentials, except pairing-connect URLs and ticketed PTY/MCP connects, which are validated in
  their handlers. Pairing codes are 16 random bytes with a 5-minute lifetime, issued only to an
  authenticated caller (`packages/server/src/pairing.ts`).
- One exception: `packages/cli/src/services/web-ui.ts:19-29` serves the bundled web shell
  (static HTML and JS, no data) before auth, for paths outside `/api`, `/auth/` and
  `/openapi.json`.
- Live probe: the child listened on `127.0.0.1:<random port>` only. Without the password,
  `/api/info`, `/openapi.json`, `/api/experimental/usage/limits`, `/api/session` and
  `/api/location` answered 401; a wrong password and an empty `auth_token` answered 401; `/`
  answered 200 with the web shell.
- The OpenAPI document marks every operation `security: []`. That is a documentation artifact;
  the dispatcher enforces auth regardless.

## Upstream limits (KTD4)

- **A budgets-route failure fails the whole reading.** The subscription card goes stale even when
  the Go route is fine.
- **Any 403 on the Go route reads as no Go plan.** The client cannot tell no subscription from a
  lapsed one, a failed payment or an edge refusal, so one such reading replaces a subscriber's
  live meters with the no-Go state. Headroom does not debounce it.
- **A lapsed SSO session can read live or as no Go plan.** A Console config-level sign-in failure
  never reaches this output. "Sign-in expired" covers only what the usage read reports.

## Timing

Measured on a machine also running another agent's build, so noisy:

- Steady-state reads take 2–5 s (minimal home 2.25–5.41 s, median about 3 s; populated config with
  8 plugins, 10 agents, 10 commands, MCP entries and skills 1.96–5.54 s). Signed out 1.95 s, no Go
  2.21 s, expired 2.84 s. Two enabled MCP servers that never answer do not block the read.
- A slow Console (stub hangs of 25 s and 75 s) ends at 17–25 s with "timed out" (the client's own
  15-second usage timeout). Through `--probe-opencode` the `slow` mode took 16 s.
- **Token refresh is capped at about 5 s by the client, not 30 s.** Requests wait at most 5 s for
  plugin activation (`packages/server/src/location.ts:36-42`), and the Console plugin's
  activation includes the refresh. A refresh held 4 s succeeded (5.94 s total); held 8, 12 or 20 s,
  the run exited 1 after 6.4–6.7 s with "Location plugins did not finish activating", and the next
  read refreshed again. A user plugin whose setup takes over about 5 s fails every read the same
  way (8 s setup: 6/6 failed), so that user would see "will retry" on every poll; 3 s setup was
  fine. The plan's KTD5 premise ("a run can spend up to 30 seconds refreshing") did not hold. The
  50-second deadline is kept as a bound that never kills a run early, not because refreshes need
  it.
- Whether the real Console rotates refresh tokens on use, so that an abandoned refresh could leave
  a stale refresh token, is unverified; the stub accepts any token.
- Refresh lock: three simultaneous reads with an expired token made **one** refresh grant
  (cross-process file lock `credential-refresh:<id>` under `state/opencode/locks`,
  `credential.ts:106`). A SIGKILL of a read's process group mid-refresh left no orphans and no
  lock, and the next read succeeded. Lock defaults: stale after 60 s, wait up to 5 minutes
  (`packages/util/src/effect-flock.ts:48-49`).

## Concurrency

- **Reads while OpenCode holds the home: passed.** With `opencode serve --hostname 127.0.0.1`
  and a TUI both up on one home and a loop creating sessions through the server every 0.2 s
  (106 and 56 writes), 10 of 10 reads succeeded (1.8–7.2 s). A read started at the same moment
  as `opencode serve` passed 15 of 15.
- **Simultaneous client starts can fail.** Ten rounds of three reads started at the same instant
  on one signed-in home: 27 succeeded and **3 failed**. The failed child server died with
  `SQLiteError: database is locked`, and the read printed the "Standalone server exited before
  reporting readiness" stack on stdout with exit 1. A signed-out home passed 30 of 30. During a
  first-contact schema migration two rounds of three had two failures each (one with
  `UNIQUE constraint failed: migration.id`, one with `database is locked`).
- Headroom's OpenCode lane is serial, so Headroom never races itself. The exposure is the user's
  own OpenCode (or another tool) starting at the same instant as a Headroom read on the built-in
  home. Such a failure reads as temporarily unavailable and the next poll retries. **Which
  process loses that race was not characterized**: only Headroom's reads were counted, so a
  user's own OpenCode start losing to a Headroom read was not ruled out.

## Migration from 1.x (KTD22): no hold built

2.x migrates a 1.x home one way on first use. Measured with OpenCode 1.19.5 homes (release
SHA-256 `c1c9e62521192192ef4c3ed1355ada2144055bddb61682217e997b03c55203c1`), validated with
1.19.5's own `session list` and `export`:

- Small (100 sessions, 4,000 messages, 19 MB): finished inside the first 2.x read, exit 0, 2.96 s.
- Large (1,000 sessions, 50,000 messages, 125,000 parts, 232 MB; the owner's real database is
  13.7 MB for scale): the migration runs as a background fiber of the server
  (`v1-migration.bun.ts:512-528`, wired in `server/src/routes.ts:202`) with a per-session cursor.
  The read never waits for it: each read exited 0 in 2.6–3.7 s and migrated about 100–115
  sessions before exiting, so about ten reads finish it. With a long-lived `opencode serve` all
  1,000 sessions were copied by about 16 s and the state read `completed` at about 44 s, while 11
  serial reads alongside it succeeded (2.0–8.9 s).
- SIGKILL of the first 2.x run at 1.0 s and 1.8 s left no orphans, the database passed
  `quick_check`, and the next run resumed and succeeded.
- Simultaneous processes migrate in parallel without duplicates (the migration lock is
  in-process only, `v1-migration.bun.ts:219`), but kept moving the cursor so the state never read
  `completed` within 12 concurrent rounds, although every session was copied.
- Conclusion: the migration finishes well inside the deadline, never blocks the read and survives
  a kill, so `opencodeUpdateHeld` and the first-run hold were not built. The real hazard is the
  simultaneous-start failure above, which a hold would not fix.
- Going back: after 2.x migrated the small home, 1.19.5 still listed and exported all 100
  sessions (2.x copies into new tables and leaves the 1.x tables). Sessions created in 2.x are not
  visible to 1.x. Reinstalling a 1.x binary was not tested.
- An installed 1.1.x keeps sessions as JSON files under `storage/`, which 2.x does not migrate at
  all (`v1-migration.bun.ts:1229-1234` checks only the SQLite `session` table).

## Log footprint

- Each read appends 11–28 KB to `log/opencode.log` in the home's data folder (11.3 KB minimal,
  21.6–27.7 KB with a populated config), about 7 MB a day at a 5-minute interval.
- The client compacts the log in place on every process start and hourly: above 50 MB it trims to
  about 25 MB (`packages/util/src/observability/logging.ts:9-13`, `:64-76`). A log padded to
  54.7 MB was 26.2 MB after one read. So the log is bounded at about 50 MB.
- Each poll of the built-in account therefore leaves OpenCode's normal footprint for a CLI run in
  `~/.local/share/opencode`. The stub's logs held no token, workspace ID or raw response; the real
  Console's log content is unchecked (see below).

## Channels, versions and several installs

- On 2026-11-12: the `curl -fsSL https://opencode.ai/install | bash` script installs the latest
  **1.x** only and points to `https://opencode.ai/v2/install` for 2.x. npm `opencode-ai` `latest`
  is **1.19.5**; 2.x is the separate package `@opencode/cli` (`latest` 2.2.7). Homebrew core
  `opencode` is **2.2.7**. The `opencode.ai/docs` page lists 2.x installs. So 2.x is the default
  for Homebrew only.
- The maintainers' guide (`https://anoma.ly/notes/opencode-2-0`) says to get on the latest 1.x and
  run `opencode upgrade --major`. 1.19.5 has that command ("upgrade to OpenCode 2 and remove
  OpenCode 1"); whether 1.1.53 has it was not checked. Because a default install does not give
  2.x, the too-old state reads "Go usage needs OpenCode 2.2 or newer" with **About OpenCode 2**,
  which opens that guide; **Install OpenCode CLI** opens `https://opencode.ai/docs/`.
- **A 1.x `--version` is not free of side effects.** In a scratch home, 1.1.53's `--version`
  created the log folder, wrote `cache/opencode/version` and downloaded a 6 MB `models.json`. On
  the owner's machine on 2026-11-12, `~/.local/share/opencode/log/opencode.log` grew and
  `~/.cache/opencode` was emptied and given a 2-byte `version` file, the pattern 1.x writes, while
  no Headroom test process was running against that home. So on a 1.x install, even the version
  gate Headroom runs before deciding "update required" touches the user's default home. Demos,
  harnesses and the XCTest host never start the client (`AppComposition.usesInertOpenCode`).
- **Headroom uses the install the login shell finds first.** A machine can have several. On the
  owner's machine, `~/.opencode/bin/opencode` (1.1.53) came first on PATH, while npm
  `@opencode/cli` 2.2.7 and Homebrew 1.1.28 were also installed, so the built-in account there
  reads as "update required" even though a 2.x exists. The fix is the user's PATH order (or
  removing the old install), not Headroom's. Finder launches without a usable login-shell answer
  fall back to `~/.opencode/bin`, then Homebrew, `/usr/local/bin`, `~/.local/bin` and
  `~/.npm-global/bin`, in that order (`OpenCodeCLI.fallbackPaths`).

## Sign-in (KTD11)

- The script runs `opencode auth login --standalone opencode --method device` in an exported
  subshell and ends with that command's own status. The device flow binds no callback port: it
  polls `/auth/device/token` (`packages/core/src/plugin/provider/opencode.ts:85-106`, `:486-`).
  During a login the only listener was the private standalone child. So concurrent logins on
  different homes need no exclusive slot. The client opens the browser only when stdin and stdout
  are both terminals (`packages/cli/src/commands/handlers/auth/login.ts:193`).
- A Console login does **not** delete a stored API key. It adds an OAuth credential and makes it
  the active one; the key stays, inactive (`packages/core/src/integration.ts:476-480`,
  `packages/core/src/credential.ts:136-172`). Captured: both credentials listed, OAuth first, and
  the usage read then reports the OAuth workspace. The built-in confirmation dialog says so.
- A device sign-in whose token carries no organization picks the first organization by name, so a
  credential has no workspace only when the account has none (`opencode.ts:521-537`). The stub's
  `device-noworkspace` mode reproduces it; it reads as no Go plan.
- Sign Out & Set Up Again (built-in only) runs `opencode auth logout --standalone opencode`, then
  the same login. Logout always opens an account picker in Terminal, exits 1 when the home has no
  stored credential and 130 when cancelled, and removes only the picked credential. The script
  ignores logout's status and ends with login's.
- Every built-in sign-in (Sign In, Sign In Again, Try Again, Sign Out & Set Up Again) first shows
  a confirmation dialog (`BuiltInSignInConfirmation`), every time. Extra accounts never see it.
- Verified against the stub: the generated extra-account script, run under zsh with stdin from
  `/dev/null`, signed a scratch home in through device mode (exit 0, 4 s), the completion marker
  recorded status 0, the next probe was live, and the real home was unchanged.
- **Removing an extra account deletes its Headroom-owned home only.** Its Console session stays
  valid on OpenCode's servers, as with the other providers.

## Still unverified (live checks, plan U11)

- The real Go response: its shape and values. Every fixture is stub-derived. Release is blocked on
  this (`BUGS.md`).
- What Go does at a limit (refuses, falls back to free models, or bills a balance), and whether
  one limited window stops Go while the others show room. The red sentence deliberately claims
  none of these.
- What the usage read returns once a Go subscription lapses.
- How quickly Go appears after purchase.
- Whether a new free Console account always has a workspace, and how the device page picks one
  for a two-workspace account.
- The real Console's log content (tokens, workspace IDs, raw responses), permissions and
  retention. The log file is world-readable.
- The built-in home after the owner upgrades: log rotation and coexistence with his own OpenCode.
- An extra account running with the user's real `HOME` (QA runs used a scratch `HOME`).
- The built-in sign-in dialog on the live `MenuBarExtra` window.

## Re-diagnosis

Run everything from the repo root. Never run a bare `--probe-opencode` on a machine whose default
OpenCode home must not be migrated: it reads the built-in home with whatever `opencode` the login
shell finds, and a 2.x client migrates a 1.x home one way. Never point a 2.x binary at a real 1.x
home. `Scripts/opencode-qa-home.sh` enforces both for QA homes: they must live under `.context/`
and may not resolve to or contain a default OpenCode home.

1. **Fetch the pinned client.** It downloads into `.context/opencode-qa/`, checks the SHA-256
   before extracting or running anything, and exits 3 on a mismatch.

   ```bash
   Scripts/opencode-qa-home.sh fetch
   # prints …/.context/opencode-qa/bin/v2.2.5/opencode
   ```

2. **Seed scratch homes.** Each must not exist yet (or be empty). `seed-key` imports a fake
   Console key whose server is the stub at `127.0.0.1:48765`; it does not need the stub running.

   ```bash
   Scripts/opencode-qa-home.sh seed-key .context/opencode-qa/homes/key
   Scripts/opencode-qa-home.sh seed-empty .context/opencode-qa/homes/empty
   # optional: a device-flow (OAuth) home; this starts and stops the stub itself
   Scripts/opencode-qa-home.sh seed-device .context/opencode-qa/homes/device
   ```

   Other seeds: `seed-key <home> --integration opencode-go` (a key on the separate Go
   integration), `seed-key <home> --no-org`, `seed-device <home> --no-workspace`, and
   `seed-device <home> --token-lifetime 5` (ages the token past expiry so the next read refreshes;
   pair it with stub mode `refreshok` or `refreshbad`).

3. **Build a DEBUG Headroom.** `--opencode-executable` exists in DEBUG builds only, and only
   together with `--opencode-home`.

   ```bash
   swift build
   ```

4. **Run the stub and the probe inside one command**, so the stub cannot outlive it. The stub binds
   127.0.0.1 only and runs in the foreground; the `trap` stops it.

   ```bash
   bash -c '
   set -u
   ROOT=$(pwd -P)
   BIN="$ROOT/.context/opencode-qa/bin/v2.2.5/opencode"
   H="$ROOT/.context/opencode-qa/homes/key"
   /usr/bin/python3 -I Scripts/opencode-stub-console.py --port 48765 "$@" & SP=$!
   trap "kill $SP 2>/dev/null; wait $SP 2>/dev/null" EXIT
   for _ in $(seq 1 50); do /usr/bin/nc -z 127.0.0.1 48765 2>/dev/null && break; sleep 0.1; done
   /usr/bin/env HOME="$H/home" .build/debug/Headroom --probe-opencode --opencode-executable "$BIN" --opencode-home "$H"
   ' _ --mode go
   ```

   Replace `--mode go` with any stub mode (`go --limited monthly`, `nogo`, `expired`, `err500`,
   `malformed`, `wrongshape`, `slow`, `revoked`, `refreshok`, `refreshbad`). `swift run Headroom
   --probe-opencode --opencode-executable "$BIN" --opencode-home "$H"` works too; the `HOME`
   override matches how the checks were run. The probe prints the parsed windows or the outcome
   name only, never a workspace, URL, email, token or raw output. Recorded results:

   | Stub mode | Probe result |
   |---|---|
   | `go` | `live OpenCode snapshot, parsed 3 window(s)`: 5h 29%, Weekly 47%, Monthly 63% |
   | `go --limited monthly` | the same, with `Monthly  100% used  limited` |
   | `nogo` | `noGoPlan (signed in, no Go plan on the active workspace)` |
   | `expired`, `revoked` | `opencodeSignInExpired` |
   | `err500`, `slow` (about 16 s) | `opencodeTransientCapture (cause: consoleUnavailable)` |
   | `malformed` | `opencodeFormatChanged (stage: clientDecode)` |
   | no stub, `homes/empty` | `opencodeSignedOut` |

5. **See the client's raw output** for a home, when a format change needs diagnosing:

   ```bash
   Scripts/opencode-qa-home.sh usage .context/opencode-qa/homes/key   # with the stub running, as above
   Scripts/opencode-qa-home.sh run .context/opencode-qa/homes/key -- auth list --standalone --format json
   Scripts/opencode-qa-home.sh env .context/opencode-qa/homes/key     # the environment a run uses
   ```

   The script refuses `opencode service`, `auth export`, `upgrade` and any server-backed command
   without `--standalone`. Raw output from a real account carries a workspace ID, name and Console
   URL: sanitize it as the fixture manifest describes before it goes anywhere near a commit.

6. **Afterwards**, confirm nothing is left running:

   ```bash
   ps -axo pid,ppid,command | grep -E 'opencode-stub-console|v2.2.5/opencode' | grep -v grep
   ```

To read a real account, a 2.x client and a 2.x home are required. On the owner's machine, the
built-in home stays untouched until he upgrades it himself with `opencode upgrade --major`.
