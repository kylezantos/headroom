import Foundation
import Testing
@testable import HeadroomCore

@MainActor
@Suite struct SetupSessionCoordinatorTests {
    @Test func grokLoginRefreshesIntoLiveUsage() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .grok)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(harness.refreshCalls == [account.key])
        coordinator.receive(.live(.grok, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
    }

    /// U4 (Copilot plan): a signed-in account with no evidence yet is a `.live` snapshot
    /// with one unavailable row (KTD7), so it completes setup like any live reading.
    @Test func copilotLoginRefreshesIntoLiveUsageEvenWithNoReadingYet() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .copilot)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(harness.refreshCalls == [account.key])
        let noReading = UsageSnapshot(
            providerID: .copilot,
            windows: [UsageWindow(
                kind: CopilotProvider.window, utilization: 0, resetSchedule: .unresolved(.absent),
                freshness: .unavailable(since: Date(timeIntervalSince1970: 0)))],
            planLabel: nil, capturedAt: Date(), freshness: .live)
        coordinator.receive(noReading, for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
    }

    @Test func copilotMissingCLIEndsTheHandoffWithItsOwnOutcome() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .copilot)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        coordinator.receive(.stale(for: .copilot, reason: .providerSetup(.copilotCLIMissing)), for: account.key)

        #expect(coordinator.state(for: account.key) == .failed(.provider(.copilotCLIMissing)))
    }

    @Test func cursorLoginThenWorkspaceTrustRefreshesIntoLiveUsage() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .cursor)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        coordinator.receive(
            .stale(for: .cursor, reason: .providerSetup(.cursorTrustRequired)),
            for: account.key
        )
        #expect(coordinator.state(for: account.key) == .failed(.provider(.cursorTrustRequired)))

        coordinator.beginWorkspaceTrust(for: account)
        await settleTasks()
        // Quitting Cursor Agent after approval can return a nonzero shell status. A
        // fresh live usage result, not that exit code, settles the handoff.
        coordinator.handoffDidEnd(account.key, completion: .failed, purpose: .trust)
        coordinator.receive(.live(.cursor, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard),
            .init(key: account.key, mode: .standard, purpose: .trust),
        ])
        #expect(harness.refreshCalls == [account.key, account.key])
    }
    /// `acceptsNewStart` is the same rule `start` applies, so the app can record a launch's
    /// reason only for a start that will actually run and never over a running session.
    @Test func acceptsNewStartMatchesWhatStartDoes() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)
        harness.existingAccounts.insert(account.key)

        #expect(coordinator.acceptsNewStart(for: account.key, purpose: .trust))
        coordinator.beginWorkspaceTrust(for: account)
        #expect(coordinator.state(for: account.key) == .preparing)

        // Already preparing: refused, and nothing new is staged.
        #expect(!coordinator.acceptsNewStart(for: account.key, purpose: .trust))
        coordinator.beginWorkspaceTrust(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 1)

        // An open handoff: a second start only becomes `.blockedByOpenHandoff`.
        #expect(coordinator.hasActiveHandoff(for: account.key))
        #expect(!coordinator.acceptsNewStart(for: account.key, purpose: .trust))
        coordinator.beginWorkspaceTrust(for: account)
        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)
        #expect(harness.prepareCalls.count == 1)

        // Connected: only a reset may start again.
        coordinator.handoffDidEnd(account.key, completion: .succeeded, purpose: .trust)
        coordinator.receive(.live(.claude, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
        #expect(!coordinator.acceptsNewStart(for: account.key, purpose: .trust))
        #expect(coordinator.acceptsNewStart(for: account.key, purpose: .reset))
    }

    @Test func cursorMCPApprovalHandoffRequiresUserDecisionThenRetries() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .cursor)

        coordinator.beginCursorMCPApproval(for: account)
        await settleTasks()
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard, purpose: .approval)])
        #expect(harness.openedHandoffs == [
            .init(accountKey: account.key, mode: .standard, purpose: .approval),
        ])

        coordinator.handoffDidEnd(account.key, completion: .failed, purpose: .approval)
        coordinator.receive(.live(.cursor, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
    }

    @Test func cursorWorkspaceTrustHandoffKeepsItsPurposeAndRetriesSafely() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .cursor)

        coordinator.beginWorkspaceTrust(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard, purpose: .trust)])
        #expect(harness.openedHandoffs == [
            .init(accountKey: account.key, mode: .standard, purpose: .trust),
        ])
        #expect(harness.resetBoundaryCalls.isEmpty)

        coordinator.handoffDidEnd(account.key, completion: .failed, purpose: .trust)
        #expect(coordinator.state(for: account.key) == .verifying)
        coordinator.receive(
            .stale(for: .cursor, reason: .providerSetup(.cursorTrustRequired)),
            for: account.key
        )
        #expect(coordinator.state(for: account.key) == .failed(.provider(.cursorTrustRequired)))
    }

    @Test func duplicateClicksPrepareAndOpenExactlyOnce() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        coordinator.begin(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(harness.openCalls == [account.key])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func beginWhileWrapperIsOpenExposesRefusalThenRetriesAfterHandoffEnds() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )
        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.hasActiveHandoff(for: account.key))
        coordinator.begin(for: account, mode: .deviceCode)

        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)
        #expect(coordinator.sessionMode(for: account.key) == .standard)
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(harness.scheduler.pendingCount == 0)

        coordinator.handoffDidEnd(account.key, completion: .failed)

        #expect(!coordinator.hasActiveHandoff(for: account.key))
        #expect(coordinator.state(for: account.key) == .verifying)
        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: account.key
        )
        coordinator.begin(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard),
            .init(key: account.key, mode: .standard),
        ])
    }

    @Test func postWrapperVerificationDoesNotReportAnActiveHandoff() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.hasActiveHandoff(for: account.key))

        coordinator.handoffDidEnd(account.key)

        #expect(coordinator.state(for: account.key) == .verifying)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
    }

    @Test func cancellationDuringSuspendedPreparationNeverOpensTerminal() async {
        let harness = SetupCoordinatorHarness()
        harness.suspendPreparation = true
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .preparing)

        coordinator.cancel(account.key)
        harness.resumePreparation()
        await settleTasks()

        #expect(harness.openCalls.isEmpty)
        #expect(harness.discardCalls == [account.key])
        #expect(coordinator.state(for: account.key) == .cancelled)
    }

    @Test func forceCancelOpenHandoffClearsRefusalAndReleasesLoginSlot() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.begin(for: account)
        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)

        coordinator.forceCancel(account.key)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
        #expect(harness.scheduler.pendingCount == 0)
    }

    /// KTD6 moved Claude off the retry ladder, so the ladder's own cancellation is pinned
    /// on a provider that still runs it. The assertions are unchanged.
    @Test func forceCancelWaitingHandoffMakesPendingRetryInert() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingCount == 1)

        coordinator.forceCancel(account.key)
        harness.scheduler.fireLastIncludingCancelled()

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
        #expect(harness.refreshCalls.isEmpty)
        #expect(harness.scheduler.pendingCount == 0)
    }

    /// KTD6/R13: Stop Waiting also has to reach a *Claude* wait, under both of the policies
    /// KTD6 introduced — the exit-signalled sign-in, which arms only its timeout, and the
    /// polled interactive launch, which arms a check beside it. Neither may leave a timer
    /// behind. The test above pins the same guarantee for the ladder Codex still runs.
    @Test func forceCancelDuringAClaudeWaitCancelsEveryTimerItsPolicyArmed() async {
        for kind in [ClaudeSetupScriptKind.signIn, .interactive] {
            let harness = SetupCoordinatorHarness()
            harness.claudeScriptKind = kind
            let coordinator = harness.makeCoordinator()
            let account = ProviderAccount.builtIn(for: .claude)

            coordinator.begin(for: account)
            await settleTasks()
            #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
            #expect(coordinator.waitingPolicy(for: account.key)
                == (kind == .signIn ? .exitSignalled : .polled))
            #expect(harness.scheduler.pendingCount == (kind == .signIn ? 1 : 2))

            coordinator.forceCancel(account.key)
            harness.scheduler.fireLastIncludingCancelled()

            #expect(coordinator.state(for: account.key) == .cancelled)
            #expect(!coordinator.hasActiveHandoff(for: account.key))
            #expect(harness.refreshCalls.isEmpty)
            #expect(harness.scheduler.pendingCount == 0)
        }
    }

    @Test func forceCancelAllowsImmediateBeginForSameAccount() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.forceCancel(account.key)
        coordinator.begin(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard),
            .init(key: account.key, mode: .standard),
        ])
        #expect(harness.openCalls == [account.key, account.key])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(coordinator.hasActiveHandoff(for: account.key))
    }

    @Test func forceCancelFinalVerificationMakesLateFailuresAndStopLossInert() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(coordinator.state(for: account.key) == .verifying)

        coordinator.forceCancel(account.key)
        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)
        coordinator.receive(
            .stale(for: .claude, reason: .providerSetup(.claudeCLIMissing)),
            for: account.key
        )
        harness.scheduler.fireLastIncludingCancelled()

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func lateHandoffEndAfterForceCancelDoesNotStartVerification() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.forceCancel(account.key)
        coordinator.handoffDidEnd(account.key, completion: .failed)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(harness.refreshCalls.isEmpty)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func forceCancelCodexSlotHolderAllowsBlockedAccountToContinue() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.begin(for: second)
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.forceCancel(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()

        #expect(coordinator.state(for: first.key) == .cancelled)
        #expect(coordinator.state(for: second.key) == .waiting(attempt: 0))
        #expect(harness.openCalls == [first.key, second.key])
    }

    @Test func resetIgnoresLiveSnapshotDuringPreparationAndStillOpensHandoff() async {
        let harness = SetupCoordinatorHarness()
        harness.suspendPreparation = true
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .preparing)
        #expect(harness.openCalls.isEmpty)
        harness.resumePreparation()
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.openCalls == [account.key])
    }

    @Test func resetSettlesOnlyFromLiveResultAfterHandoffEnds() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .codex)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.receive(.live(.codex, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(coordinator.hasActiveHandoff(for: account.key))

        coordinator.handoffDidEnd(account.key, completion: .failed)
        #expect(coordinator.state(for: account.key) == .verifying)
        coordinator.receive(.live(.codex, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.resetBoundaryCalls == [account.key, account.key])
    }

    @Test func resetPurposeReachesPreparationAndRestoresAcrossActiveAndCompletedHandoffs() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard, purpose: .reset),
        ])
        #expect(harness.openedHandoffs == [
            .init(accountKey: account.key, mode: .standard, purpose: .reset),
        ])

        let restoredHarness = SetupCoordinatorHarness()
        restoredHarness.existingAccounts.insert(account.key)
        let restored = restoredHarness.makeCoordinator()
        restored.restoreActiveHandoff(account.key, mode: .deviceCode, purpose: .reset)

        #expect(restored.sessionPurpose(for: account.key) == .reset)
        #expect(restored.sessionMode(for: account.key) == .deviceCode)
        #expect(restoredHarness.resetBoundaryCalls == [account.key])

        restored.handoffDidEnd(account.key, completion: .succeeded)
        #expect(restoredHarness.resetBoundaryCalls == [account.key, account.key])
        #expect(restored.state(for: account.key) == .verifying)

        let completedHarness = SetupCoordinatorHarness()
        completedHarness.existingAccounts.insert(account.key)
        let completed = completedHarness.makeCoordinator()
        completed.handoffDidEnd(account.key, completion: .succeeded, purpose: .reset)

        #expect(completed.sessionPurpose(for: account.key) == .reset)
        #expect(completedHarness.resetBoundaryCalls == [account.key])
        #expect(completed.state(for: account.key) == .verifying)
    }

    @Test func terminalResetFailureClearsPurposeAndAllowsLaterLiveRecovery() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        harness.scheduler.fireNext()

        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
        #expect(coordinator.sessionPurpose(for: account.key) == nil)

        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
    }

    /// KTD6 made a Claude reset exit-signalled, so the ladder failure this pins is now a
    /// ladder provider's. The retained-purpose rule it asserts is provider-independent.
    @Test func retryFailureKeepsResetPurposeWhileWrapperCanStillRescueSession() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(retryDelays: [.seconds(1)])
        let account = ProviderAccount.builtIn(for: .codex)

        coordinator.beginReset(for: account)
        await settleTasks()
        harness.scheduler.fireNext()

        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
        #expect(coordinator.sessionPurpose(for: account.key) == .reset)
        coordinator.receive(.live(.codex, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))

        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        coordinator.receive(.live(.codex, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
    }

    @Test func ordinaryBeginDuringActiveResetDoesNotClearResetSettlementGuard() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.begin(for: account)
        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)
        #expect(coordinator.hasActiveHandoff(for: account.key))
    }

    @Test func resetCanStartWhileConnectedPayoffIsStillVisible() async throws {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.receive(.live(.claude, windows: []), for: account.key)
        let connectedPayoff = try #require(coordinator.connectedPayoffToken(for: account.key))

        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(harness.openCalls == [account.key])

        coordinator.beginReset(for: account)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(!coordinator.settleConnected(account.key, token: connectedPayoff))
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.resetBoundaryCalls == [account.key])
        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard),
            .init(key: account.key, mode: .standard, purpose: .reset),
        ])
        #expect(harness.openCalls == [account.key, account.key])
    }

    @Test func providerBlockedResetKeepsItsResetIntentWhenContinued() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.beginReset(for: second)
        #expect(harness.resetBoundaryCalls.isEmpty)

        coordinator.receive(.live(.codex, windows: []), for: second.key)
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(
            providerID: .codex,
            active: first.key
        ))

        coordinator.forceCancel(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()
        coordinator.receive(.live(.codex, windows: []), for: second.key)

        #expect(coordinator.state(for: second.key) == .waiting(attempt: 0))
        #expect(harness.resetBoundaryCalls == [second.key])
    }

    @Test func forceCancelResetLeavesSessionCancelledAndAllowsOrdinaryPolling() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.forceCancel(account.key)
        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
    }

    /// KTD6 moved Claude off the retry ladder; the ladder itself is unchanged and is
    /// pinned here on a provider that still runs it.
    @Test func retriesUseVirtualSchedulerAndStopAfterLive() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(retryDelays: [.seconds(1), .seconds(2)])
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.scheduler.pendingCount == 1)

        harness.scheduler.fireNext()
        #expect(harness.refreshCalls == [account.key])
        #expect(harness.scheduler.pendingCount == 1)

        coordinator.receive(.init(providerID: .codex, windows: [], planLabel: nil, capturedAt: Date(), freshness: .live), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func setupSettlesWithNoViewMounted() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.receive(.init(providerID: .codex, windows: [], planLabel: nil, capturedAt: Date(), freshness: .live), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
    }

    @Test func ordinaryLivePollingDoesNotCreateASetupSession() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )
        harness.existingAccounts.insert(account.key)

        coordinator.receive(
            .init(
                providerID: .codex,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .live
            ),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .idle)
    }

    @Test func secondCodexLoginRequiresFreshContinueActionAfterSlotFrees() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.begin(for: second)
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.cancel(first.key)
        await settleTasks()
        #expect(harness.openCalls == [first.key])

        coordinator.continueSetup(for: second)
        await settleTasks()
        #expect(harness.openCalls == [first.key])
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.handoffDidEnd(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()
        #expect(harness.openCalls == [first.key, second.key])
    }

    @Test func blockedDeviceCodeLoginKeepsItsExplicitModeWhenContinued() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.begin(for: second, mode: .deviceCode)
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.handoffDidEnd(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()

        #expect(harness.prepareCalls.last == .init(key: second.key, mode: .deviceCode))
        #expect(coordinator.sessionMode(for: second.key) == .deviceCode)
    }

    @Test func grokLoginsCanOpenConcurrentlyBecauseTheCLIUsesEphemeralCallbacks() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("grok-one"), providerID: .grok, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("grok-two"), providerID: .grok, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        coordinator.begin(for: second)
        await settleTasks()

        #expect(Set(harness.openCalls) == Set([first.key, second.key]))
        #expect(coordinator.state(for: first.key) == .waiting(attempt: 0))
        #expect(coordinator.state(for: second.key) == .waiting(attempt: 0))
    }

    @Test func openerFailureKeepsItsTypedReason() async {
        let harness = SetupCoordinatorHarness()
        harness.openResult = .failure(.pasteboardFailed)
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .failed(.pasteboardFailed))
    }

    @Test func retryExhaustionDoesNotReopenOverActiveHandoffAndExitChecksOnce() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(retryDelays: [.seconds(1)])
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fireNext()
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
        #expect(harness.refreshCalls == [account.key])

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 1)

        coordinator.handoffDidEnd(account.key)
        #expect(harness.refreshCalls == [account.key, account.key])
        coordinator.receive(.stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.provider(.codexCallbackIncomplete)))
        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 2)
    }

    @Test func finalTransientCheckAfterHandoffExitSettlesToActionableFailure() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        #expect(coordinator.state(for: account.key) == .verifying)

        coordinator.receive(.stale(for: .claude, reason: .transient("redacted")), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
    }

    @Test func successfulCodexLoginWithoutReadableFileBecomesStorageMismatch() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .failed(.provider(.codexStorageMismatch)))
    }

    @Test func unsuccessfulCodexLoginWithoutReadableFileBecomesCallbackIncomplete() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .failed)
        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .failed(.provider(.codexCallbackIncomplete)))
    }

    @Test func completedHandoffRestoredAfterRelaunchStillRunsFinalClassification() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .codex, accountID: AccountID("codex-extra"))
        harness.existingAccounts.insert(key)

        coordinator.handoffDidEnd(key, completion: .succeeded)
        #expect(coordinator.state(for: key) == .verifying)
        #expect(harness.refreshCalls == [key])

        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: key
        )
        #expect(coordinator.state(for: key) == .failed(.provider(.codexStorageMismatch)))
    }

    @Test func confirmedAbsentDuringFinalRefreshFailsImmediately() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)

        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)

        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(harness.scheduler.pendingCount == 0)
        coordinator.receive(.stale(for: .claude, reason: .transient("redacted")), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))
    }

    @Test func inconclusiveCapabilityWaitsForLiveResultBeforeStopLoss() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)

        #expect(coordinator.state(for: account.key) == .verifying)
        #expect(harness.scheduler.pendingDelays == [.seconds(100)])

        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func inconclusiveCapabilityBecomesTypedFailureAtStopLoss() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)

        harness.scheduler.fireNext()

        #expect(
            coordinator.state(for: account.key)
                == .failed(.providerCapability(.inconclusive(.shellTimeout)))
        )
    }

    @Test func confirmedAbsentFansOutOnlyAcrossMatchingProviderSessions() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("claude-one"), providerID: .claude, label: "One")
        let second = ProviderAccount(id: AccountID("claude-two"), providerID: .claude, label: "Two")
        let codex = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "Codex")

        for account in [first, second, codex] {
            coordinator.begin(for: account)
        }
        await settleTasks()
        for account in [first, second, codex] {
            coordinator.handoffDidEnd(account.key)
        }

        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)

        #expect(coordinator.state(for: first.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(coordinator.state(for: second.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(coordinator.state(for: codex.key) == .verifying)
    }

    @Test func silentFinalRefreshStopsAndCanRestartCleanly() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)

        harness.scheduler.fireNext()
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 2)
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func finalVerificationUsesSerialLaneBoundNotRetryLadderScale() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(
            retryDelays: [.seconds(3), .seconds(7), .seconds(15), .seconds(30)]
        )
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)

        #expect(harness.scheduler.pendingDelays == [.seconds(240)])
        coordinator.receive(.live(.claude, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func liveResultReconnectsAfterPriorCapabilityFailure() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)
        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))

        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func cancelledStopLossCannotSettleRemovedSession() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)
        coordinator.markRemoved(account.key)

        harness.scheduler.fireLastIncludingCancelled()

        #expect(coordinator.state(for: account.key) == .removed)
    }

    @Test func removalCancelsRetryAndPreventsLateSettlement() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.markRemoved(account.key)
        coordinator.receive(.init(providerID: .claude, windows: [], planLabel: nil, capturedAt: Date(), freshness: .live), for: account.key)

        #expect(coordinator.state(for: account.key) == .removed)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func reinstatedKeyStartsSetupAgainAfterRemoval() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.markRemoved(account.key)
        #expect(coordinator.state(for: account.key) == .removed)
        // While removed, begin is a silent no-op — the sentinel the reinstate clears.
        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.isEmpty)

        coordinator.markReinstated(account.key)
        #expect(coordinator.state(for: account.key) == .idle)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func reinstateOnlyClearsTheRemovedSentinel() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))

        coordinator.markReinstated(account.key)

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    // MARK: - KTD6 to KTD8: the Claude waiting policy, its timeout and resume

    /// KTD6: every check during a sign-in handoff would read signed-out until the CLI
    /// process exits, and the marker monitor reports that exit within 500 ms.
    @Test func exitSignalledClaudeHandoffSchedulesOnlyItsWaitingTimeout() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(coordinator.waitingPolicy(for: account.key) == .exitSignalled)
        #expect(harness.scheduler.pendingDelays == [.seconds(300)])
        #expect(harness.refreshCalls.isEmpty)
    }

    /// KTD6: a reset drives the CLI's own logout/login pair, so the stamped script kind
    /// describes shape only — the purpose is what decides the policy.
    @Test func resetHandoffIsExitSignalledWhateverScriptKindWasStaged() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .interactive
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()

        #expect(coordinator.waitingPolicy(for: account.key) == .exitSignalled)
        #expect(harness.scheduler.pendingDelays == [.seconds(300)])

        coordinator.receive(.live(.claude, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))

        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(coordinator.state(for: account.key) == .verifying)
        coordinator.receive(.live(.claude, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
    }

    /// KTD6: the polled chain is driven by landed results, never by a fixed interval —
    /// each check is a front-of-queue probe on the account's CLI lane, which a shorter
    /// interval would monopolise.
    @Test func polledClaudeHandoffSchedulesOneCheckPerLandedResult() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .interactive
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.waitingPolicy(for: account.key) == .polled)
        #expect(harness.scheduler.pendingDelays == [.seconds(300), .seconds(10)])

        harness.scheduler.fire(after: .seconds(10))
        #expect(harness.refreshCalls == [account.key])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingDelays == [.seconds(300)])

        coordinator.receive(.stale(for: .claude, reason: .transient("redacted")), for: account.key)
        #expect(harness.scheduler.pendingDelays == [.seconds(300), .seconds(10)])

        coordinator.receive(
            .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)),
            for: account.key
        )
        #expect(harness.scheduler.pendingDelays == [.seconds(300), .seconds(10)])
    }

    /// KTD6: a capability failure never reaches `receive`, so without this channel one
    /// inconclusive locator result would end polling until the timeout.
    @Test func polledClaudeHandoffRearmsFromACapabilityFailureToo() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .interactive
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fire(after: .seconds(10))
        #expect(harness.scheduler.pendingDelays == [.seconds(300)])

        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingDelays == [.seconds(300), .seconds(10)])
    }

    /// Other providers keep today's ladder and its exhaustion exactly, and the Claude
    /// timeout never joins it.
    @Test func codexHandoffKeepsItsLadderAndItsExhaustion() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(retryDelays: [.seconds(3), .seconds(7)])
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.waitingPolicy(for: account.key) == .retryLadder)
        #expect(harness.scheduler.pendingDelays == [.seconds(3)])

        harness.scheduler.fireNext()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 1))
        #expect(harness.scheduler.pendingDelays == [.seconds(7)])

        harness.scheduler.fireNext()
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
        #expect(coordinator.hasActiveHandoff(for: account.key))
    }

    /// KTD7: the timeout is its own case, because `.retryExhausted` is the state that
    /// still offers every other provider Sign In and Check Now.
    @Test func claudeWaitingTimeoutYieldsItsOwnFailureAndKeepsTheHandoffOpen() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fire(after: .seconds(300))

        #expect(coordinator.state(for: account.key) == .failed(.waitingTimedOut))
        #expect(coordinator.hasActiveHandoff(for: account.key))
        #expect(harness.refreshCalls.isEmpty)
    }

    /// R9: a sign-in that finishes after the timeout still connects with no user action.
    @Test func lateTerminalExitAfterTheTimeoutStillVerifiesAndConnects() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fire(after: .seconds(300))
        #expect(coordinator.state(for: account.key) == .failed(.waitingTimedOut))

        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(coordinator.state(for: account.key) == .verifying)

        coordinator.receive(.live(.claude, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
    }

    /// KTD7: the timer registers in `invalidateWork` and checks its generation, so an
    /// exit that lands first leaves the disarmed timeout inert.
    @Test func theWaitingTimeoutCannotFireDuringVerification() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(coordinator.state(for: account.key) == .verifying)

        harness.scheduler.fire(after: .seconds(300), includingCancelled: true)

        #expect(coordinator.state(for: account.key) == .verifying)
    }

    /// KTD8: resume never calls `start`, so the open handoff survives and the refusal
    /// state is never entered.
    @Test func resumeWaitingFromTheTimeoutReturnsToWaitingAndRearmsOneTimeout() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fire(after: .seconds(300))
        #expect(coordinator.state(for: account.key) == .failed(.waitingTimedOut))

        coordinator.resumeWaiting(for: account.key)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(coordinator.hasActiveHandoff(for: account.key))
        #expect(harness.scheduler.pendingDelays == [.seconds(300)])
        #expect(harness.prepareCalls.count == 1)
        #expect(harness.openCalls == [account.key])
    }

    @Test func resumedPolledHandoffResumesItsPolling() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .interactive
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fire(after: .seconds(10))
        harness.scheduler.fire(after: .seconds(300))
        #expect(coordinator.state(for: account.key) == .failed(.waitingTimedOut))

        coordinator.resumeWaiting(for: account.key)

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingDelays == [.seconds(300), .seconds(10)])
    }

    @Test func resumeWaitingWithNoActiveHandoffIsANoOp() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .claude, accountID: .primary)

        coordinator.resumeWaiting(for: key)
        await settleTasks()

        #expect(coordinator.state(for: key) == .idle)
        #expect(harness.scheduler.pendingCount == 0)
        #expect(harness.prepareCalls.isEmpty)
        #expect(harness.openCalls.isEmpty)
    }

    /// The refusal a second Sign In click earns is unchanged by the new entry point.
    @Test func aSecondBeginWhileWaitingStillBlocksAndOpensNothing() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)
        #expect(harness.prepareCalls.count == 1)
        #expect(harness.openCalls == [account.key])
    }

    // MARK: - KTD8/R15: a handoff restored after relaunch

    /// R15: the timeout is measured from the handoff's original start, so a wait that had
    /// already expired while Headroom was closed lands in the timeout state rather than
    /// granting the user a fresh five minutes.
    @Test func restoredHandoffOlderThanTheTimeoutLandsInTheTimeoutState() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        harness.existingAccounts.insert(key)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        coordinator.restoreActiveHandoff(
            key,
            policy: .exitSignalled,
            startedAt: now.addingTimeInterval(-400),
            now: now
        )

        #expect(coordinator.state(for: key) == .failed(.waitingTimedOut))
        #expect(coordinator.hasActiveHandoff(for: key))
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func restoredHandoffTwoMinutesOldArmsTheRemainingThreeMinutes() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        harness.existingAccounts.insert(key)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        coordinator.restoreActiveHandoff(
            key,
            policy: .exitSignalled,
            startedAt: now.addingTimeInterval(-120),
            now: now
        )

        #expect(coordinator.state(for: key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingDelays == [.seconds(180)])
    }

    /// KTD8: `setupHandoffStartedAt` returns nil for a legacy, unparseable or future-dated
    /// start. A fresh full timeout keeps that wait bounded instead of unbounded.
    @Test func restoredHandoffWithNoReadableStartArmsAFreshTimeout() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .claude, accountID: .primary)
        harness.existingAccounts.insert(key)

        coordinator.restoreActiveHandoff(key, policy: .exitSignalled, startedAt: nil)

        #expect(coordinator.state(for: key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingDelays == [.seconds(300)])
    }

    /// KTD8: the policy comes from the record saved when the handoff opened. Both cases
    /// pass a purpose whose no-record fallback is the opposite answer, so a restore that
    /// re-derived the policy instead of reading it would fail here.
    @Test func restoredHandoffFollowsItsSavedPolicyNotTheFallback() {
        let polledHarness = SetupCoordinatorHarness()
        let polled = polledHarness.makeCoordinator()
        let setupKey = AccountKey(providerID: .claude, accountID: .primary)
        polledHarness.existingAccounts.insert(setupKey)

        polled.restoreActiveHandoff(setupKey, purpose: .setup, policy: .polled, startedAt: nil)

        #expect(polled.waitingPolicy(for: setupKey) == .polled)
        #expect(polledHarness.scheduler.pendingDelays == [.seconds(300), .seconds(10)])

        let exitHarness = SetupCoordinatorHarness()
        let exitSignalled = exitHarness.makeCoordinator()
        let trustKey = AccountKey(providerID: .claude, accountID: AccountID("claude-extra"))
        exitHarness.existingAccounts.insert(trustKey)

        exitSignalled.restoreActiveHandoff(
            trustKey,
            purpose: .trust,
            policy: .exitSignalled,
            startedAt: nil
        )

        #expect(exitSignalled.waitingPolicy(for: trustKey) == .exitSignalled)
        #expect(exitHarness.scheduler.pendingDelays == [.seconds(300)])
    }

    /// KTD8: a handoff opened by a build that saved no record falls back by purpose.
    @Test func restoredHandoffWithNoRecordFallsBackByPurpose() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let setupKey = AccountKey(providerID: .claude, accountID: .primary)
        let trustKey = AccountKey(providerID: .claude, accountID: AccountID("claude-extra"))
        harness.existingAccounts.formUnion([setupKey, trustKey])

        coordinator.restoreActiveHandoff(setupKey, purpose: .setup)
        coordinator.restoreActiveHandoff(trustKey, purpose: .trust)

        #expect(coordinator.waitingPolicy(for: setupKey) == .exitSignalled)
        #expect(coordinator.waitingPolicy(for: trustKey) == .polled)
    }

    /// Other providers keep today's restore exactly: no ladder is resumed and no timeout
    /// is armed for a handoff that outlived the launch which opened it.
    @Test func restoredCodexHandoffSchedulesNothingAsBefore() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .codex, accountID: .primary)
        harness.existingAccounts.insert(key)

        coordinator.restoreActiveHandoff(key)

        #expect(coordinator.state(for: key) == .waiting(attempt: 0))
        #expect(coordinator.waitingPolicy(for: key) == .retryLadder)
        #expect(harness.scheduler.pendingCount == 0)
    }

    // MARK: - KTD9/KTD10: the exit boundary and the closed-early failure

    /// R12/KTD9: a check already in flight when Terminal exits must not settle the
    /// verification, so the boundary is crossed before the refresh that follows it.
    @Test func handoffEndCrossesTheGenerationBoundaryBeforeItsRefresh() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.handoffBoundaryCalls.isEmpty)

        coordinator.handoffDidEnd(account.key, completion: .succeeded)

        #expect(harness.handoffBoundaryCalls == [account.key])
        #expect(harness.callOrder == ["boundary", "refresh"])
    }

    /// KTD9 applies to every purpose, and a reset still crosses its own boundary too.
    @Test func everyPurposeCrossesTheBoundaryAtHandoffEnd() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let claude = ProviderAccount.builtIn(for: .claude)
        let codex = ProviderAccount.builtIn(for: .codex)

        coordinator.beginReset(for: claude)
        await settleTasks()
        coordinator.handoffDidEnd(claude.key, completion: .succeeded)
        coordinator.begin(for: codex)
        await settleTasks()
        coordinator.handoffDidEnd(codex.key, completion: .failed)

        #expect(harness.handoffBoundaryCalls == [claude.key, codex.key])
        #expect(harness.resetBoundaryCalls == [claude.key, claude.key])
    }

    /// AE5/KTD10: `auth login`'s status on an abandoned sign-in is unobserved, so the
    /// message cannot depend on it — every completion reads the same.
    @Test(arguments: [SetupHandoffCompletion.succeeded, .failed, .unknown])
    func finalCheckStillSignedOutIsClosedBeforeSignIn(_ completion: SetupHandoffCompletion) async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: completion)
        #expect(coordinator.finalVerificationCompletion(for: account.key) == completion)

        coordinator.receive(
            .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired)),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .failed(.closedBeforeSignIn))
        #expect(coordinator.finalVerificationCompletion(for: account.key) == nil)
    }

    @Test func forceCancelDuringVerificationClearsThePendingFinalRefresh() async {
        let harness = SetupCoordinatorHarness()
        harness.claudeScriptKind = .signIn
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(coordinator.state(for: account.key) == .verifying)
        #expect(coordinator.finalVerificationCompletion(for: account.key) == .succeeded)

        coordinator.forceCancel(account.key)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(coordinator.finalVerificationCompletion(for: account.key) == nil)
        #expect(coordinator.waitingPolicy(for: account.key) == nil)
        #expect(harness.scheduler.pendingCount == 0)
    }

    private func settleTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class SetupCoordinatorHarness {
    let scheduler = ManualSetupScheduler()
    struct PrepareCall: Equatable {
        let key: AccountKey
        let mode: SetupHandoffMode
        let purpose: SetupHandoffPurpose

        init(
            key: AccountKey,
            mode: SetupHandoffMode,
            purpose: SetupHandoffPurpose = .setup
        ) {
            self.key = key
            self.mode = mode
            self.purpose = purpose
        }
    }

    var prepareCalls: [PrepareCall] = []
    var openCalls: [AccountKey] = []
    var openedHandoffs: [PreparedSetupHandoff] = []
    var discardCalls: [AccountKey] = []
    var refreshCalls: [AccountKey] = []
    var resetBoundaryCalls: [AccountKey] = []
    /// KTD9 (2026-09-19 sign-in plan): the generation boundary crossed when Terminal exits.
    var handoffBoundaryCalls: [AccountKey] = []
    /// KTD9: the boundary has to be crossed before the refresh it guards, so the two
    /// callbacks share one ordered log.
    var callOrder: [String] = []
    var existingAccounts: Set<AccountKey> = []
    var suspendPreparation = false
    var openResult: SetupOpenResult = .success(())
    /// KTD1/KTD6: what staging stamped on the handoff, which is what the waiting policy reads.
    var claudeScriptKind: ClaudeSetupScriptKind?
    private var preparationContinuation: CheckedContinuation<SetupPreparationResult, Never>?

    func makeCoordinator(
        retryDelays: [Duration] = [.seconds(1)],
        verificationStopLoss: Duration = .seconds(240),
        waitingTimeout: Duration = .seconds(300),
        polledCheckDelay: Duration = .seconds(10)
    ) -> SetupSessionCoordinator {
        SetupSessionCoordinator(
            scheduler: scheduler,
            retryDelays: retryDelays,
            verificationStopLoss: verificationStopLoss,
            waitingTimeout: waitingTimeout,
            polledCheckDelay: polledCheckDelay,
            prepare: { [weak self] account, mode, purpose in
                guard let self else { return .failure(.stagingFailed) }
                self.prepareCalls.append(.init(key: account.key, mode: mode, purpose: purpose))
                self.existingAccounts.insert(account.key)
                if self.suspendPreparation {
                    return await withCheckedContinuation { self.preparationContinuation = $0 }
                }
                return .success(PreparedSetupHandoff(
                    accountKey: account.key,
                    mode: mode,
                    purpose: purpose,
                    claudeScriptKind: self.claudeScriptKind
                ))
            },
            open: { [weak self] handoff in
                self?.openCalls.append(handoff.accountKey)
                self?.openedHandoffs.append(handoff)
                return self?.openResult ?? .failure(.stagingFailed)
            },
            discard: { [weak self] handoff in self?.discardCalls.append(handoff.accountKey) },
            accountExists: { [weak self] key in self?.existingAccounts.contains(key) == true },
            requestRefresh: { [weak self] key in
                self?.refreshCalls.append(key)
                self?.callOrder.append("refresh")
            },
            resetBoundary: { [weak self] key in self?.resetBoundaryCalls.append(key) },
            handoffBoundary: { [weak self] key in
                self?.handoffBoundaryCalls.append(key)
                self?.callOrder.append("boundary")
            }
        )
    }

    func resumePreparation() {
        preparationContinuation?.resume(returning: .success(PreparedSetupHandoff(
            accountKey: prepareCalls.last?.key ?? AccountKey(providerID: .claude, accountID: .primary),
            mode: prepareCalls.last?.mode ?? .standard,
            purpose: prepareCalls.last?.purpose ?? .setup,
            claudeScriptKind: claudeScriptKind
        )))
        preparationContinuation = nil
    }
}

@MainActor
private final class ManualSetupScheduler: SetupRetryScheduling {
    private final class Entry: SetupRetryCancellation {
        var isCancelled = false
        let delay: Duration
        let operation: @MainActor @Sendable () -> Void
        init(delay: Duration, operation: @escaping @MainActor @Sendable () -> Void) {
            self.delay = delay
            self.operation = operation
        }
        func cancel() { isCancelled = true }
    }

    private var entries: [Entry] = []
    var pendingCount: Int { entries.filter { !$0.isCancelled }.count }
    var pendingDelays: [Duration] { entries.filter { !$0.isCancelled }.map(\.delay) }

    func schedule(after delay: Duration, operation: @escaping @MainActor @Sendable () -> Void) -> any SetupRetryCancellation {
        let entry = Entry(delay: delay, operation: operation)
        entries.append(entry)
        return entry
    }

    func fireNext() {
        guard let index = entries.firstIndex(where: { !$0.isCancelled }) else { return }
        let entry = entries.remove(at: index)
        entry.operation()
    }

    /// KTD6/KTD7: the 5-minute waiting timeout sits beside the polled check, so a test
    /// names the entry it drives instead of taking whichever happened to be scheduled
    /// first. `includingCancelled` drives an entry the coordinator already disarmed, which
    /// is how a timer that must no longer fire is proven inert.
    @discardableResult
    func fire(after delay: Duration, includingCancelled: Bool = false) -> Bool {
        guard let index = entries.firstIndex(where: {
            $0.delay == delay && (includingCancelled || !$0.isCancelled)
        }) else { return false }
        let entry = entries.remove(at: index)
        entry.operation()
        return true
    }

    func fireLastIncludingCancelled() {
        guard !entries.isEmpty else { return }
        entries.removeLast().operation()
    }
}
