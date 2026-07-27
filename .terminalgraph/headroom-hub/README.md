# Headroom Hub

This directory contains the tracked, dependency-free Node tooling behind the private
TerminalGraph control room. It is an operational projection only: Headroom product
code, provider credentials, source payloads, and release mutations do not belong
here.

## Portable and local files

Tracked files include source adapters, synthetic redacted fixtures, tests, dashboard
HTML, and recreation manifests. A TerminalGraph blueprint may be tracked only after
its export contains no credentials or machine-specific paths.

Copy `config.example.json` to the ignored `config.json` for local source identifiers.
Generated snapshots live in the ignored `data/` directory. Operator-supplied release
evidence lives in the ignored `evidence/` directory. TerminalGraph-owned
`../state.json`, hooks, worktrees, logs, and screenshots also remain local.

The tokenized recreation contracts are:

- `blueprints/headroom-control-room.manifest.json`
- `blueprints/headroom-app-mission.manifest.json`
- `blueprints/headroom-site-mission.manifest.json`

TerminalGraph's local captures are useful on this machine but are not tracked because
the installed beta retains absolute working directories and does not expose an
inspectable export payload. Never hand-author TerminalGraph-owned blueprint or canvas
JSON to work around that portability gate.

## Credential boundaries

- GitHub reads use the authenticated `gh` CLI and never copy its token.
- PostHog reads use `HEADROOM_POSTHOG_API_KEY`, provisioned with read-only access.
- App Store Connect reads reuse `HEADROOM_ASC_KEY_PATH`, `HEADROOM_ASC_KEY_ID`, and
  `HEADROOM_ASC_ISSUER_ID`. Set all three or none.
- No credential belongs in `config.json`, a fixture, snapshot, mission note,
  blueprint, URL, or command argument.

The preflight reports only `ready`, `not-configured`, `setup-required`, or
`incomplete`, plus the names of missing environment variables. It never prints
credential values, private-key contents, or provider response bodies.

## Tests

Run all fixture-driven checks from the repository root:

```bash
node --test .terminalgraph/headroom-hub/tests/*.test.mjs
```

Tests use synthetic fixtures and must not contact live services.

## Operations

See `docs/terminalgraph/operations.md` for source setup, the state matrix, reviewed
delegation, mission creation and closeout, recovery, and live verification.
