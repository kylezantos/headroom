# Headroom Privacy Policy

Source for `headroom.zantos.co/privacy` (`app/headroom/privacy/page.tsx` in `headroom-site`).
The 1.5 sync disclosure was published through headroom-site PR #10; the Copilot and feedback disclosures through headroom-site PR #19.

**Effective November 12, 2026**

Headroom shows how much of your AI-subscription usage remains. The Mac and iPhone apps have **no analytics or telemetry**. This policy explains
how they read and sync usage data, and what this website measures.

## What Headroom does with data

- **No collection.** Headroom has no analytics, no telemetry, no crash reporting,
  no advertising, and no third-party SDKs. We never see your usage, your identity,
  or your device.
- **Usage data is read locally, on your Mac.** For each supported tool (Claude, Codex,
  Cursor, Grok, GitHub Copilot, OpenCode, and Antigravity), the Mac app reads usage locally, either by driving the tool's
  official command-line tool or by reading its local sign-in file, then queries that
  tool's provider with your own credentials. Requests go directly from your Mac to the
  provider. They never pass through us.
- GitHub Copilot usage comes from files on your Mac. If you turn Copilot on, Headroom
  scans the session logs the official Copilot command-line tool writes on your Mac, and
  asks that tool, on your Mac, for your monthly allowance. Those logs also hold your
  prompts and the output of the tools Copilot ran. Headroom decodes only the usage records
  in them and keeps no prompt or tool content. Nothing from the logs leaves your Mac except
  the resulting usage figure, which reaches your iPhone only if iPhone sync is on.
- OpenCode usage comes from the OpenCode command-line tool's own usage read. If you turn
  OpenCode on, Headroom runs that official tool on your Mac and reads the usage it prints; the
  tool makes the request to OpenCode with your own sign-in. Headroom reads no OpenCode
  credential and keeps nothing from that output except the usage meters (and whether the
  workspace has a Go plan), which reach your iPhone only if iPhone sync is on. The output also names
  your OpenCode workspace (its ID, name and web address); Headroom neither stores nor shows any
  of them. Like any run of the tool, each check of your default OpenCode setup adds an entry to
  the log OpenCode keeps on your Mac.
- Antigravity usage comes from the Antigravity command-line tool's own answers. If you turn
  Antigravity on, Headroom runs that official tool (`agy`) on your Mac and asks it only for its
  `/usage` and `/credits` answers, which use no model and spend no quota; the tool makes the
  request to Google with your own sign-in. Headroom reads no Antigravity credential, cookie or
  Keychain item and keeps nothing from those answers except the quota meters, their reset times
  and your AI-credits balance, which reach your iPhone only if iPhone sync is on. Headroom does
  not keep what the tool prints to its error output; it only watches it for the sign-in prompt.
  Like any run of the tool, each check adds a log file to the folder Antigravity keeps on your
  Mac, and that log is Antigravity's, not Headroom's. If the tool is signed out, a check makes
  it open a Google sign-in page in your browser; Headroom stops that check and does not check
  again until you ask it to.
- **API spend is optional and off by default.** If you enable it, the reporting
  keys you enter are stored in the macOS Keychain on your Mac and used only to call
  the providers' official cost endpoints directly.
- **iPhone and iPad sync uses your iCloud, not our servers.** When "Sync usage to
  iPhone" is on, Headroom for Mac writes a summary to iCloud key-value storage in your
  own Apple account, and the iPhone and iPad app, its widgets and Siri read it. The
  summary holds account names you chose, plan names, usage, reset times, API spend,
  display choices, check-now requests, a random ID for your Mac and for each iPhone or
  iPad, and one more random ID that lets the app check its saved data belongs to the iCloud
  account signed in now. Provider sign-in credentials and API keys are never part of this
  summary. iCloud key-value data is not end-to-end encrypted.
- **Update checks.** The Mac app checks `headroom.zantos.co` for new versions using
  the standard Sparkle framework. This is an ordinary HTTPS request for a version
  file; no personal information or system profile is sent.

- **Feedback you email us.** "Send Feedback" in the Mac and iPhone apps opens an email in
  your own mail app, addressed to support@zantos.co. Headroom sends nothing itself. You see
  the whole email first and can change or delete any of it, including the optional
  diagnostics: app, operating system and command-line tool versions, and each account's
  status, never your email, account names or sign-in details. When you send it, we receive
  what you wrote and your email address. Reports are kept in Linear, our issue tracker, and
  AI tools may help us sort them. To have a report deleted, email the same address.

## Your choices

- **Everything is a switch.** Widget sharing and iPhone sync are opt-in switches in
  Headroom's settings. Turning them off stops the corresponding data flow immediately.
  Turning off "Sync usage to iPhone" also removes the synced account data from iCloud;
  only a note that sync is off, with your Mac's random ID, and the random iCloud ID stay. Data left in an iCloud
  account you signed out of stays there until you sign back in to it and turn sync off.

## This website

- **The website counts visits; the app does not.** headroom.zantos.co uses PostHog and
  Vercel Analytics to see which pages are visited, what gets clicked, and how many people
  download Headroom, including the rough country a download comes from. This covers the
  website only. The app never reports to either service.

## Contact

Questions about this policy: **kyle@zantos.co**

We will update this page if the app's behavior ever changes, and the effective date
above will change with it.
