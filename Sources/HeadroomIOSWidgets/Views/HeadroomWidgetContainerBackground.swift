import SwiftUI

struct HeadroomWidgetContainerBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: color(HeadroomWidgetColorValues.containerBackgroundTop(dark: isDark)), location: 0),
                .init(color: color(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: isDark)), location: 0.52),
                .init(color: color(HeadroomWidgetColorValues.containerBackgroundBottom(dark: isDark)), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            RadialGradient(
                gradient: Gradient(colors: [
                    color(HeadroomWidgetColorValues.containerBackgroundGlow(dark: isDark)),
                    .clear
                ]),
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 260
            )
        }
    }

    private func color(_ rgb: HeadroomRGBColor) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func color(_ tint: HeadroomTint) -> Color {
        color(tint.color).opacity(tint.opacity)
    }

}
