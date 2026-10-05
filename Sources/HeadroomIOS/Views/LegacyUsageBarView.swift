import SwiftUI

struct LegacyUsageBarView: View {
    let window: WidgetWindowSummary
    let now: Date
    var dimmed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appeared = false

    private var percent: Int? {
        window.displayPercentRemaining.map { Int($0.rounded()) }
    }
    private var percentText: String { percent.map { "\($0)%" } ?? "—" }
    private var fraction: Double {
        min(1, max(0, (window.displayPercentRemaining ?? 0) / 100))
    }
    private var animatedFraction: Double { reduceMotion || appeared ? fraction : 0 }
    private var isEffectivelyDimmed: Bool { dimmed || !window.freshness.isLive }
    private var fillColor: Color {
        isEffectivelyDimmed
            ? Color.secondary.opacity(0.48)
            : HeadroomTheme.severityFill(
                for: window.severity,
                scheme: scheme,
                increasedContrast: contrast == .increased
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(displayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let state = MirrorPresentation.windowStateText(for: window) {
                    Text(state)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                }
                if !window.freshness.isUnavailable {
                    Text(MirrorPresentation.resetText(for: window, now: now))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 8)
                if MirrorPresentation.showsLowChip(
                    severity: window.severity,
                    dimmed: isEffectivelyDimmed
                ) {
                    lowChip
                }
                Text(percentText)
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                if percent != nil {
                    Text("left")
                        .font(.caption)
                        .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(HeadroomTheme.barTrack(scheme))
                    Capsule()
                        .fill(fillColor)
                        .frame(width: fillWidth(in: proxy.size.width))
                }
            }
            .frame(height: 9)
        }
        .opacity(isEffectivelyDimmed ? 0.68 : 1)
        .animation(reduceMotion ? nil : HeadroomTheme.valueSpring, value: fraction)
        .animation(reduceMotion ? nil : HeadroomTheme.valueSpring, value: isEffectivelyDimmed)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(HeadroomTheme.valueSpring.delay(0.10)) {
                    appeared = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenLabel) usage")
        .accessibilityValue(accessibilityValue)
    }

    private var lowChip: some View {
        Text("Low")
            .font(.caption2.weight(.bold))
            .foregroundStyle(HeadroomTheme.severityColor(for: window.severity, scheme: scheme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(HeadroomTheme.severityColor(for: window.severity, scheme: scheme).opacity(0.15), in: Capsule())
    }

    /// The Mac popover's naming (`WindowKind.displayName`), so a Claude model row reads
    /// "Fable" on both. Billing periods arrive here as `.other(label)` and keep their label.
    private var displayLabel: String {
        coreKind.displayName
    }

    /// "Fable weekly" for VoiceOver, where the short name would drop the period.
    private var spokenLabel: String {
        coreKind.spokenName
    }

    private var coreKind: WindowKind {
        switch window.kind {
        case .fiveHour: .fiveHour
        case .weekly: .weekly
        case .other(let label): .other(label)
        }
    }

    private func fillWidth(in availableWidth: CGFloat) -> CGFloat {
        guard animatedFraction > 0 else { return 0 }
        return max(9, availableWidth * animatedFraction)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let percent {
            parts.append("\(percent) percent remaining")
        }
        if let state = MirrorPresentation.windowStateText(for: window) {
            parts.append(state)
        }
        if !window.freshness.isUnavailable {
            parts.append(MirrorPresentation.resetText(for: window, now: now))
        }
        return parts.joined(separator: ", ")
    }
}
