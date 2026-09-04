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
        #expect(MeterGeometry.microCapThickness == 2.5)
        #expect(MeterGeometry.fullCapThickness == 3.5)
        #expect(MeterRecipe.cellCount(for: .micro) == 5)
        #expect(MeterRecipe.cellCount(for: .full) == 20)
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
