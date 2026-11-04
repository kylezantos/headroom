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

## 1.5 paired release: sync skew, iCloud environments and build numbers

Mac 1.5 publishes two phone formats in one publish: the primary-only schema-3 key that build 33
and 1.4.1-era phones read, and the multi-account v4 keys under `headroom.sync.v4.` (AGENTS.md,
"iPhone and iPad companion"). Users will mix versions, so the U20 integration pass records every
row below on a signed Mac and the physical iPhone, same Apple ID. Fill the result columns from
what was observed; leave a cell empty rather than guess. Record key names and sizes only, from
the Mac's `--dump-phone-sync` (signed bundle) and the phone's DEBUG Sync Diagnostics, never
payload contents.

| Pairing or event | Format that won (v4 / v3 / none) | Lineage seen | Ladder level | Dimming state | v4 keys present (names, sizes) | Result |
|---|---|---|---|---|---|---|
| 1.4.1 Mac + 1.5 phone | | | | | | |
| 1.5 Mac + build-33 phone | | | | | | |
| 1.5 Mac + 1.5 phone | | | | | | |
| 1.4.1 Mac upgraded in place to 1.5 while a 1.5 phone shows v3 (no skeleton flash, no "update your Mac" line) | | | | | | |
| 1.5 Mac downgraded to 1.4.1, then upgraded again (stale pre-downgrade v4 never shows as current) | | | | | | |
| Sync off on a 1.5 Mac | | | | | | |
| Sync off on a downgraded 1.4.1 Mac (v4 keys stay until the next 1.5 launch) | | | | | | |
| 1.5 Mac + public 1.0 (24) phone (expected "Snapshot Unreadable" or frozen, no crash) | | | | | | |
| 1.5 iPhone + 1.5 iPad on one Mac (two request keys, one Mac refresh, both finish) | | | | | | |
| Two Macs on one Apple ID (optional, unsupported; record for the release notes) | | | | | | |
| Build 33 reinstalled over 1.5 (`widget-snapshot.json` still decodes) | | | | | | |
| Mac clock 10 minutes behind | | | | | | |
| Mac clock 10 minutes ahead | | | | | | |
| Phone Apple ID changed while the app is closed, to an account with no Headroom keys and iCloud Drive off (no prior-account content on widget, Siri or control loads) | | | | | | |
| Same Apple ID, phone offline (cached content still shows) | | | | | | |
| Developer ID Mac + TestFlight phone (CloudKit Production on both) | | | | | | |
| Xcode-run Mac + Xcode-run phone (CloudKit Development on both) | | | | | | |

The account-change and offline rows only mean something once `CompanionLoaderAdoption` is on;
until then record "adoption off" and the build-33 behavior observed. Record the signed identity
gate result (`docs/qa/2026-10-04-companion-identity-candidate-gate.md`) beside them.

**A 1.4.1 Mac cannot delete v4 keys.** It predates the v4 namespace, so turning sync off there
writes only the disabled schema-3 envelope and leaves the manifest, provider, receipt and request
keys in iCloud. A phone still reads the disabled v3 as paused. The next 1.5 launch with sync off
sweeps the leftovers, because the 1.5 sweep repeats on every launch while sync is off. Say so in
the release notes for anyone who downgrades.

**iCloud environments (CloudKit reminders, conditional on the U15 spike).** Key-value storage has
no environment split; CloudKit does. A notarized Developer ID Mac carries
`icloud-container-environment = Production`, and every TestFlight or App Store phone reads
Production, so the shipping pair is Production + Production. A Mac run from Xcode and a phone run
from Xcode both use Development. Never pair across environments: a Development Mac writes records
a Production phone never sees, and the subscription silently stays quiet. Deploy the
`ReminderEvent` schema to Production before any Production build saves a record; Production
schema changes cannot be removed. The spike runbook on `spike/u15-cloudkit-reminders`
(`docs/qa/2026-10-cloudkit-reminders-spike.md`) carries the exact steps.

**Build numbers (decided 2026-10-05).** Mac 1.4.1 is build 33, and iOS TestFlight already holds
1.5 (33). The U15 CloudKit spike's TestFlight upload takes iOS **34**. The 1.5 release is build **35**
for every target, Mac included, so the paired builds stay equal. The release-candidate step stamps 35
once, on `main`; feature branches never stamp it. PR #160's `docs/release/1.5-release-checklist.md`
records this.

## Phase 4 — closeout

Website content and GitHub releases are required parts of every release, owned by the releasing
agent. Follow the website runbook's content audit and cross-repository sync gate before the
website PR, then publish both GitHub descriptions from the canonical Sparkle notes with
`Scripts/github-release.py` at the exact artifact source commit. Verify the live changelog,
homepage and both GitHub releases. Website production promotion still requires explicit approval;
GitHub publication never implies App Store publication.

Update the release evidence with exact facts and timestamps:

- merged Headroom and Headroom website commits;
- website content audit, live changelog/version/date checks, source GitHub tag/commit and both
  source/archive release URLs with matching canonical notes;
- notarization results, public checksum, appcast version/build, and Sparkle acceptance result;
- TestFlight upload, processing, group assignment, clean-install acceptance, and App Review state;
- every explicitly accepted residual, including the environment that was unavailable;
- temporary mounts, test processes, app backups, SSH keys, or test credentials created and their
  cleanup/restore status.

Run final repository synchronization and cleanliness checks. Report each release state from the
table above; do not collapse pending acceptance into a generic “everything is shipped.”
