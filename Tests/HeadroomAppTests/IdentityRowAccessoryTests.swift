import Foundation
import HeadroomCore
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
}
