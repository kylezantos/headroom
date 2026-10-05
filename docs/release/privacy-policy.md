# Headroom Privacy Policy

Source for `headroom.zantos.co/privacy` (`app/headroom/privacy/page.tsx` in `headroom-site`).
Keep the two in step; the 1.5 change is prepared for Kyle as a diff, not applied to the site.
The bracketed reminders item ships only if the CloudKit reminders spike (U15) passes and U16
lands; delete it otherwise. Set the effective date to the day 1.5 ships.

**Effective [1.5 release date]**

Headroom shows how much of your AI-subscription usage remains. It is built so that
your data stays yours: **Headroom collects nothing, tracks nothing, and has no
servers of its own.**

## What Headroom does with data

- **No collection.** Headroom has no analytics, no telemetry, no crash reporting,
  no advertising, and no third-party SDKs. We never see your usage, your identity,
  or your device.
- **Usage data is read locally, on your Mac.** For each supported tool (Claude, Codex,
  Cursor, and Grok), the Mac app reads usage locally, either by driving the tool's
  official command-line tool or by reading its local sign-in file, then queries that
  tool's provider with your own credentials. Requests go directly from your Mac to the
  provider. They never pass through us.
- **API spend is optional and off by default.** If you enable it, the reporting
  keys you enter are stored in the macOS Keychain on your Mac and used only to call
  the providers' official cost endpoints directly.
- **iPhone and iPad sync uses your iCloud, not our servers.** When "Sync usage to
  iPhone" is on, Headroom for Mac writes a summary to iCloud key-value storage in your
  own Apple account, and the iPhone and iPad app, its widgets and Siri read it. The
  summary holds account names you chose, plan names, usage, reset times, API spend,
  display choices, check-now requests, a random ID for your Mac and for each iPhone or
  iPad, and one more random ID that lets the app check its saved data belongs to the iCloud
  account signed in now. Sign-ins, credentials, emails, and API keys never leave your Mac and are
  never part of it. iCloud key-value data is not end-to-end encrypted.
- [**Reminders on your iPhone use your private iCloud database.** If you turn on "Also
  send to iPhone and iPad" on your Mac, reminder text is stored in your own private
  iCloud database so it can arrive as a notification. Depending on your notification
  preview setting, it can show account names on your Lock Screen.]
- **Update checks.** The Mac app checks `headroom.zantos.co` for new versions using
  the standard Sparkle framework. This is an ordinary HTTPS request for a version
  file; no personal information or system profile is sent.

## Your choices

- **Everything is a switch.** Widget sharing and iPhone sync are opt-in switches in
  Headroom's settings. Turning them off stops the corresponding data flow immediately.
  Turning off "Sync usage to iPhone" also removes the synced account data from iCloud;
  only a note that sync is off, with your Mac's random ID, and the random iCloud ID stay. Data left in an iCloud
  account you signed out of stays there until you sign back in to it and turn sync off.
  Deleting the app removes everything it stored on that device.

## This website

- **The website counts visits; the app does not.** headroom.zantos.co uses PostHog and
  Vercel Analytics to see which pages are visited, what gets clicked, and how many people
  download Headroom, including the rough country a download comes from. This covers the
  website only. The app never reports to either service.

## Contact

Questions about this policy: **kylezantos@gmail.com**

We will update this page if the app's behavior ever changes, and the effective date
above will change with it.
