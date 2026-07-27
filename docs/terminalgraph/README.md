# Headroom TerminalGraph Workspace

This directory contains requirements, plans, and operating notes for the private
TerminalGraph workspace used to monitor and manage Headroom.

These artifacts describe developer tooling around Headroom. They are not product
requirements for the macOS or iOS apps, public release documentation, or user-facing
support material.

## Directory boundaries

- `brainstorms/` defines what the TerminalGraph workspace should do.
- `plans/` defines how the TerminalGraph workspace and its supporting local tools
  should be built.
- Future operating notes specific to this workspace belong under this directory.
- TerminalGraph runtime assets and persisted canvas state belong under
  `.terminalgraph/`, following TerminalGraph's project conventions.

Headroom product plans remain in `docs/plans/`. Release runbooks remain in
`docs/release/`. Product learnings remain in `docs/solutions/`.

## Runtime boundary

The tracked hub implementation is rooted at `.terminalgraph/headroom-hub/`. Its
source, synthetic fixtures, dashboard, and recreation manifests are portable. Local
configuration, normalized snapshots, operator evidence, logs, worktrees,
screenshots, and TerminalGraph canvas state are ignored and must not be committed.

The hub is read-only with respect to GitHub, PostHog, the public website, App Store
Connect, and release systems. It does not add analytics to either Headroom app and
does not merge, deploy, publish, create Apple analytics report requests, or submit
builds for review.

## MCP registration

The implementation plan assumes TerminalGraph is registered with Codex:

```bash
codex mcp add terminalgraph -- "$HOME/.config/terminalgraph/bin/terminalgraph" mcp
```

Restart or reconnect the Codex session after registration so the TerminalGraph tools
become available. Registration changes Codex's user configuration; it does not add
product code or repository credentials.
