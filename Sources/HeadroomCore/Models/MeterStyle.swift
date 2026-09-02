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

    public var label: String {
        switch self {
        case .solid: "Solid"
        case .glass: "Glass + cap"
        case .ghost: "Ghost + cap"
        case .colorAsEvent: "Color as event"
        case .hueRamp: "Hue ramp"
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
    public static let fullCellHeight = 7.0
    public static let fullCellGap = 2.5
    public static let microCapThickness = 2.5
    public static let fullCapThickness = 3.5
}

public enum MeterColorScheme: String, CaseIterable, Sendable {
    case light
    case dark
}

/// The ramp's dark-scheme start is mixed against different meter surfaces. Light mode
/// uses the same white mix on both because both reference surfaces are light neutrals.
public enum MeterRampSurface: Sendable {
    case flat
    case well
}

public struct MeterRampStops: Sendable, Equatable {
    public let start: HeadroomRGBColor
    public let end: HeadroomRGBColor

    public init(start: HeadroomRGBColor, end: HeadroomRGBColor) {
        self.start = start
        self.end = end
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
    public static func cellCount(for format: GaugeFormat) -> Int {
        switch format {
        case .micro: 5
        case .full: 20
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

    public static func rampStops(
        severity: UsageSeverity,
        scheme: MeterColorScheme,
        surface: MeterRampSurface
    ) -> MeterRampStops {
        let end = HeadroomSeverityColorValues.color(for: severity, dark: scheme == .dark)
        let mixColor: HeadroomRGBColor
        switch scheme {
        case .light:
            mixColor = .white
        case .dark:
            mixColor = .black
        }
        return MeterRampStops(
            start: mix(
                end,
                weight: HeadroomMeterColorValues.rampStartSeverityMix(
                    dark: scheme == .dark,
                    surface: surface
                ),
                with: mixColor
            ),
            end: end
        )
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

    private static func mix(
        _ color: HeadroomRGBColor,
        weight: Double,
        with background: HeadroomRGBColor
    ) -> HeadroomRGBColor {
        let backgroundWeight = 1 - weight
        return HeadroomRGBColor(
            red: color.red * weight + background.red * backgroundWeight,
            green: color.green * weight + background.green * backgroundWeight,
            blue: color.blue * weight + background.blue * backgroundWeight
        )
    }
}

public struct MeterResetLine: Sendable, Equatable {
    public let countdown: String
    public let tooltip: String

    public init(countdown: String, tooltip: String) {
        self.countdown = countdown
        self.tooltip = tooltip
    }
}

public extension ResetSchedule {
    /// Produces the row's bare countdown and tooltip sentence from the same scheduled
    /// evidence. Unresolved or elapsed evidence has no reset line to display.
    func meterResetLine(now: Date) -> MeterResetLine? {
        guard case .scheduled(let deadline) = self else { return nil }
        let tooltip = Countdown.resetText(resetsAt: deadline, now: now)
        if tooltip == "Resets now" {
            return MeterResetLine(countdown: "now", tooltip: tooltip)
        }
        let prefix = "Resets in "
        guard tooltip.hasPrefix(prefix) else { return nil }
        return MeterResetLine(
            countdown: String(tooltip.dropFirst(prefix.count)),
            tooltip: tooltip
        )
    }
}
