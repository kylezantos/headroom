import Darwin
import Foundation
import Testing
@testable import HeadroomCore

/// Every test drives a fake `copilot` script that speaks the framed protocol, so neither the
/// real CLI nor `~/.copilot` is touched.
struct CopilotStatusSourceTests {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeSource(
        _ fake: FakeCopilot,
        inherited: [String: String] = [:],
        timeout: TimeInterval = 10,
        clock: MutableDateSource = MutableDateSource(Date(timeIntervalSince1970: 2_000_000_000))
    ) -> CopilotStatusSource {
        CopilotStatusSource(
            executablePath: { fake.path },
            workingDirectory: fake.directory.path,
            inheritedEnvironment: { inherited },
            loginPath: { "/usr/bin:/bin" },
            timeout: timeout,
            now: clock.now
        )
    }

    private func userAction(_ source: CopilotStatusSource) async -> CopilotStatusResult {
        await UserRequestedProbeContext.$isUserRequested.withValue(true) {
            await source.status()
        }
    }

    // MARK: Replies

    @Test func authenticatedReplyReturnsTheRawAccountStatus() async throws {
        let fake = try FakeCopilot()
        defer { fake.remove() }

        let result = await makeSource(fake).status()

        #expect(result == .signedIn(CopilotAccountStatus(
            login: "octocat",
            entitlement: 20_000,
            isUnlimited: false,
            tokenBasedBilling: true,
            reportedUsed: 300,
            reportedResetDate: DateParsing.iso8601("2026-11-03T02:14:04.291Z")
        )))
        #expect(fake.arguments == "--headless --stdio --no-auto-update")
    }

    @Test func onlyTheThreeStatusMethodsAreEverSent() async throws {
        let fake = try FakeCopilot()
        defer { fake.remove() }

        _ = await makeSource(fake).status()

        #expect(fake.methods == ["ping", "auth.getStatus", "account.getQuota"])
    }

    @Test func signedOutAccountNeverReachesTheQuotaMethod() async throws {
        let fake = try FakeCopilot(auth: #"{"isAuthenticated":false,"statusMessage":"Not signed in"}"#)
        defer { fake.remove() }

        let result = await makeSource(fake).status()

        #expect(result == .signedOut)
        #expect(fake.methods == ["ping", "auth.getStatus"])
    }

    @Test func unlimitedEntitlementCarriesNoMeteredAllowance() async throws {
        let fake = try FakeCopilot(quota: FakeCopilot.quota(
            #""isUnlimitedEntitlement":true,"entitlementRequests":-1,"usedRequests":0,"tokenBasedBilling":false"#
        ))
        defer { fake.remove() }

        guard case .signedIn(let status) = await makeSource(fake).status() else {
            Issue.record("expected a signed-in status")
            return
        }
        #expect(status.isUnlimited)
        #expect(status.entitlement == nil)
    }

    @Test func unparseableResetDateLeavesTheOtherFieldsIntact() async throws {
        let fake = try FakeCopilot(quota: FakeCopilot.quota(
            #""isUnlimitedEntitlement":false,"entitlementRequests":300,"usedRequests":12,"resetDate":"soon","tokenBasedBilling":false"#
        ))
        defer { fake.remove() }

        guard case .signedIn(let status) = await makeSource(fake).status() else {
            Issue.record("expected a signed-in status")
            return
        }
        #expect(status.entitlement == 300)
        #expect(status.reportedUsed == 12)
        #expect(status.reportedResetDate == nil)
    }

    // MARK: Failures

    @Test(arguments: [
        #"{"message":"headroom","protocolVersion":4}"#,
        #"{"message":"headroom"}"#,
    ])
    func unknownProtocolVersionIsTransient(ping: String) async throws {
        let fake = try FakeCopilot(ping: ping)
        defer { fake.remove() }

        guard case .failure(.transient) = await makeSource(fake).status() else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(fake.methods == ["ping"])
    }

    @Test func quotaRPCErrorIsTransientAndNamesNoAccount() async throws {
        let fake = try FakeCopilot(quotaError: #"{"code":-32603,"message":"octocat is not authenticated"}"#)
        defer { fake.remove() }

        let result = await makeSource(fake).status()

        guard case .failure(.transient(let message)) = result else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(!message.contains("octocat"))
    }

    @Test func nonRespondingCLIHitsTheDeadlineAndItsProcessGroupIsKilled() async throws {
        let fake = try FakeCopilot(silentProcessGroup: true)
        defer { fake.remove() }

        let start = Date()
        let result = await makeSource(fake, timeout: 1).status()

        guard case .failure(.transient) = result else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(Date().timeIntervalSince(start) < 5)
        let pids = try #require(fake.groupPIDs)
        #expect(pids.count == 2)
        #expect(await allExited(pids))
    }

    // MARK: Environment

    @Test func accountSelectingVariablesNeverReachTheSpawnedProcess() async throws {
        let fake = try FakeCopilot()
        defer { fake.remove() }

        _ = await makeSource(fake, inherited: [
            "COPILOT_HOME": "/tmp/wrong-home",
            "COPILOT_GITHUB_TOKEN": "wrong-1",
            "GH_TOKEN": "wrong-2",
            "GITHUB_TOKEN": "wrong-3",
            "HEADROOM_FAKE_KEEP": "kept",
        ]).status()

        let environment = fake.environment
        #expect(environment["HEADROOM_FAKE_KEEP"] == "kept")
        #expect(environment["PATH"] == "/usr/bin:/bin")
        for name in ["COPILOT_HOME", "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] {
            #expect(environment[name] == nil)
        }
    }

    // MARK: Cache

    @Test func timerReadsShareOneSpawnForAnHour() async throws {
        let fake = try FakeCopilot()
        defer { fake.remove() }
        let clock = MutableDateSource(t0)
        let source = makeSource(fake, clock: clock)

        let first = await source.status()
        clock.set(t0.addingTimeInterval(3_599))
        let second = await source.status()

        #expect(fake.spawnCount == 1)
        #expect(second == first)

        clock.set(t0.addingTimeInterval(3_600))
        _ = await source.status()
        #expect(fake.spawnCount == 2)
    }

    @Test func userActionBypassesTheCacheAndItsReadingServesLaterTimers() async throws {
        let fake = try FakeCopilot(auth: #"{"isAuthenticated":false}"#)
        defer { fake.remove() }
        let clock = MutableDateSource(t0)
        let source = makeSource(fake, clock: clock)

        #expect(await source.status() == .signedOut)
        try fake.setAuth(#"{"isAuthenticated":true,"login":"octocat"}"#)
        clock.set(t0.addingTimeInterval(60))

        #expect(await source.status() == .signedOut)
        guard case .signedIn = await userAction(source) else {
            Issue.record("a user action must see the new sign-in")
            return
        }
        guard case .signedIn = await source.status() else {
            Issue.record("the next timer read must reuse the fresh reading")
            return
        }
        #expect(fake.spawnCount == 2)
    }

    @Test func transientFailureIsNotCached() async throws {
        let fake = try FakeCopilot(ping: #"{"protocolVersion":4}"#)
        defer { fake.remove() }
        let source = makeSource(fake)

        _ = await source.status()
        _ = await source.status()

        #expect(fake.spawnCount == 2)
    }

    @Test func missingCLIIsNotCachedAndSpawnsNothing() async throws {
        let fake = try FakeCopilot()
        defer { fake.remove() }
        let installed = CopilotTestPath(nil)
        let source = CopilotStatusSource(
            executablePath: { installed.value },
            workingDirectory: fake.directory.path,
            inheritedEnvironment: { [:] },
            loginPath: { "/usr/bin:/bin" },
            timeout: 10
        )

        #expect(await source.status() == .cliMissing)
        #expect(fake.spawnCount == 0)

        installed.value = fake.path
        guard case .signedIn = await source.status() else {
            Issue.record("the next read must find the installed CLI")
            return
        }
    }

    // MARK: Helpers

    private func allExited(_ pids: [pid_t]) async -> Bool {
        for _ in 0..<150 {
            if pids.allSatisfy({ kill($0, 0) == -1 && errno == ESRCH }) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}

// MARK: - Doubles

final class CopilotTestPath: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    init(_ start: String?) { current = start }
    var value: String? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// A bash stand-in for `copilot --headless --stdio`. It frames replies the way the server
/// does, sends a notification and a reply to another id before each answer, and splits each
/// answer's header from its body. Replies live in files, so a test can change one between
/// spawns, and it logs what it received into its own temp directory.
struct FakeCopilot: Sendable {
    let directory: URL
    var path: String { directory.appendingPathComponent("copilot").path }

    static func quota(_ premiumFields: String) -> String {
        #"{"quotaSnapshots":{"chat":{"isUnlimitedEntitlement":true},"premium_interactions":{\#(premiumFields)}}}"#
    }

    static let defaultQuota = quota(
        #""isUnlimitedEntitlement":false,"entitlementRequests":20000,"usedRequests":300,"remainingPercentage":98.5,"resetDate":"2026-11-03T02:14:04.291Z","overage":0,"hasQuota":true,"tokenBasedBilling":true,"overageEntitlement":0"#
    )

    init(
        ping: String = #"{"message":"headroom","timestamp":1,"protocolVersion":3}"#,
        auth: String = #"{"isAuthenticated":true,"authType":"user","host":"https://github.com","statusMessage":"Signed in","login":"octocat"}"#,
        quota: String = FakeCopilot.defaultQuota,
        quotaError: String? = nil,
        silentProcessGroup: Bool = false
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-fake-copilot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let quotaMember = quotaError.map { #""error":\#($0)"# } ?? #""result":\#(quota)"#
        try ping.write(to: file("ping.json"), atomically: true, encoding: .utf8)
        try #""result":\#(auth)"#.write(to: file("auth.json"), atomically: true, encoding: .utf8)
        try quotaMember.write(to: file("quota.json"), atomically: true, encoding: .utf8)
        let script = silentProcessGroup ? Self.silentScript(in: directory) : Self.protocolScript(in: directory)
        try script.write(to: file("copilot"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    func setAuth(_ auth: String) throws {
        try #""result":\#(auth)"#.write(to: file("auth.json"), atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    var methods: [String] { lines("methods.log") }
    var spawnCount: Int { lines("spawns.log").count }
    var arguments: String? { lines("args.log").first }
    var groupPIDs: [pid_t]? {
        let pids = lines("pids.log").compactMap { pid_t($0) }
        return pids.isEmpty ? nil : pids
    }
    var environment: [String: String] {
        Dictionary(lines("env.log").compactMap { line -> (String, String)? in
            guard let separator = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<separator]), String(line[line.index(after: separator)...]))
        }, uniquingKeysWith: { _, last in last })
    }

    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func lines(_ name: String) -> [String] {
        ((try? String(contentsOf: file(name), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    /// TERM is ignored by the leader and, by inheritance, its child, so only a kill of the
    /// whole group ends both.
    private static func silentScript(in directory: URL) -> String {
        #"""
        #!/bin/bash
        trap '' TERM
        sleep 300 &
        printf '%s\n%s\n' "$$" "$!" > '\#(directory.path)/pids.log'
        while :; do sleep 1; done
        """#
    }

    private static func protocolScript(in directory: URL) -> String {
        #"""
        #!/bin/bash
        export LC_ALL=C
        cd '\#(directory.path)' || exit 1
        echo spawned >> spawns.log
        printf '%s\n' "$*" > args.log
        env > env.log
        frame() { printf 'Content-Length: %d\r\n\r\n' "${#1}"; printf '%s' "$1"; }
        method_pattern='"method":"([^"]+)"'
        id_pattern='"id":([0-9]+)'
        while IFS= read -r line; do
          line=${line%$'\r'}
          case "$line" in
            Content-Length:*) length=${line#Content-Length: } ;;
            '')
              IFS= read -r -n "$length" body
              [[ $body =~ $method_pattern ]] && method=${BASH_REMATCH[1]}
              [[ $body =~ $id_pattern ]] && id=${BASH_REMATCH[1]}
              echo "$method" >> methods.log
              frame '{"jsonrpc":"2.0","method":"session.lifecycle","params":{}}'
              frame '{"jsonrpc":"2.0","id":9999,"result":{"protocolVersion":0}}'
              case "$method" in
                ping) member="\"result\":$(cat ping.json)" ;;
                auth.getStatus) member=$(cat auth.json) ;;
                account.getQuota) member=$(cat quota.json) ;;
                *) member='"error":{"code":-32601,"message":"Method not found"}' ;;
              esac
              frame "{\"jsonrpc\":\"2.0\",\"id\":$id,$member}"
              ;;
          esac
        done
        """#
    }
}
