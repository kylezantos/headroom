import SwiftUI
import HeadroomCore

/// One usage row in either the full two-line frame or the compact micro frame.
/// The row owns text, accessibility, and value motion; `MeterGauge` owns every
/// shape × fill rendering decision.
struct UsageBarView: View {
    let window: UsageWindow
    let percentageMode: UsagePercentageMode
    let now: Date
    var meterStyle: MeterStyle = .default
    var dimmed: Bool = false
    /// H3a (Jul 2026 multi-account design review): in the multi-account meter the critical
    /// band drops the "Low" chip and paints the percentage numeral a decoupled critical text
    /// color instead. Single-account rows keep the chip exactly as before.
    var chiplessCriticalInk: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private let labelSize: CGFloat = 13
    private let resetSize: CGFloat = 11
    private let percentSize: CGFloat = 18
    private let termSize: CGFloat = 11
    private let rowSpacing: CGFloat = 5

    private var isEffectivelyDimmed: Bool { dimmed || !window.freshness.isLive }

    private var usesCriticalInk: Bool {
        chiplessCriticalInk && !isEffectivelyDimmed && severity == .critical
    }

    private var pct: Int? {
        window.freshness.isUnavailable ? nil : percentageMode.roundedPercentage(for: window)
    }

    private var percentText: String { pct.map { "\($0)%" } ?? "—" }

    private var fraction: Double {
        window.freshness.isUnavailable ? 0 : percentageMode.fraction(for: window)
    }

    private var severity: UsageSeverity { window.severity }

    /// The same spring drives gauge geometry, severity, and rolling numeric text. The value
    /// snaps under Reduce Motion, preserving the existing accessibility behavior.
    private var valueAnimation: Animation? { reduceMotion ? nil : HeadroomMotion.valueSpring }

    private var resetLine: MeterResetLine? {
        guard !window.freshness.isUnavailable else { return nil }
        return window.resetSchedule.meterResetLine(now: now)
    }

    private var gaugeFreshness: UsageWindowFreshness {
        guard dimmed, !window.freshness.isUnavailable else { return window.freshness }
        if case .stale = window.freshness { return window.freshness }
        // Snapshot-level staleness is a visual state; the date is not rendered by the gauge.
        return .stale(observedAt: window.observedAt ?? now)
    }

    private var stateText: String? {
        switch window.freshness {
        case .live:
            nil
        case .stale(let observedAt):
            Countdown.updatedLabel(capturedAt: observedAt, now: now)
                .map { "Last known \($0)" } ?? "Last known"
        case .unavailable:
            "Unavailable"
        }
    }

    var body: some View {
        Group {
            switch meterStyle.format {
            case .full:
                fullRow
            case .micro:
                microRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage")
        .accessibilityValue(accessibilityValue)
        .animation(valueAnimation, value: severity)
    }

    /// Full keeps the established fit-aware frame: label metadata and numeral above the
    /// full-width gauge, with a reset subline only when a long label cannot share the top row.
    private var fullRow: some View {
        ViewThatFits(in: .horizontal) {
            fullMeter(inlineReset: true)
            fullMeter(inlineReset: false)
        }
    }

    private func fullMeter(inlineReset: Bool) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                labelText
                stateLabel
                if inlineReset { resetLabel(fixedSize: true) }
                Spacer(minLength: 6)
                urgencyChip
                numeral
            }

            gauge

            if !inlineReset {
                resetLabel(fixedSize: false)
            }
        }
    }

    /// Micro tries the approved one-line reading cluster first. Its fallback preserves
    /// the same information while moving only the gauge + numeral to a second line.
    private var microRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                labelCluster(fixedReset: true)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                urgencyChip
                gauge
                numeral
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    labelCluster(fixedReset: false)
                    Spacer(minLength: 6)
                    urgencyChip
                }
                HStack(alignment: .center, spacing: 6) {
                    Spacer(minLength: 0)
                    gauge
                    numeral
                }
            }
        }
    }

    private func labelCluster(fixedReset: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            labelText
            stateLabel
            resetLabel(fixedSize: fixedReset)
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(ProviderStyle.meterLabelInk(scheme: scheme))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var stateLabel: some View {
        if let stateText {
            Text("· \(stateText)")
                .font(.system(size: resetSize, weight: .medium))
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func resetLabel(fixedSize: Bool) -> some View {
        if let resetLine {
            Text(resetLine.countdown)
                .font(.system(size: resetSize).monospacedDigit())
                .foregroundStyle(ProviderStyle.meterCountdownInk(scheme: scheme))
                .lineLimit(1)
                .fixedSize(horizontal: fixedSize, vertical: true)
                .help(resetLine.tooltip)
        }
    }

    @ViewBuilder
    private var urgencyChip: some View {
        if !isEffectivelyDimmed, severity == .critical, !chiplessCriticalInk {
            lowChip
                .transition(.opacity)
        }
    }

    private var numeral: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(percentText)
                .font(.system(size: percentSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(usesCriticalInk ? ProviderStyle.criticalText(scheme: scheme) : .primary)
                .contentTransition(.numericText())
                .animation(valueAnimation, value: percentText)
            if pct != nil {
                Text(percentageMode.term)
                    .font(.system(size: termSize))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
        }
        .fixedSize()
    }

    private var gauge: some View {
        MeterGauge(
            style: meterStyle,
            fraction: fraction,
            severity: severity,
            freshness: gaugeFreshness,
            scheme: scheme
        )
        .animation(valueAnimation, value: fraction)
    }

    /// Small static "Low" flag shown only for the critical band (≤15% left).
    private var lowChip: some View {
        Text("Low")
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.2)
            .foregroundStyle(ProviderStyle.severityColor(for: severity, scheme: scheme))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                ProviderStyle.severityColor(for: severity, scheme: scheme).opacity(0.16),
                in: Capsule()
            )
    }

    private var label: String {
        switch window.kind {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .billingPeriod(let label, _): return label
        case .other(let raw): return Self.normalizeOther(raw)
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let pct {
            parts.append("\(pct) percent \(percentageMode.term)")
        }
        if let stateText {
            parts.append(stateText)
        }
        if let resetLine {
            parts.append(resetLine.tooltip)
        }
        return parts.joined(separator: ", ")
    }

    /// Presentation-only tidy of Codex's constructed window labels. The model name stays
    /// verbatim; only the provider-appended period suffix is normalized.
    private static func normalizeOther(_ raw: String) -> String {
        if raw.hasSuffix(" weekly") { return "\(raw.dropLast(7)) · Weekly" }
        if raw.hasSuffix(" 5h") { return "\(raw.dropLast(3)) · 5-hour" }
        return raw
    }
}
