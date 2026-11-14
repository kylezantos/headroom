import AppKit
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

/// SM3 → PS1: the live arranger shows a pending arrangement while the pointer is down and
/// commits once, on drop, through the store's move/add/remove contract. These pin the pure
/// decisions: where a card lands, where the others sit meanwhile, and what the drop writes.
@Suite(.sharedAppState)
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

    // MARK: Card geometry (six cards at the window floor)

    /// The well widths at the 720pt floor and the default 800pt window.
    private static let floorWell: CGFloat = 436
    private static let defaultWell: CGFloat = 516

    /// Characterization: every card that already fit its pill keeps today's pill exactly —
    /// 13.5pt numeral, 7pt gap and plate, carets — at both window widths.
    @Test func cardsThatFitTheirPillKeepTheStandardGeometry() {
        let today = PillCardGeometry(pill: .standard, showsCarets: true)
        #expect(MenuBarPillMetrics.standard.numeralSize == 13.5)
        #expect(MenuBarPillMetrics.standard.vesselTextGap == 7)
        #expect(MenuBarPillMetrics.standard.plateHorizontalPadding == 7)
        for count in 1...4 {
            let width = PillShelfModel.cardWidth(forWidth: Self.floorWell, count: count)
            #expect(PillShelfModel.cardGeometry(cardWidth: width, showsPercentage: true) == today)
        }
        for count in 1...5 {
            let width = PillShelfModel.cardWidth(forWidth: Self.defaultWell, count: count)
            #expect(PillShelfModel.cardGeometry(cardWidth: width, showsPercentage: true) == today)
        }
        // Pills only: the bare vessel fits every card at full size, carets included.
        for count in 1...6 {
            for well in [Self.floorWell, Self.defaultWell] {
                let width = PillShelfModel.cardWidth(forWidth: well, count: count)
                let geometry = PillShelfModel.cardGeometry(cardWidth: width, showsPercentage: false)
                #expect(geometry.pill == .standard && geometry.showsCarets)
            }
        }
    }

    /// A card's widest pill ("100%") stays inside the card at every width from the 720pt
    /// floor up, for one to six cards, and the carets show only where they clear it. The
    /// row itself never overlaps: every card sits in its own slot.
    @Test func everyCardHoldsItsWidestPill() {
        for count in 1...6 {
            for well in stride(from: Self.floorWell, through: 1_200, by: 1) {
                let width = PillShelfModel.cardWidth(forWidth: well, count: count)
                #expect(2 * PillShelfModel.wellPadding + CGFloat(count) * width
                    + CGFloat(count - 1) * PillShelfModel.spacing <= well)
                for showsPercentage in [false, true] {
                    let geometry = PillShelfModel.cardGeometry(cardWidth: width, showsPercentage: showsPercentage)
                    let pill = geometry.pill.widestPillWidth(showsPercentage: showsPercentage)
                    #expect(pill <= width, "count \(count) well \(well): \(pill) in \(width)")
                    if geometry.showsCarets {
                        #expect(pill + 2 * PillShelfModel.caretReserve <= width,
                                "count \(count) well \(well): carets collide")
                    }
                }
            }
        }
    }

    /// Six cards: compact with carets at the default window (76pt), compact without them at
    /// the floor (63pt), standard again once the window gives each card 91pt.
    @Test func sixCardsStepDownAtNarrowWindows() {
        let floor = PillShelfModel.cardGeometry(
            cardWidth: PillShelfModel.cardWidth(forWidth: Self.floorWell, count: 6), showsPercentage: true)
        #expect(floor == PillCardGeometry(pill: .compact, showsCarets: false, showsName: false))
        let standard = PillShelfModel.cardGeometry(
            cardWidth: PillShelfModel.cardWidth(forWidth: Self.defaultWell, count: 6), showsPercentage: true)
        #expect(standard == PillCardGeometry(pill: .compact, showsCarets: true))
        #expect(PillShelfModel.cardGeometry(cardWidth: 90, showsPercentage: true).pill == .compact)
        #expect(PillShelfModel.cardGeometry(cardWidth: 91, showsPercentage: true)
            == PillCardGeometry(pill: .standard, showsCarets: true))
        #expect(MenuBarPillMetrics.compact.widestPillWidth(showsPercentage: true) <= PillShelfModel.minimumCardWidth)
    }

    /// The name leaves the header only where it would be a bare ellipsis; every card of up to
    /// five providers, and six at the default window, keeps it.
    @Test func theNameLeavesOnlyTheNarrowestCards() {
        for count in 1...6 {
            for well in [Self.floorWell, Self.defaultWell] {
                let width = PillShelfModel.cardWidth(forWidth: well, count: count)
                let expected = !(count == 6 && well == Self.floorWell)
                #expect(PillShelfModel.cardGeometry(cardWidth: width, showsPercentage: true).showsName == expected)
                #expect(PillShelfModel.cardGeometry(cardWidth: width, showsPercentage: false).showsName == expected)
            }
        }
    }
}

/// The widest-numeral constants are measured, not guessed: the real font's "100%" must round
/// up to them, and no two-digit value may be wider.
@MainActor
struct MenuBarPillMetricsTests {
    @Test func widestNumeralMatchesTheFont() {
        for metrics in [MenuBarPillMetrics.standard, .compact] {
            let font = NSFont.monospacedDigitSystemFont(ofSize: metrics.numeralSize, weight: .medium)
            func width(_ text: String) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
            #expect(width("100%") == metrics.widestNumeralWidth)
            for value in [0, 8, 38, 88, 99] {
                #expect(width("\(value)%") <= metrics.widestNumeralWidth)
            }
        }
    }
}
