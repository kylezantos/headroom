import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// The Connected payoff is claimed per account, so a card rebuilt by the meter-style
/// crossfade (M5A) cannot replay the chip or queue a second settle for the same connection.
@MainActor
@Suite(.sharedAppState)
struct ConnectedPayoffClaimTests {
    private func account(_ id: String) -> ProviderAccount {
        ProviderAccount(id: AccountID(id), providerID: .claude, label: id, isBuiltIn: false)
    }

    @Test func secondClaimForTheSameAccountIsRefused() {
        let activity = SetupSessionActivity()
        let key = account("claim-\(UUID().uuidString)").key
        #expect(activity.claimConnectedPayoff(for: key) != nil)
        #expect(activity.claimConnectedPayoff(for: key) == nil)
    }

    @Test func claimsAreIndependentPerAccount() {
        let activity = SetupSessionActivity()
        let first = account("first-\(UUID().uuidString)").key
        let second = account("second-\(UUID().uuidString)").key
        #expect(activity.claimConnectedPayoff(for: first) != nil)
        #expect(activity.claimConnectedPayoff(for: second) != nil)
    }

    @Test func releaseAllowsTheNextConnectionToPayOffAgain() {
        let activity = SetupSessionActivity()
        let key = account("release-\(UUID().uuidString)").key
        #expect(activity.claimConnectedPayoff(for: key) != nil)
        activity.releaseConnectedPayoff(for: key)
        #expect(activity.claimConnectedPayoff(for: key) != nil)
    }

    @Test func staleSettleCannotReleaseTheNextConnectionsClaim() throws {
        let activity = SetupSessionActivity()
        let key = account("stale-settle-\(UUID().uuidString)").key
        let oldClaim = try #require(activity.claimConnectedPayoff(for: key))
        activity.releaseConnectedPayoff(for: key)
        let currentClaim = try #require(activity.claimConnectedPayoff(for: key))

        #expect(!activity.releaseConnectedPayoff(oldClaim, for: key))
        #expect(activity.claimConnectedPayoff(for: key) == nil)
        #expect(activity.releaseConnectedPayoff(currentClaim, for: key))
    }

    /// `SetupSessions.settle(for:)` is the one place a payoff ends, so it must release the
    /// claim on the shared activity object.
    @Test func settleReleasesTheSharedClaim() {
        let target = account("settle-\(UUID().uuidString)")
        #expect(SetupSessionActivity.shared.claimConnectedPayoff(for: target.key) != nil)
        SetupSessions.settle(for: target)
        #expect(SetupSessionActivity.shared.claimConnectedPayoff(for: target.key) != nil)
        SetupSessionActivity.shared.releaseConnectedPayoff(for: target.key)
    }
}
