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
   Red is reserved for a provider refusal (`StatusSentenceSeverity.critical`).
5. **Things that look the same behave the same.** A filled, outlined chip is *state*; a flat
   pill is a *metadata label* (`IdentityCapsuleStyle`). Every text button has a resting
   container; bare glyph buttons only in toolbar/title rows.
6. **Motion only from `HeadroomMotion`** (one shared vocabulary on both platforms; the
   phone's only motion of its own, the once-per-launch card entrance, lives in
   `HeadroomIOS/DesignSystem/HeadroomMotion+Phone.swift`). Never declare
   your own curve, duration, or spring in a view. No pulsing, breathing, or looping
   attention animations, ever. The loading drip is the approved exception: one falling
   drop per 1.8s while waiting on the user, with a 0.45s fall and 0.6s ripple; no scale or
   opacity pulse. Slosh, print, ghost wipe, end hold and drain durations live in
   `HeadroomCore/Widgets/LoadingMotion.swift` (loading-language KTD21).
7. **Provider parity** (AGENTS.md): styling reaches Claude, Codex, Grok, and Cursor alike.
   Per-provider values go through `ProviderStyle`. Never special-case one provider's look inline.
8. **Chrome is restrained and layered.** Low-alpha fill + faint ring + 1pt inset lip + 1pt
   shadow. Never a bright rim (keep it ≤ ~0.15 white in dark). Content tiles are never a
   second `.glassEffect` (glass is only for the shell and controls).

## Where tokens live

All paths are under `Sources/`.

| Concern | Token home | Notes |
|---|---|---|
| Motion | `HeadroomSharedUI/HeadroomMotion.swift` | `settle` (house curve, 200ms), `quickSettle`, `pressDown` + `pressScale` 0.96, `hoverIn`/`hoverOut` (glyph pills), `rowHoverIn`/`rowHoverOut` (plain ease for full-width rows whose ink changes on hover), `valueSpring` (critically damped, never overshoots a value), `reorder`, `paneIn`/`paneOut`, `partIn`/`partOut`. Reduce Motion: wrap with `resolved(_:_:reduceMotion:)`, `fade`, `numericText`. AppKit event detection and window curve stay in `HeadroomApp/UI/HeadroomMotion+AppKit.swift`. |
| Brand & semantic colour (shared with widgets/iOS) | `HeadroomCore/Models/BrandColorValues.swift` | `HeadroomBrandColorValues`, `HeadroomBrandRamp` (OKLCH), `HeadroomWidgetColorValues` (text inks, hairlines, wells, fills), `HeadroomSeverityColorValues`. SwiftUI-free. |
| Colour call surface (shared by both apps) | `HeadroomSharedUI/ProviderStyle.swift` | `accent`, `textAccent`, `secondaryText`/`tertiaryText`, `accountTitleInk`, meter inks, `severityColor`/`severityFill`, `recessedWell`, CTA gradients, SVG mark per scheme. |
| Popover shell | `PopoverCardMetrics` (`PopoverView.swift`) | Shell width 384, margin 19, card width derived from them. |
| Provider card | `HeadroomApp/UI/ProviderCardView.swift`, `HeadroomSharedUI/IdentityRow.swift`, `HeadroomSharedUI/IdentityCapsule.swift` (`IdentityRowMetrics`) | Card: `.padding(13)` + `.raisedTile(cornerRadius: 10)`. Identity row: mark slot 15, gap 6, title 15 semibold / −0.15 kern, capsule height 18, capsule label 10.5 medium / +0.2 kern. |
| Phone provider card | `HeadroomIOS/Views/PhoneProviderCard.swift` (`PhoneCardMetrics`) | The popover's literals (pad 13, account gap 26, Micro rows 10, Full rows 12), each multiplied by the phone scale at use. One opaque `.headroomTile()` (r17) per provider, every account stacked inside, main first. |
| Phone scale | `HeadroomCore/Widgets/PhoneScale.swift` | KTD3: the phone draws the popover's own rows one Dynamic Type unit up. One `@ScaledMetric(relativeTo: .body)` factor seeded at `defaultFactor` 1.15, passed through `PhoneScale.clamped` (it stops growing at xxxLarge, `maximumFactor` = 1.15 × 23/17), then into every shared row's `scale` parameter. The Mac passes `PhoneScale.popover` (1.0). Never `minimumScaleFactor`. |
| Capsules & chips | `HeadroomSharedUI/IdentityCapsule.swift`: `IdentityCapsuleStyle`, `.identityCapsule(fill:horizontalPadding:border:)` | Metadata fill 0.12, stale fill 0.18, state border 0.35 @ 1pt. |
| Setup cards | `SetupCardMetrics`, `ClaudeSetupStyle`, `CodexSetupStyle` | Gaps 6 / 12 / 20. Body 12.5, notes 11. The two provider enums stay decoupled by design; their numbers live in `HeadroomBrandRamp`. |
| Settings spacing | `SettingsMetrics` (`SettingsRows.swift`) | labelToControl 4 · labelToStackedControl 6 · withinGroup 8 · headerToContent 10 · groupToGroup 20 · tileToTile 28. Segmented pickers max 220 wide. |
| Settings type | `SettingsType` (`SettingsRows.swift`) | paneTitle 20 semibold · tileTitle 15 semibold · groupLabel 13 semibold · help 11 · swatchLabel 11 medium · footnote 10. Neighbouring roles differ in size or ink, not weight alone. |
| Settings copy | `SettingsCopy` | Any string two panes print. |
| Phone Settings chrome | `HeadroomIOS/Views/Settings/PhoneSettingsChrome.swift` (`PhoneSettingsStyle`, `PhoneMeterStyleChrome`) | One native `List` sheet (`SettingsSheetView`), so sections, headers and footers are the system's. Swatches 62 wide on 5pt gaps over a 42pt well (r10), 11pt medium names; selection ring is label ink at 0.9, never blue; controls that Match my Mac governs sit at 0.38. Phone copy lives in Core `PhoneSettingsCopy`. |
| Optical alignment | `HeadroomApp/UI/OpticalLeading.swift` | `.opticalLeading(_:size:weight:)` for text starting a card line; `.capHeightCentered(size:weight:)` for mixed-size rows. Not for chip labels. |
| Widgets / iOS | `HeadroomCore/Widgets/WidgetMetrics.swift`, `WidgetTypeScale.swift`, `WidgetStyleTokens.swift` (`WidgetStyleType` hero numerals, `WidgetStyleMetrics` bars, rails, wash), `WidgetVesselGeometry.swift`, `HeadroomWidgetSharedUI/` | Widget-only type ladders and optics (CoreText, since AppKit isn't available there). Hero numerals are fixed size; labels keep Dynamic Type. The widget vessel keeps the menu-bar 11:18 proportion and is sized to the numeral's digit ink (`HeadroomWidgetFontMetrics.digitInk`). Color comes from `WidgetStyleColors.fill(for:colorMode:)`. Dimmed and past-reset states come from the recipe's `WidgetFreshnessTreatment` and are laid out by `HeadroomWidgetFreshnessFrame` for every style. Contracts: `docs/plans/2026-09-11-001-feat-widget-craft-plan.md` (WC anchors still in force) and `docs/plans/2026-10-02-1247-feat-widget-styles-plan.md`. |
| iOS companion app | `HeadroomIOS/DesignSystem/` | `HeadroomTheme` is layout only: screen background, tile fill, tile radius 17. `.headroomTile` (`Elevation.swift`) is the ring-glow elevation from `design/ios-companion.html`. Ink and provider colour come from `ProviderStyle` and the Core values; motion from `HeadroomMotion` (plus `HeadroomMotion+Phone.swift`). |
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
| Content tile on the popover or in Settings | `.raisedTile(cornerRadius:surface:)` (`.glass` popover, `.opaque` Settings) | Custom background + shadow; nested glass |
| Settings section | `SettingsTile` inside `SettingsPaneScaffold` | Hand-rolled headers |
| Settings row | `SettingsSwitchRow`, `ResponsiveControlRow`, `SettingsGroupLabel`, `SettingsHelpText`, `SettingsSuccessStatus`, `SettingsPillBadge` | Raw `Toggle` + `Text` stacks |
| Swatch / thumbnail picker | `SettingsSwatchButtonStyle` + `.selectionChrome` + `.settingsSelectionGroup` | Custom selection borders |
| Primary action (one per card) | `ClaudePrimaryButtonStyle` / `CodexPrimaryButtonStyle` | A second primary |
| An account's status + its recovery (sign in, try again, install, check now) on a popover card | `CardRowAction` — the sentence is the primary action, the secondary trails as a glyph; `CardRowStatusLine` / `CardRowWaitingLine` when there is nothing to open | A status sentence with a chip row under it |
| Any other text-labelled secondary button | `SetupChipButtonStyle` (`.regular` card foot, `.small` account row, Settings) | `HoverButtonStyle` on a word |
| Glyph-only control (gear, +, …, copy, trash, chevron) | `HoverButtonStyle` | A chip container |
| A row of card actions | `CardActionRow` / `ActionChipFlow` | Manual `HStack` wrapping |
| Account / spend title line | `IdentityRow` | Re-deriving title recipe |
| Status line under an account | `StatusSentence` + `StatusSentenceSeverity` | Severity (meter) colours |
| Plan / period / stale capsule | `.identityCapsule`, `PlanCapsule` | Padding-sized capsules (they drift in height) |
| Usage meter | `UsageBarView` / `MeterGauge` via `MeterRecipe` | New bar drawing |
| API spend line | `APISpendRow` (both apps), resolved from Core `APISpendPresentation` | A phone-only spend row |
| Provider cards across an iPad's width | `FlowingColumns` + `.flowingColumnsCard(id:)` | Fixed column counts, `.offset` handovers |
| Phone filled button / switch | `.headroomProminentButton()` / `.tint(PhoneSettingsStyle.switchTint())` | `.borderedProminent` on the system tint |
| Widget style body | `HeadroomWidgetStyledBody` + `HeadroomWidgetStyledBackground` over a `WidgetStyleRecipe`; pieces `HeadroomWidgetStyleBar`, `HeadroomWidgetVessel`/`HeadroomWidgetVesselNumeral`, `HeadroomWidgetNumeral`, `HeadroomWidgetIdentityRow`, `HeadroomWidgetFittingCaption` | Per-host widget layouts; deciding windows or fills in a view |
| Pending numeric-meter layout | Static `SkeletonMeter` beside the account's loading vessel | Animated skeletons, pulses |
| Loading and waiting vessel | `HalftoneVesselView` / `HalftonePillRow` (shared), `MiniPill` (macOS rows) | Slosh while working, drip while waiting on the user, ghost → print when a fresh reading lands; `SetupMotion` and `ReprintRecipe` decide states. |
| Provider mark | `ProviderLogoView` (macOS and iOS each have one) | Loading SVGs directly |
| Revealing a Settings sub-option | `.transition(.settingsReveal)` | Ad-hoc slide/scale |

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
- Design explorations and decisions: `design/*.html` (options docs) and `docs/plans/`
  (anchors cited in code comments). Motion rationale:
  `docs/plans/2026-09-04-002-feat-subtle-motion-system-plan.md`.
