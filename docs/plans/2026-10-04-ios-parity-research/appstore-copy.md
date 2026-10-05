# App Store copy · Headroom for iPhone and iPad · round 1

Written 2026-10-04 for Kyle’s rewrite request: better copy, anti-AI passes, and nothing that sounds like the other “Headroom” apps. Review doc: `design/appstore-copy-options.html` (approve / deny / discuss, localStorage `headroom-appstore-copy-r1`). Source data for both files: `.context/ios-parity/copy-build/` (`copydata.py`, `compdata.py`, `passes.py`; `lint.py` greps every final string; `build.py` writes the HTML; `make_md.py` writes this file). Competitor raw text: `.context/ios-parity/competitor-text/`; screenshots: `.context/ios-parity/competitor-shots/` (first three per app, `sources.json`).

**Scope update (2026-10-04, from Kyle via coordinator):** the iPhone app ships as **1.5** to match the Mac. Lock Screen widgets and a Control Center control are targeted for the same release but ship only if ready, so they are **conditional claims** here (a Lock Screen caption frame, a description sentence and What’s New bullets, all marked “only if it ships”). Live Activities, Apple Watch, StandBy-specific layouts and the phone signing in to a provider stay unclaimable.

## 1. Recommended set

| Field | Recommended | Count |
|---|---|---|
| Name | Headroom by Kyle Zantos | 23 / 30 |
| Subtitle | AI plan usage and API spend | 27 / 30 |
| Promotional text | Keep up with your AI subscription usage and API spend. Grok and Cursor join Claude and Codex, and every account your Mac tracks now shows on your phone. | 152 / 170 |
| Keywords | `claude,codex,grok,cursor,chatgpt,anthropic,openai,limits,quota,widget,tracker,meter,weekly,reset` | 96 / 100 |
| Description | Option A (§6) | 2524 / 4000 |
| What’s New | Option A (§7) | 569 |
| Screenshot eyebrows | Readouts (a real value from the frame, mono, sentence case) | — |
| “Get Headroom for Mac” row | Get Headroom for Mac (no subtitle, trailing ↗) | 20 |

**iPhone captions (proposed order)**

| # | Eyebrow (readout) | Headline | Count | Was in Direction A |
|---|---|---|---|---|
| 1 | Claude · 5-hour · 72% left | **Room left on four AI plans** | 26 | 1: “Know what’s left before the reset” |
| 2 | Nested Meter · large | **The same numbers, as widgets** | 28 | 2: “Your limits on your Home Screen” |
| 3 | From your Mac · 2 min ago | **Your Mac does the reading** | 25 | 3: “Your Mac reads it. Your iPhone shows it.” |
| 4 | Claude · Personal, Work, Studio | **Each account gets its own rows** | 30 | 4: “Every account, every limit” |
| 5 | Anthropic API · October | **API spend next to plan usage** | 28 | 8: “API spend beside your plans” |
| 6 | 4 styles · set in Edit Widget | **A different style per widget** | 28 | 5: “Four styles. One per widget.” |
| 7 | Work · weekly · 12% left | **Turns red at 15% left** | 21 | 6: “The limit that’s closest, first” |
| 8 | Meter style · same as Mac | **Your meter style carries over** | 29 | 7: “Meters that match your Mac” |
| 9 | Pull to refresh · asks your Mac | **Pull down to ask your Mac** | 25 | 9: “Just as calm in light mode” |
| 10 | Settings · iPhone sync | **Nothing to sign in to** | 21 | 10: “Nothing to sign in to on your phone” |

**iPad captions**

| # | Eyebrow | Headline | Count |
|---|---|---|---|
| 1 | 7 accounts · 4 providers | **Room for all seven accounts** | 27 |
| 2 | Nested Meter · large | **The same numbers, as widgets** | 28 |
| 3 | From your Mac · 2 min ago | **Your Mac does the reading** | 25 |
| 4 | 4 styles · set in Edit Widget | **A different style per widget** | 28 |
| 5 | Settings · iPhone sync | **Nothing to sign in to** | 21 |

Search triptych (frames 1–3): **Room left on four AI plans** / **The same numbers, as widgets** / **Your Mac does the reading**. What it is, where it lives, what it needs.

## 2. Competitor phrase inventory

Fetched 2026-10-04 with the iTunes lookup API (`https://itunes.apple.com/lookup?id=<id>&country=us`) and the `apps.apple.com/us` pages (subtitle from the product header; promotional text is the paragraph shown above the description). Captions were read from the first three screenshots of each app. Codex Meter (both) and Headroom - AI Usage, AgentHeadroom and Model Usage use raw screenshots with no captions.

### 2.1 The listings

| App (id · seller) | Subtitle | Promotional text | Screenshot captions (first three) | Note |
|---|---|---|---|---|
| **Headroom - AI Usage** (6779408286 · Rashim Anand) | Tracking: widgets & activities | Track your Claude, Codex, and Cursor usage limits at a glance — with widgets, Live Activities, and a Dynamic Island countdown to your next reset. | No captions; raw app screens (History, Headroom, History) | Signs in on the phone. Lock Screen, Live Activity, Dynamic Island, history charts. |
| **Headroom ~ Know Your AI Limits** (6806870455 · Exevio Ltd.) | AI limits, widgets & alerts | Know your AI limits with live meters, reset countdowns, widgets and alerts across Claude, Codex, Cursor, Copilot, and more. | REMAINING AI USAGE / Know your limits. · HOME SCREEN WIDGETS / Put it where you look. · APPLE WATCH / On your wrist. | Dark graphite frames, uppercase mono eyebrow, one accent-colored word, trailing period. The closest visual match to Direction A. |
| **AgentHeadroom: AI Usage Limits** (6804425133 · Third Vantage LLC) | Token quota tracker & widgets | Now on the Mac: your accounts in the menu bar and in desktop widgets, shared from your phone through iCloud Keychain. One purchase, iPhone, iPad and Mac. | No captions; raw app screens (dashboard, Lock Screen Live Activity, Claude detail) | Plain, dry voice close to ours. Also has a Mac menu bar app. In-app labels “Nearly out”, “Nearly gone”, “Burning”. |
| **Headroom: Weekly Usage** (6809208740 · Fernando Fernandes) | See your pace. Make it last. | (none shown) | Track your pace. / Know your weekly usage before it runs out. · Make it yours. / Customize what appears in your menu bar. | Mac App Store, Codex only, menu bar. |
| **QuotaKit: AI Usage Tracker** (6777747568 · Columbus Labs LLC) | Quota alerts & spend | (none shown) | Track AI usage on the go / See live session and weekly quota from your iPhone—anytime, anywhere. · See every dollar spent · Dive into provider detail | Mac collector plus iPhone companion over iCloud, the same shape as Headroom. Neon trails, laurels “Built for AI Power Users”. |
| **Codex Meter** (6781059780 · Tom Fadial) | (none) | Track your Codex GPT-5.5 usage from the app and Home Screen widget. | No captions; one raw screen | Signs in with Codex on the phone. |
| **Codex Meter - Your Codex Usage** (6792673945 · Filip Bukovina) | (none) | (none shown) | No captions; one raw screen | “PRIVATE BY DESIGN” header; earned reset credits. |
| **LibarAI** (6792757885 · Grzegorz Mackiewicz) | AI limits and useful widgets | See limits for Claude, Codex, GLM, Kimi, and MiniMax. Widgets keep usage and reset times in view on iPhone and iPad. | Every AI limit. One clear view. · See what needs attention now. · Plan around the next reset. | Dark, dense UI. |
| **AI Session Meter** (6784566115 · Yuya Otake) | AI usage forecasts & insights | Will your next task fit before the reset? Check Claude and Codex directly on iPhone or iPad. Forecast usage and explore Mac-synced detail. One-time unlock. | AI SESSION METER / Your AI usage, with a view ahead · Know when and how much you use · Detailed usage, model by model | Uppercase eyebrow over two-line headline on dark navy. |
| **Limits: AI Usage Tracker** (6783130074 · Pranav Karthik Mruthyunjayan) | Codex, Claude, Cursor limits | See your AI coding limits at a glance. Session and weekly usage, live reset countdowns, and Home and Lock Screen widgets, all private and on your device. | Your AI limits, always in view. · Every limit, one place. · All providers, one widget. | Supports Grok and Cursor too. |
| **AI Limits & Reset Tracker** (6758946226 · FractalDream Unipessoal Lda) | Alerts, widgets, reset timers | Stop refreshing multiple AI dashboards. Track usage, resets, alerts, widgets, and history across providers in one place. | All your AI usage / One dashboard for Claude, Codex, OpenAI and more. · Codex reset credits / Rate limits, resets and credits, all in one place. · Multiple accounts | Light frames with blue headlines. |
| **Agent Meter: AI Usage** (6781480047 · Shuo Deng) | Claude/Codex reset alerts | See coding-plan quotas, reset countdowns, and developer API billing at a glance. | See what’s left, anytime · Official reset updates, right on time · Every service, one clear view | Mac collector plus phone; API billing; banked resets. |
| **Model Usage** (6761831599 · Rayan Khan) | AI coding usage dashboard | A live dashboard for your AI coding usage. Watch your session and weekly totals update in real time, with widgets and Live Activity across your devices. | No captions; raw app screens | “PRIVACY BY DESIGN”; “No analytics. No tracking. No accounts.” |

### 2.2 Subtitles on the niche’s “You might also like” shelves

| App | Subtitle |
|---|---|
| AI Limits | All your AI limits at a glance |
| Codexex | Codex usage at a glance |
| Statusline: Agent Quota | Codex & Gemini, at a glance |
| AI Usage | Track your AI service usage |
| AI Usage Limits / Cooldown | Track your AI usage limits |
| AI Usage Meter | Monitor AI Subscription Limits |
| Agent Cat Mobile | AI coding limits, on the go |
| Model Pulse | AI usage, limits & spend |
| Usage for Claude | Track subscription usage |
| Token Monitor | Claude, Codex, GPT API Spend |
| UsageLens | AI quota and usage dashboard |
| UsageScope | Limits, history & reset alerts |
| CUStats Go | Claude, Codex, Grok & more |
| VibeCheck | Claude, Cursor & Codex Limits |
| Headroom Mobile (ours, today) | Your AI usage, on your phone |

### 2.3 Recurring phrases, claims and structures, and our rule for each

| Phrase or structure | Who uses it | Where | Our rule |
|---|---|---|---|
| “at a glance” | Headroom - AI Usage, Headroom: Weekly Usage, Codexex, Codex Meter, Limits, Agent Meter, AI Limits, Statusline | promo, description, subtitle | Never used. The earlier recommended subtitle “Your AI limits, at a glance” is dropped. |
| “in one place” · “one clear view” · “one dashboard” | Headroom - AI Usage, Headroom ~ Know, AgentMeter, LibarAI, Limits, AI Limits & Reset Tracker | captions, description | Never used. No “one place / view / dashboard”. |
| “Every X, one Y” / “All X, one Y” headline | LibarAI “Every AI limit. One clear view.”, Limits “Every limit, one place.” and “All providers, one widget.”, AgentMeter “Every service, one clear view” | captions | No headline starts with “Every” or “All”. Direction A’s “Every account, every limit” is gone. |
| “Know your limits” · “know how much you have left” | Headroom ~ Know (name, caption, description), Headroom - AI Usage, Limits, Headroom: Weekly Usage | name, captions, description | No “know”. Captions state the number instead. Direction A’s “Know what’s left before the reset” is gone. |
| “See what’s left” | AgentMeter caption, QuotaKit description | captions | We say “room left” or “percentage left”. |
| Fear of the wall: “before you hit a wall / a limit”, “before a limit interrupts your work”, “cut off mid-task”, “stop guessing” | Headroom - AI Usage, Headroom ~ Know, AI Limits & Reset Tracker, Model Usage, QuotaKit | opening lines | No fear framing. We describe what the screen shows. |
| “without opening the app / anything / a browser” | Limits, LibarAI, AgentHeadroom, both Codex Meters, AI Limits & Reset Tracker | description, captions | Not used. |
| “Private by design” · “Privacy by design” · “Quiet by design” | Headroom - AI Usage, Codex Meter (Bukovina), Limits, Model Usage, Headroom: Weekly Usage | section headers | Not used. Also drops our own July header “Private by architecture”. |
| “No servers, no analytics, no account” lists | Headroom - AI Usage, Model Usage, Limits, AI Session Meter, Headroom ~ Know, AgentHeadroom (“collects nothing. It has no server to collect it with.”) | privacy paragraph | We list what the Mac’s summary holds, what stays on the Mac, and quote the privacy label. |
| “Put it where you look” · “Live where you already look” | Headroom ~ Know (caption and description), Model Usage | captions | Not used. |
| “Your X, on / in Y” headline | Limits “Your AI limits, always in view.”, LibarAI “keep … in view”, our current subtitle “Your AI usage, on your phone” | captions, subtitles | Not used. Replaces Direction A’s “Your limits on your Home Screen”. |
| “on the go” · “anytime, anywhere” · “on your wrist” | QuotaKit, Agent Cat Mobile, AgentMeter, Headroom ~ Know | captions, subtitles | Not used. |
| Verb-led “Track …” / “Monitor …” | QuotaKit “Track AI usage on the go”, Headroom: Weekly Usage “Track your pace.”, six shelf subtitles | captions, subtitles | Not used as a lead verb. |
| Ampersand noun-list subtitle (“AI limits, widgets & alerts”) | Headroom ~ Know, AgentHeadroom, Headroom - AI Usage, Model Pulse, QuotaKit, UsageScope | subtitles | Our subtitle is a phrase joined with “and”. |
| “side by side” | Model Usage | description | Dropped from the July and APPSTORE drafts (“side by side, as equals”). |
| “dashboard” | QuotaKit (“a clean mobile dashboard”), Model Usage, Limits, AI Limits, UsageLens | description, subtitles | Not used. |
| “live” · “real time” · “ticking” | Model Usage, Headroom - AI Usage, Limits, Headroom ~ Know | description | Not used. The phone shows the Mac’s last reading with its age, so “live” would overclaim. |
| “X is the iPhone companion for …” opener | QuotaKit, Zodex | first line | We open with what the Mac app does and call this app its iPhone and iPad half. |
| “Headroom keeps / brings / helps …” opener | Headroom - AI Usage, Headroom ~ Know, Headroom: Weekly Usage | first line | Our first sentence’s subject is “Headroom for Mac”, which none of them can say. |
| “Built for AI power users” · “for people who live in …” | QuotaKit laurel, Zodex, our own July closer | closers, badges | No audience-flattery closer. |
| “Plan around the next reset” | LibarAI caption, Headroom - AI Usage description | captions | Not used. |
| Uppercase section headers (“FEATURES”, “WHAT IT SHOWS”, “PRIVACY”) | Most listings in the niche | description | Paragraphs that lead with a plain sentence. No all-caps headers. |
| Pace words: “on pace”, “burning”, “make it last” | Headroom: Weekly Usage, AgentHeadroom, Headroom ~ Know, QuotaKit, AI Limits | everywhere | Headroom has no pace feature, so none of these words. |
| “Make it yours” · “your way” | Headroom: Weekly Usage caption | captions | Not used. |
| “See every dollar spent” | QuotaKit caption | captions | Spend frame says “API spend next to plan usage”. |
| “Nearly gone” · “Nearly out” | AgentHeadroom in-app labels | UI, screenshots | We say “turns red at 15% left”. |
| Look: uppercase letter-spaced mono eyebrow over a large headline on dark graphite, one word in an accent color, trailing period | Headroom ~ Know (“REMAINING AI USAGE / Know your limits.”), AI Session Meter | screenshot system | Readout eyebrows in sentence case, no accent-colored words, no trailing periods. See the eyebrow decision. |

**Two findings that change Direction A.**

1. **Exevio’s “Headroom ~ Know Your AI Limits” already uses Direction A’s caption system:** dark graphite frames, an uppercase letter-spaced mono eyebrow (“REMAINING AI USAGE”, “HOME SCREEN WIDGETS”), a big headline with one word in an accent color, and a trailing period. Our differentiators: readout eyebrows in sentence case instead of topic labels, no accent-colored words, no trailing periods, and the waterline. Kyle decides in the eyebrow decision (E) of the HTML doc.
2. **AgentHeadroom writes in a plain, dry voice close to the one PRODUCT.md asks for** (“AgentHeadroom collects nothing. It has no server to collect it with.”, “Counted from either end”). Plain-and-dry alone won’t separate us, so the copy leans on facts only Headroom has: the Mac reads the official command-line tools, the phone never signs in, the four widget style names, the Mac’s meter styles, pull-down-to-ask-the-Mac. It also avoids their aphoristic closers.

## 3. Name

**Headroom by Kyle Zantos**: 23 of 30 characters. Kyle’s pick; confirmed, with these risks:

- **Search weight moves to the subtitle and keywords.** The name no longer carries “AI” or “usage”. The recommended subtitle puts “AI”, “plan”, “usage”, “API” and “spend” in the index.
- **It separates us from the four lookalikes** in a “headroom” search. None of them names a person.
- **The product page repeats the seller line** (“Kyle Zantos” sits under the name). Cosmetic.
- **Home Screen label stays “Headroom”** (`CFBundleDisplayName`, `Sources/HeadroomIOS/Info.plist:5-6`). The name changes with the next version submission (1.5).
- **Long term:** if the app moves to a company account, the name carries Kyle’s name with it.

## 4. Subtitle (≤ 30, no third-party names, Guideline 2.3.7)

Kyle’s line, “Keep up with your AI subscription usage & API spend”, is 51 characters.

| Option | Count | Note |
|---|---|---|
| **A (recommended)** · AI plan usage and API spend | 27 | Closest to your line. Puts “AI”, “usage”, “API” and “spend” in the search index now that the name carries none of them. “Plan” is the word the app already uses (the plan chip). No other listing in the niche pairs plan usage with API spend in a plain phrase. Nearest is Model Pulse, “AI usage, limits & spend”, which is an ampersand list. |
| B · Subscription usage, API spend | 29 | Your words, trimmed. Drops “AI”, so a searcher reading it cold can’t tell which subscriptions. “Usage for Claude” already uses “Track subscription usage”. |
| C · AI plan limits and API spend | 28 | Swaps “usage” for “limits”, the noun most people search. Every competitor leans on “limits”, so it blends in more. |
| D · AI plan usage, from your Mac | 28 | The angle nobody else can claim: the phone shows what your Mac reads. Loses API spend. |

**Where Kyle’s full line goes** (it fits none of the 30-character fields):

- **Promotional text (recommended):** it leads promo option A, with “and” for “&” because promo text is prose. Promo text changes any time without a new version.
- **iPad frame 1 headline** (option P1-C): the wide iPad frame holds it on three lines. Over the 32-character thumbnail rule, so iPad only.
- **Sub-caption under iPhone frame 1:** possible, but six competitors use the headline-plus-sentence pattern and it’s unreadable at search size. Not recommended.

## 5. Screenshot captions

Rules: headline ≤ 32 characters (hero ≤ 27), sentence case, no trailing period, no accent-colored word, no provider name in a headline (eyebrow readouts mirror UI labels, which is low risk), no dollar figures in captions (2.3.7 bans prices; a spend amount isn’t a price, but a caption is the wrong place to test that).

**Eyebrow systems**

- **A · Readouts (recommended):** A real value from the frame, in mono and sentence case: “Claude · 5-hour · 72% left”. Exevio’s Headroom already runs uppercase mono category labels (“REMAINING AI USAGE”) over the headline on dark frames. Readouts keep Direction A’s rhythm but say something only Headroom’s data can say.
- **B · Topics in sentence case:** A one-word topic in mono, sentence case: “Widgets”, “Accounts”. Direction A as approved.
- **C · No eyebrow:** Headline only. The waterline carries the system.

**Order changes from Direction A:** API spend moves from 8 to 5 (the subtitle now leads with plan usage and API spend). The light-mode frame becomes the pull-to-refresh frame shot in light appearance (a frame that only says “light mode exists” sells nothing; light mode still shows). If Lock Screen widgets ship, the Lock Screen frame goes in at 6, styles and Tightest First shift down one, and meter styles moves to the swap list.

### iPhone (6.9″, 1320 × 2868)

### iPhone 1 · Usage

Usage screen, four providers, default meter style. One orange weekly row, the rest green. Depends on: Redesign, four providers Direction A had “Know what’s left before the reset”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Claude · 5-hour · 72% left | Usage | **Room left on four AI plans** | 26 | Says what it is and how wide it reaches. “Room left” is the product’s own word, and no listing in the niche uses it. |
| B | Claude · 5-hour · 72% left | Usage | **Room left before each reset** | 27 | Names both numbers on every row: what’s left and when it refills. |
| C | Claude · 5-hour | Usage | **72% left, resets in 2h 14m** | 26 | The readout is the headline, Opal-style. Most distinctive, least explanatory. Countdown must match the fixture. |

### iPhone 2 · Widgets

Home Screen page: Nested Meter large (Claude + Codex) and two Vessel Hero smalls (Grok, Cursor). Depends on: Widget wall capture Direction A had “Your limits on your Home Screen”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Nested Meter · large | Widgets | **The same numbers, as widgets** | 28 | Ties the widget to the app in frame 1. Avoids Limits’ “Your AI limits, always in view” and Exevio’s “Put it where you look.” |
| B | Nested Meter · large | Widgets | **Widgets for the Home Screen** | 27 | Plain label. Safe, forgettable. |

### iPhone 3 · Mac and iPhone

Mac menu-bar strip (pills 38%, 64%) and popover behind the iPhone. Footer line: “Requires Headroom for Mac”. Depends on: Clean Mac popover capture Direction A had “Your Mac reads it. Your iPhone shows it.”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | From your Mac · 2 min ago | Mac and iPhone | **Your Mac does the reading** | 25 | One sentence instead of a mirrored pair. Says the dependency plainly, with a little dryness. |
| B | From your Mac · 2 min ago | Mac and iPhone | **From your Mac, through iCloud** | 29 | Names the whole path. More technical. |
| C | From your Mac · 2 min ago | Mac and iPhone | **Read on your Mac, shown here** | 28 | Keeps the two halves without the two-sentence beat. “Here” is vague in a screenshot. |

### iPhone 4 · Accounts

Claude Personal, Work, Studio and Codex Personal, Work stacked in their provider cards. Depends on: Multi-account on the phone (U3/U4) Direction A had “Every account, every limit”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Claude · Personal, Work, Studio | Accounts | **Each account gets its own rows** | 30 | Describes what you see. The old line opened with “Every”, the structure Limits, LibarAI and AgentMeter all use. |
| B | Claude · Personal, Work, Studio | Accounts | **Work and personal accounts too** | 30 | Warmer, names the real use. “Too” is a weak ending. |
| C | Claude · Personal, Work, Studio | Accounts | **Accounts stack by provider** | 26 | Shortest. Reads like a setting. |

### iPhone 5 · API spend

Spend rows with brand marks, the October period chip and “used”. Moved up from frame 8 to back the subtitle. Depends on: Redesigned spend rows; xAI row checked · was frame 8 Direction A had “API spend beside your plans”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Anthropic API · October | API spend | **API spend next to plan usage** | 28 | Mirrors the subtitle’s two halves. Keeps dollar figures out of the caption (2.3.7 bans prices in screenshots; a spend figure in the UI is fine, in a caption it invites a misread). |
| B | Anthropic API · October | API spend | **API spend below your plans** | 26 | Literal about the layout. |
| C | Anthropic API · October | API spend | **This month’s API spend, too** | 27 | Casual. “Too” again. |

### iPhone 6 · Widget styles

Four widgets in a 2×2: Nested Meter, Vessel Hero, Tightest First, Liquid Level. Depends on: Build 33 or later · was frame 5 Direction A had “Four styles. One per widget.”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | 4 styles · set in Edit Widget | Widget styles | **A different style per widget** | 28 | One sentence. The readout says where to set it. |
| B | 4 styles · set in Edit Widget | Widget styles | **Set the style in Edit Widget** | 28 | An instruction. Repeats the eyebrow, so pair it with the topic eyebrow. |
| C | 4 styles · set in Edit Widget | Widget styles | **Each widget keeps its own style** | 31 | Accurate. The longest of the three at 31 characters. |

### iPhone 7 · Tightest First

Tightest First medium in its critical state, plus the app’s red numeral on Claude Work’s weekly row. Depends on: Red numerals on the phone · was frame 6 Direction A had “The limit that’s closest, first”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Work · weekly · 12% left | Tightest First | **Turns red at 15% left** | 21 | A number, not a promise. Shortest headline in the set, so it holds at thumbnail size. AgentHeadroom’s UI says “Nearly gone”; this doesn’t. |
| B | Tightest First · Work weekly | Tightest First | **The lowest limit goes first** | 27 | About the widget instead of the color. True in build 33 even if the red numeral slips. |

### iPhone 8 · Meters

One Claude card in four meter styles (micro.chip.event, full.segmented.ghost, micro.tube.hue, full.machined.event). Depends on: Meter styles on the phone (U2) · was frame 7 Direction A had “Meters that match your Mac”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Meter style · same as Mac | Meters | **Your meter style carries over** | 29 | Leaves “your Mac” out, since frames 3 and 9 already lean on it. The readout says where the style comes from. |
| B | Meter style · same as Mac | Meters | **Meter style follows your Mac** | 28 | Most precise about the default. |
| C | Meter style · same as Mac | Meters | **Same meter style as your Mac** | 28 | Plainest. |

### iPhone 9 · Refresh

Usage screen in light appearance, pulled down, with the “Asking your Mac” state. Replaces the light-mode-only frame: light mode still shows, and the frame now sells a feature. Depends on: Pull to refresh asks the Mac (U5-B) Direction A had “Just as calm in light mode”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Pull to refresh · asks your Mac | Refresh | **Pull down to ask your Mac** | 25 | Says exactly what the gesture does. “Ask” stays honest about the iCloud delay; it doesn’t promise instant numbers. |
| B | Pull to refresh · asks your Mac | Refresh | **Pull down and your Mac checks** | 29 | Reads as instant, which we can’t promise yet. |

### iPhone 10 · Sign-in

Settings sheet: “From Mac · 2 min ago”, iPhone sync, Explore Demo, About with “Get Headroom for Mac”. Depends on: Redesigned Settings (S1) Direction A had “Nothing to sign in to on your phone”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Settings · iPhone sync | Sign-in | **Nothing to sign in to** | 21 | The old line cut to 21 characters. The thing every phone-side competitor can’t say: they all ask you to sign in on the phone. |
| B | Settings · iPhone sync | Sign-in | **Sign-ins stay on your Mac** | 25 | Positive framing, but frames 9 and 10 would both end on “your Mac”. |
| C | Settings · iPhone sync | Sign-in | **Your phone holds no passwords** | 29 | Concrete. Negative framing. |

### Swap-in frames

### Swap-in x0 · Lock Screen · Lock Screen

Lock Screen at 9:41 with a rectangular widget (Claude 5-hour and weekly), two circular gauges (Codex, Cursor) and the inline line above the clock. **Only if Lock Screen widgets ship** · Depends on: Lock Screen widgets (W4), only if they ship this version · If they ship: insert as frame 6, shift widget styles and Tightest First down one, and move meter styles (frame 8) to this swap list

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Lock Screen · Claude weekly 38% | Lock Screen | **Readable before you unlock** | 26 | Says what the Lock Screen adds over the Home Screen. Avoids Model Usage’s “right next to the clock” and Headroom - AI Usage’s “circular, rectangular, and inline” list. |
| B | Lock Screen · Claude weekly 38% | Lock Screen | **Lock Screen widgets as well** | 27 | Plain label. “As well” leans on frame 2. |
| C | Lock Screen · Claude weekly 38% | Lock Screen | **Readable while locked** | 21 | Shortest. Avoids the word “unlock”, which the lint flags even though here it means the phone, not a paywall. |

### Swap-in x1 · Siri · Siri

Siri answer card: Claude weekly 38%, “As of 2 min ago, from your Mac”. Depends on: Siri and Shortcuts (W9) · Swap for frame 8 if meter styles slip

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Siri · Shortcuts | Siri | **Ask Siri how much Claude is left** | 32 | The approved phrase, verbatim. The shipped App Shortcut phrase must include the app name, so the real spoken line will be longer; match whatever ships. |

### Swap-in x2 · Reminders · Reminders

A Headroom notification on the Lock Screen sent from the Mac’s use-it-up reminder. **Only if notifications through iCloud ship** · Depends on: Notifications through iCloud (planned) · Add as frame 10 if notifications ship this version

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | From your Mac · use-it-up reminder | Reminders | **Reminders from your Mac** | 23 | Only if the iCloud push ships. Shows a Lock Screen notification, which is allowed; it is not a Lock Screen widget. |

### Swap-in x3 · Codex · Codex

Codex card with the plan capsule open: 2 banked resets. Depends on: Banked resets in the envelope (U6-A) · Swap for frame 4 if multi-account slips

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Codex · Pro · 2 banked resets | Codex | **Codex banked resets show too** | 28 | Several competitors show reset credits, so this frame isn’t distinctive. Use only as a fill-in. |

### iPad (13″, 2064 × 2752)

Frames 2–5 reuse the iPhone headlines word for word, so both sets read as one voice.

### iPad 1 · Usage

Full iPad layout: four providers, seven accounts, spend, no empty bottom. Depends on: iPad layout (U8), multi-account Direction A had “Every limit, at full size”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | 7 accounts · 4 providers | Usage | **Room for all seven accounts** | 27 | Carries “Room” from iPhone frame 1 and uses a real count from the fixture. |
| B | 7 accounts · 4 providers | Usage | **Wide enough for all four** | 24 | Shorter. “All four” needs the frame to explain it. |
| C | — | Usage | **Keep up with your AI subscription usage & API spend** | 51 | Your line, verbatim. The wide iPad frame holds it on three lines; an iPhone headline can’t. Over the 32-character thumbnail rule, so it only works on iPad. |

### iPad 2 · Widgets

iPad Home Screen with Nested Meter large and Vessel Hero smalls. Depends on: iPad widget sizes (unverified) Direction A had “Your limits on your iPad Home Screen”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Nested Meter · large | Widgets | **The same numbers, as widgets** | 28 | Same line as iPhone frame 2. One voice across both sets. |
| B | Nested Meter · large | Widgets | **Widgets on the iPad Home Screen** | 31 | Plain label. |

### iPad 3 · Mac and iPad

Mac menu-bar strip plus the iPad capture. Depends on: Clean Mac popover capture Direction A had “Your Mac reads it. Your iPad shows it.”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | From your Mac · 2 min ago | Mac and iPad | **Your Mac does the reading** | 25 | Same as iPhone frame 3. |
| B | From your Mac · 2 min ago | Mac and iPad | **From your Mac, through iCloud** | 29 | Same as iPhone 3B. |

### iPad 4 · Widget styles

The four styles side by side at iPad size. Direction A had “Pick a style for every widget”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | 4 styles · set in Edit Widget | Widget styles | **A different style per widget** | 28 | Same as iPhone frame 6. |
| B | 4 styles · set in Edit Widget | Widget styles | **Set the style in Edit Widget** | 28 | Same as iPhone 6B. |

### iPad 5 · Sign-in

Settings on iPad. Depends on: Redesigned Settings (S1) Direction A had “Nothing to sign in to”.

| Option | Eyebrow (readout) | Topic eyebrow | Headline | Count | Note |
|---|---|---|---|---|---|
| A (rec) | Settings · iPhone sync | Sign-in | **Nothing to sign in to** | 21 | Unchanged from Direction A; it already passed both checks. |
| B | Settings · iPhone sync | Sign-in | **Sign-ins stay on your Mac** | 25 | Same as iPhone 10B. |

## 6. Promotional text, keywords, description

### Promotional text (≤ 170)

| Option | Count | Text | Note |
|---|---|---|---|
| A (rec) | 152 | Keep up with your AI subscription usage and API spend. Grok and Cursor join Claude and Codex, and every account your Mac tracks now shows on your phone. | Your line leads, with “and” for “&” because this is prose. The rest says what’s new. Promo text can change any time without a new version, so swap it after launch. |
| B | 158 | Rebuilt to match Headroom for Mac, with Grok and Cursor next to Claude and Codex. Pick a style for each widget, and pull down to ask your Mac for new numbers. | Leads with the redesign. Good for the first weeks after release. |
| C | 163 | Explore Demo opens every screen and widget with sample numbers, no Mac needed. Your own usage appears once Headroom for Mac is running with the same Apple Account. | For people who don’t have the Mac app yet. Pre-empts “it does nothing” reviews. |
| D | 52 | Keep up with your AI subscription usage & API spend. | Your line verbatim. Uses a third of the space and says nothing about the Mac. |

### Keywords (≤ 100, commas, no spaces)

Name and subtitle words are already indexed, so none repeat: headroom, kyle, zantos, ai, plan, usage, api, spend.

| Option | Count | Keywords | Note |
|---|---|---|---|
| A (rec) | 96 | `claude,codex,grok,cursor,chatgpt,anthropic,openai,limits,quota,widget,tracker,meter,weekly,reset` | Provider names, as the July listing did and passed review. Leaves out every word already in the name and subtitle (headroom, kyle, zantos, ai, plan, usage, api, spend). |
| B | 94 | `claude,codex,grok,cursor,limits,quota,widget,tracker,meter,session,weekly,reset,tokens,cli,mac` | Product names the app works with, but no company names (anthropic, openai, chatgpt). A middle path if review objects to company marks. |
| C | 99 | `limits,quota,widget,tracker,meter,session,weekly,reset,tokens,cli,coding,agent,llm,mac,monitor,cost` | No third-party names at all. The fallback if review objects to provider names. |

### Description A (recommended) · 2524 / 4000

Paste as plain paragraphs with no hard line breaks. The first two sentences are what shows before “more”, so they carry the Mac dependency.

```
Headroom for Mac is a menu bar app that reads your Claude, Codex, Grok and Cursor plan usage using the command-line tools you already sign in to. This app is its iPhone and iPad half. Your Mac sends it a short summary through your iCloud account, and nothing on the phone signs in to a provider.

For each account you get the percentage left in every limit and a short countdown to its reset, like 3d 23h. Rows run 5-hour first, then weekly, then model limits such as Claude’s Weekly (Fable). Grok and Cursor bill by period, so they show period pools instead, and Cursor’s splits into Cursor Models and Other Models. Codex shows any banked resets in its plan capsule. A number turns red when 15% or less is left.

Each account your Mac tracks appears under its provider, with the name you gave it on the Mac. If you track API spend on the Mac, this month’s Anthropic, OpenAI and xAI spend shows below the plans.

Widgets come in small, medium and large, and each one you place keeps its own style. Pick it in Edit Widget:
• Nested Meter: every limit for a provider, nested in one meter
• Vessel Hero: one large number with a small vessel beside it
• Tightest First: the lowest limit leads and the rest follow in order
• Liquid Level: a fill level for each provider
Color can stay on all the time or come on only when a limit runs low. Widgets show the providers you pick on the Mac, using each one’s main account.

The app uses the meter style you chose on your Mac. Settings has an override if you want a different one on the phone.

Pull down on the usage screen to ask your Mac to check again. New numbers appear once the Mac has them, and the app always shows how old the current ones are. Siri and Shortcuts can answer “How much Claude is left?” from the latest reading.

On iPad, the provider cards fill the screen in columns.

The summary from your Mac holds percentages, reset times, plan names, account names and spend totals. Passwords, sign-in tokens and API keys stay on the Mac. This app’s App Store privacy label is Data Not Collected, and the privacy policy is one page: headroom.zantos.co/privacy

To see your own numbers, install Headroom for Mac from headroom.zantos.co, sign in to the same Apple Account on both devices, and turn on Sync usage to iPhone in the Mac app. To look around first, tap Explore Demo for every screen and widget with sample numbers.

Claude, Codex, Grok and Cursor are trademarks of their owners. Headroom is not affiliated with or endorsed by Anthropic, OpenAI, xAI or Anysphere.
```

### Description B (short) · 1115 / 4000

```
Headroom for Mac reads your Claude, Codex, Grok and Cursor plan usage using the command-line tools you already sign in to. This app is its iPhone and iPad half: the Mac sends it a short summary through your iCloud account.

For every account your Mac tracks, you get the percentage left in each limit and a short countdown to its reset. A number turns red at 15% left. If you track API spend on the Mac, Anthropic, OpenAI and xAI spend shows below the plans.

Home Screen widgets come in four styles, chosen per widget in Edit Widget: Nested Meter, Vessel Hero, Tightest First and Liquid Level. Pull down on the usage screen to ask your Mac to check again, or ask Siri how much Claude is left.

Passwords, sign-in tokens and API keys stay on the Mac. This app’s privacy label is Data Not Collected.

To see your own numbers, install Headroom for Mac from headroom.zantos.co and turn on Sync usage to iPhone. Explore Demo shows the whole app with sample numbers first.

Claude, Codex, Grok and Cursor are trademarks of their owners. Headroom is not affiliated with or endorsed by Anthropic, OpenAI, xAI or Anysphere.
```

### Conditional description sentences (only if the feature ships)

| When | Sentence |
|---|---|
| Only if Lock Screen widgets ship (add after the widget paragraph) | Lock Screen widgets show the same numbers before you unlock. |
| Only if the Control Center control ships (same paragraph) | A Control Center control shows one provider’s number and opens the app. |
| Only if notifications through iCloud ship (add after the Siri paragraph) | Reminders you set in Headroom for Mac can also arrive on your phone as notifications. |

Description A with all three: 2743 characters.

## 7. What’s New (version 1.5)

### A (recommended) · 569 characters

```
Version 1.5 catches up with Headroom for Mac.
• Grok and Cursor, next to Claude and Codex
• Every account your Mac tracks, stacked under its provider
• A style for each widget, set in Edit Widget: Nested Meter, Vessel Hero, Tightest First or Liquid Level, colored always or only when low
• Your Mac’s meter style, or one you pick for the phone
• Short reset countdowns, and numbers that turn red at 15% left
• API spend rows and Codex banked resets
• Pull down to ask your Mac to check again
• Siri and Shortcuts: ask how much Claude is left
• A full-screen iPad layout
```

Conditional bullets, appended only if each ships:

- Only if Lock Screen widgets ship: `• Lock Screen widgets`
- Only if the Control Center control ships: `• A Control Center control that shows one provider’s number and opens the app`
- Only if notifications through iCloud ship: `• Reminders from your Mac, delivered to your phone`

### B (paragraph) · 228 characters

```
Version 1.5 catches up with Headroom for Mac, with Grok and Cursor, every account your Mac tracks, four widget styles and a full-screen iPad layout. Pull down to ask your Mac for new numbers, or ask Siri how much Claude is left.
```

## 8. “Get Headroom for Mac” row (About section, no tip jar this round)

Kyle: “make the language shorter so that it’s not 2 rows for the mac link”. All titles fit one line at 402 pt and 16–17 pt text.

| Option | Title | Count | Subtitle | Note |
|---|---|---|---|---|
| A (rec) | **Get Headroom for Mac** | 20 | — | Verb first, names the destination, one line with room to spare. Trailing ↗ marks it as a link out. |
| B | **Get Headroom for Mac** | 20 | headroom.zantos.co | Same title with the address under it. The subtitle makes the cell two lines tall, which is what you asked to avoid. |
| C | **Get the Mac app** | 15 | — | Shortest. Loses the product name, which matters if someone screenshots the row. |
| D | **Headroom for Mac** | 16 | — | Noun only, like a link. Reads as a heading more than an action. |
| E | **headroom.zantos.co** | 18 | — | The address as the label. Honest about where it goes; says nothing about what’s there. |

Optional subtitles (each makes the cell two lines tall): “headroom.zantos.co” (18) · “Where these numbers come from” (29) · “Free download for your Mac” (26).

## 9. Anti-AI pass log

Three passes over first-instinct drafts (v0, kept in `copy-build/v0.py`). `lint.py` greps every string for the Pass 1 banned list and the Pass 2 competitor phrases. **v0: 44 hits. Final set: 2 hits**, both the word “unlock” meaning the phone’s lock in the conditional Lock Screen copy (“Readable before you unlock”, “before you unlock.”). Option C of that frame, “Readable while locked”, avoids it if Kyle prefers. The only question mark in the final copy is the quoted Siri question.

**Pass 1 · AI tells (brief checklist plus extensions)**

- Em dashes or en dashes used for rhythm or drama
- “Not just X, it’s Y” and “X, not Y” antithesis
- Tricolon lists written for rhythm rather than content
- Fragment drumbeats (“Fast. Simple. Private.”, “Every account. Every limit.”)
- Banned words and phrases: Whether you’re, Say goodbye to, Meet, Introducing, unlock, elevate, supercharge, seamless(ly), effortless(ly), peace of mind, game-changer, empower, at your fingertips, never miss, stay on top of, all in one place, designed for, built for
- Generic adjectives: powerful, beautiful, stunning, intuitive, sleek, robust
- Rhetorical questions, exclamation marks, emoji
- Added: softeners and intensifiers (just, simply, right on / right beside, exactly, complete)
- Added: “your way”, “make it yours”, “the way you want”
- Added: “automatically” or “no need to” standing in for a mechanism you could name
- Added: mirrored two-sentence pairs (“Your Mac reads it. Your iPhone shows it.”) and semicolon pairs
- Added: closers that sum up or flatter the reader (“Made for people who…”)
- Added: idioms that don’t translate (join the party, caught off guard)
- Added: sentence case everywhere; no all-caps except the provider names’ own casing

**Pass 2 · sounds like the others**

- Every phrase and structure in the competitor table (27 rows), checked by hand and by lint.py
- Openers: no “Headroom keeps / brings / helps”, no “X is the iPhone companion for”
- Captions: no headline opening with “Every” or “All”, no “X, one Y”, no “Your X, on Y”
- Subtitles: not an ampersand noun list, not verb-led “Track / Monitor”
- Privacy: no “by design” header, no “no servers, no analytics, no account” list
- Look: eyebrows not in Exevio’s uppercase category-label style

**Pass 3 · claims, honesty and voice**

- Every claim checked against the approved feature list and APPSTORE.md §5.6 (see the claims table)
- Nothing promises speed we can’t show: iCloud delay is unverified, so “ask”, not “now”
- No prices or dollar figures in screenshot captions (Guideline 2.3.7)
- No third-party names in the subtitle (Guideline 2.3.7)
- Terms match the app: plan, plan chip, Edit Widget, Explore Demo, Sync usage to iPhone, Nested Meter, Vessel Hero, Tightest First, Liquid Level, Only when low
- Read the ten headlines in order: no two neighbors end the same way
- Headlines ≤ 32 characters; the hero ≤ 27 so it holds at search-thumbnail size
- Scope update 2026-10-04: version 1.5; Lock Screen widgets and Control Center become conditional claims

### Captions, draft by draft

| Frame | v0 | After pass 1 (why) | After pass 2 (why) | Final (pass 3) |
|---|---|---|---|---|
| i1 | Know exactly what’s left — before the reset | Know what’s left before each reset (Em dash for drama; “exactly” is an intensifier.) | Room left on four AI plans (“Know” is Exevio’s name and caption (“Know your limits.”); “what’s left” is AgentMeter’s caption (“See what’s left, anytime”).) | **Room left on four AI plans** (Kept. 26 characters.) |
| i2 | Your limits, right on your Home Screen | Your limits on your Home Screen (“Right” intensifier.) | The same numbers, as widgets (“Your X, on Y” is Limits’ caption (“Your AI limits, always in view.”) and our current subtitle. Exevio says “Put it where you look.”) | **The same numbers, as widgets** (Kept.) |
| i3 | Your Mac reads it. Your iPhone shows it. | Your Mac does the reading (Mirrored two-sentence beat; one plain sentence instead.) | Your Mac does the reading (Checked against QuotaKit (“your iPhone becomes a clean mobile dashboard”). No overlap.) | **Your Mac does the reading** (Kept. Footer “Requires Headroom for Mac” stays.) |
| i4 | Every account. Every limit. | Each account gets its own rows (Fragment drumbeat.) | Each account gets its own rows (Opening with “Every” is the LibarAI / Limits / AgentMeter structure; already gone.) | **Each account gets its own rows** (Kept. Depends on multi-account.) |
| i5 | All your spend, in one place | API spend beside your plans (“All in one place” is on the banned list.) | API spend next to plan usage (Echoes the subtitle’s two halves. Avoids QuotaKit’s “See every dollar spent”.) | **API spend next to plan usage** (Eyebrow drops the dollar figure (2.3.7).) |
| i6 | Four styles. Your way. | A style for each widget (Fragment drumbeat; “your way”.) | A different style per widget (Headroom: Weekly Usage owns “Make it yours.” Reworded so “different” carries the point at thumbnail size.) | **A different style per widget** (Kept.) |
| i7 | Never get caught off guard | The limit that’s closest, first (“Never” promise; idiom.) | Turns red at 15% left (Fear framing is everyone’s opener; “closest” was ambiguous. Avoids AgentHeadroom’s “Nearly gone”.) | **Turns red at 15% left** (Kept. Threshold matches the Mac’s Critical tier (≤15% left).) |
| i8 | Seamlessly matches your Mac | Meters that match your Mac (“Seamlessly”.) | Meters that match your Mac (No overlap found.) | **Your meter style carries over** (Three nearby headlines ended on “your Mac”; this one didn’t need to.) |
| i9 | Just as calm in light mode | Pull down to ask your Mac (“Just” softener; a frame that only says “light mode exists” sells nothing. Now the refresh feature, shot in light appearance.) | Pull down to ask your Mac (No overlap; no competitor’s phone can ask a Mac to check.) | **Pull down to ask your Mac** (“Ask” rather than “check now”: the iCloud delay is unverified.) |
| i10 | Private by design | Nothing to sign in to on your phone (Stock phrase.) | Nothing to sign in to on your phone (“Private by design” is used by five competitors; already gone.) | **Nothing to sign in to** (35 → 21 characters so it holds at thumbnail size.) |

### Pass 1 · field changes

| Field | Before | After | Why |
|---|---|---|---|
| Subtitle | Your AI limits, at a glance | AI plan usage and API spend | Your direction (usage and spend). “At a glance” is a stock phrase. |
| Promo | Meet the new Headroom: … four beautiful widget styles. Your AI limits, at your fingertips. | Keep up with your AI subscription usage and API spend. Grok and Cursor join Claude and Codex, every account your Mac tracks shows on your phone, and each widget gets its own style. | “Meet”, “beautiful”, “at your fingertips”. |
| Description | …you have left — on your iPhone, your iPad and your Home Screen. | …you have left on your iPhone, iPad and Home Screen. | Em dash; the triple “your” is a rhythm device. |
| Description | Your Mac does the reading; your iPhone simply shows the result. | (moved into the opener as one sentence) | Semicolon mirror pair; “simply”. |
| Description | It’s not just a widget — it’s your usage at a glance. | (deleted) | “Not just X, it’s Y” with an em dash. |
| Description | WIDGETS, YOUR WAY / SEAMLESSLY MATCHES YOUR MAC | WIDGET STYLES / SAME LOOK AS YOUR MAC | “Your way”, “seamlessly”. (Pass 2 removes the caps headers entirely.) |
| Description | Your Mac’s meter style comes along automatically | The app uses the meter style you chose on your Mac. | “Automatically” stood in for the mechanism. |
| Description | …Siri answers from the latest reading, no need to open the app. | Siri and Shortcuts can answer “How much Claude is left?” from the latest reading. | “No need to” filler. |
| Description | No servers. No accounts. No analytics. | Headroom has no servers, accounts or analytics. | Fragment drumbeat. (Pass 2 replaces the sentence.) |
| Description | Not ready yet? Explore Demo lets you try everything… | To look around first, tap Explore Demo… | Rhetorical question. |
| Description | API spend … right beside your plans | …shows below the plans | “Right” intensifier; “below” is literally where it is. |
| Description | Whether you live in Claude Code or bounce between four tools, Headroom gives you peace of mind about what’s left. | (deleted) | “Whether you…”, “peace of mind”, a flattering closer. |
| What’s New | A complete redesign that seamlessly matches Headroom for Mac! | Rebuilt to match Headroom for Mac. | Exclamation mark, “seamlessly”, “complete”. |
| What’s New | Grok and Cursor join the party | Grok and Cursor, next to Claude and Codex | Idiom. |
| What’s New | Every account. Every limit. | Every account your Mac tracks, stacked under its provider | Drumbeat. |
| What’s New | Four beautiful widget styles, your way | A style for each widget, set in Edit Widget: … | Adjective; “your way”. |
| What’s New | Never miss a reset with red alerts when you’re nearly out | Short reset countdowns, and numbers that turn red at 15% left | “Never miss”; “alerts” overclaimed a color change as a notification. |
| What’s New | A stunning new iPad layout | A full-screen iPad layout | Adjective. |

### Pass 2 · field changes

| Field | Before | After | Why |
|---|---|---|---|
| Description opener | Headroom shows how much of your Claude, Codex, Grok and Cursor plans you have left… | Headroom for Mac is a menu bar app that reads your Claude, Codex, Grok and Cursor plan usage… | Three lookalikes open “Headroom keeps / brings / helps”; “how much you have left” is Limits’ and Headroom - AI Usage’s line. |
| Description | All-caps section headers | Plain paragraphs that lead with their subject | Every lookalike uses caps headers; AgentHeadroom’s “WHAT IT SHOWS” is close to our “WHAT YOU GET”. |
| Description | Every account you track on your Mac, side by side | Each account your Mac tracks appears under its provider | “Side by side” is Model Usage’s. |
| Description | Live countdowns to every reset | a short countdown to its reset, like 3d 23h | “Live” is Model Usage, Limits, Exevio; it also overclaims for a mirror. |
| Description | …a number that turns red when a limit is nearly gone | A number turns red when 15% or less is left. | “Nearly gone” is AgentHeadroom’s in-app label. |
| Description | PRIVATE BY DESIGN / Headroom has no servers, accounts or analytics. | The summary from your Mac holds percentages, reset times, plan names, account names and spend totals. Passwords, sign-in tokens and API keys stay on the Mac. This app’s App Store privacy label is Data Not Collected… | Five listings say “by design”; seven use the no-servers list. Listing what travels is ours alone. |
| Description | REQUIRES HEADROOM FOR MAC / … is a free download …  | To see your own numbers, install Headroom for Mac from headroom.zantos.co, sign in to the same Apple Account on both devices, and turn on Sync usage to iPhone in the Mac app. | Avoids QuotaKit’s “Install …, turn on iCloud Sync, and your iPhone becomes …” payoff clause. Ends on the setting’s exact name instead. |
| Eyebrows | Topic labels (Headroom, Widgets, Accounts…) | Readouts (Claude · 5-hour · 72% left…) | Exevio’s frames use uppercase topic eyebrows on the same dark ground. |
| Subtitle | AI plan usage and API spend | (kept) | Checked against 15 shelf subtitles. Nearest is Model Pulse’s “AI usage, limits & spend”, an ampersand list. |

### Pass 3 · field changes

| Field | Before | After | Why |
|---|---|---|---|
| Description | Pull to refresh asks your Mac to check now | Pull down on the usage screen to ask your Mac to check again. New numbers appear once the Mac has them… | The phone-to-Mac request goes through iCloud; the delay is unverified. |
| Description | …every screen says how old the numbers are | …the app always shows how old the current ones are | Widget freshness display isn’t confirmed for every style. |
| Description | (none) | Widgets show the providers you pick on the Mac, using each one’s main account. | Earlier decision: widgets follow the main account. Saying so heads off “where are my other accounts” reviews. |
| Description | …a free download at headroom.zantos.co | install Headroom for Mac from headroom.zantos.co | Keeps prices out of the listing; nothing is lost. |
| Promo | …every account your Mac tracks shows on your phone, and each widget gets its own style. | …and every account your Mac tracks now shows on your phone. | Three-item list cut to two. |
| Promo | AI subscription usage & API spend | AI subscription usage and API spend | Prose wants “and”. Option D keeps your “&”. |
| What’s New | Rebuilt to match Headroom for Mac. | Version 1.5 catches up with Headroom for Mac. | Scope update: the iPhone app is 1.5 to match the Mac. |
| All fields | Lock Screen widgets listed as not claimable | Conditional caption frame, description sentence and What’s New bullet, each marked “only if it ships” | Scope update 2026-10-04. |
| Captions | Spend eyebrow “Anthropic API · $142.67 · October” | Anthropic API · October | Guideline 2.3.7: no prices in screenshots. A spend figure isn’t a price, but a caption is the wrong place to test that. |

### v0 drafts (for reference)

```
SUBTITLE: Your AI limits, at a glance
PROMO: Meet the new Headroom: Grok and Cursor join Claude and Codex, every account you track, and four beautiful widget styles. Your AI limits, at your fingertips.

Headroom shows how much of your Claude, Codex, Grok and Cursor plans you have left — on your iPhone, your iPad and your Home Screen. Your Mac does the reading; your iPhone simply shows the result.

WHAT YOU GET
• Every account you track on your Mac, side by side
• 5-hour, weekly and model limits, plus Grok and Cursor billing-period pools
• Live countdowns to every reset, and a number that turns red when a limit is nearly gone
• API spend for Anthropic, OpenAI and xAI, right beside your plans
• Codex banked resets in the plan capsule
• Pull to refresh asks your Mac to check now

WIDGETS, YOUR WAY
Choose a style for each widget in Edit Widget: Nested Meter, Vessel Hero, Tightest First or Liquid Level. Keep color on, or let it appear only when a limit runs low. It’s not just a widget — it’s your usage at a glance.

SEAMLESSLY MATCHES YOUR MAC
Your Mac’s meter style comes along automatically, or pick one just for your phone.

ASK SIRI
“How much Claude is left?” Siri answers from the latest reading, no need to open the app.

PRIVATE BY DESIGN
No servers. No accounts. No analytics. Your Mac sends a small summary through your own iCloud, and your passwords, tokens and API keys never leave it.

REQUIRES HEADROOM FOR MAC
Headroom for Mac is a free download at headroom.zantos.co. Not ready yet? Explore Demo lets you try everything with sample data.

Whether you live in Claude Code or bounce between four tools, Headroom gives you peace of mind about what’s left.

A complete redesign that seamlessly matches Headroom for Mac!
• Grok and Cursor join the party
• Every account. Every limit.
• Four beautiful widget styles, your way
• Never miss a reset with red alerts when you’re nearly out
• A stunning new iPad layout
```

## 10. Claims that depend on the approved round shipping (APPSTORE.md §5.6 style)

“Approved” means Kyle approved the feature for the redesign; it still has to be in the submitted 1.5 build before the copy goes live.

| Claim | Where it appears | Needs | If it slips | Status |
|---|---|---|---|---|
| Grok and Cursor on the phone | iPhone 1 (“four AI plans”), description, promo A/B, What’s New | Redesign; Grok and Cursor period rows checked on a device | Frame 1 → “Room left before each reset”; drop Grok and Cursor from promo | approved |
| Every account your Mac tracks; account names | iPhone 4, iPad 1 (“seven accounts”), description (two places), promo A, What’s New | Additive multi-account envelope field plus phone UI (U3, U4) | Swap frame 4 for the banked-resets frame; iPad 1 → “Wide enough for all four”; drop “account names” from the privacy paragraph | approved |
| Meter style follows the Mac, with a phone override | iPhone 8, description, What’s New | U2-C: MeterStyle in the envelope plus a phone picker | Swap frame 8 for the Siri frame | approved |
| Red at 15% left; short countdowns like 3d 23h | iPhone 7, description, What’s New | Redesign (P15, P19); phone uses the Mac’s ≤15% Critical threshold | Frame 7 → “The lowest limit goes first” (widget behavior, true in build 33) | approved |
| API spend rows incl. xAI, for this month | iPhone 5, description, What’s New | Redesigned spend rows; an xAI row checked on a device; spend period is the calendar month | Drop “xAI”; say “for the current period” | approved |
| Codex banked resets in the plan capsule | Description, What’s New, swap frame x3 | Banked resets added to the envelope; capsule on the phone (U6-A) | Delete the sentence and the bullet | approved |
| Four widget styles; Only when low | iPhone 2/6, iPad 2/4, description, promo B, What’s New | Build 33 or later (true in the repo today) | — | true in repo |
| Full-screen iPad layout | iPad 1, description, What’s New | U8 iPad layout | Lead the iPad set with the widget frame; drop the iPad sentence and bullet | approved |
| Pull down asks your Mac to check again | iPhone 9, description, promo B, What’s New | U5-B spike: the phone-to-Mac request through iCloud | Frame 9 → light-mode usage screen with “Room left before each reset”; drop the sentence | approved |
| Siri and Shortcuts: “How much Claude is left?” | Swap frame x1, description, What’s New | W9 App Intents. App Shortcut phrases must include the app name, so the spoken phrase will be longer | Quote the exact shipped phrase, or drop | approved |
| Lock Screen widgets | Conditional frame x0, conditional description sentence, conditional What’s New bullet | W4, only if ready for this release | Leave all three out | conditional |
| Control Center control | Conditional description sentence, conditional What’s New bullet | W6, only if ready for this release; how often its value refreshes is unverified | Leave both out | conditional |
| Notifications from the Mac’s reminders through iCloud | Conditional frame x2, description sentence, What’s New bullet | N3 / S5-C CloudKit push; planned, only if it ships | Leave all three out | conditional |
| “Sync usage to iPhone” setting name | Description (both) | Rename G8 (today it reads “Sync snapshot to iPhone”) | Use whichever name ships | approved |
| Claude’s “Weekly (Fable)” model row | Description A | Anthropic’s current /usage label | Edit with the next version if Anthropic renames it | true today |
| Cursor pools “Cursor Models” and “Other Models” | Description A | Mac Cursor parser (true today) | — | true today |
| Data Not Collected privacy label | Description (both) | True today; re-check if notifications add CloudKit | Update the label first, then the copy | true today |

Never claimed: Live Activities · Apple Watch · StandBy-specific layouts · The phone signing in to a provider · Usage history or pace (Headroom has neither).

## 11. Open questions for Kyle

1. **Eyebrows (decision E).** Readouts, sentence-case topics, or none? Exevio’s Headroom already owns the uppercase-topic look on dark frames.
2. **Keywords A or B.** A names Anthropic, OpenAI and ChatGPT as the July listing did; B keeps only the product names the app works with.
3. **Name a model row in the description?** “Weekly (Fable)” is concrete, but the description can only change with a new version, so it dates when Anthropic renames the model.
4. **Siri phrase.** App Shortcut phrases must contain the app name, so the spoken line will be longer than “How much Claude is left?”. The copy should quote whatever ships.
5. **Setting name.** The description says “Sync usage to iPhone” (rename G8). If the rename doesn’t ship, it stays “Sync snapshot to iPhone”.
6. **Spend period.** The description says “this month’s” spend. Correct if every spend row is calendar-month; otherwise “for the current period”.
7. **Trademark line.** The description ends with a one-line “not affiliated” notice. Most competitors carry one; it is the one deliberately shared line. Keep or cut?
8. **“Room” as a house word.** Frame 1 and iPad 1 both use “Room left / Room for”. It ties to the name without punning on it; say if it reads too cute.

