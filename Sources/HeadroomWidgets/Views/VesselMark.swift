import SwiftUI

/// Headroom's vessel identity glyph for the widget target. Mirrors `VesselGlyph` in the
/// app; duplicated because `HeadroomCore` is intentionally SwiftUI-free, so a shared
/// `Shape` can't live there and the widget is a separate binary. Keep the two in sync.
struct VesselMark: View {
    var lineWidth: CGFloat = 1.6
    var fill: CGFloat = 0.46

    var body: some View {
        ZStack {
            Capsule().strokeBorder(lineWidth: lineWidth)
            Capsule()
                .inset(by: lineWidth + 0.6)
                .fill()
                .mask {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(height: proxy.size.height * fill)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        .accessibilityHidden(true)
    }
}
