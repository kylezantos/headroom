# DESIGN.md — Headroom design system

Read before adding or changing UI. The tokens live in code, and the comments beside each one
hold its rationale (anchors like `R2C19`, `PA11b`). This file is the index: where each token
lives, which component does which job, and the rules for extending them.

## Rules

1. **Use a token or say why not.** Before writing a literal size, gap, radius, colour, or
   curve, look for it in the tables below. If a one-off literal is genuinely right, give it a
   one-line WHY comment. A bare magic number is a review finding.
2. **A new token needs a second call site.** A value used in one place stays a commented local
   constant. Once a second site needs it, promote it into the surface's `…Metrics`/`…Style`
   enum. If a Settings pane or widget also needs it, move it to Core
   (`HeadroomWidgetColorValues`, `HeadroomBrandRamp`).
3. **Colours are WCAG-checked and scheme-paired.** Every ink/fill token takes `dark:` or
   `scheme:`. Don't use `.secondary`/`.tertiary` for text on cards; use
   `ProviderStyle.secondaryText`/`tertiaryText` (system tertiary measures ~2.3:1 on a dark tile).
   Brand values are OKLCH stops, and contrast is asserted in `BrandColorValuesTests`.
4. **One meaning per colour.** Severity colours (green >50% remaining, amber ≤50%, red ≤15%;
   see `UsageSeverity`) mean *usage level* only. Account/lifecycle states use neutral ink.
   Red is reserved for a provider refusal (`StatusSentenceSeverity.critical`). A stale meter
   keeps its severity hue at 35% chroma for Low and Critical (craft round 2's R2C16). Stale
   healthy is narrower since CA-P1: in a fill mode whose live healthy meter is neutral (today
   only "Only when low", `MeterRecipe.livePaintsHealthyNeutral`), it paints that neutral at
   half alpha (`HeadroomMeterColorValues.staleNeutralScale` 0.5), so a stale row is never the
   only green bar on a card. The widget's `staleNeutralFill` is not reused there: it was tuned
   on the widget track (see
   `docs/solutions/ui/stale-fill-token-measured-against-the-wrong-track.md`).
5. **Things that look the same behave the same.** A filled, outlined chip is *state*; a flat
   pill is a *metadata label* (`IdentityCapsuleStyle`). Every text button has a resting
   container; bare glyph buttons only in toolbar/title rows.
6. **Motion only from `HeadroomMotion`** (one shared vocabulary on both platforms; the
   phone's only motion of its own, the once-per-launch card entrance, lives in
   `HeadroomIOS/DesignSystem/HeadroomMotion+Phone.swift`, timed by Core's
   `PhoneCardEntranceSchedule`). Never declare
   your own curve, duration, or spring in a view. No pulsing, breathing, or looping
   attention animations, ever. The loading drip is the approved exception: one falling
   drop per 1.8s while waiting on the user, with a 0.45s fall and 0.6s ripple; no scale or
   opacity pulse. Slosh, print, ghost wipe, end hold and drain durations live in
   `HeadroomCore/Widgets/LoadingMotion.swift` (loading-language KTD21).
7. **Provider parity** (AGENTS.md): styling reaches Claude, Codex, Grok, Cursor, Antigravity, Copilot, and OpenCode alike.
   Per-provider values go through `ProviderStyle`. Never special-case one provider's look inline.
8. **Chrome is restrained and layered.** Low-alpha fill + faint ring + 1pt inset lip + 1pt
   shadow, one layer per job. Never a rim above 0.15 white in dark
   (`HeadroomTileEdgeValues.darkRimCeiling`, asserted in `BrandColorValuesTests`). The dark
   popover card (CA-P2) is the setup chip's recipe at card scale: an even 1pt ring at white
   0.07 (`darkGlassRingOpacity`), a 1pt inset lip at white 0.10 (`darkGlassLipOpacity`)
   masked to fade out by 55% of the card's height, a contact shadow (black 0.40, radius 0.5,
   y 1) and an ambient shadow (black 0.30, radius 4, y 2). It replaces craft round 2's R2C1
   gradient stroke (white 0.20 top to black 0.22 bottom, one 0.6 shadow at radius 10), whose
   top was the brightest line in the popover. Light cards and the Increase Contrast branch
   are unchanged. Settings tiles have their own flat recipe (rule 9). Content tiles are never
   a second `.glassEffect` (glass is only for the shell and controls).
9. **Settings is flat and selects in ink.** A Settings tile (`.raisedTile(surface: .opaque)`,
   CA-S1, the craft audit plan's KTD4) is a flat fill with a translucent 1pt ring: dark is white 0.06 with a white
   0.09 ring and no shadow (a dark canvas cannot show one); light is `controlBackgroundColor`
   with a black 0.07 ring and two tight shadows (black 0.05 radius 0.5 y 1, black 0.04 radius
   2 y 2). Settings no longer inherits the popover card's R2C1 rim and gradient. Selection is
   neutral ink, never the system accent (CA-S2, overturning the pre-ship audit's accent
   decision): the plate is a 1.5pt ring at primary 0.85 over a primary 0.045 fill (0.07 on
   hover), `SettingsSelectionInk`. Text links are `SettingsInlineLink` (11pt secondary,
   primary on hover, `arrow.up.right` when the link leaves Headroom), never `.link` or `Link`.
   Sidebar glyphs are secondary. Switches stay native and are the one place the accent says
   "on". The phone's ring was already label ink.

## Where tokens live

All paths are under `Sources/`.

| Concern | Token home | Notes |
|---|---|---|
| Motion | `HeadroomSharedUI/HeadroomMotion.swift` | The house curve's control points once, `houseCurve` (0.22, 1, 0.36, 1), with `houseCurve(duration:)`, `settleDuration` 0.20 and `valueSpringResponse` 0.3 / `valueSpringDampingFraction` 1.0 (CA-F1): `settle`, AppKit's `windowCurve` and the `HeadroomTuning` defaults are all built from them, never copied. `settle` (200ms), `quickSettle`, `pressDown` + `pressScale` 0.96, `hoverIn`/`hoverOut` (glyph pills), `rowHoverIn`/`rowHoverOut` (plain ease for full-width rows whose ink changes on hover), `valueSpring` (critically damped, never overshoots a value), `reorder`, `paneIn`/`paneOut`, `partIn`/`partOut`, `arrivalDelay`/`arrivalSpring` (first-open draw-in). Reveal geometry: `revealBlur` 1.5 and `revealScale` 0.97. A removed view fades on `partOut` (80ms, CA-M2, KTD8), never on its scope's curve. `drain` is the Settings account drain, linear over the loading language's `drainDuration` 1.1s (CA-M3). Reduce Motion: wrap with `resolved(_:_:reduceMotion:)`, `fade`, `numericText`. AppKit event detection and window curve stay in `HeadroomApp/UI/HeadroomMotion+AppKit.swift`. The `hover` and `press` compatibility aliases are gone. |
| Phone launch entrance | Core `Widgets/MirrorPresentation.swift` (`PhoneCardEntranceSchedule`) → `HeadroomIOS/DesignSystem/HeadroomMotion+Phone.swift` | CA-M5: one entrance per launch, per card: 0.28s on the house curve, 0.055s apart, every card past the fourth starting with the fourth, a 10pt rise (none under Reduce Motion), and meters that paint their final value inside the rising card (`metersDrawIn` false). Worst case the last card starts 0.22s in, however many accounts. This overturns the iOS parity plan's KTD16, a per-account stagger capped at the eighth account with the meters drawing in on top; KTD16's once-per-launch rule stays. |
| Brand & semantic colour (shared with widgets/iOS) | `HeadroomCore/Models/BrandColorValues.swift` | `HeadroomBrandColorValues`, `HeadroomBrandRamp` (OKLCH), `HeadroomWidgetColorValues` (text inks, hairlines, wells, fills), `HeadroomSeverityColorValues`, `HeadroomTileEdgeValues` (the Mac tile edges and rule 8's 0.15 ceiling), `HeadroomMeterColorValues` (meter greys; `staleNeutralScale` and the `stale…` neutrals, CA-P1). SwiftUI-free. The dark neutral meter stops are white 0.36 / 0.24 (`glassA`/`glassB`, CA-P10), up from PA1's 0.22 / 0.11, so the dark gauge's middle clears 2:1 against its track and reads at least as clearly as light's. |
| Colour call surface (shared by both apps) | `HeadroomSharedUI/ProviderStyle.swift` | `accent`, `textAccent`, `secondaryText`/`tertiaryText`, `accountTitleInk`, meter inks, `severityColor`/`severityFill`, `recessedWell`, CTA gradients, SVG mark per scheme. `shellStatusInk(scheme:)` (CA-P6) is the popover shell's status ink, for the footer stamp and the header status line: dark `tertiaryText`, light `secondaryText`, because system tertiary measured about 2.3:1 there. |
| Popover shell | `PopoverCardMetrics` (`PopoverView.swift`) | Shell width 384, margin 19, card width derived from them. `shellWidth(columns:)` is 384 for one column and 750 for two (two cards plus the 20pt gap); `cardsHeightCap` 640 is where one column becomes two, and where two columns scroll. Header: "Usage" at 17 semibold (CA-P12, down from 20 bold), one status slot on `shellStatusInk`. While a setup card is in the visible stack the slot is empty, and the phrase returns once that card scrolls out (CA-P8, revisiting PA10's header taken from the card's action). Footer: see the components table. With Scroll vertically, `verticalCardsHeightCap` scrolls at the screen's free height less `popoverChromeHeight`, at most 900 (a 300 guard covers a bad screen reading). |
| Popover columns | Core `AccountColumnsPlanner` (`Models/AccountColumnsPlan.swift`) → `PopoverPlanModel` → `PopoverColumnsLayout` | Card pad 13, card gap 20, account gap 26 (Standard) or 4 (Compact). Never more than two columns. |
| Compact account row | `HeadroomApp/UI/CompactAccountRow.swift` (`CompactAccountRow`, `CompactCardHeader`), decided by Core `CompactAccountRowRecipe` | Approved 2026-10-13: row 26, rows 4 apart, title 13 semibold, cells 84 wide and 12 apart, cell numeral 15 semibold, no per-cell label. One `CompactCardHeader` per card (26pt: 11pt tertiary "5h left"/"wk used" right-aligned over each number column, the provider name over the account names, one hairline) repeats in each column a split card occupies. The provider mark is drawn once, in that header, on the rows' leading edge (CA-P13, overturning the account-layout plan's R9 mark on every Compact row); Standard keeps per-row marks. Meters draw as the Micro twin of the user's style. A Standard section among Compact rows sits 11pt further out each side. With Compact on, the spend card draws in the same idiom, amounts on the cells' trailing edge (CA-P11). |
| Provider card | `HeadroomApp/UI/ProviderCardView.swift`, `HeadroomSharedUI/IdentityRow.swift`, `HeadroomSharedUI/IdentityCapsule.swift` (`IdentityRowMetrics`) | Card: `.padding(13)` + `.raisedTile(cornerRadius: 10)`. Identity row: mark slot 15, gap 6, title 15 semibold / −0.15 kern, capsule height 18, capsule label 10.5 medium / +0.2 kern. A 7×11pt copy of the menu-bar vessel follows the name of the account whose reading feeds a pill, only when its provider has two or more accounts (CA-MB3, `MenuBarPillSource`; overturns L5D's "the first account is the menu-bar account"). |
| Menu-bar label marks | Core `Models/MenuBarLabelGeometry.swift`, `Models/MenuBarPalette.swift`; drawn in `HeadroomApp/UI/MenuBarLabel.swift` | CA-MB1 (KTD7): `markBoxSize` 13 (at 11 the mark read as a speck), `markVesselGap` 3 before its own vessel, and `markedMeterGapExtra` 2 added to the pill gap in front of a marked pill (icon-only 8 to 10, with percentages 16 to 18). The mark is measured in the same layout pass as the attention dot (PB5). `MenuBarPalette.markInk` is the bar's ink at 0.90, so white 0.90 on a dark bar and black 0.85 × 0.90 on a light one: one step under the numeral and monochrome, so severity stays the only colour in the bar (rule 4). Each mark is drawn from its vector at the bar's backing scale with the menu bar's own per-provider sizing, `MenuBarLabelGeometry.markMetrics` (never the popover's `HeadroomBrandMark` size): ink extent Claude 11.5, Codex 11, Grok 12, Cursor 11.5, Copilot 12, OpenCode 11, Antigravity 12, a 0.1pt `markTieLift` on each, and a 0.5pt same-ink outline on Grok, Retina only. Tuned for equal perceived size, not equal weight (Kyle, 2026-11-20: the weight-matched 9.5pt Codex read clearly smaller than Claude's star): every outer ink extent sits within 1pt of the others at 2× (11 to 12pt), a solid mark at most 0.5 to 1pt under the open ones, and weight is left to differ (about 1.85× max/min); edges snap to the pixel grid of the scale drawn, and the ink is clipped to its box. `MenuBarMarkRenderTests` pins the balance. On a 1× bar only, Codex's `>_` is knocked out again (`openCodexPrompt`, a 1.15pt stroke) because the artwork's 0.7pt cut-out rasterizes to speckles. |
| Phone provider card | `HeadroomIOS/Views/PhoneProviderCard.swift` (`PhoneCardMetrics`) | The popover's literals (pad 13, account gap 26, Micro rows 10, Full rows 12), each multiplied by the phone scale at use. One opaque `.headroomTile()` (r17) per provider, every account stacked inside, main first. |
| Phone scale | `HeadroomCore/Widgets/PhoneScale.swift` | KTD3: the phone draws the popover's own rows one Dynamic Type unit up. One `@ScaledMetric(relativeTo: .body)` factor seeded at `defaultFactor` 1.15, passed through `PhoneScale.clamped` (it stops growing at xxxLarge, `maximumFactor` = 1.15 × 23/17), then into every shared row's `scale` parameter. The Mac passes `PhoneScale.popover` (1.0). Never `minimumScaleFactor`. |
| Capsules & chips | `HeadroomSharedUI/IdentityCapsule.swift`: `IdentityCapsuleStyle`, `.identityCapsule(fill:horizontalPadding:border:)` | Metadata fill 0.12, stale fill 0.18, state border 0.35 @ 1pt. |
| Setup cards | `SetupCardMetrics` (`ClaudeSetupViews.swift`), `ClaudeSetupStyle`, `CodexSetupStyle` | Gaps 6 / 12 / 20 (lead, sibling, section). Body 12.5, notes 11, title kerning −0.2. CA-P8 and CA-P3 added `metadataToActionGap` 6 (a metadata line sits closer to the action row it qualifies), `retainedGap` 8 (retained meters under the title) and `titleTextInset` 26 (the 20pt mark plus 6). Claude and Codex share one treatment: titles in primary ink, the trust line as plain metadata (a 10pt glyph 5pt before 11pt text), an old reading's "Last read …" chip on the title line (`SetupCardReadChip`), and Core's copy for every sentence (`ProviderSignInCopy`). The two provider enums stay decoupled by design; their numbers live in `HeadroomBrandRamp`. |
| Settings spacing | `SettingsMetrics` (`SettingsRows.swift`) | labelToControl 4 · labelToStackedControl 6 · withinGroup 8 · headerToContent 10 · groupToGroup 20 · tileToTile 28. Segmented pickers max 220 wide. Trailing controls are `.controlSize(.small)`, the switches' height, so the window has one trailing edge (CA-S10); the API Spend key field and its Save button stay regular together. No heading stacks directly on another (CA-S12). |
| Settings swatch widths | `SettingsSwatchWidth` (`SettingsRows.swift`) | CA-S11: two widths on one 8pt gap. `compact` 76 for the meter rows; `wide` 160 (two compact columns plus the gap) for every other swatch picker: Theme, In-app display, the Menu Bar Display samples. Grids in one pane share column lines instead of running four rhythms. This revisits L12B and T7: L12B's 76pt meter columns stay as `compact`, while the CMM pass's 150pt In-app swatch and T7's adaptive 106–132pt Theme columns are gone. At the minimum window Theme falls back to three columns across the meter grid's 412pt. Fill captions shorten in Settings only, with the full Core name in help. |
| Accounts rows | `AccountRowSlotsLayout`, `AccountRowMetrics` (`AccountsSettingsTile.swift`), decided in `AccountsSettingsInteractions` | CA-S3: every row is three slots. Identity (flexible; name, tags beside it, status as its second line), one state or one native small button (`trailingMinWidth` 96, so "Connected", "Sign In" and "Stop Waiting" end on one x), and the "…" menu (`menuSlotWidth` 26). A second recovery action is the menu's first item. This overturns craft round 2's R2C11 (status trailing, a second button dropped onto its own line) and R2C6 (the popover's sentence printed beside a button naming the same act). |
| Settings type | `SettingsType` (`SettingsRows.swift`) | paneTitle 20 semibold · tileTitle 15 semibold · groupLabel 13 semibold · help 11 · swatchLabel 11 medium · footnote 10. Neighbouring roles differ in size or ink, not weight alone. |
| Settings copy | `SettingsCopy` | Any string two panes print. |
| Phone Settings chrome | `HeadroomIOS/Views/Settings/PhoneSettingsChrome.swift` (`PhoneSettingsStyle`, `PhoneMeterStyleChrome`) | One native `List` sheet (`SettingsSheetView`), so sections, headers and footers are the system's. Swatches 62 wide on 5pt gaps over a 42pt well (r10) in the five-up meter grid; the theme, percentage and name pickers share `pickerWellHeight` 48 (CA-I8); 11pt medium names that keep one weight selected or not; selection ring is label ink at 0.9, never blue. Sections open Appearance, Widgets, iPhone sync, About (CA-I1). While Match my Mac is on, the sections it governs are hidden and return on the crossfade resolver when it is turned off (CA-I7, overturning the iOS parity plan's KTD11, which kept them visible at 0.38 and disabled). Phone copy lives in Core `PhoneSettingsCopy`. |
| Optical alignment | `HeadroomApp/UI/OpticalLeading.swift` | `.opticalLeading(_:size:weight:)` for text starting a card line; `.capHeightCentered(size:weight:)` for mixed-size rows. Not for chip labels. |
| Widgets / iOS | `HeadroomCore/Widgets/WidgetMetrics.swift`, `WidgetTypeScale.swift`, `WidgetStyleTokens.swift` (`WidgetStyleType` hero numerals, `WidgetStyleMetrics` bars, rails, wash), `WidgetVesselGeometry.swift`, `HeadroomWidgetSharedUI/` | Widget-only type ladders and optics (CoreText, since AppKit isn't available there). Hero numerals are fixed size; labels keep Dynamic Type. The widget vessel keeps the menu-bar 11:18 proportion and is sized to the numeral's digit ink (`HeadroomWidgetFontMetrics.digitInk`). Color comes from `WidgetStyleColors.fill(for:colorMode:)`. Dimmed and past-reset states come from the recipe's `WidgetFreshnessTreatment` and are laid out by `HeadroomWidgetFreshnessFrame` for every style. Liquid Level draws its bright surface edge only where it crosses no text band (CA-W1, `WidgetWashSegment.showsEdge`): the band keeps `washEdgeTextClearance` 3 above and below and is taken across the whole `washContentInset` 14–18 range, and the column rhythm it reads (`liquidLargeHeroTop`, `liquidHeroCaptionGap`, `liquidCaptionLineGap`, `liquidLargeRowHeight`, `liquidTailGap`) is shared with the view. WC anchors from the widget craft plan are still in force. |
| Lock Screen widget | `HeadroomCore/Widgets/LockScreenWidgetTokens.swift` (ink levels, numeral and mark sizes, arc, bars, Always On wash, label Dynamic Type cap), `LockScreenInlineVesselArt.swift` | One ink of opaque grays (`Color(white:)`), never white with opacity. Numerals and marks are fixed size; labels scale up to the `xLarge` cap. (KTD5). Captions try their compact wording before truncating (CA-W6). The two-provider inline line gains one rung before the minimal form that keeps every provider's name and drops only Cursor's pool ("Grok 56% · Cursor 37%"), revisiting design 10 / R11 for that rung only. |
| iOS companion app | `HeadroomIOS/DesignSystem/` | `HeadroomTheme` is layout only: screen background, tile fill, tile radius 17. `.headroomTile` (`Elevation.swift`) is the ring-glow elevation from the approved iOS companion mock; its dark top highlight is a stroke of the tile's own shape faded out over the top 12%, so it follows the corner (CA-I4). Ink and provider colour come from `ProviderStyle` and the Core values; motion from `HeadroomMotion` (plus `HeadroomMotion+Phone.swift`). |
| Phone control colours | `HeadroomCore/Models/BrandColorValues.swift` (`HeadroomControlColorValues`) → `HeadroomIOS/DesignSystem/PhoneControlStyle.swift` | Neutral, like the popover; never system blue. The root `.tint`, the filled button's fill and its label (`.headroomProminentButton()`), and the switch on-state (0.62 of the tint) are named light/dark pairs with contrast asserted in `BrandColorValuesTests`. No `AccentColor` asset: the catalog is shared with the Mac app. |
| Meter rendering | `HeadroomCore/Models/MeterStyle.swift` (`MeterRecipe`) → `HeadroomSharedUI/MeterGauge.swift` | The pure format × shape × fill contract. `MeterGauge` is the popover's only meter renderer. |

**Shared UI module ownership.** `HeadroomSharedUI/` holds the popover's stateless pieces that
both apps draw: `MeterGauge`, `UsageBarView`, `IdentityRow`, `IdentityCapsule`, `APISpendRow`,
`PlanCapsule`, `StatusSentence` / `StatusSentenceSeverity`, `SkeletonMeter`, `ProviderStyle`,
`HeadroomMotion`, `Layout/FlowingColumnsLayout` (iPad columns, placed from Core's
`FlowingColumnsPlanner`) and `Settings/MeterStyleTile`. Xcode compiles the folder directly into
both apps and widget extensions; Swift Package consumers use the public `HeadroomSharedUI`
module, which depends on Core and `HeadroomWidgetSharedUI`. A component belongs here only when
it holds no store, no AppKit or UIKit, and no host decision: hosts resolve everything from Core
and pass it in, along with their own mark view (`ProviderLogoView` exists once per app) and a
`scale`. Host chrome is injected, not branched on: `MeterStyleTile` takes a
`MeterStyleTileChrome` (`MacSettingsMeterStyleChrome`, `PhoneMeterStyleChrome`). Mac-only pieces
stay in the app (`AccountSectionView`, `presentedSetupOutcome`, `RaisedTile`, `OpticalLeading`,
`HeadroomMotion+AppKit.swift`); phone-only pieces stay in `HeadroomIOS/DesignSystem/`. Shared rows
measure with CoreText (`widgetOpticalLeading`, `widgetCapHeightCentered`); their Mac metrics are
characterized against `OpticalLeading` in the app tests.

**Known gaps:**
- The popover has no named type ramp or spacing scale the way Settings does. Its values
  are local literals with WHY comments (card pad 13, rhythm 9). Match the neighbouring
  card code, and if you add a second use of a value, promote it (rule 2).

## Components — which one for which job

| Job | Use | Not |
|---|---|---|
| Content tile on the popover or in Settings | `.raisedTile(cornerRadius:surface:)` (`.glass` popover, `.opaque` Settings; each has its own recipe, rules 8 and 9) | Custom background + shadow; nested glass |
| Settings section | `SettingsTile` inside `SettingsPaneScaffold` | Hand-rolled headers |
| Settings row | `SettingsSwitchRow`, `ResponsiveControlRow`, `SettingsGroupLabel`, `SettingsHelpText`, `SettingsSuccessStatus`, `SettingsPillBadge` | Raw `Toggle` + `Text` stacks |
| Swatch / thumbnail picker | `SettingsSwatchButtonStyle` + `.selectionChrome` + `.settingsSelectionGroup`, at a `SettingsSwatchWidth` | Custom selection borders; a selection ring on a control that sets nothing |
| A choice that only changes a preview (Widgets & iPhone style) | `WidgetStylePreviewPicker`: a segmented control labelled "Preview" in `ResponsiveControlRow` (CA-S7, revisiting L9P's thumbnail gallery, which wore the persisted settings' selection ring) | Swatches in `selectionChrome` |
| A text link in Settings | `SettingsInlineLink`; a whole outbound row is `SettingsOutboundRow` (CA-S2) | `.buttonStyle(.link)`, `Link` (system blue) |
| One Settings account row | `AccountRowSlotsLayout` (see the Accounts rows token row) | A second button line, a trailing status sentence |
| Primary action (one per card) | `ClaudePrimaryButtonStyle` / `CodexPrimaryButtonStyle` | A second primary |
| An account's status + its recovery (sign in, try again, install, check now) on a popover card | `CardRowAction`: one line that names its action after a middle dot when the sentence lacks the verb, "Claude Code not found · Install" (CA-P5, partly revisiting craft round 2's R2C7, which wrapped the diagnosis and kept the action in a tooltip); the secondary trails as a glyph; `CardRowStatusLine` / `CardRowWaitingLine` when there is nothing to open | A status sentence with a chip row under it |
| Any other text-labelled secondary button on a popover card | `SetupChipButtonStyle` (`.regular` card foot, `.small` account row) | `HoverButtonStyle` on a word |
| Popover footer Refresh and Quit | Native `.bordered`, `.controlSize(.small)`, 11.5 medium, corner radius 6 (CA-P6, revisiting PA11b's footer size); Refresh's tooltip names ⌘R and the header gear's names ⌘, (`PopoverShortcutHelp`); no new key is bound. The stamp beside them is `shellStatusInk`. | `SetupChipButtonStyle`: a custom style label there was rehosted upside down after an appearance change |
| Text-labelled button in Settings | Native `.bordered` at `.controlSize(.small)` (CA-S3, CA-S10) | `SetupChipButtonStyle`, a second button family |
| Glyph-only control (gear, +, …, copy, trash, chevron) | `HoverButtonStyle` | A chip container |
| A row of card actions | `CardActionRow` / `ActionChipFlow`. A waiting card hosts Stop Waiting in its own action row, and its retained meters sit under its title (CA-P7, CA-P3) | Manual `HStack` wrapping; a second chip row under the card |
| Account / spend title line | `IdentityRow` | Re-deriving title recipe |
| Status line under an account | `StatusSentence` + `StatusSentenceSeverity` | Severity (meter) colours |
| Plan / period / stale capsule | `.identityCapsule`, `PlanCapsule` | Padding-sized capsules (they drift in height) |
| Usage meter | `UsageBarView` / `MeterGauge` via `MeterRecipe`. The suffix column is reserved at the widest term on screen, so every numeral ends on one x whichever word follows it; spend rows follow (CA-P11, overturning CMM12's per-term suffix on the axis). An unavailable Micro row prints "No reading yet" or "No current reading" in its countdown slot (CA-P4, overturning M3A′ for that state only; stale rows keep M3A′'s tooltip). On the phone the gauge goes, then the countdown, before the label truncates (CA-I3). | New bar drawing |
| One account on one line (Compact layout) | `CompactAccountRow` over a `CompactAccountRowRecipe`; its cells are `UsageBarView(compactLabel:)` | A new meter cell, or deciding windows in the view |
| Provider cards in one or two popover columns | `PopoverColumnsLayout` + `.layoutValue(key: PopoverColumn.self, ...)`, placed from `PopoverPlanModel` | A width that changes with data while open, `.offset` handovers |
| API spend line | `APISpendRow` (both apps), resolved from Core `APISpendPresentation` | A phone-only spend row |
| Provider cards across an iPad's width | `FlowingColumns` + `.flowingColumnsCard(id:)` | Fixed column counts, `.offset` handovers |
| Phone filled button / switch | `.headroomProminentButton()` / `.tint(PhoneSettingsStyle.switchTint())` | `.borderedProminent` on the system tint |
| Widget style body | `HeadroomWidgetStyledBody` + `HeadroomWidgetStyledBackground` over a `WidgetStyleRecipe`; pieces `HeadroomWidgetStyleBar`, `HeadroomWidgetVessel`/`HeadroomWidgetVesselNumeral`, `HeadroomWidgetNumeral`, `HeadroomWidgetIdentityRow`, `HeadroomWidgetFittingCaption` | Per-host widget layouts; deciding windows or fills in a view |
| Lock Screen body | `HeadroomWidgetLockScreenBody` over a `LockScreenWidgetRecipe`, with injected `HeadroomWidgetLockScreenArt`; pieces `HeadroomWidgetLockScreenNumeral` (knockout), `…Caption`, `…Arc`, `…NestedBars`, `…Wash`, `…Vessel`, `…BrandMark` | Circle, rectangle and inline Lock Screen layouts; drawing with home widget inks or rendering modes |
| Pending numeric-meter layout | Static `SkeletonMeter` beside the account's loading vessel | Animated skeletons, pulses |
| Loading and waiting vessel | `HalftoneVesselView` / `HalftonePillRow` (shared), `MiniPill` (macOS rows) | Slosh while working, drip while waiting on the user, ghost → print when a fresh reading lands; `SetupMotion` and `ReprintRecipe` decide states. |
| Provider mark | `ProviderLogoView` (macOS and iOS each have one) | Loading SVGs directly |
| Revealing a Settings sub-option | `.transition(.settingsReveal)` (in from `revealBlur`, out on `partOut`, CA-M2) | Ad-hoc slide/scale |
| Removing a Settings account | `SettingsAccountExit`: the row holds its slot while its vessel drains on `drain` (1.1s), its text stays solid for the first 0.8s, then the gap closes on `reorder` (CA-M3). This partly overturns the loading plan's KTD12, which let the drain run independently of the reorder, so the next row slid under it. Reduce Motion stays instant. | Letting the row leave layout before its drain ends |

## Verifying a UI change

- Fast headless check: `swift run Headroom --render-popover <dir> [--meter-style …]`. This
  is a sanity check only, not final evidence (see `BUGS.md`).
- Phone and iPad: headless `xcrun simctl` screenshots of the demo variants
  (`--demo --demo-variant <name> --demo-screen <usage|settings|widgets>`) at the default size and
  xxLarge, both appearances. Never `ImageRenderer`, which ignores Dynamic Type.
- Final check: `swift run Headroom --demo <scenario>` in the live popover, both light and
  dark appearances. Ask before driving the screen.
- Motion and performance: a still proves layout, not what moved or what it cost. Check frames
  and body counts offscreen, before and after, per
  `docs/solutions/ui/swiftui-snappiness-offscreen-measurement-and-hot-spot-checklist.md`.
- Check both appearances, and Increase Contrast/Reduce Transparency (tiles fall back to
  solid + separator).
- Design explorations and plans are kept outside the repo; the decision anchors cited in code
  comments (KTD, R, SM…) refer to them. Durable learnings live in `docs/solutions/`.
