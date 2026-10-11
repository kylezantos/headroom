#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import HeadroomCore

/// Popover account layout, Compact (R11–R14): one account on one 26pt line — mark, title,
/// a "+N" for windows with no room, then up to two cells. Everything the line drops (reset
/// times, the other windows, the main-account note) lives in its tooltip and VoiceOver value
/// (R12, R13). What it shows is `CompactAccountRowRecipe`'s decision; this only lays it out.
///
/// Sizes are the options doc's HC-D proposal (title 13 semibold, row 26, 12 between cells)
/// and still need Kyle's live review before they ship.
struct CompactAccountRow: View {
    let providerID: ProviderID
    let title: String
    let email: String?
    let showsPersistentEmail: Bool
    let isMenuBarAccount: Bool
    let recipe: CompactAccountRowRecipe
    let percentageMode: UsagePercentageMode
    let now: Date
    /// M4A: the once-per-launch draw-in, keyed like the Standard rows so a layout switch never
    /// replays it.
    let arrivalKey: AccountKey?

    static let height: CGFloat = 26
    /// The gap between two Compact rows in one card.
    static let rowGap: CGFloat = 4
    private static let titleSize: CGFloat = 13
    private static let cellGap: CGFloat = 12

    var body: some View {
        let _ = BenchCounters.hit("CompactAccountRow")
        HStack(spacing: IdentityRowMetrics.spacing) {
            ProviderLogoView(providerID: providerID, size: IdentityRowMetrics.markSlotWidth)
                .frame(width: IdentityRowMetrics.markSlotWidth, height: IdentityRowMetrics.markSlotWidth)
            CompactIdentityLayout(spacing: IdentityRowMetrics.spacing) {
                Text(title)
                    .font(.system(size: Self.titleSize, weight: .semibold))
                    .kerning(IdentityRowMetrics.titleKerning)
                    .accountTitleInk(for: providerID)
                    .lineLimit(1)
                    // "Account 12" → "Acc…12": the end that tells generated names apart stays.
                    .truncationMode(.middle)
                if let persistentEmail {
                    Text(persistentEmail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .layoutPriority(1)
            if recipe.overflowCount > 0 {
                Text("+\(recipe.overflowCount)")
                    .foregroundStyle(.secondary)
                    .identityCapsule(fill: IdentityCapsuleStyle.metadataFill, horizontalPadding: 4)
                    .fixedSize()
            }
            // The stack's own 6pt on each side is the minimum gap before the cells.
            Spacer(minLength: 0)
            cells
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(recipe.accessibilityValue)
    }

    private var persistentEmail: String? {
        guard showsPersistentEmail, let email, !email.isEmpty else { return nil }
        return email
    }

    @ViewBuilder private var cells: some View {
        switch recipe.content {
        case .meters:
            HStack(spacing: Self.cellGap) {
                ForEach(recipe.shownWindows, id: \.window.kind.persistentID) { shown in
                    UsageBarView(
                        window: shown.window,
                        percentageMode: percentageMode,
                        now: now,
                        meterStyle: recipe.meterStyle,
                        dimmed: recipe.isDimmed,
                        arrivalKey: arrivalKey,
                        compactLabel: shown.shortLabel
                    )
                }
            }
        case .skeleton, .standardFallback:
            HStack(spacing: Self.cellGap) {
                SkeletonMeter(labelWidth: 14, valueWidth: 34, format: .micro).fixedSize()
                SkeletonMeter(labelWidth: 14, valueWidth: 34, format: .micro).fixedSize()
            }
        }
    }

    private var tooltip: String {
        // The identity row's own tooltip lines (title, email, main account), then the meters'.
        var lines = IdentityRowText.helpLines(
            title: title,
            titleIsTruncated: true,
            email: email?.isEmpty == false ? email : nil,
            isMenuBarAccount: isMenuBarAccount,
            bankedHelp: nil
        ).map { [$0] } ?? []
        if recipe.isDimmed, recipe.content == .meters { lines.append("Stale") }
        if !recipe.tooltip.isEmpty { lines.append(recipe.tooltip) }
        return lines.joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        var parts = ["\(title) account"]
        if isMenuBarAccount { parts.append("main account") }
        if recipe.isDimmed, recipe.content == .meters { parts.append("stale") }
        if recipe.content == .skeleton { parts.append("loading") }
        return parts.joined(separator: ", ")
    }
}

/// The Compact row's name and persistent email (KTD11). The title takes the width it needs
/// first; the email shows only in what is left, and only when that is enough to read, so it
/// never collapses to a letter beside the name. A dropped email stays in the row's tooltip.
private struct CompactIdentityLayout: Layout {
    var spacing: CGFloat
    private static let minimumEmailWidth: CGFloat = 40

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = self.widths(available: proposal.width, subviews: subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let used = widths.reduce(0, +) + (widths.count > 1 && widths[1] > 0 ? spacing : 0)
        return CGSize(width: used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = self.widths(available: bounds.width, subviews: subviews)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = widths[index]
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            if width > 0 { x += width + spacing }
        }
    }

    /// The title's ideal width, capped by what is available; then the email's, or zero.
    private func widths(available: CGFloat?, subviews: Subviews) -> [CGFloat] {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let available else { return ideals }
        guard let title = ideals.first else { return [] }
        let titleWidth = min(title, max(available, 0))
        guard ideals.count > 1 else { return [titleWidth] }
        let room = available - titleWidth - spacing
        let emailWidth = room >= Self.minimumEmailWidth ? min(ideals[1], room) : 0
        return [titleWidth, emailWidth]
    }
}
