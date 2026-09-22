# Headroom Release Operations

Use this checklist to coordinate a Headroom release that includes the macOS website DMG,
TestFlight, or both. The platform runbooks remain authoritative for their artifact-specific
commands:

- `website-dmg-release.md` — Developer ID, notarization, Sparkle, Headroom website, and public DMG
- `ios-app-review-testflight.md` — archive, upload, TestFlight, and App Review

This document defines the operating order, status vocabulary, and manual boundaries shared by
both lanes.

## Release states are not interchangeable

Record each state independently. Never summarize a partial chain as “released.”

| State | Meaning |
| --- | --- |
| Source ready | Required tests pass and the release commit is merged to `main`. |
| Candidate tested | The exact signed candidate passed its track-specific automated and installed-app gates. It is not yet public. |
| macOS published | The notarized DMG, manifest, appcast, and deltas are live and verified. |
| Sparkle accepted | An older public installation upgraded to the new build and relaunched. |
| TestFlight uploaded | App Store Connect accepted the archive upload. Processing may still be pending. |
| TestFlight available | Processing and export compliance completed and the build is assigned to the intended group. |
| TestFlight accepted | A clean TestFlight installation passed the device checklist. |
| App Store submitted | The selected build and metadata were submitted to App Review. |

## Phase 0 — preflight before changing release state

Write down the target marketing version and build, the previous public macOS build, and the last
uploaded iOS build. Then confirm every environment required for the requested finish line:

- Headroom `main` and `headroom-site/main` are clean, current, and synchronized with origin.
- Developer ID, notarization, Sparkle signing, Xcode/App Store Connect, and Vercel authentication
  are available without exposing secret values.
- A VM/dedicated Mac, or a dedicated macOS user with a user-local `~/Applications` install, has
  the previous public DMG for the Sparkle acceptance gate. A separate user does not isolate the
  shared `/Applications` directory.
- A supported physical iPhone with TestFlight is available for internal acceptance.
- A real macOS 15 Apple-silicon environment is available when Sequoia support is a required gate.
- Permission to use the user's logged-in visible Chrome has been obtained before opening it.
- Any password, passkey, two-factor, privacy-permission, or device-unlock handoff is identified up
  front and assigned to the user.

If a required environment is unavailable, stop and resolve the scope before publishing. The user
may explicitly waive a gate or authorize publication with a named residual; record that decision
before continuing. Do not discover or renegotiate known external gates after the artifacts are
already live.

## Phase 1 — build one candidate

1. Stamp the paired host/widget versions once.
2. Run source, unit, UI, archive, and release preflight checks required by the platform runbooks.
3. Merge the candidate to Headroom `main`.
4. Build public artifacts only from that exact merged commit.

Do not rebuild from a feature branch, silently advance a build number, or let the macOS and iOS
targets drift to different build numbers during a paired release.

## Phase 2 — publish through supported lanes

1. Produce and validate the signed/notarized macOS artifact with `Scripts/release-app.sh`.
2. Publish its complete asset set through a normal `headroom-site` PR and `pnpm ship`.
3. Archive and upload iOS with `Scripts/release-ios-testflight.sh`; if Xcode account state prevents
   CLI upload, use Xcode Organizer once for the same fresh archive.
4. Verify external state independently: public website files for macOS, processing/group state in
   App Store Connect for iOS.

Do not alternate repeatedly between CLI, Xcode, browser, Screen Sharing, and accessibility
automation for the same gate. Choose the supported path, capture its result, and use one explicit
operator handoff if it reaches a user-only boundary.

## Phase 3 — acceptance without UI improvisation

Manual handoffs are valid release steps. They are not failures to automate.

For a Claude capability change, record Track A separately from unrelated provider and reset work.
Its signed installed-app evidence must use two previously configured Claude accounts and cover:

- Finder launch with a sparse inherited `PATH`, then update and relaunch of the same installation;
- a supported executable-location change, a transient inconclusive discovery, recovery through
  **Check Again**, and continuity retention without rerunning setup;
- one account reporting login-required or trust-required while its sibling remains live;
- exactly one provider-level install/retry notice, with account recovery actions staying scoped
  to the affected account; and
- `--probe-claude` output containing only capability categories, event ages, safe CLI version
  band, built-in/extra account category, and allowlisted parsed-window facts.

The tester approves every official Claude login or trust prompt manually. Evidence must not
contain executable/config paths, account labels or emails, provider panel text, credentials,
auth payloads, or raw errors. A passing local development build is source evidence only; a signed
candidate is **Candidate tested**; a successful public update is **Sparkle accepted**; neither
state implies **macOS published** unless the public artifacts were separately verified.

For a reset-accuracy or widget snapshot schema change, record Track B separately. Its signed
installed-app evidence must cover the macOS popover, macOS widgets, iPhone companion, and iOS
widgets with scheduled, absent, elapsed, malformed, implausible, and invalid-zone reset fixtures.
Confirm `Available` appears only for a fresh exact-zero absent/elapsed row; all other unresolved
rows say `Reset info unavailable`. Cross genuine deadlines and sleep/wake boundaries, checking
the `6d 4h`, `6d`, `13h 37m`, and `37m` precision cases and the ±60-second `Resets now` boundary.
Migrate v1/v2 local and synced fixtures, surface future schemas as incompatible without rewriting
them, and confirm equal-generation local data wins. Record only reset categories and ages. A
downgrade to a pre-v3 publisher is unsupported for reset fidelity because iCloud KVS cannot fence
an older writer; do not treat downgrade behavior as a safe rollback path.

- Use Computer Use only when the target app exposes a stable accessibility surface. If a menu-bar
  popover or transient system surface is not available after one fresh state query, stop. Ask the
  tester for the exact click and continue from the resulting window. Never brute-force menu-bar
  positions, keyboard focus offsets, or hidden controls.
- Do not use iPhone Mirroring as the default TestFlight path. Use it only when it is already
  configured and the user explicitly chooses it. Never trigger or work around a Mac login-password
  prompt to continue device automation.
- Never enter, read, copy, or automate passwords, passkeys, two-factor codes, device unlocks, or
  macOS privacy confirmations. State the exact handoff and wait.
- Ask before opening a visible logged-in Chrome profile. Prefer the release CLI, Xcode Organizer,
  or App Store Connect API when already configured.
- Never substitute a local/development build for an older public Sparkle installation. Never
  replace the user's working `/Applications/Headroom.app` for acceptance unless they explicitly
  approve that fallback and the existing bundle is backed up recoverably first.

Before an installed-app GUI check, prove which processes are actually running:

```bash
ps -axo pid=,etime=,command= | rg 'Headroom\.app/Contents/MacOS/Headroom'
```

Bundle copies found by Launch Services are not running instances. Keep exactly the intended public
app running, close only QA copies whose exact paths and PIDs were verified, and never use `killall`
or a broad process match during release acceptance. Treat the WidgetKit extension as a separate,
normal process.

## Phase 4 — closeout

Update the release evidence with exact facts and timestamps:

- merged Headroom and Headroom website commits;
- notarization results, public checksum, appcast version/build, and Sparkle acceptance result;
- TestFlight upload, processing, group assignment, clean-install acceptance, and App Review state;
- every explicitly accepted residual, including the environment that was unavailable;
- temporary mounts, test processes, app backups, SSH keys, or test credentials created and their
  cleanup/restore status.

Run final repository synchronization and cleanliness checks. Report each release state from the
table above; do not collapse pending acceptance into a generic “everything is shipped.”
