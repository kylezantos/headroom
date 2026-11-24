import Testing
@testable import HeadroomCore

/// PB5. The menu bar label is one rasterized image, so anything drawn past the measured width
/// is simply cut off. The attention dot hangs 3pt past its vessel's trailing edge, and the old
/// width sum only counted vessels, gaps and percentages — so in icon-only mode about 60% of the
/// dot on the *trailing* mark was clipped away. These pin the overhang into the measurement and
/// keep the drawn positions coming from the same pass.
@Suite struct MenuBarLabelGeometryTests {
    private func item(text: Double? = nil, attention: Bool = false, mark: Bool = false) -> MenuBarLabelGeometry.Item {
        MenuBarLabelGeometry.Item(textWidth: text, needsAttention: attention, hasMark: mark)
    }

    /// The approved MB1 strip: Claude 72%, Codex 38%, Cursor 9%, whose numerals measure 31, 31
    /// and 22pt at the standard 13.5pt medium monospaced digits.
    private let stripTextWidths: [Double] = [31, 31, 22]

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

    // MARK: CA-MB1 provider marks

    /// The widths the approved panel reads out under each strip: +16pt per pill (a 13pt mark
    /// 3pt before its vessel) and +2pt per gap.
    @Test func threeMarkedPillsMeasureThePanelsWidths() {
        let withText = MenuBarLabelGeometry.layout(
            items: stripTextWidths.map { item(text: $0, mark: true) }, showsPercentage: true)
        let iconOnly = MenuBarLabelGeometry.layout(
            items: stripTextWidths.map { _ in item(mark: true) }, showsPercentage: false)
        #expect(withText.imageWidth == 210)
        #expect(iconOnly.imageWidth == 97)
    }

    @Test func marksOffKeepTodaysWidths() {
        let withText = MenuBarLabelGeometry.layout(
            items: stripTextWidths.map { item(text: $0) }, showsPercentage: true)
        let iconOnly = MenuBarLabelGeometry.layout(
            items: stripTextWidths.map { _ in item() }, showsPercentage: false)
        #expect(withText.imageWidth == 170)
        #expect(iconOnly.imageWidth == 49)
        #expect(withText.placements.allSatisfy { $0.markX == nil })
    }

    /// The mark's box ends exactly `markVesselGap` before its own vessel, and the wider gap
    /// sits between the previous pill and this pill's mark, so a mark reads as its own
    /// vessel's and never as the previous numeral's.
    @Test func eachMarkSitsBeforeItsOwnVesselBehindItsOwnGap() {
        let layout = MenuBarLabelGeometry.layout(
            items: [item(text: 31, mark: true), item(text: 31, mark: true)], showsPercentage: true)
        let first = layout.placements[0], second = layout.placements[1]
        #expect(first.markX == 0)
        #expect(first.vesselX == MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap)
        #expect(second.vesselX - second.markX!
            == MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap)
        #expect(second.markX! - (first.textX! + 31) == MenuBarLabelGeometry.markedMeterGapWithPercentage)
        // The numeral still groups with its own vessel, not the next pill's mark.
        #expect(MenuBarLabelGeometry.markedMeterGapWithPercentage > MenuBarLabelGeometry.vesselTextGap)

        let iconOnly = MenuBarLabelGeometry.layout(items: [item(mark: true), item(mark: true)], showsPercentage: false)
        #expect(iconOnly.placements[1].markX! - (iconOnly.placements[0].vesselX + MenuBarLabelGeometry.vesselWidth) == MenuBarLabelGeometry.markedMeterGapIconOnly)
    }

    /// The automatic summary is a single pill: its mark adds the box and its gap, nothing else.
    @Test func aSingleMarkedPillAddsOnlyItsMarkBox() {
        let plain = MenuBarLabelGeometry.layout(items: [item(text: 31)], showsPercentage: true)
        let marked = MenuBarLabelGeometry.layout(items: [item(text: 31, mark: true)], showsPercentage: true)
        #expect(marked.imageWidth - plain.imageWidth
            == MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap)
    }

    /// PB5's rule with a mark in front: the trailing dot still lands inside the image.
    @Test func theAttentionDotStillFitsWithAMarkPresent() {
        let layout = MenuBarLabelGeometry.layout(
            items: [item(mark: true), item(attention: true, mark: true)], showsPercentage: false)
        let dotEdge = MenuBarLabelGeometry.attentionDotTrailingEdge(vesselX: layout.placements[1].vesselX)
        #expect(layout.contentWidth >= dotEdge)
        #expect(layout.imageWidth >= dotEdge)
    }

    /// CA-MB1: the menu bar sizes its marks from its own table. Every shipped provider has an
    /// entry (not the fallback), and every ink, outline included, fits the 13pt box and the
    /// 18pt image after its nudge, so a mark never draws into its gap or past the label.
    @Test(arguments: ["claude", "codex", "grok", "cursor", "copilot", "opencode", "antigravity"])
    func everyProviderHasMenuBarMarkMetricsThatFitTheBox(_ provider: String) {
        let metrics = MenuBarLabelGeometry.markMetrics(for: provider)
        #expect(metrics != MenuBarLabelGeometry.defaultMarkMetrics, "\(provider) falls back to the default")
        let ink = metrics.inkSize(aspect: HeadroomBrandMark.inkAspect(for: provider))
        #expect(max(ink.width, ink.height) == metrics.inkExtent)
        #expect(ink.width + metrics.thickening <= MenuBarLabelGeometry.markBoxSize, "\(provider) width")
        #expect(ink.height + metrics.thickening <= MenuBarLabelGeometry.markBoxSize, "\(provider) height")
        #expect(ink.height + metrics.thickening + 2 * abs(metrics.verticalNudge) <= MenuBarLabelGeometry.height)
        #expect(metrics.thickening >= 0 && metrics.thickening <= 0.5, "\(provider) outline is a hairline")
    }

    @Test func anUnknownProviderGetsTheDefaultMarkMetrics() {
        #expect(MenuBarLabelGeometry.markMetrics(for: "someday-provider") == MenuBarLabelGeometry.defaultMarkMetrics)
        let fallback = MenuBarLabelGeometry.defaultMarkMetrics
        #expect(fallback.inkExtent + fallback.thickening <= MenuBarLabelGeometry.markBoxSize)
    }
}
