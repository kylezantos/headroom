import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// The Connected payoff is claimed per account, so a card rebuilt by the meter-style
/// crossfade (M5A) cannot replay the chip or queue a second settle for the same connection.
@MainActor
@Suite
struct ConnectedPayoffClaimTests {
    private func account(_ id: String) -> ProviderAccount {
        ProviderAccount(id: AccountID(id), providerID: .claude, label: id, isBuiltIn: false)
    }

    @Test func secondClaimForTheSameAccountIsRefused() {
        let activity = SetupSessionActivity()
        let key = account("claim-\(UUID().uuidString)").key
        #expect(activity.claimConnectedPayoff(for: key))
        #expect(!activity.claimConnectedPayoff(for: key))
    }

    @Test func claimsAreIndependentPerAccount() {
        let activity = SetupSessionActivity()
        let first = account("first-\(UUID().uuidString)").key
        let second = account("second-\(UUID().uuidString)").key
        #expect(activity.claimConnectedPayoff(for: first))
        #expect(activity.claimConnectedPayoff(for: second))
    }

    @Test func releaseAllowsTheNextConnectionToPayOffAgain() {
        let activity = SetupSessionActivity()
        let key = account("release-\(UUID().uuidString)").key
        #expect(activity.claimConnectedPayoff(for: key))
        activity.releaseConnectedPayoff(for: key)
        #expect(activity.claimConnectedPayoff(for: key))
    }

    /// `SetupSessions.settle(for:)` is the one place a payoff ends, so it must release the
    /// claim on the shared activity object.
    @Test func settleReleasesTheSharedClaim() {
        let target = account("settle-\(UUID().uuidString)")
        #expect(SetupSessionActivity.shared.claimConnectedPayoff(for: target.key))
        SetupSessions.settle(for: target)
        #expect(SetupSessionActivity.shared.claimConnectedPayoff(for: target.key))
        SetupSessionActivity.shared.releaseConnectedPayoff(for: target.key)
    }
}
