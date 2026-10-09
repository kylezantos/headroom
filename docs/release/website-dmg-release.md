# Website DMG Release Runbook

Use this runbook to ship a new public macOS Headroom release at
`https://headroom.zantos.co`. It covers the whole chain: version metadata, Developer ID
signing, Apple notarization, Sparkle appcast generation, the externally archived download files,
and live verification. It also includes the installed-app acceptance test for Sparkle updates.

For a coordinated macOS + TestFlight release, start with `release-operations.md`. It defines the
shared preflight, state vocabulary, UI boundaries, and closeout evidence. This runbook owns only
the macOS website lane.

The macOS app source is this repository. The public files are hosted by the separate
`/Users/kylezantos/App Development/Manual Library/headroom-site` repository. Its Vercel
project owns `headroom.zantos.co`; do not deploy the generated `dist/` directory directly as a
new Vercel project.

## Prerequisites

- The Headroom release commit already merged to `main`, and a clean, up-to-date
  `headroom-site/main` before creating its publish branch.
- A Developer ID Application certificate installed locally.
- Working notarization credentials, normally the `headroom-notary` keychain profile.
- The Sparkle private signing key available in the login Keychain.
- A non-empty `docs/release/sparkle/Headroom-<version>-<build>.html` file for the target
  macOS marketing version and build.
- `xcodegen`, Xcode, `gh`, `pnpm`, and the Vercel CLI installed and authenticated.
- A VM/dedicated Mac, or a dedicated macOS test user with a user-local `~/Applications` install,
  with the previous public DMG ready for the installed Sparkle update test. A separate user does
  not isolate the shared `/Applications` directory. Confirm this before publishing, not after the
  new appcast is live.

Confirm the signing prerequisites without exposing credentials:

```bash
security find-identity -v -p codesigning | rg 'Developer ID Application'
xcrun notarytool history --keychain-profile headroom-notary
```

Website ownership: GitHub `kylezantos/headroom-site`, Vercel `headroom-site`.
`main` is staging; `production` serves `headroom.zantos.co`. Portfolio deployments are
independent and must never be used to publish Headroom. Only signed binaries go into
`kylezantos/headroom-downloads`; keep the source repositories private.

## 1. Bump the release version

Create a release branch in this repository. Update `project.yml` as one consistent unit:

- macOS app and widget `MARKETING_VERSION`
- macOS app Info.plist version settings
- `CURRENT_PROJECT_VERSION` for all app targets, including iOS targets

Regenerate the Xcode project, test the bump, and merge it before creating the public artifact:

```bash
xcodegen generate
swift test
bash Tests/ReleaseScripts/sparkle-release-notes-tests.sh
python3 Tests/ReleaseScripts/dmg-layout-check-tests.py
```

The generated `Headroom.xcodeproj/project.pbxproj` must be committed with `project.yml`.
Release from `main`, never from an unmerged feature branch.

Write the user-facing Sparkle notes for the exact macOS version/build at
`docs/release/sparkle/Headroom-<version>-<build>.html`. Use a short heading and concise HTML body
that make sense inside Sparkle's standard update prompt. Do not add scripts, tracking, or external
assets. The release script fails if this exact file is missing or empty; a note for another build
does not satisfy the gate.

**Proofread the notes against the shipping UI before continuing (R2B1).** They are the
widest-audience copy Headroom publishes and the surface easiest to leave behind when a
setting is renamed.

- **Curly punctuation.** Apostrophes and quotes must be typographic (`’` `“` `”`), as in
  every user-facing string in the app. The check is a search for straight `'` and `"`
  *inside* the prose — attribute quotes in the HTML tags themselves stay straight:

  ```bash
  grep -n "[^=]'" docs/release/sparkle/Headroom-<version>-<build>.html
  ```

- **Names match the build.** Every setting, control, or option named in the notes must
  read exactly as the release renders it. Open the relevant Settings pane and compare;
  a note describing the previous name is a support ticket.

## 2. Seed the release staging folder from production

`Scripts/release-app.sh` generates the appcast from `dist/headroom.zantos.co`. That directory
is local build output and may be stale. Before every release, seed it from the current
production asset set in the Headroom website repository. This preserves the current appcast item and
lets Sparkle generate a delta from the version users actually have.

```bash
STAGING='dist/headroom.zantos.co'
if [[ -e "$STAGING" ]]; then
  BACKUP="dist/release-staging-backups/$(date -u '+%Y%m%dT%H%M%SZ')"
  mkdir -p "$BACKUP"
  mv "$STAGING" "$BACKUP/headroom.zantos.co"
fi
ditto \
  '/Users/kylezantos/App Development/Manual Library/headroom-site/public' \
  "$STAGING"
```

The prior local staging folder is retained under ignored `dist/release-staging-backups/` so this
step never destroys a recoverable artifact. The Headroom website no longer bundles DMGs or deltas. After copying its small public files,
hydrate the staging directory from the verified archive:

```bash
python3 \
  "/Users/kylezantos/App Development/Manual Library/headroom-site/scripts/restore-headroom-binaries.py" \
  "$STAGING"
```

This restores older installers and deltas for Sparkle without growing website deployments.
Never remove historical mappings from `config/headroom-downloads.json`.

## 3. Build, sign, notarize, and generate the feed

Run the release script from this repository:

```bash
HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh
```

The script builds a Developer ID app, notarizes and staples the app and DMG, validates with
Gatekeeper, signs the Sparkle archive, then updates these local outputs:

- `dist/Headroom-<version>-<build>.dmg`
- `dist/headroom.zantos.co/Headroom-<version>-<build>.dmg`
- `dist/headroom.zantos.co/Headroom-<version>-<build>.html`
- `dist/headroom.zantos.co/Headroom.dmg`
- checksums, `appcast.xml`, `latest.json`, and any deltas referenced by the appcast

The DMG styling pass drives Finder for a few seconds, and the result has been known to vary
between runs: 1.5 (41) shipped with Finder's default icon positions. The script now reads the
saved `.DS_Store` back (`Scripts/dmg-layout-check.py`), retries the pass up to three times,
and checks the compressed image again. It fails the release rather than publishing a broken
install window. Hidden items (`.background`, `.VolumeIcon.icns`) are parked outside the window
and `.fseventsd` is removed, so people who show hidden files in Finder still see two icons.

Validate the output before publishing:

```bash
xcrun stapler validate dist/Headroom-<version>-<build>.dmg
spctl -a -vvv -t open --context context:primary-signature \
  dist/Headroom-<version>-<build>.dmg
shasum -a 256 dist/Headroom-<version>-<build>.dmg
```

When the candidate changes Claude executable discovery, provider capability, or account setup,
complete the Track A signed-candidate matrix before publication:

1. Install the Developer ID candidate in an isolated user-local application folder and launch it
   from Finder with two previously configured Claude accounts.
2. Confirm both accounts retain their last eligible usage during an injected/transient discovery
   failure. **Check Again** must recover after discovery returns without repeating login or trust.
3. Move or update the CLI between supported native, Homebrew, or version-manager locations that
   are available in the test environment. Confirm Headroom rediscovers it without relaunching.
4. Make one account login-required or workspace-trust-required through the official CLI. Confirm
   its sibling stays live and only the affected account offers that account-scoped recovery.
5. Install a `claude` launcher under a custom npm global prefix (for example
   `~/.npm-global/bin/claude`) that is deliberately absent from the Finder-launched app's
   inherited `PATH`. Confirm the signed candidate discovers it and shows live Claude usage
   instead of **Install Claude Code** (AE1).
6. Move that launcher from the npm prefix to the native `~/.local/bin/claude` location. Confirm
   **Check Again** rediscovers it and usage recovers without relaunching Headroom, signing in
   again, or re-approving workspace trust (AE4).
7. Run the installed binary's `--probe-claude` once for built-in and once with
   `--claude-config <test-home>`. Record only the allowlisted category output; never record the
   argument, resolved path, identity, panel text, credential, auth payload, or raw error. The
   same allowlisted, path-free recording rule applies to steps 5 and 6: never record the npm
   prefix, the derived launcher path, or npm's raw output.

Record this state as **candidate tested**, not published or Sparkle accepted. If a required login
or trust prompt appears, stop for the tester's explicit approval in the official Claude CLI.

When the candidate changes reset evidence, countdown presentation, continuity migration, or the
widget snapshot schema, complete the Track B signed-candidate matrix before publication:

1. Verify scheduled, absent, elapsed, malformed, implausible, and invalid-zone fixtures in the
   installed macOS popover, macOS widgets, iPhone companion, and iOS widgets.
2. Confirm fresh exact-zero absent/elapsed rows say `Available`; nonzero or ambiguous unresolved
   rows say `Reset info unavailable`; retained, migrated, stale, and unavailable zero rows never
   become `Available` from a clock transition.
3. Check `6d 4h`, `6d`, `13h 37m`, and `37m`, then cross a genuine deadline and a sleep/wake cycle.
   `Resets now` may appear only inside the ±60-second boundary and must not remain stuck.
4. Exercise continuity-v1/widget-v1-v2 migration and future-schema fixtures. A future payload must
   remain untouched and visible as incompatible; equal-generation local data must win over sync.
5. Run the installed binary's `--probe-claude` and record only allowlisted reset categories and
   ages—never provider reset text, time-zone text, paths, identity, credentials, or raw output.

Record Track B as **candidate tested** only after every changed surface passes. Downgrading to a
pre-v3 publisher is not a reset-fidelity rollback: an older iCloud writer can overwrite v3 because
iCloud KVS provides no writer fence.

Check that the first appcast item names the new version and build, retains the current
production item, and references only files present in `dist/headroom.zantos.co/`. Its full
versioned DMG enclosure is the universal fallback for every older installed app; deltas only
optimize matching older builds. The target item must also contain a
`sparkle:releaseNotesLink` ending in `Headroom-<version>-<build>.html`, and that local HTML file
must be non-empty. `Scripts/release-app.sh` validates this after both normal `generate_appcast`
output and the timeout fallback.

## 4. Publish assets through the Headroom website repository

Create a branch in `headroom-site`. The website keeps only metadata, notes and checksums;
signed binaries live in the public artifact-only `kylezantos/headroom-downloads` repository.
The app source remains private. Run from the current Headroom website checkout:

```bash
pnpm publish:headroom /absolute/path/to/headroom/dist/headroom.zantos.co
pnpm check:headroom-storage
pnpm build
```

The publisher verifies the local appcast and latest metadata, refuses to overwrite versioned
assets, uploads new binaries to a GitHub Release, and anonymously downloads them to verify
size and SHA-256 before updating the website manifest and small public files. The existing
`headroom.zantos.co` URLs redirect to the archive; appcast URLs and signatures stay intact.
The stable `Headroom.dmg` redirect follows the version in `latest.json` and is not permanent.

Do not copy DMGs/deltas into `public/`: the website build rejects them. Preserve all historical
manifest mappings and release assets. Use the hydration command above whenever local staging
needs older installers. If publication fails, leave the current website live and fix the failure;
do not bypass verification or overwrite an existing versioned archive asset.

Open a PR to `headroom-site/main`, wait for the Vercel preview check, then merge it. Promote the
Headroom website through its documented production path, never by pushing directly to its
`production` branch:

```bash
pnpm ship
```

## 5. Verify production from the public URL

Confirm the Vercel deployment aliases `headroom.zantos.co`, then check the live files:

```bash
curl --fail --silent https://headroom.zantos.co/latest.json
curl --fail --silent https://headroom.zantos.co/appcast.xml
curl --fail --silent https://headroom.zantos.co/Headroom-<version>-<build>.html
curl --fail --silent --location https://headroom.zantos.co/Headroom.dmg | shasum -a 256
```

The live DMG hash must equal `latest.json`'s `sha256` and `Headroom.dmg.sha256`. For the final
release-note check, confirm the target appcast item links the exact live HTML URL above and that
the response contains the target release heading and body. For the final
download-style smoke test, mount a fresh public download, validate its signature, and run the
diagnostic without launching the menu bar UI:

```bash
hdiutil verify /path/to/Headroom.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/Headroom\ Installer/Headroom.app
/Volumes/Headroom\ Installer/Headroom.app/Contents/MacOS/Headroom --probe-codex
```

## 6. Prove the installed-app update path

The website build enables automatic checks and allows users to opt into automatic downloads
and installation on quit (`SUEnableAutomaticChecks = YES`, `SUAllowsAutomaticUpdates = YES`,
`SUAutomaticallyUpdate = NO`). Automatic installation defaults off; Sparkle's saved user
preference takes precedence over that bundle default. Do not overwrite the saved preference
when packaging or launching. Users who leave it off continue to choose installation in the
native update prompt. Every public release must prove the installed-app update path below.

Run `python3 Tests/ReleaseScripts/sparkle-update-policy-tests.py` alongside the release-note
tests before packaging. It exercises both real Info.plist stamping functions with isolated
fixtures; it does not sign, publish, or install a release.

**Automatic-update acceptance:** In the same isolated environment described below, use an
older signed public build that already supports this opt-in and a newer signed release.
Verify a fresh preference starts off, turn it on, and confirm it persists after reopening
Settings and relaunching. Allow a background check to download and stage the update, then
quit normally and relaunch; verify the installed version/build, signature, and provider smoke.
Repeat with the opt-in off to confirm installation still requires the user's choice, and
with automatic checks off to confirm automatic downloads are suspended. Test “Restart to
Update” on a staged update separately. Never substitute a manual “Check for Updates” download
for proof of the background path. Record this gate as pending until the two suitable signed
builds and an isolated environment exist; preference/delegate tests are not installation proof.

Use a VM/dedicated Mac, or install into `~/Applications` in a dedicated macOS test user, so this
does not replace a working development install. A separate user alone does not isolate the shared
`/Applications` directory.

1. Download an older **public** versioned DMG through its URL in the Headroom website download manifest. Verify its
   Developer ID signature, notarization, version, and build before installing it. A local or
   Apple Development-signed bundle is not a valid starting point.
2. Before launching, inspect exact Headroom process paths. Keep only this public installation
   running; close only verified QA/debug PIDs. Launch Services may list many bundle copies, which
   are not live instances. The WidgetKit extension is expected and is not a second app.
3. Set `INSTALLED_APP` to the isolated installed bundle, then launch it once:

   ```bash
   INSTALLED_APP="$HOME/Applications/Headroom.app" # dedicated user on a shared Mac
   # INSTALLED_APP="/Applications/Headroom.app"    # VM or dedicated Mac
   open "$INSTALLED_APP"
   ```

   Do not overwrite a working development installation. If the user explicitly authorizes the
   primary-account fallback, back up the existing bundle recoverably and record that this is
   weaker than an isolated acceptance pass.
4. Open Headroom Settings and select **Check for Updates…**. Before accepting the update, confirm
   Sparkle's prompt visibly renders the target release heading and body from the versioned notes;
   blank content, notes for another build, or a load error blocks acceptance. Accept the prompt
   only after this check, then let Headroom relaunch. Do not test against a locally built app; it
   lacks the production feed configuration.
   If the menu-bar UI is not exposed after one fresh accessibility query, stop automation and ask
   the tester to make this exact click. Do not keyboard-scan the menu bar or try hidden positions.
5. Confirm the installed app's version and build equal the new release, then repeat the normal
   provider/setup smoke:

   ```bash
   /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
     "$INSTALLED_APP/Contents/Info.plist"
   /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
     "$INSTALLED_APP/Contents/Info.plist"
   "$INSTALLED_APP/Contents/MacOS/Headroom" --probe-codex
   ```

6. Exercise the signed provider recovery matrix without recording provider output or identity:
   - Claude built-in: preserve an existing trusted workspace across the Sparkle update; in a
     fresh test user, prove login-required and workspace-trust-required remain distinct and
     both recover through the official CLI.
   - Claude additional: add a fresh isolated account, close the popover while setup runs, and
     confirm it settles live without switching or modifying the built-in CLI account.
   - Codex permission: deny file access, confirm Headroom offers Privacy & Security guidance
     rather than a login loop, re-grant access, and use **Check now** to recover.
   - Codex login/storage: prove standard browser login and the explicit device-code fallback
     target the same isolated account home and leave an owner-only readable `auth.json`.
     Cancel an incomplete callback and confirm the UI offers standard retry plus device code.
   - Start one Codex login, request another, and confirm the second requires a fresh
     **Continue setup** action only after the first Terminal handoff ends.

   For a Track A Claude capability release, repeat the two-account candidate matrix from step 3
   after the Sparkle relaunch. Include executable path churn and one transient inconclusive
   discovery. Confirm continuity survives, **Check Again** recovers without setup rerun, and
   login/trust divergence stays account-scoped. This successful public-update observation is
   **Sparkle accepted**; publication remains the separately verified asset state from step 5.

   For a Track B reset/schema release, repeat the installed cross-surface matrix above after the
   Sparkle relaunch, including legacy migration and deadline crossing. Keep macOS, macOS widget,
   iPhone, and iOS widget results separate; one passing surface does not stand in for another.

7. Exercise the signed additional-account lifecycle: add, rename, refresh, and remove one
   account while a sibling remains live. Removal must stay visible while work is active, retain
   the row with Retry/Cancel on failure, delete exactly the selected Headroom-owned home on
   success, and leave the built-in and sibling homes unchanged. Confirm the popover scroll cap
   and compact density with three or more accounts.

8. Recheck macOS permission persistence after Sparkle relaunch. Existing Claude workspace trust,
   Codex file access, widget/App Group access, and iCloud snapshot publication must not regress or
   require destructive credential recreation. Record only typed outcomes, permission modes, and
   pass/fail decisions—never emails, tokens, auth contents, callback URLs, or raw provider panels.

Record the starting and ending versions plus the visible release-note result in the release PR.
A rejected signature, missing enclosure, missing/unreadable release notes, or no-update result is
a release blocker: stop before announcing the download.
If the dedicated environment was unavailable before publishing, proceed only after the user
explicitly authorizes that residual. Report the macOS lane as **published; Sparkle acceptance
pending/waived**, never simply “complete.”

For a manual acceptance pass, launch the same isolated `$INSTALLED_APP` used above and confirm the
popover matches the official provider surfaces. Repeat the provider and additional-account checks
on that freshly installed public DMG, not a locally built bundle. For the Codex
window-classification fix, a `prolite` account may correctly show only Weekly plus Spark Weekly. It
must never fabricate a five-hour row.

## Rollback

If the public artifacts are wrong, revert the release-asset commit in `headroom-site/main` and
run `pnpm ship` again. This restores the prior stable DMG, manifest, and appcast together.
Do not delete the notarized versioned DMG from this repository's local `dist/` history while
investigating.
