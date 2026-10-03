import Foundation

public enum GaugeFormat: String, CaseIterable, Identifiable, Sendable {
    case full
    case micro

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .full: "Full"
        case .micro: "Micro"
        }
    }
}

public enum GaugeShape: String, CaseIterable, Identifiable, Sendable {
    case chip
    case machined
    case segmented
    case tube

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .chip: "Chip"
        case .machined: "Machined"
        case .segmented: "Segmented"
        case .tube: "Tube"
        }
    }

    public func resolved(for format: GaugeFormat) -> GaugeShape {
        format == .full && self == .tube ? .chip : self
    }
}

public enum GaugeFill: String, CaseIterable, Identifiable, Sendable {
    case solid
    case glass
    case ghost
    case colorAsEvent = "event"
    case hueRamp = "hue"

    public var id: String { rawValue }

    /// R2C12: names the behavior, not the renderer. "Color as event" was the default's own
    /// internal name, "Hue ramp" described a traversal the fill does not perform, and
    /// "+ cap" put construction in a label whose help line already says the same thing. Raw
    /// values are untouched so no stored preference migrates.
    public var label: String {
        switch self {
        case .solid: "Always colored"
        case .glass: "Glass"
        case .ghost: "Ghost"
        case .colorAsEvent: "Only when low"
        case .hueRamp: "Fade"
        }
    }
}

/// One global meter preference value. Views resolve its shape once and consume the
/// semantic recipes below instead of rebuilding style decisions in SwiftUI.
public struct MeterStyle: Sendable, Equatable {
    public let format: GaugeFormat
    public let shape: GaugeShape
    public let fill: GaugeFill

    public static let `default` = MeterStyle(
        format: .micro,
        shape: .chip,
        fill: .colorAsEvent
    )

    public init(format: GaugeFormat, shape: GaugeShape, fill: GaugeFill) {
        self.format = format
        self.shape = shape
        self.fill = fill
    }

    public init?(launchToken: String) {
        let components = launchToken.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let format = GaugeFormat(rawValue: String(components[0])),
              let shape = GaugeShape(rawValue: String(components[1])),
              let fill = GaugeFill(rawValue: String(components[2]))
        else { return nil }
        self.init(format: format, shape: shape, fill: fill)
    }

    public var resolvedShape: GaugeShape { shape.resolved(for: format) }

    public var drawsQuarterMarks: Bool {
        format == .full && resolvedShape == .machined
    }
}

/// SwiftUI-free dimensions from the approved round-6 reference.
public enum MeterGeometry {
    public static let microChipWidth = 32.0
    public static let microChipHeight = 5.0
    public static let microMachinedWidth = 32.0
    public static let microMachinedHeight = 6.0
    public static let microMachinedInset = 1.0
    public static let microCellWidth = 6.0
    public static let microCellHeight = 5.0
    public static let microCellGap = 2.0
    public static let microTubeWidth = 5.0
    public static let microTubeHeight = 16.0
    public static let fullTrackHeight = 8.0
    public static let fullTrackInset = 1.5

    /// FS2 (Kyle, Sep 2026): the Full segmented cell is the Micro cell scaled up (~2×), not
    /// a separate drawing — "I want them to feel basically the same but adapted for their
    /// size." Micro is 6 × 5 with a 2pt gap and r1.5; Full is ≈ 15.7 × 10 with a 4.5pt gap
    /// and r2.6, chosen on a live three-way comparison after a 22 × 14.5 first cut made the
    /// row labels hard to read. The two proportions that carry the family are held in both
    /// formats: the gap is ≈ 22–25% of the cell pitch, and the corner radius is ≈ 26–30% of
    /// the cell height. `MeterStyleTests` pins the ratios so a later retune of one format
    /// cannot silently drift away from the other.
    ///
    /// MX3 (Kyle, Oct 2026, `design/meter-execution-pass-options.html`): the 10pt row of
    /// free-standing tiles read as a row of keys. Full cells now sit at 8pt — the height of
    /// every other Full track — at a 3.5pt gap and r2.5, and the tip cell stands proud of the
    /// row (`fullTipCellHeight`) the way the Glass/Ghost cap stands proud of the chip. The
    /// radius share holds the FS2 band; the gap share moves to ≈ 17%, which is what the
    /// family test's widened floor records.
    public static let fullCellHeight = 8.0
    public static let fullCellGap = 3.5
    public static let microCellRadius = 1.5
    public static let fullCellRadius = 2.5

    /// MX3: the Full tip cell is 1pt proud on each side of the 8pt row — the same 10pt the
    /// continuous cap (`fullCap.length`) stands at, so the tip names the reading the way the
    /// cap does. It overflows the row rather than growing it. Micro's tip stays flush.
    public static let fullTipCellHeight = 10.0

    /// FS2: reference only — Full cells flex to fill the row, so there is no stored width. A
    /// 14-cell row across the popover's measured 278pt meter run lands each cell at
    /// (278 − 13 × 3.5) / 14 ≈ 16.6pt (MX3), which is the width the family ratios above are
    /// stated at. Nothing renders from this; the family test and the doc comments do.
    public static let fullCellNominalWidth = 16.6

    public static func cellHeight(for format: GaugeFormat) -> Double {
        switch format {
        case .full: fullCellHeight
        case .micro: microCellHeight
        }
    }

    public static func cellGap(for format: GaugeFormat) -> Double {
        switch format {
        case .full: fullCellGap
        case .micro: microCellGap
        }
    }

    public static func cellRadius(for format: GaugeFormat) -> Double {
        switch format {
        case .full: fullCellRadius
        case .micro: microCellRadius
        }
    }

    /// MX3: the lit tip cell's height. Full stands proud of its row; Micro stays flush.
    public static func tipCellHeight(for format: GaugeFormat) -> Double {
        switch format {
        case .full: fullTipCellHeight
        case .micro: microCellHeight
        }
    }

    /// FS3 (Kyle, Sep 2026): the Settings Format swatch must preview the *real* Full row in
    /// small — "update the preview to be accurate too". A miniature cell is therefore the
    /// format's own cell scaled uniformly down to the Micro cell height, so its proportions
    /// (aspect, gap-to-pitch, radius-to-height) are exactly the shipped row's, only smaller.
    /// Micro is already miniature-sized and scales by 1.
    public struct MiniatureCell: Sendable, Equatable {
        public let width: Double
        public let height: Double
        public let gap: Double
        public let radius: Double
        /// MX3: the tip scales with the rest of the cell, so the swatch keeps the proud tip.
        public let tipHeight: Double
    }

    public static func miniatureCell(for format: GaugeFormat) -> MiniatureCell {
        switch format {
        case .micro:
            return MiniatureCell(
                width: microCellWidth,
                height: microCellHeight,
                gap: microCellGap,
                radius: microCellRadius,
                tipHeight: microCellHeight
            )
        case .full:
            let scale = microCellHeight / fullCellHeight
            return MiniatureCell(
                width: fullCellNominalWidth * scale,
                height: fullCellHeight * scale,
                gap: fullCellGap * scale,
                radius: fullCellRadius * scale,
                tipHeight: fullTipCellHeight * scale
            )
        }
    }

    /// AP2 (Kyle, Sep 2026): how many segmented cells fit across a fixed-width swatch at a
    /// given cell pitch. The Format › Full swatch draws its real cells inside a 60pt
    /// fragment, which combs them down to ~2pt ticks at the old 20 (~3.75pt at FS1's 10) and
    /// reads as a barcode rather than as
    /// the segmented meter it is previewing; it instead asks for the count that keeps each
    /// cell at the micro cell size, so the swatch shows "the same little segment chips, just
    /// more of them". Geometry only — the shipped meter still uses `MeterRecipe.cellCount`.
    ///
    /// FS2: with Full cells now 14.5pt tall, a count override alone would draw micro-width ×
    /// full-height slivers, so `MeterGauge`'s `miniatureSegmentCount` also swaps in the Micro
    /// cell height, gap, and radius. This helper supplies the count half of that pair.
    public static func segmentCount(
        fittingWidth width: Double,
        cellWidth: Double = microCellWidth,
        gap: Double = microCellGap
    ) -> Int {
        let pitch = cellWidth + gap
        guard width > 0, pitch > 0 else { return 1 }
        return max(1, Int(((width + gap) / pitch).rounded(.down)))
    }

    /// L8A: a nonzero value always shows a visible stub. The floor is measured along the
    /// fill's travel axis, inside the track's inset.
    public static let fullMinimumFillLength = 6.0
    public static let microMinimumFillLength = 3.0

    /// L7B: the approved cap constants. Full stands 1pt proud on each side of the 8pt track;
    /// Micro is 2 × 7 with square ends — the same pair serves the 32×5 chip and the 5×16 tube,
    /// because the tube is that marker rotated a quarter turn.
    ///
    /// MX1 (Oct 2026): Full's cap went 2.5 → 3pt thick with fully round ends (r 1.5) and now
    /// sits flush with the fill's rounded end (`capCenterOffset(…, flushWithFillEnd:)`), so the
    /// marker still names the exact reading without overhanging the round end.
    public static let fullCap = MeterCapGeometry(thickness: 3, length: 10, cornerRadius: 1.5)
    public static let microCap = MeterCapGeometry(thickness: 2, length: 7, cornerRadius: 0)

    public static func cap(for format: GaugeFormat) -> MeterCapGeometry {
        switch format {
        case .full: fullCap
        case .micro: microCap
        }
    }

    public static func minimumFillLength(for format: GaugeFormat) -> Double {
        switch format {
        case .full: fullMinimumFillLength
        case .micro: microMinimumFillLength
        }
    }

    /// MX1/MX6 (Oct 2026): the popover's continuous fills end in a round cap, so their floor is
    /// at least the fill's own thickness — a 1% bar is a clean dot rather than a sliver with
    /// two round ends crushed together. The format floor still applies where it is larger
    /// (Full machined's 5pt inner fill keeps 6). The widgets keep the plain format floor.
    public static func roundedMinimumFillLength(for format: GaugeFormat, thickness: Double) -> Double {
        max(minimumFillLength(for: format), thickness)
    }

    /// L8A: the fill body is `fraction × available`, floored at the format's minimum so a
    /// nonzero value never disappears. The widgets draw it as a flat-ended rect; the popover
    /// rounds its end (MX1) and passes the rounded floor as `minimum`.
    public static func continuousFillLength(
        available: Double,
        fraction: Double,
        format: GaugeFormat
    ) -> Double {
        continuousFillLength(available: available, fraction: fraction, minimum: minimumFillLength(for: format))
    }

    public static func continuousFillLength(
        available: Double,
        fraction: Double,
        minimum: Double
    ) -> Double {
        guard available > 0, fraction.isFinite, fraction > 0 else { return 0 }
        return min(available, max(minimum, available * min(1, fraction)))
    }

    /// L7B: the cap's center rides the fill's flat trailing edge, measured along the travel
    /// axis from the inside of the track's leading end. It is clamped to the track's own run
    /// so the marker never floats half-off the end at 100%; at the minimum fill length it
    /// parks with the fill, which is why it cannot collide with the leading end.
    ///
    /// MX1: `flushWithFillEnd` moves the centre back half a thickness so the cap's trailing
    /// edge lands on the fill's rounded end instead of straddling it. Full uses it; Micro's
    /// square marker still straddles its end.
    public static func capCenterOffset(
        fillLength: Double,
        available: Double,
        cap: MeterCapGeometry,
        flushWithFillEnd: Bool = false
    ) -> Double {
        let half = cap.thickness / 2
        guard available > cap.thickness else { return max(0, available / 2) }
        let center = flushWithFillEnd ? fillLength - half : fillLength
        return min(max(center, half), available - half)
    }
}

/// Which way a continuous fill travels. Chip and machined run leading → trailing; the tube
/// runs bottom → top.
public enum MeterFillAxis: Sendable {
    case horizontal
    case vertical
}

/// L7B: the Glass/Ghost cap is its own shape, not the fill's rounded end. `thickness` runs
/// along the fill's travel axis; `length` runs across the track and is deliberately longer
/// than the track so the marker crosses the well outline on both sides instead of
/// terminating inside it.
public struct MeterCapGeometry: Sendable, Equatable {
    public let thickness: Double
    public let length: Double
    public let cornerRadius: Double

    public init(thickness: Double, length: Double, cornerRadius: Double) {
        self.thickness = thickness
        self.length = length
        self.cornerRadius = cornerRadius
    }

    public func width(on axis: MeterFillAxis) -> Double {
        axis == .horizontal ? thickness : length
    }

    public func height(on axis: MeterFillAxis) -> Double {
        axis == .horizontal ? length : thickness
    }

    /// How far the cap stands proud of each side of a track this thick.
    public func overhang(onTrackThickness trackThickness: Double) -> Double {
        (length - trackThickness) / 2
    }
}

public enum MeterColorScheme: String, CaseIterable, Sendable {
    case light
    case dark
}

public struct MeterRampStops: Sendable, Equatable {
    public let start: HeadroomRGBColor
    public let end: HeadroomRGBColor
    /// MX2: the ease-out exponent applied to progress before interpolating. 1 is the linear
    /// ramp Micro keeps; Full's softer ramp eases so most of the bar sits near the true colour.
    public let easing: Double

    public init(start: HeadroomRGBColor, end: HeadroomRGBColor, easing: Double = 1) {
        self.start = start
        self.end = end
        self.easing = easing
    }

    /// R2C12: the ramp traverses OKLCH at its severity's fixed hue.
    ///
    /// The Fill option is named for a hue ramp and used to be the one thing in the meter that
    /// actually *moved* hue by accident: both stops were built by mixing the fill toward white
    /// or black in sRGB, which swings the amber ~8.5° warmer at its start. Interpolating in
    /// OKLCH with the hue pinned is what makes the name true — the ramp changes lightness and
    /// chroma only, and `MeterStyleTests` asserts the drift across it stays under 2°.
    public func color(at progress: Double) -> HeadroomRGBColor {
        let t = min(1, max(0, progress))
        let eased = easing == 1 ? t : 1 - pow(1 - t, easing)
        return HeadroomOKLCH(start).interpolated(to: HeadroomOKLCH(end), progress: eased).rgb
    }

    /// The stop a two-colour SwiftUI gradient would otherwise interpolate through in sRGB.
    /// Handing the gradient an explicit middle stop is what keeps the drawn bar on the OKLCH
    /// path instead of the straight line between its endpoints.
    public var midpoint: HeadroomRGBColor { color(at: 0.5) }

    /// The gradient's stops, evenly spaced in position. A linear ramp needs only its midpoint
    /// to stay on the OKLCH path; an eased one (MX2) samples more so the curve survives
    /// SwiftUI's linear interpolation between stops.
    public var gradientSamples: [HeadroomRGBColor] {
        guard easing != 1 else { return [start, midpoint, end] }
        let count = 9
        return (0..<count).map { color(at: Double($0) / Double(count - 1)) }
    }
}

/// A semantic fill choice. The app supplies scheme-specific visual tokens for each case;
/// freshness is settled here so stale and unavailable cannot accidentally inherit color.
public enum MeterFillRecipe: Sendable, Equatable {
    case none
    case staleGrey
    case solid
    case glass
    case ghost
    case neutral
    case ramp
}

public enum MeterCellFill: Sendable, Equatable {
    case severity
    case glass
    case ghost
    case neutral
    case ramp(progress: Double)
}

public enum MeterCellRecipe: Sendable, Equatable {
    case off
    case body(MeterCellFill)
    case tip(MeterCellFill)
}

/// Pure decisions shared by the full-width and micro renderers.
public enum MeterRecipe {
    /// FS1 (Kyle, Sep 2026): Full segmented was 20 cells at 5% each, three rows deep per
    /// account — dense enough that the row read as a barcode rather than as a meter. FS2
    /// then settled on fourteen: at the 10pt cell height that keeps the row labels readable,
    /// fourteen is what holds the Micro chip's ~1.5:1 proportion across the 278pt run (ten
    /// would have been a 2.2:1 bar, or a row of dots at a 13.8pt gap). Micro stays 5.
    public static func cellCount(for format: GaugeFormat) -> Int {
        switch format {
        case .micro: 5
        case .full: 14
        }
    }

    public static func litCellCount(fraction: Double, cells: Int) -> Int {
        guard cells > 0, !fraction.isNaN, fraction > 0 else { return 0 }
        let clampedFraction = min(fraction, 1)
        return min(cells, max(1, Int((clampedFraction * Double(cells)).rounded())))
    }

    public static func rampStops(
        severity: UsageSeverity,
        scheme: MeterColorScheme
    ) -> MeterRampStops {
        rampStops(severity: severity, scheme: scheme, surface: .well)
    }

    /// The ramp is a bar fill end to end, so both stops come from the severity *fill* tier
    /// and honor Increase Contrast (`increasedContrast`); text keeps the text tier.
    ///
    /// R2C12: the start stop is the fill moved toward white (light) or black (dark) *in
    /// OKLCH at the fill's own hue* — the same `rampStartSeverityMix` weight, applied to
    /// lightness and chroma instead of to three sRGB channels. The old sRGB mix was the one
    /// place in the meter that traversed hue, and it did it in the Fill option named for
    /// traversing hue.
    public static func rampStops(
        severity: UsageSeverity,
        scheme: MeterColorScheme,
        surface: MeterRampSurface,
        increasedContrast: Bool = false
    ) -> MeterRampStops {
        let end = HeadroomSeverityColorValues.fill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        )
        let weight = HeadroomMeterColorValues.rampStartSeverityMix(
            dark: scheme == .dark,
            surface: surface,
            increasedContrast: increasedContrast
        )
        let severityStop = HeadroomOKLCH(end)
        // White is L 1 · C 0; black is L 0 · C 0. Both are hueless, so mixing toward either
        // one at a fixed hue is just "keep `weight` of the fill's lightness and chroma".
        let mixLightness: Double = scheme == .dark ? 0 : 1
        let start = HeadroomOKLCH(
            lightness: severityStop.lightness * weight + mixLightness * (1 - weight),
            chroma: severityStop.chroma * weight,
            hue: severityStop.hue
        )
        return MeterRampStops(start: start.rgb, end: end)
    }

    /// MX2 (Kyle, Oct 2026): Full's Fade read harsh — the start was the fill mixed toward
    /// white or black, and in dark that landed *below* the track it sits on, so a 278pt bar
    /// swept from a hole to the vivid fill. Full's ramp instead keeps the fill's hue, scales
    /// its chroma, and shifts lightness a fixed step toward the card (lighter in light, darker
    /// in dark), eased out. One construction for chip, machined, and segmented — the surface
    /// split (`rampStartSeverityMix`) is Micro's alone now, and Micro keeps it unchanged.
    public static func fullRampStops(
        severity: UsageSeverity,
        scheme: MeterColorScheme,
        increasedContrast: Bool = false
    ) -> MeterRampStops {
        let end = HeadroomSeverityColorValues.fill(
            for: severity,
            dark: scheme == .dark,
            increasedContrast: increasedContrast
        )
        let severityStop = HeadroomOKLCH(end)
        let shift = HeadroomMeterColorValues.fullRampLightnessShift * (scheme == .dark ? -1 : 1)
        let start = HeadroomOKLCH(
            lightness: min(0.98, max(0, severityStop.lightness + shift)),
            chroma: severityStop.chroma * HeadroomMeterColorValues.fullRampChromaScale,
            hue: severityStop.hue
        )
        return MeterRampStops(start: start.rgb, end: end, easing: HeadroomMeterColorValues.fullRampEasing)
    }

    /// The ramp a format draws: Full's softer MX2 ramp, or Micro's surface-weighted one.
    public static func rampStops(
        format: GaugeFormat,
        severity: UsageSeverity,
        scheme: MeterColorScheme,
        surface: MeterRampSurface,
        increasedContrast: Bool = false
    ) -> MeterRampStops {
        switch format {
        case .full:
            fullRampStops(severity: severity, scheme: scheme, increasedContrast: increasedContrast)
        case .micro:
            rampStops(severity: severity, scheme: scheme, surface: surface, increasedContrast: increasedContrast)
        }
    }

    public static func cellRecipe(
        index: Int,
        lit: Int,
        fill: GaugeFill,
        severity: UsageSeverity
    ) -> MeterCellRecipe {
        guard index >= 0, index < lit else { return .off }
        let isTip = index == lit - 1
        let cellFill: MeterCellFill
        switch fill {
        case .solid:
            cellFill = .severity
        case .glass:
            cellFill = isTip ? .severity : .glass
        case .ghost:
            cellFill = isTip ? .severity : .ghost
        case .colorAsEvent:
            cellFill = severity == .healthy ? .neutral : .severity
        case .hueRamp:
            let progress = lit <= 1 ? 1 : Double(index) / Double(lit - 1)
            cellFill = .ramp(progress: progress)
        }
        return isTip ? .tip(cellFill) : .body(cellFill)
    }

    public static func fillRecipe(
        fill: GaugeFill,
        severity: UsageSeverity,
        freshness: UsageWindowFreshness
    ) -> MeterFillRecipe {
        switch freshness {
        case .unavailable:
            return .none
        case .stale:
            return .staleGrey
        case .live:
            break
        }

        switch fill {
        case .solid: return .solid
        case .glass: return .glass
        case .ghost: return .ghost
        case .colorAsEvent: return severity == .healthy ? .neutral : .solid
        case .hueRamp: return .ramp
        }
    }

}

public extension ResetSchedule {
    /// Produces the row's bare countdown and tooltip sentence from the same scheduled
    /// evidence. Unresolved or elapsed evidence has no reset line to display.
    func meterResetLine(now: Date) -> MeterResetLine? {
        guard case .scheduled(let deadline) = self else { return nil }
        return Countdown.resetLine(resetsAt: deadline, now: now)
    }
}
