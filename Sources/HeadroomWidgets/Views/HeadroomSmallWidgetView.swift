import HeadroomCore
import SwiftUI

struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly Left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(envelope.weeklyProviders) { provider in
                WidgetProviderWeeklyLine(provider: provider, compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
