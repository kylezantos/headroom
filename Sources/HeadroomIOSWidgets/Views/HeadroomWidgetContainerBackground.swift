import SwiftUI

struct HeadroomWidgetContainerBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        // The companion's full-screen gradient + top glow is tuned for a tall scroll view. Crushed
        // into a small widget, that bright glow lands right behind the top provider card, so an
        // identical card reads lighter/darker purely by vertical position (the provider cards are
        // byte-for-byte the same fill — the surround is what differed). Keep the widget surround a
        // calm, near-uniform dark that stays darker than the tile fill everywhere, so every provider
        // card sits on the same background and reads identically.
        LinearGradient(
            colors: [
                color(HeadroomWidgetColorValues.containerBackgroundTop(dark: isDark)),
                color(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: isDark)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func color(_ rgb: HeadroomRGBColor) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

}
