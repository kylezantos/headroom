# iOS parity inventory: Mac popover + Settings → iPhone/iPad (2026-10-03)

Read-only audit of `rome-v1` at `06d082af` (+ uncommitted `BUGS.md`). Every code claim cites
`file:line`; "unverified" marks inference. Paths are under `Sources/` unless they start with
`Tests/`, `docs/` or `.context/`.

**Legend.** Portability: **CORE** = Core-ready (logic/tokens already in Core and compiled into
iOS, or Foundation-only and addable), **PORT** = needs a SwiftUI move/port (AppKit or Mac-only
view code in the way), **ENV** = needs a new optional envelope field, **MAC** = Mac-only (reason
given). Effort is scope, not time: **S** = one view or one Core helper + its test; **M** = a
Core+UI pair or several views; **L** = cross-cutting (envelope + projector + Mac + phone + size
budget). ID prefixes: P popover, M motion, S Settings, N notifications, D data/envelope,
B build plumbing, G other phone gaps, W widgets/surfaces.

Captures used: `.context/ios-audit/side-by-side.png`, `ios-{usage,stale,waiting,settings}-*.png`,
`popover/popover-{multi-mixed,banked-resets,capability-failure}-*.png`,
`.context/ios-parity/renders/ipad-current-light.png`,
`renders/style-{full.segmented.ghost,micro.tube.hue}/popover-multi-2-*.png`,
`renders/style-full.chip.solid/settings-{appearance,about,notifications,widgets}-*.png`.

---

## 0. Headline findings

1. **`MeterGauge` is already portable.** It imports only SwiftUI + HeadroomCore
   (`HeadroomApp/UI/MeterGauge.swift:1-2`) and reads colors only through `ProviderStyle`, which
   is also AppKit-free (`HeadroomApp/UI/ProviderStyle.swift:1-2`). Every value both read lives in
   `HeadroomCore/Models/MeterStyle.swift` and `BrandColorValues.swift`, and those two files are
   *already* compiled into both iOS targets (`project.yml:102,109,142,149`). Moving the two files
   into a shared UI folder needs no new Core plumbing.
2. **The AppKit lives in the row, not the meter.** In `UsageBarView` the percent column is
   measured with `NSFont` (`UsageBarView.swift:144-147`), optical alignment uses `NSFont`
   (`OpticalLeading.swift:1,52-55,148-196`), and `HeadroomMotion` imports AppKit for
   `NSApp.currentEvent` and `CAMediaTimingFunction` (`HeadroomMotion.swift:1,122-134`). The shared
   widget UI already ships CoreText twins: `widgetCapHeightCentered` / `widgetOpticalLeading`
   (`HeadroomWidgetSharedUI/HeadroomWidgetTypography.swift:220,230`).
3. **The two rows draw different types.** The phone renders `WidgetWindowSummary`, the Mac renders
   `UsageWindow`. One small Core adapter (`UsageWindow(widgetSummary:)`) lets the popover row
   render envelope data unchanged. The envelope already carries `utilization`, `resetSchedule`,
   per-window `freshness` and `observedAt` (`WidgetSnapshotModels.swift:269-416`).
4. **The biggest data gap is multiple accounts.** The phone envelope carries only each
   provider's *primary* account (`Engine/UsageStore.swift:1087-1103`). Stacked accounts, Make Main
   order, per-account plan and Stale, and per-account sign-in sentences all need one additive
   `accounts` field. At the tested 20-per-provider envelope that is roughly 57 KB (estimate).
   That is inside iCloud KVS's documented 1 MB, but well into the "tens of KiB" range Apple DTS
   says to avoid, so the design has to slim or split the payload (D9).
5. **Display preferences: phone-local or mirrored from the Mac.** Meter style, percentage mode
   and title ink can be phone-local (no envelope change) or mirrored from the Mac (one optional
   `display` field). This is the main decision for the options doc.
6. **Design drift on the phone today:** a "Low" chip the Mac dropped; an amber attention notice
   that breaks DESIGN.md rule 4; system-blue tint everywhere (no AccentColor asset); stale copy
   ("Sync snapshot to iPhone", "renewal dates"); window order not normalized; "Resets in 2d 23h"
   where the Mac shows a bare "2d 23h"; one stale UI test.
7. **Notifications:** nothing over KVS is real-time on the phone. The honest choices are no phone
   notifications, best-effort local scheduling from the last snapshot, or a CloudKit-subscription
   push. That last one is the only path that matches the Mac and it is large (N3).
8. **Tip jar:** the Mac links out to Stripe (`HeadroomCore/Settings/AboutLinks.swift:26-36`).
   App Review Guideline 3.1.1 says tipping the developer uses in-app purchase. 3.1.1(a) exempts
   external links on the **US storefront only**. Checked against the live guidelines page today.
9. **Three color layers sit over the same Core tokens:** `ProviderStyle` (Mac),
   `HeadroomTheme` (iOS), and `HeadroomWidgetStyle` (`HeadroomWidgetSharedUI.swift:7-96`).
   Consolidating them is the cheapest systemic win.

---

## 1. Meter rendering (P1–P12)

What the Mac draws (captures): the default `micro.chip.event` is a 32×5 chip beside the numeral.
It is grey while healthy and turns amber or red at Low/Critical; at Critical the track tints red
(pink in light). `full.segmented.ghost` is a 14-cell row with a raised, fully colored tip and dim
body cells. `micro.tube.hue` is a 5×16 vertical tube.

| ID | Element | Mac source | iPhone today | Portability | Effort | What it takes |
|---|---|---|---|---|---|---|
| P1 | `MeterStyle` model: Format {Full, Micro} × Shape {Chip, Machined, Segmented, Tube} × Fill {Always colored, Glass, Ghost, Only when low, Fade}. Default `micro.chip.event`. Tube resolves to Chip under Full. Persisted as the launch token `format.shape.fill`. | `Models/MeterStyle.swift:3-61` (labels 9-60), default `70-74`, token parser `82-90`, `resolved(for:)` `34-36` | none. One fixed renderer: a full-width capsule that is always colored (`HeadroomIOS/Views/UsageBarView.swift:67-75`) | CORE (file already in iOS: `project.yml:109`) | S | Store a phone-local launch token (`@AppStorage`), or read it from D2 `display.meterStyle`. |
| P2 | Geometry tokens. Micro chip 32×5. Micro machined 32×6, inset 1. Micro cells 6×5, gap 2, r1.5 (5 cells = 38pt). Micro tube 5×16. Full track 8 (machined inset 1.5). Full cells: 14 cells, 8pt tall, gap 3.5, r2.5, tip 10 standing proud. Min fill: Full 6 / Micro 3, floored at the fill's thickness for rounded ends. Caps: Full 3×10 r1.5 flush with the fill end; Micro 2×7 square, straddling it. | `MeterStyle.swift:100-307` (101-112, 129-137, 233-244, 264-266, 296-306) | 9pt capsule, 9pt minimum fill (`UsageBarView.swift:75,123-126`) | CORE | S | Comes free with P5. The 278pt nominal run (`MeterStyle.swift:139-143`) assumes the 346pt popover card; on phone, Full rows just get wider and Micro stays fixed size. |
| P3 | Recipes: cell count 5/14 (`424-429`), lit cells (`431-435`), tip/body cell recipe (`522-545`), fill recipe with freshness gate (unavailable → none, stale → staleGrey) (`547-568`), OKLCH ramp stops: Full eased, Micro mixed by surface (`437-520`) | `MeterStyle.swift:418-570` | none | CORE | — | Already compiled. |
| P4 | Color tokens. Severity text tier (`BrandColorValues.swift:796-832`). Fill tier, vivid in light and swapped to text tier under Increase Contrast (`865-911`). `criticalText` (`822-824`). `criticalBarTrack` OKLCH L .391/.905, C .055/.045, h 28.1 (`539-548`). Glass A/B (`475-481`). Well bg/shadow/top shade/lip/hairline (`487-503,645-655`). Ticks off/glass/cap (`505-527`). Stale fill = chroma ×0.35 (`576-590`). Segment body ×0.70 (`627`). Full unlit cells ×0.70 (`633`). Full ramp ±0.14 L, chroma ×0.65, ease 1.3 (`638-640`). Dark flat-fill attenuation .85 (.95 critical) (`663-666`). Quarter marks .11/.14 (`670-672`). Ghost body .18/.22 dark, .30/.34 light (`679-686`) | `Models/BrandColorValues.swift` | Uses only severity text + fill and `barTrack` (`HeadroomIOS/DesignSystem/HeadroomTheme.swift:15-32,81-83`) | CORE (`project.yml:102`) | — | Already compiled. The gap is the call layer (P9). |
| P5 | `MeterGauge` renderer: frame per format/shape (`MeterGauge.swift:38-82`), continuous gauge with fill always in the tree (AR1) and cap overlay (`84-125`) | `MeterGauge.swift:7-450` | none | PORT (pure SwiftUI, move only) | S | Move to a shared folder (B4). It reads `\.colorSchemeContrast` (`28-30`), which is fine on iOS. |
| P6 | Continuous variants. Chip/tube capsule track; at Critical the track takes the critical hue unless Unavailable (`156-165`). Machined well: Full gets a 1.4pt top shade, 1pt bottom lip, 0.5 hairline; Micro gets a 0.75 shadow stroke (`127-154`). Fill has a rounded end (MX1) and clips to the track (`181-208`). Glass/Ghost cap marker (`214-230`). Fill bodies: stale grey / solid / glass+neutral gradient / ghost / ramp (`233-269`) | `MeterGauge.swift:127-269` | none | PORT | — | Part of P5. |
| P7 | Segmented: tip cell is the reading, body cells at 0.70, Full off-cells at 0.70, stale exempt, OKLCH ramp per cell (`282-390`) | `MeterGauge.swift:282-390` | none | PORT | — | Part of P5. |
| P8 | Quarter marks on Full Machined only (25/50/75%, 1pt) | `MeterGauge.swift:392-401`; `MeterStyle.swift:94-96` | none | PORT | — | Part of P5. |
| P9 | `ProviderStyle` color layer: meter inks, severity, stale, ramp, plan/title/criticalText, brand accent, `accountTitleInk` environment key (`ProviderStyle.swift:7-327`; env `299-327`) | `ProviderStyle.swift` | iOS duplicates part of it as `HeadroomTheme` (`HeadroomTheme.swift:3-88`); widgets have a third copy (`HeadroomWidgetSharedUI.swift:7-96`) | PORT (no AppKit) | S | Move to shared. `svgResourceName` (`10-18`) feeds only the Mac SVG path; iOS keeps its asset-catalog marks. Retire `HeadroomTheme`'s color functions in favour of the shared layer. |
| P10 | Settings-only miniature swatch mode (`miniatureSegmentCount`) | `MeterGauge.swift:12-22,271-280`; `MeterStyle.swift:174-229` | none | PORT | — | Needed only if the phone gets the Meter Style picker (S4). |
| P11 | Increase Contrast fill-tier swap | `MeterGauge.swift:25-30,408-414` | Yes, for its one bar (`HeadroomIOS/Views/UsageBarView.swift:25-29`) | CORE | — | Parity already. |
| P12 | Reduce Transparency / high legibility on the tile (`NSWorkspace...ShouldIncreaseContrast`, `NSColor` separator/control fills) | `RaisedTile.swift:34,57-70,85` | iOS tile is opaque (`Elevation.swift:23-29`) | MAC (AppKit APIs) | — | Not needed if the iOS tile surface stays (P29). |

---

## 2. Row anatomy (P13–P28)

Mac row (capture `side-by-side.png`, right): `5-hour  3h 11m ········ [chip] 72% left`.
iPhone row (left): `Weekly  Resets in 2d 23h ········ 38% left` over a 9pt full-width bar.

| ID | Element | Mac source | iPhone today | Portability | Effort | What it takes |
|---|---|---|---|---|---|---|
| P13 | Layout. **Full:** label row, then the gauge 7pt below; the reset drops to a subline only when it can't fit inline (`ViewThatFits`) (`UsageBarView.swift:114,361-384`). **Micro:** always one line, degrading full countdown → short ("22h") → truncated label (`402-430`). Row gap Micro 10 / Full 12 (`ProviderCardView.swift:1649`). | `UsageBarView.swift:331-430` | Label row + bar below, spacing 7, rows 14 apart (`HeadroomIOS/Views/UsageBarView.swift:33-76`; `ProviderTileView.swift:81`). Roughly "Full chip solid" with different type. | PORT | M | Port `UsageBarView` with the swaps in P16/P27/M13. Decide whether Micro's single line suits a 390pt phone (it does in width; check Dynamic Type). |
| P14 | Label: `WindowKind.displayName` ("5-hour", "Weekly", "Fable", billing labels), 13pt medium, `meterLabelInk` (#EBEBF5 dark / #1D1F24 light @ .90) (`UsageBarView.swift:432-441`; `BrandColorValues.swift:448-450`) | `UsageModels.swift:53-63` | Same text (`HeadroomIOS/Views/UsageBarView.swift:104-121`), `.subheadline` semibold, `.primary` | CORE text, PORT type | S | — |
| P15 | Countdown: bare "3d 23h" from `resetSchedule.meterResetLine` (`MeterStyle.swift:572-578` → `Countdown.swift:68-85`); short form "3d" in tight Micro (`Countdown.swift:45-58`); "now" within 60s; 11pt mono `countdownInk` (dark .66 / light .72, `BrandColorValues.swift:452-460`); on a live Critical row the ink steps up to `.secondary` (`UsageBarView.swift:505-507`); unresolved resets print nothing | `UsageBarView.swift:177-180,461-479` | "Resets in 2d 23h" (tooltip form) via `MirrorPresentation.resetText` (`MirrorPresentation.swift:55-65`), `.caption` mono tertiary. Unresolved resets print "Available" or "Reset info unavailable" (`Countdown.swift:96-113`). | CORE (Countdown + MeterStyle already in iOS) | S | Switch to `meterResetLine`. Decide whether the phone keeps "Available" (G14). |
| P16 | Percent numeral: 18pt semibold mono in a trailing column sized to "100%" (`UsageBarView.swift:109,137-147,484-497`). Ink: live Critical = `criticalText` red (dark 1.00/.40/.35, light .82/.14/.11); dimmed = `.secondary`; otherwise `.primary` (`515-523`) | as left | `.headline` mono, always `.primary`; the whole row drops to 0.68 opacity when dimmed (`HeadroomIOS/Views/UsageBarView.swift:57-59,77`) | PORT (`NSFont` width) | S | Measure with `UIFont.monospacedDigitSystemFont` or `HeadroomWidgetFontMetrics`, or reserve the width with a hidden "100%". |
| P17 | Suffix "left"/"used": 11pt `tertiaryText`, 5pt gap, natural width; slot kept for "—" rows so columns don't shift (`UsageBarView.swift:39-72,494`) | as left | "left" in `.caption` tertiary, dropped on "—" so the column shifts (`HeadroomIOS/Views/UsageBarView.swift:60-64`) | PORT | S | Comes with P13. |
| P18 | Percentage mode Left/Used flips the numeral, suffix and meter direction; severity stays based on remaining (`UsageModels.swift:162-191`; `UsageBarView.swift:151-157`) | `Settings/Preferences` via `UsageStore.swift:112,457-460` | Always "left" | CORE + (local pref or ENV D2) | S | `percentUsed` needs `utilization`. v3 rows carry it; migrated rows are nil, so derive `100 − percentRemaining` (`WidgetSnapshotModels.swift:274-276`). |
| P19 | Critical = red numeral plus the meter's own critical signals. No "Low" chip (AP1) | `UsageBarView.swift:233-240` | "Low" chip on Critical rows (`HeadroomIOS/Views/UsageBarView.swift:51-56,95-102`; `MirrorPresentation.swift:82-84`; test `Tests/HeadroomCoreTests/MirrorPresentationTests.swift:70-74`; `BUGS.md:674-677`) | CORE | S | Remove the chip and the test; add red numeral ink. |
| P20 | Row order: 5-hour, then weekly/billing, then model rows (`UsageModels.swift:530-559`), applied at `UsageStore.swift:1045-1067` | as left | Envelope order as-is (`MirrorPresentation.swift:40-42`). The projector reads the unsorted `snapshot(for:)` (`UsageStore.swift:1090`). Real Claude data arrives 5-hour first (`ClaudeUsageParser.swift:154-166`); Codex arrives in slot order (`CodexProvider.swift:58-74`). Captures show Weekly first only because the DEBUG preview seed is hand-ordered that way (`CompanionPreviewSeed.swift:55-79`). | CORE | S | Add `WidgetProviderSummary.fiveHourFirstWindows` (same rank as `UsageModels.swift:538-544`) and use it on the phone. Widgets keep `displaySubscriptionWindows` (weekly first, `WidgetSnapshotModels.swift:158-167`). |
| P21 | Stale window: Full shows "· Last known 4 min ago" (11pt medium mono tertiary, fades in after the fill lands); Micro moves it to the tooltip (`UsageBarView.swift:165-175,446-458,548-551`). The gauge keeps its hue at chroma ×0.35; the numeral goes `.secondary`. | as left | "Last known" with no age, `.caption2` semibold; fill is `Color.secondary @ .48`; row at 0.68 (`HeadroomIOS/Views/UsageBarView.swift:22-30,38-42,77`; `MirrorPresentation.swift:67-76`) | CORE (`observedAt` is on the wire: `WidgetSnapshotModels.swift:280,389`) | S | Comes with P13. Micro has no tooltip on iPhone, so either show the age inline or give up the state line. |
| P22 | Unavailable window: "—", fill fades out in place (doesn't shrink), suffix slot kept, neutral track (no red), "Unavailable" | `UsageBarView.swift:151-157,294-298`; `MeterGauge.swift:98-100,163-165,284-286` | "—", bar collapses to 0, reset hidden, "Unavailable" label | PORT | S | Comes with P13. |
| P23 | Whole-account transient stale: rows dimmed + "Stale" chip on the identity row (P33) | `ProviderCardView.swift:192-195,800-802` | Provider `.stale` → "Stale" pill under the name + dimmed rows (`MirrorPresentation.swift:44-53`; `ProviderTileView.swift:46-53`) | CORE | S | Restyle only (P33). |
| P24 | Pending: `SkeletonMeter` placeholders at varied widths + "Fetching usage…" 11.5 medium tertiary (`ProviderCardView.swift:854-867,1698-1748`) | as left | `.pending` → `.skeleton` treatment, which only dims; the tile has no windows, so it renders as an empty card (`MirrorPresentation.swift:48-49`) | PORT | S | Port `SkeletonMeter` (pure SwiftUI). Phone copy: "Waiting for your Mac's first reading". |
| P25 | Empty windows: "No usage data" (`ProviderCardView.swift:1639-1643`) | as left | none (empty tile) | PORT | S | Comes with P24. |
| P26 | Type ramp is fixed popover sizes: title 20 bold −0.2; account 15 semibold −0.15; label 13 medium; countdown 11 mono; numeral 18 semibold mono; suffix 11; capsule 10.5 medium +0.2; sentence 11.5 medium +2 leading (`PopoverView.swift:404-406`; `ProviderCardIdentityRows.swift:16-40,214-219`; `UsageBarView.swift:107-109`) | as left | Dynamic Type text styles (`.headline`/`.subheadline`/`.caption`/`.caption2`) | Decision | M | Recommend the popover ramp scaled by one `@ScaledMetric(relativeTo: .body)` unit, the way widgets do (`HeadroomWidgetTypography.swift:52-59`), so the ratios hold under Dynamic Type. Reduce Motion and accessibility are best-effort (AGENTS.md), but the iOS default still includes Dynamic Type. |
| P27 | Optical alignment: `.opticalLeading` and `.capHeightCentered` on `NSFont` (`OpticalLeading.swift:19-248`), used by row, title, sentence | as left | none | PORT | S | Swap to `widgetOpticalLeading` / `widgetCapHeightCentered` (CoreText, UIKit/AppKit conditional: `HeadroomWidgetTypography.swift:147-160,220-235`). |
| P28 | Accessibility: one element per row, label "Fable weekly usage", value "72 percent left, Resets in 3h 11m" (`UsageBarView.swift:343-345,553-565`) | as left | Same pattern, but says "percent remaining" (`HeadroomIOS/Views/UsageBarView.swift:90-92,128-140`) | PORT | S | Comes with P13. |

---

## 3. Provider card and identity rows (P29–P44)

Mac (capture `popover-multi-mixed-dark.png`): one tile per provider. Each account row is
`[mark] Personal [Max] [Stale]` in grey title ink, with meters indented 21pt beneath. Signed-out
accounts show a boxed action row: `[>_] Sign in with the official Claude CLI ↗ ⟳`.
iPhone (`ios-stale-dark.png`): one tile per provider with `[mark] Claude` over `[Stale]`, the
plan capsule pushed to the far right, and full-width bars.

| ID | Element | Mac source | iPhone today | Portability | Effort | What it takes |
|---|---|---|---|---|---|---|
| P29 | Card surface: padding 13, `RaisedTile` r10 glass. Dark fill white .075→.045; light fill white .98→.94. Stroke gradient dark white .20→black .22, light white .90→black .07, 1pt. Shadow dark black .6 r10 y3, light .12 r5 y1. Card width 346 (`ProviderCardView.swift:272-276`; `RaisedTile.swift:25-88`; `PopoverView.swift:905-909`) | as left | Padding 17, `.headroomTile` r17: opaque `tileFillTop/Bottom` gradient, 1pt ring, dark-only 1pt top rim, three shadows (`ProviderTileView.swift:22-23`; `Elevation.swift:12-53`; `HeadroomTheme.swift:4,57-68`; tokens `BrandColorValues.swift:401-427`) | Decision: keep iOS surface (CORE tokens) or port RaisedTile (needs UIKit swaps) | S | Recommend keeping the iOS surface (it's already Core-tokened and opaque, so shadows work on a full-screen gradient) and porting the *content* metrics: 13 vs 17 padding, r10 vs r17. |
| P30 | Shell: Tahoe Liquid Glass (light tinted white .55) / Sequoia `.regularMaterial` / solid fallback; r22, 384 wide, 19 margin (`PopoverView.swift:219-223,388,934-963`) | as left | Full-screen gradient + cool radial glow (`HeadroomTheme.swift:39-55`; `MirrorView.swift:56`) | MAC (popover window). iOS 26 has `glassEffect`. | S | DESIGN.md rule 8 allows glass for shell and controls only. The iOS nav bar and toolbar already get Liquid Glass; keep the tiles opaque. |
| P31 | Identity row: 15pt mark slot (ink = 13/15 × mass correction: Claude 1.00, Codex 0.92, Grok 1.20, Cursor 1.03, aspect kept: `BrandColorValues.swift:711-784`), 6pt gap, title 15 semibold −0.15 in `AccountTitleInk` (neutral #9AA2AC dark / #5F6771 light, or brand `textAccent`), plan + Stale chips leading-aligned after the title, trailing inset 21 (`ProviderCardIdentityRows.swift:7-41,231-338`; `BrandColorValues.swift:314-318`) | as left | Logo `size: 18` → 24.3pt slot (`HeadroomIOS/DesignSystem/ProviderLogoView.swift:16`); title `.headline` semibold `.primary`; Stale under the title; plan pushed trailing (`ProviderTileView.swift:40-66`) | PORT (`NSFont` used only for truncation detection: `ProviderCardIdentityRows.swift:346-359`) | S | Port `IdentityRow` minus tooltip/hover. Phone `ProviderLogoView` already uses the same `HeadroomBrandMark` rule. |
| P32 | Plan capsule: `PlanLabelPresentation.displayName` ("prolite" → "Pro Lite"), 18pt tall, 5pt h-pad, `secondary @ .12` fill, `planLabel` ink (dark .60 / light .52), 10.5 medium +0.2 (`IdentityRowMetrics` `30-40`; `IdentityCapsuleStyle.metadataFill` `53`; `identityMetadataLabel` `96-98`; `BrandColorValues.swift:300-302`) | as left | `.caption` semibold, `secondaryText`, padding 10/5, `barTrack` fill, trailing (`ProviderTileView.swift:56-64`) | CORE (PlanLabelPresentation in iOS: `project.yml:106`) | S | — |
| P33 | Stale chip: "Stale", 18pt, h-pad 5, `secondary @ .18` fill + 1pt `secondary @ .35` ring (state = outlined, metadata = flat) (`ProviderCardIdentityRows.swift:43-59,411-423`) | as left | `.caption2` semibold, `secondary @ .16`, no ring, stacked under the title (`ProviderTileView.swift:46-53`) | CORE | S | — |
| P34 | Multiple accounts: one section per account, 26pt apart; title is the account label via `rowTitle`; the provider name is used when there's a lone default label; one provider with 2+ accounts flips every card to account rows (`ProviderCardView.swift:603-647`; `Models/IdentityRowResolver.swift:5-26`); 640pt scroll cap | as left | Primary account only (`UsageStore.swift:1087-1103`) | ENV (D2 `accounts`) + PORT | L | The envelope work dominates (D). The view is `AccountSectionView` minus setup and actions. |
| P35 | Make Main order: primary first, then registry order; animated with `reorder` (`PopoverView.swift:61-63,151-154`) | as left | n/a | ENV (order of `accounts`) | S (with P34) | — |
| P36 | Main-account marker: nothing visible; tooltip and VoiceOver say "Main account — shown in the menu bar and widgets" (`ProviderCardIdentityRows.swift:361-394,427`) | as left | n/a | ENV `isPrimary` | S | On the phone it's worth saying which account the iOS widgets follow. |
| P37 | Persistent email shown when labels are ambiguous (`IdentityRowResolver.swift:30-43`; `ProviderCardIdentityRows.swift:298-305`) | as left | n/a | MAC data (emails must not sync: "Sign-ins are never synced", `WidgetSettingsSection.swift:76`; the projector never copies `accountEmail`, `WidgetSnapshotProjector.swift:50-72`) | S | Have the Mac resolve a duplicate-safe `title` before sync (e.g. "Work · 2"), never the email. |
| P38 | "Same login as X" badge: **Settings › Accounts only, not the popover** (`AccountsSettingsTile.swift:409`; detection `Providers/ClaudeAccountEmailReader.swift:130-150`) | as left | none | MAC (Settings surface) | — | Recommend skipping. If wanted, an optional `sameLoginAs: String?` per account. |
| P39 | Status-sentence action rows (#156, V13b). Boxed row: 14pt glyph column (`apple.terminal`/`globe`/`arrow.clockwise`), 11.5 medium sentence in label ink at .62 (.88 on hover), the action verb in semibold, trailing ↗ 9 semibold, fill white/black .03/.055/.08, edge .10/.14, r7, pad 7/7/6, press 0.985; a secondary action as a glyph button; Critical rows have a red verb + glyph (`ProviderCardView.swift:1172-1268,1288-1303,1363-1525`). Waiting/refusal lines are unboxed (`1309-1361`). | as left | One amber triangle notice, "Sign in again on your Mac", for *every* permanent failure; the envelope's `message` is ignored (`MirrorPresentation.swift:44-53`; `ProviderTileView.swift:68-78`) | MAC (every action is a Terminal/browser handoff on the Mac) + ENV (typed attention, D2) for the sentence | M | Phone version: the *unboxed* `CardRowStatusLine` look (glyph column + sentence, no ↗) with phone copy keyed on a typed attention value: "Sign in to Work on your Mac", "Approve the Claude workspace on your Mac", "Install Claude Code on your Mac". |
| P40 | `StatusSentenceSeverity` inks: attention = label ink, critical = `criticalText`, progress/neutral = secondary, quiet = tertiary; amber is never used for account state (R2C5) (`ProviderCardIdentityRows.swift:139-197`) | as left | Amber (`.low` severity color) for needs-attention (`ProviderTileView.swift:72,76`) and spend warnings (`APISpendMirrorView.swift:136-137`). **Breaks DESIGN.md rule 4.** | CORE | S | — |
| P41 | Capability card (Claude CLI missing / inconclusive): provider identity row + action row "Headroom can’t find the Claude Code CLI on this Mac" (`ProviderCardView.swift:258-270,328-379`; `ProviderCapabilityPresentation.swift:20-43`; capture `popover-capability-failure-dark.png`) | as left | No capability state reaches the phone (`BUGS.md:726-727`). What it shows during a capability failure is unverified (whatever the primary snapshot's freshness is). | ENV (D2 `attention` / `capability`) | S | Phone copy: "Claude Code isn't installed on your Mac." |
| P42 | Guided setup cards: Claude Connect/Waiting (with dot-matrix spinner), Codex Connect/Waiting/Access recovery, Stop Waiting, `CommandRecoveryRow` "$ claude" with copy (`ProviderCardView.swift:440-575,1059-1137,1753-1784`; `ClaudeSetupViews.swift`; `CodexSetupViews.swift`) | as left | none | MAC (Terminal handoff, pasteboard, `SetupSessions`) | — | Phone: one sentence (P39). |
| P43 | "Connected" chip payoff after setup (`ProviderCardIdentityRows.swift:474-495`) | as left | none | MAC | — | — |
| P44 | Card crossfades on a meter-style change (`.id(meterRecipeKey)`, `settle`) (`PopoverView.swift:104-135`; `ProviderCardView.swift:11-15`) | as left | n/a | PORT | S | Comes with S4. |

---

## 4. API spend (P45–P53)

Mac: `[mark] Anthropic [API] ········ $142.67 used`. No eyebrow, no dividers, one tile in the card
language. iPhone (`ios-usage-dark.png`): an "API SPEND" eyebrow, then `Anthropic API · Current month
········ $142.67`.

| ID | Element | Mac source | iPhone today | Portability | Effort | What it takes |
|---|---|---|---|---|---|---|
| P45 | Container: no eyebrow, no divider, 13pt pad, `raisedTile` r10; rows 13pt apart, 26 when any row carries a sentence (`APISpendSectionView.swift:49-82`) | as left | "API Spend" uppercased `.caption` semibold +0.4 tracking, hairline dividers, pad 17 (`APISpendMirrorView.swift:13-48`) | CORE | S | Updates `Tests/HeadroomIOSUITests/ResponsiveLayoutUITests.swift:13-18,51`, which pins "API SPEND" and "· Current month". |
| P46 | Identity line: 15pt brand mark + title. `popoverIdentity` moves a trailing qualifier into the chip ("Anthropic" + "API"). 15 semibold −0.15 in `accountTitleInk` (`APISpendSectionView.swift:101-126,183-229`; `Widgets/APISpendPresentation.swift:385-405`) | as left | No mark; full display name `.subheadline` semibold + "· context" `.caption` (`APISpendMirrorView.swift:73-89`) | CORE (APISpendPresentation is in `Widgets/`, compiled into iOS) | S | — |
| P47 | Period chip: metadata capsule reading `apiSpendPeriod.displayLabel(now:)` ("October"); balance rows read "Remaining balance" (`APISpendSectionView.swift:104-107,233-245`; `UsageModels.swift:736-765`) | as left | Raw `periodLabel` ("Current month" / "Last 30 days") | CORE (map label → `APISpendPeriod`, or ENV `spendPeriod`) | S | String-matching `APISpendPeriod.label` works today. An optional typed field is sturdier. |
| P48 | Amount: 18 semibold mono, column sized to the widest amount shown (`NSFont`), digit roll, `.privacySensitive`, then the "used"/"left" suffix (`APISpendSectionView.swift:17-37,256-305`; `directionTerm` `APISpendPresentation.swift:362-366`) | as left | `.headline` semibold mono, `minimumScaleFactor(0.76)`, no suffix (`APISpendMirrorView.swift:103-119`) | PORT (`NSFont`) | S | — |
| P49 | State tag in the chip's slot (`shortBadge`). Quiet/neutral tones use the Stale recipe; warning uses the amber text tier @ .16; critical uses `criticalText` (`APISpendSectionView.swift:202-206,386-418`) | as left | none (shows a status line instead) | CORE | S | The Mac warning *tag* is amber (`412-413`) while the Mac *sentence* is neutral. Keep that split. |
| P50 | Sentence under non-live rows (`StatusSentence` + `forSpendTone`) (`APISpendSectionView.swift:157-171`) | as left | Status line in `.caption` medium, tone-colored (amber for warning) (`APISpendMirrorView.swift:91-101,123-141`) | CORE | S | Use neutral ink for warning (P40). |
| P51 | Top-up "+" revealed on hover; opens the provider's billing page (`NSWorkspace`) (`APISpendSectionView.swift:307-379`; URLs `APISpendPresentation.swift:416-425`) | as left | none | PORT (no hover on iPhone) | S | Discuss: a context menu or link "Add funds at platform.claude.com". This is the vendor's own billing page, not a Headroom sale, so 3.1.1 shouldn't apply (unverified how App Review sees it). |
| P52 | CTA chips "Add Key" / "Replace Key" open Mac Settings (`APISpendSectionView.swift:427-455`) | as left | none | MAC (keys live on the Mac) | — | The phone sentence says "Add a key on your Mac". |
| P53 | Prepaid balance (xAI): "Remaining balance" chip + "left" suffix | `APISpendSectionView.swift:121-124,303` | Context label right ("· Remaining balance", `APISpendMirrorView.swift:74-77`); suffix missing | CORE | S | Comes with P48. |

---

## 5. Provider-specific capsules (P54–P55)

| ID | Element | Mac source | iPhone today | Portability | Effort | What it takes |
|---|---|---|---|---|---|---|
| P54 | Codex banked-reset plan capsule. Plain / bead (4pt dot in plan ink) / open ("Plus · 1 reset"). Opens on hover; on its own while a live 5-hour or weekly window is Critical; and once for 4s when a higher count first shows (acknowledgement stored per account). Tooltip and VoiceOver explain a full reset (`PlanCapsule.swift:6-61`; `Models/PlanCapsulePresentation.swift:16-73,78-88`; reveal `ProviderCardView.swift:651-687`; `docs/solutions/codex-banked-resets.md`; capture `popover-banked-resets-light.png`) | as left | none. The count is never projected (`WidgetSnapshotProjector.swift:57-71`) and the doc says the iPhone ignores it (`codex-banked-resets.md` "Widgets, the menu bar, iPhone projection… ignore the count") | ENV (`bankedResets: Int?` on provider + account) + CORE (`PlanCapsulePresentation.swift` is Foundation-only, not yet in the iOS list) | S–M | On iPhone: tap to toggle instead of hover; Critical auto-open ports as-is. The reveal ledger (`Settings/BankedResetAcknowledgements.swift`) would be phone-local, or drop the reveal. |
| P55 | Other provider-specific rows. Claude model rows ("Fable"); Codex Spark counters (popover follows the *in-app* switch, `UsageStore.swift:1045-1052`); Grok/Cursor billing-period pools ("Monthly", "Cursor Models", "Other Models") | as left | Model rows and pools render (label via `displayName`). **Spark rows follow the *widgets* switch** (`UsageStore.swift:1098`; projector `144-168`). | ENV (decision) | S | Either mirror the in-app switch for the phone app or accept the widget switch. One flag on the envelope would let the phone filter Spark rows. |

---

## 6. Popover chrome (P56–P65)

| ID | Element | Mac source | iPhone today | Portability | Effort | What it takes |
|---|---|---|---|---|---|---|
| P56 | Header: "Usage" 20 bold −0.2; the status slot speaks only for setup stages and waiting clocks; gear (15 medium secondary in a 32pt frame, `HoverButtonStyle`, ⌘,) (`PopoverView.swift:395-469`) | as left | iOS large title "Usage" + `navigationSubtitle` stamp; toolbar gear opens a sheet (`MirrorView.swift:59-64`; `IOSCompanionView.swift:21-31`) | Keep native | — | No change recommended. iOS idiom wins here. |
| P57 | Footer: Refresh (bordered, spinner over it, ⌘R) + freshness stamp ("2 min ago" / "Just now", "Checked N ago" for retained data, "Not checked yet") + Quit. The stamp is the **oldest live capture across all accounts** (`PopoverView.swift:612-686,827-900`) | as left | Pull to refresh re-reads KVS only (`MirrorView.swift:58`). The subtitle stamp is the envelope's `generatedAt`, i.e. export time (`MirrorView.swift:78-84`). | CORE (window `observedAt` is on the wire: `WidgetSnapshotProjector.swift:121`) | S | Compute the stamp with `PopoverHeaderStatusResolver.freshness` semantics from window `observedAt`. Lift the resolver (`PopoverView.swift:827-900`, pure) into Core. Phone Refresh can't make the Mac poll (see W8). |
| P58 | Refresh receipt: "Checking 3 accounts…" → "✓ Work  2 of 3" (`PopoverView.swift:652-676,701-749`) | as left | none | MAC (needs a user-started Mac refresh) | — | Only possible with W8. |
| P59 | Dot-matrix spinner (#148): 5×5 arc, 150ms hard-cut frames (not a pulse), secondary/quaternary dots at 0.8 pitch, holds a still frame under Reduce Motion (`DotMatrixSpinner.swift:31-120`). Used in the Claude/Codex waiting cards at 15pt (`ClaudeSetupViews.swift:515`; `CodexSetupViews.swift:281`). Its doc comment says "popover footer" (`75`), but the footer uses native `ProgressView` (`PopoverView.swift:633-638`). | as left | "Checking…" with native `ProgressView` (`StatusScreen.swift:31-36`) | PORT (pure SwiftUI, 0 AppKit refs) | S | Move to shared; use for the phone's Checking and Waiting states. Fix the stale doc comment. |
| P60 | Waiting card on the Mac: title + spinner + detail inside a card. The widget vessel family is `WidgetVesselGeometry` 11:18 + `HeadroomVesselMark` (`BUGS.md:762-763`). | `ClaudeSetupViews.swift:505-525` | `StatusScreen`: 88×124 `VesselMark` with **system-blue** liquid and shadow (`VesselMark.swift:32,55-63`), title3/subheadline, blue `borderedProminent` Refresh, Explore Demo (`StatusScreen.swift:13-58`; capture `ios-waiting-dark.png`) | PORT | S | Redraw the vessel with Core `WidgetVesselGeometry` and neutral/severity inks. Use the dot-matrix spinner and neutral buttons (G6). |
| P61 | Empty/first run: per-card skeleton + "Fetching usage…", guided Connect cards | `ProviderCardView.swift:854-867,440-575` | Five full-screen states: paused / iCloud unavailable / waiting / unreadable / update needed (`IOSCompanionView.swift:93-133`) | Phone-specific | S | Copy fixes in G8 and G9. |
| P62 | Scroll cap 640, 14pt bottom feather (1 / .55 / 0), custom 3pt scroll indicator (`PopoverView.swift:192-211,235-328`) | as left | Native full-screen scroll | MAC (window sizing) | — | — |
| P63 | Spacing: shell 384 / margin 19 / tile gap 20 / header→first card 14 (`PopoverView.swift:81-91,905-909`) | as left | Page padding 18, gap 12, iPad max width 980 (`MirrorView.swift:23,50-54`) | Decision | S | Suggest tile gap 20 and side margin 19–20 on iPhone for rhythm parity. |
| P64 | Account-title ink choice (G1A) set once at the popover root (`PopoverView.swift:226-228`; `ProviderStyle.swift:291-327`) | as left | n/a | CORE + pref (S6) | S | — |
| P65 | Quit | `PopoverView.swift:680` | n/a | MAC | — | — |

---

## 7. Motion (M1–M13)

DESIGN.md already flags this gap: iOS keeps its own values in `HeadroomTheme`
(`DESIGN.md` "Known gaps").

| ID | Token / behavior | Mac (`HeadroomMotion.swift`) | iPhone (`HeadroomTheme.swift`) | Gap / what it takes |
|---|---|---|---|---|
| M1 | House curve | `settle` (0.22,1,0.36,1) 200ms; `quickSettle` 120ms; `pressDown` 100ms; `pressScale` .96 (`11-25`) | `entranceAnimation` uses the same curve at **340ms** (`HeadroomTheme.swift:5`) | Share the tokens. Retire `entranceAnimation` or re-derive it. |
| M2 | Value spring | `valueSpring` response .3, damping 1.0 (`46`) | Same values (`HeadroomTheme.swift:8`) | Parity. Share one token. |
| M3 | Arrival | Once per launch per account (`ArrivalRegistry`, `UsageBarView.swift:16-29`), 350ms delay (`HeadroomMotion.swift:101`), `arrivalSpring` .4 (`106`), numeral shows its real value from the first frame (AR2, `UsageBarView.swift:201-223`). **No popover entrance at all** (M9C, `PopoverView.swift:214-216`). | Every tile fades in and rises 10pt, staggered 55ms (`ProviderTileView.swift:24-35`; `MirrorView.swift:36,45`). Every bar draws in from 0 on *each* appear after 100ms (`HeadroomIOS/Views/UsageBarView.swift:20,80-89`). | Decide: Mac-style once-per-launch arrival with no entrance, or keep the phone entrance (it's an app launch, not a 30×/day popover). The registry needs `AccountKey` (`Account.swift`, B2). |
| M4 | Landing sequence | Fill + severity color on `valueSpring`; tone and state label crossfade on `settle` *after* the fill lands (`UsageBarView.swift:281-329`) | One `.animation(valueSpring)` each for fraction and dimming (`HeadroomIOS/Views/UsageBarView.swift:78-79`) | Comes with P13. |
| M5 | Digit rolls | Countdown rolls down each minute (M2A, `UsageBarView.swift:470-473`); stamp rolls up (`PopoverView.swift:477-483`); numeral roll keyed to value (`UsageBarView.swift:527-530`) | Numeral uses `.numericText()` with no direction (`HeadroomIOS/Views/UsageBarView.swift:59`); countdown hard-cuts | Comes with P13/P57. |
| M6 | Reduce Motion (S2A) | Crossfades keep their timing, movement snaps: `resolved(_:_:reduceMotion:)`, `fade`, `numericText` (`150-176`) | `reduceMotion ? nil : …` everywhere, so color crossfades die too (`HeadroomIOS/Views/UsageBarView.swift:78-79`) | Low priority (AGENTS.md: best effort). Shared helpers fix it for free. |
| M7 | Meter-style dissolve (M5A) | `PopoverView.swift:123-135` | n/a | With S4. |
| M8 | Reorder / layout / row insert | `reorder` spring (`50`); NB1 neighbours ride `valueSpring` (`PopoverView.swift:146-159`); rows keyed by window kind and fade on insert/remove (RI1, `ProviderCardView.swift:1650-1673`) | none (`LazyVGrid` keyed by provider id, `MirrorView.swift:31-40`) | Needed once accounts arrive (P34/P35). |
| M9 | Plan capsule open/close + banked reveal | `PlanCapsule.swift:45-56`; 4s hold (`ProviderCardView.swift:651-687`) | n/a | With P54. |
| M10 | Hover/press | `CardRowButtonStyle` row hover in/out, press .985 (`ProviderCardView.swift:1423-1525`); `rowHoverIn/Out` (`HeadroomMotion.swift:37-38`) | n/a | iPad pointer can use hover; iPhone needs press states only. |
| M11 | Receipt roll | `PopoverView.swift:690-697` | n/a | MAC (P58). |
| M12 | Window handoff (SW1), keyboard-instant (KB1) | `HeadroomMotion.swift:117-134` | n/a | MAC (AppKit windows, `NSApp.currentEvent`). |
| M13 | **Porting HeadroomMotion** | The file imports AppKit only for `windowCurve` (`CAMediaTimingFunction`, which also exists on iOS via QuartzCore) and `isKeyboardInitiated` (`NSApp`) (`HeadroomMotion.swift:1,122-134`) | — | Split: everything except `isKeyboardInitiated` moves to shared; that one stays Mac-only. Then `HeadroomTheme` keeps only phone-specific layout tokens. |

---

## 8. Settings (S1–S14)

Mac Settings is a fixed `NavigationSplitView` with eight destinations (`HeadroomCore/Settings/SettingsPane.swift:6-67`);
captures `settings-{appearance,about,notifications,widgets}-*.png`.
iPhone Settings is a sheet `List` (`HeadroomIOS/Views/SettingsSheetView.swift:20-100`; capture `ios-settings-dark.png`).

| ID | Mac pane / control | Mac source | Phone today | Meaningful on a read-only mirror? | Portability | Effort |
|---|---|---|---|---|---|---|
| S1 | **General**: refresh every 2–60 min + cadence sentence, launch at login | `SettingsPanes.swift:53-128` | Covered by the "Managed on Mac" note | No. MAC (polling and login item are Mac-side). Possibly show the Mac's interval read-only (needs D2 `pollIntervalSeconds`). | MAC | — |
| S2 | **Updates** (Sparkle): auto-check, auto-install, Check for Updates | `SettingsPanes.swift:133-179` | Version row (`SettingsSheetView.swift:82-84`) | No. MAC (the App Store updates the phone). | MAC | — |
| S3 | **Appearance › Theme**: System/Light/Dark thumbnails with mini-window art (`SettingsPanes.swift:208-213`; `ThemeThumbnailPicker.swift`), pref `AppearancePreference` (`Settings/Preferences.swift:338-352`) | as left | Segmented System/Light/Dark (`SettingsSheetView.swift:54-62`) backed by a duplicate enum `AppearanceSetting` (`AppearanceSetting.swift:3-25`) in `@AppStorage("headroom.ios.appearance")` (`HeadroomIOSApp.swift:6`) | Yes, **phone-local** (a device choice, so it shouldn't follow the Mac) | CORE once the enum moves out of `Preferences.swift` (UserDefaults-heavy file; unverified whether it compiles on iOS as-is). The picker is pure SwiftUI (0 AppKit refs). | S |
| S4 | **Appearance › Meter Style**: Format (2 card-fragment swatches) / Shape (4) / Fill (5) on fixed 76pt columns, each swatch drawn by the real `MeterGauge`; help lines "Tube is available only with Micro format." and "Only when low keeps meters neutral until usage runs low. Glass and Ghost add a bright end cap." (`MeterStyleTile.swift:22-122`) | as left | none | Yes. Decide phone-local or "follow Mac" (D2). | PORT (`MeterStyleTile` has 0 AppKit refs; its swatch chrome comes from `SettingsRows.swift`, which has one `onHover`) | M |
| S5 | **In-App Display › Percentages**: Left/Used swatches (`InAppDisplayTile.swift:36-54`) | as left | none | Yes | PORT. Note `InAppDisplayTile` takes `UsageStore` for the Spark setter (`18,73-76`), so it needs an injected binding instead. | S |
| S6 | **In-App Display › Account names**: Neutral/Brand (`InAppDisplayTile.swift:56-71`; `UsageModels.swift:193-212`) | as left | none (titles are always `.primary`) | Yes, once account titles exist (P31/P34) | CORE + PORT | S |
| S7 | **In-App Display › Codex Spark counters in app** (`InAppDisplayTile.swift:73-76`) | as left | none; the phone follows the *widgets* switch (P55) | Needs a decision (P55) | ENV | S |
| S8 | **Appearance specimen**: a live inert `ProviderCardView` fed by `DemoFixture` (`AppearanceSpecimen.swift:20-60`) | as left | none | Yes, as the preview above the phone's style pickers | PORT. `DemoFixture` sits at the Core root and isn't in the iOS list; use `DemoScreenshotData` (already compiled: `Widgets/DemoScreenshotData.swift:8-46`) | S |
| S9 | **Menu Bar** pane (pills, shelf, window choices) | `SettingsPanes.swift:246-735` | — | No. MAC. Closest phone analogue is Lock Screen widgets (W4). | MAC | — |
| S10 | **Widgets & iPhone**: preview strip, style gallery (preview only), share with widgets, widget providers (≤2), Spark in widgets, **Sync usage to iPhone** + "Sends only your usage numbers through iCloud. Sign-ins are never synced." (`SettingsPanes.swift:739-777`; `WidgetSettingsSection.swift:17-79`; `WidgetStyleGalleryPicker.swift:13-86`) | as left | none. Sync status rows only (`SettingsSheetView.swift:64-73`). | Partly: a read-only "Your widgets" gallery explaining the four styles and "choose with Edit Widget"; "Widgets show Claude and Codex (set on your Mac)". | PORT (needs `HeadroomWidgetSharedUI` in the iOS **app** target, B1) | S–M |
| S11 | **Notifications** | see N | none | see N | — | — |
| S12 | **Accounts** (add/remove, stop-track, Make Main, sign-in handoffs, same-login badges) and **API Spend** (keys, period, surface switches) | `SettingsPanes.swift:785-1090`; `AccountsSettingsTile.swift` | "Managed on Mac" note (`SettingsSheetView.swift:75-80`) | No. MAC (credentials and CLI live on the Mac; OAuth constraint). The phone can *list* accounts read-only once D2 lands. | MAC | — |
| S13 | **About**: identity card (64pt icon, r = 64×8/28, "Headroom", "Version x" mono, tagline "AI usage limits + API spend right from your menu bar"), Support → "Enjoying Headroom? · Tip jar ↗" + "Headroom is free… Processed through Stripe.", Made by → Website / LinkedIn / X / GitHub (`SettingsPanes.swift:1127-1259`; `AboutLinks.swift:25-51`) | as left | Header (48pt icon, "iPhone & iPad companion") + version row (`SettingsSheetView.swift:124-136,82-84`). No links. | Yes: identity card + maker links + "Get Headroom for Mac" (website). **Tip jar: see S14.** | CORE (`AboutLinks.swift` is Foundation-only and not yet in the iOS list) + PORT (`SettingsLinkRow` uses `NSWorkspace.open`, `1233`; swap for `openURL`) | S |
| S14 | **Tip jar on iOS (flag)**. Mac: an external link to `headroom.zantos.co/tip` → Stripe Payment Link (`AboutLinks.swift:26-36`). Guidelines (fetched 2026-10-03): 3.1.1 "Apps may use in-app purchase currencies to enable customers to 'tip' the developer…"; 3.1.1(a) "…not required for developers to include buttons, external links, or other calls to action in their **United States storefront** apps"; 3.1.3 forbids steering to other purchase methods outside the US storefront. 3.2.1(vii) person-to-person gifts don't fit a developer tip. | — | none | Options: (a) StoreKit 2 consumable "tip" IAPs (allowed everywhere; Apple takes its cut; drop "Processed through Stripe"); (b) the external link shown only when the storefront is US (`Storefront.current?.countryCode`; unverified how review treats a storefront-gated link); (c) no tip jar on iOS, maker links only. | — | S (c) · M (a/b) |
| S15 | Settings grammar: `SettingsMetrics` and `SettingsType` (pane title 20, tile 15, group 13, help 11, swatch 11 medium; gaps 4/6/8/10/20/28) (`SettingsRows.swift:120-172`) | as left | iOS grouped `List` | Decision: keep the native iOS `List`/`Form` and put Headroom swatch rows inside sections. Don't port the Mac pane scaffold. | — | — |
| S16 | Phone-only rows: Demo section, Sync (Status/Source/Widgets), DEBUG diagnostics (`SettingsSheetView.swift:29-52,64-73,102-122`) | — | present | Keep. Fix the "Widgets" row (G17). | — | S |

---

## 9. Notifications (N1–N5)

| ID | Item | Source / evidence | Assessment |
|---|---|---|---|
| N1 | Mac behavior. Use-it-up reminders (rules "N day(s)/hours before reset, if ≥X% left"; scope Weekly / Billing periods / 5-hour) and the Codex banked-reset notice. Posted by the **running Mac app**, only on a fresh live merge, with ledgers written after the post is accepted. | `Notifications/NotificationCoordinator.swift:20-131`; `UseItUpEvaluator.swift:37-60`; `NotificationsSettingsPane.swift:197-315`; AGENTS.md Notifications gotcha | Logic is Foundation-only Core (`Notifications/*.swift`, `Settings/NotificationPreferences.swift`). Portable as code, but the phone has no fresh merges to feed it. |
| N2 | What the phone can observe. No polling, no push. KVS `didChangeExternallyNotification` is observed only inside the app view (`IOSCompanionView.swift:61-63`); delivery while suspended is not guaranteed (unverified, per Apple's general background model). The iOS widget extension re-reads KVS on each timeline reload (`HeadroomIOSWidgets/HeadroomIOSTimelineProvider.swift:46-62`); WidgetKit budgets those reloads (cadence unverified, roughly every 15 min at best: `WidgetTimelineSchedule.refreshDate`, `WidgetSnapshotModels.swift:627-629`). | — | **Nothing on the phone can honestly fire "the moment" a limit crosses a threshold.** |
| N3 | Options | — | **(a) None.** Phone Settings says "Reminders come from Headroom on your Mac." Honest, S. **(b) Local scheduling from the last snapshot.** On every new snapshot the app (and maybe the widget extension; scheduling from an extension is unverified) cancels and reschedules `UNNotificationRequest`s at `deadline − leadTime` for windows that were ≥X% left *as of that snapshot*. The OS fires them even if the app is closed. Risks: the percentage may have dropped since (copy must say "as of 2:14 pm"); duplicates the Mac banner (needs a per-device "Notify on: Mac / iPhone / both"). Rules come from the Mac (D2 `reminders`) or are phone-local. M. **(c) BGAppRefreshTask** to re-read KVS and reschedule (b). Opportunistic, cadence decided by the system (unverified), so it only improves (b). S–M. **(d) CloudKit subscription push.** The Mac writes a small record per notification decision (`NotificationCoordinator` already decides); a `CKQuerySubscription`/`CKDatabaseSubscription` with alert `notificationInfo` makes Apple deliver a visible push to the phone with no Headroom server. This is the only path that matches the Mac's timing and wording. L: CloudKit container, entitlements on both apps, Mac write path, and the Mac's iCloud entitlement is already provisioning-gated (`BUGS.md:407-428`). Delivery latency unverified. |
| N4 | Banked-reset notice on the phone | count not in envelope (P54) | Not schedulable (it's an event, not a deadline), so only (d), or showing it in-app on next open. |
| N5 | Permission UX | Mac permission notice and "installed app" help (`NotificationsSettingsPane.swift:14-173`) | Whatever option is chosen needs an iOS permission prompt flow; nothing exists today (no `UNUserNotificationCenter` use under `Sources/HeadroomIOS*`). |

---

## 10. Data and envelope (D1–D12)

**D1 — today's wire format (schema 3).** Envelope = `schemaVersion, generatedAt, status,
providers, apiSpendProviders, widgetProviderSelection?` (`WidgetSnapshotModels.swift:5-72`).
Provider = `id, displayName, planLabel?, freshness (pending|live|stale(message,needsAttention)),
windows, renewalDate?` (`115-137,256-267`). Window = `id, kind, label (required), percentRemaining,
utilization?, resetKind/resetDeadline/resetReason, resetLabel?, resetTimeZoneIdentifier?,
observedAt?, severity, freshness (live|stale(observedAt)|unavailable(since)),
billingPeriodDuration?` (`269-416`). Spend = `id, displayName, amount?, currency?, periodLabel,
kind?, capturedAt?, freshness, attention?` (`216-254`). Wrapped as `publishedAt, sourceID,
sourcePlatform, snapshot` under one KVS key `headroom.syncedWidgetSnapshot`
(`Sync/SyncedWidgetSnapshotModels.swift:3-25`; `iCloudSnapshotSync.swift:27`). Old phones gate on
schema numbers only (`SyncedWidgetSnapshotModels.swift:52-75`; `supports` `78-80`), and
`JSONDecoder` ignores unknown keys, so **additive optional keys are invisible to old phones**. A
schema bump instead puts old phones on "Update Needed" (`IOSCompanionView.swift:126-133`).

**D2 — proposed additive fields** (all `decodeIfPresent` / `encodeIfPresent`; schema stays 3;
unknown enum strings fall back to defaults, the way `WidgetLayoutStyle` does):

| Need | Field (name: type) | Where | Feeds |
|---|---|---|---|
| Every account per provider | `accounts: [WidgetAccountSummary]?` | `WidgetProviderSummary` | P34–P37, P39, P54 |
| — | `WidgetAccountSummary { id: String` (AccountID.raw: "primary" or a lowercase UUID, `Settings/AccountRegistry.swift:93`) `, title: String` (resolved on the Mac via `rowTitle`, de-duplicated, never an email) `, planLabel: String?, isPrimary: Bool, freshness: WidgetProviderFreshness, attention: WidgetAccountAttention?, bankedResets: Int?, windows: [WidgetWindowSummary] }` | new type in `Widgets/WidgetSnapshotModels.swift` | — |
| Phone-appropriate status sentences | `attention: WidgetAccountAttention?`, a String enum: `signInRequired, workspaceApprovalRequired, cliMissing, cliCheckInconclusive, cliUpdateRequired, accessDenied, credentialsRejected, retrying` (mapped from `ProviderSetupOutcome` / `FailureReason` / `ProviderCapabilityState`) | provider (primary) + account | P39–P41 |
| Banked resets | `bankedResets: Int?` | provider (primary) + account | P54 |
| Mirrored display prefs (only if "follow Mac") | `display: WidgetDisplayPreferences? { percentageMode: String?` ("remaining"/"used") `, meterStyle: String?` (launch token, parsed by `MeterStyle(launchToken:)`, `MeterStyle.swift:82-90`) `, accountTitleInk: String? }` | envelope | P1, P18, S4–S6 |
| Phone-side staleness | `pollIntervalSeconds: Int?` | envelope | G12 (also fixes `BUGS.md:755-757` for widgets) |
| Spend period | `spendPeriod: String?` (`APISpendPeriod.rawValue`) | `WidgetAPISpendSummary` | P47 (optional; string match works without it) |
| Spark in-app parity | `showsCodexSparkCountersInApp: Bool?`, or send all Spark rows and let each surface filter | envelope | P55 |
| Reminders (option N3b) | `reminders: { enabled: Bool, rules: [ReminderRule], scope: [String] }?` | envelope | N3b |
| Not proposed | email, same-login, account config paths, any credential | — | privacy (P37, P38) |

**D3 — projector changes.** `WidgetSnapshotProjector.project` takes a single
`snapshots: [ProviderID: UsageSnapshot]` (`WidgetSnapshotProjector.swift:6-48`). It needs a second
input: per-provider ordered `(account, title, snapshot)` lists plus display prefs. `providerSummary`
(`50-72`) builds `accounts` with the same `windowSummary` (`106-126`) and `widgetKind` filter
(`144-168`), and maps `attention` from `FailureReason.providerSetupOutcome`.

**D4 — store changes.** `UsageStore.widgetSnapshot` (`UsageStore.swift:1087-1103`) passes
`accounts(for:)` (Make Main order), `rowTitle` (`IdentityRowResolver.swift:14-26`),
`providerCapabilities` (`131`), and prefs. Consider projecting the phone envelope separately from
the macOS widget envelope: the widgets ignore accounts, and the local file has no size limit.

**D5 — export triggers.** Timer merges export only for the **primary** account
(`UsageStore.swift:1287-1293`), so an extra account's new reading wouldn't reach the phone until
the primary's next merge. The phone needs exports on extra merges too, coalesced (D9). The
preference setters for percentage mode, title ink and meter style don't export
(`UsageStore.swift:457-472`); they must if D2 `display` ships.

**D6 — existing bug found.** `setWidgetPrioritySource` exports only the widget snapshot, not the
phone snapshot (`UsageStore.swift:485-490`). The envelope's `widgetProviderSelection` drives the
iOS widgets, so a provider-selection change on the Mac reaches iPhone widgets only after the next
primary merge. Belongs in `BUGS.md`.

**D7 — derivable on the phone with no envelope change:** oldest-live stamp (window `observedAt`),
5-hour-first order, "October" period label, short countdown, last-known age, Critical ink, every
severity/meter token, "used" mode (phone-local pref), skeletons, phone copy for permanent stale
(generic only).

**D8 — privacy copy.** The Mac says "Sends only your usage numbers through iCloud. Sign-ins are
never synced." (`WidgetSettingsSection.swift:76`). Account labels and plan names already go beyond
"numbers" (plan already syncs). If account titles sync, update the copy, and keep emails out
(`AccountEmail` stays Mac-only).

**D9 — KVS limits and payload size.**
- Documented: 1 MB total per app, 1 MB per key, 1,024 keys, keys ≤64 bytes in UTF-8 (Apple
  "Storing Preferences in iCloud" archive doc, via search 2026-10-03).
- Practical: Apple DTS (Quinn, forum thread 785350) says stay "far away" from those limits; if you
  need "hundreds, or even tens, of KiB", move to CloudKit. The poster saw a 160 KB key fail to sync
  while 100 KB worked.
- Today: the Mac's local `widget-snapshot.json` is **2,281 bytes** for 3 providers, primary only
  (`ls`, file dated Oct 3 13:28).
- Estimates (a Python reconstruction of the synthesized JSON shape, *not* a Swift measurement):
  one window ≈ 330–380 B; 4 providers primary-only + 4 spend rows ≈ 4.1 KB. Adding `accounts`
  that repeat the primary (Claude 3 windows, Codex 2, Grok 1, Cursor 2 and single-account):
  1 per provider ≈ 8 KB, 5 per provider ≈ 18 KB, **20 per provider (tested envelope) ≈ 57 KB**.
- Mitigations, combinable:
  1. Leave the primary out of `accounts`; it's already the top-level row (about −25%).
  2. Give account windows a slim type without `resetLabel` / `resetTimeZoneIdentifier` / `label`.
     The phone reads `resetSchedule` and `kind`, never `resetLabel`. ~211 B per window, about −37%.
     Top-level windows can't drop `label`, because old decoders require it (`WidgetSnapshotModels.swift:358`).
  3. One key per provider for accounts (`headroom.syncedWidgetSnapshot.accounts.<id>`), each
     ≤ ~15 KB.
  4. Compress (LZFSE/zlib) under a new key.
  5. Cap mirrored extras (e.g. 8 per provider + "N more on your Mac").
- Writes: phone exports already happen on every primary merge and every full refresh
  (`UsageStore.swift:869-870,1290-1292`). With up to ~60 accounts on independent schedules,
  coalesce publishes (e.g. at most one per 30–60 s). KVS throttling specifics are unverified.
- Silent failure: `UbiquitousKeyValueSyncStore.set` always returns `true`
  (`iCloudSnapshotSync.swift:109-112`) and the publisher swallows errors (`93`), so a quota
  violation is invisible. Observe `NSUbiquitousKeyValueStoreQuotaViolationChange` in
  `didChangeExternally` change reasons.

**D10 — compatibility rule.** Keep the top-level provider fields as "the primary account" forever,
so old phones and both widget extensions behave exactly as they do today.

**D11 — tests.** New fields need round-trip and "old decoder ignores" tests next to
`Tests/HeadroomCoreTests/WidgetSnapshotProjectorTests.swift`,
`SyncedWidgetSnapshotModelsTests.swift` and `iCloudSnapshotSyncTests.swift`.

**D12 — wire adapter.** Add `UsageWindow.init(widgetSummary:)` (kind: `.other` +
`billingPeriodDuration` → `.billingPeriod`; utilization = `utilization ?? 100 − percentRemaining`;
freshness mapped 1:1) so the ported popover row renders envelope rows unchanged. Severity then
comes from `UsageSeverity(percentRemaining:)` (`UsageModels.swift:334-341`), the same bands the
projector wrote.

---

## 11. iOS build plumbing (B1–B6)

**B1 — today.** `HeadroomIOS` compiles `Sources/HeadroomIOS`, two asset catalogs, **9 hand-picked
`Models/*.swift`** (ProviderID, Countdown, ResetSchedule, BrandColorValues,
UsageSeverityColorValues, ProviderSetup, UsageModels, PlanLabelPresentation, MeterStyle), all of
`Widgets/` except the projector, and all of `Sync/` (`project.yml:89-113`). The **iOS app target
does not compile `HeadroomWidgetSharedUI`**; only the iOS widget extension does (`131`). The macOS
app does (`38`). `BUGS.md:366-372` records the hand-picked list breaking the phone build once.

**B2 — extra files per ported piece:**

| Piece | Additional files the iOS app target needs |
|---|---|
| MeterGauge + ProviderStyle (P5, P9) | **none** (Core inputs already listed); the two views move to a shared UI folder |
| Row port (P13–P28) + adapter (D12) | `Models/Account.swift` (AccountKey for the arrival registry); `HeadroomWidgetSharedUI/HeadroomWidgetTypography.swift` (CoreText optical helpers) or the whole shared UI folder; the adapter lives in `Widgets/` (already included) |
| Identity rows, plan/banked capsule (P31–P36, P54) | `Models/IdentityRowResolver.swift`, `Models/Account.swift`, `Models/PlanCapsulePresentation.swift` |
| Typed status sentences (P39–P41) | `Models/ProviderSetup.swift` (already in); `Models/UsageProvider.swift` (`ProviderCapabilityState`, `18-26`) + `Models/ProviderCapabilityPresentation.swift` if reused |
| Spend (P45–P53) | none (`Widgets/APISpendPresentation.swift`, `APISpendPeriod` in UsageModels) |
| Theme enum, About (S3, S13) | move `AppearancePreference` out of `Settings/Preferences.swift`; `Settings/AboutLinks.swift` |
| Widget gallery in app (S10) | `Sources/HeadroomWidgetSharedUI` (whole folder). WidgetKit imports in an app target already work for macOS (`project.yml:38`); on iOS unverified, but WidgetKit is importable by apps. |
| Notifications N3b | `Notifications/*.swift`, `Settings/NotificationPreferences.swift`, `Models/Account.swift` |
| Motion tokens (M13) | the shared UI folder (no Core) |

**B3 — wholesale include is safe for `Models/`.** Every file under `HeadroomCore/Models`,
`Notifications` and `Settings` imports only Foundation, except `Settings/LaunchAtLogin.swift`
(ServiceManagement). The macOS-only APIs live in `Credentials/`, `Providers/*Probe*`,
`CLIExecutableResolver`, `GrokUsageSource` and `ClaudeUsageWorkspace` (grep for
`openpty|posix_spawn|Process()|NSWorkspace|Security`). Recommend replacing the 9-file list with
`- path: Sources/HeadroomCore/Models` (+ `Notifications`) in both iOS targets, and adding an iOS
simulator build to the pre-PR check (`BUGS.md:371-372`).

**B4 — shared cross-platform UI folder.** Follow the `HeadroomWidgetSharedUI` pattern:
`#if canImport(HeadroomCore) import HeadroomCore #endif` at the top of each file
(`HeadroomWidgetSharedUI/*.swift:1`). Compile the new folder into the macOS app, the iOS app, and
(if useful) both extensions, and add it as an SPM target in `Package.swift` (iOS 26 is already
declared, `Package.swift:14`). Watch the redeclaration trap: the macOS app compiles shared folders
*into the app module* (`HeadroomWidgetTypography.swift:24-28`). Moved views must be deleted from
`HeadroomApp/UI`, not duplicated.

**B5 — test impact.** `Tests/HeadroomIOSUITests/DemoModeUITests.swift:49` (G4) and
`ResponsiveLayoutUITests.swift:13-51` (pins "API SPEND", "· Current month" and old spend
geometry). `MirrorPresentationTests.swift:70-74` pins the "Low" chip. There is no iOS unit-test
target (`Tests/` holds HeadroomAppTests, HeadroomCoreTests, HeadroomIOSUITests, ReleaseScripts),
so shared view logic must stay testable from Core.

**B6 — DesignSystem fate.** `HeadroomIOS/DesignSystem/HeadroomTheme.swift` keeps
`backgroundView` and the tile; color and motion functions move to shared. `Elevation.swift`
stays. `ProviderLogoView` (iOS) stays (asset-catalog marks). `VesselMark.swift` gets redrawn
(P60). `AppearanceSetting.swift` is deleted in favour of the Core enum.

---

## 12. Other phone gaps (G1–G18)

| ID | Gap | Source | Fix | Effort |
|---|---|---|---|---|
| G1 | **iPad layout**: two flexible columns (min 280), max width 980, spend centered at 640. The capture is about 75% empty (`ipad-current-light.png`). | `MirrorView.swift:47-54,68-76` | Options: (a) masonry columns of provider tiles with stacked accounts (fills once accounts arrive); (b) a `NavigationSplitView` with providers in a sidebar and accounts in detail; (c) a centered single 600pt column like a large popover. | M |
| G2 | Settings copy still lists "renewal dates", a feature cut in Jul 2026 | `SettingsSheetView.swift:76`; cut noted at `ProviderTileView.swift:88` | Drop the phrase. | S |
| G3 | "Low" chip | P19; `BUGS.md:674-677` | Remove it and use red numeral ink. | S |
| G4 | Stale UI test: asserts the static text "Weekly (Fable)", but the row prints "Fable" (`WindowKind.displayName`) and is one accessibility element labelled "Fable weekly usage" | `Tests/HeadroomIOSUITests/DemoModeUITests.swift:49`; `HeadroomIOS/Views/UsageBarView.swift:90-91,104-108`; log `.context/ios-audit/ios-uitests.log:316-319` | Assert on the element's accessibility label. | S |
| G5 | Demo Mode banner: sparkles in `.tint` (system blue), `accentColor @ .09` fill r16, bordered "Exit" | `MirrorView.swift:87-121` | Neutral state-chip language (IdentityCapsuleStyle), no blue. App Store shots should hide the whole banner; screenshot mode (`--demo`) only hides its Exit button today (`canExitDemo`, `IOSCompanionView.swift:148-150`). | S |
| G6 | **System-blue tint everywhere**: there's no `AccentColor` asset (`HeadroomApp/Resources/Assets.xcassets` holds only `AppIcon`). That makes the Refresh/Explore Demo buttons, banner, Settings "Explore Demo", and the `VesselMark` liquid and shadow blue. The Mac popover has no blue CTAs. | `StatusScreen.swift:41,48`; `VesselMark.swift:32,60` | Add a neutral AccentColor, or tint explicitly from Core tokens. | S |
| G7 | StatusScreen vessel doesn't match the Mac or widget vessel | P60; `BUGS.md:762-763` | Use `WidgetVesselGeometry` (11:18). | S |
| G8 | Paused-state copy "Turn **Sync snapshot to iPhone** back on…" vs the Mac toggle "**Sync usage to iPhone**" (in Settings › Widgets & iPhone) | `IOSCompanionView.swift:96`; `WidgetSettingsSection.swift:75` | Update the copy and name the pane. | S |
| G9 | No path to the Mac app: waiting / paused / iCloud states are dead ends for a new App Store user, and the Mac has no link to the iPhone app either (no App Store URL anywhere under `HeadroomApp`) | `IOSCompanionView.swift:93-133` | Add a "Get Headroom for Mac" link (headroom.zantos.co) on the phone and an App Store link in the Mac's Widgets & iPhone pane. | S |
| G10 | Spark counters follow the widget switch, not the in-app one | P55 | Decision. | S |
| G11 | The phone never calls `NSUbiquitousKeyValueStore.synchronize()`; only the Mac's diagnostic dump does | `HeadroomApp.swift:405`; `IOSCompanionView.swift:209-211` | Low priority. Whether current Apple guidance still recommends it at launch is unverified. | S |
| G12 | "Updated N min ago" is the Mac's *export* time, which moves even when provider data is stale, and nothing dims old data when the Mac sleeps | `MirrorView.swift:78-84`; `BUGS.md:755-757` | P57 stamp + D2 `pollIntervalSeconds` threshold. | S |
| G13 | One generic "Sign in again on your Mac" for every permanent failure | `MirrorPresentation.swift:44-53` | D2 `attention` + P39 copy table. | S (after D2) |
| G14 | Unresolved reset prints "Available" / "Reset info unavailable" on the phone; the Mac prints nothing | `Countdown.swift:96-113`; `MeterStyle.swift:572-578` | Decide. The Mac's blank is the honest default. | S |
| G15 | Pending provider renders an empty tile | P24 | Skeleton. | S |
| G16 | Spend amount uses `minimumScaleFactor(0.76)`; widgets forbid it (WCF7, AGENTS.md); the popover never scales | `APISpendMirrorView.swift:110` | Fixed column (P48). | S |
| G17 | Settings "Widgets: Enabled/Paused" reads the *phone-sync* status (the phone envelope is projected with `syncToIPhoneEnabled`), so it always says "Enabled" in the content state | `SettingsSheetView.swift:67-72`; `UsageStore.swift:1082-1085` | Relabel ("iPhone sync: On") or drop. | S |
| G18 | App Store listing: 1 iPad shot (light, about 75% empty, stale "Prolite"), 2 iPhone shots (brief) | `.context/ios-audit/appstore/` | Depends on G1 + P-series. Out of scope here. | — |

---

## 13. Widgets and surfaces (W1–W9)

| ID | Surface | State / source | Notes |
|---|---|---|---|
| W1 | Home Screen widgets small/medium/large, four styles × two color modes | **At parity**: one shared intent and shared bodies (`HeadroomIOSWidgets/HeadroomIOSWidgets.swift:11-29`; `project.yml:128-137`) | Remaining device-only checks are in `BUGS.md:716-770`. |
| W2 | In-app widget gallery / explainer (Mac has Settings › Widgets & iPhone) | S10 | Needs shared UI in the app target (B2). |
| W3 | Menu bar pills, slosh, vessel glyph | MAC-only (`MenuBarLabel.swift`, `MenuBarSlosh.swift`, `VesselGlyph.swift`) | Closest phone analogue: W4. |
| **Beyond parity, for discussion** | | | |
| W4 | Lock Screen accessory widgets (circular / rectangular / inline) | Feasible: same App Group cache and KVS read as the current timeline provider, so the same freshness. A circular `Gauge` maps to the vessel. | S–M |
| W5 | StandBy | Small widgets already appear in StandBy (iOS 17+). The look is unmeasured (`BUGS.md:720-722`). | S (device look only) |
| W6 | Control Center control (iOS 18 `ControlWidget`) | Feasible as an "Open Headroom · Claude 38%" button reading the cache. How often the value refreshes outside app reloads is unverified. | M |
| W7 | Live Activities | Weak fit. Updates need the app running or APNs pushes from a server (there's none), and CloudKit can't drive them. A frozen activity using `Text(timerInterval:)` could tick a reset countdown by itself, but the percentage would freeze. | M, low value |
| W8 | "Ask my Mac to refresh" (phone pull-to-refresh writes a KVS request key; the always-running Mac observes `didChangeExternally` and runs `refreshNow()`) | Feasible in principle and stays compliant (the Mac still runs the official CLIs). KVS propagation latency is unverified (seconds to minutes). It would unlock P58 receipts on the phone. | M |
| W9 | Siri / Shortcuts App Intents ("How much Claude do I have left?"), interactive widget refresh (`BUGS.md:728`), Apple Watch (`BUGS.md:444-447`) | Intents: S–M, read the cache. Watch: L, deferred. | — |

---

## Systemic recommendations

1. **Create one shared cross-platform UI folder** (e.g. `Sources/HeadroomSharedUI`, built like
   `HeadroomWidgetSharedUI`). Compile it into the macOS app, the iOS app, and an SPM target. First
   residents: `MeterGauge`, `ProviderStyle`, `IdentityCapsule`/`identityMetadataLabel`,
   `StatusSentence`, `PlanCapsule`, `SkeletonMeter`, `DotMatrixSpinner`, and the non-AppKit half of
   `HeadroomMotion`. Delete the Mac originals rather than duplicating them (B4).
2. **Port the popover row, not the iOS row.** Make `UsageBarView` platform-neutral by swapping
   `NSFont`/`OpticalLeading` for the CoreText helpers that already exist in
   `HeadroomWidgetTypography.swift`, and feed it envelope rows through a
   `UsageWindow(widgetSummary:)` adapter in Core (D12).
3. **Collapse the three color layers** (`ProviderStyle`, `HeadroomTheme`, `HeadroomWidgetStyle`)
   into the shared `ProviderStyle`. `HeadroomTheme` keeps only phone layout (background, tile).
4. **Include `HeadroomCore/Models` and `Notifications` wholesale** in both iOS targets instead of
   the 9-file list. They're Foundation-only. Add an iOS simulator build to the pre-PR check.
5. **Run the envelope work as its own stream with an explicit size budget.** Additive optional
   fields only, primary kept at top level forever, slim account windows, per-provider keys or a
   cap, coalesced publishes, and observing KVS quota violations (D2, D9).
6. **Decide phone-local vs mirrored display prefs up front.** Recommendation: phone-local Theme;
   meter style, percentage mode and title ink as phone-local settings whose default is "Same as
   Mac" (needs D2 `display`). Either way the shared picker views port as-is.
7. **Keep iOS idioms where the Mac's choice is window-specific:** large title, sheet Settings
   built on a native `List` (with Headroom swatch rows inside), pull to refresh, opaque Core-tokened
   tiles. Port the content metrics (type ramp scaled by one `@ScaledMetric`, 21pt meter inset,
   capsules, inks), not the popover window chrome.
8. **Give the phone its own typed copy for anything that's an action on the Mac.** Status sentences
   become non-interactive lines with "on your Mac" phrasing keyed by a typed `attention` value,
   never by the Mac's CLI-directed sentence (P39).
9. **Clear the cheap drift first, independent of the envelope:** "Low" chip, amber attention, blue
   tint, row order, bare countdowns, red Critical numeral, stale copy, the stale UI test,
   skeletons, and an oldest-live stamp. All of these are Core-ready (G2–G8, G12–G17, P15–P24).
10. **Notifications and the tip jar each need an explicit product decision before planning.**
    Notifications: none, local best-effort, or CloudKit push (N3). Tip jar: IAP, a US-only link,
    or omit (S14). Neither should be scoped silently.

---

Method note: during the size check I tried to read the Mac's App Group snapshot file with
`find` and `python3`. Both hung, most likely on a macOS "access data from other apps" privacy
prompt. I stopped both processes and confirmed nothing was left running. The 2,281-byte figure
comes from `ls` only. If a privacy prompt appeared on screen, it can be denied.
