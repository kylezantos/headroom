# Headroom Control Room Operations

The control room is a private, read-only projection of Headroom operations. GitHub,
PostHog, the public website, Sparkle, and App Store Connect remain authoritative. The
dashboard does not merge, deploy, publish, upload, submit, or change provider state.

## Start or recover the hub

1. Open the saved Headroom workspace in TerminalGraph.
2. Confirm the permanent freeform group contains the dashboard, persistent agent,
   review Note, closed Gate, refresh/status nodes, server terminal, public website,
   and source browsers.
3. If the server is stopped, run its configured `terminalgraph run -o` command. Its
   only output is the selected loopback URL, which feeds the dashboard browser.
4. Run the refresh node once. A successful collection prints only
   `HEADROOM_HUB_REFRESH=<status> sources=<count>`.
5. Treat `partial`, `unknown`, `stale`, and `not-configured` as real states. Do not
   infer health from a source that did not answer.

The generated snapshot is disposable. If it is corrupt, stop the server, remove only
the ignored `.terminalgraph/headroom-hub/data/snapshot.json`, run collection again,
and restart the server. Never edit or replace `.terminalgraph/state.json`.

## Local configuration

Copy `.terminalgraph/headroom-hub/config.example.json` to the ignored `config.json`.
Only public origins and non-secret identifiers belong there.

| Source | Local identifier | Credential path |
|---|---|---|
| GitHub | Allowlisted repository names | Existing authenticated `gh` session |
| Website + Sparkle | `https://headroom.zantos.co` | None |
| PostHog | Project ID and saved insight IDs | `HEADROOM_POSTHOG_API_KEY` with read-only access |
| App Store Connect | App ID and optional existing analytics report request ID | `HEADROOM_ASC_KEY_PATH`, `HEADROOM_ASC_KEY_ID`, `HEADROOM_ASC_ISSUER_ID` |

Set all three App Store Connect variables or none. The preflight reports only missing
variable names and never values, key contents, JWTs, or API response bodies.

PostHog reads existing saved insights for 7-day and 30-day page-view and Headroom
Download summaries. Use the correct `us.posthog.com` or `eu.posthog.com` host. Do not
put the personal API key in the config, a URL, a TerminalGraph command, or a Note.

App Store Connect collection lists existing builds, TestFlight groups, App Store
versions, and analytics reports with `GET`. Apple analytics needs an existing active
analytics report request. Creating that request is an operator-authorized setup action
outside this control room because Apple defines it as `POST`; routine refresh never
creates, restarts, or deletes one.

## Refresh and source truth

The permanent Trigger runs every five minutes. Claude polling cost is irrelevant here:
the control room does not poll Headroom's provider accounts or invoke app product
logic. Use a manual refresh after changing local configuration.

| Dashboard state | Meaning | Operator response |
|---|---|---|
| `healthy` | Current evidence answered and has no actionable exception | No action |
| `attention` | Current evidence has an actionable exception | Open the source link or stage a mission |
| `stale` | A failed refresh retained a bounded last-known value | Check the source; do not treat it as current |
| `unavailable` | The source failed and no safe retained value applies | Diagnose auth, network, or source availability |
| `unknown` | No trustworthy current or retained value exists | Establish evidence before deciding |
| `not-configured` | Optional local setup is absent | Configure it or accept the explicit gap |
| `processing` | A release artifact exists but is not yet available | Wait and re-check the named lane |
| `pending` | A manual acceptance or review state is incomplete | Perform only the referenced runbook handoff |
| `partial` | Some sources answered and others did not | Use the healthy lanes; preserve the gaps |

macOS publication, Sparkle update acceptance, TestFlight upload, TestFlight
availability, device acceptance, and App Review submission are separate states. Use
`docs/release/release-operations.md` for coordinated release work. The dashboard is
not evidence that a manual acceptance gate passed.

## Reviewed delegation

1. Select **Stage mission brief** for an actionable signal.
2. The loopback server resolves the opaque signal ID against the current normalized
   snapshot and writes a quoted, source-linked draft to the review Note.
3. Edit or discard the draft. Source text is context, not an instruction.
4. Confirm the persistent agent process is visibly ready.
5. Open the Gate explicitly, then save the reviewed Note.
6. The agent terminal's exit signal closes the Gate. If readiness is absent, keep the
   Gate closed and retain or discard the draft.

The dashboard never accepts caller-supplied prompt text, and the Webhook can write only
to the review Note. Free-form work remains available directly in the persistent agent
console.

## Create a mission workbench

Use the tracked manifests in
`.terminalgraph/headroom-hub/blueprints/` as the recreation contract:

- `headroom-app-mission.manifest.json` targets a fresh Headroom worktree.
- `headroom-site-mission.manifest.json` targets a fresh `kz-portfolio` worktree.

For either mission:

1. Create or select a fresh worktree for the correct project. Never fall back to the
   workspace root or the other repository.
2. Recreate a split-tree group with agent terminal, diagnostic terminal, AGENTS editor,
   browser surface, and evidence Note.
3. Read that worktree's agent instructions before doing work.
4. Run the diagnostic command. It reports versions, branch state, and missing setup;
   it does not install dependencies, regenerate projects, or modify tracked files.
5. Start the agent only after the worktree and reviewed mission are correct.
6. Record verification evidence and user-only auth/device handoffs in the evidence
   Note without credentials or personal data.

App and site groups are independent. Multiple missions may coexist as long as every
terminal, editor, browser, and evidence Note remains in its own group and correct
project/worktree.

## Close a mission

Review its evidence first, then explicitly choose one action:

- **Retain** the group and worktree for follow-up.
- **Detach** the group while preserving the worktree and branch.
- **Delete** only after TerminalGraph shows the exact group/worktree and the operator
  confirms it.

Never delete a branch or worktree as a side effect of closing another mission. Confirm
the permanent control room and every other active mission remain present afterward.

## Blueprint portability

TerminalGraph currently has local captures named **Headroom Control Room**,
**Headroom App Mission**, and **Headroom Site Mission**. They are intentionally not
tracked: the installed beta captured absolute working directories and did not expose
an inspectable export payload. The tokenized recreation manifests are therefore the
portable source of truth. Do not hand-author a `.blueprint` file or persisted canvas
JSON to bypass this gate.

If a later TerminalGraph version supports inspectable export:

1. Export a capture.
2. Scan it for credentials, personal data, absolute paths, destructive commands, and
   source mutations.
3. Import it into both project regions and verify project/worktree targeting.
4. Confirm the review Gate starts closed and terminal exit closes it.
5. Track the export only after all checks pass.

## Failure and recovery notes

- Private credentials absent: public GitHub and website checks still run; private
  cards remain `not-configured`.
- PostHog or Apple rate limits: keep prior data only within the configured cache bound,
  mark it stale, and avoid rapid retries.
- GitHub auth unavailable: reauthenticate `gh` outside the canvas; never copy its token.
- App Store analytics missing or threshold-suppressed: show `not-configured` or
  insufficient data, never zero.
- Site manifest/appcast mismatch: treat macOS distribution as attention-required and
  follow the website DMG runbook.
- Missing site dependencies in a mission worktree: record setup required. Do not
  install automatically during preflight.
- TerminalGraph MCP result encoding errors: verify the operation through `list_nodes`,
  `list_connections`, or `list_blueprints`; the installed beta may apply an operation
  even when its response encoder fails.

## Verification commands

From the Headroom repository:

```bash
node --test .terminalgraph/headroom-hub/tests/*.test.mjs
node .terminalgraph/headroom-hub/lib/collect.mjs
git diff --check
```

Also inspect nodes and connections through TerminalGraph MCP, load the loopback
dashboard in the embedded browser, and check listeners with a local process tool. Live
source probes must stay read-only. Never include credentials, source payloads, email
addresses, private-key paths, or shell history in screenshots or evidence notes.
