import Foundation
import Testing
import HeadroomCore
@testable import Headroom

@MainActor
@Suite(.serialized)
struct LoadingDemoTests {
    private func controller(loading: Bool = true) -> LoadingDemoController {
        LoadingDemoController(loading: loading,
            clock: LoadingDemoClock(pinned: Date(timeIntervalSince1970: 2_000_000_000)),
            automaticCompletion: false, preparationDelay: .zero, waitingDelay: .zero,
            probeDelay: .zero, spendDelay: .zero)
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Controlled demo checkpoint was not reached")
        throw DemoTestFailure.checkpoint
    }

    @Test func typedSetupCannotBecomeConnectedBeforeActualHandoffCompletionForEveryProvider() async throws {
        for id in DemoFixture.registeredProviderOrder {
            let owner = controller()
            let store = AppComposition.demoMultiAccountStore(scenario: .loading, controller: owner)
            owner.configure(store: store)
            let coordinator = try #require(owner.coordinator)
            await store.refreshAll()
            // Setup here is a separate interaction after the initial refresh's retained hold.
            owner.clock.set(owner.clock.now().addingTimeInterval(1))
            let account = try #require(store.primaryAccount(for: id))
            await owner.preparation.hold()
            SetupSessions.resetSetup(for: account)
            #expect(SetupSessions.state(for: account) == .preparing)
            try await waitUntil { await owner.preparation.waiterCount == 1 }
            await owner.preparation.release()
            try await waitUntil { SetupSessions.state(for: account) == .waiting(attempt: 0) }
            #expect(owner.accountStorage.activeHandoffCount == 1)
            store.refreshAccountNow(account.key, origin: .setupCheck)
            await store.waitForAccountProbesToFinish()
            #expect(SetupSessions.state(for: account) == .waiting(attempt: 0))
            #expect(store.snapshot(for: account.key).freshness != .live)
            let checkpoint = await owner.sources.checkpoint(for: account.key)
            await checkpoint.hold()
            await owner.completeHandoff(account.key)
            #expect(SetupSessions.state(for: account) == .verifying)
            try await waitUntil { await checkpoint.waiterCount == 1 }
            #expect(store.userRefreshRun?.entries[account.key]?.origin == .setupCheck)
            #expect(store.accountActionCheckingKeys.isEmpty)
            await checkpoint.release()
            await store.waitForAccountProbesToFinish()
            #expect(SetupSessions.state(for: account) == .connected)
            #expect(store.snapshot(for: account.key).freshness == .live)
            let claim = try #require(SetupSessions.claimConnectedPayoff(for: account))
            SetupSessions.settle(for: account, connectedPayoffClaim: claim)
            #expect(SetupSessions.state(for: account) == .idle)
            await owner.shutdown()
            #expect(!SetupSessions.hasDemoBoundary(coordinator))
            #expect(owner.ownedTaskCount == 0)
            #expect(await owner.sources.waiterCount() == 0)
            #expect(owner.accountStorage.activeHandoffCount == 0)
            #expect(SetupSessions.outstandingScriptCount == 0)
            #expect(SetupSessions.outstandingCompletionTaskCount == 0)
        }
    }

    @Test func UIAddRemoveStopTrackingAndStopWaitingUseOnlyInertBoundaries() async throws {
        let owner = controller(loading: false)
        let store = AppComposition.demoMultiAccountStore(scenario: .multiProviders, controller: owner)
        owner.configure(store: store)
        await store.refreshAll()
        for id in [ProviderID.claude, .codex, .grok] {
            let account = try #require(AccountsSettingsInteractions.addAccount(for: id, to: store,
                openSetup: { SetupSessions.openSetup(for: $0, onRetry: {}) }))
            try await waitUntil { SetupSessions.state(for: account) == .waiting(attempt: 0) }
            await store.waitForAccountProbesToFinish()
            #expect(store.snapshot(for: account.key).freshness != .live)
            #expect(await AccountsSettingsInteractions.removeAccount(account, from: store) == .setupActive)
            AccountsSettingsInteractions.stopWaiting(for: account, in: store)
            #expect(SetupSessions.state(for: account) == .cancelled)
            #expect(await AccountsSettingsInteractions.removeAccount(account, from: store) == .removed)
            let second = try #require(AccountsSettingsInteractions.addAccount(for: id, to: store,
                openSetup: { SetupSessions.openSetup(for: $0, onRetry: {}) }))
            try await waitUntil { SetupSessions.state(for: second) == .waiting(attempt: 0) }
            AccountsSettingsInteractions.stopWaiting(for: second, in: store)
            let builtIn = try #require(store.accounts(for: id).first(where: { $0.isBuiltIn }))
            #expect(await AccountsSettingsInteractions.removeAccount(builtIn, from: store) == .removed)
            #expect(store.isBuiltInTrackingStopped(for: id))
        }
        #expect(owner.cancellationKeys.count == 6)
        #expect(owner.preparedKeys.count == 6)
        #expect(owner.openedKeys.count == 6)
        #expect(SetupSessions.outstandingScriptCount == 0)
        #expect(SetupSessions.outstandingCompletionTaskCount == 0)
        await owner.shutdown()
        #expect(owner.ownedTaskCount == 0)
        #expect(owner.accountStorage.activeHandoffCount == 0)
    }

    @Test func stopWaitingDuringPreparationAndTeardownReleaseHeldRealRequests() async throws {
        let owner = controller()
        let store = AppComposition.demoMultiAccountStore(scenario: .loading, controller: owner)
        owner.configure(store: store)
        await owner.preparation.hold()
        let account = try #require(AccountsSettingsInteractions.addAccount(for: .grok, to: store,
            openSetup: { SetupSessions.openSetup(for: $0, onRetry: {}) }))
        try await waitUntil { await owner.preparation.waiterCount == 1 }
        AccountsSettingsInteractions.stopWaiting(for: account, in: store)
        try await waitUntil { await owner.preparation.waiterCount == 0 }
        #expect(SetupSessions.state(for: account) == .cancelled)
        #expect(owner.openedKeys.isEmpty)
        let pending = try #require(store.accounts(for: .claude).first(where: { $0.id == AccountID("loading-pending") }))
        let checkpoint = await owner.sources.checkpoint(for: pending.key)
        await checkpoint.hold()
        owner.refresh()
        try await waitUntil { await checkpoint.waiterCount == 1 }
        #expect(store.probingAccounts.contains(pending.key))
        #expect(store.snapshot(for: pending.key).freshness == .pending)
        await owner.shutdown()
        #expect(await owner.sources.waiterCount() == 0)
        #expect(owner.ownedTaskCount == 0)
        #expect(!store.isRefreshing)
        #expect(store.probingAccounts.isEmpty)
        #expect(SetupSessionActivity.shared.waitingSince(for: account.key) == nil)
        #expect(SetupSessionActivity.shared.openedAt(for: account.key) == nil)
        #expect(SetupSessions.outstandingScriptCount == 0)
        #expect(SetupSessions.outstandingCompletionTaskCount == 0)
    }

    @Test func actualDemoSettingsDependencyFactoriesBypassDiskCapableSpies() async throws {
        let spy = DemoDependencySpy()
        let credentials = AppComposition.makeSettingsCredentialStore(isDemo: true, codexReader: spy, apiKeyStore: spy)
        _ = await credentials.codexSession()
        for id in APIKeyProvider.allCases {
            _ = await credentials.apiKey(for: id)
            _ = await credentials.saveAPIKey("demo-placeholder", for: id)
            _ = await credentials.deleteAPIKey(for: id)
        }
        let detector = AppComposition.makeSettingsDuplicateDetector(isDemo: true, readIdentity: { _ in
            spy.noteRead()
            return AccountIdentity.claude(accountUUID: "11111111-2222-3333-4444-555555555555", organizationUUID: nil)
        })
        #expect(detector.duplicateLabels(for: [.builtIn(for: .claude)]).isEmpty)
        #expect(spy.calls == 0)
        #expect(AppComposition.settingsLaunchControl is DemoLaunchAtLogin)
        try AppComposition.settingsLaunchControl.setEnabled(true)
        #expect(AppComposition.settingsLaunchControl.isEnabled)
        try AppComposition.settingsLaunchControl.setEnabled(false)
    }

    /// Default-login plan U11: a demo gets the in-memory record store and never touches
    /// `defaultLoginRecords.v1`; a real launch gets the UserDefaults store over the suite it
    /// is handed.
    @Test func demoRecordStoreIsInMemoryAndARealLaunchWritesItsDefaults() throws {
        let suite = "headroom.tests.default-login-records.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "defaultLoginRecords.v1"
        let payload = Data("records".utf8)

        let demo = AppComposition.makeDefaultLoginRecordStore(isDemo: true, defaults: defaults)
        #expect(demo is DemoDefaultLoginRecordStore)
        demo.write(payload)
        #expect(defaults.data(forKey: key) == nil)

        let real = AppComposition.makeDefaultLoginRecordStore(isDemo: false, defaults: defaults)
        #expect(real is DefaultLoginRecordStore)
        real.write(payload)
        #expect(defaults.data(forKey: key) == payload)
        #expect(real.read() == payload)
    }
}

private enum DemoTestFailure: Error { case checkpoint }

private final class DemoDependencySpy: CodexAuthReading, APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func noteRead() { lock.withLock { count += 1 } }
    func readCodexCredential() throws -> CodexCredential { noteRead(); throw CredentialError.notLoggedIn }
    func readAPIKey(for provider: APIKeyProvider) throws -> String { noteRead(); throw CredentialError.notLoggedIn }
    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws { noteRead() }
    func deleteAPIKey(for provider: APIKeyProvider) throws { noteRead() }
}
