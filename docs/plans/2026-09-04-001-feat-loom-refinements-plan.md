# Loom 2026-09-04 refinements — popover, meters, menu bar, Settings

Source: Kyle's Loom review of main @ `c623f806` (2026-09-04), options doc
`design/popover-settings-refinement-options.html`, decisions pasted back from that doc's
"Copy answers" export. Decision anchors below (`L1A` … `L12B`) are the WHY citations for
code comments.

Reference frames and measurements: `.context/video-review/2026-09-04/frames/INDEX.md` (not
committed). Real tokens with file:line citations were gathered in
`.context/video-review/2026-09-04/TOKENS.md`; the doc's callouts repeat them.

## Decisions

| Anchor | Item | Decision |
|---|---|---|
| L1A | Menu bar label follows the menu bar's own appearance | Approved (1b-A). 1b-B/C denied. Popover light tokens (1a) approved as-is. |
| L2A | Bespoke popover scroll indicator in the 19pt gutter | Approved (2-A) after clarifying that the indicator sits inside the gutter, 8pt from the shell edge, and never over a card. 2-B/C denied. |
| L3A | Top feather mirroring the bottom feather | Approved (3-A). 3-B/C denied. |
| L4B | Card right margin mirrors the label column: 13 / 34 / 34 | Approved (4-B). Current (4-A) and 21pt (4-C) denied. |
| L5D | No main-account badge; order alone plus tooltip | Approved (5-D). The outlined "Main" badge (5-A, shipped on this branch in f586ef68) is removed. |
| L6 | Humanized plan badges | Approved as shipped (f586ef68). No change. |
| L7B | Glass/Ghost cap as a separate shape, not clipped by the fill | Approved (7-B) with Kyle's constants: **Full 2.5 × 10, r 1.25**, overlapping the 8pt track by 1pt top and bottom; **Micro chip 2 × 7, r 0** on the 5pt chip; **Micro tube 7 × 2, r 0** across the 5pt tube. 7-A/C denied. |
| L8A | Flat trailing end on every continuous fill | Approved (8-A): fill is a plain rect clipped by the track shape (the menu-bar vessel recipe), so the base is rounded and the end is flat. Full and Micro, chip/machined/tube, every fill. 8-B/C denied. |
| L9A | Settings window 800 × 700 default, resizable both axes, min 720 × 600 | Approved (9-A). Sidebar 216 ideal / 250 max; detail content column capped at 640; panes scroll; per-pane window heights retired. 9-B/C denied. |
| L9P | Widgets & iPhone preview strip | Approved (9-preview): small + medium widget previews and an iPhone tile above the toggles, from fixture data. |
| L10A | Sidebar identity aligned to the pane title | Approved (10-A): 28pt logo, 14 semibold name, 10.5 version; the logo's vertical center equals the pane title's center; nav begins 14pt below. 10-B/C denied. |
| L11A | Disable "Add Account…" while a provider is off | Approved (11-A), help text "Turn Grok on to add an account." 11-B/C denied. |
| L12B | Format as swatch tiles in the Meter style tile | Approved (12-B): Full / Micro become two swatches in the same style as Shape and Fill; captions sit above each row; every swatch the same width; 8pt gaps; 16pt between rows. 12-A/C denied. |

## Workstreams (parallel, file-owned)

- **W1 Meters** — `MeterStyle.swift` (geometry), `MeterGauge.swift`, `MeterStyleTests.swift`: L7B, L8A.
- **W2 Popover** — `PopoverView.swift`, `ProviderCardView.swift`, `ProviderCardIdentityRows.swift`,
  `UsageBarView.swift`, `APISpendSectionView.swift`: L2A, L3A, L4B, L5D.
- **W3 Menu bar** — `MenuBarLabel.swift`, `VesselGlyph.swift`, `HeadroomApp.swift` (label scene only),
  a small pure palette helper in Core with tests: L1A.
- **W4a Settings shell** — `SettingsView.swift`, `SettingsSidebar.swift`, `SettingsPane.swift`,
  `SettingsPanes.swift` (scaffold only), `HeadroomApp.swift` (settings scene only),
  `AccountsSettingsInteractions.swift`, `AccountsSettingsTile.swift`, `AccountsSettingsInteractionTests.swift`:
  L9A, L10A, L11A.
- **W4b Meter style tile** — `MeterStyleTile.swift`: L12B.
- **W5 Widget previews** — `SettingsPanes.swift` (Widgets pane only), `WidgetSettingsSection.swift`,
  `Package.swift` / `project.yml` if `HeadroomWidgetSharedUI` must become an app dependency,
  `HeadroomWidgetSharedUI` if widget views move there: L9P.

Out of scope: widget and iOS meter rendering (they intentionally carry no popover style), the
Ghost light-contrast residual in BUGS.md, main's 10pt scroller gutter (superseded by L2A on merge).

## Acceptance

`swift build`, `swift test`, and the `HeadroomAppTests` xcodebuild scheme pass on the merged
branch. Visual acceptance follows the AGENTS.md gotcha: the live `MenuBarExtra` window via
`swift run Headroom --demo multi-2 --meter-style <format>.<shape>.<fill>` in both appearances,
never `--render-popover` PNGs. The menu bar label needs a light-wallpaper check by Kyle.
