import HeadroomCore
import SwiftUI

struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(envelope.weeklyProviders) { provider in
                WidgetProviderWeeklyLine(provider: provider, compact: true)
            }
            Spacer(minLength: 0)
        }
        // KTD1: system content margins carry the ~14pt effective outer margin; keep only
        // a minimal residual. Tune against the widget gallery.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}
