// STREAM-A STUB — delete at merge.
//
// Stream B (shared meter / bar / strip / typography / status views) is written against the
// Core API in the plan's "Core API this plan fixes" block, which stream A is building in
// parallel. These declarations exist only so `swift build` passes in B's worktree; every
// one of them is replaced by stream A's real, unit-tested version at the merge. Values here
// are copied from the plan so a local render is not nonsense, but they carry no tests and
// are not the source of truth.
//
// Two notes for the merge:
//   1. The plan names Core's family enum `WidgetFamily`. **That name is ambiguous**:
//      `WidgetKit.WidgetFamily` already exists, and every file in this module imports both
//      WidgetKit (for `widgetAccentable`, `widgetRenderingMode`) and HeadroomCore, which
//      makes an unqualified `WidgetFamily` an "ambiguous for type lookup" error in the
//      SwiftPM build (verified). Stream B therefore codes against `HeadroomWidgetFamily`.
//      If stream A ships the enum as `WidgetFamily`, the one-line fix in Core is
//      `public typealias HeadroomWidgetFamily = WidgetFamily`.
//   2. `LargeWidgetDensity` is deliberately **not** stubbed — it already exists in Core and
//      stream A rewrites it in place. Stream B's views never read it.

#if canImport(HeadroomCore)
import HeadroomCore
#endif
import Foundation

// MARK: - WidgetTypeScale (WCF1, WCF2)

public enum HeadroomWidgetFamily: Sendable, Equatable, CaseIterable { case small, medium, large }

public enum WidgetTypeStep: Sendable, Equatable { case standard, dense }

public struct WidgetTypeScale: Sendable, Equatable {
    public let header: Double
    public let name: Double
    public let nameKerning: Double
    public let label: Double
    public let countdown: Double
    public let numeral: Double
    public let suffix: Double
    public let spendAmount: Double
    public let spendSuffix: Double
    public let footer: Double
    public let statusTitle: Double
    public let statusMessage: Double
    public let pillLabel: Double
    public let pillHeight: Double

    public static func scale(
        for family: HeadroomWidgetFamily,
        step: WidgetTypeStep = .standard
    ) -> WidgetTypeScale {
        let dense = step == .dense
        return WidgetTypeScale(
            header: 11,
            name: family == .large ? (dense ? 14 : 15) : 14,
            nameKerning: -0.15,
            label: family == .large && !dense ? 13 : 12,
            countdown: dense ? 10.5 : 11,
            numeral: family == .medium || dense ? 16 : 18,
            suffix: dense ? 10.5 : 11,
            spendAmount: 13,
            spendSuffix: 11,
            footer: 11,
            statusTitle: 14,
            statusMessage: 11.5,
            pillLabel: 9.5,
            pillHeight: 15
        )
    }

    /// Measured width of "100%" in SF semibold monospaced digits: 52 @18, 47.5 @16, 42 @14.
    public static func numeralColumnWidth(forNumeralSize size: Double) -> Double {
        switch size {
        case ..<14: 42 * size / 14
        case ..<16: 42 + (size - 14) / 2 * 5.5
        case ..<18: 47.5 + (size - 16) / 2 * 4.5
        default: 52 * size / 18
        }
    }
}

// MARK: - WidgetMetrics (WCF3, WCF4, WCL2, WCL4, WCL5)

public enum WidgetMetrics {
    public static let residualMargin: Double = 2
    public static let iOSMarginReclaim: Double = 4
    public static let iOSMediumMargin: Double = 16
    public static let markGap: Double = 6

    public static func markSlot(
        for family: HeadroomWidgetFamily,
        step: WidgetTypeStep = .standard
    ) -> Double {
        switch family {
        case .small: 15
        case .medium: 16
        case .large: step == .dense ? 18 : 20
        }
    }

    public static func contentAxis(
        for family: HeadroomWidgetFamily,
        step: WidgetTypeStep = .standard
    ) -> Double {
        markSlot(for: family, step: step) + markGap
    }

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
    public static let hairline: Double = 1
}

// MARK: - WidgetStatusCopy (WCW4)

public enum WidgetStatusState: Sendable, CaseIterable {
    case macSetupNeeded, macIncompatibleSchema, macDisabled, macPending
    case iosDisabled, iosSetupNeeded, iosWaitingForMac, iosCorrupt, iosIncompatibleSchema

    public var title: String {
        switch self {
        case .macSetupNeeded: "No usage yet"
        case .macIncompatibleSchema, .iosIncompatibleSchema: "Update Headroom"
        case .macDisabled: "Widgets are off"
        case .macPending: "Not checked yet"
        case .iosDisabled: "Sync is off"
        case .iosSetupNeeded: "iCloud is off"
        case .iosWaitingForMac: "Waiting for your Mac"
        case .iosCorrupt: "Couldn't read the data"
        }
    }

    public var message: String {
        switch self {
        case .macSetupNeeded: "Open Headroom on this Mac to send usage to widgets."
        case .macIncompatibleSchema: "This widget needs a newer version of the app."
        case .macDisabled: "Turn on Share data with widgets in Headroom Settings."
        case .macPending: "Open Headroom to take the first reading."
        case .iosDisabled: "Turn on Sync usage to iPhone in Headroom on your Mac."
        case .iosSetupNeeded: "Turn on iCloud for Headroom in iPhone Settings."
        case .iosWaitingForMac: "Open Headroom on your Mac to send a reading."
        case .iosCorrupt: "Open Headroom on your Mac and choose Check Now."
        case .iosIncompatibleSchema: "Update the app on your Mac and iPhone."
        }
    }

    public var vesselFill: Double {
        switch self {
        case .macPending, .iosWaitingForMac: 0
        default: 0.46
        }
    }
}

// MARK: - Colour tokens (WCM1, WCM3, WCL4)

public extension HeadroomWidgetColorValues {
    static func neutralFill(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.26)
            : HeadroomTint(
                color: HeadroomRGBColor(red: 107 / 255, green: 114 / 255, blue: 123 / 255),
                opacity: 1
            )
    }

    static func staleNeutralFill(dark: Bool) -> HeadroomRGBColor {
        dark
            ? HeadroomRGBColor(red: 140 / 255, green: 141 / 255, blue: 147 / 255)
            : HeadroomRGBColor(red: 141 / 255, green: 146 / 255, blue: 153 / 255)
    }

    static func widgetHairline(dark: Bool) -> HeadroomTint {
        dark
            ? HeadroomTint(color: .white, opacity: 0.14)
            : HeadroomTint(color: .black, opacity: 0.10)
    }
}

public extension HeadroomMeterColorValues {
    /// WCM3: the `WidgetUsageSeverity` overload of the popover's `staleFill`. Healthy falls
    /// to the neutral stale tone because WCM1 already made a healthy *live* bar neutral.
    static func staleFill(
        for severity: WidgetUsageSeverity,
        dark: Bool,
        increasedContrast: Bool
    ) -> HeadroomRGBColor {
        switch severity {
        case .healthy:
            HeadroomWidgetColorValues.staleNeutralFill(dark: dark)
        case .low:
            staleFill(for: UsageSeverity.low, dark: dark, increasedContrast: increasedContrast)
        case .critical:
            staleFill(for: UsageSeverity.critical, dark: dark, increasedContrast: increasedContrast)
        }
    }
}

// MARK: - Snapshot accessors (WCW2, WCW7)

public extension WidgetWindowSummary {
    var widgetDisplayLabel: String {
        switch kind {
        case .weekly: "Weekly"
        case .fiveHour: "5-hour"
        case .other: isBillingPeriod ? label : compactLabel
        }
    }
}

public extension WidgetSnapshotEnvelope {
    var smallHeaderTitle: String {
        let providers = widgetProviders
        guard !providers.isEmpty else { return "Usage left" }
        var nouns: Set<String> = []
        for provider in providers {
            guard let window = provider.primarySubscriptionWindow else { return "Usage left" }
            if window.isBillingPeriod {
                nouns.insert("Monthly")
            } else if window.kind == .weekly {
                nouns.insert("Weekly")
            } else {
                return "Usage left"
            }
        }
        return nouns.count == 1 ? "\(nouns.first!) left" : "Usage left"
    }
}
