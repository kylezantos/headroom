// STREAM-A/B STUB — delete at merge.
//
// This file exists only so stream C's worktree compiles before streams A (Core tokens)
// and B (shared meter/bar/strip/status/typography) land. Every declaration below is a
// placeholder for a symbol the plan assigns to another stream; the values are NOT the
// design values — A and B own those. Delete this whole file in the merge commit.
//
// Plan: docs/plans/2026-09-11-001-feat-widget-craft-plan.md

#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

// MARK: - Stream A · Sources/HeadroomCore/Widgets/WidgetTypeScale.swift

public enum WidgetFamily: Sendable, Equatable, CaseIterable {
    case small, medium, large
}

public enum WidgetTypeStep: Sendable, Equatable, CaseIterable {
    case standard, dense
}

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

    public static func scale(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> WidgetTypeScale {
        let dense = step == .dense
        return WidgetTypeScale(
            header: 11,
            name: family == .large && !dense ? 15 : 14,
            nameKerning: -0.15,
            label: family == .large && !dense ? 13 : 12,
            countdown: dense ? 10.5 : 11,
            numeral: family == .small ? 18 : (family == .large && !dense ? 18 : 16),
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

    public static func numeralColumnWidth(forNumeralSize size: Double) -> Double {
        switch size {
        case 18: 52
        case 16: 47.5
        default: 42
        }
    }
}

// MARK: - Stream A · Sources/HeadroomCore/Widgets/WidgetMetrics.swift

public enum WidgetMetrics {
    public static let residualMargin: Double = 2
    public static let iOSMarginReclaim: Double = 4
    public static let iOSMediumMargin: Double = 16
    public static let markGap: Double = 6

    public static func markSlot(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> Double {
        switch family {
        case .small: 15
        case .medium: 16
        case .large: step == .dense ? 18 : 20
        }
    }

    public static func contentAxis(for family: WidgetFamily, step: WidgetTypeStep = .standard) -> Double {
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

// MARK: - Stream A · LargeWidgetDensity rewrite
//
// The shipping Core enum already carries roomy/regular/compact plus barHeight,
// headerSpacing, meterSpacing and providerIconSize, so only the members the rewrite adds
// are stubbed here.

public extension LargeWidgetDensity {
    var typeStep: WidgetTypeStep {
        switch self {
        case .roomy, .regular: .standard
        case .compact, .ultraCompact: .dense
        }
    }

    var providerGapFloor: Double { 16 }
    var edgeGapWeight: Double { 0.6 }

    var showsPlanPill: Bool {
        switch self {
        case .roomy, .regular: true
        case .compact, .ultraCompact: false
        }
    }
}

// MARK: - Stream A · Sources/HeadroomCore/Widgets/WidgetStatusCopy.swift

public enum WidgetStatusState: Sendable, CaseIterable {
    case macSetupNeeded, macIncompatibleSchema, macDisabled, macPending
    case iosDisabled, iosSetupNeeded, iosWaitingForMac, iosCorrupt, iosIncompatibleSchema

    public var title: String { "Stub title" }
    public var message: String { "Stub message." }
    public var vesselFill: Double { 0.46 }
}

// MARK: - Stream A · WidgetSnapshotModels additions

public extension WidgetSnapshotEnvelope {
    var smallHeaderTitle: String { "Usage left" }
}

public extension WidgetWindowSummary {
    var widgetDisplayLabel: String { label }
}

// MARK: - Stream B · HeadroomWidgetStyle additions

public extension HeadroomWidgetStyle {
    static func accountTitle(scheme: ColorScheme) -> Color { secondaryText(scheme: scheme) }
    static func planLabel(scheme: ColorScheme) -> Color { tertiaryText(scheme: scheme) }
    static func widgetHairline(scheme: ColorScheme) -> Color { hairline(scheme: scheme) }
    static func hairlineWidth(displayScale: CGFloat) -> CGFloat { 1 / max(1, displayScale) }
}

// MARK: - Stream B · HeadroomWidgetTypography

public enum HeadroomWidgetTypography {
    /// Distance from a text view's line-box top to the cap top of its glyphs. C uses it
    /// to start the medium centre rule at the first meter label's cap (WCL4).
    public static func capTopInset(size: Double, weight: Font.Weight) -> Double { 0 }
}

public extension View {
    func capHeightCentered(size: Double, weight: Font.Weight) -> some View { self }
    func opticalLeading(_ leading: Double, size: Double, weight: Font.Weight) -> some View { self }
}

// MARK: - Stream B · new shared views

public struct HeadroomWidgetAttentionGlyph: View {
    public enum Kind: Sendable { case provider, spend }

    private let kind: Kind
    private let size: Double

    @Environment(\.colorScheme) private var scheme

    public init(kind: Kind, size: Double) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        Image(systemName: kind == .provider ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
    }
}

public struct HeadroomVesselMark: View {
    private let fill: CGFloat

    public init(fill: CGFloat = 0.46) {
        self.fill = fill
    }

    public var body: some View {
        Capsule().strokeBorder(lineWidth: 1.6).accessibilityHidden(true)
    }
}

public struct HeadroomWidgetStatusCard: View {
    private let state: WidgetStatusState
    private let family: WidgetFamily
    private let scale: WidgetTypeScale

    public init(state: WidgetStatusState, family: WidgetFamily, scale: WidgetTypeScale) {
        self.state = state
        self.family = family
        self.scale = scale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if family != .small {
                Text(state.title).font(.system(size: scale.statusTitle, weight: .semibold)).lineLimit(1)
            }
            Text(state.message).font(.system(size: scale.statusMessage, weight: .medium)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Stream B · new inits on the existing shared components
//
// These delegate to the shipping inits so C can already call the plan's signatures; B
// replaces the bodies (reserved numeral column, glance configuration, WCM1–WCM6 inks).

public extension HeadroomWidgetUsageMeter {
    init(
        window: WidgetWindowSummary?,
        fallbackLabel: String,
        now: Date? = nil,
        scale: WidgetTypeScale,
        family: WidgetFamily,
        providerIsLive: Bool,
        showsResetInline: Bool = false,
        glance: Bool = false,
        glanceName: String? = nil,
        glanceMarkSlot: Double? = nil
    ) {
        self.init(
            window: window,
            fallbackLabel: glance ? (glanceName ?? fallbackLabel) : fallbackLabel,
            now: now,
            showsResetInline: showsResetInline,
            compact: family != .large,
            scale: nil
        )
    }
}

public extension HeadroomWidgetUsageBar {
    init(
        percentRemaining: Double,
        severity: WidgetUsageSeverity,
        freshness: WidgetWindowFreshness,
        providerIsLive: Bool,
        height: CGFloat
    ) {
        self.init(
            percentRemaining: percentRemaining,
            severity: severity,
            dimmed: !freshness.isLive || !providerIsLive,
            height: height
        )
    }
}

public extension HeadroomWidgetAPISpendStrip {
    init(
        summaries: [WidgetAPISpendSummary],
        now: Date,
        family: WidgetFamily,
        scale: WidgetTypeScale,
        footerText: String?,
        showsRule: Bool
    ) {
        self.init(summaries: summaries, now: now, footerText: footerText)
    }
}
