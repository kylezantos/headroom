# Security policy

Headroom reads usage from official AI-provider CLIs and stores API keys in the macOS Keychain, so
reports about credential handling, data leaving the device, or the iCloud sync payload matter most.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's **Report a vulnerability** button on the
repository's Security tab, or email **support@zantos.co** with "Security" in the subject.

Include what you found, how to reproduce it, and which Headroom version (Settings › About) and
macOS or iOS version you used. You'll get a reply within a week. Fixes ship in the next release,
and you'll be credited in its notes unless you'd rather not be.

## Supported versions

Only the latest release, from https://headroom.zantos.co or the App Store, receives fixes.

## Automated checks

GitHub secret scanning and push protection are enabled, alongside Dependabot vulnerability
alerts and security-update pull requests. CodeQL scans Python, JavaScript/TypeScript and
GitHub Actions workflows using GitHub's default setup, including local-input threat modeling.

**Swift code is not covered by CodeQL.** Headroom requires Xcode 27 / Swift 6.4, which
[CodeQL's traced analysis does not currently support](https://github.com/github/codeql-cli-binaries/blob/main/CHANGELOG.md#release-2273-2026-10-20).
The ordinary Swift tests and Mac/iOS builds remain required CI checks; passing them does not
replace a security review. Revisit Swift scanning when upstream toolchain support is available.
