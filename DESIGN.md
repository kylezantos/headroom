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
6. **Motion only from `HeadroomMotion`** (macOS; iOS uses `HeadroomTheme`). Never declare
   your own curve, duration, or spring in a view. No pulsing, breathing, or looping
   attention animations, ever.
7. **Provider parity** (AGENTS.md): styling reaches Claude, Codex, Grok, and Cursor alike.
   Per-provider values go through `ProviderStyle`. Never special-case one provider's look inline.
8. **Chrome is restrained and layered.** Low-alpha fill + faint ring + 1pt inset lip + 1pt
   shadow. Never a bright rim (keep it ≤ ~0.15 white in dark). Content tiles are never a
   second `.glassEffect` (glass is only for the shell and controls).

## Where tokens live

All paths are under `Sources/`.

| Concern | Token home | Notes |
|---|---|---|
| Motion | `HeadroomApp/UI/HeadroomMotion.swift` | `settle` (house curve, 200ms), `quickSettle`, `pressDown` + `pressScale` 0.96, `hoverIn`/`hoverOut`, `valueSpring` (critically damped, never overshoots a value), `reorder`, `paneIn`/`paneOut`, `partIn`/`partOut`. Reduce Motion: wrap with `resolved(_:_:reduceMotion:)`, `fade`, `numericText`. |
| Brand & semantic colour (shared with widgets/iOS) | `HeadroomCore/Models/BrandColorValues.swift` | `HeadroomBrandColorValues`, `HeadroomBrandRamp` (OKLCH), `HeadroomWidgetColorValues` (text inks, hairlines, wells, fills), `HeadroomSeverityColorValues`. SwiftUI-free. |
| Colour call surface (macOS) | `HeadroomApp/UI/ProviderStyle.swift` | `accent`, `textAccent`, `secondaryText`/`tertiaryText`, `accountTitleInk`, meter inks, `severityColor`/`severityFill`, `recessedWell`, CTA gradients, SVG mark per scheme. |
| Popover shell | `PopoverCardMetrics` (`PopoverView.swift`) | Shell width 384, margin 19, card width derived from them. |
| Provider card | `ProviderCardView.swift`, `IdentityRowMetrics` | Card: `.padding(13)` + `.raisedTile(cornerRadius: 10)`. Identity row: mark slot 15, gap 6, title 15 semibold / −0.15 kern, capsule height 18, capsule label 10.5 medium / +0.2 kern. |
| Capsules & chips | `IdentityCapsuleStyle`, `.identityCapsule(fill:horizontalPadding:border:)` | Metadata fill 0.12, stale fill 0.18, state border 0.35 @ 1pt. |
| Setup cards | `SetupCardMetrics`, `ClaudeSetupStyle`, `CodexSetupStyle` | Gaps 6 / 12 / 20. Body 12.5, notes 11. The two provider enums stay decoupled by design; their numbers live in `HeadroomBrandRamp`. |
| Settings spacing | `SettingsMetrics` (`SettingsRows.swift`) | labelToControl 4 · labelToStackedControl 6 · withinGroup 8 · headerToContent 10 · groupToGroup 20 · tileToTile 28. Segmented pickers max 220 wide. |
| Settings type | `SettingsType` (`SettingsRows.swift`) | paneTitle 20 semibold · tileTitle 15 semibold · groupLabel 13 semibold · help 11 · swatchLabel 11 medium · footnote 10. Neighbouring roles differ in size or ink, not weight alone. |
| Settings copy | `SettingsCopy` | Any string two panes print. |
| Optical alignment | `HeadroomApp/UI/OpticalLeading.swift` | `.opticalLeading(_:size:weight:)` for text starting a card line; `.capHeightCentered(size:weight:)` for mixed-size rows. Not for chip labels. |
| Widgets / iOS | `HeadroomCore/Widgets/WidgetMetrics.swift`, `WidgetTypeScale.swift`, `WidgetStyleTokens.swift` (`WidgetStyleType` hero numerals, `WidgetStyleMetrics` bars, rails, wash), `WidgetVesselGeometry.swift`, `HeadroomWidgetSharedUI/` | Widget-only type ladders and optics (CoreText, since AppKit isn't available there). Hero numerals are fixed size; labels keep Dynamic Type. The widget vessel keeps the menu-bar 11:18 proportion and is sized to the numeral's digit ink (`HeadroomWidgetFontMetrics.digitInk`). Color comes from `WidgetStyleColors.fill(for:colorMode:)`. Contracts: `docs/plans/2026-09-11-001-feat-widget-craft-plan.md` (WC anchors still in force) and `docs/plans/2026-10-02-1247-feat-widget-styles-plan.md`. |
| iOS companion app | `HeadroomIOS/DesignSystem/` | `HeadroomTheme` (tile radius 17, its own entrance/value animations, provider colours) and `.headroomTile` (`Elevation.swift`, ring-glow elevation from `design/ios-companion.html`). Colours come from the same Core values. |
| Meter rendering | `HeadroomCore/Models/MeterStyle.swift` (`MeterRecipe`) → `MeterGauge` | The pure format × shape × fill contract. `MeterGauge` is the popover's only meter renderer. |

**Known gaps:**
- iOS keeps its own motion values in `HeadroomTheme` rather than sharing `HeadroomMotion`.
  Keep the two in step by hand (e.g. both `valueSpring`s are critically damped, M1A).
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
| Any text-labelled secondary button | `SetupChipButtonStyle` (`.regular` card foot, `.small` account row) | `HoverButtonStyle` on a word |
| Glyph-only control (gear, +, …, copy, trash, chevron) | `HoverButtonStyle` | A chip container |
| A row of card actions | `CardActionRow` / `ActionChipFlow` | Manual `HStack` wrapping |
| Account / spend title line | `IdentityRow` | Re-deriving title recipe |
| Status line under an account | `StatusSentence` + `StatusSentenceSeverity` | Severity (meter) colours |
| Plan / period / stale capsule | `.identityCapsule`, `PlanCapsule` | Padding-sized capsules (they drift in height) |
| Usage meter | `UsageBarView` / `MeterGauge` via `MeterRecipe` | New bar drawing |
| Widget style body | `HeadroomWidgetStyledBody` + `HeadroomWidgetStyledBackground` over a `WidgetStyleRecipe`; pieces `HeadroomWidgetStyleBar`, `HeadroomWidgetVessel`/`HeadroomWidgetVesselNumeral`, `HeadroomWidgetNumeral`, `HeadroomWidgetIdentityRow`, `HeadroomWidgetFittingCaption` | Per-host widget layouts; deciding windows or fills in a view |
| Loading placeholder | `SkeletonMeter` | Spinners, pulses |
| Provider mark | `ProviderLogoView` (macOS and iOS each have one) | Loading SVGs directly |
| Revealing a Settings sub-option | `.transition(.settingsReveal)` | Ad-hoc slide/scale |

## Verifying a UI change

- Fast headless check: `swift run Headroom --render-popover <dir> [--meter-style …]`. This
  is a sanity check only, not final evidence (see `BUGS.md`).
- Final check: `swift run Headroom --demo <scenario>` in the live popover, both light and
  dark appearances. Ask before driving the screen.
- Check both appearances, and Increase Contrast/Reduce Transparency (tiles fall back to
  solid + separator).
- Design explorations and decisions: `design/*.html` (options docs) and `docs/plans/`
  (anchors cited in code comments). Motion rationale:
  `docs/plans/2026-09-04-002-feat-subtle-motion-system-plan.md`.
