import Testing
@testable import HeadroomCore

/// PB5. The menu bar label is one rasterized image, so anything drawn past the measured width
/// is simply cut off. The attention dot hangs 3pt past its vessel's trailing edge, and the old
/// width sum only counted vessels, gaps and percentages — so in icon-only mode about 60% of the
/// dot on the *trailing* mark was clipped away. These pin the overhang into the measurement and
/// keep the drawn positions coming from the same pass.
@Suite struct MenuBarLabelGeometryTests {
    private func item(text: Double? = nil, attention: Bool = false) -> MenuBarLabelGeometry.Item {
        MenuBarLabelGeometry.Item(textWidth: text, needsAttention: attention)
    }

    @Test func theTrailingAttentionDotFitsInsideTheMeasuredWidth() {
        let layout = MenuBarLabelGeometry.layout(
            items: [item(attention: true)],
            showsPercentage: false
        )
        let vesselX = layout.placements[0].vesselX
        #expect(layout.contentWidth
            >= MenuBarLabelGeometry.attentionDotTrailingEdge(vesselX: vesselX))
        #expect(layout.imageWidth >= layout.contentWidth)
    }

    /// The dot is the only thing that can extend past the running cursor, so its presence is
    /// exactly what the extra width is for — and nothing else pays for it.
    @Test func theOverhangIsAddedOnlyWhenTheTrailingMarkCarriesTheDot() {
        let plain = MenuBarLabelGeometry.layout(items: [item()], showsPercentage: false)
        let flagged = MenuBarLabelGeometry.layout(items: [item(attention: true)], showsPercentage: false)

        #expect(plain.contentWidth == MenuBarLabelGeometry.vesselWidth)
        #expect(flagged.contentWidth - plain.contentWidth
            == MenuBarLabelGeometry.attentionDotDiameter - MenuBarLabelGeometry.attentionDotInset)
    }

    /// Every non-trailing dot was already covered incidentally — a following meter adds at
    /// least `meterGapIconOnly` and a percentage adds at least `vesselTextGap`, both wider than
    /// the overhang — which is why the bug only ever showed on the last mark. That has to stay
    /// true, or the fix is hiding a second one.
    @Test func aCoveredDotDoesNotWidenTheImage() {
        let leading = MenuBarLabelGeometry.layout(
            items: [item(attention: true), item()],
            showsPercentage: false
        )
        let neither = MenuBarLabelGeometry.layout(
            items: [item(), item()],
            showsPercentage: false
        )
        #expect(leading.contentWidth == neither.contentWidth)

        let withText = MenuBarLabelGeometry.layout(
            items: [item(text: 24, attention: true)],
            showsPercentage: true
        )
        let withoutDot = MenuBarLabelGeometry.layout(
            items: [item(text: 24)],
            showsPercentage: true
        )
        #expect(withText.contentWidth == withoutDot.contentWidth)
    }

    @Test func placementsWalkVesselGapVesselAndMatchTheMeasuredWidth() {
        let items = [item(text: 24), item(text: 30, attention: true)]
        let layout = MenuBarLabelGeometry.layout(items: items, showsPercentage: true)
        let gap = MenuBarLabelGeometry.meterGapWithPercentage

        #expect(layout.placements.count == 2)
        #expect(layout.placements[0].vesselX == 0)
        #expect(layout.placements[0].textX
            == MenuBarLabelGeometry.vesselWidth + MenuBarLabelGeometry.vesselTextGap)
        #expect(layout.placements[1].vesselX
            == MenuBarLabelGeometry.vesselWidth + MenuBarLabelGeometry.vesselTextGap + 24 + gap)
        #expect(layout.placements[1].textX
            == layout.placements[1].vesselX
                + MenuBarLabelGeometry.vesselWidth
                + MenuBarLabelGeometry.vesselTextGap)
        // The trailing percentage is wider than the dot's overhang, so it sets the width.
        #expect(layout.contentWidth == layout.placements[1].textX! + 30)
    }

    /// A meter with no percentage draws no text, and the icon-only gap is the narrower one.
    @Test func iconOnlyModeUsesTheTighterGapAndPlacesNoText() {
        let layout = MenuBarLabelGeometry.layout(
            items: [item(), item()],
            showsPercentage: false
        )
        #expect(layout.placements.allSatisfy { $0.textX == nil })
        #expect(layout.placements[1].vesselX
            == MenuBarLabelGeometry.vesselWidth + MenuBarLabelGeometry.meterGapIconOnly)
        #expect(MenuBarLabelGeometry.meterGap(showsPercentage: false)
            < MenuBarLabelGeometry.meterGap(showsPercentage: true))
    }

    /// The image is never narrower than a single vessel, and never narrower than its content.
    @Test func imageWidthClearsBothFloors() {
        #expect(MenuBarLabelGeometry.layout(items: [], showsPercentage: false).imageWidth
            == MenuBarLabelGeometry.vesselWidth)
        let fractional = MenuBarLabelGeometry.layout(
            items: [item(text: 24.4)],
            showsPercentage: true
        )
        #expect(fractional.imageWidth >= fractional.contentWidth)
        #expect(fractional.imageWidth == fractional.contentWidth.rounded(.up))
    }
}
