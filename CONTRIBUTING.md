# Contributing to Headroom

Thanks for helping. Headroom is a macOS menu bar app (with an iPhone and iPad companion) that
shows how much of your AI subscriptions you have left. A growing number of people rely on its
numbers, so reliability and honesty come before new features.

## Before you start

- **Outside code contributions:** open a GitHub contribution proposal first and wait for the
  maintainer to add the **`accepted`** label before starting implementation or opening a code PR.
  This applies to bug fixes as well as new features, providers and refactors. Describe the problem,
  your proposed approach and how you would verify it. Keep the PR within the accepted scope.
- **Tiny documentation fixes:** typos, broken links and small wording corrections can come
  directly as a PR. Discuss larger documentation changes first.
- **Bug reports and feature requests:** email **support@zantos.co**. Customer feedback stays in
  the maintainer's private tracker; a GitHub issue is needed only when proposing an outside
  contribution. Don't copy private customer details into a public proposal.
- **Security problems:** see [SECURITY.md](SECURITY.md). Don't file them as public issues.

An `accepted` issue approves the direction and scope, not the final code. The PR still needs
review and passing checks. Code PRs without an accepted issue may be closed without review.
The maintainer's own fixes and releases can use internal tracking without a public issue.

## The one rule

Headroom only ever reads what a provider's **official client** shows. It never signs in on its
own, never reuses a CLI's stored tokens, and never calls a provider's private endpoints.

For Claude, that means usage comes only from running the official `claude` CLI's `/usage` panel.
Anthropic's policy forbids third-party use of Claude subscription sign-ins and blocks it on the
server, so pull requests that read the `Claude Code-credentials` Keychain item, call
`api.anthropic.com/api/oauth/usage`, add a "Sign in with Claude" flow or imitate the CLI's
User-Agent will be closed. The same boundary applies to every provider; each one's details are in
[AGENTS.md](AGENTS.md).

## Requirements

- Xcode 27.0 or later (Swift 6.4), on an Apple silicon Mac.
- `xcodegen` for app bundle builds: `brew install xcodegen`.
- To see real numbers, the CLI for the provider you're working on, installed and signed in. You
  don't need any of them to build, test or run the demos.

## Build, run and test

```bash
swift build                      # the Mac app and its core library
swift test                       # unit tests: all mocked, no CLI, network or Keychain
swift run Headroom --demo        # the app with fixture data; see AGENTS.md for the scenarios

# Mac app tests. You don't need an Apple developer account: signing is turned off.
./Scripts/build-app.sh --deps-only
xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' \
  -derivedDataPath ./.xcode-derived CODE_SIGNING_ALLOWED=NO test

# iPhone app and widgets, if you touched Sources/HeadroomIOS*, Sources/HeadroomSharedUI or
# the Core folders the phone shares (Models, Notifications, Settings, Sync, Widgets).
xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
```

The project is generated from `project.yml`. After editing it, run `xcodegen generate` and commit
both files.

Building a signed `Headroom.app` (`./Scripts/build-app.sh`) and anything involving iCloud sync, App
Groups or notifications needs your own Apple team and bundle IDs. Change them locally, and leave
`project.yml`'s team and `com.kylezantos.*` identifiers out of your pull request.

## How the code works

[AGENTS.md](AGENTS.md) is the guide for both people and coding agents: architecture, data flow,
commands, and a long list of gotchas, each learned the hard way. Read the sections that cover what
you're changing. Durable write-ups of past problems are in [`docs/solutions/`](docs/solutions/).
UI work starts from [DESIGN.md](DESIGN.md); shared vocabulary is in [CONCEPTS.md](CONCEPTS.md).

A few rules that come up in almost every change:

- **Every provider, every account.** A change applies to Claude, Codex, Grok, Cursor, Copilot
  and OpenCode, and to every account of each. If a provider's CLI genuinely can't support it,
  say so in the pull request and explain why.
- **Swift 6 strict concurrency stays clean.**
- **Everything is testable without the real world.** New behavior goes behind an injectable seam
  and gets unit tests with fixtures; tests never run a real CLI, hit the network or touch the
  Keychain.
- **Failures are typed** (`FailureReason`), never error strings that could leak tokens, emails or
  account details.
- **UI changes:** include screenshots in light and dark appearance. `swift run Headroom
  --render-popover <dir>` renders the popover offscreen; `--render-widgets <dir>` renders every
  widget style and fails if anything overflows.

## Pull requests

- For an outside code contribution, link the GitHub issue labeled `accepted` in the PR template.
- Keep each pull request to one change. Title it in the conventional-commit style the history
  uses, such as `fix(codex): read the weekly window on the prolite plan`.
- Fill in the template: what happened, the fix, and what you ran.
- Never commit API keys, account emails, CLI auth files or real `/usage` captures. Redact fixtures.
- On your first pull request, confirm in its description that you have read and agree to the
  [Contributor License Agreement](CLA.md). The maintainer checks this manually. It lets the
  maintainer keep shipping Headroom on the App Store, which the GPL alone doesn't allow.

## License and name

Headroom's code is licensed under the [GNU General Public License v3.0](LICENSE). The Headroom
name and app icon are not covered by that license: if you publish a fork, give it a different name
and icon.
