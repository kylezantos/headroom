import Foundation
import Testing
@testable import HeadroomCore

private struct StubCursorSource: CursorUsageSource {
    let result: CursorPanelResult
    func capturePanel() async -> CursorPanelResult { result }
}

@Suite struct CursorProviderTests {
    private func fixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "cursor-usage", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var augustFirst2026: Date {
        ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z")!
    }

    @Test func liveOfficialPanelFixtureDecodesMonthlyIncludedUsage() async throws {
        let text = try fixture()
        let provider = CursorProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.providerID == .cursor)
        #expect(snapshot.planLabel == "Pro+")
        #expect(snapshot.windows.count == 1)
        // Fixture is a real non-zero live capture (Included 1% used); pins that the parser
        // reads the rendered percentage, not a hardcoded zero.
        #expect(snapshot.windows.first?.utilization == 1)
        #expect(snapshot.windows.first?.percentRemaining == 99)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60))
        #expect(snapshot.windows.first?.resetSchedule == .scheduled(
            ISO8601DateFormatter().date(from: "2026-09-01T23:59:59Z")!
        ))
        #expect(snapshot.windows.first?.resetLabel == "Resets Sep 1")
    }

    @Test func includedPercentReadsAnArbitraryMidRangeValue() throws {
        let text = try fixture().replacingOccurrences(
            of: "Included        1% used",
            with: "Included        73% used"
        )
        let parsed = try #require(CursorUsageParser.parse(text, now: augustFirst2026))
        #expect(parsed.includedPercentUsed == 73)
    }

    @Test func displayedResetDayDoesNotExpireAtMidnight() throws {
        let middayOnReset = try #require(ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z"))
        let parsed = try #require(CursorUsageParser.parse(try fixture(), now: middayOnReset))

        #expect(parsed.resetsAt == ISO8601DateFormatter().date(from: "2026-09-01T23:59:59Z"))
        #expect(parsed.resetLabel == "Resets Sep 1")
    }

    @Test func fixedOnDemandSpendDecodesWithoutChangingIncludedUsage() async throws {
        let text = try fixture().replacingOccurrences(
            of: "On-Demand       Disabled",
            with: "On-Demand       $12.50 / $100.00"
        )
        let parsed = try #require(CursorUsageParser.parse(text, now: augustFirst2026))
        #expect(parsed.includedPercentUsed == 1)
        #expect(parsed.onDemand == .fixed(usedDollars: 12.5, limitDollars: 100))

        let spend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)
        #expect(spend.freshness == .live)
        #expect(spend.amount == 12.5)
        #expect(spend.currency == "usd")
        #expect(spend.periodLabel == "Resets Sep 1")
    }

    @Test func disabledOnDemandProducesAnExplicitNonApplicableSnapshot() async throws {
        let spend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(try fixture())),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)
        #expect(spend.freshness == .live)
        #expect(spend.amount == nil)
        #expect(spend.currency == nil)
    }

    @Test func cliFailuresMapToTypedRedactedOutcomes() async {
        let cases: [(CursorPanelResult, ProviderSetupOutcome)] = [
            (.cliNotFound, .cursorCLIMissing),
            (.loginRequired, .cursorAuthAbsent),
            (.unknownUI, .cursorUnknownUI),
            (.transientCapture, .cursorTransientCapture),
        ]
        for (result, expected) in cases {
            let snapshot = await CursorProvider(source: StubCursorSource(result: result)).fetchSnapshot()
            guard case .stale(let reason) = snapshot.freshness else {
                Issue.record("expected stale Cursor snapshot")
                continue
            }
            #expect(reason == .providerSetup(expected))
        }
    }

    @Test func malformedPanelFailsSafe() async {
        let snapshot = await CursorProvider(
            source: StubCursorSource(result: .panel("Usage unavailable"))
        ).fetchSnapshot()
        #expect(snapshot.freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func authStatusReadsOnlyTheOfficialBoolean() {
        #expect(CursorUsageCLIProbe.classifyAuthStatus(Data(#"{"isAuthenticated":true,"userEmail":"ignored@example.com"}"#.utf8)) == .loggedIn)
        #expect(CursorUsageCLIProbe.classifyAuthStatus(Data(#"{"isAuthenticated":false}"#.utf8)) == .loggedOut)
        #expect(CursorUsageCLIProbe.classifyAuthStatus(Data(#"{"status":"authenticated"}"#.utf8)) == .unsupported)
    }

    @Test func tuiInputRequiresThePromptAndSelectedUsageCommand() {
        #expect(CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nAsk (shift+tab to cycle)\nAuto"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nA new onboarding screen"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Ask (shift+tab to cycle)"))

        #expect(CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /usage\n/context"))
        // The live TUI pads the arrow-to-command gap with several spaces and trails the
        // row with a description; both must still classify as the selected /usage row.
        #expect(CursorUsageCLIProbe.isUsageAutocompleteSelected("→  /usage    Show plan and on-demand usage"))
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("/usage\n/context"))
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /context\n/usage"))
        // Token boundary: a differently-named command must never satisfy the gate.
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /usages\n/context"))
    }

    @Test func cursorIsExplicitlySingleAccount() {
        #expect(CursorProvider(source: StubCursorSource(result: .transientCapture)).accountCapacity == 1)
    }

    @Test func executableDisappearingBeforeProbeFailsClosedWithoutPTYInput() async {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-removed-cursor-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o700]
        ))
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        try? FileManager.default.removeItem(at: executable)

        #expect(await CursorUsageCLIProbe(cursorPath: executable.path).capturePanel() == .cliNotFound)
    }
}

@Suite struct CursorConnectionTests {
    @Test func generatedLoginScriptUsesOnlyOfficialCommandAndParsesAsZsh() throws {
        let script = CursorCLI.loginScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("'/Users/test/.local/bin/cursor-agent' login"))
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(!script.localizedCaseInsensitiveContains("token"))

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
}
