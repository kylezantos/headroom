import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// Claude CLI discovery and manual-command recovery at the app boundary: what the
/// capability recovery row offers for each discovery state, and which executable the
/// staged handoff, clipboard fallback, and legacy script actually launch.
@Suite struct ClaudeExecutableDiscoveryInteractionTests {
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
        #expect(actions.secondaryAccessibilityLabel == "Check Again for Personal")
        #expect(actions.usesSecondLine)
    }

    /// AE7: incomplete discovery keeps Check Again + Open Guided Setup and never shows
    /// confirmed-absence installation copy.
    @MainActor @Test func inconclusiveDiscoveryKeepsRetryActionsWithoutInstallCopy() {
        for issue in [CLIExecutableDiscoveryIssue.shellTimeout, .npmPrefixUnresolved] {
            let recovery = capabilityRecoveryPresentation(
                state: .inconclusive(issue),
                hasActiveSetupSession: false
            )?.recovery
            #expect(recovery?.primaryAction == .checkNow)
            #expect(recovery?.secondaryAction == .openClaudeSetup)
            #expect(recovery?.primaryLabel == "Check Again")
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
        #expect(staged.manualCommand.contains("CLAUDE_CONFIG_DIR='\(configDirectory)'"))
        #expect(staged.manualCommand.hasSuffix("'\(launcher.path)'"))
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
        #expect(command.hasSuffix("'\(path)'"))
        #expect(!command.hasSuffix(" claude"))
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
