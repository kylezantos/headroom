#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import HeadroomCore

/// Popover account layout, Compact (R11–R14): one account on one 26pt line — mark, title,
/// a "+N" for windows with no room, then up to two cells. Everything the line drops (reset
/// times, the other windows, banked resets, the main-account note) lives in its tooltip and
/// VoiceOver value (R12, R13). What it shows is `CompactAccountRowRecipe`'s decision; this
/// only lays it out.
///
/// Kyle approved the HC-D sizes (title 13 semibold, row 26, 12 between cells) with one change
/// (2026-10-13, `design/popover-compact-header-mockup.html`): the window names and the
/// left/used word sit once in the card's `CompactCardHeader`, not in every cell, which gives
/// names the room to read whole.
struct CompactAccountRow: View {
    let providerID: ProviderID
    let title: String
    let email: String?
    let showsPersistentEmail: Bool
    var titleIsEmail: Bool = false
    let isMenuBarAccount: Bool
    let recipe: CompactAccountRowRecipe
    /// The card header's columns. Each window sits under its own kind, so an account showing
    /// only a weekly window keeps it under "wk" beside its neighbours.
    let columns: [WindowKind]
    let bankedResets: Int?
    let percentageMode: UsagePercentageMode
    let now: Date
    /// M4A: the once-per-launch draw-in, keyed like the Standard rows so a layout switch never
    /// replays it.
    let arrivalKey: AccountKey?

    static let height: CGFloat = 26
    /// The gap between two Compact rows in one card.
    static let rowGap: CGFloat = 4
    private static let titleSize: CGFloat = 13
    static let cellGap: CGFloat = 12
    /// One fixed width per cell, Segmented's 38pt gauge plus the 15pt "100%" column, so cells
    /// and header labels line up down the card whatever each row shows.
    static let cellWidth: CGFloat = 84

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
                    // Generated labels keep their ordinal; email titles keep the local
                    // part visible instead of spending scarce width on a shared domain.
                    .truncationMode(titleIsEmail ? .tail : .middle)
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
        HStack(spacing: Self.cellGap) {
            switch recipe.content {
            case .meters:
                ForEach(Array(placedWindows.enumerated()), id: \.offset) { _, shown in
                    if let shown {
                        UsageBarView(
                            window: shown.window,
                            percentageMode: percentageMode,
                            now: now,
                            meterStyle: recipe.meterStyle,
                            dimmed: recipe.isDimmed,
                            arrivalKey: arrivalKey,
                            compactLabel: ""
                        )
                        .frame(width: Self.cellWidth, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: Self.cellWidth, height: 1)
                    }
                }
            case .skeleton, .standardFallback:
                ForEach(0..<max(columns.count, 2), id: \.self) { _ in
                    SkeletonMeter(labelWidth: 0, valueWidth: 34, format: .micro)
                        .frame(width: Self.cellWidth, alignment: .trailing)
                }
            }
        }
    }

    /// The shown windows under their header columns; a window whose kind no column names
    /// takes the first empty one, so nothing the recipe shows is dropped.
    private var placedWindows: [CompactAccountRowWindow?] {
        guard !columns.isEmpty else { return recipe.shownWindows }
        var placed: [CompactAccountRowWindow?] = columns.map { kind in
            recipe.shownWindows.first { $0.window.kind.persistentID == kind.persistentID }
        }
        let used = Set(placed.compactMap { $0?.window.kind.persistentID })
        for leftover in recipe.shownWindows where !used.contains(leftover.window.kind.persistentID) {
            if let gap = placed.firstIndex(where: { $0 == nil }) { placed[gap] = leftover }
        }
        return placed
    }

    private var tooltip: String {
        // The identity row's own tooltip lines (title, email, main account), then the meters'.
        var lines = IdentityRowText.helpLines(
            title: title,
            titleIsTruncated: true,
            email: email?.isEmpty == false ? email : nil,
            isMenuBarAccount: isMenuBarAccount,
            bankedHelp: PlanCapsulePresentation.helpLine(count: bankedResets)
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

/// The Compact card's one header line (Kyle, 2026-10-13): the provider's name over the account
/// names, and each column's window name with the left/used term ("5h left", "wk used")
/// right-aligned over its numbers, all in tertiary 11pt above one hairline. Every label sits over
/// what it describes, and a split card's second piece still says whose accounts it holds. Fixed
/// height, because the column planner counts it once per card piece.
struct CompactCardHeader: View {
    let providerName: String
    let columns: [WindowKind]
    let percentageMode: UsagePercentageMode

    /// 16pt line, 6pt to the hairline, 4pt to the first row.
    static let height: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: IdentityRowMetrics.spacing) {
                // On the names' axis, past the logo column.
                Color.clear.frame(width: IdentityRowMetrics.markSlotWidth, height: 1)
                Text(providerName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                HStack(spacing: CompactAccountRow.cellGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, kind in
                        Text("\(CompactAccountRowRecipe.shortLabel(for: kind)) \(percentageMode.term)")
                            .lineLimit(1)
                            .frame(width: CompactAccountRow.cellWidth, alignment: .trailing)
                    }
                }
            }
            .font(.system(size: MeterSuffixColumn.size))
            .foregroundStyle(.tertiary)
            .frame(height: 16)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.height)
        // The rows' own VoiceOver values already name each window and say left or used.
        .accessibilityHidden(true)
    }
}
