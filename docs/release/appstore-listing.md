# App Store Connect — Headroom (iOS) listing copy

Paste-ready fields for the `com.kylezantos.headroom.ios` 1.0 submission.

## Submission log

- 2026-07-15: App Review rejected iOS 1.0 build 14 under Guideline 2.1(a)
  because reviewers could not access connected functionality without Kyle's Mac/iCloud
  setup. Submission ID: `3472c833-11a3-4815-82d0-816b291dab60`.
- 2026-07-18: Uploaded universal iPhone/iPad build 23 with the production demonstration
  mode and the latest companion/widget fixes. Select build 23 only after processing and
  the clean TestFlight acceptance gate in `ios-app-review-testflight.md` pass.
- 2026-07-20: Prepared universal build 24 as the next candidate. Source/archive preflight,
  signature validation, the iPhone UI suite, and Apple Distribution-signed local IPA export pass;
  it has not been uploaded or assigned to a TestFlight group.

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
Headroom for iPhone and iPad is the pocket companion to Headroom for Mac — the menu bar
app that shows how much of your Claude and Codex subscription usage remains.

Your Mac reads the numbers. Your iPhone or iPad shows them. Glance at your Home Screen
and know whether you have room for one more session before the weekly window
resets.

WHAT YOU SEE
• Claude and Codex side by side, as equals — session and weekly windows with
  percentage remaining
• Reset times, exactly as the providers report them
• Model-specific limits, plus optional API spend totals if you track them on the Mac
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

CONNECTED USE REQUIRES THE MAC APP
Headroom is a companion display. Live data needs Headroom for Mac
(free download at headroom.zantos.co) running on a Mac signed into the same
iCloud account, with "Sync snapshot to iPhone" switched on. A clearly labeled
built-in demo lets anyone explore the complete app and widgets before connecting.

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

Send Feedback (Nov 2026) keeps this answer: the row opens a `mailto:` in the user's own
mail app and the app transmits nothing. Whatever the user chooses to email arrives
through their mail provider, not the app. Kyle confirms against Apple's App Privacy
definitions when he next edits the answers.

## Age Rating

All questionnaire answers: **None** → rating 4+.

## Export Compliance

Already declared in the binary: `ITSAppUsesNonExemptEncryption = NO`
(standard HTTPS only). No prompt should appear at submission.

## Screenshots

**Uploaded to the 1.5.1 draft on October 13, 2026.** All twelve Print screenshots finished
processing and their order was verified through App Store Connect. The live 1.5 listing still
shows Graphite (`design/appstore/shots.json`) until the new version is released. Re-run captures
for future releases if any screen shown here changes.

The **Print** set (chosen 2026-10-09). Source:
`design/appstore/print/` (layout, captures, renders; its README covers refreshing captures).
Render with `Scripts/export-appstore-print.sh`, which writes `dist/appstore/print/` and verifies
size, sRGB and no alpha. Upload in this order.

6.9" iPhone (1320 × 2868), `dist/appstore/print/iphone69/`:

1. `iphone69-01-how-much-is-left.png` — "How much is left?" Halftone vessel at 38%, Usage below
2. `iphone69-02-every-account.png` — "Every account, on your iPhone." Multi-account Usage
3. `iphone69-03-lock-screen.png` — "And your Lock Screen." Inline, circle and rectangle widgets
4. `iphone69-04-widget-style.png` — "Pick a widget style." Tightest First solid, other styles ghosted
5. `iphone69-05-pull-to-check-now.png` — "Pull to check now." Real check-now receipt
6. `iphone69-06-know-your-limits.png` — "Know your limits." Requires Headroom for Mac

13" iPad (2064 × 2752), `dist/appstore/print/ipad13/`: the same six frames in the same order
(`ipad13-01-…` to `ipad13-06-…`), using the native two-column iPad captures, the iPad widget wall,
an iPad-proportioned Lock Screen and "on your iPad" / "Headroom for iPad" copy.

All captures use the labeled representative demo data (`--demo` fixtures). No caption mentions a
price; provider marks appear only inside real UI.

## Notes for App Review (paste into "App Review Information → Notes")

```
Headroom has no login or Headroom account. Please leave "Sign-in required" off.

To review every display feature without a Mac or provider account:
1. Launch Headroom on iPhone or iPad.
2. Tap "Explore Demo" on the Waiting for Mac screen.
3. Review Claude, Codex, Weekly (Fable), API Spend, reset times, and Settings.
4. Add a small, medium, or large Headroom widget. It uses the same clearly
   labeled demo data while Demo Mode is active.
5. In Settings, tap "Exit Demo" to return to the real companion state.

Demo Mode uses bundled representative data, makes no provider or Headroom
server request, and never overwrites a real synced snapshot. Live connected
data is a redaction-safe summary published by Headroom for Mac through the
user's own iCloud Key-Value Store. The iOS app and widgets are read-only.

There is no hidden functionality, dynamic code, analytics, or data collection.
Contact kylezantos@gmail.com if any assistance is needed.
```
