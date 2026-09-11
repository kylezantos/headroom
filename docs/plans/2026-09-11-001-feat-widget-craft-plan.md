# Widget craft (2026-09-11)

Source: `design/widget-craft-options.html` (the audit, 33 areas) and `design/widget-proposed-design.html`
(every recommendation folded into one mock, medium = "columns, dividers dialed"). Kyle approved the
whole set on 2026-09-11: "your widget recommendations are approved. Let's get it into the real thing.
No version bump needed." Work lands on top of `53328bcf` (#118). Decision anchors are `WC` + the
report's area ID (`WCF1` … `WCD3`) and are the WHY citations for code comments.

The full arguments live in `.context/qc/widgets/report.md` (not committed); this plan carries the
decisions and the exact values. Where the mock builder measured a conflict, the mock's resolution
wins and is recorded here.

Standing rules: no pulsing or looping motion; widgets are static timelines, so the only motion is the
`.contentTransition(.numericText())` a reload may carry (WCD3). Swift 6 strict concurrency; every
new value is a Core token with a test; providers and views never throw. **Envelope schema stays at
3** — nothing here changes the wire format.

## Decisions

| Anchor | Decision |
| --- | --- |
| WCF1 | **One type ladder in points, identical on both platforms, read through `@ScaledMetric`.** `WidgetTypeScale` (Core) holds the sizes; views read them via `@ScaledMetric(relativeTo:)` so iPhone keeps Dynamic Type (root cap `xxLarge` stays; inert on macOS). Numerals are `.semibold`, never `.bold`. Ladder: small header 11 medium; name 14 semibold kern −0.15 (large standard 15); meter label 12 medium (large standard 13); countdown/state 11 mono (dense 10.5); numeral small 18 / medium 16 / large standard 18 / dense 16, semibold mono; suffix 11 (dense 10.5); spend amount 13 semibold mono, "used" 11; footer 11 medium mono; status title 14 semibold, message 11.5 medium. Every semantic `Font` style in the widget bodies goes. |
| WCF2 | **Reserved numeral and suffix columns.** Numeral column = the measured width of "100%" at the ladder size: 52 / 47.5 / 42 pt at 18 / 16 / 14 (constants in Core, with the measurement noted). Trailing-aligned; `layoutPriority(1)` on the numeral, the name truncates `.tail`; every `minimumScaleFactor` on a numeral is deleted. The suffix is always laid out and inked `Color.clear` when there is no value (popover R2B2). Large's metadata cluster gets a two-rung `ViewThatFits`: `[label · state · countdown]` → `[label · state]` — the countdown drops whole, never ellipsised. |
| WCF3 | **The content axis, leading side only.** Mark slot + 6 = axis: small 21 (slot 15), medium 22 (slot 16), large 26 / 24 (slot 20 / 18 by type step). Header caption, name, labels **and bars** start on the axis; the mark hangs in the gutter, leading-aligned. Bars run to the content edge; no trailing mirror (a widget has no card padding to mirror — say so in the comment). |
| WCF4 | **One margin rule.** Effective margin = system content margin + 2 residual on every family and both hosts: mac 18; iPhone 14 on small and large (the 4pt reclaim stays, documented), **16 on medium** (WCL4). Large's `h8` → `h2`; macOS large takes the same fixed vertical margin iOS has instead of zeroing it, so both hosts distribute the same slack. iOS medium's `Spacer`-inside-spaced-`VStack` goes: `spacing: 0` + explicit paddings, same tree as macOS. Published as `WidgetMetrics` in Core. |
| WCF5 | **One implementation per surface.** `HeadroomLargeWidgetView` moves into `HeadroomWidgetSharedUI`; `HeadroomIOSWidgetView.small/medium/large` and their helpers are deleted and the shared bodies called, with the footer prefix as a parameter. The small line is rebuilt on `HeadroomWidgetUsageMeter` in a `.glance` configuration (name in the label slot, no label, no suffix). The `dense` / 3-column branches and the medium `scale:` parameter go. One `VesselMark` (the macOS outline-with-liquid-level drawing) in the shared module; the iOS private copy goes. |
| WCF6 | **Stay flat; depth goes into the bar track and the rules.** No inner tile. Bars ≥ 6pt get a shallow well: `strokeBorder(LinearGradient(dark ? [black 0.18, white 0.05] : [black 0.07, white 0.30]), lineWidth: 1/displayScale)`. Rules are true hairlines (WCL4). The unused `tileFill*` tokens stay for the companion. |
| WCF7 | **Nothing overlaps, nothing clips: what does not fit truncates.** (Kyle, 2026-09-11: "anything that doesn't fit should be truncated instead of overlapping accidentally or something else that looks like a bug.") Every row degrades on one ladder: drop the countdown whole → drop the state word whole → **truncate the flexible text with a tail ellipsis** (`lineLimit(1)`, `truncationMode(.tail)`) — the meter label, the provider name, the status message, the footer stamp. Numerals, suffixes, amounts, bars and marks never shrink, clip, or overlap: they are `fixedSize()` only where a flexible sibling is guaranteed to give. No `minimumScaleFactor` anywhere. Every `Text` that could wrap carries `lineLimit(1)` unless the design is multi-line (status messages: `lineLimit(2)` then tail). The spend strip drops the stamp whole, then truncates it, never the amounts. Verified by the harness sweep: no tile may have a child whose frame exceeds the tile's content box. |
| WCM1 | **Healthy paints neutral; colour arrives as an event** (the popover's shipped default, `MeterStyle.default.fill == .colorAsEvent`). `HeadroomWidgetColorValues.neutralFill(dark:)` = white 0.26 dark / `#6B727B` light; the bar paints `severity == .healthy ? neutralFill : severityFill`. Not the user's stored style — the envelope does not carry it. |
| WCM2 | **Critical = red numeral + critical track; the "Low" chip is deleted** (popover AP1 / H3a / R2C15). Numeral ink `criticalText` when `severity == .critical && freshness.isLive`; the track takes `HeadroomMeterColorValues.criticalBarTrack` at critical (`.unavailable` opts out). Applies to the small line too. "low" stays in the accessibility value; the small line becomes one accessibility element. |
| WCM3 | **Stale bars take `staleFill`** (R2C16: the row's severity at 0.35 chroma) via a `WidgetUsageSeverity` overload; with WCM1 a stale-healthy bar is the neutral stale tone `#55575C` dark / `#8D9299` light (new token `staleNeutralFill`; the mock's dark `#8C8D93` composited *above* the live neutral fill, so the merge lowered it between the track and the live fill). The `secondaryText` grey fill is gone. Numeral goes `secondaryText` when the window is not live. |
| WCM4 | **The small family honours window freshness.** `displayPercentRemaining` for numeral and fraction; dimmed when `window == nil || !freshness.isLive`; "—" when nil. (Falls out of WCF5's rebuild; land it first as a three-line fix if the rebuild slips.) |
| WCM5 | **Provider attention reaches the meters and comes off the severity ramp** (R2C5). `provider.freshness` is routed into every meter the family draws, so a stale provider's rows take WCM3's treatment and dimmed numerals. Header glyph = `exclamationmark.circle.fill` in `secondaryText`, cap-centred against the name; the spend strip keeps the triangle in the same ink. Large prints the on-wire `stale(message:)` beside the glyph at 11pt tertiary. Small is dim-only (the glyph does not fit beside the reserved column — measured 137 in 134). |
| WCM6 | **Constant minimum fill** via `MeterGeometry.continuousFillLength(available:fraction:format:)` — `.full` for bars ≥ 6pt, `.micro` below. |
| WCM7 | **Accented / vibrant set recut.** `widgetAccentable()` on the bar fill (not the track), the numeral, and the spend amounts; off the provider names; `.widgetAccentedRenderingMode(.desaturated)` on the brand marks; in non-`.fullColor` modes the bar draws fill `.primary` / track `.primary.opacity(0.20)`. Reasoned, not measured — flagged in `BUGS.md` for a device look. |
| WCM8 | **StandBy / stripped background:** when `showsWidgetContainerBackground == false`, `HeadroomWidgetStyle` returns full-strength neutrals (`.primary` / `.secondary` / track `.primary.opacity(0.22)`), sharing WCM7's non-fullColor path. Flagged for a device look. |
| WCL1 | **Large: three reachable tiers, two type steps, weighted edges, no provider rule.** Rows = provider headers + rendered meters (the spend strip is not counted — the mock's arithmetic: Single 4 → roomy, Everyday 6 → regular, Dense 8 → compact). `LargeWidgetDensity` becomes `roomy ≤ 4`, `regular ≤ 6`, else `compact`; `ultraCompact` and the four-rung `Scale` go; `typeStep` = `.standard` for roomy + regular, `.dense` for compact. Tokens: bar 8 / 7 / 6; header → first meter 6 / 6 / 4; meter → meter 12 / 12 / 8; provider gap floor 16 / 16 / 12; label → bar 7; mark slot 20 / 20 / 18; plan pill at roomy + regular only. (Merge: compact tightened from 5 / 9 / 16 after the harness showed the 8-row mix's ideal height matching the Mac tile to the point, which made the WCF7 rung shed rows the tier had counted.) Large's vertical margin is the system margin alone; the rhythm's weighted edge gaps supply the rest. The inter-provider hairline is deleted; the provider gap is flexible with a 16 floor and the **edge spacers are weighted 0.6×** the provider gap (a `layoutPriority`/proportional spacer pair — the KTD-D amendment: tokens and edge weighting change, structure does not). The spend strip keeps its hairline (1/displayScale) with 9 below. Fill-aware tier selection is the follow-up, recorded in `BUGS.md`. |
| WCL2 | **Grouping ratio.** Header → first meter 6, meter → meter 10 (medium) / 12 (large standard) / 9 (dense); label → bar 7 everywhere (small's 3 and medium's 2 included). |
| WCL3 | **Mark slot from the name's cap height** (`round(1.43 × capHeight)`): small 15, medium 16, large 20 / 18 — the same numbers WCF3 uses. `massCorrection` untouched. |
| WCL4 | **Rules, dialed (Kyle, 2026-09-11: option B).** All rules at `1 / displayScale` with a lifted widget-only token `widgetHairline` = white 0.14 / black 0.10. Large: no provider rule (WCL1), spend rule kept. **Medium: gutter 28; the centre rule is shortened to the meter band** (cap top of the first meter label to the bottom of the last bar in the taller column), centred in the gutter, one device pixel, so each bar ends 14 clear of it; **no spend hairline** — a flexible spacer with a 14 floor separates the spend row; iPhone margin 16 (not 14); spend clusters pinned at natural width, and the stamp drops whole when the run cannot hold amounts + stamp. Same overlay construction on both hosts. |
| WCL5 | **Small spends its slack on the payload.** Header 11 at the axis → rows 22; row = name line (the 18 numeral sets the line box; name → column gap **4**, nothing else) → 6 → bar **8**; row → row 12; one trailing spacer. Header string per WCW7. |
| WCL6 | **Cap-height centring and optical leading, CoreText.** `HeadroomWidgetTypography` in the shared module: `capHeightCentered(size:weight:)` and `opticalLeading(_:size:weight:)` built on `CTFontGetCapHeight` / glyph bounds, cache-safe in an extension process; applied to mark + name + numeral in the small row, mark + name + glyph in headers, and the label column in medium/large. |
| WCL7 | **iOS medium tree mirrors macOS** (folded into WCF4/WCF5). The computed 6.1" overflow disappears with WCF1's 16pt numeral; **verify with one Simulator capture of the 6.1" medium with spend** before the PR closes and note the result in the PR. |
| WCL9 | **Medium prints its countdown where the column can hold it.** `showsResetInline: true` on medium with WCF2's two-rung ladder; the mock measured that a two-column medium at the 28 gutter cannot hold `label + countdown + column + suffix`, so in practice the countdown appears on single-provider medium only. Ship the switch and the ladder; do not force a fit. |
| WCW1 | **Print the countdown, not the tooltip.** `window.resetSchedule.meterResetLine(now:)?.countdown` (`6d 4h`, `3h 15m`, `now`); nothing when unresolved (no "Reset info unavailable", no "Available"). `Countdown.resetText` stays for the accessibility value. |
| WCW2 | **Window labels via one Core accessor** `WidgetWindowSummary.widgetDisplayLabel`: `.weekly` → "Weekly", `.fiveHour` → "5-hour", `.other` → `compactLabel` ("Fable", "Spark"), billing period → its label; fallback "Usage" (WCW7). |
| WCW3 | **Footer.** macOS "Updated N ago" on every family/branch; iPhone "From Mac · N ago"; iOS demo drops "sample · " (the DEMO capsule carries it); `.monospacedDigit()`; ink `secondaryText` for the stamp only. Small keeps no footer. |
| WCW4 | **Status cards.** `WidgetStatusCopy` in Core keyed by a shared status enum, unit-tested; sentence case; small prints the message only (mark + one sentence), medium/large title + message at WCF1 sizes; padding = the family residual so the status axis is the content axis; block vertically centred; macOS `getSnapshot` gets the `context.isPreview` branch iOS already has; `VesselMark.fill` 0.0 for "no reading yet" states (`pending`, `waitingForMac`), 0.46 otherwise. Strings: mac — "No usage yet" / "Open Headroom on this Mac to send usage to widgets."; "Update Headroom" / "This widget needs a newer version of the app."; "Widgets are off" / "Turn on Share data with widgets in Headroom Settings."; "Not checked yet" / "Open Headroom to take the first reading.". iPhone — "Sync is off" / "Turn on Sync usage to iPhone in Headroom on your Mac."; "iCloud is off" / "Turn on iCloud for Headroom in iPhone Settings."; "Waiting for your Mac" / "Open Headroom on your Mac to send a reading."; "Couldn't read the data" / "Open Headroom on your Mac and choose Check Now."; "Update Headroom" / "Update the app on your Mac and iPhone.". |
| WCW5 | **State words where the family has room.** `MirrorPresentation.windowStateText` ungated (medium reads `5-hour · Unavailable   —`); large prints `· Last known N ago` from `observedAt`; medium keeps the bare `· Last known`. Both obey WCF2's ladder (drop whole, never ellipsise). |
| WCW6 | **The spend strip.** No "API" eyebrow. Rule: kept on large, none on medium (WCL4). Items: mark 13 · amount 13 semibold mono · "used"/"left" 11 tertiary 5 after (`APISpendPresentation.directionTerm`), items 10 apart. Large prints `rowStatus(...).shortBadge` after a row that needs attention, tone-inked (warning → `secondaryText`, critical → `criticalText`, neutral → tertiary); medium shows the neutral-ink triangle with the badge in the accessibility label. Clusters at natural width; the stamp drops whole when it cannot fit. |
| WCW7 | **Small header rule and the fallback noun.** Header = "<Noun> left" when every shown provider's primary window shares a period noun ("Weekly" / "Monthly"), "Usage left" when mixed or any provider is pending; `fallbackLabel` "Usage" at every site. |
| WCW8 | **"—" everywhere** (no "--"). DEMO capsule on the state-chip recipe: `low` ink on `low @ 0.16`, `secondary @ 0.35` ring, 9 semibold tracked 0.5, aligned to the content margin. |
| WCW9 | **Plan pill on large at roomy + regular**, after the name, leading-aligned: capsule 15, 9.5 medium kern 0.2, `secondary @ 0.12`, no ring, `planLabel` ink; hidden at compact; none on small / medium (a stated decision). |
| WCD1 | **Neutral names.** Provider names take `accountTitle` (`#9AA2AC` dark / `#5F6771` light); colour lives in the mark and in severity events. (Brand tint stays available as the popover's own user option; not plumbed to widgets — `BUGS.md`.) |
| WCD3 | **The reset that is happening now.** With WCW1 the countdown holds "now" past the deadline (R2M3); at "now" only, the numeral steps to `secondaryText` while the bar keeps its fill; the next capture restores it and the numeral carries `.contentTransition(.numericText())`. |

## Core API this plan fixes (stream A builds, B and C code against it)

```swift
// Sources/HeadroomCore/Widgets/WidgetTypeScale.swift
public enum WidgetFamily: Sendable { case small, medium, large }
public enum WidgetTypeStep: Sendable { case standard, dense }
public struct WidgetTypeScale: Sendable, Equatable {
    public let header: Double            // 11 (small only)
    public let name: Double              // 14 / 14 / 15 / 14
    public let nameKerning: Double       // -0.15
    public let label: Double             // — / 12 / 13 / 12
    public let countdown: Double         // — / 11 / 11 / 10.5
    public let numeral: Double           // 18 / 16 / 18 / 16
    public let suffix: Double            // — / 11 / 11 / 10.5
    public let spendAmount: Double       // 13
    public let spendSuffix: Double       // 11
    public let footer: Double            // 11
    public let statusTitle: Double       // 14
    public let statusMessage: Double     // 11.5
    public let pillLabel: Double         // 9.5
    public let pillHeight: Double        // 15
    public static func scale(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> WidgetTypeScale
    /// Measured width of "100%" in SF semibold monospaced digits at `size`: 52 @18, 47.5 @16, 42 @14.
    public static func numeralColumnWidth(forNumeralSize size: Double) -> Double
}

// Sources/HeadroomCore/Widgets/WidgetMetrics.swift
public enum WidgetMetrics {
    public static let residualMargin: Double = 2          // WCF4
    public static let iOSMarginReclaim: Double = 4         // small + large only
    public static let iOSMediumMargin: Double = 16         // WCL4
    public static let markGap: Double = 6
    public static func markSlot(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> Double   // 15 / 16 / 20 / 18
    public static func contentAxis(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> Double // slot + 6
    public static let labelToBar: Double = 7
    public static let smallHeaderToRows: Double = 22
    public static let smallRowToRow: Double = 12
    public static let smallBarHeight: Double = 8
    public static let mediumHeaderToMeter: Double = 6
    public static let mediumMeterToMeter: Double = 10
    public static let mediumBarHeight: Double = 6
    public static let mediumGutter: Double = 28
    public static let mediumSpendAirFloor: Double = 14
    public static let spendItemGap: Double = 10
    public static let spendRuleToRow: Double = 9
    public static let suffixGap: Double = 5
    public static let hairline: Double = 1  // divided by displayScale in the view
}

// LargeWidgetDensity.swift (rewritten)
public enum LargeWidgetDensity: Equatable, Sendable { case roomy, regular, compact
    public init(providerCount: Int, meterCount: Int)          // rows = providers + meters; ≤4 / ≤6 / else
    public init(envelope: WidgetSnapshotEnvelope)
    public var typeStep: WidgetTypeStep                        // standard / standard / dense
    public var barHeight: Double                               // 8 / 7 / 6
    public var headerSpacing: Double                           // 6 / 6 / 5
    public var meterSpacing: Double                            // 12 / 12 / 9
    public var providerGapFloor: Double                        // 16
    public var edgeGapWeight: Double                           // 0.6
    public var providerIconSize: Double                        // 20 / 20 / 18
    public var showsPlanPill: Bool                             // true / true / false
}

// BrandColorValues.swift additions (HeadroomWidgetColorValues / HeadroomMeterColorValues)
public static func neutralFill(dark: Bool) -> HeadroomTint          // white 0.26 / rgb(0.42,0.447,0.482)@1
public static func staleNeutralFill(dark: Bool) -> HeadroomRGBColor  // #55575C / #8D9299
public static func widgetHairline(dark: Bool) -> HeadroomTint        // white 0.14 / black 0.10
public static func staleFill(for severity: WidgetUsageSeverity, dark: Bool, increasedContrast: Bool) -> HeadroomRGBColor  // overload; healthy → staleNeutralFill
public static func criticalBarTrack(dark: Bool)  // exists

// WidgetSnapshotModels.swift additions
extension WidgetWindowSummary { public var widgetDisplayLabel: String }                  // WCW2
extension WidgetSnapshotEnvelope { public var smallHeaderTitle: String }                 // WCW7
extension WidgetProviderSummary { public var periodNoun: String? }                       // "Weekly" / "Monthly" / nil

// Sources/HeadroomCore/Widgets/WidgetStatusCopy.swift
public enum WidgetStatusState: Sendable, CaseIterable {
    case macSetupNeeded, macIncompatibleSchema, macDisabled, macPending
    case iosDisabled, iosSetupNeeded, iosWaitingForMac, iosCorrupt, iosIncompatibleSchema
    public var title: String; public var message: String; public var vesselFill: Double
}
```

Existing Core that the views must now call: `ResetSchedule.meterResetLine(now:)` (countdown / "now"),
`MirrorPresentation.windowStateText(for:)`, `Countdown.updatedLabel(capturedAt:now:)`,
`APISpendPresentation.rowStatus(...)`.`shortBadge` / `.tone`, `APISpendPresentation.directionTerm(kind:)`,
`MeterGeometry.continuousFillLength(available:fraction:format:)`, `HeadroomBrandMark.markSize(for:slot:)`.

## Streams (file-owned; add, don't rename; every stream leaves ≤5 one-line hand-offs for the others)

| Stream | Owns | Builds |
| --- | --- | --- |
| **A · Core** | `Sources/HeadroomCore/Widgets/WidgetTypeScale.swift` (new), `WidgetMetrics.swift` (new), `WidgetStatusCopy.swift` (new), `LargeWidgetDensity.swift`, `WidgetSnapshotModels.swift` (additions only), `Sources/HeadroomCore/Models/BrandColorValues.swift` (additions only), `Tests/HeadroomCoreTests/LargeWidgetDensityTests.swift`, new `WidgetTypeScaleTests.swift`, `WidgetStatusCopyTests.swift`, additions to `BrandColorValuesTests.swift`, `WidgetSnapshotProjectorTests.swift` or a new `WidgetWindowLabelTests.swift` | WCF1 tokens, WCF2 widths, WCF3/WCF4 metrics, WCL1 density, WCM1/WCM3/WCL4 tokens, WCW2/WCW7 accessors, WCW4 copy — with tests pinning every number and string |
| **B · Shared meter, bar, strip, style, typography, status** | `Sources/HeadroomWidgetSharedUI/HeadroomWidgetSharedUI.swift`, new `HeadroomWidgetTypography.swift`, new `HeadroomWidgetStatusViews.swift` (shared `HeadroomWidgetStatusCard` + `HeadroomVesselMark`) | WCF2 columns + ladder, WCF6 track well, WCM1–WCM8 bar/meter/glyph rules, WCM6 fill floor, WCW1/WCW5 countdown + state text, WCW6 strip, WCW3 footer text style helper, WCW8 dash, WCD1 name ink helper, WCD3 numeral at "now", WCL6 typography, WCW4 status card views. New `HeadroomWidgetUsageMeter` init: `(window:, fallbackLabel:, now:, scale: WidgetTypeScale, family: WidgetFamily, providerIsLive: Bool, showsResetInline: Bool, glance: Bool)`; keep the old init compiling until C switches, then delete it in the merge. |
| **C · Family bodies, hosts, preview** | `Sources/HeadroomWidgetSharedUI/HeadroomWidgetFamilyViews.swift`, new `Sources/HeadroomWidgetSharedUI/HeadroomLargeWidgetView.swift` (moved + rewritten), `Sources/HeadroomWidgets/**` (host, timeline provider, deletions), `Sources/HeadroomIOSWidgets/**` (host, deletions, DEMO capsule), `Sources/HeadroomApp/UI/WidgetPreviewStrip.swift`, `project.yml` + regenerated `Headroom.xcodeproj` (`xcodegen generate`) | WCF3/WCF4/WCF5 layout + margins + module move, WCL1 large rhythm (weighted edges, no rule, plan pill WCW9), WCL2, WCL4 medium rule + gutter + spend air, WCL5 small rhythm, WCL9 medium countdown switch, WCW3 footer strings per host, WCW4 status wiring + `isPreview`, WCW8 DEMO capsule, WCM5 routing `provider.freshness` into meters, WCM4 |

Hand-off seams (stated so streams can proceed in parallel): B's new meter/bar/strip signatures are
the ones above; C calls them with the names in this plan. If B has to deviate, B writes the final
signature into its hand-off list and C's merge adapts. A's token names are final.

## Verification (Fable, at merge)

1. `swift build`; `swift test` (all green, new tests present for every Core number and string).
2. `./Scripts/build-app.sh --deps-only && xcodebuild -project Headroom.xcodeproj -scheme HeadroomAppTests -destination 'platform=macOS' -derivedDataPath ./.xcode-derived test`.
3. `xcodebuild -project Headroom.xcodeproj -scheme HeadroomIOS -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — the iOS widget extension must compile (it was silently broken for a week once).
4. Widget renders through the `.context/qc/widgets/render-harness/` harness, now importing the shared large view directly, across the fixture matrix in both schemes; PIL checks: small numeral column 52, small axis 21, medium gutter 28 with the rule confined to the meter band, no large provider rule, edge gap ≈ 0.6 × provider gap, healthy bars neutral, stale bar below every live fill.
5. One Simulator capture of the 6.1" medium with spend (WCL7) — via `xcrun simctl` headless; no visible Simulator window.
6. `BUGS.md` "Widget craft residuals": WCM7/WCM8 device looks, fill-aware density (WCL1-B), brand-tint names not plumbed (WCD1), envelope items (percentage mode, MeterStyle, capability state), dual-platform harness.

## Not in this round (recorded, not built)

Envelope schema changes of any kind; `MeterStyle` or percentage-mode plumbing; multi-account widget
rows; interactive (`AppIntent`) widgets; localisation of widget strings; a version bump.
