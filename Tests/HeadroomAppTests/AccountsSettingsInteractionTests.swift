import Foundation
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

@MainActor
@Suite(.sharedAppState, .serialized)
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

    @Test func guidedClaudeResetPreparesResetPurposeAndOfficialAuthCommands() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-reset-preparation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let account = ProviderAccount.builtIn(for: .claude)

        let result = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            purpose: .reset,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true")
        )
        guard case .success(let handoff) = result else {
            Issue.record("Expected reset preparation to succeed")
            return
        }
        let prepared = try #require(SetupSessions.stagedHandoff(for: account.key))
        let script = try String(contentsOf: prepared.scriptURL, encoding: .utf8)

        #expect(handoff.purpose == .reset)
        #expect(script.contains("'/usr/bin/true' auth logout && '/usr/bin/true' auth login"))
        await SetupSessions.discardPreparedHandoff(handoff)
    }

    // MARK: - U5 (OpenCode plan): staging the sign-in handoff

    /// KTD3: a 1.x client is refused at staging with the usage read's own outcome. No script
    /// is written, so no Terminal can open.
    @Test func openCodeStagingRefusesAnOldClientBeforeAnyTerminal() async {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-oc-stage-old-\(UUID().uuidString)/ClaudeProbe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let account = ProviderAccount.builtIn(for: .opencode)
        for version in ["1.1.53\n", "opencode v2.1.0"] {
            let result = await SetupSessions.prepareHandoff(
                for: account,
                mode: .standard,
                builtInClaudeWorkspace: workspace,
                openCodeExecutableResolver: { "/fake/bin/opencode" },
                openCodeExecutableOverride: nil,
                openCodeVersionReader: { _, _ in version }
            )
            #expect(result == .failure(.provider(.opencodeUpdateRequired)))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
        }
        let missing = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            builtInClaudeWorkspace: workspace,
            openCodeExecutableResolver: { nil },
            openCodeExecutableOverride: nil,
            openCodeVersionReader: { _, _ in "2.2.5" }
        )
        #expect(missing == .failure(.executableMissing))
    }

    /// KTD18: the built-in home never takes the DEBUG override; the version read and the
    /// script both use the resolved client, and the clipboard fallback names its path.
    @Test(arguments: [SetupHandoffPurpose.setup, .reset])
    func openCodeBuiltInStagingUsesTheResolvedClientAndItsDefaultHome(_ purpose: SetupHandoffPurpose) async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-oc-stage-\(UUID().uuidString)/ClaudeProbe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let account = ProviderAccount.builtIn(for: .opencode)
        let reads = VersionReadRecorder()

        let result = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            purpose: purpose,
            builtInClaudeWorkspace: workspace,
            openCodeExecutableResolver: { "/resolved/bin/opencode" },
            openCodeExecutableOverride: "/override/opencode",
            openCodeVersionReader: { path, home in
                await reads.record(path, home)
                return "opencode v2.2.5"
            }
        )
        guard case .success(let handoff) = result else {
            Issue.record("Expected OpenCode staging to succeed, got \(result)")
            return
        }
        let prepared = try #require(SetupSessions.stagedHandoff(for: account.key))
        let script = try String(contentsOf: prepared.scriptURL, encoding: .utf8)

        #expect(await reads.calls == ["/resolved/bin/opencode builtIn"])
        #expect(script.contains("unset XDG_DATA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME"))
        #expect(script.contains("'/resolved/bin/opencode' auth login --standalone opencode --method device"))
        #expect(script.contains("'/resolved/bin/opencode' auth logout --standalone opencode") == (purpose == .reset))
        #expect(!script.contains("/override/opencode"))
        #expect(script.contains("trap headroom_setup_completed EXIT"))
        #expect(prepared.manualCommand.contains("/resolved/bin/opencode"))
        #expect(handoff.purpose == purpose)
        await SetupSessions.discardPreparedHandoff(handoff)
    }

    // MARK: - U5/AE7: the built-in sign-in warning

    /// Covers AE7: Sign In, Sign In Again (the same `openSetup`), Try Again and reset on the
    /// built-in account ask before anything is staged, every time, including after an earlier
    /// confirmed start. Cancel opens nothing.
    @Test func builtInOpenCodeSignInAsksEveryTimeAndCancelOpensNothing() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let harness = AppSetupHarness(store: fixture.store)
        let coordinator = harness.makeCoordinator()
        let builtIn = ProviderAccount.builtIn(for: .opencode)
        let center = BuiltInSignInConfirmation.shared
        center.reset()
        defer { center.reset() }

        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.performRecovery(.connectOpenCode, for: builtIn, onRetry: {})
        }
        #expect(center.pending?.account.key == builtIn.key)
        #expect(center.pending?.purpose == .setup)
        #expect(coordinator.state(for: builtIn.key) == .idle)

        if let request = center.pending { center.cancel(request) }
        await settleTasks()
        #expect(center.pending == nil)
        #expect(harness.preparedKeys.isEmpty)
        #expect(harness.openedKeys.isEmpty)

        // Confirm: the start runs for real.
        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.openSetup(for: builtIn, onRetry: {})
            if let request = center.pending { center.confirm(request) }
        }
        #expect(center.pending == nil)
        #expect(coordinator.state(for: builtIn.key) == .preparing)
        await settleTasks()
        #expect(harness.preparedKeys == [builtIn.key])
        coordinator.forceCancel(builtIn.key)
        SetupSessions.forceCancel(for: builtIn)

        // Asked again after an earlier confirmed start: nothing is remembered.
        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.tryAgain(for: builtIn, route: .startNewHandoff(.setup), onRetry: {})
        }
        #expect(center.pending?.purpose == .setup)
        if let request = center.pending { center.cancel(request) }

        // Reset, from Try Again's reset branch and from the direct entry point.
        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.tryAgain(for: builtIn, route: .startNewHandoff(.reset), onRetry: {})
        }
        #expect(center.pending?.purpose == .reset)
        if let request = center.pending { center.cancel(request) }
        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.resetSetup(for: builtIn)
        }
        #expect(center.pending?.purpose == .reset)
        SetupSessions.withCoordinator(coordinator) {
            if let request = center.pending { center.confirm(request) }
        }
        #expect(coordinator.sessionPurpose(for: builtIn.key) == .reset)
        await settleTasks()
        #expect(harness.preparedKeys == [builtIn.key, builtIn.key])
        coordinator.forceCancel(builtIn.key)
        SetupSessions.forceCancel(for: builtIn)
    }

    /// AE7: an extra account, and every other provider's built-in, start with no dialog.
    @Test func extraOpenCodeAccountsAndOtherProvidersNeverAsk() async {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let harness = AppSetupHarness(store: fixture.store)
        let coordinator = harness.makeCoordinator()
        let center = BuiltInSignInConfirmation.shared
        center.reset()
        defer { center.reset() }
        let extra = ProviderAccount(id: AccountID("oc-extra-\(UUID().uuidString)"), providerID: .opencode,
                                    label: "Work", isBuiltIn: false)
        let claude = ProviderAccount.builtIn(for: .claude)

        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.openSetup(for: extra, onRetry: {})
            SetupSessions.openSetup(for: claude, onRetry: {})
        }
        #expect(center.pending == nil)
        await settleTasks()
        #expect(harness.preparedKeys == [extra.key, claude.key])
        for account in [extra, claude] {
            coordinator.forceCancel(account.key)
            SetupSessions.forceCancel(for: account)
        }
    }

    /// The Settings reset dialog is the built-in warning itself, so it asks once, not twice.
    @Test func settingsResetDialogCarriesTheOpenCodeWarning() {
        let builtIn = ProviderAccount.builtIn(for: .opencode)
        let message = AccountsSettingsInteractions.resetDialogMessage(for: builtIn, providerDisplayName: "OpenCode")
        #expect(message == SettingsCopy.opencodeBuiltInResetWarning)
        #expect(AccountsSettingsInteractions.resetDialogMessage(
            for: .builtIn(for: .codex), providerDisplayName: "Codex"
        ).contains("switches the Codex CLI login"))
    }

    /// U12 (b): a Console login adds an OAuth credential and makes it active; a stored key is
    /// kept. The copy says so, never that the key is replaced or removed, and the Terminal
    /// claim stays modest for users who moved OpenCode's data (KTD10).
    @Test func builtInWarningCopyMatchesWhatALoginDoesToAStoredKey() {
        let signIn = SettingsCopy.opencodeBuiltInSignInWarning
        #expect(signIn.contains("A saved API key stays saved"))
        #expect(signIn.contains("makes it the active login"))
        for text in [signIn, SettingsCopy.opencodeBuiltInResetWarning] {
            #expect(!text.localizedCaseInsensitiveContains("replace"))
            #expect(text.contains("Terminal normally uses"))
            #expect(!text.contains("'"))
            #expect(!text.localizedCaseInsensitiveContains("connect"))
        }
        #expect(BuiltInSignInConfirmation.title(for: .setup) == "Sign in to OpenCode Console?")
        #expect(BuiltInSignInConfirmation.title(for: .reset) == "Sign out and set up again?")
        #expect(BuiltInSignInConfirmation.confirmLabel(for: .setup) == "Sign In")
    }

    @Test func confirmationGoesToTheKeyWindowThenAVisibleOneThenTheLatest() {
        let a = UUID(), b = UUID(), c = UUID()
        typealias Candidate = BuiltInSignInConfirmation.PresenterCandidate
        #expect(BuiltInSignInConfirmation.choosePresenter(from: [
            Candidate(id: a, isKey: false, isVisible: true),
            Candidate(id: b, isKey: true, isVisible: true),
            Candidate(id: c, isKey: false, isVisible: false),
        ]) == b)
        #expect(BuiltInSignInConfirmation.choosePresenter(from: [
            Candidate(id: a, isKey: false, isVisible: true),
            Candidate(id: c, isKey: false, isVisible: false),
        ]) == a)
        #expect(BuiltInSignInConfirmation.choosePresenter(from: [
            Candidate(id: a, isKey: false, isVisible: false),
            Candidate(id: c, isKey: false, isVisible: false),
        ]) == c)
        #expect(BuiltInSignInConfirmation.choosePresenter(from: []) == nil)
    }

    @Test func openCodeInstallRouteIsTheDocsPageAndTheNoGoRowCarriesTheWorkspaceNote() {
        #expect(SetupSessions.recoveryRoute(for: .installOpenCodeCLI) == .documentation(OpenCodeCLI.installationURL))
        #expect(PlanStatusActionRow.primaryHelp(for: .seeOpenCodeGoPlans) == SettingsCopy.opencodeWorkspaceScope)
        #expect(PlanStatusActionRow.primaryHelp(for: .checkNow) == nil)
        #expect(SetupSessions.failureMessage(
            for: .executableMissing, account: .builtIn(for: .opencode)
        ) == "OpenCode CLI wasn’t found. Install or update it, then try again.")
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

        let extras = AccountRegistry.testedEnvelope - 1
        for _ in 0..<extras {
            let added = AccountsSettingsInteractions.addAccount(
                for: .claude,
                to: fixture.store,
                openSetup: { opened.append($0.key) }
            )
            #expect(added != nil)
        }

        #expect(fixture.store.accounts(for: .claude).count == AccountRegistry.testedEnvelope)
        #expect(Set(opened).count == extras)
        #expect(AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { opened.append($0.key) }
        ) == nil)
        #expect(opened.count == extras)
    }

    @Test func accountCounterReadsAsATestedEnvelopeOnlyAtCapacity() {
        #expect(AccountsSettingsInteractions.accountCounterText(usedSlots: 19, capacity: 20) == "19 of 20")
        #expect(AccountsSettingsInteractions.accountCounterText(usedSlots: 20, capacity: 20) == "Tested up to 20")
        // Cursor's single account is a design bound, not an envelope anyone tested up to.
        #expect(AccountsSettingsInteractions.accountCounterText(usedSlots: 1, capacity: 1) == "Single account")
    }

    @Test func singleAccountProviderExplainsItsBoundInsteadOfAnEnvelope() {
        let cursor = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Cursor",
            accounts: [ProviderAccount.builtIn(for: .cursor)],
            capacity: 1,
            hasFreeAccountSlot: false,
            isSurfaceEnabled: true,
            hasActiveHandoff: { _ in false }
        )
        #expect(!cursor.addAction.isEnabled)
        #expect(cursor.addAction.helpText == "Cursor supports one account")
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

    @Test func committedRenameIgnoresLateFieldWriteAfterFocusMoves() {
        let work = ProviderAccount(
            id: AccountID("work"),
            providerID: .claude,
            label: "Work QA"
        )
        let studio = ProviderAccount(
            id: AccountID("studio"),
            providerID: .claude,
            label: "Studio"
        )

        #expect(!acceptsAccountLabelDraftChange(
            for: work.key,
            focusedAccountKey: studio.key
        ))
        #expect(accountLabelFieldValue(
            for: work,
            draft: "Work",
            focusedAccountKey: studio.key
        ) == "Work QA")
        #expect(acceptsAccountLabelDraftChange(
            for: work.key,
            focusedAccountKey: work.key
        ))
        #expect(accountLabelFieldValue(
            for: work,
            draft: "Work QA Draft",
            focusedAccountKey: work.key
        ) == "Work QA Draft")
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

    @Test func builtInRemovalRoutesToStopTrackingWithoutTouchingDisk() async {
        let storage = InteractionStorage()
        let fixture = makeFixture(storage: storage)
        defer { fixture.cleanup() }
        guard let extra = AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { _ in }
        ) else {
            Issue.record("Expected an additional Claude account")
            return
        }
        let builtIn = fixture.store.accounts(for: .claude).first(where: \.isBuiltIn)!

        #expect(await AccountsSettingsInteractions.removeAccount(builtIn, from: fixture.store) == .removed)
        #expect(fixture.store.accounts(for: .claude).map(\.key) == [extra.key])
        // Stop-tracking is registry-only: the CLI's own config home is never deleted.
        #expect(storage.removedKeys.isEmpty)
        #expect(fixture.store.isBuiltInTrackingStopped(for: .claude))

        let resumed = AccountsSettingsInteractions.resumeTrackingBuiltIn(for: .claude, in: fixture.store)
        #expect(resumed?.id == .primary)
        #expect(fixture.store.accounts(for: .claude).first?.isBuiltIn == true)
        #expect(!fixture.store.isBuiltInTrackingStopped(for: .claude))
        await settleTasks()
    }

    /// Resume is the undo for stop-tracking, so the resurfaced row has to poll now
    /// rather than at the next timer tick — and only that row: each Claude fetch is a
    /// 20–30s CLI session, so a fan-out here would be an expensive silent regression.
    @Test func resumeTrackingRefreshesOnlyTheResumedBuiltInRow() async {
        let fetches = AccountFetchRecorder()
        let suiteName = "co.zantos.headroom.app-interactions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(
            providers: [
                CountingAccountProvider(id: .claude, accountID: .primary, fetches: fetches),
                CountingAccountProvider(id: .codex, accountID: .primary, fetches: fetches),
            ],
            preferences: Preferences(defaults: defaults),
            accountRegistry: AccountRegistry(defaults: defaults),
            accountStorage: InteractionStorage(),
            providerFactory: { account in
                CountingAccountProvider(id: account.providerID, accountID: account.id, fetches: fetches)
            }
        )
        guard let extra = AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: store,
            openSetup: { _ in }
        ) else {
            Issue.record("Expected an additional Claude account")
            return
        }
        let builtIn = store.accounts(for: .claude).first(where: \.isBuiltIn)!
        #expect(await AccountsSettingsInteractions.removeAccount(builtIn, from: store) == .removed)
        await settleTasks()
        await fetches.reset()

        #expect(AccountsSettingsInteractions.resumeTrackingBuiltIn(for: .claude, in: store)?.id == .primary)
        await settleTasks()

        #expect(await fetches.count(for: builtIn.key) == 1)
        #expect(await fetches.count(for: extra.key) == 0)
        #expect(await fetches.count(for: AccountKey(providerID: .codex, accountID: .primary)) == 0)
    }

    @Test func everyRecoveryActionHasOneAppBoundaryRoute() {
        let expected: [(SetupRecoveryAction, SetupSessions.RecoveryRoute)] = [
            (.installClaudeCLI, .documentation(URL(string: "https://code.claude.com/docs/en/installation")!)),
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
            (.installCopilotCLI, .documentation(CopilotCLI.installationURL)),
            (.connectCopilot, .setup(.standard)),
            (.installOpenCodeCLI, .documentation(URL(string: "https://opencode.ai/docs/")!)),
            (.updateOpenCode, .documentation(URL(string: "https://anoma.ly/notes/opencode-2-0")!)),
            (.connectOpenCode, .setup(.standard)),
            (.seeOpenCodeGoPlans, .documentation(URL(string: "https://opencode.ai/go")!)),
            // KTD21: the same feedback email as Settings › About.
            (.contactSupport, .feedbackEmail),
            // KTD5 (2026-09-19 sign-in plan): Claude's approval handoff shares Cursor's
            // trust route; only Sign In still routes to `.setup(.standard)`.
            (.openClaudeWorkspace, .workspaceTrust),
            // A startup question is answered in the same interactive launch.
            (.answerClaudeQuestion, .workspaceTrust),
            (.openCursorWorkspace, .workspaceTrust),
            (.reviewCursorTools, .cursorTools),
            (.showPrivacyGuidance, .privacyGuidance(URL(string: "https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac")!)),
            (.resolveCodexStorage, .setup(.standard)),
            (.checkNow, .checkNow),
        ]

        for (action, route) in expected {
            #expect(SetupSessions.recoveryRoute(for: action) == route)
        }
    }

    @Test func stopWaitingClearsSetupActiveRemovalRefusalAndRoutesForceCancel() async {
        let storage = InteractionStorage(setupHandoffActive: true)
        let fixture = makeFixture(storage: storage)
        defer { fixture.cleanup() }
        let account = try! #require(AccountsSettingsInteractions.addAccount(
            for: .claude,
            to: fixture.store,
            openSetup: { _ in }
        ))
        #expect(await fixture.store.removeAccount(account.key) == .setupActive)
        #expect(fixture.store.accountRemovalStates[account.key] == .setupActive)
        var cancelled: [AccountKey] = []

        AccountsSettingsInteractions.stopWaiting(
            for: account,
            in: fixture.store,
            forceCancel: { cancelled.append($0.key) }
        )

        #expect(cancelled == [account.key])
        #expect(fixture.store.accountRemovalStates[account.key] == nil)
    }

    // MARK: - R9/R10/R11: the provider group's subscription switch (KTD6)

    @Test func providerSwitchStaysEnabledWhileNoAccountHasAnOpenHandoff() {
        let accounts = [
            ProviderAccount.builtIn(for: .claude),
            ProviderAccount(id: AccountID("work"), providerID: .claude, label: "Work"),
        ]

        let presentation = AccountsSettingsInteractions.subscriptionSwitchPresentation(
            providerDisplayName: "Claude",
            accounts: accounts,
            isSurfaceEnabled: true,
            hasActiveHandoff: { _ in false }
        )

        #expect(presentation.isEnabled)
        #expect(presentation.helpText == nil)
        #expect(presentation.accessibilityLabel == "Claude subscription")
    }

    @Test func providerSwitchDisablesWithANamedReasonWhileASignInIsOpen() {
        let builtIn = ProviderAccount.builtIn(for: .claude)
        let work = ProviderAccount(id: AccountID("work"), providerID: .claude, label: "Work")

        let whileOn = AccountsSettingsInteractions.subscriptionSwitchPresentation(
            providerDisplayName: "Claude",
            accounts: [builtIn, work],
            isSurfaceEnabled: true,
            hasActiveHandoff: { $0.key == work.key }
        )
        #expect(!whileOn.isEnabled)
        #expect(whileOn.helpText == "Finish or stop the sign-in in progress before turning Claude off")

        let whileOff = AccountsSettingsInteractions.subscriptionSwitchPresentation(
            providerDisplayName: "Claude",
            accounts: [builtIn, work],
            isSurfaceEnabled: false,
            hasActiveHandoff: { $0.key == work.key }
        )
        #expect(!whileOff.isEnabled)
        #expect(whileOff.helpText == "Finish or stop the sign-in in progress before turning Claude on")
    }

    @Test func providerOffDimsRowsAndHidesFetchStateWhileManagementStaysLive() {
        let accounts = [
            ProviderAccount.builtIn(for: .grok),
            ProviderAccount(id: AccountID("second"), providerID: .grok, label: "Second"),
        ]

        let off = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: accounts,
            capacity: 5,
            hasFreeAccountSlot: true,
            isSurfaceEnabled: false,
            hasActiveHandoff: { _ in false }
        )

        #expect(off.dimsAccountRows)
        // R11: "off" means "not fetched", never "unmanageable" — fetch-derived status
        // hides, but a sign-in the user starts anyway still reports itself.
        #expect(off.hidesAccountStatus(isSetupState: false))
        #expect(!off.hidesAccountStatus(isSetupState: true))
        #expect(off.hidesFetchRecovery)
        #expect(off.hidesCapabilityBanner)
        // R2B1: one constant behind the Accounts help line and the Menu Bar Off tooltip, and
        // no trailing stop — the two sites used to disagree on exactly that.
        #expect(off.offHelpText == "Not fetched while this provider is off")
        #expect(off.offHelpText == SettingsCopy.providerOffNotice)
        #expect(SettingsCopy.providerOffAccessibilityLabel
                == "Off — not fetched while this provider is off")
        #expect(off.showsAccountCounter)
        #expect(off.showsAddAction)
        #expect(off.subscriptionSwitch.isEnabled)

        let on = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: accounts,
            capacity: 5,
            hasFreeAccountSlot: true,
            isSurfaceEnabled: true,
            hasActiveHandoff: { _ in false }
        )
        #expect(!on.dimsAccountRows)
        #expect(!on.hidesAccountStatus(isSetupState: false))
        #expect(!on.hidesAccountStatus(isSetupState: true))
        #expect(!on.hidesFetchRecovery)
        #expect(!on.hidesCapabilityBanner)
        #expect(on.offHelpText == nil)
    }

    // MARK: - L11A: Add Account while the provider is off

    @Test func addAccountIsLiveWhileTheProviderIsOnAndHasARoomySlot() {
        let presentation = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: [ProviderAccount.builtIn(for: .grok)],
            capacity: 5,
            hasFreeAccountSlot: true,
            isSurfaceEnabled: true,
            hasActiveHandoff: { _ in false }
        )

        #expect(presentation.showsAddAction)
        #expect(presentation.addAction.isEnabled)
        #expect(presentation.addAction.helpText == "Sign in another account via the official CLI")
    }

    @Test func addAccountIsDisabledWhileTheProviderIsOffAndSaysWhy() {
        let presentation = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: [ProviderAccount.builtIn(for: .grok)],
            capacity: 5,
            hasFreeAccountSlot: true,
            isSurfaceEnabled: false,
            hasActiveHandoff: { _ in false }
        )

        // L11A: the button is still drawn — it dims with the group rather than vanishing.
        #expect(presentation.showsAddAction)
        #expect(!presentation.addAction.isEnabled)
        #expect(presentation.addAction.helpText == "Turn Grok on to add an account")
        // The switch is the way back out, so it must not dim with everything else.
        #expect(presentation.subscriptionSwitch.isEnabled)
    }

    @Test func addAccountAtCapacityKeepsTheCapacityReasonEvenWhileOff() {
        let full = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: [ProviderAccount.builtIn(for: .grok)],
            capacity: 5,
            hasFreeAccountSlot: false,
            isSurfaceEnabled: false,
            hasActiveHandoff: { _ in false }
        )

        // L11A: turning the provider on would not free a slot, so the off-switch reason
        // must never displace the capacity one — it would send the user through the
        // switch for nothing.
        #expect(!full.addAction.isEnabled)
        #expect(full.addAction.helpText == "Tested up to 5 accounts per provider")

        let fullAndOn = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: [ProviderAccount.builtIn(for: .grok)],
            capacity: 5,
            hasFreeAccountSlot: false,
            isSurfaceEnabled: true,
            hasActiveHandoff: { _ in false }
        )
        #expect(!fullAndOn.addAction.isEnabled)
        #expect(fullAndOn.addAction.helpText == "Tested up to 5 accounts per provider")
    }

    @Test func addAccountIgnoresAnOpenHandoffButStillFollowsTheSwitch() {
        let accounts = [
            ProviderAccount.builtIn(for: .grok),
            ProviderAccount(id: AccountID("second"), providerID: .grok, label: "Second"),
        ]

        let midHandoffOn = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: accounts,
            capacity: 5,
            hasFreeAccountSlot: true,
            isSurfaceEnabled: true,
            hasActiveHandoff: { $0.id == AccountID("second") }
        )
        // R10 holds the *switch* mid-handoff; L11A does not extend that to Add Account,
        // because starting a second sign-in strands nothing.
        #expect(midHandoffOn.addAction.isEnabled)
        #expect(!midHandoffOn.subscriptionSwitch.isEnabled)

        let midHandoffOff = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: accounts,
            capacity: 5,
            hasFreeAccountSlot: true,
            isSurfaceEnabled: false,
            hasActiveHandoff: { $0.id == AccountID("second") }
        )
        #expect(!midHandoffOff.addAction.isEnabled)
        #expect(midHandoffOff.addAction.helpText == "Turn Grok on to add an account")
    }

    @Test func singleAccountProviderHeaderDropsTheCounterAndAddButKeepsTheSwitch() {
        let presentation = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Cursor",
            accounts: [ProviderAccount.builtIn(for: .cursor)],
            capacity: 1,
            hasFreeAccountSlot: false,
            isSurfaceEnabled: false,
            hasActiveHandoff: { _ in false }
        )

        #expect(!presentation.showsAccountCounter)
        #expect(!presentation.showsAddAction)
        #expect(presentation.subscriptionSwitch.isEnabled)
        #expect(presentation.subscriptionSwitch.accessibilityLabel == "Cursor subscription")
    }

    @Test func leavingAccountsCommitsOnlyTheDraftsThatWouldChangeALabel() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let account = try! #require(AccountsSettingsInteractions.addAccount(
            for: .codex,
            to: fixture.store,
            openSetup: { _ in }
        ))
        let builtIn = try! #require(fixture.store.accounts(for: .codex).first { $0.isBuiltIn })

        let pending = AccountsSettingsInteractions.pendingLabelCommits(
            drafts: [
                account.key: "  Studio  ",
                builtIn.key: "   ",
            ],
            accounts: [builtIn, account]
        )

        // Blank drafts are not renames; the unchanged built-in label stays put.
        #expect(pending.map(\.key) == [account.key])

        for pendingAccount in pending {
            AccountsSettingsInteractions.commitLabel(
                "  Studio  ",
                for: pendingAccount,
                in: fixture.store
            )
        }
        #expect(fixture.store.accounts(for: .codex).first { $0.key == account.key }?.label == "Studio")
        #expect(fixture.store.accounts(for: .codex).first { $0.key == builtIn.key }?.label == builtIn.label)

        // A draft identical to the stored label is not a pending commit either.
        let settled = try! #require(fixture.store.accounts(for: .codex).first { $0.key == account.key })
        #expect(AccountsSettingsInteractions.pendingLabelCommits(
            drafts: [settled.key: "Studio"],
            accounts: [settled]
        ).isEmpty)
    }

    @Test func forceCancelClearsDurableMarkersAndRelaunchRestoresNoGhostSession() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-force-cancel-relaunch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportRoot) }
        let workspace = supportRoot.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let account = ProviderAccount.builtIn(for: .claude)
        let marker = AccountStorage.setupCompletionMarker(
            for: account,
            builtInClaudeWorkspace: workspace
        )
        try AccountStorage.prepareSetupCompletionMarker(marker)
        try Data("complete:1\n".utf8).write(to: URL(fileURLWithPath: marker.completedPath))
        SetupSessions.configure(
            store: fixture.store,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true"),
            builtInClaudeWorkspace: workspace
        )
        #expect(SetupSessions.hasActiveHandoff(for: account))

        SetupSessions.forceCancel(for: account)

        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))
        #expect(!FileManager.default.fileExists(atPath: marker.completedPath))
        #expect(!SetupSessions.hasActiveHandoff(for: account))

        SetupSessions.configure(
            store: fixture.store,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true"),
            builtInClaudeWorkspace: workspace
        )
        #expect(SetupSessions.state(for: account) == .idle)
        #expect(!SetupSessions.hasActiveHandoff(for: account))
    }

    @Test func lateCompletionAfterForceCancelDoesNotRestoreGhostSessionOnRelaunch() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-force-cancel-late-completion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportRoot) }
        let workspace = supportRoot.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let account = ProviderAccount.builtIn(for: .claude)
        let marker = AccountStorage.setupCompletionMarker(
            for: account,
            builtInClaudeWorkspace: workspace
        )
        try AccountStorage.prepareSetupCompletionMarker(marker)

        // Deterministically model the wrapper's EXIT trap after it has accepted the
        // pending owner but before it publishes completion.
        #expect(AccountStorage.setupHandoffIsActive(marker: marker))
        SetupSessions.configure(
            store: fixture.store,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true"),
            builtInClaudeWorkspace: workspace
        )
        SetupSessions.forceCancel(for: account)
        try Data("complete:setup:0\n".utf8)
            .write(to: URL(fileURLWithPath: marker.completedPath))

        SetupSessions.configure(
            store: fixture.store,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true"),
            builtInClaudeWorkspace: workspace
        )

        #expect(SetupSessions.state(for: account) == .idle)
        #expect(!SetupSessions.hasActiveHandoff(for: account))
    }

    @Test func relaunchRestoresResetPurposeFromCompletedMarkerBeforeVerification() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        await fixture.store.refreshAll()
        let supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-reset-relaunch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportRoot) }
        let workspace = supportRoot.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let account = ProviderAccount.builtIn(for: .claude)
        let marker = AccountStorage.setupCompletionMarker(
            for: account,
            builtInClaudeWorkspace: workspace
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: marker.completedPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("complete:reset:0\n".utf8)
            .write(to: URL(fileURLWithPath: marker.completedPath))
        #expect(fixture.store.snapshot(for: account.key).freshness == .live)

        SetupSessions.configure(
            store: fixture.store,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true"),
            builtInClaudeWorkspace: workspace
        )

        #expect(SetupSessions.state(for: account) == .verifying)
        #expect(fixture.store.snapshot(for: account.key).freshness == .pending)
        #expect(!FileManager.default.fileExists(atPath: marker.completedPath))
    }

    @Test func builtInResetPresentationCoversLoneExtraAndDemoStores() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let builtIn = ProviderAccount.builtIn(for: .claude)
        #expect(AccountsSettingsInteractions.builtInRowActions(
            for: builtIn,
            in: fixture.store
        ) == .resetOnly)

        _ = fixture.store.addAccount(for: .claude)
        #expect(AccountsSettingsInteractions.builtInRowActions(
            for: builtIn,
            in: fixture.store
        ) == .resetAndStopTracking)

        let demoStore = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
            ],
            accounts: [builtIn]
        )
        #expect(AccountsSettingsInteractions.builtInRowActions(
            for: builtIn,
            in: demoStore
        ) == .unavailable)
    }

    @Test func builtInResetRoutesOnlyConfiguredBuiltInAccountToCoordinatorEntryPoint() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let builtIn = ProviderAccount.builtIn(for: .codex)
        let extra = ProviderAccount(
            id: AccountID("extra"),
            providerID: .codex,
            label: "Extra",
            isBuiltIn: false
        )
        var resetKeys: [AccountKey] = []

        let resetBuiltIn = AccountsSettingsInteractions.resetBuiltIn(
            builtIn,
            in: fixture.store,
            beginReset: { resetKeys.append($0.key) }
        )
        let resetExtra = AccountsSettingsInteractions.resetBuiltIn(
            extra,
            in: fixture.store,
            beginReset: { resetKeys.append($0.key) }
        )

        #expect(resetBuiltIn)
        #expect(!resetExtra)
        #expect(resetKeys == [builtIn.key])
    }

    @Test func promotionPresentationDistinguishesPrimaryAvailableAndDemoRows() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let builtIn = ProviderAccount.builtIn(for: .claude)
        let extra = try! #require(fixture.store.addAccount(for: .claude))

        #expect(AccountsSettingsInteractions.promotionState(for: builtIn, in: fixture.store) == .primary)
        #expect(AccountsSettingsInteractions.promotionState(for: extra, in: fixture.store) == .available)

        let demoStore = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot, accountID: extra.id),
            ],
            accounts: [builtIn, extra]
        )
        #expect(AccountsSettingsInteractions.promotionState(for: extra, in: demoStore) == .unavailable)
    }

    @Test func makeMainReturnsFocusAndVoiceOverContextForTheMovedRow() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let extra = try! #require(fixture.store.addAccount(for: .codex))

        let feedback = AccountsSettingsInteractions.makeMain(extra, in: fixture.store)

        #expect(feedback?.accountKey == extra.key)
        #expect(feedback?.announcement == "\(extra.label) is now Main")
        #expect(fixture.store.primaryAccount(for: .codex)?.key == extra.key)
    }

    @Test func capabilityRecoveryTargetsPromotedPrimary() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let extra = try! #require(fixture.store.addAccount(for: .claude))
        _ = AccountsSettingsInteractions.makeMain(extra, in: fixture.store)
        var routed: [AccountKey] = []

        #expect(AccountsSettingsInteractions.performCapabilityRecovery(
            .openClaudeSetup,
            for: .claude,
            in: fixture.store,
            perform: { _, account, _ in routed.append(account.key) }
        ))
        #expect(routed == [extra.key])
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

    @Test func repeatedCheckNowSharesForcedDiscoveryWithSelectedAccountRefresh() async {
        let suiteName = "co.zantos.headroom.check-now-generation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shell = GatedCheckNowShellSearch()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestCheckNowHintStore(),
            shellSearch: { await shell.search() },
            validate: { _ in .missing }
        )
        let fetches = CheckNowFetchRecorder()
        let account = ProviderAccount.builtIn(for: .claude)
        let store = UsageStore(
            providers: [CheckNowUsageProvider(locator: locator, fetches: fetches)],
            preferences: Preferences(defaults: defaults),
            accounts: [account]
        )
        SetupSessions.configure(store: store, claudeExecutableLocator: locator)

        for _ in 0..<2 {
            SetupSessions.performRecovery(
                .checkNow,
                for: account,
                onRetry: { store.refreshAccountNow(account.key) }
            )
        }
        while await shell.count < 1 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        await shell.release()
        while await fetches.count < 1 { await Task.yield() }
        while store.isRefreshing { await Task.yield() }

        #expect(await fetches.count == 1)
        #expect(await shell.count == 1)
    }

    @Test func providerCapabilityRecoveryTargetsPrimaryAndRefreshesEveryProviderAccount() {
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
        #expect(refreshed == fixture.store.accounts(for: .claude).map(\.key))
        #expect(refreshed.contains(try! #require(extra?.key)))
        #expect(extra?.key != primary)
    }

    @Test func inconclusiveCapabilityOffersBothProviderScopedSettingsActions() {
        let presentation = capabilityRecoveryPresentation(
            state: .inconclusive(.shellTimeout),
            hasActiveSetupSession: false
        )

        #expect(presentation?.recovery.primaryLabel == "Check Now")
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
            #expect(actions?.primaryLabel == ProviderSignInCopy.button)
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

    /// R14/KTD13 (2026-09-19 sign-in plan): Show Terminal activates the app recorded for the
    /// open handoff exactly once. It is an activation, not another entry point into setup, so
    /// nothing may be staged, begun, or re-stated by it.
    @Test func showTerminalActivatesTheRecordedHandlerOnceAndStartsNoHandoff() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let account = ProviderAccount.builtIn(for: .claude)
        let environment = configureIsolatedSetupSessions(store: fixture.store)
        defer { environment.cleanup() }
        let recorder = ActivationRecorder(isRunning: true)
        let restore = SetupSessions.activateApplication
        defer {
            SetupSessions.activateApplication = restore
            SetupSessions.noteHandoffTerminalApp(nil, for: account.key)
        }
        SetupSessions.activateApplication = { recorder.activate($0) }
        SetupSessions.noteHandoffTerminalApp("com.apple.Terminal", for: account.key)

        #expect(SetupSessions.showTerminal(for: account))

        #expect(recorder.activated == ["com.apple.Terminal"])
        #expect(SetupSessions.state(for: account) == .idle)
        #expect(!SetupSessions.hasActiveHandoff(for: account))
        #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
    }

    /// R14/KTD13: with nothing recorded, or with the recorded handler no longer running, the
    /// button is silent — it reports that it activated nothing and leaves the session alone.
    @Test func showTerminalIsASilentNoOpWithoutARunningRecordedHandler() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let account = ProviderAccount.builtIn(for: .claude)
        let environment = configureIsolatedSetupSessions(store: fixture.store)
        defer { environment.cleanup() }
        let recorder = ActivationRecorder(isRunning: false)
        let restore = SetupSessions.activateApplication
        defer {
            SetupSessions.activateApplication = restore
            SetupSessions.noteHandoffTerminalApp(nil, for: account.key)
        }
        SetupSessions.activateApplication = { recorder.activate($0) }
        SetupSessions.noteHandoffTerminalApp(nil, for: account.key)

        // No handler known: the AppKit seam is never reached.
        #expect(!SetupSessions.showTerminal(for: account))
        #expect(recorder.activated.isEmpty)

        // Handler known but no instance of it is running.
        SetupSessions.noteHandoffTerminalApp("com.apple.Terminal", for: account.key)
        #expect(!SetupSessions.showTerminal(for: account))

        #expect(recorder.activated == ["com.apple.Terminal"])
        #expect(SetupSessions.state(for: account) == .idle)
        #expect(!SetupSessions.hasActiveHandoff(for: account))
        #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
    }

    /// R14/KTD13: the handler is saved per handoff when it opens, so changing the default
    /// `.command` app mid-handoff still fronts the app that actually holds the older one. The
    /// later handoff's identifier stands in for the changed default; neither is a real
    /// LaunchServices lookup, which is the point — Show Terminal never repeats one.
    @Test func showTerminalActivatesTheSavedAppAfterTheDefaultHandlerChanges() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let opened = ProviderAccount.builtIn(for: .claude)
        let environment = configureIsolatedSetupSessions(store: fixture.store)
        defer { environment.cleanup() }
        let later = try #require(fixture.store.addAccount(for: .claude))
        let recorder = ActivationRecorder(isRunning: true)
        let restore = SetupSessions.activateApplication
        defer {
            SetupSessions.activateApplication = restore
            SetupSessions.noteHandoffTerminalApp(nil, for: opened.key)
            SetupSessions.noteHandoffTerminalApp(nil, for: later.key)
        }
        SetupSessions.activateApplication = { recorder.activate($0) }
        SetupSessions.noteHandoffTerminalApp("co.zantos.headroom.tests.OpeningTerminal", for: opened.key)
        SetupSessions.noteHandoffTerminalApp("co.zantos.headroom.tests.NewDefaultTerminal", for: later.key)

        #expect(SetupSessions.showTerminal(for: opened))

        #expect(recorder.activated == ["co.zantos.headroom.tests.OpeningTerminal"])
        #expect(SetupSessions.handoffTerminalApp(for: opened.key) == "co.zantos.headroom.tests.OpeningTerminal")
    }

    @Test func oneActionRecoveryStaysSingleLine() {
        let account = ProviderAccount.builtIn(for: .codex)
        let actions = AccountsSettingsInteractions.recoveryRowActions(
            snapshot: .stale(for: .codex, reason: .providerSetup(.codexCredentialIO)),
            account: account
        )

        #expect(actions?.usesSecondLine == false)
        #expect(actions?.primaryLabel == "Check Now")
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

    /// Configure the shared session routing against a throwaway Claude workspace, so a test
    /// that only needs a live coordinator never reads or writes the real support directory.
    private func configureIsolatedSetupSessions(store: UsageStore) -> IsolatedSetupEnvironment {
        let supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-setup-environment-\(UUID().uuidString)", isDirectory: true)
        SetupSessions.configure(
            store: store,
            claudeExecutableLocator: FixedExecutableLocator(path: "/usr/bin/true"),
            builtInClaudeWorkspace: supportRoot.appendingPathComponent("ClaudeProbe", isDirectory: true)
        )
        return IsolatedSetupEnvironment(supportRoot: supportRoot)
    }
}

private struct IsolatedSetupEnvironment {
    let supportRoot: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: supportRoot)
    }
}

/// U5: records which client and home staging asked for a version, without running one.
private actor VersionReadRecorder {
    private(set) var calls: [String] = []

    func record(_ path: String, _ home: OpenCodeAccountHome) {
        switch home {
        case .builtIn: calls.append("\(path) builtIn")
        case .isolated(let root): calls.append("\(path) \(root)")
        }
    }
}

/// Stands in for the one AppKit call Show Terminal makes, recording every identifier it was
/// asked to front and reporting whether an instance of it was running.
@MainActor
private final class ActivationRecorder {
    private let isRunning: Bool
    private(set) var activated: [String] = []

    init(isRunning: Bool) { self.isRunning = isRunning }

    func activate(_ bundleIdentifier: String) -> Bool {
        activated.append(bundleIdentifier)
        return isRunning
    }
}

/// Shared by `ClaudeExecutableDiscoveryInteractionTests`, so file-internal rather than private.
struct FixedExecutableLocator: CLIExecutableLocating {
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

private struct CheckNowUsageProvider: UsageProvider {
    let id = ProviderID.claude
    let displayName = "Claude"
    let locator: any CLIExecutableLocating
    let fetches: CheckNowFetchRecorder

    func fetchSnapshot() async -> UsageSnapshot {
        await fetches.record()
        _ = await locator.locate()
        return .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))
    }
}

/// Counts fetches per account, so an interaction can be held to the exact set of
/// accounts it should have refreshed. Shared across provider instances because the
/// factory rebuilds one on every attach.
private actor AccountFetchRecorder {
    private var counts: [AccountKey: Int] = [:]

    func record(_ key: AccountKey) { counts[key, default: 0] += 1 }
    func count(for key: AccountKey) -> Int { counts[key] ?? 0 }
    func reset() { counts.removeAll() }
}

private struct CountingAccountProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    let fetches: AccountFetchRecorder
    var displayName: String { id == .claude ? "Claude" : "Codex" }

    func fetchSnapshot() async -> UsageSnapshot {
        await fetches.record(AccountKey(providerID: id, accountID: accountID))
        return .stale(for: id, reason: .notLoggedIn("Not signed in"))
    }
}

private actor CheckNowFetchRecorder {
    private(set) var count = 0

    func record() { count += 1 }
}

private actor GatedCheckNowShellSearch {
    private(set) var count = 0
    private var isReleased = false
    private var continuations: [CheckedContinuation<CLIExecutableShellResult, Never>] = []

    func search() async -> CLIExecutableShellResult {
        count += 1
        if isReleased { return .completed(candidates: []) }
        return await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: .completed(candidates: []))
        }
    }
}

private final class TestCheckNowHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    func hint(for executableName: String) -> String? { nil }
    func setHint(_ path: String?, for executableName: String) {}
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
    private let setupHandoffActive: Bool

    init(
        removals: [Result<Void, AccountStorageFailure>] = [],
        setupHandoffActive: Bool = false
    ) {
        self.removals = removals
        self.setupHandoffActive = setupHandoffActive
    }

    var removedKeys: [AccountKey] { lock.withLock { _removedKeys } }

    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> {
        .success(())
    }

    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool { setupHandoffActive }

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
@Suite(.sharedAppState) struct ProviderStyleIdentityTests {
    @Test func everyRegisteredProviderHasABrandIdentity() {
        for id in [ProviderID.claude, .codex, .grok, .cursor, .copilot, .opencode] {
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
        #expect(ProviderStyle.svgResourceName(for: .copilot, scheme: .light) == "copilot-light")
        #expect(ProviderStyle.svgResourceName(for: .copilot, scheme: .dark) == "copilot-dark")
        #expect(ProviderStyle.svgResourceName(for: .opencode, scheme: .light) == "opencode-light")
        #expect(ProviderStyle.svgResourceName(for: .opencode, scheme: .dark) == "opencode-dark")
    }

    /// U6 (OpenCode plan): the widget families and the Lock Screen read the asset catalog
    /// through `HeadroomWidgetStyle`, a separate switch from `ProviderStyle`, so a provider
    /// added to one and not the other would draw the dashed-circle fallback on the widgets.
    @Test func widgetStyleResolvesEveryRegisteredProvidersMark() {
        let expected: [(ProviderID, String)] = [
            (.claude, "ClaudeBrandIcon"), (.codex, "CodexBrandIcon"), (.grok, "GrokBrandIcon"),
            (.cursor, "CursorBrandIcon"), (.copilot, "CopilotBrandIcon"), (.opencode, "OpenCodeBrandIcon"),
        ]
        for (id, asset) in expected {
            #expect(HeadroomWidgetStyle.assetName(for: id.raw) == asset, "\(id.raw) asset")
            #expect(HeadroomWidgetStyle.accent(for: id.raw) != Color.secondary, "\(id.raw) accent")
            #expect(HeadroomWidgetStyle.symbol(for: id.raw) != "circle.dashed", "\(id.raw) symbol")
        }
        #expect(HeadroomWidgetStyle.assetName(for: "unknown-provider") == nil)
    }
}

@Suite(.sharedAppState) struct ProviderCardCapabilityTests {
    @MainActor @Test func ordinaryWaitingHandoffExposesStopActionOnSettingsAndPopover() async {
        let account = ProviderAccount.builtIn(for: .claude)
        let coordinator = SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { $0 == account.key },
            requestRefresh: { _ in }
        )

        coordinator.beginReset(for: account)
        for _ in 0..<20 { await Task.yield() }

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        let hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = {
            coordinator.hasActiveHandoff(for: $0.key)
        }
        #expect(settingsStopWaitingAccount(
            account,
            removalState: nil,
            setupState: coordinator.state(for: account.key),
            hasActiveHandoff: hasActiveHandoff
        ) == account)

        // A built-in reset can retain live usage while Terminal is still open. The
        // popover action therefore keys off handoff ownership, not snapshot freshness.
        let liveSnapshot = UsageSnapshot(
            providerID: .claude,
            windows: [],
            planLabel: nil,
            capturedAt: Date(),
            freshness: .live
        )
        #expect(providerCardStopWaitingAccount(
            entries: [ProviderAccountEntry(account: account, snapshot: liveSnapshot)],
            offersStopWaiting: {
                setupSessionOffersStopWaiting(
                    state: coordinator.state(for: $0.key),
                    hasActiveHandoff: hasActiveHandoff($0)
                )
            }
        ) == account)
    }

    @MainActor @Test func providerBlockedRowDoesNotOwnStopWaitingAction() async {
        let active = ProviderAccount.builtIn(for: .codex)
        let blocked = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )
        let coordinator = SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { $0 == active.key || $0 == blocked.key },
            requestRefresh: { _ in }
        )

        coordinator.begin(for: active)
        for _ in 0..<20 { await Task.yield() }
        coordinator.begin(for: blocked)

        guard case .blockedByProviderLogin = coordinator.state(for: blocked.key) else {
            Issue.record("Expected the second Codex account to be provider-blocked")
            return
        }
        #expect(settingsStopWaitingAccount(
            blocked,
            removalState: nil,
            setupState: coordinator.state(for: blocked.key),
            hasActiveHandoff: { coordinator.hasActiveHandoff(for: $0.key) }
        ) == nil)
    }

    @MainActor @Test func capabilityRefusalEndsWhenWrapperClosesAndVerificationBegins() async {
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        let entries = [ProviderAccountEntry(account: account, snapshot: .pending(for: .claude))]
        let coordinator = SetupSessionCoordinator(
            retryDelays: [.seconds(60)],
            prepare: { account, mode in
                .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { _ in .success(()) },
            accountExists: { $0 == account.key },
            requestRefresh: { _ in }
        )

        coordinator.begin(for: account)
        for _ in 0..<20 { await Task.yield() }

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        let hasActiveWrapper = providerCardHasActiveSetupSession(
            entries: entries,
            hasActiveHandoff: { coordinator.hasActiveHandoff(for: $0.key) }
        )
        #expect(hasActiveWrapper)

        coordinator.handoffDidEnd(account.key)

        #expect(coordinator.state(for: account.key) == .verifying)
        let hasPostWrapperHandoff = providerCardHasActiveSetupSession(
            entries: entries,
            hasActiveHandoff: { coordinator.hasActiveHandoff(for: $0.key) }
        )
        #expect(!hasPostWrapperHandoff)
    }

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
        #expect(active?.state(for: .checkNow) == .refused("Close setup, then retry"))
    }
}

@Suite(.sharedAppState) struct OpenHandoffRefusalPresentationTests {
    @MainActor @Test func blockedRowsExposeRefusalCopyWithoutRecoveryActions() {
        let account = ProviderAccount.builtIn(for: .codex)
        let snapshot = UsageSnapshot.stale(
            for: .codex,
            reason: .providerSetup(.codexAuthAbsent)
        )
        let setupState = SetupSessionState.blockedByOpenHandoff
        let recoveryActions = settingsRecoveryActions(
            snapshot: snapshot,
            account: account,
            setupState: setupState
        )
        let status = AccountsSettingsTile.AccountStatus(
            snapshot: snapshot,
            waiting: false,
            blocked: false,
            blockedByOpenHandoff: true,
            setupFailed: false,
            removalState: nil
        )

        #expect(setupHandoffRefusalMessage(for: setupState) == "Close setup, then retry")
        #expect(recoveryActions == nil)
        #expect(!status.needsRecovery)
        #expect(setupHandoffRefusalMessage(for: .verifying) == nil)
    }

    /// Review #6 (2026-09-19 sign-in plan): a reset blanks the row to `.pending`, and an
    /// exit-signalled handoff runs no check until Terminal closes, so the row would read
    /// "Fetching…" for the whole browser login.
    @Test func blankedRowWithAnOpenSessionReadsWaitingNotFetching() {
        func status(waiting: Bool) -> AccountsSettingsTile.AccountStatus {
            AccountsSettingsTile.AccountStatus(
                snapshot: .pending(for: .claude),
                waiting: waiting,
                blocked: false,
                blockedByOpenHandoff: false,
                setupFailed: false,
                removalState: nil
            )
        }

        #expect(status(waiting: true) == .waiting)
        #expect(status(waiting: true).isSetupState)
        #expect(status(waiting: false) == .fetching)
    }
}

@Suite(.sharedAppState) struct AccountsCapabilityPresentationTests {
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
        ) == "Claude Code availability. Headroom can’t find Claude Code on this Mac")
        #expect(dedupe.announcement(for: .claude, state: .confirmedAbsent) == nil)
        #expect(dedupe.announcement(for: .claude, state: .available) == nil)
        #expect(dedupe.announcement(
            for: .claude,
            state: .inconclusive(.shellTimeout)
        ) == "Claude Code availability. Couldn’t confirm where Claude Code is\u{00A0}—\u{00A0}will retry")
        #expect(dedupe.announcement(for: .claude, state: .inconclusive(.shellTimeout)) == nil)
    }
}

/// R13/KTD12 (2026-09-19 sign-in plan): the Settings row's controls while a handoff runs.
@Suite(.sharedAppState) struct SettingsWaitingRowTests {
    private var claudeSnapshot: UsageSnapshot {
        .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))
    }

    @MainActor @Test func waitingRowsOfferNoFetchRecoveryPair() {
        let account = ProviderAccount.builtIn(for: .claude)
        for state in [SetupSessionState.preparing, .waiting(attempt: 0), .waiting(attempt: 3), .verifying] {
            #expect(settingsRecoveryActions(
                snapshot: claudeSnapshot,
                account: account,
                setupState: state
            ) == nil, "\(state) still offers the outcome's recovery pair")
            #expect(setupRowRecovery(for: state) == .sessionOnly)
        }
    }

    /// KTD12/R6: both session-owned failures swap the row's primary to Try Again — the
    /// timeout to resume its still-open window, the too-old CLI to re-stage a handoff, which
    /// is the only thing that re-reads the installed version. Neither leaves the outcome's
    /// pair behind.
    @MainActor @Test func theTwoSessionOwnedFailuresReplaceTheRecoveryPair() {
        let account = ProviderAccount.builtIn(for: .claude)
        for state in [SetupSessionState.failed(.waitingTimedOut), .failed(.updateRequired)] {
            #expect(settingsRecoveryActions(
                snapshot: claudeSnapshot,
                account: account,
                setupState: state
            ) == nil)
        }
        #expect(setupRowRecovery(for: .failed(.waitingTimedOut)) == .tryAgain)
        #expect(setupRowRecovery(for: .failed(.updateRequired)) == .tryAgain)
        #expect(settingsStopWaitingAccount(
            account,
            removalState: nil,
            setupState: .failed(.waitingTimedOut),
            hasActiveHandoff: { _ in true }
        ) == account)
    }

    /// Every other failed state keeps the actions it returns today.
    @MainActor @Test func everyOtherFailedStateKeepsItsActionsUnchanged() {
        let account = ProviderAccount.builtIn(for: .codex)
        let snapshot = UsageSnapshot.stale(for: .codex, reason: .providerSetup(.codexAuthAbsent))
        for failure in [SetupSessionFailure.retryExhausted, .closedBeforeSignIn,
                        .terminalRejected, .stagingFailed, .executableMissing] {
            let actions = settingsRecoveryActions(
                snapshot: snapshot,
                account: account,
                setupState: .failed(failure)
            )
            #expect(actions?.primaryLabel == ProviderSignInCopy.button, "\(failure)")
            #expect(actions?.secondaryLabel == "Use Device Code", "\(failure)")
            #expect(setupRowRecovery(for: .failed(failure)) == .outcomeRecovery)
        }
        #expect(settingsRecoveryActions(
            snapshot: snapshot,
            account: account,
            setupState: .idle
        )?.primaryLabel == ProviderSignInCopy.button)
    }

    @MainActor @Test func stopWaitingSurvivesTheConfirmingPhase() {
        let account = ProviderAccount.builtIn(for: .claude)
        #expect(settingsStopWaitingAccount(
            account,
            removalState: nil,
            setupState: .verifying,
            hasActiveHandoff: { _ in false }
        ) == account)
        #expect(providerCardStopWaitingAccount(
            entries: [ProviderAccountEntry(account: account, snapshot: claudeSnapshot)],
            offersStopWaiting: {
                setupSessionOffersStopWaiting(state: .verifying, hasActiveHandoff: false)
                    && $0.key == account.key
            }
        ) == account)
    }

    /// Nothing that was not waiting starts offering Stop Waiting.
    @MainActor @Test func settledSessionsStillOfferNoStopWaiting() {
        let account = ProviderAccount.builtIn(for: .claude)
        for state in [SetupSessionState.idle, .connected, .cancelled,
                      .failed(.retryExhausted), .failed(.closedBeforeSignIn)] {
            #expect(settingsStopWaitingAccount(
                account,
                removalState: nil,
                setupState: state,
                hasActiveHandoff: { _ in false }
            ) == nil, "\(state) should not offer Stop Waiting")
        }
    }
}

/// KTD12/R10: Try Again is one handler with two branches, and the announcement it can
/// trigger speaks once per handoff rather than once per press.
@Suite(.sharedAppState) struct SetupSessionTryAgainTests {
    @MainActor @Test func tryAgainFrontsTheTerminalAppAndResumesWhenAHandoffIsOpen() {
        let account = ProviderAccount.builtIn(for: .claude)
        var activated: [String] = []
        let original = SetupSessions.activateApplication
        defer { SetupSessions.activateApplication = original }
        SetupSessions.activateApplication = { identifier in
            activated.append(identifier)
            return true
        }
        SetupSessions.noteHandoffTerminalApp("com.apple.Terminal", for: account.key)
        defer { SetupSessions.noteHandoffTerminalApp(nil, for: account.key) }

        // KTD12: with the window still open Try Again fronts it and resumes; it never
        // stages a second handoff for the same account. The route is passed in because the
        // coordinator that would decide it is process-wide shared state in this target.
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: true, purpose: .setup)
            == .showTerminalAndResume)
        SetupSessions.tryAgain(for: account, route: .showTerminalAndResume, onRetry: {})
        #expect(activated == ["com.apple.Terminal"])
    }

    /// R10: with no handoff open Try Again starts a fresh one, of the purpose the session
    /// was already running — an approval restarts as an approval, not as a sign-in.
    @MainActor @Test func tryAgainStartsAFreshHandoffWhenNoneIsOpen() {
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: .setup)
            == .startNewHandoff(.setup))
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: .trust)
            == .startNewHandoff(.trust))
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: nil)
            == .startNewHandoff(.setup))
    }

    /// R14: with no handler recorded nothing is fronted, and no handoff is begun or restaged.
    @MainActor @Test func showTerminalIsSilentWithNoRecordedHandler() {
        let account = ProviderAccount(
            id: AccountID("claude-no-handler"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        let original = SetupSessions.activateApplication
        defer { SetupSessions.activateApplication = original }
        var activations = 0
        SetupSessions.activateApplication = { _ in
            activations += 1
            return true
        }
        #expect(!SetupSessions.showTerminal(for: account))
        #expect(activations == 0)
    }

    /// KTD12: a timeout, Try Again, timeout sequence announces the sentence once. The dedupe
    /// used to clear whenever the state left `.failed`, which Try Again does on every press.
    @MainActor @Test func aTryAgainLoopAnnouncesTheTimeoutOnce() {
        var announcer = SetupFailureAnnouncer()
        let key = AccountKey(providerID: .claude, accountID: .primary)

        let firstTimeout = announcer.shouldAnnounce(.waitingTimedOut, for: key, hasActiveHandoff: true)
        // Try Again returns the session to `.waiting` with the same window still open.
        let duringResume = announcer.shouldAnnounce(nil, for: key, hasActiveHandoff: true)
        let secondTimeout = announcer.shouldAnnounce(.waitingTimedOut, for: key, hasActiveHandoff: true)
        // A genuinely different failure is never silenced.
        let differentFailure = announcer.shouldAnnounce(.closedBeforeSignIn, for: key, hasActiveHandoff: true)
        // Once the handoff ends the claim is released, so a later handoff speaks again.
        let afterHandoffEnded = announcer.shouldAnnounce(nil, for: key, hasActiveHandoff: false)
        let laterHandoff = announcer.shouldAnnounce(.waitingTimedOut, for: key, hasActiveHandoff: true)

        #expect(firstTimeout)
        #expect(!duringResume)
        #expect(!secondTimeout)
        #expect(differentFailure)
        #expect(!afterHandoffEnded)
        #expect(laterHandoff)
    }
}

/// R2B1/R2C6/KTD12: `SetupSessions.failureMessage` lives in the app target, so the copy rules
/// Core enforces on `ProviderSetupOutcome` are asserted for it here.
@Suite(.sharedAppState) struct SetupFailureCopyTests {
    private let accounts: [ProviderAccount] = [
        .builtIn(for: .claude), .builtIn(for: .codex), .builtIn(for: .grok), .builtIn(for: .cursor),
    ]
    private let failures: [SetupSessionFailure] = [
        .executableMissing, .updateRequired, .stagingFailed, .terminalRejected,
        .pasteboardFailed, .retryExhausted, .waitingTimedOut, .closedBeforeSignIn,
        .provider(.claudeLoginRequired), .providerCapability(.confirmedAbsent),
        .providerCapability(.inconclusive(.shellTimeout)),
    ]

    @MainActor private var allStrings: [String] {
        var strings: [String] = []
        for account in accounts {
            for failure in failures {
                for purpose in [SetupHandoffPurpose.setup, .reset, .trust, .approval] {
                    for reason in ClaudeInteractiveLaunchReason.allCases.map(Optional.some) + [nil] {
                        strings.append(SetupSessions.failureMessage(
                            for: failure,
                            account: account,
                            purpose: purpose,
                            interactiveReason: reason
                        ))
                    }
                }
                if let detail = SetupSessions.failureDetail(for: failure) {
                    strings.append(detail)
                }
            }
        }
        return strings
    }

    @MainActor @Test func everyFailureSentenceUsesCurlyApostrophesAndNonBreakingDashes() {
        for text in allStrings {
            #expect(!text.isEmpty)
            #expect(!text.contains("'"), "\(text) carries a straight apostrophe")
            let characters = Array(text)
            for (index, character) in characters.enumerated() where character == "\u{2014}" {
                #expect(index > 0 && characters[index - 1] == "\u{00A0}",
                        "\(text) has a breaking space before its em dash")
                #expect(index + 1 < characters.count && characters[index + 1] == "\u{00A0}",
                        "\(text) has a breaking space after its em dash")
            }
        }
    }

    /// R2C6: "connect" is not a word for signing in. PA11: "Check Again" and "Refresh" are
    /// not words for a forced poll.
    @MainActor @Test func noFailureSentenceUsesARetiredSynonym() {
        for text in allStrings {
            #expect(!text.localizedCaseInsensitiveContains("connect"),
                    "\(text) still names signing in \"connect\"")
            #expect(!text.localizedCaseInsensitiveContains("Check Again"))
            #expect(!text.localizedCaseInsensitiveContains("Refresh"))
        }
    }

    /// KTD12: the timeout state offers Try Again and Stop Waiting only, so its sentence must
    /// not point at a button that is not there. `.retryExhausted` keeps its Check Now,
    /// because the providers that still reach it keep that chip.
    @MainActor @Test func theTimeoutSentenceNamesNoButtonAbsentFromItsState() {
        let account = ProviderAccount.builtIn(for: .claude)
        let present = Set(claudeWaitingCardActions(
            state: .failed(.waitingTimedOut),
            hasActiveHandoff: true
        ).map(\.label) + ["Stop Waiting"])
        let absent = ["Check Now", "Sign In", "Sign In Again", "Show Terminal",
                      "Continue Setup", "Open Claude Workspace"]
        for (purpose, reason) in [(SetupHandoffPurpose.setup, ClaudeInteractiveLaunchReason?.none),
                                  (.reset, nil), (.trust, nil), (.trust, .startupQuestion)] {
            let message = SetupSessions.failureMessage(
                for: .waitingTimedOut,
                account: account,
                purpose: purpose,
                interactiveReason: reason
            )
            let detail = SetupSessions.failureDetail(for: .waitingTimedOut) ?? ""
            for label in absent {
                #expect(!message.localizedCaseInsensitiveContains(label),
                        "the timeout sentence names \(label), which is not in its state")
                #expect(!detail.localizedCaseInsensitiveContains(label))
            }
            // The sentence states the cause; the detail may point only at what is on screen.
            #expect(!message.localizedCaseInsensitiveContains("try again"))
            #expect(present.contains("Try Again"))
        }
        #expect(SetupSessions.failureMessage(
            for: .retryExhausted,
            account: .builtIn(for: .codex),
            purpose: .setup
        ).contains("Check Now"))
    }

    /// KTD12: only the timeout carries a second line, and only because its window is still
    /// open — the fact a one-line sentence cannot hold.
    @MainActor @Test func onlyTheTimeoutCarriesASecondLine() {
        for failure in failures where failure != .waitingTimedOut {
            #expect(SetupSessions.failureDetail(for: failure) == nil, "\(failure)")
        }
        #expect(SetupSessions.failureDetail(for: .waitingTimedOut)
            == "Terminal is still open. Finish there, or try again to keep waiting.")
    }
}

// MARK: - Remembered rows (default-login plan U7, KTD8)

/// Returns whatever reading the test set; never touches a CLI.
private final class RememberedRowTestProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .codex
    let displayName = "Codex"
    private let lock = NSLock()
    private var snapshot: UsageSnapshot = .pending(for: .codex)

    func set(_ snapshot: UsageSnapshot) { lock.withLock { self.snapshot = snapshot } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { snapshot } }
}

/// Counts the phone captures the store submits (U8: a rename must reach the phone path).
@MainActor
private final class RememberedRowPhoneSpy: CompanionPhoneSyncing {
    private(set) var captures: [CompanionPublishCapture] = []
    func submit(_ capture: CompanionPublishCapture) { captures.append(capture) }
}

/// A Codex built-in whose default login moved from one account to another, so the store
/// keeps the first as a remembered row. Real registry and record store on a throwaway suite.
@MainActor
private struct RememberedRowFixture {
    static let first = "aaaaaaaa-0000-4000-8000-000000000001"
    static let second = "bbbbbbbb-0000-4000-8000-000000000002"

    let defaults: UserDefaults
    let registry: AccountRegistry
    let provider = RememberedRowTestProvider()
    let phoneSync = RememberedRowPhoneSpy()
    let store: UsageStore

    init() {
        let suite = "headroom.remembered-rows.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        self.defaults = defaults
        registry = AccountRegistry(defaults: defaults)
        let provider = self.provider
        store = UsageStore(
            providers: [provider],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: DemoAccountStorage(),
            providerFactory: { _ in provider },
            defaultLoginRecords: DefaultLoginRecordStore(defaults: defaults),
            phoneSyncExporter: phoneSync
        )
    }

    func reading(_ account: String, used: Double) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: used, resetsAt: Date().addingTimeInterval(5 * 86_400))],
            planLabel: "plus", accountEmail: "\(account)@example.com",
            capturedAt: Date(), freshness: .live,
            identity: .known(AccountIdentity.codex(accountID: account)!)
        )
    }

    func read(_ account: String, used: Double = 10) async {
        provider.set(reading(account, used: used))
        await store.refreshAll()
    }

    /// Reads the first account, renames the row "Work", then moves the login on.
    func switchAway() async -> DisplayAccount {
        await read(Self.first, used: 90)
        store.renameAccount(AccountKey(providerID: .codex, accountID: .primary), to: "Work")
        await read(Self.second, used: 3)
        return store.displayAccounts(for: .codex).first { $0.isRemembered }!
    }
}

@MainActor
@Suite(.sharedAppState, .serialized)
struct RememberedRowInteractionTests {
    private let builtInKey = AccountKey(providerID: .codex, accountID: .primary)

    @Test func makeMainSignOutAndSetupAreNotOfferedForARememberedRow() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        let main = fixture.store.displayAccounts(for: .codex)[0]

        #expect(AccountsSettingsInteractions.promotionState(for: row, in: fixture.store) == .unavailable)
        #expect(AccountsSettingsInteractions.promotionState(for: main, in: fixture.store) == .primary)
        #expect(AccountsSettingsInteractions.builtInRowActions(for: row.account, in: fixture.store) == .unavailable)
        #expect(AccountsSettingsInteractions.resetBuiltIn(row.account, in: fixture.store, beginReset: { _ in
            Issue.record("A remembered row must not start a reset")
        }) == false)
        #expect(AccountsSettingsInteractions.recoveryRowActions(
            snapshot: fixture.store.snapshot(for: row.key), account: row.account
        ) == nil)
        #expect(AccountsSettingsInteractions.makeMain(row.account, in: fixture.store) == nil)
        #expect(fixture.store.displayPrimaryKey(for: .codex) == builtInKey)
    }

    @Test func renamingARememberedRowInSettingsWritesTheRecordStoreNotTheRegistry() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        let registryBefore = fixture.defaults.data(forKey: "providerAccounts.v1")

        let pending = AccountsSettingsInteractions.pendingLabelCommits(
            drafts: [row.key: "Esper Labs"], rows: fixture.store.displayAccounts(for: .codex)
        )
        #expect(pending.map(\.key) == [row.key])
        #expect(AccountsSettingsInteractions.commitLabel("  Esper Labs ", for: row, in: fixture.store))

        #expect(fixture.defaults.data(forKey: "providerAccounts.v1") == registryBefore)
        #expect(fixture.store.accounts(for: .codex).map(\.label) == ["Main"])
        #expect(fixture.store.displayAccounts(for: .codex).map(\.label) == ["Main", "Esper Labs"])
        // An unchanged draft commits nothing.
        let renamed = fixture.store.displayAccounts(for: .codex)[1]
        #expect(AccountsSettingsInteractions.commitLabel("Esper Labs", for: renamed, in: fixture.store) == false)
    }

    @Test func removingARememberedRowInSettingsHidesItWithoutATombstone() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()

        #expect(await AccountsSettingsInteractions.removeAccount(row, from: fixture.store) == .removed)

        #expect(fixture.store.displayAccounts(for: .codex).map(\.key) == [builtInKey])
        #expect(fixture.store.isBuiltInTrackingStopped(for: .codex) == false)
        #expect(fixture.store.accounts(for: .codex).map(\.key) == [builtInKey])
        #expect(fixture.store.rememberedAccounts(for: .codex, includingHidden: true).map(\.isHidden) == [true])
    }

    /// Stop-tracking the built-in needs an engine extra; a remembered row is not one.
    @Test func stopTrackingIsNotOfferedWhenOnlyARememberedRowSitsBesideTheBuiltIn() async {
        let fixture = RememberedRowFixture()
        _ = await fixture.switchAway()
        let main = fixture.store.displayAccounts(for: .codex)[0]
        #expect(AccountsSettingsInteractions.builtInRowActions(for: main.account, in: fixture.store) == .resetOnly)
    }

    /// The popover's card rows follow the engine rows, and the row's appearance is one
    /// account-set change for the column plan; a steady reading after it is none.
    @Test func aRememberedRowJoinsThePopoverCardAndReplansOnce() async {
        let fixture = RememberedRowFixture()
        await fixture.read(RememberedRowFixture.first, used: 90)
        let slots = {
            ProviderCardView.columnSlots(
                providerID: .codex,
                entries: PopoverView.accountEntries(for: .codex, in: fixture.store),
                capabilityStatus: nil
            )
        }
        let before = slots()
        #expect(before.count == 1)

        await fixture.read(RememberedRowFixture.second, used: 3)
        let entries = PopoverView.accountEntries(for: .codex, in: fixture.store)
        #expect(entries.map(\.kind) == [.engine, .remembered])
        #expect(entries.map(\.account.key)[0] == builtInKey)
        #expect(entries[1].snapshot.freshness != .live)
        let after = slots()
        #expect(after != before)
        #expect(after.map(\.id) == entries.map(\.account.key.description))

        await fixture.read(RememberedRowFixture.second, used: 4)
        #expect(slots() == after)
    }

    /// AE5: with no remembered row the popover's entries are the engine list exactly.
    @Test func withoutARememberedRowThePopoverEntriesAreTheEngineRows() async {
        let fixture = RememberedRowFixture()
        await fixture.read(RememberedRowFixture.first)
        await fixture.read(RememberedRowFixture.first, used: 20)
        let entries = PopoverView.accountEntries(for: .codex, in: fixture.store)
        #expect(entries.map(\.account) == fixture.store.accounts(for: .codex))
        #expect(entries.allSatisfy { !$0.isRemembered })
        #expect(entries.allSatisfy { $0.lastReadAt == nil })
    }

    // MARK: U8

    /// The popover entry carries the remembered row's last-read time, so the row draws its
    /// tag without a store read of its own; the engine row carries none.
    @Test func thePopoverEntryCarriesTheRememberedRowsLastReadTime() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        let entries = PopoverView.accountEntries(for: .codex, in: fixture.store)
        let summary = fixture.store.rememberedAccounts(for: .codex).first { $0.key == row.key }
        #expect(summary?.lastReadAt != nil)
        #expect(entries.map(\.lastReadAt) == [nil, summary?.lastReadAt])
    }

    /// Rename reaches every place the row's name shows: the popover's entry, the footer
    /// receipt, and the phone path (a fresh capture is submitted; whether the phone lists
    /// remembered rows is U9's, KTD14).
    @Test func renamingARememberedRowUpdatesThePopoverTheReceiptAndThePhonePath() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        let capturesBefore = fixture.phoneSync.captures.count

        #expect(AccountsSettingsInteractions.commitLabel("Esper Labs", for: row, in: fixture.store))

        let entries = PopoverView.accountEntries(for: .codex, in: fixture.store)
        #expect(entries.first { $0.account.key == row.key }?.account.label == "Esper Labs")
        #expect(fixture.store.desktopAccountName(for: entries[1].account) == "Esper Labs")
        #expect(fixture.store.refreshReceiptTitle(for: row.key).hasSuffix("Esper Labs"))
        #expect(fixture.phoneSync.captures.count > capturesBefore)
    }

    /// R11: Remove only hides it. The dialog says so in plain words, its button is not
    /// destructive, and the row leaves every display list with no registry tombstone.
    @Test func removingARememberedRowSaysItStaysHiddenAndDeletesNothing() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        let registryBefore = fixture.defaults.data(forKey: "providerAccounts.v1")

        #expect(AccountsSettingsInteractions.removalDialogTitle(for: row) == "Remove this account?")
        let message = AccountsSettingsInteractions.removalDialogMessage(for: row)
        #expect(message == "It stays hidden until your CLI is signed in to this account again. Nothing is deleted.")
        #expect(AccountsSettingsInteractions.removalIsDestructive(for: row) == false)

        #expect(await AccountsSettingsInteractions.removeAccount(row, from: fixture.store) == .removed)
        #expect(!fixture.store.displayAccounts(for: .codex).contains { $0.key == row.key })
        #expect(PopoverView.accountEntries(for: .codex, in: fixture.store).allSatisfy { !$0.isRemembered })
        #expect(fixture.store.isBuiltInTrackingStopped(for: .codex) == false)
        #expect(fixture.defaults.data(forKey: "providerAccounts.v1") == registryBefore)
    }

    /// The engine rows' dialogs keep their own words.
    @Test func engineRowRemovalDialogsAreUnchanged() async {
        let fixture = RememberedRowFixture()
        _ = await fixture.switchAway()
        let builtIn = fixture.store.displayAccounts(for: .codex)[0]
        let extra = DisplayAccount(
            account: ProviderAccount(id: AccountID("extra"), providerID: .codex, label: "Extra"), kind: .engine
        )
        #expect(AccountsSettingsInteractions.removalDialogTitle(for: builtIn) == "Stop tracking this account?")
        #expect(AccountsSettingsInteractions.removalDialogMessage(for: builtIn)
            == "Headroom stops showing it. Your CLI stays signed in — nothing on this Mac is deleted.")
        #expect(AccountsSettingsInteractions.removalIsDestructive(for: builtIn) == false)
        #expect(AccountsSettingsInteractions.removalDialogTitle(for: extra) == "Remove this account?")
        #expect(AccountsSettingsInteractions.removalDialogMessage(for: extra)
            == "Its sign-in on this Mac is deleted with it. Your subscription is untouched.")
        #expect(AccountsSettingsInteractions.removalIsDestructive(for: extra))
    }

    /// R7: Settings prints the popover's own tag as the row's status line.
    @Test func theSettingsStatusLineSaysWhenTheRowWasLastRead() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        let summary = fixture.store.rememberedAccounts(for: .codex).first { $0.key == row.key }!
        let status = AccountsSettingsInteractions.rememberedStatus(
            lastReadAt: summary.lastReadAt,
            snapshot: fixture.store.snapshot(for: row.key),
            now: summary.lastReadAt!.addingTimeInterval(120)
        )
        #expect(status == "Last read 2 min ago")
        #expect(AccountsSettingsInteractions.rememberedStatusHelp.contains("Add Account"))
    }

    /// R12: no Make Main, no Sign Out & Set Up Again, no sign-in or Try Again — in Settings
    /// and on the popover row.
    @Test func aRememberedRowOffersNoMakeMainSignOutOrTryAgain() async {
        let fixture = RememberedRowFixture()
        let row = await fixture.switchAway()
        #expect(AccountsSettingsInteractions.promotionState(for: row, in: fixture.store) == .unavailable)
        #expect(AccountsSettingsInteractions.builtInRowActions(for: row.account, in: fixture.store) == .unavailable)
        #expect(AccountsSettingsInteractions.recoveryRowActions(
            snapshot: fixture.store.snapshot(for: row.key), account: row.account
        ) == nil)
        let entry = PopoverView.accountEntries(for: .codex, in: fixture.store)[1]
        #expect(entry.isRemembered)
        #expect(entry.kind.offersRetry == false)
        #expect(row.kind.offersRetry == false)
    }
}

// MARK: - One account, one row (default-login plan U10)

private final class MergedRowTestProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .codex
    let accountID: AccountID
    let displayName = "Codex"
    private let lock = NSLock()
    private var snapshot: UsageSnapshot = .pending(for: .codex)

    init(accountID: AccountID) { self.accountID = accountID }

    func set(_ snapshot: UsageSnapshot) { lock.withLock { self.snapshot = snapshot } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { snapshot } }
}

/// Mock scenario B: the Codex built-in "Esper Labs" reads the work account, "Account 2"
/// has its own sign-in to gmail, and the default login then moves to gmail.
@MainActor
private struct MergedRowFixture {
    static let work = "aaaaaaaa-0000-4000-8000-000000000001"
    static let gmail = "bbbbbbbb-0000-4000-8000-000000000002"

    let builtIn = MergedRowTestProvider(accountID: .primary)
    let extra: MergedRowTestProvider
    let extraAccount: ProviderAccount
    let store: UsageStore

    init() {
        let suite = "headroom.merged-rows.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let registry = AccountRegistry(defaults: defaults)
        let extraAccount = registry.addAccount(for: .codex, label: "Account 2")!
        self.extraAccount = extraAccount
        let extra = MergedRowTestProvider(accountID: extraAccount.id)
        self.extra = extra
        let builtIn = self.builtIn
        store = UsageStore(
            providers: [builtIn, extra],
            preferences: Preferences(defaults: defaults),
            accountRegistry: registry,
            accountStorage: DemoAccountStorage(),
            providerFactory: { account in account.isBuiltIn ? builtIn : extra },
            defaultLoginRecords: DefaultLoginRecordStore(defaults: defaults)
        )
    }

    static func reading(_ account: String, used: Double) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: [UsageWindow(kind: .weekly, utilization: used, resetsAt: Date().addingTimeInterval(5 * 86_400))],
            planLabel: "plus", accountEmail: "\(account)@example.com",
            capturedAt: Date(), freshness: .live,
            identity: .known(AccountIdentity.codex(accountID: account)!)
        )
    }

    func merge() async {
        extra.set(Self.reading(Self.gmail, used: 31))
        builtIn.set(Self.reading(Self.work, used: 90))
        await store.refreshAll()
        store.renameAccount(AccountKey(providerID: .codex, accountID: .primary), to: "Esper Labs")
        builtIn.set(Self.reading(Self.gmail, used: 31))
        await store.refreshAll()
    }
}

@MainActor
@Suite(.sharedAppState, .serialized)
struct MergedRowInteractionTests {
    private let builtInKey = AccountKey(providerID: .codex, accountID: .primary)

    /// U10: Settings lists the merged pair as one row, "Account 2", with its own actions:
    /// it carries the Main badge and is not offered Make Main.
    @Test func theMergedPairIsOneRowWithTheExtrasActions() async {
        let fixture = MergedRowFixture()
        await fixture.merge()
        let rows = fixture.store.displayAccounts(for: .codex)
        #expect(rows.map(\.label) == ["Account 2", "Esper Labs"])
        let merged = rows[0]
        #expect(merged.key == fixture.extraAccount.key)
        #expect(merged.account.isBuiltIn == false)
        #expect(AccountsSettingsInteractions.promotionState(for: merged, in: fixture.store) == .primary)
        #expect(AccountsSettingsInteractions.makeMain(merged.account, in: fixture.store) == nil)
        // The popover card draws the same rows.
        #expect(PopoverView.accountEntries(for: .codex, in: fixture.store).map(\.account.key) == rows.map(\.key))
    }

    /// U10: the built-in's Sign Out & Set Up Again and stop-tracking stay reachable from the
    /// provider header while its row is merged away, and starting the reset shows the row.
    @Test func theProviderHeaderOffersTheMergedBuiltInsActions() async throws {
        let fixture = MergedRowFixture()
        #expect(AccountsSettingsInteractions.mergedBuiltIn(for: .codex, in: fixture.store) == nil)
        #expect(AccountsSettingsInteractions.mergedBuiltInActions(for: .codex, in: fixture.store) == .unavailable)

        await fixture.merge()
        let builtIn = try #require(AccountsSettingsInteractions.mergedBuiltIn(for: .codex, in: fixture.store))
        #expect(builtIn.key == builtInKey)
        #expect(AccountsSettingsInteractions.mergedBuiltInActions(for: .codex, in: fixture.store) == .resetAndStopTracking)

        var reset: ProviderAccount?
        let started = AccountsSettingsInteractions.resetBuiltIn(builtIn, in: fixture.store, beginReset: { reset = $0 })
        #expect(started)
        #expect(reset?.key == builtInKey)

        #expect(await AccountsSettingsInteractions.removeAccount(
            DisplayAccount(account: builtIn, kind: .engine), from: fixture.store
        ) == .removed)
        #expect(fixture.store.isBuiltInTrackingStopped(for: .codex))
        #expect(fixture.store.displayAccounts(for: .codex).map(\.label) == ["Account 2", "Esper Labs"])
        #expect(AccountsSettingsInteractions.mergedBuiltIn(for: .codex, in: fixture.store) == nil)
        #expect(fixture.store.displayProjection(for: .codex).mergeMap.isEmpty)
    }

    /// Covers AE5: two accounts kept apart on purpose draw as before, with no header menu.
    @Test func twoSeparateAccountsDrawAsBefore() async {
        let fixture = MergedRowFixture()
        fixture.extra.set(MergedRowFixture.reading(MergedRowFixture.gmail, used: 31))
        fixture.builtIn.set(MergedRowFixture.reading(MergedRowFixture.work, used: 90))
        await fixture.store.refreshAll()
        #expect(fixture.store.displayAccounts(for: .codex).map(\.account) == fixture.store.accounts(for: .codex))
        #expect(AccountsSettingsInteractions.mergedBuiltInActions(for: .codex, in: fixture.store) == .unavailable)
    }
}
