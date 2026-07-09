import HeadroomCore
import SwiftUI

/// Small widget: one weekly meter per provider under a quiet column header.
///
/// Layout (Jul 2026 redesign): each meter line owns an equal *flexible* slot
/// (`maxHeight: .infinity`) so the content distributes across the widget's full height —
/// the old fixed-gap stack pooled a dead void under the last bar, which read top-heavy
/// and template-ish. Hierarchy got one clear step per level: 11pt header (defers), 13pt
/// brand-accent names, 16pt bold percent (the glance payload, same step as the large
/// widget's prominent meters).
struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weekly left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
            ForEach(envelope.providers) { provider in
                let windows = provider.weeklyDisplayWindows
                if windows.isEmpty {
                    WidgetProviderWeeklyLine(provider: provider, compact: true)
                        .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(windows) { window in
                        SmallWeeklyWindowLine(provider: provider, window: window)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
            }
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the meters have room to breathe.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                WidgetProviderIcon(providerID: provider.id, size: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text("\(Int(window.percentRemaining.rounded()))%")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 42, alignment: .trailing)
            }
            WidgetUsageBar(
                percentRemaining: window.percentRemaining,
                severity: window.severity,
                height: 7
            )
        }
    }
}
