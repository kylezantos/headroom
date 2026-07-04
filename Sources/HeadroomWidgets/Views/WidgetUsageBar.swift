import HeadroomCore
import SwiftUI

struct WidgetUsageBar: View {
    let percentRemaining: Double
    let severity: WidgetUsageSeverity
    var dimmed = false

    @Environment(\.colorScheme) private var scheme

    private var fraction: Double {
        min(1, max(0, percentRemaining / 100))
    }

    private func fillWidth(in availableWidth: Double) -> Double {
        guard fraction > 0 else { return 0 }
        return max(4, availableWidth * fraction)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(WidgetProviderStyle.barTrack(scheme: scheme))
                Capsule()
                    .fill(dimmed ? WidgetProviderStyle.secondaryText(scheme: scheme) : WidgetProviderStyle.severityColor(for: severity))
                    .frame(width: fillWidth(in: geo.size.width))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
