# App Store presentation: Headroom iPhone/iPad companion

Research for the `design/ios-parity-options.html` App Store area (A1–A7). Written 2026-10-03.
Apple doc quotes were fetched on 2026-10-03. Anything not checked against a source is marked
**unverified**. Code claims cite `file:line`.

---

## 0. Short version

1. **Recommended direction: A "Graphite", dark-first frames with captions plus a waterline.**
   Each frame is a real app capture on the Vessel icon's graphite gradient, with a short
   sentence-case caption and one thin mint "waterline" running across every frame at the same
   height. The first three frames, which are all a searcher sees, are: the app with four
   providers, widgets on a Home Screen, and the Mac-to-iPhone handoff. Section 4 has the reasons
   and three real alternatives (panoramic, Home Screen scenes, generative/lifestyle).
2. **Turn off Mac availability** for the iOS app (App Store Connect › Pricing and Availability ›
   iPhone and iPad Apps on Apple Silicon Mac). Today the Mac App Store offers an unverified iPad
   mirror that shows its weakest screenshot, on the very computer that is supposed to be the
   data source. The product already pushes the iPhone widget off the Mac
   (`.disfavoredLocations([.iPhoneWidgetsOnMac])`, `Sources/HeadroomIOSWidgets/HeadroomIOSWidgets.swift:25`).
3. **The name needs a decision.** Four other App Store apps in the same niche already use
   "Headroom" ("Headroom - AI Usage", "Headroom ~ Know Your AI Limits", "AgentHeadroom: AI Usage
   Limits", and "Headroom: Weekly Usage" on the Mac App Store). Plain "Headroom" was the planned
   name (`docs/release/appstore-listing.md:17-20`) but the live name is "Headroom Mobile", so it
   was probably unavailable in July (**unverified**; Kyle would know). My recommendation is
   **"Headroom: AI Usage Companion"** (28 chars).
4. **Listing copy is stale and has a formatting bug.** The live description covers Claude and
   Codex only, doesn't mention Explore Demo, and has hard line breaks in the middle of sentences
   (pasted from the 80-column block in the repo doc). A full rewrite is in §5. Several of its
   claims (multi-account, meter styles, red critical numerals, iPad layout) only become true once
   the redesign ships. §5.6 lists every one.
5. **Pipeline:** headless `simctl` captures with new `--demo-variant` / `--demo-screen` launch
   arguments, an iOS-metric "widget wall" screen for the Home Screen shots, and an HTML/CSS
   compositor rendered with `dev-browser --headless` to exact pixel sizes. Then convert to sRGB
   and strip the alpha channel. Only one size per device is needed: 1320×2868 for iPhone and
   2064×2752 for iPad.

---

## 1. Today: what the public listing actually shows

Sources: iTunes lookup API for id 6787519784, the live page
`https://apps.apple.com/us/app/headroom-mobile/id6787519784` (fetched 2026-10-03), and
`.context/ios-audit/appstore/`.

| Field | Live value | Note |
|---|---|---|
| Name | Headroom Mobile | Repo doc says `Headroom` (`docs/release/appstore-listing.md:17-20`), so the doc has drifted |
| Subtitle | Your AI usage, on your phone | Says "phone", but the same page serves iPad and Mac |
| Category | Developer Tools / Utilities | Free, iOS 26.0+, version 1.0 (2026-07-26), 0 ratings |
| Platform line | "Designed for iPad. Not verified for macOS." | Compatibility: "Mac Requires macOS 26.0 or later and a Mac with Apple M1 chip or later." |
| iPhone shots | 2 plain simulator captures (dark, light) | The old July design, Claude and Codex only |
| iPad shots | 1 light capture | 75% empty, stale "Prolite" chip, status-bar date "Wed Jul 22", and a stray arc in the bottom-right corner |
| Description | Claude and Codex only; "Without it, the app will wait politely — but it will wait." | No Explore Demo mention. It also differs from the repo doc, which does mention the demo |

**Bugs worth fixing whatever direction we pick:**

- **Hard line breaks in the description.** The live text contains `the menu bar\napp that shows`,
  `Glance at your Home Screen\nand know`, and so on. The App Store keeps line breaks, so the
  description most likely renders ragged on a phone (**likely; check on a device**). Paste the
  new copy with one line per paragraph.
- **Bottom-right arc on the iPad captures.** It appears in both the published shot and today's
  render (`.context/ios-parity/renders/ipad-current-dark.png`). It looks like the iPadOS 26
  window resize handle (**unverified**). Capture with the iPad simulator in Full Screen Apps
  multitasking mode, or check the corner before upload.
- **Status bar on the iPad shows a charging bolt and the real date.** `simctl status_bar
  override --time` accepts an ISO date and then also sets the date on iPad. Use
  `--time 2026-01-13T09:41:00 --batteryState discharging --batteryLevel 100`.
- "Prolite" is fixed in the current build: the iPad render now says "Pro Lite". The `full` demo
  fixture still stores `planLabel: "Prolite"` (`Sources/HeadroomCore/Widgets/DemoScreenshotData.swift:69`)
  and relies on the presentation layer to format it.

**The niche is crowded.** The "You might also like" shelf on Headroom's own page lists eight AI
usage trackers: Charge, Codexex, Zodex, QuotaKit, LibarAI, Codex Meter (×2), Model Usage and
AI Session Meter. A search for "headroom" returns four lookalike names (§5.1). Some of those
competitors ask you to sign in to the provider on the phone (for example Codex Meter: "Sign in
with Codex to retrieve live 5-hour and weekly usage windows"). Headroom never does, and that is
a true, distinctive claim worth a frame (§4).

---

## 2. Hard requirements (A1, A4)

### 2.1 Screenshot sizes and format

Source: Screenshot specifications,
https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications ·
Upload guide, https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/

| Slot | Accepted portrait sizes | Required? |
|---|---|---|
| iPhone 6.9″ | 1260×2736, 1290×2796, **1320×2868** | The primary iPhone slot. 6.5″ is "Required if app runs on iPhone and screenshots for 6.9" display aren't provided." |
| iPhone 6.5″ / 6.3″ / 6.1″ / 5.5″ … | 1284×2778 / 1206×2622 / 1179×2556 … | Optional. "If screenshots with the accepted sizes aren't provided, scaled screenshots … are used." |
| iPad 13″ | **2064×2752**, 2048×2732 (landscape 2752×2064, 2732×2048) | "Required if app runs on iPad". Headroom runs natively on iPad (`TARGETED_DEVICE_FAMILY: "1,2"`, `project.yml:126`). |
| iPad 12.9″ / 11″ | … | Scaled from 13″ when not provided |

- **Count:** 1–10 per device size, per locale.
- **Format:** `.jpeg`, `.jpg`, `.png`. Verbatim: *"Images can't include alpha channels or
  transparencies."* Simulator captures are sRGB with alpha. The widget harness renders are
  **Display P3** with alpha (checked with `sips` on `.context/ios-audit/widget-renders/*.png`).
  Apple's spec doesn't mention color space. Normalize everything to sRGB so the saturated
  severity greens and oranges don't shift between the composite and the store.
- **Scaling:** *"If your app's user interface is the same across multiple device sizes … provide
  only the highest resolution screenshots required. They automatically scale down."* So we need
  one iPhone set at 1320×2868 and one iPad set at 2064×2752.
- **Changing screenshots requires a new version:** *"Once your app is submitted for review and
  approved, you must create a new version to update the screenshots."* Promotional text is the
  exception and can change at any time (§5.3).
- **Search results:** *"the first one to three images will appear in search results when no app
  preview is available"* (https://developer.apple.com/app-store/product-page/). Frames 1–3 have
  to work as a triptych at thumbnail size. A practical rule: the caption's cap height should be at
  least 4% of the frame width, so a headline of about 100 px or more on a 1320 px frame
  (rule of thumb, **unverified**).
- Apple also suggests: *"If your app supports Dark Mode, consider including at least one
  screenshot that showcases what the experience looks like."*

### 2.2 App Preview video

Source: https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications

- Up to **3** per size and locale. Length **15–30 s**. Up to 500 MB. Poster frame defaults to 5 s.
- iPhone 6.9″/6.5″/6.3″: **886×1920** portrait (1920×886 landscape). iPad 13″: **1200×1600**
  portrait (1600×1200 landscape).
- H.264 progressive at 10–12 Mbps, High Profile up to Level 4.0, ≤30 fps, `.mov/.m4v/.mp4`; or
  ProRes 422 HQ (`.mov`). Stereo audio: 256 kbps AAC at 44.1/48 kHz. A silent track still has to
  be present (common practice; **unverified** whether Apple rejects a file with no audio track).
- Guideline 2.3.4: *"previews may only use video screen captures of the app itself … You can add
  narration and video or textual overlays."* That rules out Mac footage and any generated
  imagery in a preview.
- Previews autoplay muted, so the first seconds have to carry it.
- **Recommendation: skip the preview this round.** The phone app is a calm, read-only glance
  surface with very little motion to show, and the store's autoplay would replace frame 1 in
  search results. Revisit if the phone gains something worth watching. Any future preview must
  be a screen capture with no pulsing or looping attention motion.

### 2.3 Guideline 2.3: what's allowed and what gets rejected

Source: https://developer.apple.com/app-store/review/guidelines/ (2.3 Accurate Metadata)

**Allowed (quoted from the guidelines):**
- 2.3.3: *"Screenshots should show the app in use, and not merely the title art, login page, or
  splash screen. They may also include text and image overlays …"* Captions, backgrounds and
  device frames are fine.
- 2.3.4: text overlays on previews are fine.

**What gets rejected (App Review's 2.3.3 rejection text, as quoted in
https://developer.apple.com/forums/thread/765166):**
- *"Marketing or promotional materials that do not reflect the UI of the app are not appropriate
  for screenshots."*
- *"The majority of the screenshots should highlight the app's main features and functionality."*
- *"Make sure that the screenshots show the app in use on the correct device, unless they are
  included to demonstrate that the app can be used on multiple Apple platforms."*
- *"Your … 13-inch iPad screenshots show an iPhone device frame … Upload new screenshots that
  accurately reflect the app in use on iPad."* The iPad set must show the real iPad layout, never
  an iPhone frame or a stretched iPhone capture.

**What that means for Headroom:**
- **Mac imagery.** One frame showing the Mac menu bar or popover next to the iPhone is defensible
  under the multi-platform exception. It is also honest, because the iPhone app really does
  depend on the Mac. But the Mac app is a different product that isn't on the App Store, so keep
  the iPhone UI dominant in that frame (at least half its area). Show Mac UI in **one or two**
  frames out of 8–10, never in frame 1 on its own. The risk is low to moderate (**judgment, not
  documented**).
- **Generated or lifestyle imagery.** It's fine as a background plate behind real captures. A
  frame that is mostly mood and little UI is the documented rejection pattern.
- **Fictional data:** 2.3.9 says *"display fictional account information instead of data from a
  real person."* The `--demo` fixtures already do this. Multi-account shots must use invented
  labels such as "Personal", "Work" and "Studio", never real emails.
- **No price in screenshots:** 2.3.7 says *"Metadata such as app names, subtitles, screenshots,
  and previews should not include prices …"*. Don't caption "Free Mac app".
- **What's New:** 2.3.12 says *"significant changes must be listed in the notes."* The redesign
  needs a specific What's New (draft in §5.5).
- **Review notes:** 2.3.1(a) says new features *"must be described with specificity in the Notes
  for Review."* Update the review-notes block in `docs/release/appstore-listing.md` for four
  providers, the widget styles, and how to reach every new screen inside Explore Demo.

### 2.4 Trademarks, other apps, other platforms

- **Subtitle:** 2.3.7 says subtitles *"should not … reference other apps"*. Keep Claude, Codex,
  Grok and Cursor **out of the subtitle**. "Headroom for Mac" in the subtitle is also a stretch.
- **Keywords:** Apple's product page guidance says *"Do not use trademarked terms … competing app
  names"*. The July listing passed review with `claude,codex,chatgpt,anthropic,openai`. Naming
  the providers the app genuinely works with is common practice and has a precedent here.
  Section 5.4 gives one keyword set that uses provider names and one that doesn't.
- **Provider logos in screenshots:** they appear because the app UI shows them, which is normal.
  **Don't** use them as standalone decoration, for example a big Claude starburst in the caption
  band or a constellation of provider logos. That reads as endorsement and invites a 5.2.1 flag
  (*"Don't use protected third-party material such as trademarks … without permission"*).
- **Platforms:** 2.3.10 bans imagery of *other mobile platforms*. Mac, iPad and iPhone are all
  Apple, so they're fine.
- **Apple device frames:** Apple's Marketing Guidelines
  (https://developer.apple.com/app-store/marketing/guidelines/) say to use the official product
  bezels from https://developer.apple.com/design/resources/ (iPhone 17/18, iPad Pro (M5), MacBook
  Pro M5 and others are listed), and: *"Do not crop, tilt, or obstruct"*, *"Do not add …
  graphic elements that appear to enter or come out of the product screen"*, and show multiple
  products *"in the correct relative sizes."* Many top listings ignore this (Flighty, Mercury,
  Opal tilt or crop), and enforcement seems lax (**unverified**). **The zero-risk route is
  frameless:** a rounded screen with a hairline edge. No device is drawn, so the bezel rules don't
  apply. All four directions below use that unless noted.

### 2.5 Custom product pages, product page optimization, in-app events

- **Custom product pages** (https://developer.apple.com/app-store/custom-product-pages/): up to
  **70** extra versions of the page with their own screenshots, promotional text and previews,
  each reachable by a unique URL. They are reviewed on their own, separately from app versions.
  Apple says they can also appear in search *"when assigned matching keywords"* (I haven't
  checked this in App Store Connect). Deep links work on iOS 18+. **Worth one:** a page for
  visitors from headroom.zantos.co ("Get Headroom for iPhone"). Those people already have the
  Mac app, so it should lead with the Mac→iPhone frame and the Home Screen widgets. The default
  page stays tuned for searchers. Later, keyword pages could lead with Cursor or Grok for people
  searching "cursor usage" (**verify keyword-CPP behavior in ASC first**).
- **Product page optimization** (https://developer.apple.com/app-store/product-page-optimization/):
  up to **3** alternate versions, up to **90 days**, judged at 90% confidence, and reviewable
  without a new version unless the icon changes. At Headroom's traffic (0 ratings) a test is
  unlikely to reach confidence. **Skip it for now.**
- **In-app events** (https://developer.apple.com/app-store/in-app-events/): types include
  "Major Update". Event card 16:9 at 1920×1080 or larger, detail page 9:16 at 1080×1920 or
  larger, up to 31 days. Apple excludes general awareness promotions. A "Major Update" card for
  the redesign could qualify but is optional and low value. **Skip it.**

### 2.6 How "Designed for iPad" shows up on the Mac, and how to opt out (A4)

Source: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon

- **Default is on.** iPhone and iPad apps *"automatically become available"* on Apple-silicon
  Macs running macOS 11 or later. The live page confirms it ("Designed for iPad. Not verified for
  macOS." plus the Mac compatibility line).
- **Which screenshots appear on Mac:** the iPad set, because the app supports iPad. Kyle saw this
  in the Mac App Store. A developer-forum thread says the same about the web store: iPad
  screenshots showed by default until the developer turned off Mac availability
  (https://developer.apple.com/forums/thread/675970, from 2021). Today's US web page put the
  iPhone set first in my fetch, so the web behavior may have changed. Apple's docs don't say
  which set the Mac App Store uses. **You can't upload Mac-specific screenshots** for an iOS app
  on Mac. The only way to get them is to add a macOS platform to the record, and *"releasing it
  … will replace the iOS app on the Mac App Store."* The real Mac app can't take that route: it
  is deliberately unsandboxed so it can run the CLIs (README "Leave App Sandbox off"), and the
  Mac App Store requires the sandbox.
- **How to opt out:** Apps › Headroom › **Pricing and Availability** › **iPhone and iPad Apps on
  Apple Silicon Mac** › Apple Silicon Mac Availability › deselect **"Make this app available"** ›
  Save. It applies to the app as a whole, not per version. Requires the Account Holder, Admin or
  App Manager role. What happens to Macs that already installed it is **unverified**, though
  past installs normally stay. Apple Vision Pro availability has its own toggle in the same
  section, also on by default.
- **Trade-offs:**

| Keep Mac availability | Opt out (recommended) |
|---|---|
| The Mac App Store returns *something* for "Headroom". | Mac users find Headroom through the website, which is where the real Mac app (a free DMG) lives. |
| What it offers is an unverified iPad mirror running on the Mac that is meant to be the source. Without the Mac app it shows "Waiting for Mac". With it, the mirror is redundant. | No confusing second "Headroom" next to four lookalikes on the Mac store. |
| It shows the iPad set as the Mac first impression, so the iPad set would need to be as strong as the iPhone set, and probably landscape (2752×2064) to suit the Mac window. | The iPad set only serves iPad buyers and can stay portrait. |
| It risks reviews from Mac users who expected the menu bar app. | It matches an existing product decision: the iPhone widget is already pushed off the Mac (`HeadroomIOSWidgets.swift:25`). |

  **Recommend opting out.** Revisit only if a Mac App Store version of Headroom ever becomes
  possible.

---

## 3. What good looks like (A1 references)

Eight reference images are saved in `.context/ios-parity/appstore-refs/` (600×1300 JPEG from
mzstatic via the iTunes lookup `screenshotUrls`). `appstore-refs/sources.json` records the app,
id, screenshot index, source URL and technique for each.

| # | App (id) | Technique | Lesson for Headroom | Saved image |
|---|---|---|---|---|
| 1 | **Linear Mobile** (1645587184) | Dark-first, centered sentence-case headline, barely-there device outline, near-monochrome UI | The closest tonal match to "quiet, precise, premium". Restraint reads as confidence. | `linear-mobile-01.jpg` |
| 2 | **Raycast** (6503428327), the iOS companion to a Mac app | Dark set with a small mono eyebrow above a two-line headline; UI cards break out of the device; 3D brand objects | The eyebrow-plus-headline rhythm suits a developer tool. Skip the 3D objects. | `raycast-ios-01.jpg` |
| 3 | **Mercury Weather** (1621800675) | Bold captions, a gradient per shot, and a final frame of real widgets on a Home Screen ("Interactive Widgets for your Home Screen") | Widgets on an actual Home Screen sell the glance better than the app does. | `mercury-weather-08.jpg` |
| 4 | **Tiimo** (1480220328) | Strip-style set: one continuous gradient, the first device bleeds off the right edge, and floating cards cross the frame edges | How a panorama reads when it's swiped. The devices don't continue across frames; the background and loose elements do. | `tiimo-01.jpg`, `tiimo-02.jpg` |
| 5 | **Opal** (1497465230) | Premium/lifestyle: the hero metric *is* the headline ("Get back 1h23m every day"), a rendered 3D environment, a tilted device | The model for a generative direction. Its tilt breaks Apple's bezel guideline. | `opal-01.jpg` |
| 6 | **QuotaKit** (6777747568), a **direct competitor** (Mac→iPhone AI usage companion) | Neon light trails, laurels ("Built for AI Power Users"), feature pills, gradient headline words | The look to differentiate *from*: generic AI gloss, and the anti-reference in PRODUCT.md. | `quotakit-01.jpg` |
| 7 | **Things 3** (904237743) | One flat brand color, a bold lead phrase plus a sentence, and a calm closing frame with Lock Screen and Home Screen widgets | A widget closer that stays restrained. | `things3-08.jpg` |
| 8 | **Flighty** (1358823008) | Captioned frames, Live Activity and Dynamic Island scenes, a device that crosses the seam between frames 2 and 3, press quotes | Shows system surfaces (Lock Screen, Home Screen) as features. | not saved |
| 9 | **Fantastical** (718043190) | A "Works with Your Existing Accounts" frame with a constellation of provider logos | A tempting idea for a "four providers" frame, but avoid it (§2.4: logos as decoration). | not saved |
| 10 | **Tot Pocket** (1498235191), the iOS sibling of a Mac app | "Seamlessly sync text across iOS & macOS with iCloud" caption | Proof that the sync story can be told in one caption without drawing the Mac. | not saved |
| 11 | **LibarAI** (6792757885), a competitor | Dark, full-bleed screens, one-line captions, very dense UI | Density hurts at thumbnail size. Headroom's calm cards will read better. | not saved |
| 12 | **Streaks** (963034692) | No captions; full-bleed brand-color screens; widget Home Screen as the last frame | Full-bleed Home Screen frames, the technique Direction C builds on. | not saved |

What the strongest sets have in common: a single visual system across all frames; one idea per
frame; captions short enough to read in search results; widgets shown on a Home Screen rather
than floating alone; and at most one "story" frame.

---

## 4. Directions for Headroom (A1, A2, A7)

**Shared assumptions**

- **Brand tokens** come from `design/vessel-app-icon.svg`:
  - Graphite `#33404f → #1a2330 → #0b111a` (lines 4–6)
  - Liquid `#93ffc6 → #4bdd97 → #1fac70` (lines 9–11)
  - Meniscus highlight `#eafff4` at 0.42 opacity (line 36)
  - Wall `#dfe8e6`, `#b7c4c2` (lines 20–21), used as the light-mode surface
- **Caption type:**
  - Headlines in SF Pro Display Semibold, sentence case, tight tracking, so captions match the
    in-app type. SF's license covers UI mock-ups for Apple platforms; whether App Store captions
    count is **unverified**. If Kyle wants zero license doubt, use Source Sans 3 Semibold (OFL),
    the website's face.
  - Eyebrows in TX-02, the website's mono and Kyle's font, at about 34 px, in liquid green.
  - None of these faces is on the banned list.
- **One moment everywhere:** the same numbers in every frame. Claude at 72% for the 5-hour
  window, 38% weekly and 61% Fable; Codex 41% / 64%; Grok 56%; Cursor 69% / 37%. These come from
  the style fixtures (`DemoScreenshotData.swift:486-489`). The `full` phone fixture currently
  says Fable 54% (`:62`); unify the two before shooting.
- **Status bar:** 9:41, full Wi-Fi, a full battery with no charging bolt, and on iPad a fixed
  date via the ISO `--time` value.
- **No motion** in any still. No pulsing, breathing or looping glow anywhere, including any
  future preview.

### Direction A: "Graphite", dark-first frames with captions and a waterline (recommended)

**Concept.** Every frame is a real capture on the graphite gradient. A 2 px liquid-green
**waterline** runs edge to edge at the same height (about 64% from the top) on every frame, with
a faint liquid tint below it (`#1fac70` at about 10% fading to 0). The caption sits in the
"headroom" above the line: a mono eyebrow, then a headline of at most two lines. The device is
**frameless**: the capture at about 82% of the frame width, a continuous-corner radius, a
hairline edge (`rgba(255,255,255,.12)`), with the bottom bleeding off the frame. The waterline
borrows the panorama's sense of continuity without its fragility: every frame still stands
alone, can be reordered, and can be reused in custom pages.

**iPhone (6.9″, 1320×2868)**

| # | Eyebrow | Headline caption | Content and state | Fixture / launch args | Depends on |
|---|---|---|---|---|---|
| 1 | Headroom | Know what's left before the reset | Usage screen with four providers. Default meter style; one orange weekly row, the rest green | `--demo --demo-variant fourProviders` (`fourProviders` exists, `DemoScreenshotData.swift:39,266`) | Redesigned usage screen; the variant launch argument (§6) |
| 2 | Widgets | Your limits on your Home Screen | Home Screen page: Nested Meter large (Claude + Codex) plus two Vessel Hero smalls (Grok, Cursor) on a graphite wallpaper | Widget wall, `claudeCodex` + `grokCursor` | Widget wall (§6.2) |
| 3 | Mac + iPhone | Your Mac reads it. Your iPhone shows it. | The Mac menu-bar strip across the top (pills reading 38% and 64%) with the popover dropping from it; the iPhone capture in front taking at least half the frame; small footer line "Requires Headroom for Mac" | Mac popover from `--demo multi-4`, phone `fourProviders` | A clean Mac popover capture (harness gaps, §6.3) |
| 4 | Accounts | Every account, every limit | Usage screen with Claude Personal/Work/Studio and Codex Personal/Work (mirrors the Mac `multi-3` scenario) | New `multiAccount` variant | **Multi-account on phone** (envelope change). If it doesn't ship, swap in "Model limits too", showing the Fable row |
| 5 | Widget styles | Four styles. One per widget. | Four widgets in a 2×2: Nested Meter, Vessel Hero, Tightest First, Liquid Level (all small, or 2 medium + 2 small) | Widget wall, `claudeCodex` | — (widget styles exist in build 33) |
| 6 | Tightest first | The limit that's closest, first | Tightest First medium in its critical state plus the app's red critical numeral | Widget `tightClaudeCursor` (`:490`); app `attention` variant | Red critical numerals on phone |
| 7 | Meters | Meters that match your Mac | One Claude card shown in four meter styles (micro.chip.event, full.segmented.ghost, micro.tube.hue, full.machined.event) | `--meter-style …` on phone | **Meter styles on phone**; the wording depends on whether the style syncs from the Mac or is chosen on the phone |
| 8 | API spend | API spend beside your plans | Spend rows with marks, period chip and "used" | `full` variant (spend on) | Redesigned spend rows; xAI row (**verify on phone**) |
| 9 | Light mode | Just as calm in light mode | Frame 1 in light appearance on the "wall" gradient, waterline in `#1fac70` | `simctl ui appearance light` | — |
| 10 | Private | Nothing to sign in to on your phone | Settings sheet: sync status, "From Mac · 2 min ago", Explore Demo / About | `--demo-screen settings` | Redesigned Settings (S1) |

Frames 1–3 form the search triptych: what it is, where it lives, what it needs.

**iPad (13″, 2064×2752 portrait, or landscape if Mac availability stays on)**

| # | Headline caption | Content | Depends on |
|---|---|---|---|
| 1 | Every limit, at full size | Redesigned iPad usage: four providers, accounts, spend, with no empty bottom 75% | iPad layout (U10) |
| 2 | Your limits on your iPad Home Screen | iPad Home Screen with widgets | iPad widget geometry in the widget wall (sizes **unverified**) |
| 3 | Your Mac reads it. Your iPad shows it. | Mac strip plus iPad capture | as iPhone #3 |
| 4 | Pick a style for every widget | The four styles side by side | — |
| 5 | Nothing to sign in to | Settings | S1 |

**Production.** Captures come from `simctl` (§6.1). The widget frames come from the widget wall
(§6.2). The compositor is HTML/CSS (§6.3). Cost **S–M** once the redesigned screens exist.
Review risk **low**: every frame is real UI, and Mac UI appears in one frame.

**Why I recommend A:**
- It matches PRODUCT.md ("quiet, precise, premium"; anti-reference: "marketing-site gloss") and
  the icon.
- It sets Headroom apart from competitors that went neon (QuotaKit) or dense (LibarAI).
- It has the lowest review risk.
- It is fully repeatable from the repo with no external imagery.
- Each frame survives reordering, custom product pages and future localization.
- It produces the iPad set with the same system.

### Direction B: "Source and mirror", one panorama telling the Mac→iPhone story

**Concept.** One continuous graphite canvas sliced into seven frames. The **Mac menu bar runs
along the top of frames 1–3 like a horizon.** The waterline from A becomes a literal line that
flows out of the Mac popover, crosses the seams, fills the iPhone, and ends at frame 7 in the
Vessel mark. Devices and widget tiles straddle the seams (Tiimo's technique) so swiping feels
like one surface.

**iPhone shots**

| # | Caption | Content |
|---|---|---|
| 1 | Your Mac reads it. Your iPhone shows it. | Menu-bar strip with pills; the iPhone in front showing four providers (iPhone UI dominant; the Mac never stands alone) |
| 2 | Synced through your own iCloud | The same iPhone straddles the seam; a short sync line, no cloud icon cliché |
| 3 | Then it's on your Home Screen | Home Screen widgets; a Nested Meter large tile crosses the seam |
| 4 | Four styles. One per widget. | The four styles fan across the seam between frames 4 and 5 |
| 5 | The limit that's closest, first | Tightest First plus the red numeral |
| 6 | Every account, every limit | Multi-account usage (same dependency as A4) |
| 7 | Nothing to sign in to on your phone | Settings; the waterline ends in the Vessel mark |

**iPad:** a separate 3–4 frame panorama. The aspect ratio differs, so the iPhone canvas can't be
reused.

**Fixtures:** as in A.

**Production.** The compositor renders one 7×1320 by 2868 canvas and slices it into exact
1320-wide frames. Seam elements are placed on the slice lines; the store's gutters are visual
only. Cost **M**.

**Risks.**
- Frames 1–3 must each make sense alone, because search shows only three.
- Any reorder, custom product page, or later localization breaks the continuity.
- The Mac appears in three frames. Keep the iPhone dominant in each so "the majority … highlight
  the app's main features" still holds.

**Best for:** the most distinctive storytelling, and the strongest answer to "better than
straight screenshots". It costs the most to maintain.

### Direction C: Widget-first, full-bleed Home Screen scenes

**Concept.** Most frames *are* an iPhone Home Screen at 1320×2868: no device frame, a status bar
at the top, Headroom widgets on a custom Headroom wallpaper (graphite vessel gradient, plus a
"wall" light variant). The caption sits in a band at the top of the wallpaper. Never show other
apps' icons; a widgets-only Home Screen page is a real iOS layout. The app itself appears in two
frames. Bonus: release the wallpapers on headroom.zantos.co.

**iPhone shots**

| # | Caption | Content |
|---|---|---|
| 1 | Your AI limits, on your Home Screen | Nested Meter large plus two Vessel Hero smalls |
| 2 | One number. The one that matters. | Four Vessel Hero smalls in a 2×2 (Claude, Codex, Grok, Cursor) |
| 3 | The limit that's closest, first | Tightest First medium, critical state |
| 4 | Read the level, not the math | Liquid Level medium plus large |
| 5 | Color only when it counts | "Only when low" color mode: three neutral widgets and one orange |
| 6 | Open it for the whole picture | The app (frameless capture) |
| 7 | Every account, every limit | App, multi-account (dependency as A4) |
| 8 | Your Mac reads it. Your iPhone shows it. | Mac strip plus phone |
| 9 | Light or dark | Light Home Screen |

**iPad:** a widget-wall Home Screen (iPad suits it), the app, Mac + iPad, and a light variant.

**Fixtures:** widget fixtures `claudeCodex`, `grokCursor`, `tightClaudeCursor`, `spend`, plus the
"Only when low" color mode (`WidgetColorMode`).

**Production.** Entirely dependent on true iOS-metric widget renders (§6.2), because macOS
harness renders lay iPhone text out with macOS metrics (`WidgetRenderHarness.swift:13-15`) and a
Home Screen invites close inspection. Cost **M**.

**Risks.**
- Low review risk: widgets are app functionality, and Apple's own sample lists show widget
  frames.
- An empty icon grid can look staged. Mitigate with a dock blur and a "widgets page" layout.

**Best for:** selling the reason to install the phone app at all, which is the glance.

### Direction D: "Studio", premium/lifestyle with generated imagery (A7)

**Concept.** Opal-level polish. Matte graphite studio surfaces, soft top light, and the Vessel as
a **physical glass capsule** holding mint liquid at 38%, used as a hero object. Real captures are
composited onto official bezels or frameless screens. Some lifestyle frames: a desk at dusk with
a MacBook and an iPhone on a stand.

**Uses for Higgsfield** (Kyle mentioned the Higgsfield MCP; **it is not connected in this
session, so none of this was tested**):
1. **Background plates:** graphite and glass environments with no devices and no text.
2. **The glass Vessel hero object** at several fill levels (38%, 64%, 12% critical).
3. **Lifestyle plates** with blank or green-screen device areas, where official bezels and real
   captures are composited.

Never generate UI, numbers, screens or devices.

Prompt sketches:
- "studio product photograph, matte graphite surface, soft overhead light, a tall glass capsule
  with rounded ends standing upright, filled one third with luminous mint-green liquid, flat calm
  meniscus, deep blue-black background, no text"
- "dim desk at dusk, aluminum laptop closed, phone on a stand, screen area pure #00FF00, shallow
  depth of field, cool graphite palette, no logos"

**iPhone shots (example)**

| # | Caption | Content |
|---|---|---|
| 1 | How much is left, at a glance | Glass vessel object beside a frameless phone |
| 2 | Your Mac reads it. Your iPhone shows it. | Desk plate with real Mac and phone captures |
| 3 | Your limits on your Home Screen | Phone on a matte surface with widgets |
| 4–8 | (as A) | Plates as backgrounds only |

**Production.** Generation, then manual compositing in HTML. Cost **L**.

**Review and brand risk: medium-high.**
- 2.3.3: frames that are mostly mood get rejected. Keep a real capture as the main subject of
  every frame, with generated imagery at most about 40% of a frame.
- Apple's marketing guidelines: generated iPhones and Macs are unofficial device depictions.
  Composite official bezels instead.
- 2.3.9: rights to generated material depend on Higgsfield's commercial terms (**unverified**).
- 2.3.4: none of it can be used in an App Preview.
- Brand: this drifts toward the AI gloss that QuotaKit already owns and that PRODUCT.md rules
  out.

**Best for:** a single custom product page or the website hero, not the default listing.

**Recommendation in one line:** ship **A** as the default page. If Kyle wants more theater, use
**C's** Home Screen frames for #2 and #5. Keep **B** in reserve for a website-traffic custom
product page. Use **D** only for web and social.

---

## 5. Listing copy (A3, A5)

### 5.1 Name (30 chars max)

App Store search for "headroom" (US/GB/DE/JP, 2026-10-03) returns these apps in the same niche:

| Id | Name | Seller | Released |
|---|---|---|---|
| 6779408286 | Headroom - AI Usage | Rashim Anand | 2026-06-23 (a month *before* Headroom Mobile) |
| 6806870455 | Headroom ~ Know Your AI Limits | Exevio Ltd. | 2026-09-12 |
| 6804425133 | AgentHeadroom: AI Usage Limits | Third Vantage LLC | 2026-09-05; also claims a Mac menu bar presence |
| 6809208740 | Headroom: Weekly Usage | Fernando Fernandes | 2026-09-14, Mac App Store, Codex |

Unrelated names in other categories: HeadRoom Nav, Headroom AI Hinglish Captions, Headroom:
Remote Desktop, System Headroom.

Whether exact "Headroom" is free in App Store Connect is **unverified**. It wasn't used in July
even though it was the plan. Even if it were free, it would sit among four lookalikes with no
keyword in it. The Home Screen label stays "Headroom" either way (`CFBundleDisplayName`,
`Sources/HeadroomIOS/Info.plist:5-6`). The name changes with the next version submission. With
0 ratings there is nothing to lose.

| Option | Chars | Pros | Cons |
|---|---|---|---|
| **Headroom: AI Usage Companion** (recommended) | 28 | Indexes "AI", "usage" and "companion"; says up front that it pairs with something, which pre-empts "doesn't work alone" reviews; device-neutral (iPhone, iPad, Mac) | Long. Sits close to "Headroom - AI Usage". |
| Headroom Mobile (keep) | 15 | No change, no risk | "Mobile" is a weak keyword and wrong on iPad and Mac |
| Headroom Companion | 18 | Short and honest | No search terms |
| Headroom: Usage Mirror | 22 | Echoes the site ("the phone is the mirror") | "Mirror" suggests screen mirroring |
| Headroom by Kyle Zantos | 23 | Clearly separates it from the lookalikes | Spends name weight on the maker |

Separate business note: a June 2026 app named "Headroom - AI Usage" predates this listing. That
may be worth a trademark conversation. This is not legal advice and is out of scope here.

### 5.2 Subtitle (30 chars max; no third-party names, per 2.3.7)

| Option | Chars |
|---|---|
| **Your AI limits, at a glance** (recommended) | 27 |
| AI usage limits at a glance | 27 |
| See what's left before reset | 28 |
| Limits and resets, at a glance | 30 |
| AI limits on your Home Screen | 29 |

The current subtitle, "Your AI usage, on your phone", says "phone" on a page that also serves
iPad and Mac.

### 5.3 Promotional text (170 chars; editable any time without review of a version)

- **Recommended (156):** `Now with Grok and Cursor beside Claude and Codex, every account you track on your Mac, and a style you pick for each widget. Try it first with Explore Demo.`
- **If multi-account hasn't shipped (162):** `Grok and Cursor join Claude and Codex, and every widget gets its own style: Nested Meter, Vessel Hero, Tightest First or Liquid Level. Try it all in Explore Demo.`

### 5.4 Keywords (100 chars, commas, no spaces after commas)

Name and subtitle words are already indexed, so don't repeat "headroom", "ai", "usage",
"companion", "limits" or "glance".

- **With provider names (97, recommended; the July version passed review with similar terms):**
  `claude,codex,grok,cursor,chatgpt,quota,meter,tracker,widget,session,weekly,cli,token,coding,agent`
- **Without third-party trademarks (96, the safe fallback if review objects):**
  `quota,meter,tracker,widget,session,weekly,cli,token,coding,agent,menubar,llm,plan,monitor,mirror`

### 5.5 Description (2,047 chars; paste as plain paragraphs with no hard wraps)

```
Headroom shows how much of your Claude, Codex, Grok and Cursor plans you have left, on your iPhone, your iPad and your Home Screen. It's the companion to Headroom for Mac: your Mac reads the numbers, and your iPhone mirrors them.

WHAT YOU SEE
• Claude, Codex, Grok and Cursor side by side, as equals
• Every account you track on your Mac, each with its own limits
• 5-hour, weekly and model limits, plus the billing-period pools Grok and Cursor use
• A countdown to every reset, with a limit that's nearly gone shown in red
• Optional API spend for Anthropic, OpenAI and xAI, if you track it on your Mac
• When the numbers last updated, on every screen

WIDGETS IN YOUR STYLE
Small, medium and large widgets for your Home Screen. Choose a style for each one in Edit Widget:
• Nested Meter: weekly and 5-hour together for each provider
• Vessel Hero: one large number, the one that matters
• Tightest First: whichever limit is closest to running out
• Liquid Level: a fill you can read from across the room
Keep them in color, or let color appear only when a limit runs low.

THE SAME LOOK AS YOUR MAC
The meter styles you pick on your Mac, the same short countdowns and the same calm design, in light or dark.

PRIVATE BY DESIGN
Your Mac publishes a small usage summary through your own iCloud account, and your iPhone reads it. The summary holds percentages, reset times, plan names and the account names you choose. It never holds passwords, sign-in tokens or API keys. Headroom has no servers, no Headroom account, no analytics and no ads. The privacy policy is one page: headroom.zantos.co/privacy

NEEDS HEADROOM FOR MAC
Live numbers come from Headroom for Mac, a free download at headroom.zantos.co, running on a Mac signed in to the same iCloud account with "Sync snapshot to iPhone" turned on. Want to look around first? Tap Explore Demo to try the whole app and its widgets with sample data. No Mac or sign-in needed.

Made for people who spend all day in Claude Code, Codex, Grok and Cursor and just want to know how much headroom is left.
```

**What's New (2.3.12) draft:**

```
A redesign that matches Headroom for Mac.
• Grok and Cursor join Claude and Codex
• Every account you track on your Mac, not just the main one
• Four widget styles, chosen per widget in Edit Widget, colored always or only when low
• The Mac's meter styles, short countdowns, and red when a limit is nearly gone
• A full-size iPad layout
```

### 5.6 Claims that must be true in the shipped build before they go in the listing

| Claim (used in) | Status in repo today | Evidence | Action |
|---|---|---|---|
| Four providers on the phone (description, promo, A1) | **Likely true.** Grok and Cursor logos are in the app; a four-provider fixture exists; Mac 1.4.1 publishes Cursor (BRIEF). | `Sources/HeadroomIOS/DesignSystem/ProviderLogoView.swift:40-41`, `DemoScreenshotData.swift:266` | Check Grok and Cursor billing-period rows on a device |
| Every account you track (description, promo, What's New, A4) | **Not true.** The envelope carries only each provider's primary account. | `Sources/HeadroomCore/Engine/UsageStore.swift:1089-1090` (`primarySnapshots`); BRIEF "Known envelope facts" | Ship the additive multi-account field and phone UI, or drop the bullet and use the fallback promo |
| Account names in the summary (privacy paragraph) | Only becomes true with multi-account. The current live copy says "never … account details". | — | Keep the privacy copy in step with whatever the envelope really carries; never emails |
| Four widget styles plus color mode (description, A5, C) | **True in repo build 33** (AppIntentConfiguration with `HeadroomWidgetConfigurationIntent`); **not in the public 1.0 build 24** | `Sources/HeadroomIOSWidgets/HeadroomIOSWidgets.swift:15-19` | Ship build ≥33 |
| Meter styles "you pick on your Mac" (description, A7) | **Not true.** The phone has no `MeterStyle` usage (grep of `Sources/HeadroomIOS` is empty); `MeterStyle` isn't in the envelope (BRIEF). | — | Depends on decision U1. If the style is chosen on the phone, change to "The same meter styles as your Mac" |
| Red when nearly gone, short countdowns (description, A6) | **Not true on the phone today** (July design: "Resets in …", "Low" chip) | BRIEF "Current state" | Redesign |
| API spend incl. xAI (description, A8) | Spend is mirrored (`APISpendMirrorView.swift`); the envelope projects all spend providers (`UsageStore.swift:1099-1100`). No xAI phone fixture. | — | Check an xAI row on a device; add an xAI spend fixture if it's shown |
| Explore Demo (description, review notes) | True | `Sources/HeadroomIOS/Views/StatusScreen.swift:45`, `SettingsSheetView.swift:46` | — |
| Small/medium/large Home Screen widgets | True. **No Lock Screen, StandBy-specific, Live Activity or control widgets**; don't claim any of those. | `HeadroomIOSWidgets.swift:24` | — |
| Full-size iPad layout (What's New, iPad #1) | Not true (the current iPad is two-up with empty space) | `.context/ios-parity/renders/ipad-current-*.png` | Decision U10 |
| No servers, analytics or ads; Data Not Collected | True per the privacy label | `docs/release/appstore-listing.md` App Privacy | — |
| Banked resets, notifications | **Not on the phone** (banked resets aren't in the envelope; notifications are Mac-only) | BRIEF; AGENTS.md Notifications | Don't claim them in the iOS listing |

---

## 6. Production pipeline (A6)

### 6.1 Captures (headless `simctl`)

**Base it on** `Scripts/capture-demo-screenshots.sh`. It already creates the "Headroom 16 Pro
Max" iPhone and "Headroom iPad Pro 13" iPad simulators (`:31-34`), builds and installs the app,
overrides the status bar (`:84`), launches with `--demo` (`:86`), and strips alpha with ffmpeg
(`:90`).

**Run it with `HEADROOM_IOS_ONLY=1`.** Its macOS half runs `killall Headroom` (`:113`), which
would quit Kyle's live Mac app. AGENTS.md's release-ops rules forbid broad process termination.

**Needed additions:**
1. **A `--demo-variant <name>` launch argument.** The variant today comes only from App Group
   defaults (`DemoScreenshotData.swift:21`), and `CompanionDemoModeStore.setVariant` is called
   only from tests (`Sources/HeadroomCore/Sync/CompanionDemoModeStore.swift:52`). Without the
   argument, the four-provider and multi-account states can't be captured.
2. **A `--demo-screen <usage|settings|appearance|widgets>` launch argument** to land directly on
   each screen. The alternative is a small XCUITest that navigates and calls
   `XCUIScreen.main.screenshot()`, which is sturdier than the fixed `sleep 8` (`:87`) for
   anything beyond the first screen.
3. **A `--meter-style <format.shape.fill>` launch argument on the phone**, mirroring the Mac
   flag, once meter styles land.
4. **Status bar:** `--time 2026-01-13T09:41:00 --batteryState discharging --batteryLevel 100
   --wifiBars 3`. The ISO value also fixes the iPad date. Put the iPad in Full Screen Apps mode
   to avoid the corner arc (**unverified** cause).
5. Leave the `--demo` screenshot mode as it is. It already hides the DEMO badge in screenshot
   launches (`Sources/HeadroomIOS/Views/IOSCompanionView.swift:149`). That is fine because the
   data is fictional (2.3.9).

### 6.2 Home Screen widget scenes (the "widget wall")

**Recommended:** a DEBUG-only `--demo-screen widgets` view in the iOS app.
- It lays out the real `HeadroomWidgetStyledBody` and `HeadroomWidgetStyledBackground` at true
  iOS widget sizes, in a Home Screen grid over a Headroom wallpaper, with no app icons. `simctl`
  captures it with real iOS text metrics.
- It needs `Sources/HeadroomWidgetSharedUI` in the HeadroomIOS app target. Today the iOS widget
  extension compiles it (`project.yml:131`) but the iOS app doesn't (`:89-116`). The Mac app
  already does exactly this for its Widgets & iPhone settings previews (`project.yml:36-38`, the
  "L9P" comment), so there's a precedent. The phone's planned Widgets gallery (option S3) needs
  the same thing, so it's one seam doing two jobs.

**Fallback:** the macOS harness. `swift run Headroom --render-widgets <dir> --widget-geometry ios67`
already has 6.9″ sizes: small 170×170, medium 364×170, large 364×382 pt
(`Sources/HeadroomApp/WidgetRenderHarness.swift:36-38`). It renders at about 2× with a 12 pt
surround and P3 output (`nestedMeter-claudeCodex-large-ios61-dark.png` is 724×756). The harness
would need a `--widget-scale 3` flag and a bare/transparent option. It still carries macOS text
metrics (`:13-15`), so treat its output as acceptable for Direction A's small widget insets and
not for C's full Home Screens.

**Not recommended:** driving SpringBoard through XCUITest to add real widgets. It's brittle and
slow.

**iPad:** widget sizes for the 13″ Home Screen aren't in the harness and are **unverified**.
Capture them from the widget-wall view on the iPad simulator.

### 6.3 Mac imagery for the "Mac reads it" frame

`--render-popover` is offscreen and known to be imperfect. The BRIEF notes that `popover-connected-*`
leaks a real setup card and that `four-default` and `multi-4` render as two-provider popovers.
AGENTS.md says not to accept harness output as final evidence.

Options:
- (a) Fix those harness gaps first, then render `--render-popover <dir>` with the demo scenario
  and meter style.
- (b) **Ask Kyle** for one short live `--demo multi-4` popover capture (his "no live screen
  captures" rule applies).

The menu-bar strip can be drawn in the compositor from the real pill values, so it never needs a
live capture.

### 6.4 Compositor (HTML/CSS rendered headlessly)

- **Files:** `design/appstore/compositor.html`, one self-contained page, plus
  `design/appstore/shots.json`. Each shot carries an id, device, appearance, eyebrow, caption,
  capture paths, layout and waterline position. CSS variables carry the tokens above, so Kyle can
  edit captions in JSON without touching layout.
- **Fonts:** load SF Pro Display or Source Sans 3 and TX-02 from local files with `@font-face` so
  rendering is deterministic.
- **Rendering:** `dev-browser --headless --browser agent-qa` runs a script that sets the viewport
  to the exact pixel size (1320×2868 or 2064×2752) at deviceScaleFactor 1, visits
  `compositor.html#shot=<id>` for each shot, and saves the screenshots. Then run
  `dev-browser stop` so no daemon is left running. Screenshots land in `~/.dev-browser/tmp/`;
  copy them to `dist/appstore/<set>/`.
- **Panorama (B):** render one wide canvas and slice it into 1320 px frames with ffmpeg
  (`-vf crop=1320:2868:<x>:0`, where x = 1320 × frame index).
- **Alternative:** a Swift `--render-appstore` harness using `ImageRenderer`. It gives token
  fidelity with no browser, but is slower for a designer to iterate on. Choose it only if the
  HTML route's fonts or colors drift.

### 6.5 Post-processing and the upload checklist

```bash
for f in dist/appstore/*/*.png; do
  sips --matchTo '/System/Library/ColorSync/Profiles/sRGB Profile.icc' "$f" --out "$f"
  ffmpeg -loglevel error -i "$f" -vf format=rgb24 -y "${f%.png}.tmp.png" && mv "${f%.png}.tmp.png" "$f"
done
sips -g pixelWidth -g pixelHeight -g hasAlpha -g profile dist/appstore/*/*.png
```

- [ ] iPhone set: every file is exactly **1320×2868**. iPad set: every file is exactly
  **2064×2752** (or 2752×2064 for landscape).
- [ ] `hasAlpha: no` on every file. Profile is sRGB. Widget renders (P3) were converted *before*
  compositing.
- [ ] Naming: `iphone69-01-know-whats-left-dark.png` … `ipad13-01-full-size-dark.png`. Upload in
  numeric order; App Store Connect keeps the upload order, and files can be dragged to reorder.
- [ ] Every frame shows real app UI as its main subject. Mac UI appears in at most two frames.
  The iPad set shows only iPad UI.
- [ ] No prices or "free" in images. No standalone provider logos. No real names or emails.
  Status bar reads 9:41 with a full battery and no charging bolt.
- [ ] The same numbers appear in every frame (§4 "one moment").
- [ ] Every caption's claim is checked against §5.6 on the build being submitted.
- [ ] Captions are legible at search-thumbnail size: preview frames 1–3 side by side at about 30%
  scale.
- [ ] Light and dark frames both checked, and no frame is mostly empty (the current iPad failure).
- [ ] Description pasted with no hard line breaks. Review Notes and What's New updated.
- [ ] Mac availability decision applied in Pricing and Availability (§2.6).
- [ ] `docs/release/appstore-listing.md` updated to match what's live: name, subtitle,
  screenshot list (the doc lists 2 iPad shots but only 1 is live), and description.
- [ ] Optional later: script the upload through the App Store Connect API (`appScreenshotSets` /
  `appScreenshots`) using the existing `HEADROOM_ASC_KEY_*` credentials. Not needed for one set.

---

## 7. Not verified

- Whether exact "Headroom" is available as an App Store Connect name, and why the July submission
  became "Headroom Mobile".
- Which screenshot set the Mac App Store app shows (Kyle saw the iPad set; Apple doesn't document
  it). Whether turning off Mac availability affects existing Mac installs.
- The cause of the bottom-right arc on iPad captures (I suspect the iPadOS 26 window resize
  handle).
- Whether the App Store renders hard line breaks in the description on a device (very likely; I
  only checked the HTML source).
- Whether SF Pro's license covers App Store caption use.
- Keyword-assigned custom product pages appearing in organic search (from Apple's marketing page;
  I didn't check it in App Store Connect).
- iPad 13″ Home Screen widget point sizes.
- All Higgsfield behavior and its commercial terms (not connected in this session).
- Whether App Review accepts the Mac-UI frame (the multi-platform exception is App Review's own
  wording, but the Mac app isn't distributed through the App Store).

## 8. Related issues spotted (outside this task)

- `Scripts/capture-demo-screenshots.sh:113` runs `killall Headroom`, which kills a live Mac app.
  It conflicts with the release-ops rule against broad process termination. This belongs in
  BUGS.md.
- `docs/release/appstore-listing.md` has drifted from the live listing: name, description and the
  iPad screenshot count.
- The demo fixtures disagree with each other (Fable 54% in `full` vs 61% in the style fixtures).
  The `full` fixture also still stores `"Prolite"`, static "Resets Jul 9" labels and July
  renewal dates (`DemoScreenshotData.swift:59-71`). Any surface that shows those strings will look
  stale in shots taken in October.
