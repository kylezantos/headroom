import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

/// SM3: the live arranger shows a pending order through offsets and commits once, on drop,
/// through the store's move-before contract. These pin the translation from "card left slot
/// `start` and settled in slot `target`" to that contract.
struct MenuBarPillArrangerTests {
    private typealias Arranger = MenuBarPillArranger<EmptyView>
    private let ids: [ProviderID] = [.claude, .codex, ProviderID("grok"), ProviderID("cursor")]

    @Test func movingRightLandsBeforeTheCardAfterTheTarget() {
        #expect(Arranger.insertionTarget(in: ids, moving: 0, to: 2) == ProviderID("cursor"))
    }

    @Test func movingLeftLandsBeforeTheCardItDisplaced() {
        #expect(Arranger.insertionTarget(in: ids, moving: 3, to: 0) == .claude)
        #expect(Arranger.insertionTarget(in: ids, moving: 2, to: 1) == .codex)
    }

    @Test func movingToTheLastSlotAppends() {
        #expect(Arranger.insertionTarget(in: ids, moving: 0, to: 3) == nil)
    }

    @Test func everyCommitReproducesTheOrderTheRowShowed() {
        for start in ids.indices {
            for target in ids.indices where target != start {
                var shown = ids
                shown.insert(shown.remove(at: start), at: target)

                let moved = ids[start]
                var committed = ids.filter { $0 != moved }
                let before = Arranger.insertionTarget(in: ids, moving: start, to: target)
                committed.insert(moved, at: before.flatMap(committed.firstIndex(of:)) ?? committed.endIndex)

                #expect(committed == shown, "start \(start) → target \(target)")
            }
        }
    }
}
