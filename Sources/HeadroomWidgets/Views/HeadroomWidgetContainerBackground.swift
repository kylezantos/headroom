import HeadroomCore
import SwiftUI

struct HeadroomWidgetContainerBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        // Companion parity: the same top → middle → bottom falloff as the iOS companion's
        // screen background (HeadroomTheme.backgroundView), minus its radial top glow — at
        // widget scale the glow's bright center would land behind the top provider card,
        // while at phone scale it sits above the content entirely. Measured beside the
        // companion's cards the surround runs ~(20 → 13); this 3-stop ramp reproduces that,
        // staying darker than the tile fill everywhere so both cards read identically.
        LinearGradient(
            colors: [
                color(HeadroomWidgetColorValues.containerBackgroundTop(dark: isDark)),
                color(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: isDark)),
                color(HeadroomWidgetColorValues.containerBackgroundBottom(dark: isDark)),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func color(_ rgb: HeadroomRGBColor) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

}
