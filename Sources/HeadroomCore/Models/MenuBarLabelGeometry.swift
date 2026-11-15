import Foundation

/// Where every piece of the rasterized menu bar label lands, and how wide the resulting
/// image has to be.
///
/// PB5: this used to be two loops in `MenuBarLabelRenderer` — one that summed a width and one
/// that drew — and they disagreed. The attention dot is drawn 3pt past the vessel's trailing
/// edge (it is a corner badge, not a column), but only the vessel and its text were measured,
/// so in icon-only mode the dot on the *last* meter had nothing to be drawn into and about
/// 60% of it was clipped away by the image bounds. Anywhere else the dot is covered
/// incidentally — a percentage adds at least `vesselTextGap`, another meter adds at least
/// `meterGapIconOnly`, and both are wider than the overhang — which is why the bug only ever
/// showed on the trailing mark.
///
/// One layout pass now answers both questions, so a mark's drawn extent cannot leave the
/// measured width again. Kept SwiftUI/AppKit-free so `MenuBarLabelGeometryTests` can measure it
/// without a status item.
public enum MenuBarLabelGeometry {
    public static let height: Double = 18
    public static let vesselWidth: Double = 11
    public static let vesselTextGap: Double = 7
    public static let meterGapWithPercentage: Double = 16
    public static let meterGapIconOnly: Double = 8
    public static let attentionDotDiameter: Double = 5
    /// How far the dot's leading edge sits *inside* the vessel's trailing edge; the rest of
    /// the diameter hangs past it.
    public static let attentionDotInset: Double = 2
    /// CA-MB1 (KTD7): a provider mark's square optical box, 13pt so it carries about the
    /// vessel's weight (at 11pt it read as a speck beside it).
    public static let markBoxSize: Double = 13
    /// The space between a mark's box and its own vessel.
    public static let markVesselGap: Double = 3
    /// CA-MB1: added to the pill-to-pill gap in front of a marked pill (icon-only 8 → 10,
    /// with percentages 16 → 18), so a mark attaches to its own vessel and not to the
    /// previous pill's numeral.
    public static let markedMeterGapExtra: Double = 2

    /// How one provider's mark sits inside its `markBoxSize` box (CA-MB1). The box, its gap
    /// and the pill gaps never change with the provider, so the label measures the same
    /// whichever marks it carries; only the ink inside the box does.
    public struct MarkMetrics: Sendable, Equatable {
        /// The ink's larger dimension in points; the other follows the artwork's
        /// `HeadroomBrandMark.inkAspect`.
        public let inkExtent: Double
        /// Points the ink's centre is raised above the vessel's centre (negative lowers it).
        public let verticalNudge: Double
        /// Total width of a same-ink outline added around the artwork, in points (0 = none):
        /// thickens hairline strokes that thin out at 13pt. Drawn on Retina bars only: on a
        /// 1× bar a whole-pixel outline closes counters.
        public let thickening: Double

        public init(inkExtent: Double, verticalNudge: Double = 0, thickening: Double = 0) {
            self.inkExtent = inkExtent
            self.verticalNudge = verticalNudge
            self.thickening = thickening
        }

        /// The ink's width and height for an artwork of `aspect` (width ÷ height).
        public func inkSize(aspect: Double) -> (width: Double, height: Double) {
            guard aspect.isFinite, aspect > 0 else { return (inkExtent, inkExtent) }
            return aspect >= 1 ? (inkExtent, inkExtent / aspect) : (inkExtent * aspect, inkExtent)
        }
    }

    /// The mark of a provider the table does not know: a mid-weight extent from the six below.
    public static let defaultMarkMetrics = MarkMetrics(inkExtent: 11, verticalNudge: markTieLift)

    /// CA-MB1: a 0.1pt lift on every mark. When an ink height and the 18pt image disagree in
    /// pixel parity the centred mark falls on a half pixel, and the lift settles that tie one
    /// pixel up rather than down, which is where the optical centre sits anyway.
    public static let markTieLift: Double = 0.1

    /// CA-MB1 (Nov 2026): the menu bar's own mark sizing, never the popover's
    /// `HeadroomBrandMark.markSize`. That rule was tuned for coloured marks at popover sizes;
    /// in one ink at 13pt it left the six marks 2pt apart in height and 1.85× apart in weight
    /// (Codex's and OpenCode's solid shapes heavy, Grok's and Copilot's strokes faint). Tuned
    /// by optical rule rather than equal boxes, measured at 2× (alpha-weighted ink, then
    /// judged on 1× and 2× sheets on both bars):
    /// - Codex 9.5 and OpenCode 10 (8 wide): the solid shapes take the least extent.
    /// - Cursor 10.5: a near-solid cube, one step under the open marks; an even 1× height.
    /// - Claude 11.5: its rays leave most of the box empty, so it takes more.
    /// - Copilot 12.5 (10.4 tall): size alone brings its open face level, no outline (a 0.3pt
    ///   outline filled the goggles).
    /// - Grok 12.5 with a 0.5pt outline: size alone stalls at 0.66 of Codex's weight even
    ///   filling the box, so the hairline ring and slash are thickened on Retina only.
    /// Result at 2×: weight max/min 1.30× (was 1.85×), every centre within +0.25pt of the
    /// vessel's. At 1× Grok stays the lightest (an outline closes its ring there).
    public static func markMetrics(for providerID: String) -> MarkMetrics {
        switch providerID {
        case ProviderID.claude.raw: MarkMetrics(inkExtent: 11.5, verticalNudge: markTieLift)
        case ProviderID.codex.raw: MarkMetrics(inkExtent: 9.5, verticalNudge: markTieLift)
        case ProviderID.grok.raw: MarkMetrics(inkExtent: 12.5, verticalNudge: markTieLift, thickening: 0.5)
        case ProviderID.cursor.raw: MarkMetrics(inkExtent: 10.5, verticalNudge: markTieLift)
        case ProviderID.copilot.raw: MarkMetrics(inkExtent: 12.5, verticalNudge: markTieLift)
        case ProviderID.opencode.raw: MarkMetrics(inkExtent: 10, verticalNudge: markTieLift)
        default: defaultMarkMetrics
        }
    }

    /// The part of a meter this layout cannot derive on its own: whether it draws a
    /// percentage (and how wide that text measured), whether it carries the attention dot,
    /// and whether it draws its provider's mark (CA-MB1).
    public struct Item: Sendable, Equatable {
        public let textWidth: Double?
        public let needsAttention: Bool
        public let hasMark: Bool

        public init(textWidth: Double?, needsAttention: Bool, hasMark: Bool = false) {
            self.textWidth = textWidth
            self.needsAttention = needsAttention
            self.hasMark = hasMark
        }
    }

    public struct Placement: Sendable, Equatable {
        /// Leading edge of the vessel glyph.
        public let vesselX: Double
        /// Leading edge of the percentage, when the meter draws one.
        public let textX: Double?
        /// Leading edge of the mark's `markBoxSize` box, when the meter draws one (CA-MB1).
        public let markX: Double?

        public init(vesselX: Double, textX: Double?, markX: Double? = nil) {
            self.vesselX = vesselX
            self.textX = textX
            self.markX = markX
        }
    }

    public struct Layout: Sendable, Equatable {
        public let placements: [Placement]
        /// The widest point anything is drawn to, including the attention dot's overhang.
        public let contentWidth: Double
        /// What the image is actually made at: never narrower than a single vessel.
        public let imageWidth: Double

        public init(placements: [Placement], contentWidth: Double, imageWidth: Double) {
            self.placements = placements
            self.contentWidth = contentWidth
            self.imageWidth = imageWidth
        }
    }

    public static func meterGap(showsPercentage: Bool) -> Double {
        showsPercentage ? meterGapWithPercentage : meterGapIconOnly
    }

    /// The trailing edge of `item`'s attention dot, measured from the vessel's leading edge.
    public static func attentionDotTrailingEdge(vesselX: Double) -> Double {
        vesselX + vesselWidth - attentionDotInset + attentionDotDiameter
    }

    /// `vesselTextGap` is overridable only for the Settings pill card's compact step; the
    /// status item always uses the standard gap.
    public static func layout(items: [Item], showsPercentage: Bool, vesselTextGap: Double = vesselTextGap) -> Layout {
        let gap = meterGap(showsPercentage: showsPercentage)
        var cursor: Double = 0
        var extent: Double = 0
        var placements: [Placement] = []
        placements.reserveCapacity(items.count)

        for item in items {
            if cursor > 0 { cursor += gap + (item.hasMark ? markedMeterGapExtra : 0) }
            // CA-MB1: the mark is measured in this pass, like the attention dot (PB5), so a
            // drawn mark can never fall outside the image.
            var markX: Double?
            if item.hasMark {
                markX = cursor
                cursor += markBoxSize + markVesselGap
            }
            let vesselX = cursor
            cursor += vesselWidth
            var textX: Double?
            if let textWidth = item.textWidth {
                cursor += vesselTextGap
                textX = cursor
                cursor += textWidth
            }
            placements.append(Placement(vesselX: vesselX, textX: textX, markX: markX))
            extent = max(extent, cursor)
            if item.needsAttention {
                extent = max(extent, attentionDotTrailingEdge(vesselX: vesselX))
            }
        }

        return Layout(
            placements: placements,
            contentWidth: extent,
            imageWidth: max(vesselWidth, extent.rounded(.up))
        )
    }
}
