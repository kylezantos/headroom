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
    var showsMark: Bool = true

    static let height: CGFloat = 26
    /// The gap between two Compact rows in one card.
    static let rowGap: CGFloat = 4
    private static let titleSize: CGFloat = 13
    private static let cellGap: CGFloat = 12

    var body: some View {
        let _ = BenchCounters.hit("CompactAccountRow")
        HStack(spacing: IdentityRowMetrics.spacing) {
            Group {
                if showsMark {
                    ProviderLogoView(providerID: providerID, size: IdentityRowMetrics.markSlotWidth)
                } else {
                    Color.clear
                }
            }
            .frame(width: IdentityRowMetrics.markSlotWidth, height: IdentityRowMetrics.markSlotWidth)
            identityText
                .accountTitleInk(for: providerID)
                .lineLimit(1)
                // With an email the title leads and the address gives way; alone, a long
                // name keeps both its ends.
                .truncationMode(persistentEmail == nil ? .middle : .tail)
                .layoutPriority(1)
            if recipe.overflowCount > 0 {
                Text("+\(recipe.overflowCount)")
                    .foregroundStyle(.secondary)
                    .identityCapsule(fill: IdentityCapsuleStyle.metadataFill, horizontalPadding: 5)
                    .fixedSize()
            }
            Spacer(minLength: IdentityRowMetrics.spacing)
            cells
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(recipe.accessibilityValue)
    }

    /// KTD11's persistent email rides the title as one line, so the two truncate together
    /// instead of the address collapsing to a letter beside a full name.
    private var identityText: Text {
        let name = Text(title)
            .font(.system(size: Self.titleSize, weight: .semibold))
            .kerning(IdentityRowMetrics.titleKerning)
        guard let persistentEmail else { return name }
        return name + Text("  \(persistentEmail)")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
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
        var lines = [title]
        if let email, !email.isEmpty { lines.append(email) }
        if isMenuBarAccount { lines.append(IdentityRowText.mainAccountHelp) }
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
