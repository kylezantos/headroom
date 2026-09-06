# Subtle motion system — popover, meters, Settings

Source: Kyle's decisions on `design/motion-design-options.html` (built against main @
`ddc5da5d`, 2026-09-04), pasted back from that doc's "Copy answers" export. Decision anchors
below (`S1A` … `M11A`) are the option IDs from the doc and are the WHY citations for code
comments. The motion inventory the doc was drawn from is `.context/motion-inventory.md` (not
committed); the doc's callouts repeat its file:line cites.

Weighting: Emil (restraint) first, Jakub (polish, subtler exits) second, Apple fluid-interface
rules for springs and Reduce Motion. Standing rules: nothing loops or pulses, nothing exceeds
300ms, one cause produces one motion.

## Decisions

| Anchor | Item | Decision |
|---|---|---|
| S1A | One curve family | Approved. Press adopts the house curve `(0.22, 1, 0.36, 1)`; the stock `easeOut` is retired. S1B/S1C denied. |
| S2A | Reduce Motion policy | Approved. One resolver: opacity/colour crossfades keep their timing under Reduce Motion; anything that travels, scales, blurs, resizes, or rolls digits becomes instant. The six ungated setup-button sites are gated. S2B denied. |
| S3A | Hover and press asymmetry | Approved. Hover-in `quickSettle` 120ms, hover-out `smooth` 180ms; press-down lands inside 100ms of pointer-down, release returns on `settle`. Setup primary buttons keep scale 0.98 but adopt the same timing. S3B/S3C denied. |
| M1A | A capture lands | Approved. Fill length, numeral roll, and severity colour ride one critically damped `valueSpring` (`dampingFraction 1.0`); the "Low" chip appears only after the fill lands, opacity-only on `settle`, via `withAnimation {} completion: {}`. Footer Refresh⇄spinner crossfade unchanged. M1B/M1C denied. |
| M2A | The minute tick | Approved. "Updated N min ago" and every "Resets …" countdown use `numericText(value:)` keyed on the minute value so digits roll with time's direction, on `settle`. Under Reduce Motion: plain swap. M2B/M2C denied. |
| M3A′ | A window goes stale / unavailable / live | Discussed → resolved as **colour only, and Micro hides the state label**. Kyle: the "· Last known …" line must not appear on a Micro gauge because it pushes the gauge and numeral out of the card. Full keeps the label (it has its own row). Micro carries the state through the stale-grey fill and dimmed numeral, moves the text to the row's `.help` tooltip and accessibility label. Motion: fill crossfades to stale grey and numeral ink dims on `settle`; Full's label fades in after the fill settles; on `.unavailable` the fill fades out and the numeral crossfades to "—"; return to live mirrors it. No travel. M3B/M3C denied. |
| M4A | First data after launch | Approved with a note. Skeleton crossfades to the live body; the fill draws from 0 to its value on `valueSpring` and the numeral rolls once from `0%` to its value on the same spring. Kyle saw a stutter in the demo between the digits arriving and settling into place: the shipping version must have **no layout shift** — the numeral column is already fixed-width (`UsageBarView.swift:34-37`), so the roll happens inside a stable frame, and the roll is one `numericText(value:)` transition, never a count-up through intermediate values. Fires only on `.pending → .live`; later polls are M1A. M4B/M4C denied. |
| M5A | Meter style change | Approved. Appearance specimen and popover crossfade old→new recipe on `settle` (`.id(meterStyle)` + `.transition(.opacity)`, the Menu Bar preview pattern at `SettingsPanes.swift:209-217`); `MeterStyleTile` swatch ring animates on the press token to match `ThemeThumbnailPicker`. M5B/M5C denied. |
| M6B | Settings pane switch | Approved **against the recommendation** (Kyle's call): 120ms opacity-only crossfade of the detail column on `quickSettle`. Nothing travels. Sidebar highlight stays native. M6A/M6C denied. |
| M7A | Account list changes | Approved with a note. Reorder on `reorder` spring (`response 0.35, dampingFraction 1.0`); inserted rows use `settingsReveal` (4pt rise + blur), removed rows fade only; the popover card list adopts the same reorder animation keyed on account order. Kyle: the **container contraction after a removal was jerky** in the demo — the row's fade and the container's height change must share one animation scope (same `withAnimation`), so the tile contracts on the spring while the row fades, never after it. M7B/M7C denied. |
| M8A | Connected chip | Approved. Enter opacity + scale 0.96→1 on `valueSpring`; exit opacity-only on `settle`; 4s hold unchanged. M8B/M8C denied. |
| M9C | Popover open | **Superseded 2026-09-06.** M9A (keep the once-per-session fade) was approved on paper, then Kyle reviewed the live build and called for instant: no entrance motion at all, not even on the first open. The fade, its session gate, and the render-harness `forceVisible` escape hatch are removed. |
| M10A | Menu bar numeral | Approved: cut, and record why in `MenuBarLabel.swift`. M10B denied. |
| M11A | Refresh and setup chips | Approved. Footer crossfade kept; setup chips and primary buttons adopt S3A timing and S2A gating. M11B denied. |

## Contract (already on the branch)

`Sources/HeadroomApp/UI/HeadroomMotion.swift` now declares the whole vocabulary. Workstreams
code against it and do not add curves, durations, or springs anywhere else:

- `settle` 200ms, `quickSettle` 120ms, `pressDown` 100ms — all `(0.22, 1, 0.36, 1)`.
- `hoverIn` (= `quickSettle`), `hoverOut` (`smooth` 180ms).
- `valueSpring` `spring(response 0.3, dampingFraction 1.0)`; `reorder` `spring(0.35, 1.0)`.
- `hover` / `press` remain as compatibility names; migrate call sites to the S3A pairs.
- `resolved(_:_:reduceMotion:)` with `Kind.crossfade | .movement`; `numericText(value:reduceMotion:)`
  and `numericText(reduceMotion:)` for `contentTransition`.

Rules for every call site: always `.animation(_, value:)` (never bare), chain with
`withAnimation {} completion: {}` (never `DispatchQueue.asyncAfter`), one `.animation`
modifier per kind so Reduce Motion can resolve crossfade and movement separately, and every
motion site reads `@Environment(\.accessibilityReduceMotion)`.

## Workstreams (parallel, file-owned)

- **W1 Buttons and gating** — `HoverButtonStyle.swift`, `ClaudeSetupViews.swift` (button
  styles only: `ClaudePrimaryButtonStyle`, `SetupChipButtonStyle`), `CodexSetupViews.swift`
  (button style only), `ThemeThumbnailPicker.swift` (ring token), plus a pure unit test for
  `HeadroomMotion.resolved` in `Tests/HeadroomAppTests/HeadroomMotionTests.swift`:
  S1A, S2A (the six ungated sites), S3A, M11A (chips).
- **W2 Meter rows** — `UsageBarView.swift`, `MeterGauge.swift` (only if the fill animation
  scope must move): M1A, M2A (row countdown), M3A′.
- **W3 Popover and cards** — `PopoverView.swift`, `ProviderCardView.swift`,
  `ProviderCardIdentityRows.swift`: M2A (header "Updated"), M4A, M7A (popover card-list
  reorder), M8A, M9A (anchor comment), M11A (footer, confirm unchanged).
- **W4 Settings** — `SettingsView.swift`, `SettingsPanes.swift`, `AppearanceSpecimen.swift`,
  `MeterStyleTile.swift`, `AccountsSettingsTile.swift`, `AccountsSettingsInteractions.swift`
  if the reorder animation scope needs it: M5A, M6B, M7A (Settings list + container).

W1 and W2 both touch nothing in common; W2 and W3 share no file but W3 must not re-animate
what W2 animates inside `UsageBarView`. `HeadroomMotion.swift` and `MenuBarLabel.swift` are
closed; if a workstream needs a new token, it stops and reports rather than adding one.

Out of scope: widgets and iOS (they carry no popover motion), the bespoke scroll indicator
and feathers (L2A/L3A, already tuned), the menu bar (M10A), Full-format layout changes
beyond keeping the state label.

## Acceptance

`swift build`, `swift test`, and
`xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' test`
pass on the merged branch. Visual acceptance follows the AGENTS.md gotcha: the live
`MenuBarExtra` window via `swift run Headroom --demo multi-2` (and `--demo multi-mixed` for
M3A′, `--demo multi-3` for M7A) in both appearances, never `--render-popover`. Reduce Motion on
and off is Kyle's check (agents do not change system accessibility settings). Review motion
with a slowed screen recording: every spring settles without overshoot, no layout shift during
M4A, the Accounts tile contracts on the spring during M7A removals.
