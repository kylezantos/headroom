# Headroom Privacy Policy

**Effective July 8, 2026**

Headroom shows how much of your AI-subscription usage remains. It is built so that
your data stays yours: **Headroom collects nothing, tracks nothing, and has no
servers of its own.**

## What Headroom does with data

- **No collection.** Headroom has no analytics, no telemetry, no crash reporting,
  no advertising, and no third-party SDKs. We never see your usage, your identity,
  or your device.
- **Usage data is read locally, on your Mac.** The Mac app reads Claude usage by
  driving the official `claude` command-line tool on your machine, and Codex usage
  by reading the Codex CLI's local sign-in file and querying the provider with your
  own credentials. Requests go directly from your Mac to Anthropic or OpenAI —
  never through us.
- **API spend is optional and off by default.** If you enable it, the reporting
  keys you enter are stored in the macOS Keychain on your Mac and used only to call
  the providers' official cost endpoints directly.
- **iPhone sync uses your iCloud, not our servers.** The iPhone app and widgets
  display a summary synced through iCloud Key-Value Store on your own Apple
  account: provider names, percentages remaining, reset times, and freshness
  timestamps. Credentials, API keys, and raw account data never leave your Mac and
  are never part of the synced payload.
- **Update checks.** The Mac app checks `headroom.zantos.co` for new versions using
  the standard Sparkle framework. This is an ordinary HTTPS request for a version
  file; no personal information or system profile is sent.

## Your choices

Widget sharing and iPhone sync are opt-in switches in Headroom's settings. Turning
them off stops the corresponding data flow immediately. Deleting the app removes
everything it stored on that device.

## Contact

Questions about this policy: **kylezantos@gmail.com**

We will update this page if the app's behavior ever changes, and the effective date
above will change with it.
