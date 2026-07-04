import SwiftUI

struct WidgetStatusView: View {
    let title: String
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                VesselMark().frame(width: 12, height: 20)
            }
            .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
