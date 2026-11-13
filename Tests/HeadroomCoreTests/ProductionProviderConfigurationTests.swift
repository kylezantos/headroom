import Foundation
import Testing
@testable import HeadroomCore

@Suite struct ProductionProviderConfigurationTests {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let accounts = URL(fileURLWithPath: "/Users/test/Library/Application Support/Headroom/Accounts")
    private let workspace = URL(fileURLWithPath: "/Users/test/Library/Application Support/Headroom/ClaudeProbe")

    @Test func builtInAccountsUseOnlyProviderDefaultsAndPreserveIdentity() {
        let claude = ProviderAccountConfiguration.make(
            for: .builtIn(for: .claude), userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let codex = ProviderAccountConfiguration.make(
            for: .builtIn(for: .codex), userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let grok = ProviderAccountConfiguration.make(
            for: .builtIn(for: .grok), userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )

        #expect(claude.accountKey == AccountKey(providerID: .claude, accountID: .primary))
        #expect(claude.claudeConfigDirectory == nil)
        #expect(claude.claudeWorkspaceDirectory == workspace)
        #expect(codex.accountKey == AccountKey(providerID: .codex, accountID: .primary))
        #expect(codex.codexHomeDirectory == nil)
        #expect(codex.codexAuthFile?.path == "/Users/test/.codex/auth.json")
        #expect(grok.accountKey == AccountKey(providerID: .grok, accountID: .primary))
        #expect(grok.grokHomeDirectory == nil)
        #expect(grok.grokAuthFile?.path == "/Users/test/.grok/auth.json")
    }

    @Test func additionalAccountsUseTheirExactIsolatedPathsAndIDs() {
        let claudeAccount = ProviderAccount(id: AccountID("claude-work"), providerID: .claude, label: "Work")
        let codexAccount = ProviderAccount(id: AccountID("codex-work"), providerID: .codex, label: "Work")
        let grokAccount = ProviderAccount(id: AccountID("grok-work"), providerID: .grok, label: "Work")
        let claude = ProviderAccountConfiguration.make(
            for: claudeAccount, userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let codex = ProviderAccountConfiguration.make(
            for: codexAccount, userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let grok = ProviderAccountConfiguration.make(
            for: grokAccount, userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )

        #expect(claude.accountKey == claudeAccount.key)
        #expect(claude.claudeConfigDirectory?.path.hasSuffix("/claude/claude-work/config") == true)
        #expect(claude.claudeWorkspaceDirectory?.path.hasSuffix("/claude/claude-work/workspace") == true)
        #expect(codex.accountKey == codexAccount.key)
        #expect(codex.codexHomeDirectory?.path.hasSuffix("/codex/codex-work") == true)
        #expect(codex.codexAuthFile?.path.hasSuffix("/codex/codex-work/auth.json") == true)
        #expect(grok.accountKey == grokAccount.key)
        #expect(grok.grokHomeDirectory?.path.hasSuffix("/grok/grok-work") == true)
        #expect(grok.grokAuthFile?.path.hasSuffix("/grok/grok-work/auth.json") == true)
    }

    // MARK: OpenCode (U4, KTD10)

    @Test func openCodeBuiltInCarriesNoXDGPathsAndReadsTheDefaultHome() {
        let opencode = ProviderAccountConfiguration.make(
            for: .builtIn(for: .opencode), userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        #expect(opencode.accountKey == AccountKey(providerID: .opencode, accountID: .primary))
        #expect(opencode.opencodeHome == .builtIn)
        #expect(opencode.opencodeDataHome == nil)
        #expect(opencode.opencodeConfigHome == nil)
        #expect(opencode.opencodeCacheHome == nil)
        #expect(opencode.opencodeStateHome == nil)
        #expect(opencode.opencodeHome?.xdgValues.isEmpty == true)
    }

    @Test func openCodeExtraCarriesFourXDGPathsUnderItsOwnAccountFolder() throws {
        let account = ProviderAccount(id: AccountID("opencode-work"), providerID: .opencode, label: "Work")
        let opencode = ProviderAccountConfiguration.make(
            for: account, userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let root = accounts.appendingPathComponent("opencode/opencode-work", isDirectory: true).path
        #expect(opencode.accountKey == account.key)
        #expect(opencode.opencodeHome == .isolated(root: root))
        #expect(opencode.opencodeDataHome?.path == root + "/data")
        #expect(opencode.opencodeConfigHome?.path == root + "/config")
        #expect(opencode.opencodeCacheHome?.path == root + "/cache")
        #expect(opencode.opencodeStateHome?.path == root + "/state")
        // The child gets exactly these four, and data and state share one root (KTD10).
        let values = try #require(opencode.opencodeHome?.xdgValues)
        #expect(values == [
            "XDG_DATA_HOME": root + "/data",
            "XDG_CONFIG_HOME": root + "/config",
            "XDG_CACHE_HOME": root + "/cache",
            "XDG_STATE_HOME": root + "/state",
        ])
        // Nothing else routes there, and no other provider gets an OpenCode home.
        #expect(opencode.grokHomeDirectory == nil && opencode.codexHomeDirectory == nil)
        let grok = ProviderAccountConfiguration.make(
            for: ProviderAccount(id: AccountID("g"), providerID: .grok, label: "G"),
            userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        #expect(grok.opencodeHome == nil)
    }

    @Test func twoOpenCodeExtrasNeverShareAHome() {
        let first = ProviderAccountConfiguration.make(
            for: ProviderAccount(id: AccountID("a"), providerID: .opencode, label: "A"),
            userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let second = ProviderAccountConfiguration.make(
            for: ProviderAccount(id: AccountID("b"), providerID: .opencode, label: "B"),
            userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        #expect(first.opencodeHome != second.opencodeHome)
        #expect(first.opencodeStateHome != second.opencodeStateHome)
    }
}

/// KTD18: the DEBUG-only `--opencode-executable` seam. It reaches extra-account homes and a
/// `--probe-opencode` that names `--opencode-home`, never the built-in home, because 2.x
/// migrates a 1.x home one way on first use.
@Suite struct OpenCodeExecutableOverrideTests {
    private let override = ["Headroom", "--opencode-executable", "/tmp/opencode-v2"]

    @Test func releaseBuildsIgnoreTheOverride() {
        #expect(OpenCodeLaunchArguments.executableOverride(arguments: override, buildAllowsOverride: false) == nil)
        #expect(OpenCodeLaunchArguments.executableOverride(arguments: override, buildAllowsOverride: true) == "/tmp/opencode-v2")
        let probe = override + ["--probe-opencode", "--opencode-home", "/tmp/home"]
        #expect(OpenCodeLaunchArguments.probeTarget(arguments: probe, buildAllowsOverride: false)
            == OpenCodeProbeTarget(home: .isolated(root: "/tmp/home"), executable: nil))
    }

    @Test func aMissingOrFlagShapedValueIsNoOverride() {
        #expect(OpenCodeLaunchArguments.executableOverride(arguments: ["Headroom", "--opencode-executable"], buildAllowsOverride: true) == nil)
        #expect(OpenCodeLaunchArguments.executableOverride(
            arguments: ["Headroom", "--opencode-executable", "--probe-opencode"], buildAllowsOverride: true
        ) == nil)
    }

    @Test func aProbeWithoutAHomeIgnoresTheOverride() {
        let probe = override + ["--probe-opencode"]
        #expect(OpenCodeLaunchArguments.probeTarget(arguments: probe, buildAllowsOverride: true)
            == OpenCodeProbeTarget(home: .builtIn, executable: nil))
    }

    @Test func aProbeWithAHomeUsesTheOverride() {
        let probe = override + ["--probe-opencode", "--opencode-home", "/tmp/stub-home/"]
        #expect(OpenCodeLaunchArguments.probeTarget(arguments: probe, buildAllowsOverride: true)
            == OpenCodeProbeTarget(home: .isolated(root: "/tmp/stub-home"), executable: "/tmp/opencode-v2"))
    }

    @Test func aHomeFlagWithoutAValueRefusesTheProbe() {
        // Never falls back to the built-in home: the user asked for an isolated one.
        #expect(OpenCodeLaunchArguments.probeTarget(arguments: ["Headroom", "--probe-opencode", "--opencode-home"], buildAllowsOverride: true) == nil)
        #expect(OpenCodeLaunchArguments.probeTarget(
            arguments: ["Headroom", "--probe-opencode", "--opencode-home", "--opencode-executable", "/x"], buildAllowsOverride: true
        ) == nil)
    }

    @Test func theRouterNeverSendsTheBuiltInHomeToTheOverride() async {
        let standard = RecordingOpenCodeSource()
        let overridden = RecordingOpenCodeSource()
        let router = OpenCodeExecutableOverrideRouter(standard: standard, overridden: overridden)
        _ = await router.capture(home: .builtIn)
        _ = await router.capture(home: .isolated(root: "/tmp/extra"))
        #expect(await standard.homes == [.builtIn])
        #expect(await overridden.homes == [.isolated(root: "/tmp/extra")])
    }
}

private actor RecordingOpenCodeSource: OpenCodeUsageSource {
    private(set) var homes: [OpenCodeAccountHome] = []
    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        homes.append(home)
        return .noGoPlan
    }
}
