import Darwin
import Foundation
import Testing
@testable import HeadroomCore

// U2 (OpenCode plan). Classification is pinned to U12's captures of the real v2.2.5 client
// against the stub Console (KTD17); process tests run a fake `opencode` as `/bin/sh <script>`
// that prints those same captures, so neither the real client nor any OpenCode home is touched.

// MARK: - Fixtures

private struct OpenCodeFixture {
    let name: String
    let stdout: Data
    let exit: Int32
    let capturedAt: Date

    static let manifest: [String: Double] = {
        guard let url = Bundle.module.url(forResource: "opencode-fixtures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fixtures = object["fixtures"] as? [[String: Any]]
        else { return [:] }
        var result: [String: Double] = [:]
        for fixture in fixtures {
            if let name = fixture["name"] as? String, let ms = fixture["capturedAtMs"] as? Double {
                result[name] = ms
            }
        }
        return result
    }()

    static func load(_ name: String) throws -> OpenCodeFixture {
        let stdoutURL = try #require(Bundle.module.url(forResource: "opencode-\(name)", withExtension: "stdout"))
        let exitURL = try #require(Bundle.module.url(forResource: "opencode-\(name)", withExtension: "exit"))
        let exitText = try String(contentsOf: exitURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = try #require(manifest[name], "\(name) is missing from the manifest")
        return OpenCodeFixture(
            name: name,
            stdout: try Data(contentsOf: stdoutURL),
            exit: try #require(Int32(exitText)),
            capturedAt: Date(timeIntervalSince1970: ms / 1_000)
        )
    }

    var output: OpenCodeRunOutput {
        OpenCodeRunOutput(exitCode: exit, stdout: stdout, overflowed: false, timedOut: false)
    }
}

private func output(exit: Int32?, _ text: String, overflowed: Bool = false, timedOut: Bool = false) -> OpenCodeRunOutput {
    OpenCodeRunOutput(exitCode: exit, stdout: Data(text.utf8), overflowed: overflowed, timedOut: timedOut)
}

private let goWindowsLine = #"{"location":{"directory":"/x"},"data":{"workspace":{"id":"w","name":"n","usageURL":"u"},"go":{"rolling":{"percent":29,"limited":false,"resetsAt":1794541199409},"weekly":{"percent":47,"limited":false,"resetsAt":1794810479409},"monthly":{"percent":63,"limited":false,"resetsAt":1796030879409}}}}"#

// MARK: - Classification (pure)

struct OpenCodeUsageClassifierTests {
    /// Every captured fixture, by kind, with its KTD4 / KTD20 / KTD3 result.
    private static let usageTable: [String: OpenCodeUsageClassifier.UsageStep] = [
        "nogo": .done(.noGoPlan),
        "signed-out": .needsAuthList,
        "api-key": .needsAuthList,
        "go-key": .needsAuthList,
        "no-workspace": .needsAuthList,
        "expired": .done(.failed(.signInExpired)),
        "revoked": .done(.failed(.signInExpired)),
        "refreshbad": .done(.failed(.signInExpired)),
        "err500": .done(.failed(.transient(.consoleUnavailable))),
        "slow": .done(.failed(.transient(.consoleUnavailable))),
        "stub-down": .done(.failed(.transient(.consoleUnavailable))),
        "malformed": .done(.failed(.formatChanged(.clientDecode))),
        "wrongshape": .done(.failed(.formatChanged(.clientDecode))),
        "unknown-operation": .needsOperationList,
        "plugins-not-activated": .done(.failed(.transient(.pluginsNotActivated))),
        "standalone-start-failed": .done(.failed(.transient(.serverStartFailed))),
    ]
    private static let liveFixtures = ["go", "go-limited", "go-oauth", "refreshok", "go-real"]
    private static let authTable: [String: OpenCodeCapture] = [
        "auth-list-signed-out": .failed(.signedOut),
        "auth-list-api-key": .failed(.consoleSignInRequired),
        "auth-list-go-key": .failed(.consoleSignInRequired),
        "auth-list-oauth": .noGoPlan,
        "auth-list-no-workspace": .noGoPlan,
        "auth-list-key-then-oauth": .noGoPlan,
    ]
    private static let operationTable: [String: OpenCodeCapture] = [
        "operations": .failed(.transient(.clientFailed)),
        "operations-missing": .failed(.formatChanged(.operationMissing)),
    ]
    private static let versionTable: [String: OpenCodeCaptureFailure?] = [
        "version-2x": nil,
        "version-1x": .updateRequired,
    ]

    @Test func everyManifestFixtureHasAnExpectedResult() {
        let covered = Set(Self.usageTable.keys).union(Self.liveFixtures).union(Self.authTable.keys)
            .union(Self.operationTable.keys).union(Self.versionTable.keys)
        #expect(!OpenCodeFixture.manifest.isEmpty)
        #expect(Set(OpenCodeFixture.manifest.keys) == covered)
    }

    @Test(arguments: Array(usageTable.keys))
    func usageFixtureMapsToItsKTD4Result(name: String) throws {
        let fixture = try OpenCodeFixture.load(name)
        #expect(OpenCodeUsageClassifier.classifyUsage(fixture.output) == Self.usageTable[name])
    }

    @Test(arguments: ["go", "go-oauth", "refreshok"])
    func liveFixtureReadsThreeWindowsByName(name: String) throws {
        let fixture = try OpenCodeFixture.load(name)
        guard case .done(.goUsage(let usage)) = OpenCodeUsageClassifier.classifyUsage(fixture.output) else {
            Issue.record("\(name) did not read as live Go usage")
            return
        }
        #expect([usage.rolling.percentUsed, usage.weekly.percentUsed, usage.monthly.percentUsed] == [29, 47, 63])
        #expect(![usage.rolling.isLimited, usage.weekly.isLimited, usage.monthly.isLimited].contains(true))
        // resetsAt is milliseconds; the stub put each reset a fixed span after the capture.
        let now = fixture.capturedAt
        #expect(abs(usage.rolling.resetsAt.timeIntervalSince(now) - 11_520) < 5)
        #expect(abs(usage.weekly.resetsAt.timeIntervalSince(now) - 280_800) < 5)
        #expect(abs(usage.monthly.resetsAt.timeIntervalSince(now) - 1_501_200) < 5)
    }

    /// The one fixture that is not stub-derived: a real Go response captured on 2026-11-13 with
    /// client 2.2.7, minutes after subscribing and before any use. It pins the real field names,
    /// that `resetsAt` is milliseconds, and the three reset spans a real account reported.
    @Test func realGoResponseReadsThreeUnusedWindows() throws {
        let fixture = try OpenCodeFixture.load("go-real")
        guard case .done(.goUsage(let usage)) = OpenCodeUsageClassifier.classifyUsage(fixture.output) else {
            Issue.record("the real Go response did not read as live Go usage")
            return
        }
        #expect([usage.rolling.percentUsed, usage.weekly.percentUsed, usage.monthly.percentUsed] == [0, 0, 0])
        #expect(![usage.rolling.isLimited, usage.weekly.isLimited, usage.monthly.isLimited].contains(true))
        let now = fixture.capturedAt
        // Unused, the rolling window reports a reset five hours out; weekly ends on a fixed
        // boundary (a whole-second UTC time); monthly ends thirty days after the purchase.
        #expect(abs(usage.rolling.resetsAt.timeIntervalSince(now) - 18_000) < 60)
        #expect(usage.weekly.resetsAt == Date(timeIntervalSince1970: 1_794_787_200))
        #expect(abs(usage.monthly.resetsAt.timeIntervalSince(now) - 2_592_000) < 600)
    }

    @Test func limitedWindowReadsFullyUsedWhateverItReports() throws {
        let fixture = try OpenCodeFixture.load("go-limited")
        guard case .done(.goUsage(let usage)) = OpenCodeUsageClassifier.classifyUsage(fixture.output) else {
            Issue.record("go-limited did not read as live Go usage")
            return
        }
        #expect(usage.monthly == OpenCodeGoWindow(
            percentUsed: 100, isLimited: true, resetsAt: Date(timeIntervalSince1970: 1_796_030_892_655 / 1_000)
        ))
        #expect(usage.rolling.percentUsed == 29 && !usage.rolling.isLimited)

        // KTD6: `limited` is the authority, never the percentage.
        let lowButLimited = goWindowsLine.replacingOccurrences(
            of: #""percent":63,"limited":false"#, with: #""percent":12,"limited":true"#
        )
        guard case .done(.goUsage(let forced)) = OpenCodeUsageClassifier.classifyUsage(output(exit: 0, lowButLimited))
        else {
            Issue.record("limited line did not read as live")
            return
        }
        #expect(forced.monthly.percentUsed == 100)
        #expect(forced.monthly.isLimited)
    }

    @Test(arguments: Array(authTable.keys))
    func authListFixtureMapsToItsKTD20Result(name: String) throws {
        let fixture = try OpenCodeFixture.load(name)
        #expect(OpenCodeUsageClassifier.classifyAuthList(fixture.output) == Self.authTable[name])
    }

    @Test(arguments: Array(operationTable.keys))
    func operationListFixtureMapsToItsKTD4Result(name: String) throws {
        let fixture = try OpenCodeFixture.load(name)
        #expect(OpenCodeUsageClassifier.classifyOperationList(fixture.output) == Self.operationTable[name])
    }

    @Test(arguments: Array(versionTable.keys))
    func versionFixtureMapsToItsKTD3Result(name: String) throws {
        let fixture = try OpenCodeFixture.load(name)
        #expect(OpenCodeUsageClassifier.classifyVersion(fixture.output) == Self.versionTable[name])
    }

    // MARK: Version gate

    @Test func versionParsesBothCapturedForms() {
        #expect(OpenCodeVersion(versionOutput: "opencode v2.2.5\n") == OpenCodeVersion(major: 2, minor: 2, patch: 5))
        #expect(OpenCodeVersion(versionOutput: "1.1.53\n") == OpenCodeVersion(major: 1, minor: 1, patch: 53))
        #expect(OpenCodeVersion(versionOutput: "v2.10.0") == OpenCodeVersion(major: 2, minor: 10, patch: 0))
        #expect(OpenCodeVersion(versionOutput: "OpenCode 2.2.5") == nil)
        #expect(OpenCodeVersion(versionOutput: "") == nil)
        #expect(OpenCodeVersion(versionOutput: "warning: something\nopencode v2.2.5") == nil)
    }

    @Test func gateIsTwoPointTwoOrNewer() {
        let cases: [(String, OpenCodeCaptureFailure?)] = [
            ("opencode v2.2.5", nil),
            ("opencode v2.2.0", nil),
            ("opencode v3.0.0", nil),
            ("opencode v2.1.4", .updateRequired),
            ("opencode v2.1.99", .updateRequired),
            ("1.1.53", .updateRequired),
            ("1.19.5", .updateRequired),
        ]
        for (text, expected) in cases {
            #expect(OpenCodeUsageClassifier.classifyVersion(output(exit: 0, text + "\n")) == expected, "\(text)")
        }
    }

    @Test func unreadableVersionIsTransient() {
        let unreadable: [OpenCodeRunOutput?] = [
            nil,
            output(exit: 0, "something else\n"),
            output(exit: 1, "opencode v2.2.5\n"),
            output(exit: nil, "opencode v2.2.5\n", timedOut: true),
            output(exit: 0, "", overflowed: true),
        ]
        for run in unreadable {
            #expect(OpenCodeUsageClassifier.classifyVersion(run) == .transient(.unreadableVersion))
        }
    }

    // MARK: Usage edges

    @Test func undecodableNonEmptyStdoutIsFormatChanged() {
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, "hello\n")) == .done(.failed(.formatChanged(.usageOutput))))
        // Exit 1 with non-JSON stdout is a client failure (below), not a format change.
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, "hello\n")) == .done(.failed(.transient(.clientFailed))))
        // Exit 0 JSON with no `data` key is another contract, not a null reading.
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, #"{"location":{}}"#))
            == .done(.failed(.formatChanged(.usageOutput))))
        // Exit 1 JSON with no message.
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, #"{"_tag":"X"}"#))
            == .done(.failed(.formatChanged(.usageOutput))))
        // A Go block missing a window, or a window missing its reset.
        let noMonthly = #"{"data":{"go":{"rolling":{"percent":1,"limited":false,"resetsAt":1},"weekly":{"percent":1,"limited":false,"resetsAt":1}}}}"#
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, noMonthly)) == .done(.failed(.formatChanged(.usageOutput))))
        let noReset = goWindowsLine.replacingOccurrences(of: #","resetsAt":1796030879409"#, with: "")
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, noReset)) == .done(.failed(.formatChanged(.usageOutput))))
    }

    /// The built-in home loads the user's plugins, and a plugin can print to stdout before the
    /// client prints its one JSON line. That line still decides the reading.
    @Test func pluginTextBeforeTheEnvelopeStillReads() throws {
        let go = try OpenCodeFixture.load("go")
        let noisy = Data("[my-plugin] loaded 3 tools\n{not json either\n".utf8) + go.stdout
        let run = OpenCodeRunOutput(exitCode: 0, stdout: noisy, overflowed: false, timedOut: false)
        guard case .done(.goUsage(let usage)) = OpenCodeUsageClassifier.classifyUsage(run) else {
            Issue.record("a plugin line before the envelope lost the reading")
            return
        }
        #expect([usage.rolling.percentUsed, usage.weekly.percentUsed, usage.monthly.percentUsed] == [29, 47, 63])
        #expect(!OpenCodeUsageClassifier.clearsVersionMemo(run), "plugin text is not another client")

        let nullReading = try OpenCodeFixture.load("signed-out")
        let noisyNull = OpenCodeRunOutput(
            exitCode: 0, stdout: Data("plugin hello\n".utf8) + nullReading.stdout, overflowed: false, timedOut: false)
        #expect(OpenCodeUsageClassifier.classifyUsage(noisyNull) == .needsAuthList)

        // No envelope line at all stays format changed on exit 0.
        let noEnvelope = output(exit: 0, "plugin hello\n{\"location\":{}}\n")
        #expect(OpenCodeUsageClassifier.classifyUsage(noEnvelope) == .done(.failed(.formatChanged(.usageOutput))))
    }

    /// A crash stack (ENOSPC, EACCES…) is a client failure: transient, never "Contact support".
    @Test func crashStackOnExitOneIsTransient() {
        let stack = """
        Error: ENOSPC: no space left on device, write
            at writeSync (node:fs:936:3)
            at <anonymous> (/$bunfs/root/chunk-abc.js:2:1020)

        """
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, stack)) == .done(.failed(.transient(.clientFailed))))
        // Still: the captured decode errors are format changed, and empty stdout asks for the list.
        let malformed = try? OpenCodeFixture.load("malformed")
        #expect(malformed.map { OpenCodeUsageClassifier.classifyUsage($0.output) } == .done(.failed(.formatChanged(.clientDecode))))
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, "")) == .needsOperationList)
    }

    @Test func invalidResetFailsTheWholeReading() {
        let zeroReset = goWindowsLine.replacingOccurrences(of: "1796030879409", with: "0")
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, zeroReset)) == .done(.failed(.formatChanged(.usageValues))))
        let negative = goWindowsLine.replacingOccurrences(of: "1794541199409", with: "-5")
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, negative)) == .done(.failed(.formatChanged(.usageValues))))
    }

    @Test func goNullReadsAsNoGoPlan() {
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, #"{"data":{"workspace":{},"go":null}}"#)) == .done(.noGoPlan))
    }

    @Test func unrecognizedErrorMessageIsTransientNeverSignIn() {
        let lines = [
            #"{"_tag":"ServiceUnavailableError","message":"Something new happened","service":"opencode"}"#,
            #"{"_tag":"ServiceUnavailableError","message":"(403 GET http://x/zen/go/v1/usage)","service":"opencode"}"#,
            #"{"_tag":"ServiceUnavailableError","message":"(50 GET short code)","service":"opencode"}"#,
        ]
        for line in lines {
            #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, line)) == .done(.failed(.transient(.unrecognizedError))))
        }
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, #"{"message":"(503 GET x)"}"#))
            == .done(.failed(.transient(.consoleUnavailable))))
    }

    @Test func otherExitsAndSignalsAreTransient() {
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 2, goWindowsLine)) == .done(.failed(.transient(.unexpectedExit))))
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 137, "")) == .done(.failed(.transient(.unexpectedExit))))
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: nil, "")) == .done(.failed(.transient(.unexpectedExit))))
    }

    @Test func whitespaceOnlyStdoutOnExitOneAsksForTheOperationList() {
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, "\n  \n")) == .needsOperationList)
        // Exit 0 with nothing printed is not a reading.
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, "")) == .done(.failed(.formatChanged(.usageOutput))))
    }

    @Test func deadlineIsTransientUnlessAValidLineWasPrinted() throws {
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: nil, "", timedOut: true)) == .done(.failed(.transient(.deadline))))
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: nil, #"{"message":"Reconnect OpenCode Console"}"#, timedOut: true))
            == .done(.failed(.transient(.deadline))))
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: nil, #"{"location":{},"data":null}"# + "\n", timedOut: true))
            == .needsAuthList)
        let go = try OpenCodeFixture.load("go")
        guard case .done(.goUsage) = OpenCodeUsageClassifier.classifyUsage(
            OpenCodeRunOutput(exitCode: nil, stdout: go.stdout, overflowed: false, timedOut: true)
        ) else {
            Issue.record("a valid line printed before a hang was lost")
            return
        }
    }

    @Test func overflowIsFormatChanged() {
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 0, "", overflowed: true)) == .done(.failed(.formatChanged(.outputTooLarge))))
        #expect(OpenCodeUsageClassifier.classifyUsage(output(exit: 1, "", overflowed: true)) == .done(.failed(.formatChanged(.outputTooLarge))))
    }

    @Test func versionMemoClearsOnDeadlineOrUndecodableOutput() throws {
        #expect(OpenCodeUsageClassifier.clearsVersionMemo(output(exit: nil, "", timedOut: true)))
        #expect(OpenCodeUsageClassifier.clearsVersionMemo(output(exit: 0, "", overflowed: true)))
        #expect(OpenCodeUsageClassifier.clearsVersionMemo(output(exit: 0, "not json")))
        #expect(OpenCodeUsageClassifier.clearsVersionMemo(try OpenCodeFixture.load("standalone-start-failed").output))
        #expect(!OpenCodeUsageClassifier.clearsVersionMemo(try OpenCodeFixture.load("go").output))
        #expect(!OpenCodeUsageClassifier.clearsVersionMemo(try OpenCodeFixture.load("expired").output))
        #expect(!OpenCodeUsageClassifier.clearsVersionMemo(try OpenCodeFixture.load("unknown-operation").output))
    }

    // MARK: Follow-ups

    /// Every `--standalone` command can fail transiently (U12), and signed out is a permanent
    /// "Sign in" state, so only a decoded list may decide it.
    @Test func failedAuthListIsTransientNeverSignedOut() {
        let failures: [OpenCodeRunOutput?] = [
            nil,
            output(exit: 1, "[]"),
            output(exit: 0, "not json"),
            output(exit: 0, #"{"id":"opencode"}"#),
            output(exit: nil, "", timedOut: true),
            output(exit: 0, "", overflowed: true),
        ]
        for run in failures {
            #expect(OpenCodeUsageClassifier.classifyAuthList(run) == .failed(.transient(.authListUnreadable)))
        }
    }

    @Test(arguments: ["standalone-start-failed", "plugins-not-activated"])
    func authListThatHitsATransientClientFailureIsTransient(name: String) throws {
        let captured = try OpenCodeFixture.load(name)
        let run = OpenCodeRunOutput(exitCode: 1, stdout: captured.stdout, overflowed: false, timedOut: false)
        #expect(OpenCodeUsageClassifier.classifyAuthList(run) == .failed(.transient(.authListUnreadable)))
    }

    @Test func authListReadsOnlyTheTwoConsoleIntegrations() {
        let otherProvider = #"[{"id":"anthropic","connections":[{"type":"credential","method":"oauth"}]}]"#
        #expect(OpenCodeUsageClassifier.classifyAuthList(output(exit: 0, otherProvider)) == .failed(.signedOut))
        let external = #"[{"id":"opencode","connections":[{"type":"credential","method":"external"}]}]"#
        #expect(OpenCodeUsageClassifier.classifyAuthList(output(exit: 0, external)) == .noGoPlan)
        let empty = #"[{"id":"opencode","connections":[]},{"id":"opencode-go","connections":[]}]"#
        #expect(OpenCodeUsageClassifier.classifyAuthList(output(exit: 0, empty)) == .failed(.signedOut))
        // A Go key next to a Console OAuth sign-in: the sign-in wins.
        let both = #"[{"id":"opencode-go","connections":[{"type":"credential","method":"key"}]},{"id":"opencode","connections":[{"type":"credential","method":"oauth"}]}]"#
        #expect(OpenCodeUsageClassifier.classifyAuthList(output(exit: 0, both)) == .noGoPlan)
        // OAuth on the Go key integration is not a Console sign-in.
        let goOAuth = #"[{"id":"opencode-go","connections":[{"type":"credential","method":"oauth"}]}]"#
        #expect(OpenCodeUsageClassifier.classifyAuthList(output(exit: 0, goOAuth)) == .failed(.consoleSignInRequired))
    }

    @Test func authListDecodesNoLabels() throws {
        let fixture = try OpenCodeFixture.load("auth-list-key-then-oauth")
        let decoded = try JSONDecoder().decode([OpenCodeAuthIntegrationDTO].self, from: fixture.stdout)
        #expect(Mirror(reflecting: decoded[0]).children.map(\.label) == ["id", "connections"])
        #expect(Mirror(reflecting: decoded[0].connections[0]).children.map(\.label) == ["type", "method"])
        #expect(!String(describing: decoded).contains("Stub Device Workspace"))
        #expect(!String(describing: decoded).contains("cred_"))
    }

    @Test func usageDecodingKeepsNoWorkspace() throws {
        let fixture = try OpenCodeFixture.load("go")
        let decoded = try JSONDecoder().decode(OpenCodeUsageEnvelopeDTO.self, from: fixture.stdout)
        #expect(Mirror(reflecting: try #require(decoded.data)).children.map(\.label) == ["go"])
    }

    @Test func noCaptureCarriesWorkspaceURLOrOutput() throws {
        for name in OpenCodeFixture.manifest.keys {
            let fixture = try OpenCodeFixture.load(name)
            let results: [String] = [
                String(describing: OpenCodeUsageClassifier.classifyUsage(fixture.output)),
                String(describing: OpenCodeUsageClassifier.classifyAuthList(fixture.output)),
                String(describing: OpenCodeUsageClassifier.classifyOperationList(fixture.output)),
            ]
            for text in results {
                for secret in ["wrk_fixture", "Fixture Workspace", "127.0.0.1", "cred_", "Stub Device", "Reconnect", "bunfs"] {
                    #expect(!text.contains(secret), "\(name) leaked \(secret)")
                }
            }
        }
    }

    @Test func failedOperationListIsTransient() {
        let failures: [OpenCodeRunOutput?] = [
            nil,
            output(exit: 1, ""),
            output(exit: 0, "not json"),
            output(exit: nil, "", timedOut: true),
            output(exit: 0, "", overflowed: true),
            output(exit: 0, #"{"openapi":"3.1.0"}"#),
        ]
        for run in failures {
            #expect(OpenCodeUsageClassifier.classifyOperationList(run) == .failed(.transient(.operationListUnreadable)))
        }
    }

    @Test func operationIsFoundByPathOrByOperationID() {
        let byPath = #"{"paths":{"/api/experimental/usage/limits":{}}}"#
        #expect(OpenCodeUsageClassifier.classifyOperationList(output(exit: 0, byPath)) == .failed(.transient(.clientFailed)))
        let movedPath = #"{"paths":{"/api/v2/usage":{"get":{"operationId":"experimental.usage.limits"}}}}"#
        #expect(OpenCodeUsageClassifier.classifyOperationList(output(exit: 0, movedPath)) == .failed(.transient(.clientFailed)))
        let gone = #"{"paths":{"/api/info":{"get":{"operationId":"server.info"}}}}"#
        #expect(OpenCodeUsageClassifier.classifyOperationList(output(exit: 0, gone)) == .failed(.formatChanged(.operationMissing)))
    }

    // MARK: Commands

    @Test func commandsAreTheClosedSet() {
        #expect(OpenCodeCommand.allCases.count == 4)
        #expect(OpenCodeCommand.version.arguments == ["--version"])
        #expect(OpenCodeCommand.usageLimits.arguments == ["api", "--standalone", "experimental.usage.limits"])
        #expect(OpenCodeCommand.authList.arguments == ["auth", "list", "--standalone", "--format", "json"])
        #expect(OpenCodeCommand.operationList.arguments == ["api", "--standalone", "GET", "/openapi.json"])
        for command in OpenCodeCommand.allCases where command != .version {
            #expect(command.arguments.contains("--standalone"))
        }
        for command in OpenCodeCommand.allCases {
            #expect(!command.arguments.contains("service"))
            #expect(!command.arguments.contains("export"))
        }
    }

    @Test func sizeCapsAreExplicitPerRead() throws {
        #expect(OpenCodeCommand.usageLimits.sizeCap == 64 * 1_024)
        #expect(OpenCodeCommand.authList.sizeCap == 64 * 1_024)
        let operations = try OpenCodeFixture.load("operations")
        // The usage cap would reject the OpenAPI document; its own cap fits it with room to grow.
        #expect(operations.stdout.count > OpenCodeCommand.usageLimits.sizeCap)
        #expect(OpenCodeCommand.operationList.sizeCap >= operations.stdout.count * 8)
    }

    @Test func failuresMapToTheU1Outcomes() {
        let cases: [(OpenCodeCaptureFailure, ProviderSetupOutcome)] = [
            (.cliMissing, .opencodeCLIMissing),
            (.updateRequired, .opencodeUpdateRequired),
            (.signedOut, .opencodeSignedOut),
            (.consoleSignInRequired, .opencodeConsoleSignInRequired),
            (.signInExpired, .opencodeSignInExpired),
            (.formatChanged(.clientDecode), .opencodeFormatChanged),
            (.transient(.deadline), .opencodeTransientCapture),
        ]
        for (failure, outcome) in cases {
            #expect(failure.outcome == outcome)
            #expect(failure.failureReason == .providerSetup(outcome))
        }
        #expect(OpenCodeCaptureFailure.signInExpired.failureReason.isPermanent)
        #expect(!OpenCodeCaptureFailure.transient(.unrecognizedError).failureReason.isPermanent)
    }
}

// MARK: - Environment

/// KTD2 step 2: the two fixed `OPENCODE_*` values every child gets, and nothing else.
enum OpenCodeTestExpectations {
    static let fixedNames = ["OPENCODE_DISABLE_AUTOUPDATE", "OPENCODE_DISABLE_MODELS_FETCH"]
    static let fixedLines = ["OPENCODE_DISABLE_AUTOUPDATE=1", "OPENCODE_DISABLE_MODELS_FETCH=1"]
}

struct OpenCodeEnvironmentTests {
    private let inherited = [
        "HOME": "/Users/someone",
        "FOO": "bar",
        "PATH": "/usr/bin",
        "OPENCODE_API_KEY": "sk-secret",
        "OPENCODE_CONFIG": "/elsewhere/opencode.json",
        "OPENCODE_SERVER_PASSWORD": "pw",
        "OPENCODE_DISABLE_MODELS_FETCH": "0",
        "OPENCODE_DISABLE_AUTOUPDATE": "0",
        "XDG_DATA_HOME": "/custom/data",
        "XDG_STATE_HOME": "/custom/state",
    ]

    @Test func builtInAccountClearsEveryOpenCodeAndXDGVariable() {
        let result = OpenCodeCLI.environment(inherited: inherited, home: .builtIn, loginPath: "/login/bin:/usr/bin")
        #expect(result.keys.filter { $0.hasPrefix("OPENCODE_") }.sorted() == OpenCodeTestExpectations.fixedNames)
        #expect(result["OPENCODE_DISABLE_MODELS_FETCH"] == "1")
        // A background poll must never self-update the user's CLI, whatever their shell set.
        #expect(result["OPENCODE_DISABLE_AUTOUPDATE"] == "1")
        #expect(OpenCodeCLI.xdgVariables.allSatisfy { result[$0] == nil })
        #expect(result["PATH"] == "/login/bin:/usr/bin")
        #expect(result["HOME"] == "/Users/someone")
        #expect(result["FOO"] == "bar")
    }

    @Test func extraAccountGetsItsOwnFourXDGFolders() {
        let result = OpenCodeCLI.environment(
            inherited: inherited,
            home: .isolated(root: "/Accounts/opencode/abc"),
            loginPath: "/usr/bin"
        )
        #expect(result["XDG_DATA_HOME"] == "/Accounts/opencode/abc/data")
        #expect(result["XDG_CONFIG_HOME"] == "/Accounts/opencode/abc/config")
        #expect(result["XDG_CACHE_HOME"] == "/Accounts/opencode/abc/cache")
        #expect(result["XDG_STATE_HOME"] == "/Accounts/opencode/abc/state")
        #expect(result["OPENCODE_API_KEY"] == nil)
        #expect(result["OPENCODE_DISABLE_MODELS_FETCH"] == "1")
    }

    @Test func shellLinesApplyTheSameRule() throws {
        let home = OpenCodeAccountHome.isolated(root: "/tmp/it's here")
        let script = (["export OPENCODE_API_KEY=x OPENCODE_CONFIG=y XDG_DATA_HOME=/z XDG_CACHE_HOME=/c"]
            + OpenCodeCLI.shellEnvironmentLines(for: home)
            + ["env"]).joined(separator: "\n")
        let builtIn = (["export OPENCODE_API_KEY=x XDG_DATA_HOME=/z"]
            + OpenCodeCLI.shellEnvironmentLines(for: .builtIn)
            + ["env"]).joined(separator: "\n")

        for (text, expectXDG) in [(script, true), (builtIn, false)] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-f", "-c", text]
            process.environment = ["PATH": "/usr/bin:/bin"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            #expect(lines.filter { $0.hasPrefix("OPENCODE_") }.sorted() == OpenCodeTestExpectations.fixedLines)
            if expectXDG {
                #expect(lines.contains("XDG_DATA_HOME=/tmp/it's here/data"))
                #expect(lines.contains("XDG_STATE_HOME=/tmp/it's here/state"))
                #expect(lines.contains("XDG_CACHE_HOME=/tmp/it's here/cache"))
                #expect(lines.contains("XDG_CONFIG_HOME=/tmp/it's here/config"))
            } else {
                #expect(!lines.contains { $0.hasPrefix("XDG_") })
            }
        }
    }

    @Test func workingDirectoryIsHeadroomOwned() {
        let path = OpenCodeCLI.defaultWorkingDirectory.path
        #expect(path.hasSuffix("/Headroom/OpenCodeProbe"))
        #expect(path.contains("/Library/Application Support/"))
    }
}

// MARK: - Capture cache

/// A source whose captures wait until released, counting each start per home.
private actor GatedOpenCodeSource: OpenCodeUsageSource {
    private(set) var starts: [OpenCodeAccountHome] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let result: OpenCodeCapture

    init(result: OpenCodeCapture = .noGoPlan) {
        self.result = result
    }

    func capture(home: OpenCodeAccountHome) async -> OpenCodeCapture {
        starts.append(home)
        await withCheckedContinuation { waiters.append($0) }
        return result
    }

    func releaseOldest() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    var startCount: Int { starts.count }
    var waiting: Int { waiters.count }
}

private func waitUntil(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

struct OpenCodeUsageCaptureCacheTests {
    @Test func concurrentCapturesForOneHomeShareOneRead() async {
        let source = GatedOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        async let first = cache.capture(home: .builtIn)
        await waitUntil { await source.waiting == 1 }
        async let second = cache.capture(home: .builtIn)
        try? await Task.sleep(for: .milliseconds(50))
        await source.releaseAll()
        let results = await [first, second]
        #expect(results == [.noGoPlan, .noGoPlan])
        #expect(await source.startCount == 1)
    }

    @Test func differentHomesReadSeparately() async {
        let source = GatedOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        async let first = cache.capture(home: .builtIn)
        async let second = cache.capture(home: .isolated(root: "/a"))
        await waitUntil { await source.waiting == 2 }
        await source.releaseAll()
        _ = await [first, second]
        #expect(await source.startCount == 2)
    }

    @Test func noFinishedResultIsKept() async {
        let source = GatedOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        async let first = cache.capture(home: .builtIn)
        await waitUntil { await source.waiting == 1 }
        await source.releaseAll()
        _ = await first
        async let second = cache.capture(home: .builtIn)
        await waitUntil { await source.waiting == 1 }
        await source.releaseAll()
        _ = await second
        #expect(await source.startCount == 2)
    }

    @Test func invalidationDropsTheInFlightEntry() async {
        let source = GatedOpenCodeSource()
        let cache = OpenCodeUsageCaptureCache(source: source)
        let home = OpenCodeAccountHome.isolated(root: "/removed")
        async let stale = cache.capture(home: home)
        await waitUntil { await source.waiting == 1 }
        cache.invalidate(home: home)
        async let fresh = cache.capture(home: home)
        await waitUntil { await source.waiting == 2 }
        #expect(await source.startCount == 2)

        // The older read finishing must not drop the newer entry: a third caller joins it.
        await source.releaseOldest()
        _ = await stale
        async let joined = cache.capture(home: home)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await source.startCount == 2)
        await source.releaseAll()
        _ = await [fresh, joined]
    }
}

// MARK: - Process

/// One generic fake `opencode`, written once for the whole suite and always run as
/// `/bin/sh <script>` (KTD17, BUGS.md "text file busy"). Each test gives it its own directory
/// through `FAKE_OPENCODE_DIR`; per command the script logs its argv, environment and working
/// folder, runs an optional `<command>.pre` hook, prints `<command>.stdout`, runs an optional
/// `<command>.post` hook and exits with `<command>.exit`.
private enum FakeOpenCodeScript {
    static let body = """
    dir="$FAKE_OPENCODE_DIR"
    printf '%s\\n' "$*" >> "$dir/argv.log"
    case "$*" in
      "--version") name=version ;;
      "api --standalone experimental.usage.limits") name=usage ;;
      "auth list --standalone --format json") name=auth ;;
      "api --standalone GET /openapi.json") name=operations ;;
      *) name=unknown ;;
    esac
    env > "$dir/$name.env"
    pwd -P > "$dir/$name.pwd"
    echo $$ >> "$dir/$name.pids"
    if [ -f "$dir/$name.pre" ]; then . "$dir/$name.pre"; fi
    if [ -f "$dir/$name.stdout" ]; then cat "$dir/$name.stdout"; fi
    if [ -f "$dir/$name.post" ]; then . "$dir/$name.post"; fi
    if [ -f "$dir/$name.exit" ]; then exit "$(cat "$dir/$name.exit")"; fi
    exit 0
    """

    static let shared: String = write(to: FileManager.default.temporaryDirectory
        .appendingPathComponent("headroom-opencode-fake-\(UUID().uuidString)", isDirectory: true))

    static func write(to directory: URL) -> String {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("opencode")
        try? Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private struct FakeOpenCode {
    let directory: URL
    let workingDirectory: URL
    var script: String

    init(privateScript: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-opencode-test-\(UUID().uuidString)", isDirectory: true)
        workingDirectory = directory.appendingPathComponent("OpenCodeProbe", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        script = privateScript
            ? FakeOpenCodeScript.write(to: directory.appendingPathComponent("bin", isDirectory: true))
            : FakeOpenCodeScript.shared
        try set("version", stdout: "opencode v2.2.5\n", exit: 0)
    }

    func set(_ command: String, stdout: String, exit: Int32) throws {
        try Data(stdout.utf8).write(to: directory.appendingPathComponent("\(command).stdout"))
        try Data("\(exit)\n".utf8).write(to: directory.appendingPathComponent("\(command).exit"))
    }

    func set(_ command: String, fixture name: String) throws {
        let fixture = try OpenCodeFixture.load(name)
        try fixture.stdout.write(to: directory.appendingPathComponent("\(command).stdout"))
        try Data("\(fixture.exit)\n".utf8).write(to: directory.appendingPathComponent("\(command).exit"))
    }

    func hook(_ command: String, pre: String? = nil, post: String? = nil) throws {
        if let pre { try Data(pre.utf8).write(to: directory.appendingPathComponent("\(command).pre")) }
        if let post { try Data(post.utf8).write(to: directory.appendingPathComponent("\(command).post")) }
    }

    func source(
        inherited: [String: String] = [:],
        deadline: TimeInterval = 10,
        resolveCount: Counter? = nil,
        executable: String? = nil,
        usePath: Bool = true
    ) -> OpenCodeCLIUsageSource {
        let script = executable ?? script
        let dir = directory.path
        return OpenCodeCLIUsageSource(
            resolveExecutable: { resolveCount?.increment(); return usePath ? script : nil },
            resolveLoginPath: { "/usr/bin:/bin" },
            inheritedEnvironment: { inherited.merging(["FAKE_OPENCODE_DIR": dir]) { $1 } },
            workingDirectory: workingDirectory.path,
            deadline: deadline,
            versionDeadline: 5,
            interpreter: "/bin/sh"
        )
    }

    var argv: [String] {
        (try? String(contentsOf: directory.appendingPathComponent("argv.log"), encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
    }

    func count(_ arguments: [String]) -> Int { argv.filter { $0 == arguments.joined(separator: " ") }.count }

    func environment(_ command: String) -> [String: String] {
        let text = (try? String(contentsOf: directory.appendingPathComponent("\(command).env"), encoding: .utf8)) ?? ""
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { result[String(parts[0])] = String(parts[1]) }
        }
        return result
    }

    func pids(_ command: String) -> [pid_t] {
        ((try? String(contentsOf: directory.appendingPathComponent("\(command).pids"), encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { pid_t($0) }
    }

    func text(_ file: String) -> String {
        ((try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func isRunning(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

private func userRequested(_ source: OpenCodeCLIUsageSource, home: OpenCodeAccountHome = .builtIn) async -> OpenCodeCapture {
    await UserRequestedProbeContext.$isUserRequested.withValue(true) { await source.capture(home: home) }
}

struct OpenCodeUsageSourceProcessTests {
    @Test func liveFixtureReturnsThreeWindows() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "go")
        guard case .goUsage(let usage) = await fake.source().capture(home: .builtIn) else {
            Issue.record("expected live usage")
            return
        }
        #expect(usage.weekly.percentUsed == 47)
        #expect(fake.argv == ["--version", "api --standalone experimental.usage.limits"])
    }

    @Test func belowFloorVersionsNeverRunTheUsageRead() async throws {
        for version in ["opencode v2.1.4\n", "1.1.53\n"] {
            let fake = try FakeOpenCode()
            defer { fake.remove() }
            try fake.set("version", stdout: version, exit: 0)
            try fake.set("usage", fixture: "go")
            let source = fake.source()
            #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
            #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
            // `api` never ran, and the too-old verdict was not spawned again (below).
            #expect(fake.argv == ["--version"])
        }
    }

    /// A 1.x `--version` appends to the user's real log and can reset their cache, so an
    /// unchanged too-old binary is not asked again on every poll.
    @Test func tooOldVerdictIsNotRespawnedForAnUnchangedBinary() async throws {
        let fake = try FakeOpenCode(privateScript: true)
        defer { fake.remove() }
        try fake.set("version", stdout: "1.1.53\n", exit: 0)
        let source = fake.source()
        for _ in 0..<3 {
            #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
        }
        #expect(await source.capture(home: .isolated(root: fake.directory.path)) == .failed(.updateRequired))
        #expect(fake.count(OpenCodeCommand.version.arguments) == 1)
    }

    @Test func tooOldVerdictIsCheckedAgainOnAUserRequest() async throws {
        let fake = try FakeOpenCode(privateScript: true)
        defer { fake.remove() }
        try fake.set("version", stdout: "1.1.53\n", exit: 0)
        let source = fake.source()
        #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
        #expect(await userRequested(source) == .failed(.updateRequired))
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)
        // A version-manager shim swapped behind an unchanged file is seen on Check Now.
        try fake.set("version", stdout: "opencode v2.2.5\n", exit: 0)
        try fake.set("usage", fixture: "nogo")
        #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
        #expect(await userRequested(source) == .noGoPlan)
    }

    @Test func tooOldVerdictIsCheckedAgainWhenTheBinaryChanges() async throws {
        let fake = try FakeOpenCode(privateScript: true)
        defer { fake.remove() }
        try fake.set("version", stdout: "opencode v2.1.4\n", exit: 0)
        let source = fake.source()
        #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: fake.script
        )
        #expect(await source.capture(home: .builtIn) == .failed(.updateRequired))
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)

        // Upgraded in place: a new modification date and a 2.x version pass.
        try fake.set("version", stdout: "opencode v2.2.5\n", exit: 0)
        try fake.set("usage", fixture: "nogo")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: fake.script
        )
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.version.arguments) == 3)
    }

    @Test func unreadableVersionIsTransientAndNotMemoized() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("version", stdout: "", exit: 1)
        let source = fake.source()
        #expect(await source.capture(home: .builtIn) == .failed(.transient(.unreadableVersion)))
        try fake.set("version", stdout: "opencode v2.2.5\n", exit: 0)
        try fake.set("usage", fixture: "nogo")
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)
    }

    @Test func versionMemoIsReusedUntilTheExecutableChanges() async throws {
        let fake = try FakeOpenCode(privateScript: true)
        defer { fake.remove() }
        try fake.set("usage", fixture: "nogo")
        let source = fake.source()
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(await source.capture(home: .isolated(root: fake.directory.path)) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.version.arguments) == 1)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: fake.script
        )
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)
        #expect(fake.count(OpenCodeCommand.usageLimits.arguments) == 3)
    }

    @Test func versionMemoFollowsSymlinksToTheTarget() async throws {
        let fake = try FakeOpenCode(privateScript: true)
        defer { fake.remove() }
        try fake.set("usage", fixture: "nogo")
        let link = fake.directory.appendingPathComponent("link-opencode").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: fake.script)
        let source = fake.source(executable: link)
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: fake.script
        )
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)
    }

    @Test func deadlineClearsAPassingMemo() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "nogo")
        // A 1-second deadline made the ordinary runs time out on a loaded machine.
        let source = fake.source(deadline: 4)
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        try fake.hook("usage", pre: "sleep 30\n")
        #expect(await source.capture(home: .builtIn) == .failed(.transient(.deadline)))
        try FileManager.default.removeItem(at: fake.directory.appendingPathComponent("usage.pre"))
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)
    }

    @Test func undecodableOutputClearsAPassingMemo() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "standalone-start-failed")
        let source = fake.source()
        #expect(await source.capture(home: .builtIn) == .failed(.transient(.serverStartFailed)))
        #expect(await source.capture(home: .builtIn) == .failed(.transient(.serverStartFailed)))
        #expect(fake.count(OpenCodeCommand.version.arguments) == 2)
    }

    @Test func childEnvironmentFollowsKTD2AndKTD10() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "signed-out")
        try fake.set("auth", fixture: "auth-list-signed-out")
        let inherited = [
            "FOO": "bar",
            "OPENCODE_API_KEY": "sk-secret",
            "OPENCODE_CONFIG_DIR": "/elsewhere",
            "OPENCODE_DISABLE_MODELS_FETCH": "0",
            "XDG_DATA_HOME": "/custom/data",
            "XDG_CONFIG_HOME": "/custom/config",
        ]
        let source = fake.source(inherited: inherited)

        #expect(await source.capture(home: .builtIn) == .failed(.signedOut))
        for command in ["version", "usage", "auth"] {
            let env = fake.environment(command)
            #expect(env.keys.filter { $0.hasPrefix("OPENCODE_") }.sorted() == OpenCodeTestExpectations.fixedNames, "\(command)")
            #expect(env["OPENCODE_DISABLE_MODELS_FETCH"] == "1")
            #expect(env["OPENCODE_DISABLE_AUTOUPDATE"] == "1")
            #expect(!env.keys.contains { $0.hasPrefix("XDG_") }, "\(command)")
            #expect(env["PATH"] == "/usr/bin:/bin")
            #expect(env["FOO"] == "bar")
        }

        let root = fake.directory.appendingPathComponent("account").path
        #expect(await source.capture(home: .isolated(root: root)) == .failed(.signedOut))
        for command in ["usage", "auth"] {
            let env = fake.environment(command)
            #expect(env["XDG_DATA_HOME"] == root + "/data")
            #expect(env["XDG_CONFIG_HOME"] == root + "/config")
            #expect(env["XDG_CACHE_HOME"] == root + "/cache")
            #expect(env["XDG_STATE_HOME"] == root + "/state")
            #expect(env.keys.filter { $0.hasPrefix("OPENCODE_") }.sorted() == OpenCodeTestExpectations.fixedNames)
        }
    }

    @Test func workingFolderIsTheProbeFolderNotTheAppDirectory() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "nogo")
        #expect(!FileManager.default.fileExists(atPath: fake.workingDirectory.path))
        _ = await fake.source().capture(home: .builtIn)
        // realpath(3), because Foundation's symlink resolution drops `/private` and `pwd -P` keeps it.
        func physical(_ path: String) -> String? {
            guard let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let expected = try #require(physical(fake.workingDirectory.path))
        #expect(fake.text("usage.pwd") == expected)
        #expect(fake.text("version.pwd") == expected)
        #expect(fake.text("usage.pwd") != physical(FileManager.default.currentDirectoryPath))
    }

    @Test func clientThatNeverExitsIsKilledAtTheDeadlineWithItsGroup() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        // The child would outlive the test by minutes on its own, so returning well before it
        // could exit proves the deadline ended the run. The bound is 10× the 3 s deadline: a
        // tight one (< 5 s on a 1 s deadline) failed once under a loaded parallel run without
        // any bug, and 3 s gives a slow-starting shell time to record its pids before the kill.
        try fake.hook("usage", pre: "sleep 120 &\necho $! > \"$dir/child.pid\"\nwait\n")
        let started = Date()
        let result = await fake.source(deadline: 3).capture(home: .builtIn)
        #expect(result == .failed(.transient(.deadline)))
        #expect(Date().timeIntervalSince(started) < 30)
        let leader = try #require(fake.pids("usage").first)
        let child = try #require(pid_t(fake.text("child.pid")))
        #expect(!isRunning(leader))
        #expect(!isRunning(child))
    }

    @Test func validLineThenHangStillReturnsTheCapture() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "go")
        try fake.hook("usage", post: "sleep 30\n")
        guard case .goUsage = await fake.source(deadline: 1).capture(home: .builtIn) else {
            Issue.record("the printed reading was lost")
            return
        }
        #expect(!isRunning(try #require(fake.pids("usage").first)))
    }

    @Test func slowRefreshInsideTheDeadlineStillReturnsItsCapture() async throws {
        // Scaled stand-in for a refreshok run slower than 30 s inside the 50 s deadline: the
        // run is never ended early (KTD5).
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "refreshok")
        try fake.hook("usage", pre: "sleep 1.2\n")
        guard case .goUsage = await fake.source(deadline: 3).capture(home: .builtIn) else {
            Issue.record("a slow run inside the deadline was lost")
            return
        }
    }

    /// The client gets `/dev/null` as stdin, as the QA script runs it, so a client that ever
    /// reads stdin sees end of file at once instead of waiting out the 50-second deadline.
    @Test func aClientThatReadsStdinSeesEndOfFileAndExitsPromptly() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "go")
        try fake.hook("version", pre: "cat > /dev/null\n")
        try fake.hook("usage", pre: "cat > /dev/null\n")
        let started = Date()
        // A client blocked on stdin would never print its reading, so the reading is the proof.
        // The bound only has to sit under the deadline; a tight one flaked on a loaded machine.
        guard case .goUsage = await fake.source(deadline: 60).capture(home: .builtIn) else {
            Issue.record("a client reading stdin did not finish with its reading")
            return
        }
        #expect(Date().timeIntervalSince(started) < 45)
    }

    @Test func refreshBadIsSignInExpired() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "refreshbad")
        #expect(await fake.source().capture(home: .builtIn) == .failed(.signInExpired))
    }

    @Test func outputAboveTheCapIsFormatChanged() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", stdout: String(repeating: "x", count: 70 * 1_024), exit: 0)
        #expect(await fake.source().capture(home: .builtIn) == .failed(.formatChanged(.outputTooLarge)))
    }

    @Test func operationListBelowItsOwnCapIsRead() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "unknown-operation")
        try fake.set("operations", fixture: "operations")
        #expect(await fake.source().capture(home: .builtIn) == .failed(.transient(.clientFailed)))
        #expect(fake.argv == ["--version", "api --standalone experimental.usage.limits", "api --standalone GET /openapi.json"])
    }

    @Test func operationGoneIsFormatChanged() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "unknown-operation")
        try fake.set("operations", fixture: "operations-missing")
        #expect(await fake.source().capture(home: .builtIn) == .failed(.formatChanged(.operationMissing)))
    }

    @Test func failedOperationListIsTransient() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "unknown-operation")
        try fake.set("operations", stdout: "", exit: 1)
        #expect(await fake.source().capture(home: .builtIn) == .failed(.transient(.operationListUnreadable)))
    }

    @Test(arguments: [
        ("auth-list-go-key", OpenCodeCapture.failed(.consoleSignInRequired)),
        ("auth-list-api-key", .failed(.consoleSignInRequired)),
        ("auth-list-oauth", .noGoPlan),
        ("auth-list-no-workspace", .noGoPlan),
        ("auth-list-key-then-oauth", .noGoPlan),
        ("auth-list-signed-out", .failed(.signedOut)),
    ])
    func nullReadingIsToldApartByTheAuthList(fixture: String, expected: OpenCodeCapture) async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "signed-out")
        try fake.set("auth", fixture: fixture)
        #expect(await fake.source().capture(home: .builtIn) == expected)
        #expect(fake.argv == ["--version", "api --standalone experimental.usage.limits", "auth list --standalone --format json"])
    }

    @Test func failedAuthListIsTransient() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "api-key")
        try fake.set("auth", stdout: "", exit: 1)
        #expect(await fake.source().capture(home: .builtIn) == .failed(.transient(.authListUnreadable)))
        try fake.set("auth", fixture: "standalone-start-failed")
        #expect(await fake.source().capture(home: .builtIn) == .failed(.transient(.authListUnreadable)))
    }

    @Test func terminalSignInBetweenTwoNullReadingsShowsAtTheNextPoll() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "signed-out")
        try fake.set("auth", fixture: "auth-list-signed-out")
        let source = fake.source()
        #expect(await source.capture(home: .builtIn) == .failed(.signedOut))
        try fake.set("auth", fixture: "auth-list-oauth")
        #expect(await source.capture(home: .builtIn) == .noGoPlan)
        #expect(fake.count(OpenCodeCommand.authList.arguments) == 2)
    }

    @Test func spawnArgumentsAreOnlyTheClosedSet() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        let source = fake.source()
        try fake.set("usage", fixture: "signed-out")
        try fake.set("auth", fixture: "auth-list-api-key")
        _ = await source.capture(home: .builtIn)
        try fake.set("usage", fixture: "unknown-operation")
        try fake.set("operations", fixture: "operations")
        _ = await source.capture(home: .isolated(root: "/x"))
        try fake.set("usage", fixture: "go")
        _ = await source.capture(home: .builtIn)

        let allowed = Set(OpenCodeCommand.allCases.map { $0.arguments.joined(separator: " ") })
        #expect(!fake.argv.isEmpty)
        #expect(fake.argv.allSatisfy { allowed.contains($0) })
        #expect(Set(fake.argv) == allowed)
    }

    @Test func missingExecutableIsCLIMissing() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        #expect(await fake.source(usePath: false).capture(home: .builtIn) == .failed(.cliMissing))
        let notExecutable = fake.directory.appendingPathComponent("usage.exit").path
        #expect(await fake.source(executable: notExecutable).capture(home: .builtIn) == .failed(.cliMissing))
        #expect(fake.argv.isEmpty)
    }

    @Test func routinePollsReuseTheResolvedPathAndUserRequestsSearchAgain() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "nogo")
        let counter = Counter()
        let source = fake.source(resolveCount: counter)
        _ = await source.capture(home: .builtIn)
        _ = await source.capture(home: .builtIn)
        #expect(counter.count == 1)
        _ = await userRequested(source)
        #expect(counter.count == 2)
    }

    @Test func concurrentCapturesForOneHomeSpawnOneClient() async throws {
        let fake = try FakeOpenCode()
        defer { fake.remove() }
        try fake.set("usage", fixture: "nogo")
        try fake.hook("usage", pre: "sleep 0.5\n")
        let cache = OpenCodeUsageCaptureCache(source: fake.source())
        async let first = cache.capture(home: .builtIn)
        async let second = cache.capture(home: .builtIn)
        #expect(await [first, second] == [.noGoPlan, .noGoPlan])
        #expect(fake.count(OpenCodeCommand.usageLimits.arguments) == 1)

        async let third = cache.capture(home: .builtIn)
        async let fourth = cache.capture(home: .isolated(root: "/other"))
        _ = await [third, fourth]
        #expect(fake.count(OpenCodeCommand.usageLimits.arguments) == 3)
    }
}
