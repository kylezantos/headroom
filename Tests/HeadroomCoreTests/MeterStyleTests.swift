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
        // R2C12: the labels name the behavior; the raw values are the stored preference and
        // deliberately did *not* change, so no one's chosen fill migrates on update. This
        // pairing is the whole point of the test — a rename that touched a raw value would
        // silently reset every install to the default.
        let fills: [(GaugeFill, String, String)] = [
            (.solid, "solid", "Always colored"),
            (.glass, "glass", "Glass"),
            (.ghost, "ghost", "Ghost"),
            (.colorAsEvent, "event", "Only when low"),
            (.hueRamp, "hue", "Fade"),
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
        // FS2: the Full cell is the Micro cell scaled up (~2.9×), not its own drawing.
        // MX3: Full cells sit at the 8pt track height with a 10pt proud tip.
        #expect(MeterGeometry.fullCellHeight == 8)
        #expect(MeterGeometry.fullCellGap == 3.5)
        #expect(MeterGeometry.microCellRadius == 1.5)
        #expect(MeterGeometry.fullCellRadius == 2.5)
        #expect(MeterGeometry.fullCellNominalWidth == 16.6)
        #expect(MeterGeometry.fullTipCellHeight == 10)
        #expect(MeterGeometry.tipCellHeight(for: .full) == MeterGeometry.fullCap.length)
        #expect(MeterGeometry.tipCellHeight(for: .micro) == MeterGeometry.microCellHeight)
        #expect(MeterGeometry.fullMinimumFillLength == 6)
        #expect(MeterGeometry.microMinimumFillLength == 3)
        #expect(MeterRecipe.cellCount(for: .micro) == 5)
        // FS1: Full is one cell per 10%, down from 20 cells at 5% each.
        #expect(MeterRecipe.cellCount(for: .full) == 14)
    }

    /// FS2 (Kyle, Sep 2026): "I want them to feel basically the same but adapted for their
    /// size." The Full segmented cell is the Micro cell scaled up (~2.9×), so the two
    /// proportions that carry the family have to hold in *both* formats: the gap is a fifth
    /// to a third of the cell pitch, and the corner radius is roughly a quarter to a third of
    /// the cell height. This test is the guard rail on a later retune of one format alone —
    /// it fails if Micro or Full drifts out of the shared band, not if either number moves.
    ///
    /// MX3 (Oct 2026) widened the gap floor 0.20 → 0.15: Full's tighter 3.5pt gap sits at
    /// ≈ 17% of pitch, Micro's at 25%. The radius band is unchanged.
    @Test func segmentedCellsAreOneFamilyAcrossFormats() {
        let widths: [(format: GaugeFormat, width: Double)] = [
            (.micro, MeterGeometry.microCellWidth),
            // Full cells flex to fill the row; this is the width 10 of them land on across the
            // popover's measured 278pt meter run — (278 − 13 × 3.5) / 14 ≈ 16.6.
            (.full, MeterGeometry.fullCellNominalWidth),
        ]
        // Both formats are covered, so adding a third can't quietly skip the family check.
        #expect(Set(widths.map(\.format)) == Set(GaugeFormat.allCases))

        for (format, width) in widths {
            let gap = MeterGeometry.cellGap(for: format)
            let height = MeterGeometry.cellHeight(for: format)
            let radius = MeterGeometry.cellRadius(for: format)

            let gapShare = gap / (width + gap)
            #expect(gapShare >= 0.15, "\(format) gap/pitch \(gapShare) is below the family band")
            #expect(gapShare <= 0.30, "\(format) gap/pitch \(gapShare) is above the family band")

            let radiusShare = radius / height
            #expect(radiusShare >= 0.25, "\(format) radius/height \(radiusShare) is below the family band")
            #expect(radiusShare <= 0.32, "\(format) radius/height \(radiusShare) is above the family band")
        }

        // The nominal Full width is the run the ratios are stated at, not a rendering
        // constant — it has to keep agreeing with the shipped count and gap.
        let run = Double(MeterRecipe.cellCount(for: .full)) * MeterGeometry.fullCellNominalWidth
            + Double(MeterRecipe.cellCount(for: .full) - 1) * MeterGeometry.fullCellGap
        #expect(abs(run - 278) < 1)

        // The accessors are the family's one source; they must agree with the stored values.
        #expect(MeterGeometry.cellHeight(for: .micro) == MeterGeometry.microCellHeight)
        #expect(MeterGeometry.cellHeight(for: .full) == MeterGeometry.fullCellHeight)
        #expect(MeterGeometry.cellGap(for: .micro) == MeterGeometry.microCellGap)
        #expect(MeterGeometry.cellGap(for: .full) == MeterGeometry.fullCellGap)
        #expect(MeterGeometry.cellRadius(for: .micro) == MeterGeometry.microCellRadius)
        #expect(MeterGeometry.cellRadius(for: .full) == MeterGeometry.fullCellRadius)

        // Full is the Micro cell scaled up, so every dimension has to grow together.
        #expect(MeterGeometry.fullCellHeight > MeterGeometry.microCellHeight)
        #expect(MeterGeometry.fullCellGap > MeterGeometry.microCellGap)
        #expect(MeterGeometry.fullCellRadius > MeterGeometry.microCellRadius)
    }

    /// AP2: the Format › Full swatch derives its cell count from the fragment width instead
    /// of drawing Full's real cells at whatever size a 60pt fragment leaves them (FS1's 10
    /// cells combed to ~3.75pt there, and under FS2's 6.4pt gap they would be ~0.24pt slivers
    /// 14.5pt tall — which is why the override now carries the whole miniature cell, not just
    /// the count). In the 60pt fragment the micro pitch
    /// (6pt cell + 2pt gap) fits exactly 7 — 7 × 6 + 6 × 2 = 54, and an 8th would need 62.
    @Test func swatchSegmentCountFitsMicroSizedCellsInTheFragment() {
        #expect(MeterGeometry.segmentCount(fittingWidth: 60) == 7)
        // Exactly-fitting and just-short widths land on either side of the same boundary.
        #expect(MeterGeometry.segmentCount(fittingWidth: 62) == 8)
        #expect(MeterGeometry.segmentCount(fittingWidth: 61.9) == 7)
        // The micro gauge's own width is the round trip of this math.
        #expect(MeterGeometry.segmentCount(fittingWidth: 38) == MeterRecipe.cellCount(for: .micro))
        // Degenerate widths still yield a drawable gauge rather than an empty HStack.
        #expect(MeterGeometry.segmentCount(fittingWidth: 0) == 1)
        #expect(MeterGeometry.segmentCount(fittingWidth: 1) == 1)
        // The pitch is a parameter, not a constant baked into the helper.
        #expect(MeterGeometry.segmentCount(fittingWidth: 60, cellWidth: 4, gap: 1) == 12)
    }

    /// FS3: the Format › Full swatch previews the real Full row in small — the shipped cell
    /// scaled uniformly to Micro's height, so aspect, gap-to-pitch and radius-to-height match.
    @Test func miniatureFullCellIsTheRealCellScaledToMicroHeight() {
        let real = (
            w: MeterGeometry.fullCellNominalWidth, h: MeterGeometry.fullCellHeight,
            g: MeterGeometry.fullCellGap, r: MeterGeometry.fullCellRadius
        )
        let mini = MeterGeometry.miniatureCell(for: .full)
        let scale = MeterGeometry.microCellHeight / real.h
        #expect(mini.height == MeterGeometry.microCellHeight)
        #expect(abs(mini.width - real.w * scale) < 0.001)
        #expect(abs(mini.gap - real.g * scale) < 0.001)
        #expect(abs(mini.radius - real.r * scale) < 0.001)
        #expect(abs(mini.width / mini.height - real.w / real.h) < 0.001)
        #expect(abs(mini.gap / (mini.width + mini.gap) - real.g / (real.w + real.g)) < 0.001)
        #expect(abs(mini.tipHeight - MeterGeometry.fullTipCellHeight * scale) < 0.001)
        #expect(MeterGeometry.miniatureCell(for: .micro).width == MeterGeometry.microCellWidth)
        #expect(MeterGeometry.miniatureCell(for: .micro).tipHeight == MeterGeometry.microCellHeight)
        // MX3: the wider 8pt-tall Full cell scales to fewer, wider miniatures — four fit the
        // 60pt Format fragment at the shipped proportions (six under FS2's taller cell).
        #expect(MeterGeometry.segmentCount(fittingWidth: 60, cellWidth: mini.width, gap: mini.gap) == 4)
    }

    /// L7B: the cap is its own marker with Kyle's approved constants, not a slice of the fill.
    /// It is longer than its track on purpose — 1pt proud on each side of the 8pt full track
    /// and of the 5pt micro chip and tube.
    @Test func capGeometryMatchesTheApprovedMarkerConstants() {
        // MX1: Full's cap is a 3pt round-ended pill.
        #expect(MeterGeometry.fullCap == MeterCapGeometry(
            thickness: 3,
            length: 10,
            cornerRadius: 1.5
        ))
        #expect(MeterGeometry.microCap == MeterCapGeometry(
            thickness: 2,
            length: 7,
            cornerRadius: 0
        ))
        #expect(MeterGeometry.cap(for: .full) == MeterGeometry.fullCap)
        #expect(MeterGeometry.cap(for: .micro) == MeterGeometry.microCap)

        // Full · chip and machined: 3 wide × 10 tall, 1pt proud of the 8pt track.
        #expect(MeterGeometry.fullCap.width(on: .horizontal) == 3)
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

        // MX1/MX6: the popover's rounded fills floor at their own thickness where that is larger.
        #expect(MeterGeometry.roundedMinimumFillLength(for: .full, thickness: 8) == 8)
        #expect(MeterGeometry.roundedMinimumFillLength(for: .full, thickness: 5) == 6)
        #expect(MeterGeometry.roundedMinimumFillLength(for: .micro, thickness: 5) == 5)
        #expect(MeterGeometry.roundedMinimumFillLength(for: .micro, thickness: 2) == 3)
        #expect(MeterGeometry.continuousFillLength(available: 278, fraction: 0.01, minimum: 8) == 8)
        #expect(MeterGeometry.continuousFillLength(available: 5, fraction: 0.01, minimum: 8) == 5)

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
        #expect(MeterGeometry.capCenterOffset(fillLength: 100, available: 100, cap: full) == 98.5)
        #expect(MeterGeometry.capCenterOffset(fillLength: 32, available: 32, cap: micro) == 31)
        #expect(MeterGeometry.capCenterOffset(fillLength: 16, available: 16, cap: micro) == 15)

        // MX1: flush, the cap's trailing edge lands on the fill end, and it still parks inside.
        #expect(MeterGeometry.capCenterOffset(fillLength: 74, available: 100, cap: full, flushWithFillEnd: true) == 72.5)
        #expect(MeterGeometry.capCenterOffset(fillLength: 8, available: 100, cap: full, flushWithFillEnd: true) == 6.5)
        #expect(MeterGeometry.capCenterOffset(fillLength: 1, available: 100, cap: full, flushWithFillEnd: true) == 1.5)
        #expect(MeterGeometry.capCenterOffset(fillLength: 100, available: 100, cap: full, flushWithFillEnd: true) == 98.5)

        // Degenerate track shorter than the cap: center it instead of producing a negative.
        #expect(MeterGeometry.capCenterOffset(fillLength: 2, available: 2, cap: full) == 1)
        #expect(MeterGeometry.capCenterOffset(fillLength: 0, available: 0, cap: full) == 0)
    }

    @Test func segmentedCellCountsClampAndKeepANonzeroFloor() {
        // Both shipped counts (FS1: Micro 5, Full 10) plus a larger one, because the helper
        // is generic over cell count and the swatch asks it for fragment-derived counts.
        for cells in [5, 10, 20] {
            #expect(MeterRecipe.litCellCount(fraction: 0, cells: cells) == 0)
            #expect(MeterRecipe.litCellCount(fraction: -0.1, cells: cells) == 0)
            #expect(MeterRecipe.litCellCount(fraction: 0.03, cells: cells) == 1)
            #expect(MeterRecipe.litCellCount(fraction: 1, cells: cells) == cells)
            #expect(MeterRecipe.litCellCount(fraction: 1.1, cells: cells) == cells)
        }
        #expect(MeterRecipe.litCellCount(fraction: 0.72, cells: 5) == 4)
        // FS1: at Full's 10 cells a reading rounds to the nearest tenth.
        #expect(MeterRecipe.litCellCount(fraction: 0.72, cells: 10) == 7)
        #expect(MeterRecipe.litCellCount(fraction: 0.62, cells: 10) == 6)
        #expect(MeterRecipe.litCellCount(fraction: 0.72, cells: 20) == 14)
        #expect(MeterRecipe.litCellCount(fraction: 0.72, cells: 14) == 10)
        #expect(MeterRecipe.litCellCount(fraction: 0.12, cells: 14) == 2)
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

    /// MX2 (Oct 2026): Full's Fade is a short, eased ramp — the fill's hue at reduced chroma,
    /// shifted a fixed lightness step toward the card — and Micro keeps the surface-weighted
    /// ramp unchanged. The hue pin from R2C12 holds for both.
    @Test func fullRampIsShortEasedAndHoldsItsHue() {
        for scheme in MeterColorScheme.allCases {
            for increasedContrast in [false, true] {
                for severity in [UsageSeverity.healthy, .low, .critical] {
                    let label = "\(severity) \(scheme) ic=\(increasedContrast)"
                    let stops = MeterRecipe.fullRampStops(
                        severity: severity,
                        scheme: scheme,
                        increasedContrast: increasedContrast
                    )
                    let fill = HeadroomSeverityColorValues.fill(
                        for: severity,
                        dark: scheme == .dark,
                        increasedContrast: increasedContrast
                    )
                    #expect(stops.end == fill, "\(label) end")
                    #expect(stops.easing == HeadroomMeterColorValues.fullRampEasing)

                    let start = HeadroomOKLCH(stops.start)
                    let end = HeadroomOKLCH(stops.end)
                    let shift = start.lightness - end.lightness
                    let expected = HeadroomMeterColorValues.fullRampLightnessShift
                    // Gamut clamping can trim the step by a hair at the saturated ends.
                    #expect(abs(abs(shift) - expected) < 0.02, "\(label) shift \(shift)")
                    #expect(scheme == .dark ? shift < 0 : shift > 0, "\(label) shifts toward the card")
                    #expect(start.chroma < end.chroma, "\(label) start is the quieter end")

                    let reference = end.hue
                    for step in 0...20 {
                        let hue = HeadroomOKLCH(stops.color(at: Double(step) / 20)).hue
                        let drift = abs((hue - reference + 540).truncatingRemainder(dividingBy: 360) - 180)
                        #expect(drift < 2, "\(label) at \(step): \(drift)°")
                    }

                    // Eased out: halfway along the bar is already past halfway to the fill.
                    let halfway = HeadroomOKLCH(stops.color(at: 0.5)).lightness
                    let linearHalfway = (start.lightness + end.lightness) / 2
                    #expect(abs(halfway - end.lightness) < abs(linearHalfway - end.lightness), "\(label) eases")

                    let samples = stops.gradientSamples
                    #expect(samples.count == 9)
                    #expect(channelDistance(samples[0], stops.start) < 0.001)
                    #expect(channelDistance(samples[8], stops.end) < 0.001)

                    // Format routing: Full takes this ramp on every surface; Micro keeps its own.
                    for surface in [MeterRampSurface.flat, .well] {
                        #expect(MeterRecipe.rampStops(
                            format: .full, severity: severity, scheme: scheme,
                            surface: surface, increasedContrast: increasedContrast
                        ) == stops)
                        #expect(MeterRecipe.rampStops(
                            format: .micro, severity: severity, scheme: scheme,
                            surface: surface, increasedContrast: increasedContrast
                        ) == MeterRecipe.rampStops(
                            severity: severity, scheme: scheme,
                            surface: surface, increasedContrast: increasedContrast
                        ))
                    }
                }
            }
        }
        // Micro's linear ramp still draws exactly its three stops.
        let micro = MeterRecipe.rampStops(severity: .low, scheme: .dark, surface: .flat)
        #expect(micro.easing == 1)
        #expect(micro.gradientSamples == [micro.start, micro.midpoint, micro.end])
    }

    /// R2C12: the Fill option named "Hue ramp" was the one thing in the meter that moved hue,
    /// and it did it by accident — both stops were built by mixing the severity fill toward
    /// white or black in sRGB, which swings the amber ~8.5° warmer at its start. The ramp is
    /// now built and traversed in OKLCH at the fill's own hue, so the drift across it is
    /// structurally zero. The 2° bound is slack for gamut clamping at the saturated ends, not
    /// a target: anything approaching it means a stop is being clipped and should be retuned.
    @Test func theRampHoldsItsSeverityHueEndToEnd() {
        for scheme in MeterColorScheme.allCases {
            for surface in [MeterRampSurface.flat, .well] {
                for increasedContrast in [false, true] {
                    for severity in [UsageSeverity.healthy, .low, .critical] {
                        let stops = MeterRecipe.rampStops(
                            severity: severity,
                            scheme: scheme,
                            surface: surface,
                            increasedContrast: increasedContrast
                        )
                        let reference = HeadroomOKLCH(stops.end).hue
                        let label = "\(severity) \(scheme) \(surface) ic=\(increasedContrast)"
                        for step in 0...20 {
                            let progress = Double(step) / 20
                            let hue = HeadroomOKLCH(stops.color(at: progress)).hue
                            let drift = abs((hue - reference + 540).truncatingRemainder(dividingBy: 360) - 180)
                            #expect(drift < 2, "\(label) at \(progress): \(drift)°")
                        }
                        // The start and the midpoint are the two stops the renderers draw.
                        // `color(at:)` round-trips through OKLCH, so the endpoints match to
                        // well under a 1/255 channel step rather than bit-for-bit.
                        #expect(channelDistance(stops.color(at: 0), stops.start) < 0.001, "\(label) start")
                        #expect(channelDistance(stops.color(at: 1), stops.end) < 0.001, "\(label) end")
                        let midpoint = HeadroomOKLCH(stops.midpoint)
                        let start = HeadroomOKLCH(stops.start)
                        let end = HeadroomOKLCH(stops.end)
                        #expect(
                            abs(midpoint.lightness - (start.lightness + end.lightness) / 2) < 0.01,
                            "\(label) midpoint lightness"
                        )
                        // The mix target is hueless, so the start is the *less* chromatic end.
                        #expect(start.chroma < end.chroma, "\(label) start chroma")
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
                shortCountdown: "3h",
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

    private func channelDistance(_ lhs: HeadroomRGBColor, _ rhs: HeadroomRGBColor) -> Double {
        max(abs(lhs.red - rhs.red), max(abs(lhs.green - rhs.green), abs(lhs.blue - rhs.blue)))
    }
}
