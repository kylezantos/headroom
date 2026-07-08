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

- ~~App icon — user to provide.~~ Done: Vessel `AppIcon.appiconset` (16–1024), wired via
  `ASSETCATALOG_COMPILER_APPICON_NAME`. The artwork is full-bleed square PNG output so iOS,
  iPadOS, and macOS can apply their native icon shape without a second baked-in frame.
  Regenerate all sizes with `node Scripts/gen-app-icon.mjs` (master:
  `design/vessel-app-icon.svg`).
- `MenuBarLabel` uses a fixed font size (menu bar height is OS-constrained).

## iPhone sync — Mac needs the iCloud-KVS entitlement (provisioning-gated)

- **Confirmed root cause of "iPhone shows a stale snapshot".** The installed standalone
  `Headroom.app` publishes phone snapshots through `NSUbiquitousKeyValueStore`, which is inert
  without the `com.apple.developer.ubiquity-kvstore-identifier` entitlement. `Scripts/build-app.sh`
  **strips** that entitlement unless `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1`, so a default-built
  app can't publish at all — `iCloudSnapshotPublisher.export` swallows the failure (`try?`) and
  the iPhone freezes on the last snapshot that propagated while a properly-provisioned build ran.
  Verify with `Headroom.app/Contents/MacOS/Headroom --dump-phone-sync` (run from the **signed
  bundle**, not `swift run` — a bare CLI has no bundle id/entitlement and always reads empty).
- **The entitlement is provisioning-gated.** `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1` alone isn't
  enough: the restricted entitlement needs an embedded provisioning profile, or macOS SIGKILLs
  the app at launch (exit 137, verified). `build-app.sh` now accepts
  `HEADROOM_PROVISIONING_PROFILE=/path/to/*.provisionprofile` to embed one, and warns when the
  entitlement is on without a profile.
- **Fix path (needs the Apple Developer account — interactive):** enable the iCloud Key-Value
  storage capability for `com.kylezantos.headroom` (team `8D42S4MS38`), then either run/archive
  the macOS target from Xcode with managed signing (embeds the profile automatically) and install
  that build, or download a macOS development profile and rebuild with
  `HEADROOM_ENABLE_ICLOUD_ENTITLEMENT=1 HEADROOM_PROVISIONING_PROFILE=… ./Scripts/build-app.sh`.
  The iOS host/widget entitlements already declare the key and are signed via Xcode, so the phone
  read side is fine — only the Mac publisher is blocked.

## Companion platforms

- **watchOS companion is deferred.** It should probably reuse the iCloud snapshot contract,
  but it needs separate watch targets, signing/provisioning, widget complications or a
  Watch app surface, and real-device QA. Treat it as a follow-up rather than folding it
  into the iPhone companion branch.
