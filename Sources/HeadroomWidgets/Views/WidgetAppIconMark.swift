import SwiftUI

/// The Headroom app icon rendered as a small rounded mark for the medium/large widget
/// headers (R2). Source art is the full-bleed `vessel-app-icon.svg` imageset; rounding
/// is applied at render time with the established `size * 0.22` continuous-corner recipe
/// from `HeadroomAppIconView`, so the mark reads identically on both platforms.
struct WidgetAppIconMark: View {
    var size: CGFloat = 18

    var body: some View {
        Image("AppIconMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: size * 0.16, y: size * 0.06)
            .accessibilityHidden(true)
    }
}
