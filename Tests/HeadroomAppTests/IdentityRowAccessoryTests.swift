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

    @Test func theMenuBarGlyphNeedsTwoOrMoreAccounts() {
        #expect(IdentityRowText.feedsMenuBar(isPillSource: true, providerAccountCount: 2))
        #expect(IdentityRowText.feedsMenuBar(isPillSource: true, providerAccountCount: 7))
        #expect(!IdentityRowText.feedsMenuBar(isPillSource: true, providerAccountCount: 1))
        #expect(!IdentityRowText.feedsMenuBar(isPillSource: false, providerAccountCount: 3))
        #expect(IdentityRowText.menuBarSourceHelp == "Shown in the menu bar")
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
