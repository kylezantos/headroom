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
            run: { _, path, loginPath in
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
            run: { _, _, _ in Issue.record("ran a CLI that isn't installed"); return nil }
        )
        #expect(versions.allSatisfy { $0.version == .notInstalled })
    }

    @Test func eachRunIsToldWhichProviderItReads() async {
        let seen = SeenProviders()
        _ = await CLIVersionReader.versions(
            resolve: { "/fake/\($0.raw)" },
            loginPath: { "/login/bin" },
            run: { providerID, path, _ in
                #expect(path == "/fake/\(providerID.raw)")
                seen.insert(providerID)
                return nil
            }
        )
        #expect(seen.values == Set(CLIVersionReader.providers))
    }

    private static let inherited = [
        "FOO": "bar",
        "OPENCODE_API_KEY": "sk-secret",
        "OPENCODE_CONFIG": "/elsewhere/opencode.json",
        "OPENCODE_DISABLE_AUTOUPDATE": "0",
        "XDG_DATA_HOME": "/custom/data",
        "XDG_CONFIG_HOME": "/custom/config",
        "XDG_CACHE_HOME": "/custom/cache",
        "XDG_STATE_HOME": "/custom/state",
    ]

    /// The feedback window's OpenCode `--version` follows the rule every other OpenCode spawn
    /// does (KTD2, KTD10), so no inherited variable can point it at another home.
    @Test func openCodeVersionRunsWithTheOpenCodeRuleInTheProbeFolder() throws {
        let launch = CLIVersionReader.launch(for: .opencode, loginPath: "/login/bin", inherited: Self.inherited)
        #expect(launch.environment == OpenCodeCLI.environment(inherited: Self.inherited, home: .builtIn, loginPath: "/login/bin"))
        #expect(launch.workingDirectory == OpenCodeCLI.defaultWorkingDirectory.path)
        #expect(launch.readsNullStdin)

        // The spawn itself: a fake `opencode` run as `/bin/sh <script>` prints what it got.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-version-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("opencode")
        try Data("env\necho \"HEADROOM_PWD=$(pwd -P)\"\n".utf8).write(to: script)

        let output = try #require(CLIVersionReader.runVersion(
            providerID: .opencode,
            executablePath: script.path,
            loginPath: "/usr/bin:/bin",
            inherited: Self.inherited,
            interpreter: "/bin/sh",
            deadline: 5
        ))
        let lines = output.split(separator: "\n").map(String.init)
        let environment = Dictionary(lines.compactMap { line -> (String, String)? in
            guard let equals = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<equals]), String(line[line.index(after: equals)...]))
        }, uniquingKeysWith: { $1 })
        #expect(environment.keys.filter { $0.hasPrefix("OPENCODE_") }.sorted() == OpenCodeTestExpectations.fixedNames)
        #expect(environment["OPENCODE_DISABLE_MODELS_FETCH"] == "1")
        #expect(environment["OPENCODE_DISABLE_AUTOUPDATE"] == "1")
        #expect(!environment.keys.contains { $0.hasPrefix("XDG_") })
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["FOO"] == "bar")
        let expectedFolder = try #require(realpath(OpenCodeCLI.defaultWorkingDirectory.path, nil))
        defer { free(expectedFolder) }
        #expect(environment["HEADROOM_PWD"] == String(cString: expectedFolder))
        #expect(environment["HEADROOM_PWD"] != NSHomeDirectory())
    }

    /// Every other provider's read is unchanged: the inherited environment with the login PATH,
    /// from the home folder.
    @Test func otherProvidersKeepTheInheritedEnvironment() {
        for providerID in CLIVersionReader.providers where providerID != .opencode {
            let launch = CLIVersionReader.launch(for: providerID, loginPath: "/login/bin", inherited: Self.inherited)
            #expect(launch.environment == Self.inherited.merging(["PATH": "/login/bin"]) { $1 }, "\(providerID.raw)")
            #expect(launch.workingDirectory == NSHomeDirectory())
            #expect(!launch.readsNullStdin)
        }
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

private final class SeenProviders: @unchecked Sendable {
    private let lock = NSLock()
    private var set: Set<ProviderID> = []
    func insert(_ id: ProviderID) { lock.withLock { _ = set.insert(id) } }
    var values: Set<ProviderID> { lock.withLock { set } }
}
