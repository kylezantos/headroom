import Darwin
import Foundation
import Testing
@testable import HeadroomCore

// Classification is pinned to captures of the real agy 1.5.9 (see the fixture manifest for
// which are live, derived or synthetic). Process tests run a fake `agy` as `/bin/sh <script>`
// that prints those same captures, so the real CLI and its home are never touched.

// MARK: - Fixtures

private struct AntigravityFixture {
    let name: String
    let stdout: Data
    let exit: Int32

    static let manifest: Set<String> = {
        guard let url = Bundle.module.url(forResource: "antigravity-fixtures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fixtures = object["fixtures"] as? [[String: Any]]
        else { return [] }
        return Set(fixtures.compactMap { $0["name"] as? String })
    }()

    static func load(_ name: String) throws -> AntigravityFixture {
        let stdoutURL = try #require(Bundle.module.url(forResource: "antigravity-\(name)", withExtension: "stdout"))
        let exitURL = try #require(Bundle.module.url(forResource: "antigravity-\(name)", withExtension: "exit"))
        let exitText = try String(contentsOf: exitURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(manifest.contains(name), "\(name) is missing from the manifest")
        return AntigravityFixture(name: name, stdout: try Data(contentsOf: stdoutURL), exit: try #require(Int32(exitText)))
    }

    static func loadStderr(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "antigravity-\(name)", withExtension: "stderr"))
        return try Data(contentsOf: url)
    }

    var output: AntigravityRunOutput {
        AntigravityRunOutput(exitCode: exit, stdout: stdout, overflowed: false, timedOut: false)
    }

    var text: String { String(decoding: stdout, as: UTF8.self) }
}

private func output(exit: Int32?, _ text: String, overflowed: Bool = false, timedOut: Bool = false) -> AntigravityRunOutput {
    AntigravityRunOutput(exitCode: exit, stdout: Data(text.utf8), overflowed: overflowed, timedOut: timedOut)
}

private func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// The live usage payload with one edit applied to its text.
private func editedUsage(_ replace: String, with replacement: String) throws -> String {
    let live = try AntigravityFixture.load("usage-live").text
    #expect(live.contains(replace), "the live payload no longer contains \(replace)")
    return live.replacingOccurrences(of: replace, with: replacement)
}

private func buckets(_ capture: AntigravityCapture) -> [AntigravityBucket]? {
    guard case .usage(let usage) = capture else { return nil }
    return usage.buckets
}

// MARK: - Classification (pure)

struct AntigravityUsageClassifierTests {
    @Test func everyFixtureIsInTheManifest() throws {
        #expect(AntigravityFixture.manifest == [
            "usage-live", "credits-live", "version-live", "usage-signed-out",
            "usage-missing-3p-5h", "usage-one-turn", "usage-output-tokens", "credits-1200",
        ])
    }

    @Test func liveUsageReadsFourBucketsByIDAndWindow() throws {
        let read = try #require(buckets(AntigravityUsageClassifier.classifyUsage(try AntigravityFixture.load("usage-live").output)))
        #expect(read.map(\.pool) == [.gemini, .gemini, .claudeAndGPT, .claudeAndGPT])
        #expect(read.map(\.window) == [.weekly, .fiveHour, .weekly, .fiveHour])
        #expect(abs(read[0].remainingFraction - 0.9946) < 0.0001)
        #expect(abs(read[1].remainingFraction - 0.9894) < 0.0001)
        #expect(read[2].remainingFraction == 1)
        #expect(read[3].remainingFraction == 1)
        #expect(read.map(\.resetsAt) == [
            utc("2026-11-24T00:33:16Z"), utc("2026-11-17T05:33:16Z"),
            utc("2026-11-24T00:42:21Z"), utc("2026-11-17T05:42:21Z"),
        ])
    }

    @Test func anOmittedBucketIsAbsent() throws {
        let read = try #require(buckets(AntigravityUsageClassifier.classifyUsage(
            try AntigravityFixture.load("usage-missing-3p-5h").output)))
        #expect(read.count == 3)
        #expect(!read.contains { $0.pool == .claudeAndGPT && $0.window == .fiveHour })
        #expect(read.contains { $0.pool == .claudeAndGPT && $0.window == .weekly })
    }

    @Test func fractionsOutsideZeroToOneAreClamped() throws {
        let above = try editedUsage(#""remaining_fraction":0.9946085214614868"#, with: #""remaining_fraction":1.4"#)
        let below = try editedUsage(#""remaining_fraction":0.9894489645957947"#, with: #""remaining_fraction":-0.2"#)
        let high = try #require(buckets(AntigravityUsageClassifier.classifyUsage(output(exit: 0, above))))
        let low = try #require(buckets(AntigravityUsageClassifier.classifyUsage(output(exit: 0, below))))
        #expect(high[0].remainingFraction == 1)
        #expect(low[1].remainingFraction == 0)
    }

    @Test func aMissingResetKeepsTheRowWithNoReset() throws {
        let noReset = try editedUsage(#","reset_time":"2026-11-17T05:42:21Z""#, with: "")
        let read = try #require(buckets(AntigravityUsageClassifier.classifyUsage(output(exit: 0, noReset))))
        #expect(read.count == 4)
        #expect(read[3].pool == .claudeAndGPT && read[3].window == .fiveHour)
        #expect(read[3].resetsAt == nil)
        #expect(read[3].remainingFraction == 1)
    }

    @Test func anotherCommandNameIsFormatChanged() throws {
        let other = try editedUsage(#""command":{"name":"usage""#, with: #""command":{"name":"quota""#)
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, other)) == .failed(.formatChanged(.commandName)))
    }

    @Test func nonJSONOnExitZeroStopsPollingAndEmptyIsFormatChanged() {
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, "Gemini Models\tWeekly\t99%\n"))
            == .failed(.unsupportedClient))
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, "")) == .failed(.formatChanged(.output)))
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, " \n")) == .failed(.formatChanged(.output)))
    }

    @Test func nonzeroExitWithoutAnAnswerIsTransient() {
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 1, "")) == .failed(.transient(.unexpectedExit)))
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 3, "error: something\n")) == .failed(.transient(.unexpectedExit)))
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: nil, "")) == .failed(.transient(.unexpectedExit)))
    }

    @Test func deadlineIsTransientUnlessAFullAnswerWasPrinted() throws {
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: nil, "", timedOut: true)) == .failed(.transient(.deadline)))
        let live = try AntigravityFixture.load("usage-live")
        let hung = AntigravityRunOutput(exitCode: nil, stdout: live.stdout, overflowed: false, timedOut: true)
        #expect(buckets(AntigravityUsageClassifier.classifyUsage(hung))?.count == 4)
    }

    @Test func outputOverTheCapStopsPolling() {
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, "", overflowed: true))
            == .failed(.unsupportedClient))
    }

    /// Synthetic, shaped like what agy printed for an empty CLI home after it had started a
    /// Google sign-in. "failed or timed out" is not proof of a signed-out account.
    @Test func capturedSignedOutAnswerIsTransientAuthenticationFailure() throws {
        let fixture = try AntigravityFixture.load("usage-signed-out")
        #expect(AntigravityUsageClassifier.classifyUsage(fixture.output) == .failed(.transient(.authenticationFailed)))
        let exitZero = AntigravityRunOutput(exitCode: 0, stdout: fixture.stdout, overflowed: false, timedOut: false)
        #expect(AntigravityUsageClassifier.classifyUsage(exitZero) == .failed(.transient(.authenticationFailed)))
        let otherError = fixture.text.replacingOccurrences(of: "authentication failed or timed out", with: "something new")
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 1, otherError)) == .failed(.transient(.clientError)))
    }

    /// The sign-in prompt on stderr is positive evidence of a signed-out account, whatever
    /// stdout held when the run was ended.
    @Test func aSignInPromptOnStderrIsSignedOut() throws {
        let fixture = try AntigravityFixture.load("usage-signed-out")
        for stdout in [Data(), fixture.stdout] {
            for exit: Int32? in [nil, 0, 1] {
                let run = AntigravityRunOutput(
                    exitCode: exit, stdout: stdout, overflowed: false, timedOut: false, showedSignInPrompt: true
                )
                #expect(AntigravityUsageClassifier.classifyUsage(run) == .failed(.signedOut))
                #expect(AntigravityUsageClassifier.classifyCredits(run) == .signedOut)
            }
        }
    }

    @Test func theSignInMarkerMatchesTheCapturedStderrOnly() throws {
        let stderr = try AntigravityFixture.loadStderr("usage-signed-out")
        #expect(AntigravityUsageClassifier.showsSignInPrompt(stderr))
        // Split across two reads, the marker is still found.
        let text = String(decoding: stderr, as: UTF8.self)
        let cut = text.index(text.startIndex, offsetBy: 9)
        var scanner = AntigravitySignInPromptScanner()
        let first = scanner.scan(Data(text[..<cut].utf8))
        let second = scanner.scan(Data(text[cut...].utf8))
        #expect(!first)
        #expect(second)
        for other in [
            "", "warning: telemetry disabled\n", "authentication failed or timed out\n",
            "407 Proxy Authentication Required\n", "511 Network Authentication Required\n",
        ] {
            #expect(!AntigravityUsageClassifier.showsSignInPrompt(Data(other.utf8)), "\(other)")
        }
    }

    /// agy's other sign-in lines are sign-outs too, also when split between two reads.
    @Test(arguments: [
        "Waiting for authentication...\n",
        "Waiting for authentication (timeout 60s)...\n",
        "Error: authentication required. Run 'agy acp --login' to log in, then retry.\n",
        "Please visit the URL to log in: https://accounts.google.com/\n",
    ])
    func agysOtherSignInLinesAreSignedOut(line: String) {
        #expect(AntigravityUsageClassifier.showsSignInPrompt(Data(line.utf8)))
        for cut in 1..<min(line.count, 30) {
            var scanner = AntigravitySignInPromptScanner()
            let index = line.index(line.startIndex, offsetBy: cut)
            let first = scanner.scan(Data(line[..<index].utf8))
            let second = scanner.scan(Data(line[index...].utf8))
            #expect(first || second, "cut \(cut)")
        }
    }

    @Test(arguments: ["usage-one-turn", "usage-output-tokens"])
    func anAnswerThatCostATurnOrTokensIsUnsupportedClient(name: String) throws {
        #expect(AntigravityUsageClassifier.classifyUsage(try AntigravityFixture.load(name).output) == .failed(.unsupportedClient))
    }

    @Test func aSuccessWithoutACommandOrTurnCountsIsUnsupportedClient() throws {
        let noCommand = #"{"status":"SUCCESS","response":"Here is your usage...","num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0}}"#
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, noCommand)) == .failed(.unsupportedClient))
        let noTurns = try editedUsage(#""num_turns":0,"#, with: "")
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, noTurns)) == .failed(.unsupportedClient))
        let noUsage = try editedUsage(
            #""usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},"#,
            with: "")
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, noUsage)) == .failed(.unsupportedClient))
        // The guard holds whatever the exit status.
        let turn = try AntigravityFixture.load("usage-one-turn")
        let failedTurn = AntigravityRunOutput(exitCode: 3, stdout: turn.stdout, overflowed: false, timedOut: false)
        #expect(AntigravityUsageClassifier.classifyUsage(failedTurn) == .failed(.unsupportedClient))
    }

    @Test func noRecognisedBucketIsFormatChanged() throws {
        let renamed = try editedUsage(#""window":"5h""#, with: #""window":"daily""#)
            .replacingOccurrences(of: #""window":"weekly""#, with: #""window":"monthly""#)
        #expect(AntigravityUsageClassifier.classifyUsage(output(exit: 0, renamed)) == .failed(.formatChanged(.usageValues)))
        // An unknown pool alongside known ones is skipped, not guessed into a pool.
        let newPool = try editedUsage(#""id":"3p-weekly""#, with: #""id":"other-weekly""#)
        let read = try #require(buckets(AntigravityUsageClassifier.classifyUsage(output(exit: 0, newPool))))
        #expect(read.count == 3)
    }

    @Test func liveCreditsReadZeroAndDerivedReadTwelveHundred() throws {
        #expect(AntigravityUsageClassifier.classifyCredits(try AntigravityFixture.load("credits-live").output) == .balance(0))
        #expect(AntigravityUsageClassifier.classifyCredits(try AntigravityFixture.load("credits-1200").output) == .balance(1200))
    }

    @Test func malformedCreditsAreUnavailable() throws {
        let live = try AntigravityFixture.load("credits-live").text
        let cases: [AntigravityRunOutput?] = [
            nil,
            output(exit: 0, live.replacingOccurrences(of: #""remaining_credits":0"#, with: #""remaining_credits":"lots""#)),
            output(exit: 0, live.replacingOccurrences(of: #""remaining_credits":0"#, with: #""remaining_credits":-5"#)),
            output(exit: 0, live.replacingOccurrences(of: #""name":"credits""#, with: #""name":"usage""#)),
            output(exit: 1, live),
            output(exit: nil, "", timedOut: true),
            output(exit: nil, "not json", timedOut: true),
            output(exit: 0, ""),
        ]
        for run in cases {
            #expect(AntigravityUsageClassifier.classifyCredits(run) == .unavailable)
        }
    }

    @Test func creditsThatCanNotProveNoTurnAreUnsupportedClient() {
        #expect(AntigravityUsageClassifier.classifyCredits(output(exit: 0, "not json")) == .unsupportedClient)
        #expect(AntigravityUsageClassifier.classifyCredits(output(exit: 0, "", overflowed: true)) == .unsupportedClient)
    }

    @Test func creditsThatCostATurnAreUnsupportedClient() throws {
        let live = try AntigravityFixture.load("credits-live").text
        #expect(AntigravityUsageClassifier.classifyCredits(
            output(exit: 0, live.replacingOccurrences(of: #""num_turns":0"#, with: #""num_turns":2"#))) == .unsupportedClient)
        #expect(AntigravityUsageClassifier.classifyCredits(
            output(exit: 0, live.replacingOccurrences(of: #""input_tokens":0"#, with: #""input_tokens":40"#))) == .unsupportedClient)
    }

    @Test func versionGateIsOnePointFiveNineOrNewer() {
        let cases: [(String, AntigravityCaptureFailure?)] = [
            ("1.5.9\n", nil),
            ("1.6.0\n", nil),
            ("2.0.0", nil),
            ("1.5.8\n", .updateRequired),
            ("1.1.11\n", .updateRequired),
        ]
        for (text, expected) in cases {
            #expect(AntigravityUsageClassifier.classifyVersion(output(exit: 0, text)) == expected, "\(text)")
        }
        let unreadable: [AntigravityRunOutput?] = [
            nil,
            output(exit: 0, "warning\n1.5.9\n"),
            output(exit: 1, "1.5.9\n"),
            output(exit: nil, "1.5.9\n", timedOut: true),
            output(exit: 0, "", overflowed: true),
        ]
        for run in unreadable {
            #expect(AntigravityUsageClassifier.classifyVersion(run) == .transient(.unreadableVersion))
        }
    }

    @Test func noCaptureCarriesResponseTextOrDescriptions() throws {
        for name in AntigravityFixture.manifest where !name.hasPrefix("version") {
            let fixture = try AntigravityFixture.load(name)
            let text = String(describing: AntigravityUsageClassifier.classifyUsage(fixture.output))
                + String(describing: AntigravityUsageClassifier.classifyCredits(fixture.output))
            for leak in ["Models within", "Gemini 4", "refresh in", "Limit Remaining", "authentication failed", "accounts.google"] {
                #expect(!text.contains(leak), "\(name) leaked \(leak)")
            }
        }
    }

    @Test func commandsAreTheClosedSet() {
        #expect(AntigravityCommand.allCases.count == 3)
        #expect(AntigravityCommand.version.arguments == ["--version"])
        #expect(AntigravityCommand.usage.arguments == ["-p", "/usage", "--output-format", "json"])
        #expect(AntigravityCommand.credits.arguments == ["-p", "/credits", "--output-format", "json"])
        for command in AntigravityCommand.allCases {
            // Slash expansion is what routes the read to the no-turn answer.
            #expect(!command.arguments.contains("--disable-slash-commands"))
            #expect(command.sizeCap > 0)
        }
    }
}

// MARK: - Process

/// One generic fake `agy`, always run as `/bin/sh <script>` (BUGS.md "text file busy"). Each
/// test gives it its own directory through `FAKE_AGY_DIR`; per command the script logs its
/// argv, runs an optional `<command>.pre` hook, prints `<command>.stdout` and exits with
/// `<command>.exit`.
private enum FakeAgyScript {
    static let body = """
    dir="$FAKE_AGY_DIR"
    printf '%s\\n' "$*" >> "$dir/argv.log"
    case "$*" in
      "--version") name=version ;;
      "-p /usage --output-format json") name=usage ;;
      "-p /credits --output-format json") name=credits ;;
      *) name=unknown ;;
    esac
    pwd -P > "$dir/$name.pwd"
    echo $$ >> "$dir/$name.pids"
    if [ -f "$dir/$name.pre" ]; then . "$dir/$name.pre"; fi
    if [ -f "$dir/$name.stdout" ]; then cat "$dir/$name.stdout"; fi
    if [ -f "$dir/$name.exit" ]; then exit "$(cat "$dir/$name.exit")"; fi
    exit 0
    """

    static let shared: String = write(to: FileManager.default.temporaryDirectory
        .appendingPathComponent("headroom-agy-fake-\(UUID().uuidString)", isDirectory: true))

    static func write(to directory: URL) -> String {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("agy")
        try? Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}

private final class ResolveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String
    init(_ value: String) { stored = value }
    var value: String {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private struct FakeAgy {
    let directory: URL
    let workingDirectory: URL
    let script: String

    init(privateScript: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-agy-test-\(UUID().uuidString)", isDirectory: true)
        workingDirectory = directory.appendingPathComponent("AntigravityProbe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        script = privateScript
            ? FakeAgyScript.write(to: directory.appendingPathComponent("bin", isDirectory: true))
            : FakeAgyScript.shared
        try set("version", fixture: "version-live")
        try set("usage", fixture: "usage-live")
        try set("credits", fixture: "credits-live")
    }

    func set(_ command: String, stdout: String, exit: Int32) throws {
        try Data(stdout.utf8).write(to: directory.appendingPathComponent("\(command).stdout"))
        try Data("\(exit)\n".utf8).write(to: directory.appendingPathComponent("\(command).exit"))
    }

    func set(_ command: String, fixture name: String) throws {
        let fixture = try AntigravityFixture.load(name)
        try fixture.stdout.write(to: directory.appendingPathComponent("\(command).stdout"))
        try Data("\(fixture.exit)\n".utf8).write(to: directory.appendingPathComponent("\(command).exit"))
    }

    func hook(_ command: String, pre: String) throws {
        try Data(pre.utf8).write(to: directory.appendingPathComponent("\(command).pre"))
    }

    func source(
        deadline: TimeInterval = 10,
        resolveCount: ResolveCounter? = nil,
        executable: String? = nil,
        found: Bool = true,
        resolve: (@Sendable () -> String?)? = nil,
        environment: [String: String] = [:],
        memory: AntigravityProbeMemory = .none
    ) -> AntigravityCLIUsageSource {
        let script = executable ?? script
        let dir = directory.path
        return AntigravityCLIUsageSource(
            resolveExecutable: resolve ?? { resolveCount?.increment(); return found ? script : nil },
            resolveLoginPath: { "/usr/bin:/bin" },
            inheritedEnvironment: { environment.merging(["FAKE_AGY_DIR": dir]) { $1 } },
            workingDirectory: workingDirectory.path,
            deadline: deadline,
            versionDeadline: 5,
            interpreter: "/bin/sh",
            memory: memory
        )
    }

    var argv: [String] {
        (try? String(contentsOf: directory.appendingPathComponent("argv.log"), encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
    }

    func count(_ command: AntigravityCommand) -> Int {
        argv.filter { $0 == command.arguments.joined(separator: " ") }.count
    }

    func pids(_ command: String) -> [pid_t] {
        ((try? String(contentsOf: directory.appendingPathComponent("\(command).pids"), encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { pid_t($0) }
    }

    func text(_ file: String) -> String {
        ((try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func touch(secondsAgo: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -secondsAgo)], ofItemAtPath: script
        )
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func isRunning(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

/// A user-requested probe, by default the kind a launch, Refresh or phone Check Now makes.
private func userRequested(
    _ source: AntigravityCLIUsageSource, origin: UserRefreshOrigin = .fullRefresh
) async -> AntigravityCapture {
    await UserRequestedProbeContext.$isUserRequested.withValue(true) {
        await UserRequestedProbeContext.$origins.withValue([origin]) { await source.capture() }
    }
}

/// `AntigravityProbeMemory` over one in-test store, standing in for Preferences across a relaunch.
private final class MemoryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped: AntigravityStoppedClient?
    private var signedOut = false
    private(set) var writes = 0

    var memory: AntigravityProbeMemory {
        AntigravityProbeMemory(
            loadStoppedClient: { self.lock.withLock { self.stopped } },
            saveStoppedClient: { value in self.lock.withLock { self.stopped = value; self.writes += 1 } },
            loadSignedOut: { self.lock.withLock { self.signedOut } },
            saveSignedOut: { value in self.lock.withLock { self.signedOut = value; self.writes += 1 } }
        )
    }

    var storedStop: AntigravityStoppedClient? { lock.withLock { stopped } }
    var storedSignedOut: Bool { lock.withLock { signedOut } }
}

struct AntigravityUsageSourceProcessTests {
    @Test func liveFixturesReturnFourBucketsAndZeroCredits() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        guard case .usage(let usage) = await fake.source().capture() else {
            Issue.record("expected a usage reading")
            return
        }
        #expect(usage.buckets.count == 4)
        #expect(usage.credits == 0)
        #expect(fake.argv == ["--version", "-p /usage --output-format json", "-p /credits --output-format json"])
    }

    @Test func creditsAreReadWhenAboveZero() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        try fake.set("credits", fixture: "credits-1200")
        guard case .usage(let usage) = await fake.source().capture() else {
            Issue.record("expected a usage reading")
            return
        }
        #expect(usage.credits == 1200)
    }

    @Test func malformedCreditsLeaveTheUsageReadingIntact() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        let live = try AntigravityFixture.load("credits-live").text
        try fake.set("credits", stdout: live.replacingOccurrences(of: #""remaining_credits":0"#, with: #""remaining_credits":"lots""#), exit: 0)
        guard case .usage(let usage) = await fake.source().capture() else {
            Issue.record("a malformed credits payload failed the usage reading")
            return
        }
        #expect(usage.buckets.count == 4)
        #expect(usage.credits == nil)
    }

    @Test func aFailedUsageReadSkipsCredits() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        try fake.set("usage", stdout: "", exit: 1)
        #expect(await fake.source().capture() == .failed(.transient(.unexpectedExit)))
        #expect(fake.count(.credits) == 0)
    }

    @Test func aProcessThatOutlivesTheDeadlineIsKilledWithItsGroup() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        try fake.hook("usage", pre: "sleep 120 &\necho $! > \"$dir/child.pid\"\nwait\n")
        let started = Date()
        #expect(await fake.source(deadline: 3).capture() == .failed(.transient(.deadline)))
        #expect(Date().timeIntervalSince(started) < 30)
        let leader = try #require(fake.pids("usage").first)
        let child = try #require(pid_t(fake.text("child.pid")))
        #expect(!isRunning(leader))
        #expect(!isRunning(child))
    }

    @Test func outputOverTheCapStopsPolling() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        try fake.set("usage", stdout: String(repeating: "x", count: AntigravityCommand.usage.sizeCap + 1_024), exit: 0)
        let source = fake.source()
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(fake.pids("usage").count == 1)
    }

    @Test func aMissingExecutableIsCLIMissingAndNotCached() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        let counter = ResolveCounter()
        let missing = fake.source(resolveCount: counter, found: false)
        #expect(await missing.capture() == .failed(.cliMissing))
        #expect(await missing.capture() == .failed(.cliMissing))
        #expect(counter.count == 2)
        let notExecutable = fake.directory.appendingPathComponent("usage.exit").path
        #expect(await fake.source(executable: notExecutable).capture() == .failed(.cliMissing))
        #expect(fake.argv.isEmpty)
    }

    @Test func routinePollsReuseTheResolvedPathAndUserRequestsSearchAgain() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        let counter = ResolveCounter()
        let source = fake.source(resolveCount: counter)
        _ = await source.capture()
        _ = await source.capture()
        #expect(counter.count == 1)
        _ = await userRequested(source)
        #expect(counter.count == 2)
    }

    @Test func aPassingVersionIsReusedUntilTheExecutableChanges() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        let source = fake.source()
        _ = await source.capture()
        _ = await source.capture()
        #expect(fake.count(.version) == 1)
        try fake.touch(secondsAgo: 3_600)
        _ = await source.capture()
        #expect(fake.count(.version) == 2)
        #expect(fake.count(.usage) == 3)
    }

    @Test func aVersionBelowTheFloorNeverRunsTheUsageRead() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        try fake.set("version", stdout: "1.5.8\n", exit: 0)
        #expect(await fake.source().capture() == .failed(.updateRequired))
        #expect(fake.argv == ["--version"])
    }

    @Test func theCapturedSignedOutAnswerIsTransient() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        try fake.set("usage", fixture: "usage-signed-out")
        #expect(await fake.source().capture() == .failed(.transient(.authenticationFailed)))
    }

    /// The client waits up to 60 s on an interactive Google sign-in it opened itself. The read
    /// ends at the prompt, and no routine poll runs the client again until the user asks.
    @Test func aSignInPromptEndsTheReadAndStopsRoutinePolls() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try FileManager.default.copyItem(
            at: try #require(Bundle.module.url(forResource: "antigravity-usage-signed-out", withExtension: "stderr")),
            to: fake.directory.appendingPathComponent("usage.stderr")
        )
        try fake.hook("usage", pre: "cat \"$dir/usage.stderr\" >&2\nsleep 60 &\necho $! > \"$dir/child.pid\"\nwait\n")
        let source = fake.source(deadline: 30)
        let started = Date()
        #expect(await source.capture() == .failed(.signedOut))
        #expect(Date().timeIntervalSince(started) < 10, "the read waited on the sign-in")
        let leader = try #require(fake.pids("usage").first)
        let child = try #require(pid_t(fake.text("child.pid")))
        #expect(!isRunning(leader))
        #expect(!isRunning(child))
        #expect(fake.count(.credits) == 0)

        let spawned = fake.argv.count
        #expect(await source.capture() == .failed(.signedOut))
        #expect(await source.capture() == .failed(.signedOut))
        #expect(fake.argv.count == spawned, "a routine poll ran agy while signed out")

        // A full refresh while still signed out re-checks with browser launches suppressed and
        // stays signed out without letting routine polls resume.
        #expect(await userRequested(source, origin: .fullRefresh) == .failed(.signedOut))
        #expect(fake.count(.usage) == 2)
        let afterFullRefresh = fake.argv.count
        #expect(await source.capture() == .failed(.signedOut))
        #expect(fake.argv.count == afterFullRefresh, "routine poll ran agy after signed-out full refresh")

        // Once the user signs back in outside Headroom, Refresh recovers automatically.
        try fake.hook("usage", pre: "")
        #expect(buckets(await userRequested(source, origin: .fullRefresh))?.count == 4)
        #expect(fake.count(.usage) == 3)
        #expect(buckets(await source.capture())?.count == 4)
        #expect(fake.count(.usage) == 4)
    }

    /// The check after a sign-in through Headroom clears the mark, even when a full refresh
    /// was coalesced into the same probe.
    @Test func theCheckAfterASignInThroughHeadroomReadsAgain() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.hook("usage", pre: "echo 'Authentication required. Please visit the URL to log in:' >&2\nsleep 60\n")
        let source = fake.source(deadline: 30)
        #expect(await source.capture() == .failed(.signedOut))
        try fake.hook("usage", pre: "")
        let coalesced = await UserRequestedProbeContext.$isUserRequested.withValue(true) {
            await UserRequestedProbeContext.$origins.withValue([.fullRefresh, .setupCheck]) { await source.capture() }
        }
        #expect(buckets(coalesced)?.count == 4)
    }

    /// A relaunch keeps the signed-out mark for routine polls, while an explicit Refresh recovers
    /// once the user has signed back into `agy` outside Headroom.
    @Test func theSignedOutMarkSurvivesARelaunch() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        let box = MemoryBox()
        try fake.hook("usage", pre: "echo 'Waiting for authentication (timeout 60s)...' >&2\nsleep 60\n")
        #expect(await fake.source(deadline: 30, memory: box.memory).capture() == .failed(.signedOut))
        #expect(box.storedSignedOut)

        let spawned = fake.argv.count
        let relaunched = fake.source(deadline: 30, memory: box.memory)
        #expect(await relaunched.capture() == .failed(.signedOut))
        #expect(fake.argv.count == spawned, "a routine poll after relaunch ran agy while signed out")

        // A full refresh while still signed out keeps the persisted signed-out mark.
        #expect(await userRequested(relaunched, origin: .fullRefresh) == .failed(.signedOut))
        #expect(box.storedSignedOut)

        // After signing in externally, Refresh clears the mark and reads live usage.
        try fake.hook("usage", pre: "")
        #expect(buckets(await userRequested(relaunched, origin: .fullRefresh))?.count == 4)
        #expect(!box.storedSignedOut)
    }

    /// A relaunch keeps the safety stop, keyed by path, modification date and version.
    @Test func theSafetyStopSurvivesARelaunch() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        let box = MemoryBox()
        try fake.set("usage", fixture: "usage-one-turn")
        #expect(await fake.source(memory: box.memory).capture() == .failed(.unsupportedClient))
        let stored = try #require(box.storedStop)
        #expect(stored.path != nil)
        #expect(stored.modified != nil)
        #expect(stored.version == AntigravityVersion(major: 1, minor: 5, patch: 9))

        try fake.set("usage", fixture: "usage-live")
        let spawned = fake.argv.count
        let relaunched = fake.source(memory: box.memory)
        #expect(await relaunched.capture() == .failed(.unsupportedClient))
        #expect(fake.argv.count == spawned, "a relaunch spawned a stopped client")

        // An update (new modification date) lifts the stop and clears the stored setting.
        try fake.touch(secondsAgo: 3_600)
        #expect(buckets(await fake.source(memory: box.memory).capture())?.count == 4)
        #expect(box.storedStop == nil)
    }

    /// Variables that would move agy onto an API key or Cloud credentials never reach it.
    @Test func apiKeyAndCloudCredentialVariablesAreStripped() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.hook("usage", pre: "env > \"$dir/usage.env\"\n")
        var environment: [String: String] = ["KEEP_ME": "1"]
        for name in AntigravityCLIUsageSource.strippedEnvironment { environment[name] = "x" }
        #expect(buckets(await fake.source(environment: environment).capture())?.count == 4)
        let seen = fake.text("usage.env")
        #expect(seen.contains("KEEP_ME=1"))
        for name in AntigravityCLIUsageSource.strippedEnvironment {
            #expect(!seen.contains("\(name)="), "\(name)")
        }
    }

    /// Probes suppress browser launches (via a `no-browser` `open -> /usr/bin/false` shim ahead
    /// of PATH plus `BROWSER=/usr/bin/false`) and disable agy's background auto-updater without
    /// setting `SSH_CONNECTION` or writing inside the probe working folder.
    @Test func probesSuppressBrowserLaunchesAndBackgroundUpdaterWithoutSSHConnection() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.hook("usage", pre: "env > \"$dir/usage.env\"\ncommand -v open > \"$dir/usage.open\"\n")
        try fake.hook("credits", pre: "env > \"$dir/credits.env\"\ncommand -v open > \"$dir/credits.open\"\n")
        let source = fake.source(environment: ["BROWSER": "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"])
        #expect(buckets(await source.capture())?.count == 4)

        let noBrowserDir = await source.noBrowserBinDirectoryPath
        let expectedOpen = (noBrowserDir as NSString).appendingPathComponent("open")
        let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: expectedOpen)
        #expect(linkTarget == "/usr/bin/false")

        for command in ["usage", "credits"] {
            let envText = fake.text("\(command).env")
            let comment = Comment(rawValue: command)
            #expect(envText.contains("BROWSER=/usr/bin/false"), comment)
            #expect(envText.contains("AGY_CLI_DISABLE_AUTO_UPDATE=true"), comment)
            #expect(!envText.contains("SSH_CONNECTION="), comment)
            #expect(fake.text("\(command).open") == expectedOpen, comment)
        }

        // The working directory itself stays empty.
        let contents = try FileManager.default.contentsOfDirectory(atPath: fake.workingDirectory.path)
        #expect(contents.isEmpty)
    }

    @Test func aSignInPromptOnTheCreditsReadIsSignedOutToo() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.hook("credits", pre: "echo 'Authentication required. Please visit the URL to log in:' >&2\nsleep 60\n")
        let source = fake.source(deadline: 30)
        #expect(await source.capture() == .failed(.signedOut))
        let spawned = fake.argv.count
        #expect(await source.capture() == .failed(.signedOut))
        #expect(fake.argv.count == spawned)
    }

    /// `agy`'s `keyringAuth` falls into interactive OAuth when a stored-token refresh stalls past
    /// its 10 s timeout even while Keychain is still signed in. After a live reading, a single
    /// routine-poll sign-in prompt stays transient and recovers automatically on the next poll.
    @Test func aSingleSignInPromptAfterALiveReadIsTransientAndRecoversOnNextRoutinePoll() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        let box = MemoryBox()
        let source = fake.source(deadline: 30, memory: box.memory)
        #expect(buckets(await source.capture())?.count == 4)

        try fake.hook("usage", pre: "echo 'Authentication required. Please visit the URL to log in:' >&2\nsleep 60\n")
        #expect(await source.capture() == .failed(.transient(.authenticationFailed)))
        #expect(!box.storedSignedOut)

        try fake.hook("usage", pre: "")
        #expect(buckets(await source.capture())?.count == 4)
        #expect(!box.storedSignedOut)
        #expect(fake.count(.usage) == 3)
    }

    /// Two consecutive routine-poll sign-in prompts after a live reading confirm the sign-out,
    /// persist the mark, and stop further routine polls.
    @Test func twoConsecutiveSignInPromptsAfterALiveReadConfirmSignedOut() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        let box = MemoryBox()
        let source = fake.source(deadline: 30, memory: box.memory)
        #expect(buckets(await source.capture())?.count == 4)

        try fake.hook("usage", pre: "echo 'Authentication required. Please visit the URL to log in:' >&2\nsleep 60\n")
        #expect(await source.capture() == .failed(.transient(.authenticationFailed)))
        #expect(!box.storedSignedOut)

        #expect(await source.capture() == .failed(.signedOut))
        #expect(box.storedSignedOut)

        let spawned = fake.argv.count
        #expect(await source.capture() == .failed(.signedOut))
        #expect(fake.argv.count == spawned, "routine poll ran agy after confirmed sign-out")
    }

    @Test(arguments: ["usage-one-turn", "usage-output-tokens"])
    func anAnswerThatCostATurnStopsEveryLaterSpawn(name: String) async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.set("usage", fixture: name)
        let source = fake.source()
        #expect(await source.capture() == .failed(.unsupportedClient))
        let spawned = fake.argv.count
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(fake.argv.count == spawned, "a sticky failure spawned agy again")
        #expect(fake.count(.credits) == 0)
    }

    @Test func creditsThatCostATurnStopEveryLaterSpawn() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        let live = try AntigravityFixture.load("credits-live").text
        try fake.set("credits", stdout: live.replacingOccurrences(of: #""num_turns":0"#, with: #""num_turns":1"#), exit: 0)
        let source = fake.source()
        #expect(await source.capture() == .failed(.unsupportedClient))
        let spawned = fake.argv.count
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(fake.argv.count == spawned)
    }

    @Test func theStickyFailureClearsWhenTheModificationDateChanges() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.set("usage", fixture: "usage-one-turn")
        let source = fake.source()
        #expect(await source.capture() == .failed(.unsupportedClient))
        try fake.set("usage", fixture: "usage-live")
        #expect(await source.capture() == .failed(.unsupportedClient))
        try fake.touch(secondsAgo: 3_600)
        #expect(buckets(await source.capture())?.count == 4)
    }

    @Test func theStickyFailureClearsWhenTheVersionChanges() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.set("usage", fixture: "usage-one-turn")
        let source = fake.source()
        #expect(await source.capture() == .failed(.unsupportedClient))
        // An unchanged version behind an unchanged file stays stopped, even on a user request,
        // and that request runs only the local version print.
        #expect(await userRequested(source) == .failed(.unsupportedClient))
        #expect(fake.count(.usage) == 1)
        // A version manager swapped the version behind the same file.
        try fake.set("version", stdout: "1.6.0\n", exit: 0)
        try fake.set("usage", fixture: "usage-live")
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(buckets(await userRequested(source))?.count == 4)
    }

    @Test func theStickyFailureClearsWhenTheResolvedPathChanges() async throws {
        let fake = try FakeAgy(privateScript: true)
        defer { fake.remove() }
        try fake.set("usage", fixture: "usage-one-turn")
        let path = PathBox(fake.script)
        let source = fake.source(resolve: { path.value })
        #expect(await source.capture() == .failed(.unsupportedClient))
        // Reinstalled elsewhere: the old path is gone, so the next poll resolves again.
        let moved = FakeAgyScript.write(to: fake.directory.appendingPathComponent("moved", isDirectory: true))
        try FileManager.default.removeItem(atPath: fake.script)
        path.value = moved
        try fake.set("usage", fixture: "usage-live")
        #expect(buckets(await source.capture())?.count == 4)
    }

    @Test func spawnsUseOnlyTheClosedSetInTheProbeFolder() async throws {
        let fake = try FakeAgy()
        defer { fake.remove() }
        _ = await fake.source().capture()
        let allowed = Set(AntigravityCommand.allCases.map { $0.arguments.joined(separator: " ") })
        #expect(Set(fake.argv) == allowed)
        func physical(_ path: String) -> String? {
            guard let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let expected = try #require(physical(fake.workingDirectory.path))
        #expect(fake.text("usage.pwd") == expected)
        #expect(fake.text("credits.pwd") == expected)
    }
}
