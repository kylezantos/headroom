import AppKit
import Foundation
import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

@Suite(.sharedAppState) struct IdentityRowAccessoryTests {
    private let key = AccountKey(providerID: .grok, accountID: .primary)
    @Test func accountActionsShowOnlyTheirOwnAccessory() {
        let value = AccountLoadingState.resolve(key: key, checking: [key], probing: [key], ends: [:], fullRefresh: false)
        #expect(value.showsAccessory)
        #expect(value.motion == .slosh)
        let other = AccountKey(providerID: .grok, accountID: AccountID("other"))
        #expect(!AccountLoadingState.resolve(key: other, checking: [key], probing: [key], ends: [:], fullRefresh: false).showsAccessory)
    }
    @Test func timersAndFullRefreshDoNotShowAccountActionAccessories() {
        #expect(!AccountLoadingState.resolve(key: key, checking: [], probing: [key], ends: [:], fullRefresh: false).showsAccessory)
        #expect(!AccountLoadingState.resolve(key: key, checking: [key], probing: [key], ends: [:], fullRefresh: true).showsAccessory)
    }
    @Test func queuedPendingAccountsDoNotPretendToBeProbing() {
        let value = AccountLoadingState.resolve(key: key, checking: [key], probing: [], ends: [:], fullRefresh: false)
        #expect(value.showsAccessory)
        #expect(value.motion == .still)
        #expect(AccountLoadingState.resolve(key: key, checking: [], probing: [key], ends: [:], fullRefresh: false).motion == .slosh)
    }
    @Test func spendWaitTracksActualFetchForEverySpendProvider() {
        for provider in [ProviderID.claude, .codex, .grok, .cursor] {
            #expect(SpendWaitingLine.motion(providerID: provider, inFlight: []) == .still)
            #expect(SpendWaitingLine.motion(providerID: provider, inFlight: [provider]) == .slosh)
        }
    }

    // MARK: CA-P3: the stale chip and VoiceOver say one thing

    @Test func aStaleRowSaysWhenItWasReadAndVoiceOverMatches() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let chip = Countdown.staleReadLabel(capturedAt: now.addingTimeInterval(-14 * 60), now: now)
        #expect(chip == "Last read 14 min ago")
        let spoken = IdentityRowText.accessibilityParts(
            title: "Work", planDisplayName: "Pro", isMenuBarAccount: false, isStale: true,
            email: nil, showsConnectedChip: false, bankedPhrase: nil, staleLabel: chip)
        #expect(spoken == "Work, Pro plan, Last read 14 min ago")
        #expect(!spoken.contains("Stale"))
        // A host that passes no read age keeps today's words.
        let legacy = IdentityRowText.accessibilityParts(
            title: "Work", planDisplayName: nil, isMenuBarAccount: false, isStale: true,
            email: nil, showsConnectedChip: false, bankedPhrase: nil)
        #expect(legacy == "Work, Stale")
        #expect(Countdown.staleReadLabel(capturedAt: nil, now: now) == "Not refreshed")
    }

    // MARK: CA-MB3: the menu-bar source glyph

    /// MB4: any account that feeds a pill carries the glyph, a provider's only account included.
    @Test func theMenuBarGlyphMarksEveryPillSource() {
        #expect(IdentityRowText.feedsMenuBar(isPillSource: true))
        #expect(!IdentityRowText.feedsMenuBar(isPillSource: false))
        #expect(IdentityRowText.menuBarSourceHelp == "Shown in the menu bar")
    }

    /// CA-MB3 review fix: "main account" (tooltip, VoiceOver, Compact label) and "feeds a pill"
    /// (the glyph) are two facts. A main account whose provider is not in the menu bar keeps
    /// its main-account words and draws no glyph.
    @MainActor @Test func aMainAccountOutOfTheMenuBarKeepsItsWordsAndDrawsNoGlyph() {
        func width(main: Bool) -> CGFloat {
            NSHostingView(rootView: IdentityRow(
                providerID: .claude, title: "Work", planLabel: nil, isMenuBarAccount: main,
                isStale: false, email: nil, showsPersistentEmail: false, showsConnectedChip: false,
                mark: { side in Color.clear.frame(width: side, height: side) }
            )).fittingSize.width
        }
        #expect(width(main: true) == width(main: false))
        #expect(IdentityRowText.helpLines(
            title: "Work", titleIsTruncated: false, email: nil, isMenuBarAccount: true, bankedHelp: nil
        ) == IdentityRowText.mainAccountHelp)
        #expect(IdentityRowText.isMainAccountRow(isDisplayPrimary: true, providerAccountCount: 2))
        #expect(!IdentityRowText.isMainAccountRow(isDisplayPrimary: true, providerAccountCount: 1))
        #expect(!IdentityRowText.isMainAccountRow(isDisplayPrimary: false, providerAccountCount: 2))
    }

    @MainActor @Test func onlyThePillSourceDrawsTheGlyph() {
        func width(glyph: Bool) -> CGFloat {
            NSHostingView(rootView: IdentityRow(
                providerID: .claude, title: "Work", planLabel: nil, isMenuBarAccount: true,
                isStale: false, email: nil, showsPersistentEmail: false, showsConnectedChip: false,
                showsMenuBarSourceGlyph: glyph,
                mark: { side in Color.clear.frame(width: side, height: side) }
            )).fittingSize.width
        }
        #expect(width(glyph: true) > width(glyph: false) + MenuBarSourceGlyph.size.width)
    }

    /// CA-I5 review fix: the phone's spend card chooses its chip fit from its rows' ideal width
    /// (`ViewThatFits`). A stale row's status sentence wraps to the card, so it must not widen
    /// that ideal width, or every chip drops to a subline whenever any row is non-live.
    @MainActor @Test func aSpendRowsSentenceNeverWidensItsIdealWidth() {
        func idealWidth(stale: Bool) -> CGFloat {
            let snapshot = APISpendSnapshot(
                providerID: .claude, displayName: "Anthropic API", amount: 142.67, currency: "USD",
                periodLabel: "This month", capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                freshness: stale ? .stale(.transient("x")) : .live)
            let status = APISpendRowStatus(
                badge: stale ? "3h ago" : nil, shortBadge: stale ? "3h ago" : nil, tone: .neutral,
                message: stale ? "Couldn’t read the amount. Your Mac will try again on its next check." : nil,
                callToAction: nil, remoteHint: nil)
            let row = APISpendRow(
                snapshot: snapshot, status: status, title: "Anthropic API", contextLabel: "This month",
                amount: "$142.67", amountColumnWidth: 80, scale: 1.15, chipFit: .inline,
                mark: { side in Color.clear.frame(width: side, height: side) },
                waitingLine: { Text($0) })
            return NSHostingView(rootView: row).fittingSize.width
        }
        #expect(!(idealWidth(stale: true) > idealWidth(stale: false) + 1))
    }

    @MainActor @Test func theMenuBarGlyphIsSevenByEleven() {
        let size = NSHostingView(rootView: MenuBarSourceGlyph()).fittingSize
        #expect(size == CGSize(width: 7, height: 11))
        let phone = NSHostingView(rootView: MenuBarSourceGlyph(scale: 1.15)).fittingSize
        // Fitting sizes land on the point grid, so the scaled glyph is checked to within it.
        #expect(abs(phone.width - 7 * 1.15) < 1)
    }

    // MARK: CA-P11: one numeral edge

    /// With "left" and "used" both on screen, a percentage and a currency figure end on one
    /// trailing x: every suffix reserves the same column, whichever word it prints.
    @MainActor @Test func everySuffixReservesTheSameColumn() {
        #expect(Set(MeterSuffixColumn.terms) == ["left", "used"])
        let left = NSHostingView(rootView: MeterSuffixLabel(term: "left")).fittingSize.width
        let used = NSHostingView(rootView: MeterSuffixLabel(term: "used")).fittingSize.width
        let hidden = NSHostingView(rootView: MeterSuffixLabel(term: "left", isVisible: false)).fittingSize.width
        #expect(left == used)
        #expect(hidden == used)
        #expect(used > 0)
        let spendTerm = APISpendPresentation.directionTerm(kind: .periodSpend)
        let spend = NSHostingView(rootView: MeterSuffixLabel(term: spendTerm)).fittingSize.width
        #expect(spend == left)
    }
}
