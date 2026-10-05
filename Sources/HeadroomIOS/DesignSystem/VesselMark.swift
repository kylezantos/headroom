import SwiftUI

/// U10 (P59, G7): the Headroom vessel on the phone, drawn on the widget's
/// `WidgetVesselGeometry` (the menu-bar glyph's 11:18) in neutral inks — the widget vessel's
/// resting wall and the "only when low" neutral body. It is a mark, not a meter: no severity
/// colour and no system blue (G6). Sized from the height it is offered.
struct VesselMark: View {
    var fill: Double = 0.30
    /// The status mock (P59) draws its 84pt vessel with a 2.6 wall; the widget clamp (≤ 2.1)
    /// is for numeral-sized vessels and hairlines at this size. Nil takes the widget clamp.
    var stroke: Double?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let geometry = Self.geometry(fitting: proxy.size, stroke: stroke)
            let inset = CGFloat(geometry.inset)
            let liquid = CGFloat(geometry.liquidHeight(fraction: fill))
            ZStack {
                Capsule()
                    .inset(by: CGFloat(geometry.stroke) / 2)
                    .stroke(wallInk, lineWidth: CGFloat(geometry.stroke))
                if liquid > 0 {
                    // VesselGlyph.render: clip to the inset capsule, then fill the lower part.
                    Rectangle()
                        .fill(liquidInk)
                        .frame(height: liquid)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .frame(width: CGFloat(geometry.innerWidth), height: CGFloat(geometry.innerHeight))
                        .clipShape(Capsule())
                        .padding(inset)
                }
            }
            .frame(width: CGFloat(geometry.width), height: CGFloat(geometry.height))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    /// The largest 11:18 vessel inside `size`.
    static func geometry(fitting size: CGSize, stroke: Double?) -> WidgetVesselGeometry {
        let height = min(Double(size.height), Double(size.width) / WidgetVesselGeometry.aspect)
        let base = WidgetVesselGeometry(height: max(0, height))
        return WidgetVesselGeometry(width: base.width, height: base.height, stroke: stroke)
    }

    private var wallInk: Color {
        Color(styleTint: HeadroomWidgetColorValues.tertiaryText(dark: scheme == .dark))
    }

    private var liquidInk: Color {
        Color(styleTint: HeadroomWidgetColorValues.neutralFill(dark: scheme == .dark))
    }
}
