import Foundation
import Testing
@testable import HeadroomCore

struct FeedbackDiagnosticsCollectorTests {
    private let platform = FeedbackDiagnosticsCollector.Platform(
        appVersion: "1.5.3 (53)", operatingSystem: "macOS 26.1", architecture: "arm64"
    )

    private func key(_ providerID: ProviderID, _ id: String) -> AccountKey {
        AccountKey(providerID: providerID, accountID: AccountID(id))
    }

    @Test func accountsAreNumberedPerProviderInDisplayOrderAndOffProvidersListNoAccounts() {
        let accounts: [ProviderID: [AccountKey]] = [
            .claude: [key(.claude, "primary"), key(.claude, "work")],
            .codex: [key(.codex, "primary")],
            .grok: [key(.grok, "primary")],
        ]
        let diagnostics = FeedbackDiagnosticsCollector.diagnostics(
            platform: platform,
            cliVersions: [],
            registered: [.claude, .codex, .grok],
            enabled: [.claude, .codex],
            accounts: { accounts[$0] ?? [] },
            freshness: { $0 == key(.claude, "work") ? .stale(.notLoggedIn("x")) : .live }
        )
        #expect(diagnostics.providersOff == [.grok])
        #expect(diagnostics.accounts == [
            .init(providerID: .claude, position: 1, status: .live),
            .init(providerID: .claude, position: 2, status: .stale("notLoggedIn")),
            .init(providerID: .codex, position: 1, status: .live),
        ])
    }

    /// R4 through the real store: a snapshot carrying an email, a plan name and a failure
    /// message that quotes the email surfaces none of them, and the account's label stays out.
    @MainActor
    @Test func storeSnapshotsNeverLeakEmailPlanLabelOrMessage() async {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let sentinelEmail = "sentinel-user@example.com"
        let sentinelPlan = "SentinelPlanName"
        let snapshot = UsageSnapshot(
            providerID: .claude,
            windows: [],
            planLabel: sentinelPlan,
            accountEmail: sentinelEmail,
            capturedAt: Date(),
            freshness: .stale(.notLoggedIn("Signed in as \(sentinelEmail) on \(sentinelPlan)"))
        )
        let store = UsageStore(
            providers: [StubProvider(id: .claude, displayName: "Claude", snapshot: snapshot)],
            preferences: Preferences(defaults: defaults)
        )
        await store.refreshAll()

        let diagnostics = FeedbackDiagnosticsCollector.diagnostics(
            store: store, platform: platform, cliVersions: []
        )
        let email = FeedbackEmail(source: .mac, diagnostics: diagnostics)
        #expect(email.body.contains("Claude #1: stale (notLoggedIn)"))
        for forbidden in [sentinelEmail, sentinelPlan, "Signed in", "Main"] {
            #expect(!email.body.contains(forbidden), "\(forbidden)")
            #expect(!email.mailtoURL.absoluteString.contains(forbidden), "\(forbidden)")
        }
    }

    @Test func platformNamesMacOSAndArchitecture() {
        let current = FeedbackDiagnosticsCollector.Platform.current(appVersion: "1.5.3")
        #expect(current.operatingSystem.hasPrefix("macOS "))
        #expect(["arm64", "x86_64"].contains(current.architecture))
    }
}

struct CLIVersionReaderTests {
    @Test func everyProviderIsListedInOrderIncludingCopilot() async {
        let versions = await CLIVersionReader.versions(
            resolve: { $0 == .grok ? nil : "/fake/\($0.raw)" },
            loginPath: { "/login/bin" },
            run: { path, loginPath in
                #expect(loginPath == "/login/bin")
                return path.hasSuffix("cursor") ? nil : "\(path.split(separator: "/").last!) 1.2.3"
            }
        )
        #expect(versions.map(\.providerID) == [.claude, .codex, .grok, .cursor, .copilot, .opencode])
        #expect(versions.map(\.version) == [
            .version("1.2.3"), .version("1.2.3"), .notInstalled, .unknown, .version("1.2.3"), .version("1.2.3"),
        ])
    }

    @Test func nothingInstalledSkipsTheLoginShellAndEveryRun() async {
        let versions = await CLIVersionReader.versions(
            resolve: { _ in nil },
            loginPath: { Issue.record("login PATH looked up with no CLI installed"); return "" },
            run: { _, _ in Issue.record("ran a CLI that isn't installed"); return nil }
        )
        #expect(versions.allSatisfy { $0.version == .notInstalled })
    }

    /// `yes --version` prints forever and never exits, so this is the deadline path, and
    /// its endless output also exercises the 4 KB read cap.
    @Test func aCLIThatNeverExitsIsNilByTheDeadline() {
        let start = Date()
        #expect(CLIVersionReader.runVersion(executablePath: "/usr/bin/yes", loginPath: "/usr/bin:/bin", deadline: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    /// System binaries rather than a script written here: running a just-written script
    /// while other tests spawn processes can fail with "text file busy".
    @Test func aRealVersionPrintIsReadAndANonZeroExitIsNil() {
        let output = CLIVersionReader.runVersion(executablePath: "/usr/bin/git", loginPath: "/usr/bin:/bin", deadline: 5)
        guard case .version = FeedbackCLIVersion(versionOutput: output) else {
            Issue.record("git --version read as \(String(reflecting: output))")
            return
        }
        #expect(CLIVersionReader.runVersion(executablePath: "/usr/bin/false", loginPath: "/usr/bin:/bin", deadline: 5) == nil)
        #expect(CLIVersionReader.runVersion(executablePath: "/nonexistent/headroom-cli", loginPath: "/usr/bin:/bin", deadline: 5) == nil)
    }
}
