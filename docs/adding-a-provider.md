# Adding a provider

This is a practical starting point for contributors and their agents. Start with
[CONTRIBUTING.md](../CONTRIBUTING.md) and [AGENTS.md](../AGENTS.md) for process and architecture.
Consult [DESIGN.md](../DESIGN.md) when changing UI.

## Start with the accepted issue

An `accepted` issue means the maintainer wants the feature and welcomes a contribution.
You can investigate the official client, try an isolated prototype and choose the implementation
within the existing patterns. A small feasibility PR is welcome when the read path is uncertain;
it is not a required separate stage. Document what you found in the issue or PR.

Discuss a different authentication/data-access mechanism or significant architecture change
before implementing it. You do not need separate approval for every command, helper or parser.

## Follow the existing pipeline

An ordinary provider fits this path:

**Official client/status source → injected capture/parser → `UsageProvider` → shared
polling/store → existing Mac, phone and widget presentation.**

| Responsibility | Starting points |
| --- | --- |
| Discover/run a CLI, capture output | `CLIExecutableResolver`, `CLIExecutableLocator`, `StdioChildProcess`, existing PTY probes in `Sources/HeadroomCore/Providers/` |
| Parse and normalize a reading | Injectable source + typed capture; see `OpenCodeUsageSource`, `ClaudeUsageParser` and `CursorUsageCLIProbe` |
| Supply account snapshots | [UsageProvider.swift](../Sources/HeadroomCore/Models/UsageProvider.swift); see `OpenCodeProvider` and `CursorProvider` |
| Wire the provider | `AppComposition.subscriptionProviderRegistry` in [HeadroomApp.swift](../Sources/HeadroomApp/HeadroomApp.swift), plus `ProviderID` and preferences |
| Poll, merge and age readings | `AccountProbeScheduler`, `LaneSchedule`, `UsageStore`; reuse the existing lane/backoff/freshness behavior |
| Accounts and sign-in | `AccountRegistry`, `AccountStorage`, `ProviderAccountConfiguration`, `SetupSessionCoordinator` and `UI/SetupSessions.swift` |
| Display and sync | Existing shared components/recipes, `CompanionSyncModels`, iOS views/widgets and App Intents |

Choose the closest example, not necessarily the newest provider. Structured CLI output, a PTY
status panel and official-client logs have different tradeoffs. Reuse the useful seams without
copying vendor-specific quirks. A provider normally does not need a second polling engine,
custom login system, new settings navigation or its own card/widget implementation.

## Keep the read path safe and the numbers honest

- Prefer a read-only status surface provided by the vendor's official client. Record its exact
  version/build and the official documentation; link pinned upstream source when available.
  Check what a poll does, including startup behavior. It must not send model requests, execute
  agent tools, spend quota or change the user's workspace/login to obtain a reading.
- Do not harvest subscription OAuth tokens, copy browser cookies, scrape dashboards, impersonate
  first-party clients or add undocumented subscription API calls. An endpoint appearing in
  upstream source is not permission to call it directly. A documented public quota API can be
  proposed, but agree on that different access path first.
- Existing Codex HTTP and Grok fallback paths have provider-specific boundaries in AGENTS.md;
  they are not a general recipe for another vendor's credentials. The Claude OAuth prohibition
  there still applies. A slash command passed through prompt mode is not automatically a safe
  status read: verify routing before automating it.
- Establish which product, plan and pool the numbers describe. Session token statistics,
  account-wide quota, advertised rate limits and API spending are different measurements.
  Preserve source-provided units, used/remaining direction, reset times and freshness. Missing
  values are unavailable, not zero; do not invent resets or combine unrelated model pools.
- Use typed failures and the store's continuity rules. A timeout or unknown response is not
  evidence of sign-out or a missing CLI. Keep raw responses, tokens and account details out of
  logs, errors, screenshots and committed fixtures.

## Fit into the rest of Headroom

- New providers are normally opt-in/off by default. Use the shared setup/Terminal handoff and
  account management. Prove client-home isolation before offering extra accounts; single-account
  support is reasonable when the client cannot isolate them. Explain the limitation.
- Keep demos, render/bench harnesses and hosted tests inert: no real CLI, credential/config access,
  sign-in or live sync. Use fixture sources and isolated test data through the existing seams.
- Review the ordinary provider surfaces: Settings/accounts, Standard/Compact popover, menu bar,
  refresh/reminders, Mac widgets, phone sync/display, home/Lock Screen widgets and Siri/intents.
  Parity is the default; discuss and document client-imposed exceptions or staged delivery.
- Search current code for a similar provider (for example `opencode`) to find registration and
  switch sites. Classify the matches rather than mechanically replacing names or changing frozen
  compatibility fixtures and historical notes. Keep stored IDs stable and preserve sync decoding.
- Use existing UI tokens/components. Check the new provider alongside the others in dense layouts
  and relevant account/sync tests. Discuss a genuinely needed model/schema/layout extension;
  do not redesign shared systems or raise budgets just to make the integration fit.

## Make the PR easy to review

Link the accepted issue and explain the chosen source, quota semantics, supported client version,
account behavior and known limitations. Sanitized fixtures and focused parser/provider/error
handling tests should cover the new behavior; reuse existing process and scheduling helpers.
Tests stay offline and do not use real accounts, network or Keychain. Add the fixture/demo coverage
needed to inspect the provider without credentials.

Run the build/test commands in CONTRIBUTING.md and the relevant existing rendering, sync and
account checks. Where possible, compare a live reading with the official client using an account
you are authorized to test. Distinguish live observations, source-derived behavior and synthetic
fixtures; state what remains unverified rather than forcing a paid/exhausted state to prove it.
Keep PRs focused, preserve existing assertions, and document the transport/limits in
`docs/solutions/` plus AGENTS.md. Official releases and website deployment remain maintainer work.

## Useful examples

- [OpenCode: structured reads and isolation](solutions/opencode-cli-usage-feasibility.md)
- [Cursor: PTY status output](solutions/cursor-agent-usage-feasibility.md)
- [Copilot: client-produced records and freshness](solutions/copilot-cli-usage-feasibility.md)
- [Grok: its specific approved fallback](solutions/grok-build-usage-feasibility.md)
- [Polling design](solutions/architecture-patterns/per-account-polling-measured-duty-cycle.md)
- [Phone sync contract](solutions/architecture-patterns/companion-sync-v4-multi-key.md)
