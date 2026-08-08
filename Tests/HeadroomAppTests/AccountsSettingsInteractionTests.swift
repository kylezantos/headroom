import Foundation
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

@MainActor
@Suite(.serialized)
struct AccountsSettingsInteractionTests {
    @Test func productionProviderProvisionsBuiltInClaudeWorkspaceBeforePolling() {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-provider-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let account = ProviderAccount.builtIn(for: .claude)

        _ = AppComposition.provider(
            for: account,
            credentials: CredentialStore(),
            builtInClaudeWorkspace: workspace
        )

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func guidedSetupProvisionsBuiltInClaudeWorkspaceBeforeWritingScript() async {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-setup-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let result = await SetupSessions.prepareHandoff(
            for: .builtIn(for: .claude),
            mode: .standard,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true")
        )

        guard case .success(let handoff) = result else {
            Issue.record("Expected setup preparation to succeed from an absent workspace")
            return
        }
        await SetupSessions.discardPreparedHandoff(handoff)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func guidedSetupKeepsInconclusiveClaudeDiscoveryRetryable() async {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-setup-inconclusive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = await SetupSessions.prepareHandoff(
            for: .builtIn(for: .claude),
            mode: .standard,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(location: .inconclusive(.shellTimeout))
        )

        #expect(result == .failure(.providerCapability(.inconclusive(.shellTimeout))))
    }

    @Test func guidedSetupForcesFreshClaudeDiscoveryBeforePreparingScript() async {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-setup-forced-discovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let locator = RecordingExecutableLocator(location: .available(path: "/usr/bin/true", source: .loginShell))

        let result = await SetupSessions.prepareHandoff(
            for: .builtIn(for: .claude),
            mode: .standard,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: locator
        )

        guard case .success(let handoff) = result else {
            Issue.record("Expected setup preparation to succeed")
            return
        }
        await SetupSessions.discardPreparedHandoff(handoff)
        #expect(await locator.forceRefreshes == [true])
    }

    @Test func addFlowReachesPreparingWaitingAndLiveForEachProviderWithoutMountedViews() async {
        for providerID in [ProviderID.claude, .codex] {
            let fixture = makeFixture()
            defer { fixture.cleanup() }
            let harness = AppSetupHarness(store: fixture.store)
            let coordinator = harness.makeCoordinator()

            guard let account = AccountsSettingsInteractions.addAccount(
                for: providerID,
                to: fixture.store,
                openSetup: { coordinator.begin(for: $0) }
            ) else {
                Issue.record("Expected an additional \(providerID.raw) account")
                continue
            }

            #expect(coordinator.state(for: account.key) == .preparing)
            await settleTasks()
            #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
            #expect(harness.preparedKeys == [account.key])
            #expect(harness.openedKeys == [account.key])

            coordinator.receive(
                .init(
                    providerID: providerID,
                    windows: [],
                    planLabel: nil,
                    capturedAt: Date(),
                    freshness: .live
                ),
                for: account.key
            )
            #expect(coordinator.state(for: account.key) == .connected)

            let builtIn = fixture.store.accounts(for: providerID).first(where: \.isBuiltIn)!
            #expect(coordinator.state(for: builtIn.key) == .idle)
        }
    }

    @Test func addOpensOnlyTheCreatedAccountAndHonorsTheProviderCap() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var opened: [AccountKey] = []

        for _ in 0..<4 {
            let added = AccountsSettingsInteractions.addAccount(
                for: .claude,
                to: fixture.store,
                openSetup: { opened.append($0.key) }
            )
            #expect(added != nil)
        }

        #expect(fixture.store.accounts(for: .claude).count == AccountRegistry.maxPerProvider)
        #expect(Set(opened).count == 4)
        #expect(AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { opened.append($0.key) }
        ) == nil)
        #expect(opened.count == 4)
    }

    @Test func renameCommitsTrimmedFocusLossDraftAndRejectsBlankDraft() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        guard let account = AccountsSettingsInteractions.addAccount(
            for: .codex,
            to: fixture.store,
            openSetup: { _ in }
        ) else {
            Issue.record("Expected an additional Codex account")
            return
        }

        #expect(AccountsSettingsInteractions.commitLabel(
            "  Work Account \n",
            for: account,
            in: fixture.store
        ))
        #expect(fixture.store.accounts(for: .codex).first(where: { $0.key == account.key })?.label == "Work Account")

        let renamed = fixture.store.accounts(for: .codex).first(where: { $0.key == account.key })!
        #expect(!AccountsSettingsInteractions.commitLabel("   ", for: renamed, in: fixture.store))
        #expect(fixture.store.accounts(for: .codex).first(where: { $0.key == account.key })?.label == "Work Account")
    }

    @Test func removalFailureKeepsTheSelectedRowAndRetryRemovesOnlyThatAccount() async {
        let storage = InteractionStorage(removals: [.failure(.removeFailed), .success(())])
        let fixture = makeFixture(storage: storage)
        defer { fixture.cleanup() }
        guard let account = AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { _ in }
        ) else {
            Issue.record("Expected an additional Claude account")
            return
        }

        #expect(await AccountsSettingsInteractions.removeAccount(account, from: fixture.store) == .failed)
        #expect(fixture.store.accounts(for: .claude).contains(where: { $0.key == account.key }))
        #expect(fixture.store.accountRemovalStates[account.key] == .failed)

        #expect(await AccountsSettingsInteractions.removeAccount(account, from: fixture.store) == .removed)
        #expect(!fixture.store.accounts(for: .claude).contains(where: { $0.key == account.key }))
        #expect(fixture.store.accounts(for: .claude).contains(where: { $0.isBuiltIn }))
        #expect(storage.removedKeys == [account.key, account.key])
    }

    @Test func everyRecoveryActionHasOneAppBoundaryRoute() {
        let expected: [(SetupRecoveryAction, SetupSessions.RecoveryRoute)] = [
            (.installClaudeCLI, .documentation(URL(string: "https://docs.anthropic.com/en/docs/claude-code/getting-started")!)),
            (.copyManualCommand, .copyManualCommand(.standard)),
            (.openClaudeSetup, .setup(.standard)),
            (.installCodexCLI, .documentation(URL(string: "https://developers.openai.com/codex/cli/")!)),
            (.connectCodex, .setup(.standard)),
            (.connectCodexDeviceCode, .setup(.deviceCode)),
            (.reconnectCodex, .setup(.standard)),
            (.showPrivacyGuidance, .privacyGuidance(URL(string: "https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac")!)),
            (.resolveCodexStorage, .setup(.standard)),
            (.checkNow, .checkNow),
        ]

        for (action, route) in expected {
            #expect(SetupSessions.recoveryRoute(for: action) == route)
        }
    }

    @Test func checkNowForcesClaudeDiscoveryBeforeRefreshingOnlyTheSelectedAccount() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let locator = RecordingExecutableLocator(location: .confirmedAbsent)
        SetupSessions.configure(store: fixture.store, claudeExecutableLocator: locator)
        let accounts = fixture.store.accounts(for: .claude)
        guard let selected = AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { _ in }
        ) else {
            Issue.record("Expected an additional Claude account")
            return
        }
        var refreshed: [AccountKey] = []
        await locator.setLocation(.available(path: "/installed/claude", source: .loginShell))

        SetupSessions.performRecovery(
            .checkNow,
            for: selected,
            onRetry: { refreshed.append(selected.key) }
        )

        while refreshed.isEmpty { await Task.yield() }

        #expect(refreshed == [selected.key])
        #expect(!accounts.contains(where: { refreshed.contains($0.key) }))
        #expect(await locator.forceRefreshes == [true])
    }

    private func makeFixture(
        storage: InteractionStorage = InteractionStorage()
    ) -> InteractionFixture {
        let suiteName = "co.zantos.headroom.app-interactions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let registry = AccountRegistry(defaults: defaults)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: storage,
            providerFactory: { account in
                DemoUsageProvider(
                    id: account.providerID,
                    displayName: account.providerID == .claude ? "Claude" : "Codex",
                    snapshot: .pending(for: account.providerID),
                    accountID: account.id
                )
            }
        )
        return InteractionFixture(store: store, suiteName: suiteName)
    }

    private func settleTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private struct FixedExecutableLocator: CLIExecutableLocating {
    let location: CLIExecutableLocation

    init(path: String) {
        self.location = .available(path: path, source: .memoryHint)
    }

    init(location: CLIExecutableLocation) {
        self.location = location
    }

    func locate(forceRefresh: Bool) async -> CLIExecutableLocation {
        location
    }

    func invalidate(path: String, reason: CLIExecutableInvalidationReason) async {}
}

private actor RecordingExecutableLocator: CLIExecutableLocating {
    private var location: CLIExecutableLocation
    private(set) var forceRefreshes: [Bool] = []

    init(location: CLIExecutableLocation) { self.location = location }

    func locate(forceRefresh: Bool) async -> CLIExecutableLocation {
        forceRefreshes.append(forceRefresh)
        return location
    }

    func invalidate(path: String, reason: CLIExecutableInvalidationReason) async {}

    func setLocation(_ location: CLIExecutableLocation) {
        self.location = location
    }
}

@MainActor
private struct InteractionFixture {
    let store: UsageStore
    let suiteName: String

    func cleanup() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}

private final class InteractionStorage: AccountStorageManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var removals: [Result<Void, AccountStorageFailure>]
    private var _removedKeys: [AccountKey] = []

    init(removals: [Result<Void, AccountStorageFailure>] = []) {
        self.removals = removals
    }

    var removedKeys: [AccountKey] { lock.withLock { _removedKeys } }

    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> {
        .success(())
    }

    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool { false }

    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> {
        lock.withLock {
            _removedKeys.append(account.key)
            return removals.isEmpty ? .success(()) : removals.removeFirst()
        }
    }
}

@MainActor
private final class AppSetupHarness {
    let store: UsageStore
    var preparedKeys: [AccountKey] = []
    var openedKeys: [AccountKey] = []
    var refreshedKeys: [AccountKey] = []

    init(store: UsageStore) {
        self.store = store
    }

    func makeCoordinator() -> SetupSessionCoordinator {
        SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { [weak self] account, mode in
                self?.preparedKeys.append(account.key)
                await Task.yield()
                return .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { [weak self] handoff in
                self?.openedKeys.append(handoff.accountKey)
                return .success(())
            },
            accountExists: { [weak self] key in
                self?.store.accounts(for: key.providerID).contains(where: { $0.key == key }) == true
            },
            requestRefresh: { [weak self] key in
                self?.refreshedKeys.append(key)
            }
        )
    }
}

/// Pins the P1 "grey dashed circle" regression: every registered subscription provider
/// must resolve a real brand mark + accent + non-fallback symbol through `ProviderStyle`,
/// in both color schemes, rather than hitting the `default:` identity arm.
@Suite struct ProviderStyleIdentityTests {
    @Test func everyRegisteredProviderHasABrandIdentity() {
        for id in [ProviderID.claude, .codex, .grok, .cursor] {
            #expect(ProviderStyle.svgResourceName(for: id, scheme: .light) != nil, "\(id.raw) light mark")
            #expect(ProviderStyle.svgResourceName(for: id, scheme: .dark) != nil, "\(id.raw) dark mark")
            #expect(ProviderStyle.accent(for: id) != Color.secondary, "\(id.raw) accent")
            #expect(ProviderStyle.symbol(for: id) != "circle.dashed", "\(id.raw) symbol")
        }
    }

    @Test func monochromeProvidersSelectSchemeSpecificMarks() {
        #expect(ProviderStyle.svgResourceName(for: .grok, scheme: .light) == "grok-light")
        #expect(ProviderStyle.svgResourceName(for: .grok, scheme: .dark) == "grok-dark")
        #expect(ProviderStyle.svgResourceName(for: .cursor, scheme: .light) == "cursor-light")
        #expect(ProviderStyle.svgResourceName(for: .cursor, scheme: .dark) == "cursor-dark")
    }
}

@Suite struct ProviderCardCapabilityTests {
    @MainActor @Test func activeSetupSessionTakesPrecedenceOverCapabilityRecovery() {
        #expect(ProviderCardView.capabilityRecoveryPresentation(
            state: .inconclusive(.shellTimeout),
            hasActiveSetupSession: false
        ) != nil)
        #expect(ProviderCardView.capabilityRecoveryPresentation(
            state: .inconclusive(.shellTimeout),
            hasActiveSetupSession: true
        ) == nil)
        #expect(ProviderCardView.capabilityRecoveryPresentation(
            state: .available,
            hasActiveSetupSession: false
        ) == nil)
    }
}
