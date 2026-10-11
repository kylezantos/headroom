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

    static let spend = PopoverColumnSlot(id: spendID, providerID: nil)
}

/// KTD3 / KTD10: the popover's column plan, owned by `PopoverView`. Measured heights stay out of
/// observation; only the resolved `Equatable` plan is observed, and it is written only when it
/// changes, so a height report never re-runs the popover body.
///
/// Replan triggers (KTD2, amended by the U1 spike): the popover closing, an account-set change,
/// and a layout preference change. The U1 spike found the popover's view state survives close
/// and reopen, and that a width change made on open shows the old width for ~116ms first, so the
/// plan for the next open is made as the popover closes, from the heights it last drew.
@MainActor
@Observable
final class PopoverPlanModel {
    private(set) var plan: AccountColumnsPlan?

    @ObservationIgnored private var slots: [PopoverColumnSlot] = []
    @ObservationIgnored private var heights: [String: Double] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var replanScheduled = false
    @ObservationIgnored private let cap: Double

    init(cap: Double) {
        self.cap = cap
    }

    /// What to draw for `slots`: the plan, carried across an account-set change until the new
    /// items have been measured.
    func drawnPlan(for slots: [PopoverColumnSlot]) -> AccountColumnsPlan {
        AccountColumnsPlanner.carried(plan, to: slots.map(Self.placeholderItem))
    }

    func update(slots newSlots: [PopoverColumnSlot]) {
        guard newSlots != slots else { return }
        slots = newSlots
        replanIfNeeded()
    }

    /// A measured content height, without card padding. Height changes alone never replan (R6);
    /// they only complete a replan that was waiting on them. Heights arrive from inside layout
    /// (`ColumnItemsStack`), so a replan they complete runs after the pass, not during it.
    func record(_ height: CGFloat, for id: String) {
        let value = Double(height)
        if let old = heights[id], abs(old - value) <= AccountColumnsPlanner.heightTolerance { return }
        heights[id] = value
        guard needsReplan, !replanScheduled else { return }
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

    /// A different layout draws different heights, so the old ones can't plan it.
    func layoutDidChange() {
        generation += 1
        heights.removeAll()
    }

    private var needsReplan: Bool {
        AccountColumnsPlanner.needsReplan(previous: plan, itemIDs: slots.map(\.id), generation: generation)
    }

    private func replanIfNeeded() {
        guard needsReplan, let items = measuredItems() else { return }
        let next = AccountColumnsPlanner.plan(items: items, cap: cap, generation: generation, previous: plan)
        if next != plan { plan = next }
    }

    /// Every slot's height, with a capability header folded into its provider's first item
    /// (KTD1), or nil while any is unmeasured.
    private func measuredItems() -> [AccountColumnsItem]? {
        var items: [AccountColumnsItem] = []
        for slot in slots {
            guard var height = heights[slot.id] else { return nil }
            if let headerID = slot.headerID {
                guard let header = heights[headerID] else { return nil }
                height += header + AccountColumnsMetrics.popover.accountGap
            }
            items.append(AccountColumnsItem(id: slot.id, groupID: slot.groupID, height: height, isSpend: slot.isSpend))
        }
        return items
    }

    private static func placeholderItem(_ slot: PopoverColumnSlot) -> AccountColumnsItem {
        AccountColumnsItem(id: slot.id, groupID: slot.groupID, height: 0, isSpend: slot.isSpend)
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
        let items = slots.map {
            AccountColumnsItem(id: $0.id, groupID: $0.groupID, height: 0, isSpend: $0.isSpend)
        }
        var groupStart: [String: Int] = [:]
        for (index, slot) in slots.enumerated() where groupStart[slot.groupID] == nil {
            groupStart[slot.groupID] = index
        }
        return AccountColumnsPlanner.placement(of: plan, items: items).fragments.map { fragment in
            let slot = slots[fragment.itemRange.lowerBound]
            let start = groupStart[fragment.groupID] ?? 0
            let isWholeCard = slot.isSpend || slots[fragment.itemRange].count == slots.lazy
                .filter { $0.groupID == fragment.groupID }.count
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
