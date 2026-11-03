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
            run: { path in path.hasSuffix("cursor") ? nil : "\(path.split(separator: "/").last!) 1.2.3" }
        )
        #expect(versions.map(\.providerID) == [.claude, .codex, .grok, .cursor, .copilot])
        #expect(versions.map(\.version) == [
            .version("1.2.3"), .version("1.2.3"), .notInstalled, .unknown, .version("1.2.3"),
        ])
    }

    @Test func aVersionThatTimesOutIsNil() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let slow = directory.appendingPathComponent("slow")
        try "#!/bin/sh\nsleep 5\necho 9.9.9\n".write(to: slow, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slow.path)

        #expect(CLIVersionReader.runVersion(executablePath: slow.path, loginPath: "/usr/bin:/bin", deadline: 0.5) == nil)
    }

    @Test func aRealVersionPrintIsReadAndANonZeroExitIsNil() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = directory.appendingPathComponent("good")
        let bad = directory.appendingPathComponent("bad")
        try "#!/bin/sh\necho \"tool 4.5.6\"\n".write(to: good, atomically: true, encoding: .utf8)
        try "#!/bin/sh\necho \"tool 4.5.6\"\nexit 3\n".write(to: bad, atomically: true, encoding: .utf8)
        for file in [good, bad] {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }

        let output = CLIVersionReader.runVersion(executablePath: good.path, loginPath: "/usr/bin:/bin", deadline: 3)
        #expect(FeedbackCLIVersion(versionOutput: output) == .version("4.5.6"))
        #expect(CLIVersionReader.runVersion(executablePath: bad.path, loginPath: "/usr/bin:/bin", deadline: 3) == nil)
        #expect(CLIVersionReader.runVersion(executablePath: directory.appendingPathComponent("missing").path,
                                            loginPath: "/usr/bin:/bin", deadline: 3) == nil)
    }
}
