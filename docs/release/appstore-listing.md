# App Store Connect — Headroom (iOS) listing copy

Paste-ready fields for the `com.kylezantos.headroom.ios` 1.0 submission.

## Name (30 chars max)

```
Headroom
```

## Subtitle (30 chars max)

```
Your AI usage, on your phone
```

## Category

Primary: **Developer Tools** · Secondary: **Utilities**

## Description (4000 chars max)

```
Headroom for iPhone is the pocket companion to Headroom for Mac — the menu bar
app that shows how much of your Claude and Codex subscription usage remains.

Your Mac reads the numbers. Your iPhone shows them. Glance at your Home Screen
and know whether you have room for one more session before the weekly window
resets.

WHAT YOU SEE
• Claude and Codex side by side, as equals — session and weekly windows with
  percentage remaining
• Reset times, exactly as the providers report them
• Plan renewal dates, plus optional API spend totals if you track them on
  the Mac
• Freshness at a glance: every screen says when the numbers last updated

WIDGETS THAT RESPECT A GLANCE
Small, medium, and large Home Screen widgets in the same design as the app —
readable percentages, clean bars, no decoration competing with the number you
came for.

PRIVATE BY ARCHITECTURE
Your Mac publishes a usage summary through your own iCloud account, and your
iPhone reads it. That summary is percentages, reset labels, and timestamps —
never credentials, API keys, or account details. Headroom has no servers, no
accounts, no analytics, and nothing to sell. The full policy is one page:
headroom.zantos.co/privacy

REQUIRES THE MAC APP
Headroom for iPhone is a companion display. It needs Headroom for Mac
(free download at headroom.zantos.co) running on a Mac signed into the same
iCloud account, with "Sync snapshot to iPhone" switched on. Without it, the
app will wait politely — but it will wait.

Built for people who live in Claude Code and Codex all day and just want to
know: how much headroom is left?
```

## Keywords (100 chars max, comma-separated)

```
claude,codex,chatgpt,anthropic,openai,usage,quota,limit,tracker,widget,ai,cli,developer
```

## URLs

- Support URL: `https://headroom.zantos.co`
- Marketing URL: `https://headroom.zantos.co`
- Privacy Policy URL: `https://headroom.zantos.co/privacy`

## App Privacy (questionnaire)

**Data Not Collected.** The app collects no data. (Usage summaries sync
device-to-device through the user's own iCloud Key-Value Store; the developer
never receives any data. No analytics or third-party SDKs.)

## Age Rating

All questionnaire answers: **None** → rating 4+.

## Export Compliance

Already declared in the binary: `ITSAppUsesNonExemptEncryption = NO`
(standard HTTPS only). No prompt should appear at submission.

## Screenshots

6.9" iPhone (1320 × 2868), from `~/Desktop/headroom-shots/appstore-6.9/`:

1. `ios-usage-dark-6.9.png` — dark mode, both providers live
2. `ios-usage-light-6.9.png` — light mode

(Same build's demo fixture; values are representative. Add widget shots later
if desired — not required for first submission.)

## Notes for App Review (paste into "App Review Information → Notes")

```
Headroom for iPhone is a companion display for Headroom for Mac, a macOS menu
bar app distributed at https://headroom.zantos.co. The Mac app reads the
user's Claude/Codex subscription usage locally and publishes a redaction-safe
summary (percentages, reset times, timestamps — never credentials) through
the user's own iCloud Key-Value Store. This iOS app and its widgets are
read-only views of that summary.

WHAT YOU WILL SEE IN REVIEW
Without a Mac running the companion, the app launches to a clear "Waiting for
your Mac" state that explains the setup steps. This is the intended
first-run experience for a companion app; there is no login, no account, and
no server — data arrives only from the reviewer's/user's own Mac via their
own iCloud account.

The App Store screenshots were captured using the app's built-in demo
fixture (fixed sample data rendered by the real UI) so they accurately
represent a connected state.

There is no hidden functionality; no dynamic code; no data collection of any
kind. Contact kylezantos@gmail.com for anything at all — happy to provide a
demo video of the Mac-to-iPhone sync working end to end if useful.
```
