import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// R15: Compact never hides an action. An account whose setup session owns its row keeps the
/// Standard section, and so does a `.connected` session, whose payoff only that section settles.
/// The pure overload is exercised with inputs from the same helpers the card uses, so no
/// shared `SetupSessions` coordinator state is created or left behind.
@MainActor
@Suite
struct CompactFallbackTests {
    private let account = ProviderAccount(
        id: AccountID("compact-fallback-\(UUID().uuidString)"),
        providerID: .claude,
        label: "Compact Fallback",
        isBuiltIn: false
    )

    private func needsStandardSection(
        _ state: SetupSessionState,
        hasActiveHandoff: Bool = false
    ) -> Bool {
        var failureMessage: String?
        if case .failed(let failure) = state {
            failureMessage = SetupSessions.failureMessage(for: failure, account: account)
        }
        return compactRowNeedsStandardSection(
            state: state,
            offersStopWaiting: setupSessionOffersStopWaiting(state: state, hasActiveHandoff: hasActiveHandoff),
            hasFailureMessage: failureMessage != nil
        )
    }

    @Test func waitingSessionThatOffersStopWaitingKeepsStandard() {
        #expect(setupSessionOffersStopWaiting(state: .waiting(attempt: 0), hasActiveHandoff: true))
        #expect(needsStandardSection(.waiting(attempt: 0), hasActiveHandoff: true))
    }

    @Test func openHandoffAloneKeepsStandard() {
        // An idle state with a still-open Terminal handoff still offers Stop Waiting.
        #expect(compactRowNeedsStandardSection(state: .idle, offersStopWaiting: true, hasFailureMessage: false))
    }

    @Test func failureMessageKeepsStandard() {
        // `.retryExhausted` is an outcome-recovery state, so only its sentence keeps the section.
        #expect(!setupSessionOwnsSurface(for: .failed(.retryExhausted)))
        #expect(needsStandardSection(.failed(.retryExhausted)))
        #expect(compactRowNeedsStandardSection(state: .idle, offersStopWaiting: false, hasFailureMessage: true))
    }

    @Test func handoffRefusalKeepsStandard() {
        #expect(needsStandardSection(.blockedByOpenHandoff))
    }

    @Test func connectedSessionKeepsStandardUntilItsPayoffSettles() {
        #expect(!setupSessionOwnsSurface(for: .connected))
        #expect(needsStandardSection(.connected))
    }

    @Test func idleAccountUsesCompactRow() {
        #expect(!needsStandardSection(.idle))
        // A fresh account has no session under any coordinator, so the live wrapper agrees.
        #expect(!compactRowNeedsStandardSection(account))
    }
}
