# Safe provider session improvements

This is the approved shipping subset of the persistent-provider-sessions investigation.
The complete automatic-renewal plan is not claimed complete.

## Included behavior

- Claude polling runs the existing version-gated official `/usage` path without an
  `auth status` preflight. Login, trust and unknown screens receive no usage input.
  Returning-user signed-out footers are recognized before ready markers and directly
  from print output, without opening a second interactive process.
  A plan label is omitted when the usage report does not supply it.
- Codex rereads official-client credentials after the first HTTP 401. If the access
  token changed, it retries once using the new session and identity. An unchanged
  session offers Check Now first and Sign In Again second. No credential writes or
  automatic refresh process are introduced.
- Local 14-day session diagnostics separate observed sign-outs, credential rejections
  and sampling coverage. Diagnostic output contains aggregate counts, not account
  identities or credentials. HTTP 401 rejection edges include unchanged sessions
  without claiming login revocation. Intentional reset/removal ends the observation edge.
- Hosted XCTest composition is inert even when Xcode omits the scheme's demo argument.

## Provider parity

Claude's official-client boundary prevents the Codex HTTP retry policy from applying
there. Grok and Cursor authentication transports are unchanged. Aggregate diagnostics
cover all providers and all tracked accounts. The phone maps Codex uncertainty to its
existing retrying state; the sync schema is unchanged.

## Preserved unfinished work

The original `codex/persistent-provider-sessions` checkout at
`/Users/kylezantos/.codex/worktrees/c110/headroom` retains the automatic-renewal owner,
process adapter, protocol, policy, tests, synthetic harnesses, plan and review.
A private file-hashed snapshot also exists under
`/Users/kylezantos/.codex/session-recovery-backups/2026-10-20-c110`.
None of the four automatic-renewal source files or their project memberships is
included in this shipping branch. Their settlement, backend, lifecycle and real
persisted-renewal gates remain open.

## Earlier evidence and its limits

The private real-account VM completed 96 successful official-client reads per
provider over eight hours with zero failures. The earlier combined candidate then
returned three Claude windows and one Codex window without another login. Those
checks did not inspect credentials or force expiry and do not prove real rotation.
The shipping subset is tested independently below.

## Shipping verification

- `swift build`: passed; final incremental build 0.99 seconds.
- `swift test`: final unchanged confirmation passed **1,915 tests in 138 suites**,
  20.517 seconds. Before the two review fixes, 1,913 tests passed. New regressions
  then failed before their fixes. One subsequent full run hit the unchanged,
  previously recorded CLI locator scheduling flake; its assertion was not loosened.
- Hosted Mac `HeadroomAppTests`: **350 tests in 48 suites**, 22.530 seconds,
  `TEST SUCCEEDED` after the review fixes. Sparkle dependencies prepared first.
- iOS generic-simulator app and widget build: `BUILD SUCCEEDED` after the fixes.
- Inert `--dump-session-reliability --demo`: exit 0; only aggregate diagnostic
  headings, with the unbundled-state warning. No provider access was requested.
- `git diff --check`: passed.
- `ce-code-review`: independent Claude Opus 5.5 pass found two defects; both fixed
  with failing-before-fix regressions. Local passes were sequential in this context;
  no separate independent validator ran. Full coverage and advisory dispositions:
  `docs/reviews/2026-10-20-safe-provider-session-fixes-review.md`.

Final logs are `/tmp/headroom-safe-test-confirmation.log`,
`/tmp/headroom-safe-mac-tests-final.log`, `/tmp/headroom-safe-ios-final.log` and
`/tmp/headroom-safe-build-final.log`. These local checks do not establish real
renewal or measured sign-out reduction.
