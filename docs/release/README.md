# Release documentation

This directory keeps the public privacy policy and canonical Sparkle release notes. Build,
packaging and release-validation scripts remain in `Scripts/` and `Tests/ReleaseScripts/`.
Normal contributor build instructions are in [CONTRIBUTING.md](../../CONTRIBUTING.md).

The maintainer is responsible for official releases. Signing and notarization setup,
TestFlight/App Store submissions, website deployment, acceptance checklists and release
records live in the private `kylezantos/headroom-site` repository under `docs/release/`.
Its `release-website-dmg` skill is the entry point for official website DMG releases.

App Store artwork exports use locally installed licensed fonts, as described in the
[artwork README](../../design/appstore/print/README.md). Those fonts are not required to
build or test the app.
