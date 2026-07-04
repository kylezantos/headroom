import HeadroomCore
import SwiftUI

struct WidgetUsageMeter: View {
    let window: WidgetWindowSummary?
    let fallbackLabel: String
    var now: Date?
    var showsResetInline = false
    var compact = false

    @Environment(\.colorScheme) private var scheme

    private var percentText: String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private var resetText: String? {
        guard let window, showsResetInline else { return nil }
        if let label = window.resetLabel { return label }
        guard let now else { return nil }
        if window.resetsAt <= now { return "Resets now" }
        return "Resets in \(Countdown.string(to: window.resetsAt, now: now))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window?.label ?? fallbackLabel)
                    .font(compact ? .caption2.weight(.medium) : .caption)
                    .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                if let resetText {
                    Text("· \(resetText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 2)
                Text(percentText)
                    .font((compact ? Font.caption2 : Font.caption).bold().monospacedDigit())
                    .foregroundStyle(window == nil ? WidgetProviderStyle.secondaryText(scheme: scheme) : .primary)
            }
            WidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil
            )
        }
    }
}
