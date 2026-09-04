import Foundation
import Testing
@testable import HeadroomCore

struct MeterStyleTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func optionEnumsExposeStableRawValuesLabelsAndIdentifiers() {
        let formats: [(GaugeFormat, String, String)] = [
            (.full, "full", "Full"),
            (.micro, "micro", "Micro"),
        ]
        let shapes: [(GaugeShape, String, String)] = [
            (.chip, "chip", "Chip"),
            (.machined, "machined", "Machined"),
            (.segmented, "segmented", "Segmented"),
            (.tube, "tube", "Tube"),
        ]
        let fills: [(GaugeFill, String, String)] = [
            (.solid, "solid", "Solid"),
            (.glass, "glass", "Glass + cap"),
            (.ghost, "ghost", "Ghost + cap"),
            (.colorAsEvent, "event", "Color as event"),
            (.hueRamp, "hue", "Hue ramp"),
        ]

        for (value, rawValue, label) in formats {
            #expect(GaugeFormat(rawValue: rawValue) == value)
            #expect(value.id == rawValue)
            #expect(value.label == label)
        }
        for (value, rawValue, label) in shapes {
            #expect(GaugeShape(rawValue: rawValue) == value)
            #expect(value.id == rawValue)
            #expect(value.label == label)
        }
        for (value, rawValue, label) in fills {
            #expect(GaugeFill(rawValue: rawValue) == value)
            #expect(value.id == rawValue)
            #expect(value.label == label)
        }

        #expect(GaugeFormat(rawValue: "unknown") == nil)
        #expect(GaugeShape(rawValue: "unknown") == nil)
        #expect(GaugeFill(rawValue: "unknown") == nil)
    }

    @Test func defaultStyleIsMicroChipColorAsEvent() {
        #expect(MeterStyle.default == MeterStyle(
            format: .micro,
            shape: .chip,
            fill: .colorAsEvent
        ))
    }

    @Test func shapeResolutionAndQuarterMarksCoverTheWholeStyleGrid() {
        for format in GaugeFormat.allCases {
            for shape in GaugeShape.allCases {
                for fill in GaugeFill.allCases {
                    let style = MeterStyle(format: format, shape: shape, fill: fill)
                    let expectedShape: GaugeShape = format == .full && shape == .tube
                        ? .chip
                        : shape

                    #expect(style.resolvedShape == expectedShape)
                    #expect(style.drawsQuarterMarks == (format == .full && shape == .machined))
                }
            }
        }
    }

    @Test func geometryMatchesTheDecidedReferenceDimensions() {
        #expect(MeterGeometry.microChipWidth == 32)
        #expect(MeterGeometry.microChipHeight == 5)
        #expect(MeterGeometry.microMachinedWidth == 32)
        #expect(MeterGeometry.microMachinedHeight == 6)
        #expect(MeterGeometry.microMachinedInset == 1)
        #expect(MeterGeometry.microCellWidth == 6)
        #expect(MeterGeometry.microCellHeight == 5)
        #expect(MeterGeometry.microCellGap == 2)
        #expect(MeterGeometry.microTubeWidth == 5)
        #expect(MeterGeometry.microTubeHeight == 16)
        #expect(MeterGeometry.fullTrackHeight == 8)
        #expect(MeterGeometry.fullTrackInset == 1.5)
        #expect(MeterGeometry.fullCellHeight == 7)
        #expect(MeterGeometry.fullCellGap == 2.5)
        #expect(MeterGeometry.fullMinimumFillLength == 6)
        #expect(MeterGeometry.microMinimumFillLength == 3)
        #expect(MeterRecipe.cellCount(for: .micro) == 5)
        #expect(MeterRecipe.cellCount(for: .full) == 20)
    }

    /// L7B: the cap is its own marker with Kyle's approved constants, not a slice of the fill.
    /// It is longer than its track on purpose — 1pt proud on each side of the 8pt full track
    /// and of the 5pt micro chip and tube.
    @Test func capGeometryMatchesTheApprovedMarkerConstants() {
        #expect(MeterGeometry.fullCap == MeterCapGeometry(
            thickness: 2.5,
            length: 10,
            cornerRadius: 1.25
        ))
        #expect(MeterGeometry.microCap == MeterCapGeometry(
            thickness: 2,
            length: 7,
            cornerRadius: 0
        ))
        #expect(MeterGeometry.cap(for: .full) == MeterGeometry.fullCap)
        #expect(MeterGeometry.cap(for: .micro) == MeterGeometry.microCap)

        // Full · chip and machined: 2.5 wide × 10 tall, 1pt proud of the 8pt track.
        #expect(MeterGeometry.fullCap.width(on: .horizontal) == 2.5)
        #expect(MeterGeometry.fullCap.height(on: .horizontal) == 10)
        #expect(MeterGeometry.fullCap.overhang(onTrackThickness: MeterGeometry.fullTrackHeight) == 1)

        // Micro · chip: 2 wide × 7 tall on the 32×5 chip.
        #expect(MeterGeometry.microCap.width(on: .horizontal) == 2)
        #expect(MeterGeometry.microCap.height(on: .horizontal) == 7)
        #expect(MeterGeometry.microCap.overhang(onTrackThickness: MeterGeometry.microChipHeight) == 1)

        // Micro · tube: the same marker turned a quarter turn — 7 wide × 2 tall on the 5×16 tube.
        #expect(MeterGeometry.microCap.width(on: .vertical) == 7)
        #expect(MeterGeometry.microCap.height(on: .vertical) == 2)
        #expect(MeterGeometry.microCap.overhang(onTrackThickness: MeterGeometry.microTubeWidth) == 1)
    }

    /// L8A: a plain rect of `fraction × available`, floored per format. No end rounding lives
    /// here — the track shape supplies it, which is what makes the trailing edge flat.
    @Test func continuousFillLengthFloorsAndClampsPerFormat() {
        #expect(MeterGeometry.minimumFillLength(for: .full) == 6)
        #expect(MeterGeometry.minimumFillLength(for: .micro) == 3)

        #expect(MeterGeometry.continuousFillLength(available: 100, fraction: 0.74, format: .full) == 74)
        #expect(MeterGeometry.continuousFillLength(available: 32, fraction: 0.5, format: .micro) == 16)

        // Below roughly 6% (full) / 9% (micro) the fill parks at its minimum.
        #expect(MeterGeometry.continuousFillLength(available: 100, fraction: 0.02, format: .full) == 6)
        #expect(MeterGeometry.continuousFillLength(available: 32, fraction: 0.02, format: .micro) == 3)

        #expect(MeterGeometry.continuousFillLength(available: 100, fraction: 1, format: .full) == 100)
        #expect(MeterGeometry.continuousFillLength(available: 100, fraction: 1.4, format: .full) == 100)
        // A track shorter than the floor never overflows its own run.
        #expect(MeterGeometry.continuousFillLength(available: 4, fraction: 0.01, format: .full) == 4)

        for format in GaugeFormat.allCases {
            #expect(MeterGeometry.continuousFillLength(available: 100, fraction: 0, format: format) == 0)
            #expect(MeterGeometry.continuousFillLength(available: 100, fraction: -0.3, format: format) == 0)
            #expect(MeterGeometry.continuousFillLength(available: 100, fraction: .nan, format: format) == 0)
            #expect(MeterGeometry.continuousFillLength(available: 0, fraction: 0.5, format: format) == 0)
        }
    }

    /// L7B: the cap's center rides the fill's trailing edge, parks with the fill at the
    /// minimum length (so it never reaches the track's leading end), and stays inside the
    /// track's own run at 100% rather than hanging half its thickness past the end.
    @Test func capCenterRidesTheFillEndWithoutLeavingTheTrack() {
        let full = MeterGeometry.fullCap
        let micro = MeterGeometry.microCap

        #expect(MeterGeometry.capCenterOffset(fillLength: 74, available: 100, cap: full) == 74)
        #expect(MeterGeometry.capCenterOffset(fillLength: 16, available: 32, cap: micro) == 16)

        // Parked at the minimum fill: the cap's leading edge still clears the track start.
        let parkedFull = MeterGeometry.capCenterOffset(
            fillLength: MeterGeometry.fullMinimumFillLength,
            available: 100,
            cap: full
        )
        #expect(parkedFull == 6)
        #expect(parkedFull - full.thickness / 2 > 0)

        let parkedMicro = MeterGeometry.capCenterOffset(
            fillLength: MeterGeometry.microMinimumFillLength,
            available: 32,
            cap: micro
        )
        #expect(parkedMicro == 3)
        #expect(parkedMicro - micro.thickness / 2 > 0)

        // At 100% the whole marker stays within the track.
        #expect(MeterGeometry.capCenterOffset(fillLength: 100, available: 100, cap: full) == 98.75)
        #expect(MeterGeometry.capCenterOffset(fillLength: 32, available: 32, cap: micro) == 31)
        #expect(MeterGeometry.capCenterOffset(fillLength: 16, available: 16, cap: micro) == 15)

        // Degenerate track shorter than the cap: center it instead of producing a negative.
        #expect(MeterGeometry.capCenterOffset(fillLength: 2, available: 2, cap: full) == 1)
        #expect(MeterGeometry.capCenterOffset(fillLength: 0, available: 0, cap: full) == 0)
    }

    @Test func segmentedCellCountsClampAndKeepANonzeroFloor() {
        for cells in [5, 20] {
            #expect(MeterRecipe.litCellCount(fraction: 0, cells: cells) == 0)
            #expect(MeterRecipe.litCellCount(fraction: -0.1, cells: cells) == 0)
            #expect(MeterRecipe.litCellCount(fraction: 0.03, cells: cells) == 1)
            #expect(MeterRecipe.litCellCount(fraction: 1, cells: cells) == cells)
            #expect(MeterRecipe.litCellCount(fraction: 1.1, cells: cells) == cells)
        }
        #expect(MeterRecipe.litCellCount(fraction: 0.72, cells: 5) == 4)
        #expect(MeterRecipe.litCellCount(fraction: 0.72, cells: 20) == 14)
        #expect(MeterRecipe.litCellCount(fraction: .nan, cells: 5) == 0)
        #expect(MeterRecipe.litCellCount(fraction: 0.5, cells: 0) == 0)
    }

    /// The ramp is a bar fill end to end, so its end stop is the severity *fill* token, not the
    /// text token (Sep 2026 fill/text split) — and it tracks Increase Contrast with the rest of
    /// the meter.
    @Test func rampStopsStayInTheSeverityHueAndEndAtFullSeverity() {
        for scheme in MeterColorScheme.allCases {
            for severity in [UsageSeverity.healthy, .low, .critical] {
                for increasedContrast in [false, true] {
                    let severityFill = HeadroomSeverityColorValues.fill(
                        for: severity,
                        dark: scheme == .dark,
                        increasedContrast: increasedContrast
                    )
                    for surface in [MeterRampSurface.flat, .well] {
                        let stops = MeterRecipe.rampStops(
                            severity: severity,
                            scheme: scheme,
                            surface: surface,
                            increasedContrast: increasedContrast
                        )

                        #expect(stops.end == severityFill)
                        #expect(stops.start != stops.end)
                        #expect(!isNeutral(stops.start))
                    }
                }
            }
        }
    }

    @Test func cellRecipesPreserveEveryFillAndTipContract() {
        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 2,
            fill: .solid,
            severity: .low
        ) == .body(.severity))
        #expect(MeterRecipe.cellRecipe(
            index: 1,
            lit: 2,
            fill: .solid,
            severity: .low
        ) == .tip(.severity))

        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 2,
            fill: .glass,
            severity: .low
        ) == .body(.glass))
        #expect(MeterRecipe.cellRecipe(
            index: 1,
            lit: 2,
            fill: .glass,
            severity: .low
        ) == .tip(.severity))

        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 2,
            fill: .ghost,
            severity: .low
        ) == .body(.ghost))
        #expect(MeterRecipe.cellRecipe(
            index: 1,
            lit: 2,
            fill: .ghost,
            severity: .low
        ) == .tip(.severity))

        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 2,
            fill: .colorAsEvent,
            severity: .healthy
        ) == .body(.neutral))
        #expect(MeterRecipe.cellRecipe(
            index: 1,
            lit: 2,
            fill: .colorAsEvent,
            severity: .healthy
        ) == .tip(.neutral))
        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 2,
            fill: .colorAsEvent,
            severity: .critical
        ) == .body(.severity))
        #expect(MeterRecipe.cellRecipe(
            index: 1,
            lit: 2,
            fill: .colorAsEvent,
            severity: .critical
        ) == .tip(.severity))

        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 5,
            fill: .hueRamp,
            severity: .critical
        ) == .body(.ramp(progress: 0)))
        #expect(MeterRecipe.cellRecipe(
            index: 2,
            lit: 5,
            fill: .hueRamp,
            severity: .critical
        ) == .body(.ramp(progress: 0.5)))
        #expect(MeterRecipe.cellRecipe(
            index: 4,
            lit: 5,
            fill: .hueRamp,
            severity: .critical
        ) == .tip(.ramp(progress: 1)))
        #expect(MeterRecipe.cellRecipe(
            index: 0,
            lit: 1,
            fill: .hueRamp,
            severity: .critical
        ) == .tip(.ramp(progress: 1)))

        for fill in GaugeFill.allCases {
            #expect(MeterRecipe.cellRecipe(index: 3, lit: 3, fill: fill, severity: .low) == .off)
            #expect(MeterRecipe.cellRecipe(index: -1, lit: 3, fill: fill, severity: .low) == .off)
        }
    }

    @Test func fillRecipesHonorFillSeverityAndFreshness() {
        #expect(MeterRecipe.fillRecipe(
            fill: .solid,
            severity: .healthy,
            freshness: .live
        ) == .solid)
        #expect(MeterRecipe.fillRecipe(
            fill: .glass,
            severity: .healthy,
            freshness: .live
        ) == .glass)
        #expect(MeterRecipe.fillRecipe(
            fill: .ghost,
            severity: .healthy,
            freshness: .live
        ) == .ghost)
        #expect(MeterRecipe.fillRecipe(
            fill: .colorAsEvent,
            severity: .healthy,
            freshness: .live
        ) == .neutral)
        #expect(MeterRecipe.fillRecipe(
            fill: .colorAsEvent,
            severity: .low,
            freshness: .live
        ) == .solid)
        #expect(MeterRecipe.fillRecipe(
            fill: .colorAsEvent,
            severity: .critical,
            freshness: .live
        ) == .solid)
        #expect(MeterRecipe.fillRecipe(
            fill: .hueRamp,
            severity: .healthy,
            freshness: .live
        ) == .ramp)

        let observedAt = now.addingTimeInterval(-300)
        for fill in GaugeFill.allCases {
            #expect(MeterRecipe.fillRecipe(
                fill: fill,
                severity: .healthy,
                freshness: .stale(observedAt: observedAt)
            ) == .staleGrey)
            for shape in GaugeShape.allCases {
                let style = MeterStyle(format: .micro, shape: shape, fill: fill)
                #expect(MeterRecipe.fillRecipe(
                    fill: style.fill,
                    severity: .critical,
                    freshness: .unavailable(since: observedAt)
                ) == .none)
            }
        }
    }

    @Test func resetLineKeepsBareAndTooltipCopyInSyncAcrossWindowKinds() {
        let deadline = now.addingTimeInterval(3 * 3_600 + 11 * 60)
        let rolling = UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: deadline)
        let billing = UsageWindow(
            kind: .billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60),
            utilization: 20,
            resetsAt: deadline
        )

        for window in [rolling, billing] {
            #expect(window.resetSchedule.meterResetLine(now: now) == MeterResetLine(
                countdown: "3h 11m",
                tooltip: "Resets in 3h 11m"
            ))
        }
        #expect(ResetSchedule.scheduled(now).meterResetLine(now: now) == MeterResetLine(
            countdown: "now",
            tooltip: "Resets now"
        ))
        #expect(ResetSchedule.unresolved(.absent).meterResetLine(now: now) == nil)
    }

    @Test func launchTokensParseExactlyThreeKnownComponents() {
        #expect(MeterStyle(launchToken: "micro.chip.event") == MeterStyle(
            format: .micro,
            shape: .chip,
            fill: .colorAsEvent
        ))
        #expect(MeterStyle(launchToken: "full.tube.ghost") == MeterStyle(
            format: .full,
            shape: .tube,
            fill: .ghost
        ))
        #expect(MeterStyle(launchToken: "full.blob.solid") == nil)
        #expect(MeterStyle(launchToken: "full.chip") == nil)
        #expect(MeterStyle(launchToken: "full.chip.solid.extra") == nil)
        #expect(MeterStyle(launchToken: "full..solid") == nil)
        #expect(MeterStyle(launchToken: "") == nil)
    }

    private func isNeutral(_ color: HeadroomRGBColor) -> Bool {
        abs(color.red - color.green) < 0.000_001
            && abs(color.green - color.blue) < 0.000_001
    }
}
