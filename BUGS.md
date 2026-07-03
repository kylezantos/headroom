# Deferred / Follow-up

Non-blocking items. The app works end-to-end (75 tests pass; live Claude + Codex data
verified). The earlier OAuth/Keychain-token approach and its U9 spike are **obsolete** —
Anthropic prohibits and blocks third-party subscription-OAuth use, so Claude now reads the
official `claude` CLI's `/usage` panel instead.

## Claude CLI probe

- **Parser is pinned to the current `/usage` layout.** `ClaudeUsageParser` keys on stable
  shapes ("Current session", "Current week (…)", "N% used", "Resets …") rather than line
  positions, but a future Claude Code redesign of the panel could still break it. It fails
  safe (empty result → transient stale), and the `--probe-claude` diagnostic makes drift
  easy to spot. Add a version check / update the fixture if the panel changes.
- **Each poll spawns a full `claude` session (~20–30s, some CPU).** Fine at the default
  5-minute cadence for a personal tool; if the interval is set very low in Settings this
  becomes noticeable. Consider a minimum floor or caching if that matters.
- **No live integration test for the PTY probe.** Provider tests use a fixture panel +
  mock source (fast, deterministic). The real `ClaudeUsageCLIProbe` is verified manually
  via `--probe-claude`; a machine-dependent integration test would need the CLI logged in.

## Reliability (carried from earlier review)

- **No backoff on repeated failures.** Both providers retry every cycle at the fixed
  interval. Exponential backoff on consecutive transient failures would be gentler on a
  down endpoint. Design choice — deferred.

## Polish

- ~~App icon — user to provide.~~ Done: Vessel `AppIcon.appiconset` (16–1024, full-bleed
  for Tahoe's glass mask), wired via `ASSETCATALOG_COMPILER_APPICON_NAME`. Regenerate the
  master from `design/vessel-icon.html`.
- `MenuBarLabel` uses a fixed font size (menu bar height is OS-constrained).
