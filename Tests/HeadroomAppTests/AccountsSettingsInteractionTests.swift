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
            (.installGrokCLI, .documentation(URL(string: "https://x.ai/news/grok-build")!)),
            (.connectGrok, .setup(.standard)),
            (.connectGrokDeviceCode, .setup(.deviceCode)),
            (.reconnectGrok, .setup(.standard)),
            (.installCursorAgent, .documentation(URL(string: "https://docs.cursor.com/en/cli/installation")!)),
            (.connectCursor, .setup(.standard)),
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

    @Test func providerCapabilityRecoveryTargetsAndRefreshesPrimaryOnly() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let extra = AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { _ in }
        )
        var performedFor: [AccountKey] = []
        var refreshed: [AccountKey] = []

        let routed = AccountsSettingsInteractions.performCapabilityRecovery(
            .checkNow,
            for: .claude,
            in: fixture.store,
            perform: { action, account, retry in
                #expect(SetupSessions.recoveryRoute(for: action) == .checkNow)
                performedFor.append(account.key)
                retry()
            },
            refresh: { refreshed.append($0) }
        )

        let primary = AccountKey(providerID: .claude, accountID: .primary)
        #expect(routed)
        #expect(performedFor == [primary])
        #expect(refreshed == [primary])
        #expect(extra?.key != primary)
    }

    @Test func inconclusiveCapabilityOffersBothProviderScopedSettingsActions() {
        let presentation = capabilityRecoveryPresentation(
            state: .inconclusive(.shellTimeout),
            hasActiveSetupSession: false
        )

        #expect(presentation?.recovery.primaryLabel == "Check Again")
        #expect(presentation?.recovery.primaryAction == .checkNow)
        #expect(presentation?.recovery.secondaryLabel == "Open Guided Setup")
        #expect(presentation?.recovery.secondaryAction == .openClaudeSetup)
    }

    @Test func codexDeviceCodeIsAnAccountScopedSecondarySettingsAction() {
        let account = ProviderAccount(
            id: AccountID("codex-work"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )
        let actions = AccountsSettingsInteractions.recoveryRowActions(
            snapshot: .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            account: account
        )

        #expect(actions?.usesSecondLine == true)
        #expect(actions?.secondaryLabel == "Use Device Code")
        #expect(actions?.secondaryAccessibilityLabel == "Use Device Code for Work")
        #expect(actions?.secondaryAction == .connectCodexDeviceCode)
        #expect(actions?.secondaryAction.map(SetupSessions.recoveryRoute(for:)) == .setup(.deviceCode))
    }

    @Test func grokDeviceCodeSettingsActionsLaunchConcurrentAccountBoundSessions() async throws {
        let accountsBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-grok-settings-device-code-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: accountsBase) }
        let accounts = [
            ProviderAccount(id: AccountID("grok-personal"), providerID: .grok, label: "Personal", isBuiltIn: false),
            ProviderAccount(id: AccountID("grok-work"), providerID: .grok, label: "Work", isBuiltIn: false),
        ]
        let harness = GrokDeviceCodeSetupHarness(accounts: accounts, accountsBase: accountsBase)
        let coordinator = harness.makeCoordinator()

        for account in accounts {
            let actions = AccountsSettingsInteractions.recoveryRowActions(
                snapshot: .stale(for: .grok, reason: .providerSetup(.grokAuthAbsent)),
                account: account
            )
            #expect(actions?.primaryLabel == "Connect Grok")
            #expect(actions?.secondaryLabel == "Use Device Code")
            #expect(actions?.secondaryAccessibilityLabel == "Use Device Code for \(account.label)")
            #expect(actions?.secondaryAction == .connectGrokDeviceCode)
            guard let action = actions?.secondaryAction,
                  case .setup(let mode) = SetupSessions.recoveryRoute(for: action)
            else {
                Issue.record("Expected the Grok settings secondary action to route to setup")
                continue
            }
            coordinator.begin(for: account, mode: mode)
        }

        await settleTasks()

        #expect(harness.bindings.count == 2)
        #expect(accounts.allSatisfy { coordinator.state(for: $0.key) == .waiting(attempt: 0) })
        #expect(accounts.allSatisfy { coordinator.sessionMode(for: $0.key) == .deviceCode })
        let first = try #require(harness.bindings[accounts[0].key])
        let second = try #require(harness.bindings[accounts[1].key])
        #expect(first.home != second.home)
        #expect(first.script.contains("export GROK_HOME='\(first.home.path)'"))
        #expect(second.script.contains("export GROK_HOME='\(second.home.path)'"))
        #expect(!first.script.contains(second.home.path))
        #expect(!second.script.contains(first.home.path))
    }

    @Test func oneActionRecoveryStaysSingleLine() {
        let account = ProviderAccount.builtIn(for: .codex)
        let actions = AccountsSettingsInteractions.recoveryRowActions(
            snapshot: .stale(for: .codex, reason: .providerSetup(.codexCredentialIO)),
            account: account
        )

        #expect(actions?.usesSecondLine == false)
        #expect(actions?.primaryLabel == "Check Again")
        #expect(actions?.secondaryAction == nil)
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

@MainActor
private final class GrokDeviceCodeSetupHarness {
    struct Binding {
        let home: URL
        let script: String
    }

    let accounts: [ProviderAccount]
    let accountsBase: URL
    var bindings: [AccountKey: Binding] = [:]

    init(accounts: [ProviderAccount], accountsBase: URL) {
        self.accounts = accounts
        self.accountsBase = accountsBase
    }

    func makeCoordinator() -> SetupSessionCoordinator {
        SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { [weak self] account, mode in
                guard let self else { return .failure(.stagingFailed) }
                do {
                    guard let home = ProviderAccountConfiguration.make(
                        for: account,
                        accountsBase: self.accountsBase
                    ).grokHomeDirectory else { return .failure(.stagingFailed) }
                    try FileManager.default.createDirectory(
                        at: home,
                        withIntermediateDirectories: true,
                        attributes: [.posixPermissions: 0o700]
                    )
                    let script = GrokCLI.loginScript(
                        executablePath: "/opt/homebrew/bin/grok",
                        grokHome: home.path,
                        mode: mode
                    )
                    self.bindings[account.key] = Binding(home: home, script: script)
                    await Task.yield()
                    return .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
                } catch {
                    return .failure(.stagingFailed)
                }
            },
            open: { _ in .success(()) },
            accountExists: { [accounts] key in accounts.contains(where: { $0.key == key }) },
            requestRefresh: { _ in }
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
    @MainActor @Test func activeSetupSessionKeepsCapabilityRecoveryVisibleWithRefusalState() {
        #expect(capabilityRecoveryPresentation(
            state: .inconclusive(.shellTimeout),
            hasActiveSetupSession: false
        ) != nil)
        let active = capabilityRecoveryPresentation(
            state: .inconclusive(.shellTimeout),
            hasActiveSetupSession: true
        )
        #expect(active != nil)
        #expect(active?.state(for: .checkNow) == .refused("Close setup, then retry"))
        #expect(active?.state(for: .openClaudeSetup) == .refused("Close setup, then retry"))
        #expect(capabilityRecoveryPresentation(
            state: .available,
            hasActiveSetupSession: false
        ) == nil)
    }

    @MainActor @Test func installActionsRemainAvailableWhileSetupIsOpen() {
        let active = capabilityRecoveryPresentation(
            state: .confirmedAbsent,
            hasActiveSetupSession: true
        )

        #expect(active?.state(for: .installClaudeCLI) == .enabled)
        #expect(active?.state(for: .copyManualCommand) == .enabled)
    }
}

@Suite struct AccountsCapabilityPresentationTests {
    @MainActor @Test func capabilityFailureDemoDrivesStoreNoticeWithRetainedAndBareRows() async {
        let fixture = DemoFixture.multiFixture(for: .capabilityFailure)
        let suiteName = "co.zantos.headroom.capability-demo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let continuityCache = UsageContinuityCache(defaults: defaults)
        for (key, snapshot) in fixture.continuitySnapshots {
            continuityCache.save(snapshot, for: key)
        }
        let store = UsageStore(
            providers: fixture.providers,
            preferences: Preferences(defaults: defaults),
            accounts: fixture.accounts,
            continuityCache: continuityCache
        )

        await store.refreshAll()
        let snapshots = fixture.accounts.map { store.snapshot(for: $0.key) }

        #expect(fixture.accounts.count == 2)
        #expect(store.providerCapabilities[.claude]?.state == .confirmedAbsent)
        #expect(snapshots.contains { !$0.windows.isEmpty })
        #expect(snapshots.contains { $0.windows.isEmpty })
        let notice = capabilityRecoveryPresentation(
            state: store.providerCapabilities[.claude]?.state,
            hasActiveSetupSession: false
        )
        #expect(snapshots.map {
            AccountsSettingsInteractions.capabilityRowPresentation(
                snapshot: $0,
                capability: notice
            )
        }.contains(.retainedUsage))
        #expect(snapshots.map {
            AccountsSettingsInteractions.capabilityRowPresentation(
                snapshot: $0,
                capability: notice
            )
        }.contains(.waitingForClaudeCode))
    }

    @Test func capabilityFailureDerivesBareAndRetainedRowsWithoutMutatingSnapshots() {
        let pending = UsageSnapshot.pending(for: .claude)
        let retained = UsageSnapshot(
            providerID: .claude,
            windows: [UsageWindow(kind: .weekly, utilization: 62, resetsAt: Date(timeIntervalSince1970: 20))],
            planLabel: "Max",
            capturedAt: Date(timeIntervalSince1970: 10),
            freshness: .stale(.transient("will retry"))
        )
        let notice = capabilityRecoveryPresentation(
            state: .confirmedAbsent,
            hasActiveSetupSession: false
        )

        #expect(AccountsSettingsInteractions.capabilityRowPresentation(
            snapshot: pending,
            capability: notice
        ) == .waitingForClaudeCode)
        #expect(AccountsSettingsInteractions.capabilityRowPresentation(
            snapshot: retained,
            capability: notice
        ) == .retainedUsage)
        #expect(retained.windows.first?.utilization == 62)
        #expect(retained.capturedAt == Date(timeIntervalSince1970: 10))
    }

    @Test func nonFailureCapabilityStatesLeaveRowsUnchanged() {
        for state in [
            ProviderCapabilityState.unknown,
            .discovering,
            .available,
        ] {
            #expect(AccountsSettingsInteractions.capabilityRowPresentation(
                snapshot: .pending(for: .claude),
                capability: capabilityRecoveryPresentation(
                    state: state,
                    hasActiveSetupSession: false
                )
            ) == .standard)
        }
    }

    @Test func capabilityAnnouncementFiresOncePerFailureTransition() {
        var dedupe = CapabilityAnnouncementDedupe()

        #expect(dedupe.announcement(
            for: .claude,
            state: .confirmedAbsent
        ) == "Claude Code availability. Install Claude Code to show usage")
        #expect(dedupe.announcement(for: .claude, state: .confirmedAbsent) == nil)
        #expect(dedupe.announcement(for: .claude, state: .available) == nil)
        #expect(dedupe.announcement(
            for: .claude,
            state: .inconclusive(.shellTimeout)
        ) == "Claude Code availability. Claude Code location couldn't be confirmed — usage will retry")
        #expect(dedupe.announcement(for: .claude, state: .inconclusive(.shellTimeout)) == nil)
    }
}
