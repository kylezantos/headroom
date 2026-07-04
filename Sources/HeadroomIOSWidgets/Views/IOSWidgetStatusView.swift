import SwiftUI

struct IOSWidgetStatusView: View {
    let title: String
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var secondaryText: Color {
        scheme == .dark ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.66) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.74)
    }
}
