import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// Claude CLI discovery and manual-command recovery at the app boundary: what the
/// capability recovery row offers for each discovery state, and which executable the
/// staged handoff, clipboard fallback, and legacy script actually launch.
@Suite(.sharedAppState) struct ClaudeExecutableDiscoveryInteractionTests {
    /// A `.command` handler can acknowledge LaunchServices without actually running the
    /// script. Exercise the production orchestration seam so reverting `openPreparedHandoff`
    /// to the default handler makes this test fail.
    @MainActor @Test func preparedHandoffTargetsSystemTerminalAndPersistsItsHost() async throws {
        let account = ProviderAccount(
            id: AccountID("terminal-success-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Terminal success",
            isBuiltIn: false
        )
        let workspace = temporaryWorkspace()
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        defer {
            SetupSessions.forceCancel(for: account)
            try? AccountStorage.removeDirectories(for: account)
            try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent())
        }
        let staging = await stageClaudeHandoff(
            for: account,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.300 (Claude Code)")
        )
        let handoff = try #require(staging.handoff)
        let prepared = try #require(staging.staged)
        var resolvedBundleIdentifiers: [String] = []
        var openCalls: [(script: URL, application: URL)] = []

        let result = await SetupSessions.openPreparedHandoff(
            handoff,
            resolveTerminalApplication: { bundleIdentifier in
                resolvedBundleIdentifiers.append(bundleIdentifier)
                return terminalURL
            },
            openScript: { script, application in
                openCalls.append((script, application))
                return true
            },
            copy: { _ in
                Issue.record("A successful Terminal handoff must not use the clipboard fallback")
                return false
            }
        )

        guard case .success = result else {
            Issue.record("Expected the prepared handoff to open successfully")
            return
        }
        #expect(resolvedBundleIdentifiers == ["com.apple.Terminal"])
        #expect(openCalls.count == 1)
        #expect(openCalls.first?.script == prepared.scriptURL)
        #expect(openCalls.first?.application == terminalURL)
        #expect(SetupSessions.handoffTerminalApp(for: account.key) == "com.apple.Terminal")
        #expect(AccountStorage.setupHandoffRecord(marker: prepared.completionMarker)?
            .terminalBundleIdentifier == "com.apple.Terminal")
    }

    @MainActor @Test func unavailableTerminalClearsStagingAndReportsPasteboardFailure() async throws {
        let account = ProviderAccount(
            id: AccountID("terminal-unavailable-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Terminal unavailable",
            isBuiltIn: false
        )
        let workspace = temporaryWorkspace()
        defer {
            try? AccountStorage.removeDirectories(for: account)
            try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent())
        }
        let staging = await stageClaudeHandoff(
            for: account,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.300 (Claude Code)")
        )
        let handoff = try #require(staging.handoff)
        let prepared = try #require(staging.staged)

        let result = await SetupSessions.openPreparedHandoff(
            handoff,
            resolveTerminalApplication: { _ in nil },
            openScript: { _, _ in
                Issue.record("Terminal open must not run when resolution fails")
                return true
            },
            copy: { _ in false }
        )

        guard case .failure(.pasteboardFailed) = result else {
            Issue.record("Expected pasteboardFailed when Terminal is unavailable and copy fails")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: prepared.scriptURL.path))
        #expect(!AccountStorage.setupHandoffIsActive(marker: prepared.completionMarker))
    }

    @MainActor @Test func rejectedTerminalOpenClearsStagingAndCopiesManualCommand() async throws {
        let account = ProviderAccount(
            id: AccountID("terminal-rejected-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Terminal rejected",
            isBuiltIn: false
        )
        let workspace = temporaryWorkspace()
        defer {
            try? AccountStorage.removeDirectories(for: account)
            try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent())
        }
        let staging = await stageClaudeHandoff(
            for: account,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.300 (Claude Code)")
        )
        let handoff = try #require(staging.handoff)
        let prepared = try #require(staging.staged)
        var copiedCommands: [String] = []

        let result = await SetupSessions.openPreparedHandoff(
            handoff,
            resolveTerminalApplication: { _ in
                URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            },
            openScript: { script, _ in
                #expect(script == prepared.scriptURL)
                return false
            },
            copy: { command in
                copiedCommands.append(command)
                return true
            }
        )

        guard case .failure(.terminalRejected) = result else {
            Issue.record("Expected terminalRejected when Terminal refuses the staged script")
            return
        }
        #expect(copiedCommands == [prepared.manualCommand])
        #expect(!FileManager.default.fileExists(atPath: prepared.scriptURL.path))
        #expect(!AccountStorage.setupHandoffIsActive(marker: prepared.completionMarker))
    }

    @MainActor @Test func forceCancelDuringTerminalLaunchDoesNotRestoreTheStaleHandoff() async throws {
        let account = ProviderAccount(
            id: AccountID("terminal-cancelled-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Terminal cancelled",
            isBuiltIn: false
        )
        let workspace = temporaryWorkspace()
        let gate = HandoffOpenGate()
        defer {
            SetupSessions.forceCancel(for: account)
            try? AccountStorage.removeDirectories(for: account)
            try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent())
        }
        let staging = await stageClaudeHandoff(
            for: account,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.300 (Claude Code)")
        )
        let handoff = try #require(staging.handoff)
        let prepared = try #require(staging.staged)

        let opening = Task { @MainActor in
            await SetupSessions.openPreparedHandoff(
                handoff,
                resolveTerminalApplication: { _ in
                    URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                },
                openScript: { _, _ in await gate.open() },
                copy: { _ in
                    Issue.record("Cancellation must own cleanup without a clipboard fallback")
                    return true
                }
            )
        }
        await gate.waitUntilStarted()
        SetupSessions.forceCancel(for: account)
        await gate.release()
        let result = await opening.value

        guard case .failure(.terminalRejected) = result else {
            Issue.record("Expected the stale launch result to be rejected after cancellation")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: prepared.scriptURL.path))
        #expect(!AccountStorage.setupHandoffIsActive(marker: prepared.completionMarker))
        #expect(SetupSessions.handoffTerminalApp(for: account.key) == nil)
    }

    /// AE5: confirmed absence routes to installation guidance plus a forced discovery
    /// check, with an accessibility label for each offered action.
    @MainActor @Test func confirmedAbsenceOffersInstallAndCheckAgainWithLabelledActions() {
        let presentation = capabilityRecoveryPresentation(
            state: .confirmedAbsent,
            hasActiveSetupSession: false
        )
        let recovery = presentation?.recovery
        let actions = AccountsSettingsInteractions.RecoveryRowActions(
            presentation: ProviderSetupOutcome.claudeCLIMissing.recoveryPresentation,
            accountLabel: "Personal"
        )

        #expect(recovery?.primaryAction == .installClaudeCLI)
        #expect(recovery?.secondaryAction == .checkNow)
        #expect(SetupSessions.recoveryRoute(for: recovery!.primaryAction)
            == .documentation(URL(string: "https://code.claude.com/docs/en/installation")!))
        #expect(SetupSessions.recoveryRoute(for: recovery!.secondaryAction!) == .checkNow)
        #expect(actions.primaryAccessibilityLabel == "Install Claude Code for Personal")
        #expect(actions.secondaryAccessibilityLabel == "Check Now for Personal")
        #expect(actions.hasSecondaryAction)
    }

    /// AE7: incomplete discovery keeps Check Now + Open Guided Setup and never shows
    /// confirmed-absence installation copy.
    @MainActor @Test func inconclusiveDiscoveryKeepsRetryActionsWithoutInstallCopy() {
        for issue in [CLIExecutableDiscoveryIssue.shellTimeout, .npmPrefixUnresolved] {
            let recovery = capabilityRecoveryPresentation(
                state: .inconclusive(issue),
                hasActiveSetupSession: false
            )?.recovery
            #expect(recovery?.primaryAction == .checkNow)
            #expect(recovery?.secondaryAction == .openClaudeSetup)
            #expect(recovery?.primaryLabel == "Check Now")
            #expect(recovery?.secondaryLabel == "Open Guided Setup")
            #expect(recovery?.status.localizedCaseInsensitiveContains("install") == false)
        }
    }

    /// AE6: an npm-derived absolute launcher reaches the staged handoff and its clipboard
    /// fallback with the extra account's isolated `CLAUDE_CONFIG_DIR` and marker.
    @MainActor @Test func npmDerivedLauncherStagesExtraAccountHandoffAndAbsolutePathFallback() async throws {
        let launcher = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-npm-prefix-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("claude")
        let account = ProviderAccount(
            id: AccountID("npm-extra-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        defer { try? AccountStorage.removeDirectories(for: account) }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-npm-handoff-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(
                location: .available(path: launcher.path, source: .npmGlobalPrefix)
            )
        )

        guard case .success(let handoff) = result else {
            Issue.record("Expected preparation to succeed for an npm-derived launcher")
            return
        }
        let staged = try #require(SetupSessions.stagedHandoff(for: handoff.accountKey))
        let script = try String(contentsOf: staged.scriptURL, encoding: .utf8)
        let configDirectory = AccountStorage.claudeConfigDirectoryURL(for: account).path

        #expect(script.contains("'\(launcher.path)'"))
        #expect(script.contains("export CLAUDE_CONFIG_DIR='\(configDirectory)'"))
        #expect(script.contains("'\(staged.completionMarker.completedPath)'"))
        #expect(!script.contains("exec claude"))
        // KTD3 (2026-09-19 sign-in plan): the manual command routes through the exported
        // subshell form, so every command in it binds to this account's config home.
        #expect(staged.manualCommand.contains("(export CLAUDE_CONFIG_DIR='\(configDirectory)' && "))
        #expect(staged.manualCommand.hasSuffix("'\(launcher.path)')"))
        #expect(!staged.manualCommand.hasSuffix(" claude"))

        await SetupSessions.discardPreparedHandoff(handoff)
    }

    /// R6/KTD5: the legacy render-harness handoff launches the same validated absolute
    /// executable, so an npm-prefix or legacy install is not lost to a bare-name lookup
    /// against a hardcoded PATH.
    @MainActor @Test func legacyStagedScriptLaunchesTheResolvedAbsoluteExecutable() throws {
        let script = ClaudeSetupSession.script(
            for: .builtIn(for: .claude),
            workspacePath: "/tmp/work space",
            executablePath: "/Users/Test User/.npm-global/bin/claude"
        )

        #expect(script.contains("exec '/Users/Test User/.npm-global/bin/claude'"))
        #expect(!script.contains("command -v claude"))
        #expect(!script.contains("exec claude"))
        #expect(script.contains("cd '/tmp/work space'"))
        #expect(script.contains("$HOME/.claude/local"))
        try expectZshParses(script)
    }

    /// R7: with no resolved executable the legacy script shows install guidance instead of
    /// staging another bare lookup, and keeps extra-account config isolation.
    @MainActor @Test func legacyStagedScriptWithoutResolutionStagesNoBareLookup() throws {
        let account = ProviderAccount(
            id: AccountID("legacy-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        let script = ClaudeSetupSession.script(
            for: account,
            workspacePath: "/tmp/work space",
            executablePath: nil
        )
        let configDirectory = AccountStorage.claudeConfigDirectoryURL(for: account).path

        #expect(script.contains("Claude Code CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("exec claude"))
        #expect(!script.contains("command -v claude"))
        #expect(script.contains("export CLAUDE_CONFIG_DIR='\(configDirectory)'"))
        #expect(script.contains("$HOME/.claude/local"))
        try expectZshParses(script)
    }

    /// AE3/KTD5: the approval handoff reaches the trust purpose at the app boundary, while
    /// Sign In keeps the ordinary setup route.
    @MainActor @Test func claudeWorkspaceApprovalRoutesToTheTrustHandoff() {
        #expect(SetupSessions.recoveryRoute(for: .openClaudeWorkspace) == .workspaceTrust)
        #expect(SetupSessions.recoveryRoute(for: .openClaudeSetup) == .setup(.standard))
        #expect(ProviderSetupOutcome.claudeTrustRequired.recoveryPresentation.primaryAction
            == .openClaudeWorkspace)
    }

    /// KTD1: a built-in account on a current CLI signs in without the user typing anything,
    /// and the version read carries no config override, so it reads the CLI's own default.
    @MainActor @Test func currentBuiltInCLIStagesTheSignInScript() async throws {
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let versions = ClaudeVersionReaderSpy("2.1.217 (Claude Code)")

        let staging = await stageClaudeHandoff(
            for: .builtIn(for: .claude),
            workspace: workspace,
            versions: versions
        )

        #expect(staging.handoff?.claudeScriptKind == .signIn)
        #expect(staging.staged?.claudeScriptKind == .signIn)
        let script = try #require(staging.script)
        #expect(script.contains("auth login"))
        #expect(script.contains("auth status --json"))
        #expect(staging.staged?.manualCommand.contains("auth login") == true)
        #expect(await versions.environments == [[:]])
        await staging.discard()
    }

    /// KTD1: a reset keeps its own script on a current CLI — the sign-in guard would skip
    /// the sign-out the reset exists to perform.
    @MainActor @Test func resetKeepsItsResetScriptOnACurrentCLI() async throws {
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let staging = await stageClaudeHandoff(
            for: .builtIn(for: .claude),
            purpose: .reset,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.300 (Claude Code)")
        )

        let script = try #require(staging.script)
        #expect(script.contains("auth logout"))
        #expect(script.contains("auth login"))
        #expect(!script.contains("auth status --json"))
        await staging.discard()
    }

    /// AE7/KTD1: a never-onboarded extra account below the print-mode floor runs on the PTY
    /// path, where the bare launch shows the login selector and then the approval prompt in
    /// one Terminal trip. At the floor the same account stages the sign-in script. Both read
    /// the version through that account's own config home.
    @MainActor @Test func extraAccountBelowThePrintFloorStagesTheInteractiveLaunch() async throws {
        let account = ProviderAccount(
            id: AccountID("staging-extra-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        defer { try? AccountStorage.removeDirectories(for: account) }
        let configDirectory = AccountStorage.claudeConfigDirectoryURL(for: account).path

        for (version, expected) in [("2.1.100 (Claude Code)", ClaudeSetupScriptKind.interactive),
                                    ("2.1.217 (Claude Code)", .signIn)] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let versions = ClaudeVersionReaderSpy(version)

            let staging = await stageClaudeHandoff(
                for: account,
                workspace: workspace,
                versions: versions
            )

            #expect(staging.handoff?.claudeScriptKind == expected)
            // KTD11: the reason travels with the kind — it is what the waiting copy turns
            // on, and only the interactive launch has one.
            #expect(staging.staged?.claudeInteractiveReason
                == (expected == .interactive ? .neverOnboardedExtraAccount : nil))
            let script = try #require(staging.script)
            #expect(script.contains("auth login") == (expected == .signIn))
            #expect(await versions.environments == [["CLAUDE_CONFIG_DIR": configDirectory]])
            await staging.discard()
        }
    }

    /// AE7/KTD1: the print-mode floor gates extra accounts only. A built-in account below it
    /// has already been onboarded in the CLI's own config, so it stages the sign-in script.
    @MainActor @Test func builtInAccountBelowThePrintFloorStillStagesTheSignInScript() async throws {
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let staging = await stageClaudeHandoff(
            for: .builtIn(for: .claude),
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.100 (Claude Code)")
        )

        #expect(staging.handoff?.claudeScriptKind == .signIn)
        await staging.discard()
    }

    /// R6/KTD1: a readable version below 2.1.41 refuses the handoff for sign-in and reset
    /// alike — those CLIs can sign in and never be confirmed, because every usage check
    /// reads `auth status`. Nothing is staged, so nothing can be opened.
    @MainActor @Test func versionBelowTheSignInFloorRefusesWithoutStagingAScript() async {
        for purpose in [SetupHandoffPurpose.setup, .reset] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let account = ProviderAccount.builtIn(for: .claude)

            let staging = await stageClaudeHandoff(
                for: account,
                purpose: purpose,
                workspace: workspace,
                versions: ClaudeVersionReaderSpy("2.1.40 (Claude Code)")
            )

            #expect(staging.result == .failure(.updateRequired))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
            #expect(stagedScriptFiles(besideWorkspace: workspace).isEmpty)
        }
    }

    /// Review #1 (2026-09-19 sign-in review): a reset refused for a too-old CLI never opened
    /// a handoff, so the coordinator clears the session purpose — deliberately, so a settled
    /// failure cannot suppress ordinary polling. Try Again then read back `.setup` and
    /// started a plain sign-in against an account the reset never signed out, which the
    /// script's own guard reports as already signed in: Headroom called the old login
    /// connected and the user believed the reset had happened.
    @MainActor @Test func aRefusedResetIsRememberedSoTryAgainResumesTheReset() async {
        let account = refusalAccount()
        defer { try? AccountStorage.removeDirectories(for: account) }
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let staging = await stageClaudeHandoff(
            for: account,
            purpose: .reset,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.40 (Claude Code)")
        )

        #expect(staging.result == .failure(.updateRequired))
        #expect(SetupSessions.refusedHandoffPurpose(for: account) == .reset)

        let purpose = SetupSessions.tryAgainPurpose(
            sessionPurpose: nil,
            refusedPurpose: SetupSessions.refusedHandoffPurpose(for: account)
        )
        #expect(purpose == .reset)
        let route = SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: purpose)
        #expect(route == .startNewHandoff(.reset))
        #expect(SetupSessions.tryAgainAction(for: route) == .startReset)
        // The coordinator's own purpose still wins, and an open handoff never consults the
        // memo at all — it fronts the window that is already there.
        #expect(SetupSessions.tryAgainPurpose(sessionPurpose: .trust, refusedPurpose: .reset) == .trust)
        #expect(SetupSessions.tryAgainRoute(hasActiveHandoff: true, purpose: .reset)
            == .showTerminalAndResume)

        SetupSessions.forceCancel(for: account)
    }

    /// Review #1: the memo describes one refusal, so it must not outlive it — a later Try
    /// Again on an ordinary sign-in must never be turned into a sign-out.
    @MainActor @Test func aRememberedRefusalNeverOutlivesTheFailureItDescribes() async {
        let account = refusalAccount()
        defer { try? AccountStorage.removeDirectories(for: account) }

        for end in ["begin", "forceCancel", "settle"] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let staging = await stageClaudeHandoff(
                for: account,
                purpose: .reset,
                workspace: workspace,
                versions: ClaudeVersionReaderSpy("2.1.40 (Claude Code)")
            )
            #expect(staging.result == .failure(.updateRequired))
            #expect(SetupSessions.refusedHandoffPurpose(for: account) == .reset)

            switch end {
            case "begin": SetupSessions.noteHandoffBegan(for: account)
            case "forceCancel": SetupSessions.forceCancel(for: account)
            default: SetupSessions.settle(for: account)
            }

            #expect(SetupSessions.refusedHandoffPurpose(for: account) == nil,
                    "\(end) left the refused purpose behind")
            SetupSessions.forceCancel(for: account)
        }
    }

    /// A key no other test touches: the memo is per account and process-wide.
    private func refusalAccount() -> ProviderAccount {
        ProviderAccount(
            id: AccountID("refused-reset-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
    }

    /// R6: an unreadable version keeps today's interactive launch, so a change to the CLI's
    /// version format cannot lock every user out of sign-in.
    @MainActor @Test func unreadableVersionKeepsTheInteractiveLaunch() async throws {
        for version in [nil, "claude-code (unknown build)"] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }

            let staging = await stageClaudeHandoff(
                for: .builtIn(for: .claude),
                workspace: workspace,
                versions: ClaudeVersionReaderSpy(version)
            )

            #expect(staging.handoff?.claudeScriptKind == .interactive)
            // KTD11: `/login` guidance follows this reason, so an unreadable version must
            // not be staged as a never-onboarded extra account.
            #expect(staging.staged?.claudeInteractiveReason == .versionUnreadable)
            #expect(try #require(staging.script).contains("auth login") == false)
            await staging.discard()
        }
    }

    /// AE3/KTD1: the approval handoff stages the interactive launch at any version — the
    /// approval prompt only appears there, and the sign-in script's guard would exit on an
    /// account that is already signed in.
    @MainActor @Test func workspaceApprovalStagesTheInteractiveLaunchAtEveryVersion() async throws {
        for version in ["2.1.40 (Claude Code)", "2.1.100 (Claude Code)", "2.1.300 (Claude Code)"] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }

            let staging = await stageClaudeHandoff(
                for: .builtIn(for: .claude),
                purpose: .trust,
                workspace: workspace,
                versions: ClaudeVersionReaderSpy(version)
            )

            #expect(staging.handoff?.claudeScriptKind == .interactive)
            let script = try #require(staging.script)
            #expect(!script.contains("auth login"))
            #expect(!script.contains("auth logout"))
            await staging.discard()
        }
    }

    /// A startup question opens the same interactive launch an approval does, and the reason
    /// recorded when **Open Claude Code** was pressed lands in the prepared script (and from
    /// there the durable record). A plain approval keeps no reason, and a sign-in never
    /// borrows one left over from an earlier startup-question launch.
    @MainActor @Test func aStartupQuestionStagesTheInteractiveLaunchWithItsReason() async throws {
        let account = ProviderAccount.builtIn(for: .claude)
        defer { SetupSessions.noteRequestedTrustReason(nil, for: account.key) }

        for (requested, purpose, expectedKind, expectedReason) in [
            (ClaudeInteractiveLaunchReason.startupQuestion, SetupHandoffPurpose.trust,
             ClaudeSetupScriptKind.interactive, ClaudeInteractiveLaunchReason?.some(.startupQuestion)),
            (nil, .trust, .interactive, nil),
            (.startupQuestion, .setup, .signIn, nil),
        ] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            SetupSessions.noteRequestedTrustReason(requested, for: account.key)

            let staging = await stageClaudeHandoff(
                for: account,
                purpose: purpose,
                workspace: workspace,
                versions: ClaudeVersionReaderSpy("2.1.312 (Claude Code)")
            )

            #expect(staging.handoff?.claudeScriptKind == expectedKind)
            #expect(staging.staged?.claudeInteractiveReason == expectedReason)
            let script = try #require(staging.script)
            #expect(script.contains("auth login") == (expectedKind == .signIn))
            await staging.discard()
        }
    }

    /// **Open Claude Code** routes to the approval's launch; only the reason it records sets
    /// it apart. Try Again maps that reason back to the action that started it, so a timed-out
    /// startup question restarts as one and a plain approval stays an approval.
    @MainActor @Test func openClaudeCodeSharesTheTrustLaunchAndTryAgainKeepsItsReason() {
        #expect(SetupSessions.recoveryRoute(for: .answerClaudeQuestion) == .workspaceTrust)
        #expect(SetupSessions.trustLaunchReason(for: .answerClaudeQuestion) == .startupQuestion)
        for action in [SetupRecoveryAction.openClaudeWorkspace, .openCursorWorkspace] {
            #expect(SetupSessions.trustLaunchReason(for: action) == nil)
        }
        #expect(SetupSessions.workspaceTrustRecoveryAction(for: .startupQuestion) == .answerClaudeQuestion)
        #expect(SetupSessions.workspaceTrustRecoveryAction(for: nil) == .openClaudeWorkspace)

        let account = ProviderAccount(
            id: AccountID("claude-startup-question"), providerID: .claude, label: "Work", isBuiltIn: false
        )
        defer { SetupSessions.noteRequestedTrustReason(nil, for: account.key) }
        SetupSessions.noteRequestedTrustReason(.startupQuestion, for: account.key)
        let route = SetupSessions.tryAgainRoute(hasActiveHandoff: false, purpose: .trust)
        #expect(SetupSessions.tryAgainAction(for: route) == .startWorkspaceTrust)
        let retried = SetupSessions.workspaceTrustRecoveryAction(
            for: SetupSessions.requestedTrustReason(for: account.key)
        )
        #expect(retried == .answerClaudeQuestion)
        #expect(SetupSessions.trustLaunchReason(for: retried) == .startupQuestion)

        // The plain approval flow is unchanged: no reason, and Try Again reopens the workspace.
        SetupSessions.noteRequestedTrustReason(
            SetupSessions.trustLaunchReason(for: .openClaudeWorkspace), for: account.key
        )
        #expect(SetupSessions.requestedTrustReason(for: account.key) == nil)
        #expect(SetupSessions.workspaceTrustRecoveryAction(
            for: SetupSessions.requestedTrustReason(for: account.key)
        ) == .openClaudeWorkspace)
    }

    /// KTD5 of the 2026-08-12 plan: an unresolved executable still fails with the typed
    /// capability state and stages nothing, and the version gate never runs — there is no
    /// validated binary to ask.
    @MainActor @Test func unresolvedDiscoveryKeepsItsCapabilityFailuresAndSkipsTheVersionRead() async {
        let account = ProviderAccount.builtIn(for: .claude)
        let expectations: [(CLIExecutableLocation, SetupSessionFailure)] = [
            (.confirmedAbsent, .providerCapability(.confirmedAbsent)),
            (.inconclusive(.npmPrefixUnresolved), .providerCapability(.inconclusive(.npmPrefixUnresolved))),
        ]

        for (location, failure) in expectations {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let versions = ClaudeVersionReaderSpy("2.1.300 (Claude Code)")

            let result = await SetupSessions.prepareHandoff(
                for: account,
                mode: .standard,
                builtInClaudeWorkspace: workspace,
                claudeExecutableLocator: FixedExecutableLocator(location: location),
                claudeVersionReader: { path, overrides in
                    await versions.read(executablePath: path, environmentOverrides: overrides)
                }
            )

            #expect(result == .failure(failure))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
            #expect(await versions.executablePaths.isEmpty)
        }
    }

    private struct ClaudeStagingOutcome {
        let result: SetupPreparationResult
        let staged: SetupSessions.PreparedScript?
        let script: String?

        var handoff: PreparedSetupHandoff? {
            guard case .success(let handoff) = result else { return nil }
            return handoff
        }

        @MainActor func discard() async {
            guard let handoff else { return }
            await SetupSessions.discardPreparedHandoff(handoff)
        }
    }

    @MainActor private func stageClaudeHandoff(
        for account: ProviderAccount,
        purpose: SetupHandoffPurpose = .setup,
        workspace: URL,
        executablePath: String = "/opt/homebrew/bin/claude",
        versions: ClaudeVersionReaderSpy
    ) async -> ClaudeStagingOutcome {
        let result = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            purpose: purpose,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(
                location: .available(path: executablePath, source: .memoryHint)
            ),
            claudeVersionReader: { path, overrides in
                await versions.read(executablePath: path, environmentOverrides: overrides)
            }
        )
        let staged = SetupSessions.stagedHandoff(for: account.key)
        let script = staged.flatMap { try? String(contentsOf: $0.scriptURL, encoding: .utf8) }
        return ClaudeStagingOutcome(result: result, staged: staged, script: script)
    }

    private func temporaryWorkspace() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-staging-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    /// Staging writes its `.command` next to the workspace, so an empty listing is the
    /// evidence that a refusal wrote no script at all.
    private func stagedScriptFiles(besideWorkspace workspace: URL) -> [URL] {
        let setupDirectory = workspace
            .deletingLastPathComponent()
            .appendingPathComponent("Setup", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: setupDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "command" }
    }

    private func expectZshParses(_ script: String) throws {
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n"]
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    /// KTD5: unresolved discovery fails preparation, so no staged handoff — and therefore
    /// no Terminal-rejected clipboard fallback — can exist without a validated executable.
    @MainActor @Test func unresolvedDiscoveryStagesNoHandoffForTheClipboardFallback() async {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-unresolved-handoff-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let account = ProviderAccount.builtIn(for: .claude)

        for location in [CLIExecutableLocation.confirmedAbsent, .inconclusive(.npmPrefixUnresolved)] {
            let result = await SetupSessions.prepareHandoff(
                for: account,
                mode: .standard,
                builtInClaudeWorkspace: workspace,
                claudeExecutableLocator: FixedExecutableLocator(location: location)
            )
            #expect(result != .success(PreparedSetupHandoff(accountKey: account.key, mode: .standard)))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
        }
    }

    /// R6: a resolved locator yields a manual command naming the shell-quoted absolute
    /// executable, never a bare `claude` that would repeat the lookup that just failed.
    @MainActor @Test func resolvedCommandNamesTheLocatedAbsoluteExecutable() async throws {
        let path = "/Users/Test User/.npm-global/bin/claude"
        let command = try #require(await ClaudeSetupSession.resolvedCommand(
            locator: FixedExecutableLocator(location: .available(path: path, source: .npmGlobalPrefix))
        ))

        #expect(command.contains("'\(path)'"))
        // KTD3 (2026-09-19 sign-in plan): the executable is the last command inside the
        // routing subshell that every manual command now shares.
        #expect(command.hasSuffix("'\(path)')"))
        #expect(!command.hasSuffix(" claude"))
    }

    /// R6: the refusal names the product the user updates and leaks nothing about the
    /// version it read.
    @MainActor @Test func updateRequiredFailureCopyNamesTheProduct() {
        #expect(SetupSessions.failureMessage(for: .updateRequired, account: .builtIn(for: .claude))
            == "Update Claude Code, then try again.")
    }

    /// The missing-CLI sentence appends " CLI" itself, so Copilot's product name must not.
    @MainActor @Test func copilotMissingCopyNamesTheCLIOnce() {
        let account = ProviderAccount.builtIn(for: .copilot)
        #expect(SetupSessions.failureMessage(for: .executableMissing, account: account)
            == "GitHub Copilot CLI wasn’t found. Install or update it, then try again.")
        #expect(SetupSessions.failureMessage(for: .updateRequired, account: account)
            == "Update GitHub Copilot, then try again.")
    }

    /// R8/KTD7: the timeout state offers Try Again and Stop Waiting only, so its sentence
    /// names no button — unlike `.retryExhausted`, which still points at Check Now. The
    /// wording follows the handoff purpose.
    @MainActor @Test func waitingTimeoutCopyFollowsThePurposeAndNamesNoButton() {
        let account = ProviderAccount.builtIn(for: .claude)
        let signIn = SetupSessions.failureMessage(
            for: .waitingTimedOut,
            account: account,
            purpose: .setup
        )
        let approval = SetupSessions.failureMessage(
            for: .waitingTimedOut,
            account: account,
            purpose: .trust
        )

        #expect(signIn == "Sign-in wasn’t confirmed.")
        #expect(approval == "Approval wasn’t confirmed.")
        // A startup question rides the approval's purpose but asked for something else.
        let startupQuestion = SetupSessions.failureMessage(
            for: .waitingTimedOut,
            account: account,
            purpose: .trust,
            interactiveReason: .startupQuestion
        )
        #expect(startupQuestion == "Claude Code wasn’t ready yet.")
        // The reason means nothing outside the `.trust` launch.
        #expect(SetupSessions.failureMessage(
            for: .waitingTimedOut, account: account, purpose: .setup, interactiveReason: .startupQuestion
        ) == signIn)
        for reason in [ClaudeInteractiveLaunchReason.versionUnreadable, .neverOnboardedExtraAccount] {
            #expect(SetupSessions.failureMessage(
                for: .waitingTimedOut, account: account, purpose: .trust, interactiveReason: reason
            ) == approval)
        }
        #expect(!startupQuestion.contains("Check Now"))
        #expect(SetupSessions.failureMessage(for: .waitingTimedOut, account: account, purpose: .reset)
            == signIn)
        for message in [signIn, approval] {
            #expect(!message.contains("Check Now"))
            #expect(!message.lowercased().contains("connect"))
        }
    }

    /// R11/KTD10: the window is gone and the account is still signed out. The status the
    /// wrapper recorded is unobservable for an abandoned sign-in, so the copy never cites it.
    @MainActor @Test func closedBeforeSignInCopyStatesWhatHappened() {
        #expect(SetupSessions.failureMessage(
            for: .closedBeforeSignIn,
            account: .builtIn(for: .claude)
        ) == "Terminal closed before sign-in finished.")
    }

    /// KTD5: without a resolved path there is no command at all — the nil branch must not
    /// fall back to a bare-name invocation.
    @MainActor @Test func resolvedCommandIsNilWhenDiscoveryYieldsNoPath() async {
        for location in [CLIExecutableLocation.confirmedAbsent, .inconclusive(.shellTimeout)] {
            let command = await ClaudeSetupSession.resolvedCommand(
                locator: FixedExecutableLocator(location: location)
            )
            #expect(command == nil)
        }
    }
}

private actor HandoffOpenGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Bool, Never>] = []

    func open() async -> Bool {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if released { return true }
        return await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume(returning: true) }
    }
}

/// KTD1/KTD4: a fixed `--version` capture in place of the real CLI, recording what staging
/// asked so account isolation is asserted without spawning anything.
private actor ClaudeVersionReaderSpy {
    private let output: String?
    private(set) var executablePaths: [String] = []
    private(set) var environments: [[String: String]] = []

    init(_ output: String?) {
        self.output = output
    }

    func read(executablePath: String, environmentOverrides: [String: String]) -> String? {
        executablePaths.append(executablePath)
        environments.append(environmentOverrides)
        return output
    }
}

/// The startup-question reason through the real `SetupSessions` routing: Try Again, a refused
/// second click and a relaunch after Terminal closed. Each drives a stand-in coordinator whose
/// staging is inert, swapped in with `SetupSessions.withCoordinator`, so the live coordinator
/// in this test host never stages a handoff and nothing opens Terminal.
@MainActor
@Suite(.sharedAppState) struct ClaudeStartupQuestionSessionTests {
    private func standInCoordinator() -> SetupSessionCoordinator {
        SetupSessionCoordinator(
            scheduler: StartupQuestionIgnoringScheduler(),
            prepare: { _, _, _ in .failure(.stagingFailed) },
            open: { _ in .success(()) },
            accountExists: { _ in true },
            requestRefresh: { _ in }
        )
    }

    private func account(_ id: String) -> ProviderAccount {
        ProviderAccount(id: AccountID(id), providerID: .claude, label: "Work", isBuiltIn: false)
    }

    private func cleanUp(_ account: ProviderAccount) {
        SetupSessions.noteRequestedTrustReason(nil, for: account.key)
        SetupSessions.noteHandoffInteractiveReason(nil, for: account.key)
        SetupSessionActivity.shared.endWaiting(for: account.key)
        SetupSessionActivity.shared.set(nil, for: account.key)
    }

    /// Try Again after a timed-out startup question restarts as one. A hard-coded
    /// Open Claude Workspace here would clear the reason and fail this test.
    @Test func tryAgainRestartsAStartupQuestionAsOne() {
        let coordinator = standInCoordinator()
        let question = account("claude-startup-try-again")
        let approval = account("claude-approval-try-again")
        defer { cleanUp(question); cleanUp(approval) }

        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.noteRequestedTrustReason(.startupQuestion, for: question.key)
            SetupSessions.tryAgain(for: question, route: .startNewHandoff(.trust), onRetry: {})
            #expect(coordinator.state(for: question.key) == .preparing)
            #expect(coordinator.sessionPurpose(for: question.key) == .trust)
            #expect(SetupSessions.requestedTrustReason(for: question.key) == .startupQuestion)
            #expect(SetupSessions.interactiveReason(for: question) == .startupQuestion)

            // The plain approval is unchanged: no reason before or after.
            SetupSessions.tryAgain(for: approval, route: .startNewHandoff(.trust), onRetry: {})
            #expect(coordinator.state(for: approval.key) == .preparing)
            #expect(SetupSessions.requestedTrustReason(for: approval.key) == nil)
            #expect(SetupSessions.interactiveReason(for: approval) == nil)
        }
    }

    /// A second click the coordinator refuses must not rewrite the running session's reason,
    /// whether the session is still preparing or its Terminal is already open.
    @Test func aRefusedSecondClickKeepsTheRunningReason() {
        let coordinator = standInCoordinator()
        let preparing = account("claude-startup-preparing")
        let open = account("claude-startup-open")
        defer { cleanUp(preparing); cleanUp(open) }

        SetupSessions.withCoordinator(coordinator) {
            SetupSessions.performRecovery(.answerClaudeQuestion, for: preparing, onRetry: {})
            #expect(coordinator.state(for: preparing.key) == .preparing)
            #expect(SetupSessions.requestedTrustReason(for: preparing.key) == .startupQuestion)
            SetupSessions.performRecovery(.openClaudeWorkspace, for: preparing, onRetry: {})
            #expect(coordinator.state(for: preparing.key) == .preparing)
            #expect(SetupSessions.requestedTrustReason(for: preparing.key) == .startupQuestion)
            #expect(SetupSessions.interactiveReason(for: preparing) == .startupQuestion)

            coordinator.restoreActiveHandoff(open.key, purpose: .trust)
            SetupSessions.noteHandoffInteractiveReason(.startupQuestion, for: open.key)
            SetupSessions.noteRequestedTrustReason(.startupQuestion, for: open.key)
            SetupSessions.performRecovery(.openClaudeWorkspace, for: open, onRetry: {})
            #expect(coordinator.state(for: open.key) == .blockedByOpenHandoff)
            #expect(SetupSessions.requestedTrustReason(for: open.key) == .startupQuestion)
            #expect(SetupSessions.interactiveReason(for: open) == .startupQuestion)
        }
    }

    /// A `.trust` handoff whose Terminal closed while Headroom was quit settles on relaunch
    /// with the reason its record saved, so the verifying card keeps its own copy. A plain
    /// approval settles with the approval's copy as before.
    @Test func relaunchAfterTerminalClosedKeepsTheStartupQuestionCopy() throws {
        for (id, reason, expectedPrompt) in [
            ("claude-startup-relaunch", ClaudeInteractiveLaunchReason?.some(.startupQuestion),
             SetupWaitingPrompt.startupQuestion),
            ("claude-approval-relaunch", nil, .workspaceApproval),
        ] {
            let coordinator = standInCoordinator()
            let account = account(id)
            defer { cleanUp(account) }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("headroom-startup-relaunch-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let marker = SetupCompletionMarker(
                pendingPath: directory.appendingPathComponent("pending").path,
                completedPath: directory.appendingPathComponent("complete").path
            )
            let generation = try AccountStorage.prepareSetupCompletionMarker(marker, purpose: .trust)
            try AccountStorage.writeSetupHandoffRecord(
                SetupHandoffRecord(
                    waitingPolicy: .polled,
                    terminalBundleIdentifier: "com.apple.Terminal",
                    claudeInteractiveReason: reason
                ),
                marker: marker,
                generation: generation
            )
            // The wrapper's own exit record, written while Headroom was not running.
            try Data("complete:trust:\(generation):0\n".utf8)
                .write(to: URL(fileURLWithPath: marker.completedPath + "." + generation))
            #expect(!AccountStorage.setupHandoffIsActive(marker: marker))

            SetupSessions.settleFinishedHandoff(marker, for: account.key, coordinator: coordinator)

            #expect(coordinator.state(for: account.key) == .verifying)
            #expect(AccountStorage.setupHandoffRecord(marker: marker) == nil)
            let phase = SetupSessions.withCoordinator(coordinator) {
                SetupSessions.waitingPhase(for: account)
            }
            #expect(phase == .confirming(expectedPrompt, reportedFinished: true))
            #expect(phase?.copy.title == (reason == nil ? "Confirming approval…" : "Confirming…"))
        }
    }
}

@MainActor
private final class StartupQuestionIgnoringScheduler: SetupRetryScheduling {
    private final class Cancellation: SetupRetryCancellation {
        func cancel() {}
    }

    func schedule(
        after _: Duration,
        operation _: @escaping @MainActor @Sendable () -> Void
    ) -> any SetupRetryCancellation {
        Cancellation()
    }
}
