import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

/// SM3 → PS1: the live arranger shows a pending arrangement while the pointer is down and
/// commits once, on drop, through the store's move/add/remove contract. These pin the pure
/// decisions: where a card lands, where the others sit meanwhile, and what the drop writes.
struct MenuBarPillArrangerTests {
    private typealias Arranger = PillShelfModel
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

    // MARK: - Two shelves (PS1)

    private let grok = ProviderID("grok")
    private let cursor = ProviderID("cursor")
    private let pitch: CGFloat = 108

    private func drop(
        _ id: ProviderID,
        shown: [ProviderID],
        notShown: [ProviderID],
        dx: CGFloat,
        inNotShown: Bool
    ) -> PillShelfSlot? {
        PillShelfModel.drop(
            for: id, shown: shown, notShown: notShown, canonicalOrder: ids,
            translation: dx, pointerInNotShown: inNotShown, pitch: pitch
        )
    }

    @Test func aShelfCardDraggedUpLandsAtTheSlotUnderIt() {
        // Grok is the shelf's first card, under the menu bar's first slot.
        let shown: [ProviderID] = [.claude, .codex]
        let notShown = [grok, cursor]
        #expect(drop(grok, shown: shown, notShown: notShown, dx: 0, inNotShown: false)
            == PillShelfSlot(shelf: .menuBar, index: 0))
        #expect(drop(grok, shown: shown, notShown: notShown, dx: pitch * 0.6, inNotShown: false)
            == PillShelfSlot(shelf: .menuBar, index: 1))
        // Past the last pill it appends, never beyond.
        #expect(drop(grok, shown: shown, notShown: notShown, dx: pitch * 9, inNotShown: false)
            == PillShelfSlot(shelf: .menuBar, index: 2))
        #expect(PillShelfModel.commit(for: grok, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .menuBar, index: 1)) == .add(grok, before: .codex))
        #expect(PillShelfModel.commit(for: grok, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .menuBar, index: 2)) == .add(grok, before: nil))
    }

    @Test func aPillDraggedDownReturnsToItsCanonicalShelfSlot() {
        let shown: [ProviderID] = [cursor, .codex]
        let notShown: [ProviderID] = [.claude, grok]
        // Cursor is last in canonical order, so it lands after Grok wherever it is dropped.
        #expect(drop(cursor, shown: shown, notShown: notShown, dx: -pitch * 3, inNotShown: true)
            == PillShelfSlot(shelf: .notShown, index: 2))
        #expect(drop(.codex, shown: shown, notShown: notShown, dx: 0, inNotShown: true)
            == PillShelfSlot(shelf: .notShown, index: 1))
        #expect(PillShelfModel.commit(for: .codex, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .notShown, index: 1)) == .remove(.codex))
    }

    @Test func theLastPillCannotLeaveTheMenuBar() {
        let shown: [ProviderID] = [.codex]
        let notShown: [ProviderID] = [.claude, grok, cursor]
        #expect(drop(.codex, shown: shown, notShown: notShown, dx: 0, inNotShown: true)
            == PillShelfSlot(shelf: .menuBar, index: 0))
        #expect(PillShelfModel.commit(for: .codex, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .notShown, index: 1)) == .none)
    }

    @Test func releasingWhereTheCardStartedWritesNothing() {
        let shown: [ProviderID] = [.claude, .codex]
        let notShown = [grok, cursor]
        #expect(PillShelfModel.commit(for: .codex, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .menuBar, index: 1)) == .none)
        #expect(PillShelfModel.commit(for: grok, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .notShown, index: 0)) == .none)
        #expect(PillShelfModel.commit(for: .claude, shown: shown, notShown: notShown,
                                      drop: PillShelfSlot(shelf: .menuBar, index: 1)) == .move(.claude, before: nil))
    }

    @Test func theOtherCardsOpenAGapAtTheDropAndCloseTheOneLeft() {
        let shown: [ProviderID] = [.claude, .codex]
        let notShown = [grok, cursor]
        let slots = PillShelfModel.slots(
            shown: shown, notShown: notShown, dragging: cursor,
            drop: PillShelfSlot(shelf: .menuBar, index: 1)
        )
        #expect(slots[.claude] == PillShelfSlot(shelf: .menuBar, index: 0))
        #expect(slots[.codex] == PillShelfSlot(shelf: .menuBar, index: 2))
        #expect(slots[grok] == PillShelfSlot(shelf: .notShown, index: 0))
        // The dragged card keeps its origin; its pointer offset is measured from there.
        #expect(slots[cursor] == PillShelfSlot(shelf: .notShown, index: 1))

        let resting = PillShelfModel.slots(shown: shown, notShown: notShown, dragging: nil, drop: nil)
        #expect(resting[.codex] == PillShelfSlot(shelf: .menuBar, index: 1))
        #expect(resting[cursor] == PillShelfSlot(shelf: .notShown, index: 1))
    }

    /// PS7: a released card is anchored at its drop slot, and that arrangement is exactly
    /// what the store commits, so the commit moves nothing on screen.
    @Test func aLandingCardIsAnchoredWhereTheCommitPutsIt() {
        let shown: [ProviderID] = [.claude, .codex]
        let notShown = [grok, cursor]
        let drop = PillShelfSlot(shelf: .menuBar, index: 1)
        let landing = PillShelfModel.slots(
            shown: shown, notShown: notShown, dragging: cursor, drop: drop, holdsOrigin: false
        )
        #expect(landing[cursor] == drop)
        let committed = PillShelfModel.slots(shown: [.claude, cursor, .codex], notShown: [grok], dragging: nil, drop: nil)
        #expect(landing == committed)
    }

    @Test func fourCardsFitOneRowAtTheWindowFloor() {
        // 720pt window − 216pt sidebar − 40pt pane padding − 26pt tile padding − 2pt inset,
        // less the well's 9pt insets and three 8pt gaps.
        #expect(PillShelfModel.cardWidth(forWidth: 436, count: 4) == 98)
        #expect(PillShelfModel.cardWidth(forWidth: 600, count: 4) == PillShelfModel.maximumCardWidth)
        #expect(PillShelfModel.cardWidth(forWidth: 0, count: 4) == PillShelfModel.minimumCardWidth)
    }

    /// U6 (Copilot plan): five cards share one row at the same 436pt floor.
    @Test func fiveCardsFitOneRowAtTheWindowFloor() {
        let width = PillShelfModel.cardWidth(forWidth: 436, count: 5)
        #expect(width == 77)
        #expect(2 * PillShelfModel.wellPadding + 5 * width + 4 * PillShelfModel.spacing <= 436)
    }

    /// U7 (OpenCode plan): one to five cards keep the widths they had before a sixth provider,
    /// at the 720pt floor (436pt well) and the default 800pt window (516pt well).
    @Test func oneToFiveCardsKeepTheirWidths() {
        let floor: [Int: CGFloat] = [1: 100, 2: 100, 3: 100, 4: 98, 5: 77]
        let standard: [Int: CGFloat] = [1: 100, 2: 100, 3: 100, 4: 100, 5: 93]
        for count in 1...5 {
            #expect(PillShelfModel.cardWidth(forWidth: 436, count: count) == floor[count])
            #expect(PillShelfModel.cardWidth(forWidth: 516, count: count) == standard[count])
            #expect(PillShelfModel.cardWidth(forWidth: 436, count: count) > 62)
        }
    }

    /// U7 (OpenCode plan, KTD14): six cards share one row at the 720pt floor. Each is at
    /// least the 62pt minimum and the row fits the well; at the default window they get 76.
    @Test func sixCardsFitOneRowAtTheWindowFloor() {
        #expect(PillShelfModel.minimumCardWidth == 62)
        let width = PillShelfModel.cardWidth(forWidth: 436, count: 6)
        #expect(width >= PillShelfModel.minimumCardWidth)
        #expect(width == 63)
        #expect(2 * PillShelfModel.wellPadding + 6 * width + 5 * PillShelfModel.spacing <= 436)
        #expect(PillShelfModel.cardWidth(forWidth: 516, count: 6) == 76)
    }
}
