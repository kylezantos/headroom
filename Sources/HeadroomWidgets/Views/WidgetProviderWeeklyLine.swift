import HeadroomCore
import SwiftUI

struct WidgetProviderWeeklyLine: View {
    let provider: WidgetProviderSummary
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 3) {
            HStack(spacing: compact ? 5 : 6) {
                WidgetProviderIcon(providerID: provider.id, size: compact ? 12 : 15)
                Text(provider.displayName)
                    .font((compact ? Font.system(size: 12) : Font.caption).weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: compact ? 2 : 4)
                Text(percent(provider.weeklyWindow))
                    .font((compact ? Font.system(size: 14) : Font.title3).bold().monospacedDigit())
                    .foregroundStyle(provider.weeklyWindow == nil ? WidgetProviderStyle.secondaryText(scheme: scheme) : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: compact ? 36 : nil, alignment: .trailing)
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
