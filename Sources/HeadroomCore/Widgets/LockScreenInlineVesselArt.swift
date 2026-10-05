import Foundation

/// KTD9 (2026-10-04 Lock Screen plan): the inline slot accepts only text and one image, so the
/// vessel ships as eleven stepped template images. They are drawn from `WidgetVesselGeometry`
/// so the inline vessel keeps the widget vessel's 11:18 proportion, stroke and inset.
public enum LockScreenInlineVesselArt {
    public static let levels = 0...10
    /// KTD9: the inline image is drawn at the vessel's own point size, beside 17 pt text.
    public static let geometry = WidgetVesselGeometry(height: 18)

    public static func assetName(level: Int) -> String {
        "LockScreenInlineVessel\(min(levels.upperBound, max(levels.lowerBound, level)))"
    }

    /// Template art: black ink on transparent, recoloured by the system's inline text style.
    public static func svg(level: Int) -> String {
        let g = geometry
        let clamped = min(levels.upperBound, max(levels.lowerBound, level))
        let liquid = g.liquidHeight(fraction: Double(clamped) / Double(levels.upperBound))
        func n(_ value: Double) -> String { String(format: "%.3f", value) }
        var body = """
        <rect x="\(n(g.stroke / 2))" y="\(n(g.stroke / 2))" width="\(n(g.width - g.stroke))" \
        height="\(n(g.height - g.stroke))" rx="\(n((g.width - g.stroke) / 2))" fill="none" \
        stroke="#000" stroke-width="\(n(g.stroke))"/>
        """
        if liquid > 0 {
            body += """

            <clipPath id="inner"><rect x="\(n(g.inset))" y="\(n(g.inset))" width="\(n(g.innerWidth))" \
            height="\(n(g.innerHeight))" rx="\(n(g.innerWidth / 2))"/></clipPath>
            <rect clip-path="url(#inner)" x="\(n(g.inset))" y="\(n(g.inset + g.innerHeight - liquid))" \
            width="\(n(g.innerWidth))" height="\(n(liquid))" fill="#000"/>
            """
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(n(g.width))" height="\(n(g.height))" \
        viewBox="0 0 \(n(g.width)) \(n(g.height))">
        \(body)
        </svg>

        """
    }

    public static let imagesetContents = """
    {
      "images" : [ { "filename" : "vessel.svg", "idiom" : "universal" } ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
    }

    """
}
