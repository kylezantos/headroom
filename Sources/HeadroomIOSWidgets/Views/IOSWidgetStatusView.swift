import SwiftUI

struct IOSWidgetStatusView: View {
    let title: String
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                VesselMark()
                    .frame(width: 12, height: 20)
            }
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
        Color(HeadroomWidgetColorValues.secondaryText(dark: scheme == .dark))
    }
}

private struct VesselMark: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.primary.opacity(0.9))
            .overlay(alignment: .topLeading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.28))
                    .frame(width: 2.5)
                    .padding(.leading, 3)
                    .padding(.vertical, 3)
            }
            .accessibilityHidden(true)
    }
}

private extension Color {
    init(_ tint: HeadroomTint) {
        self = Color(tint.color).opacity(tint.opacity)
    }

    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
