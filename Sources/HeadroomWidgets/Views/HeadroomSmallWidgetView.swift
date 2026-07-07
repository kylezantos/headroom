import HeadroomCore
import SwiftUI

struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weekly left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(envelope.providers) { provider in
                    let windows = provider.weeklyDisplayWindows
                    if windows.isEmpty {
                        WidgetProviderWeeklyLine(provider: provider, compact: true)
                    } else {
                        ForEach(windows) { window in
                            SmallWeeklyWindowLine(provider: provider, window: window)
                        }
                    }
                }
            }
            .padding(.top, 9)
            Spacer(minLength: 0)
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the small family has room for three weekly lines.
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
    }
}

private struct SmallWeeklyWindowLine: View {
    let provider: WidgetProviderSummary
    let window: WidgetWindowSummary

    @Environment(\.colorScheme) private var scheme

    private var title: String {
        switch window.kind {
        case .weekly:
            return provider.displayName
        case .fiveHour:
            return window.label
        case .other:
            return window.label.replacingOccurrences(of: " weekly", with: "", options: .caseInsensitive)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                WidgetProviderIcon(providerID: provider.id, size: 12)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text("\(Int(window.percentRemaining.rounded()))%")
                    .font(.system(size: 14).bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 36, alignment: .trailing)
            }
            WidgetUsageBar(
                percentRemaining: window.percentRemaining,
                severity: window.severity
            )
        }
    }
}
