import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// R15: Compact never hides an action. An account whose setup session owns its row keeps the
/// Standard section, and so does a `.connected` session, whose payoff only that section settles.
/// The pure overload is exercised with inputs from the same helpers the card uses, so no
/// shared `SetupSessions` coordinator state is created or left behind.
@MainActor
@Suite(.sharedAppState)
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

/// CA-P13 (overturns the account-layout plan's R9 for Compact): the provider mark is drawn
/// once, in the card's header, so it travels with the header. Every piece of a split Compact
/// card repeats that header, and so its one mark; the rows draw none (render-verified at
/// `multi-7` and `multi-20` with `--account-layout compact`).
@Suite(.sharedAppState)
struct CompactCardMarkTests {
    private func entries(_ count: Int) -> [ProviderAccountEntry] {
        (0..<count).map { index in
            let account = index == 0 ? ProviderAccount.builtIn(for: .claude)
                : ProviderAccount(id: AccountID("mark-\(index)"), providerID: .claude, label: "Account \(index + 1)", isBuiltIn: false)
            return ProviderAccountEntry(account: account, snapshot: UsageSnapshot(
                providerID: .claude,
                windows: [UsageWindow(kind: .fiveHour, utilization: 20, resetSchedule: .unresolved(.absent)),
                          UsageWindow(kind: .weekly, utilization: 40, resetSchedule: .unresolved(.absent))],
                planLabel: nil, capturedAt: Date(), freshness: .live))
        }
    }

    @Test @MainActor func everyPieceOfASplitCompactCardCarriesTheHeader() {
        let slots = ProviderCardView.columnSlots(providerID: .claude, entries: entries(7), capabilityStatus: nil,
                                                 accountLayout: .compact)
        #expect(slots.count == 7)
        #expect(slots.allSatisfy { $0.fragmentHeader == Double(CompactCardHeader.height) })
    }

    @Test @MainActor func standardPiecesCarryNoHeader() {
        let slots = ProviderCardView.columnSlots(providerID: .claude, entries: entries(7), capabilityStatus: nil,
                                                 accountLayout: .standard)
        #expect(slots.allSatisfy { $0.fragmentHeader == 0 })
    }
}

/// CA-P11 (POP-10): the Compact spend card's header and row tags.
@Suite(.sharedAppState)
struct CompactSpendLayoutTests {
    @Test func theHeaderNamesThePeriodAndDirectionOnce() {
        #expect(CompactSpendLayout.headerTrailingLabel(periodLabel: "Nov", kinds: [.periodSpend, .periodSpend]) == "Nov · used")
        #expect(CompactSpendLayout.headerTrailingLabel(periodLabel: "Nov", kinds: [.balance]) == "Balance · left")
        #expect(CompactSpendLayout.headerTrailingLabel(periodLabel: "Nov", kinds: [.periodSpend, .balance]) == "Nov")
    }

    @Test func aBalanceRowSaysSoOnlyWhereTheHeaderDoesNot() {
        #expect(CompactSpendLayout.rowTag(shortBadge: nil, isLive: true, contextLabel: "Balance", kind: .balance, mixedKinds: true) == "Balance")
        #expect(CompactSpendLayout.rowTag(shortBadge: nil, isLive: true, contextLabel: "Balance", kind: .balance, mixedKinds: false) == nil)
        #expect(CompactSpendLayout.rowTag(shortBadge: nil, isLive: true, contextLabel: "Nov", kind: .periodSpend, mixedKinds: true) == nil)
        #expect(CompactSpendLayout.rowTag(shortBadge: "Rejected", isLive: false, contextLabel: "Nov", kind: .periodSpend, mixedKinds: false) == "Rejected")
    }

    /// Spend amounts take the Compact cells' numeral size, so the two read as one family on
    /// the card's trailing edge (the shared x is render-verified at `spend-states` Compact).
    @Test func theAmountMatchesTheCompactNumeral() {
        #expect(CompactSpendLayout.amountSize == 15)
    }
}
