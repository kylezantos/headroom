---
name: release-website-dmg
description: "Ship or prepare a Headroom macOS website release: bump the version, build a Developer ID-signed and notarized DMG, publish the Sparkle appcast and download assets to headroom.zantos.co through headroom-site, and verify fresh downloads and updates from installed older releases. Use whenever the user asks to release, publish, ship, update, or make a new Headroom DMG available."
---

# Headroom Website DMG Release

Follow [docs/release/website-dmg-release.md](../../../docs/release/website-dmg-release.md) as
the authoritative procedure. Use `Scripts/release-app.sh` for the signed/notarized artifact;
do not recreate its signing, appcast, or packaging logic.

For a coordinated request that also includes TestFlight or App Store work, first read
[docs/release/release-operations.md](../../../docs/release/release-operations.md), then follow
each platform runbook as a separate release lane. Report their states separately.

## Scope and safety

- Treat `https://headroom.zantos.co` as the public site. Do not substitute a similarly named
  domain.
- The source repo is Headroom. Website metadata and Vercel deployment belong to
  `/Users/kylezantos/App Development/Manual Library/headroom-site`; signed binaries live in
  the public artifact-only `kylezantos/headroom-downloads` GitHub Releases archive.
- Never release from an unmerged Headroom branch, deploy `dist/` as a separate Vercel project,
  force-push, or delete versioned DMGs, checksum files, or Sparkle deltas.
- Perform external publishing only when the user explicitly asks to ship or publish. For a
  request to prepare/review the release process, stop before changing the Headroom website repo or
  production site.
- Preflight every required external environment before publishing: the runbook's isolated Sparkle
  installation, physical TestFlight device, App Store Connect access, and macOS 15 hardware when
  that compatibility gate is in scope. Resolve or explicitly record unavailable gates before
  shipping.
- Distinguish bundle copies from live processes. Before installed-app QA, verify exact process
  paths and keep only the intended public app running. Never use `killall` or broad process matches.
- Treat passwords, passkeys, two-factor codes, device unlocks, privacy prompts, and approval to
  use a visible logged-in browser as explicit user handoffs.
- If a menu-bar or transient system UI is not accessible after one fresh Computer Use state query,
  stop automation and request the exact user click. Never brute-force menu-bar coordinates,
  keyboard offsets, or hidden controls.
- Do not use iPhone Mirroring as a TestFlight default or configure it during a release. Use it only
  when already configured and explicitly chosen by the user.

## Required release sequence

1. Identify the target marketing version and monotonically increasing build. Update the version
   fields together in `project.yml`, add the required non-empty
   `docs/release/sparkle/Headroom-<version>-<build>.html`, run `xcodegen generate` and
   `swift test` plus `bash Tests/ReleaseScripts/sparkle-release-notes-tests.sh` and
   `python3 Tests/ReleaseScripts/dmg-layout-check-tests.py`, and merge the
   release bump and notes to `main` before generating public artifacts.
2. Seed `dist/headroom.zantos.co` from the current `headroom-site/public` using the runbook's
   non-destructive staging step, then hydrate archived binaries with the Headroom website
   `scripts/restore-headroom-binaries.py` helper. This retains the current appcast history so Sparkle can produce
   deltas; the latest full versioned DMG remains the fallback for all older installations.
3. Run `HEADROOM_NOTARY_PROFILE=headroom-notary ./Scripts/release-app.sh`. Do not echo,
   inspect, or commit credentials, signing keys, auth files, or generated secret values.
4. Validate notarization, Gatekeeper, checksums, `latest.json`, every appcast enclosure, and the
   target build's versioned release-note link and staged HTML before copying release outputs.
   Confirm the app has `SUFeedURL`, `SUPublicEDKey`, and the new `CFBundleVersion` stamped.
5. Create a normal branch and PR in `headroom-site`; run `pnpm publish:headroom <staging-directory>`.
   This publishes and verifies binaries in GitHub Releases, updates the download redirect
   manifest, and copies only small website metadata. Never copy DMGs or deltas into `public/`.
   Preserve every existing versioned archive asset and mapping. Build, preview, merge,
   then use the Headroom website's documented `pnpm ship` path.
6. Validate the live manifest, appcast, stable-DMG checksum, mounted DMG signature, and public
   diagnostic. Then run the runbook's installed-app update test from an older public release in
   its isolated installation. Confirm the update prompt visibly renders the target notes before
   accepting the update. The release is not complete until Sparkle upgrades it to the new
   version/build.

## Status discipline

“Published,” “uploaded,” “processed,” “assigned,” and “accepted” are different states. Never call
an App Store Connect upload available in TestFlight until processing and group assignment are
verified. Never call a public DMG release fully accepted until the installed Sparkle update passes,
unless the user explicitly waives that gate and the handoff records the residual.

## Handoff

Report the target version/build, the public download URL, live checksum match, appcast result,
and installed-app update result. If any verification fails, do not call the release complete;
state the failed gate and keep the prior public assets intact.
