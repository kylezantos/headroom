import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// Antigravity registration: one single-account provider on its own CLI lane, one shared read
/// path, the launches that never start `agy`, and the Terminal sign-in handoff's script.
@MainActor
struct AntigravityCompositionTests {
    private let realLaunch: [String: String] = [:]

    @Test func theRegistryListsAntigravityLastWithCapacityOne() throws {
        let registry = AppComposition.subscriptionProviderRegistry
        #expect(registry.last?.id == .antigravity)
        let antigravity = try #require(registry.first { $0.id == .antigravity })
        #expect(antigravity.accountCapacity == 1)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-antigravity-\(UUID().uuidString)/ClaudeProbe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let provider = AppComposition.provider(
            for: .builtIn(for: .antigravity), credentials: CredentialStore(), builtInClaudeWorkspace: workspace
        )
        #expect(provider is AntigravityProvider)
        #expect(provider.accountCapacity == antigravity.accountCapacity)
        #expect(provider.pollingLane == .serial("antigravity-cli"))
        #expect(provider.accountKey == AccountKey(providerID: .antigravity, accountID: .primary))
    }

    @Test func anExtraAccountNeverReadsTheDefaultLogin() {
        let extra = ProviderAccount(id: AccountID("work"), providerID: .antigravity, label: "Work")
        let provider = AppComposition.provider(for: extra, credentials: CredentialStore())
        #expect(!(provider is AntigravityProvider))
    }

    @Test func demosHarnessesAndTheTestHostNeverStartAgy() {
        for arguments in [
            ["Headroom", "--demo"],
            ["Headroom", "--demo", "six-providers"],
            ["Headroom", "--render-popover", "/tmp/out"],
            ["Headroom", "--render-widgets", "/tmp/out"],
            ["Headroom", "--render-loading-preview", "/tmp/out"],
            ["Headroom", "--bench-ui", "settings"],
        ] {
            #expect(AppComposition.usesInertAntigravity(arguments: arguments, environment: realLaunch), "\(arguments)")
            #expect(AppComposition.makeAntigravityCLISource(arguments: arguments, environment: realLaunch)
                is InertAntigravityUsageSource)
        }
        let testHost = ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]
        #expect(AppComposition.makeAntigravityCLISource(arguments: ["Headroom"], environment: testHost)
            is InertAntigravityUsageSource)
        // This process is the XCTest host, so the launch's shared source is inert too.
        #expect(AppComposition.usesInertAntigravity())
        #expect(AppComposition.antigravityUsageSource is InertAntigravityUsageSource)
        #expect(!AppComposition.usesInertAntigravity(arguments: ["Headroom"], environment: realLaunch))
    }

    @Test func aRealLaunchReadsThroughTheOfficialClient() {
        #expect(AppComposition.makeAntigravityCLISource(arguments: ["Headroom"], environment: realLaunch)
            is AntigravityCLIUsageSource)
    }

    @Test func theInertSourceStartsNothing() async {
        #expect(await InertAntigravityUsageSource().capture() == .failed(.transient(.spawnFailed)))
        // A provider over the inert source is a "will retry" row, never signed out or missing.
        let snapshot = await AntigravityProvider(source: InertAntigravityUsageSource()).fetchSnapshot()
        #expect(snapshot.freshness == .stale(.providerSetup(.antigravityTransientCapture)))
    }

    @Test func signInAndInstallRouteThroughTheSharedHandoff() {
        #expect(SetupSessions.recoveryRoute(for: .connectAntigravity) == .setup(.standard))
        #expect(SetupSessions.recoveryRoute(for: .installAntigravityCLI)
            == .documentation(AntigravityCLI.installationURL))
        #expect(neverSignedInOutcome(for: .antigravity) == .antigravitySignedOut)
    }

    @Test func theSignInScriptRunsOnlyTheCLIsOwnLogin() {
        let script = AntigravityCLI.loginScript(executablePath: "/opt/homebrew/bin/agy")
        #expect(script.contains("exec '/opt/homebrew/bin/agy' acp --login"))
        #expect(!script.contains("/usage"))
        #expect(!script.contains(" -p "))
        #expect(AntigravityCLI.manualLoginCommand(executablePath: "/opt/homebrew/bin/agy")
            == "'/opt/homebrew/bin/agy' acp --login")
        let missing = AntigravityCLI.loginScript(executablePath: nil)
        #expect(missing.contains("Antigravity CLI was not found"))
        #expect(missing.contains("exit 127"))
    }
}
