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
        #expect(off.offHelpText == "Not fetched while this provider is off.")
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
        #expect(presentation.addAction.helpText == "Turn Grok on to add an account.")
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
        #expect(full.addAction.helpText == "Up to 5 accounts per provider")

        let fullAndOn = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: "Grok",
            accounts: [ProviderAccount.builtIn(for: .grok)],
            capacity: 5,
            hasFreeAccountSlot: false,
            isSurfaceEnabled: true,
            hasActiveHandoff: { _ in false }
        )
        #expect(!fullAndOn.addAction.isEnabled)
        #expect(fullAndOn.addAction.helpText == "Up to 5 accounts per provider")
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
        #expect(midHandoffOff.addAction.helpText == "Turn Grok on to add an account.")
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

        #expect(presentation?.recovery.primaryLabel == "Check again")
        #expect(presentation?.recovery.primaryAction == .checkNow)
        #expect(presentation?.recovery.secondaryLabel == "Open guided setup")
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
        #expect(actions?.secondaryLabel == "Use device code")
        #expect(actions?.secondaryAccessibilityLabel == "Use device code for Work")
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
            #expect(actions?.secondaryLabel == "Use device code")
            #expect(actions?.secondaryAccessibilityLabel == "Use device code for \(account.label)")
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
        #expect(actions?.primaryLabel == "Check again")
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
            hasActiveHandoff: hasActiveHandoff
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

@Suite struct OpenHandoffRefusalPresentationTests {
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
        ) == "Claude Code availability. Couldn't confirm where Claude Code is — will retry")
        #expect(dedupe.announcement(for: .claude, state: .inconclusive(.shellTimeout)) == nil)
    }
}
