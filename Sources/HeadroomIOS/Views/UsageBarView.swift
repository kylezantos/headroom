import SwiftUI

struct UsageBarView: View {
    let window: WidgetWindowSummary
    let now: Date
    var dimmed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var percent: Int { Int(window.percentRemaining.rounded()) }
    private var fraction: Double { min(1, max(0, window.percentRemaining / 100)) }
    private var animatedFraction: Double { reduceMotion || appeared ? fraction : 0 }
    private var fillColor: Color {
        dimmed ? Color.secondary.opacity(0.48) : HeadroomTheme.severityColor(for: window.severity, scheme: scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(displayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(MirrorPresentation.resetText(for: window, now: now))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
                    .lineLimit(1)
                    .layoutPriority(-1)
                Spacer(minLength: 8)
                if MirrorPresentation.showsLowChip(severity: window.severity, dimmed: dimmed) {
                    lowChip
                }
                Text("\(percent)%")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text("left")
                    .font(.caption)
                    .foregroundStyle(HeadroomTheme.tertiaryText(scheme))
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
        .opacity(dimmed ? 0.68 : 1)
        .animation(reduceMotion ? nil : HeadroomTheme.valueSpring, value: fraction)
        .animation(reduceMotion ? nil : HeadroomTheme.valueSpring, value: dimmed)
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
        .accessibilityLabel("\(displayLabel) usage")
        .accessibilityValue("\(percent) percent remaining, \(MirrorPresentation.resetText(for: window, now: now))")
    }

    private var lowChip: some View {
        Text("Low")
            .font(.caption2.weight(.bold))
            .foregroundStyle(HeadroomTheme.severityColor(for: window.severity, scheme: scheme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(HeadroomTheme.severityColor(for: window.severity, scheme: scheme).opacity(0.15), in: Capsule())
    }

    private var displayLabel: String {
        switch window.kind {
        case .fiveHour:
            "Session"
        case .weekly:
            "Weekly"
        case .other(let label):
            label
        }
    }

    private func fillWidth(in availableWidth: CGFloat) -> CGFloat {
        guard animatedFraction > 0 else { return 0 }
        return max(4, availableWidth * animatedFraction)
    }
}
