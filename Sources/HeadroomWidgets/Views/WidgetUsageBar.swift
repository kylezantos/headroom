import HeadroomCore
import SwiftUI

struct WidgetUsageBar: View {
    let percentRemaining: Double
    let severity: WidgetUsageSeverity
    var dimmed = false
    var height: CGFloat = 6

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
                    .fill(dimmed ? WidgetProviderStyle.secondaryText(scheme: scheme) : WidgetProviderStyle.severityColor(for: severity, scheme: scheme))
                    .frame(width: fillWidth(in: geo.size.width))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
