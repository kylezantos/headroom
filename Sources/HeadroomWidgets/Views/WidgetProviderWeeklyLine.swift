import HeadroomCore
import SwiftUI

struct WidgetProviderWeeklyLine: View {
    let provider: WidgetProviderSummary
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            HStack(spacing: 6) {
                WidgetProviderIcon(providerID: provider.id, size: compact ? 13 : 15)
                Text(provider.displayName)
                    .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(percent(provider.weeklyWindow))
                    .font((compact ? Font.callout : Font.title3).bold().monospacedDigit())
                    .foregroundStyle(provider.weeklyWindow == nil ? WidgetProviderStyle.secondaryText(scheme: scheme) : .primary)
            }
            WidgetUsageBar(
                percentRemaining: provider.weeklyWindow?.percentRemaining ?? 0,
                severity: provider.weeklyWindow?.severity ?? .healthy,
                dimmed: provider.weeklyWindow == nil
            )
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }
}
