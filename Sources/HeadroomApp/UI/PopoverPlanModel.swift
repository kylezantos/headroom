import Foundation
import Observation
import HeadroomCore

/// One entry in the popover's column flow (KTD1): an account section of a multi-account card,
/// a whole single-account card, or the API spend card. `headerID` names the capability-recovery
/// header that the provider's first fragment draws above this item (R9).
struct PopoverColumnSlot: Equatable {
    static let spendID = "spend"

    let id: String
    let providerID: ProviderID?
    var headerID: String? = nil

    var isSpend: Bool { providerID == nil }
    var groupID: String { providerID?.raw ?? Self.spendID }

    /// The slot as a planner item with no height: enough to carry or place a plan.
    var placeholderItem: AccountColumnsItem {
        AccountColumnsItem(id: id, groupID: groupID, height: 0, isSpend: isSpend)
    }

    static let spend = PopoverColumnSlot(id: spendID, providerID: nil)
}

/// KTD3 / KTD10: the popover's column plan, owned by `PopoverView`. Measured heights stay out of
/// observation, and so does the plan itself: the body observes only `drawnRevision`, which moves
/// when a new plan draws differently. A height report never re-runs the popover body, and nor
/// does a first plan that draws the one column already on screen.
///
/// Replan triggers (KTD2, amended by the U1 spike): the popover closing, an account-set change,
/// and a layout preference change. The U1 spike found the popover's view state survives close
/// and reopen, and that a width change made on open shows the old width for ~116ms first, so the
/// plan for the next open is made as the popover closes, from the heights it last drew.
@MainActor
@Observable
final class PopoverPlanModel {
    @ObservationIgnored private(set) var plan: AccountColumnsPlan?
    private var drawnRevision = 0

    @ObservationIgnored private var slots: [PopoverColumnSlot] = []
    @ObservationIgnored private var slotIDs: [String] = []
    @ObservationIgnored private var heights: [String: Double] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var replanScheduled = false
    @ObservationIgnored private let cap: Double
    @ObservationIgnored private var layout: AccountLayout?
    private var metrics: AccountColumnsMetrics { Self.metrics(for: layout ?? .standard) }

    init(cap: Double) {
        self.cap = cap
    }

    /// What to draw for `slots`: the plan, carried across an account-set change until the new
    /// items have been measured.
    func drawnPlan(for slots: [PopoverColumnSlot]) -> AccountColumnsPlan {
        _ = drawnRevision
        return Self.drawn(plan, for: slots)
    }

    private static func drawn(_ plan: AccountColumnsPlan?, for slots: [PopoverColumnSlot]) -> AccountColumnsPlan {
        AccountColumnsPlanner.carried(plan, to: slots.map(\.placeholderItem))
    }

    func update(slots newSlots: [PopoverColumnSlot]) {
        guard newSlots != slots else { return }
        slots = newSlots
        slotIDs = newSlots.map(\.id)
        // Removed accounts' heights would otherwise linger for the life of the popover.
        let live = Set(slotIDs + newSlots.compactMap(\.headerID))
        heights = heights.filter { live.contains($0.key) }
        replanIfNeeded()
    }

    /// A measured content height, without card padding. Height changes alone never replan (R6);
    /// they only complete a replan that was waiting on them. Heights arrive from inside layout
    /// (`ColumnItemsStack`), so a replan they complete runs after the pass, not during it.
    func record(_ height: CGFloat, for id: String) {
        let value = Double(height)
        if let old = heights[id], abs(old - value) <= AccountColumnsPlanner.heightTolerance { return }
        heights[id] = value
        guard !replanScheduled, needsReplan else { return }
        replanScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            replanScheduled = false
            replanIfNeeded()
        }
    }

    func popoverDidClose() {
        generation += 1
        replanIfNeeded()
    }

    /// A different layout draws different heights and a different account gap, so it opens a new
    /// generation (KTD2). The heights stay: clearing them stranded the plan, because the spend
    /// card and whole cards report only when their height changes, so an unchanged one never
    /// came back. Every height the new layout changes is re-reported in its first pass (account
    /// sections always, the others because they changed), and the replan those reports complete
    /// runs on the next main turn, after the whole pass; the heights it leaves alone still hold.
    func setLayout(_ newLayout: AccountLayout) {
        guard newLayout != layout else { return }
        let isFirst = layout == nil
        layout = newLayout
        guard !isFirst else { return }
        generation += 1
    }

    /// Compact rows sit 4pt apart in a card; Standard sections 26pt.
    static func metrics(for layout: AccountLayout) -> AccountColumnsMetrics {
        var metrics = AccountColumnsMetrics.popover
        if layout == .compact { metrics.accountGap = Double(CompactAccountRow.rowGap) }
        return metrics
    }

    private var needsReplan: Bool {
        AccountColumnsPlanner.needsReplan(previous: plan, itemIDs: slotIDs, generation: generation)
    }

    private func replanIfNeeded() {
        guard needsReplan, let items = measuredItems() else { return }
        let next = AccountColumnsPlanner.plan(
            items: items, cap: cap, generation: generation, previous: plan, metrics: metrics
        )
        guard next != plan else { return }
        let before = Self.drawn(plan, for: slots)
        plan = next
        let after = Self.drawn(next, for: slots)
        if before.columnCount != after.columnCount || before.splitIndex != after.splitIndex {
            drawnRevision &+= 1
        }
    }

    /// Every slot's height, with a capability header folded into its provider's first item
    /// (KTD1), or nil while any is unmeasured.
    private func measuredItems() -> [AccountColumnsItem]? {
        var items: [AccountColumnsItem] = []
        for slot in slots {
            guard var height = heights[slot.id] else { return nil }
            if let headerID = slot.headerID {
                guard let header = heights[headerID] else { return nil }
                // The capability card's header sits a Standard account gap above its accounts.
                height += header + AccountColumnsMetrics.popover.accountGap
            }
            items.append(AccountColumnsItem(id: slot.id, groupID: slot.groupID, height: height, isSpend: slot.isSpend))
        }
        return items
    }
}

/// One card, or one piece of a provider card split across the two columns (KTD6).
struct PopoverCardFragment: Identifiable, Equatable {
    /// Stable per provider and piece, so a moved split updates the same two cards.
    let id: String
    let providerID: ProviderID?
    /// Indices into the provider's drawn accounts; nil draws the whole card.
    let accountRange: Range<Int>?
    let isFirstFragment: Bool
    let column: Int

    var isSpend: Bool { providerID == nil }

    /// The fragments to draw for `plan`, in reading order (R5).
    static func fragments(slots: [PopoverColumnSlot], plan: AccountColumnsPlan) -> [PopoverCardFragment] {
        var groupStart: [String: Int] = [:]
        var groupCount: [String: Int] = [:]
        for (index, slot) in slots.enumerated() {
            if groupStart[slot.groupID] == nil { groupStart[slot.groupID] = index }
            groupCount[slot.groupID, default: 0] += 1
        }
        return AccountColumnsPlanner.placement(of: plan, items: slots.map(\.placeholderItem)).fragments.map { fragment in
            let slot = slots[fragment.itemRange.lowerBound]
            let start = groupStart[fragment.groupID] ?? 0
            let isWholeCard = slot.isSpend || fragment.itemRange.count == groupCount[fragment.groupID]
            return PopoverCardFragment(
                id: "\(fragment.groupID)#\(fragment.isFirstFragmentOfGroup ? 0 : 1)",
                providerID: slot.providerID,
                accountRange: isWholeCard
                    ? nil
                    : (fragment.itemRange.lowerBound - start)..<(fragment.itemRange.upperBound - start),
                isFirstFragment: fragment.isFirstFragmentOfGroup,
                column: fragment.column
            )
        }
    }
}
