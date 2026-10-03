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

    private var namedPoolKinds: [WindowKind] {
        let month: TimeInterval = 30 * 24 * 60 * 60
        return [
            .billingPeriod(label: "Cursor Models", duration: month),
            .billingPeriod(label: "Other Models", duration: month),
        ]
    }

    @Test func liveOfficialPanelFixtureDecodesBothNamedPools() async throws {
        let text = try fixture()
        let provider = CursorProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.providerID == .cursor)
        #expect(snapshot.planLabel == "Pro+")
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows.map(\.utilization) == [1, 3])
        #expect(snapshot.windows.map(\.percentRemaining) == [99, 97])
        #expect(snapshot.windows.map(\.kind) == namedPoolKinds)
        #expect(snapshot.windows.allSatisfy { $0.resetSchedule == .scheduled(
            ISO8601DateFormatter().date(from: "2026-09-01T23:59:59Z")!
        ) })
        #expect(snapshot.windows.allSatisfy { $0.resetLabel == "Resets Sep 1" })
    }

    @Test func includedPercentReadsAnArbitraryMidRangeValue() throws {
        let text = try fixture().replacingOccurrences(
            of: "Included        1% used",
            with: "Included        73% used"
        )
        let parsed = try #require(CursorUsageParser.parse(text, now: augustFirst2026))
        #expect(parsed.includedPercentUsed == 73)
    }

    @Test func namedPoolsUseTheirOwnArbitraryValuesInsteadOfIncluded() async throws {
        let text = try fixture()
            .replacingOccurrences(of: "Included        1% used", with: "Included        9% used")
            .replacingOccurrences(of: "Auto          1% used", with: "Auto          37% used")
            .replacingOccurrences(of: "API           3% used", with: "API           62% used")
        let snapshot = await snapshot(for: text)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.map(\.utilization) == [37, 62])
        #expect(snapshot.windows.map(\.kind) == namedPoolKinds)
    }

    @Test func lastCoherentCompletedRepaintWins() async throws {
        let first = try fixture()
            .replacingOccurrences(of: "Auto          1% used", with: "Auto          12% used")
            .replacingOccurrences(of: "API           3% used", with: "API           24% used")
        let second = try fixture()
            .replacingOccurrences(of: "Auto          1% used", with: "Auto          31% used")
            .replacingOccurrences(of: "API           3% used", with: "API           63% used")
        let trailingIncomplete = """
        Usage • Pro+ Resets Sep 1
        Included 1% used
        Auto 99% used
        """
        let snapshot = await snapshot(for: first + "\n" + second + "\n" + trailingIncomplete)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.map(\.utilization) == [31, 63])
    }

    @Test func namedPercentagesClampToTheSupportedRange() async throws {
        let text = try fixture()
            .replacingOccurrences(of: "Auto          1% used", with: "Auto          120% used")
            .replacingOccurrences(of: "API           3% used", with: "API           101% used")

        #expect(await snapshot(for: text).windows.map(\.utilization) == [100, 100])
    }

    @Test func rowsFromDifferentIncompleteRepaintsNeverFormASyntheticPair() async {
        let text = """
        Usage • Pro+ Resets Sep 1
        Included 1% used
        Auto 11% used
        Usage • Pro+ Resets Sep 1
        Included 1% used
        API 22% used
        """

        #expect(await snapshot(for: text).freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func completedIncludedOnlyPanelUsesCompatibilityFallback() async {
        let snapshot = await snapshot(for: """
        Usage • Pro Resets Sep 1
        Monthly plan and on-demand usage
        Category Current Usage
        Included 42% used
        On-Demand Disabled
        """)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Included", duration: 30 * 24 * 60 * 60))
        #expect(snapshot.windows.first?.utilization == 42)
    }

    @Test func truncatedIncludedOnlyPanelFailsStale() async {
        let snapshot = await snapshot(for: """
        Usage • Pro Resets Sep 1
        Monthly plan and on-demand usage
        Included 42% used
        """)

        #expect(snapshot.freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func completedOneNamedPoolPanelPublishesThatPool() async {
        let snapshot = await snapshot(for: """
        Usage • Start Resets Sep 1
        Monthly plan and on-demand usage
        Included 17% used
        Auto 29% used
        On-Demand Disabled
        """)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Cursor Models", duration: 30 * 24 * 60 * 60))
        #expect(snapshot.windows.first?.utilization == 29)
    }

    @Test func completedNamedPoolsDoNotRequireIncluded() async {
        let snapshot = await snapshot(for: """
        Usage • Pro+ Resets Sep 1
        Monthly plan and on-demand usage
        Auto 12% used
        API 47% used
        On-Demand Disabled
        """)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.map(\.kind) == namedPoolKinds)
        #expect(snapshot.windows.map(\.utilization) == [12, 47])
    }

    @Test func completedAPIOnlyPanelPublishesOtherModels() async {
        let snapshot = await snapshot(for: """
        Usage • Start Resets Sep 1
        Monthly plan and on-demand usage
        Included 17% used
        API 41% used
        On-Demand Disabled
        """)

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Other Models", duration: 30 * 24 * 60 * 60))
        #expect(snapshot.windows.first?.utilization == 41)
    }

    @Test func truncatedOneNamedPoolPanelFailsStale() async {
        let snapshot = await snapshot(for: """
        Usage • Start Resets Sep 1
        Monthly plan and on-demand usage
        Included 17% used
        Auto 29% used
        """)

        #expect(snapshot.freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func unknownOrRenamedSiblingRowFailsStaleInsteadOfFallingBack() async {
        let snapshot = await snapshot(for: """
        Usage • Pro+ Resets Sep 1
        Monthly plan and on-demand usage
        Included 1% used
        Premium Models 7% used
        On-Demand Disabled
        """)

        #expect(snapshot.freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func malformedNamedPercentageFailsStale() async throws {
        let text = try fixture().replacingOccurrences(of: "API           3% used", with: "API           --% used")
        #expect(await snapshot(for: text).freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func displayedResetDayDoesNotExpireAtMidnight() throws {
        let middayOnReset = try #require(ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z"))
        let parsed = try #require(CursorUsageParser.parse(try fixture(), now: middayOnReset))

        #expect(parsed.resetsAt == ISO8601DateFormatter().date(from: "2026-09-01T23:59:59Z"))
        #expect(parsed.resetLabel == "Resets Sep 1")
    }

    @Test func resetDayRollsIntoTheNextYearAfterItHasPassed() throws {
        let december = try #require(ISO8601DateFormatter().date(from: "2026-12-15T12:00:00Z"))
        let parsed = try #require(CursorUsageParser.parse(try fixture(), now: december))

        #expect(parsed.resetsAt == ISO8601DateFormatter().date(from: "2027-09-01T23:59:59Z"))
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

    @Test func onDemandRemainsLiveWhenSubscriptionRowsAreUnknown() async {
        let text = """
        Usage • Pro+ Resets Sep 1
        Monthly plan and on-demand usage
        Included 1% used
        Renamed Pool 8% used
        On-Demand $12.50 / $100.00
        """
        let subscription = await snapshot(for: text)
        let spend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)

        #expect(subscription.freshness == .stale(.providerSetup(.cursorTransientCapture)))
        #expect(spend.freshness == .live)
        #expect(spend.amount == 12.5)
        #expect(spend.currency == "usd")
    }

    @Test func unlimitedAndUnavailableOnDemandVariantsKeepTheirExistingMeaning() async throws {
        let unlimited = try fixture().replacingOccurrences(
            of: "On-Demand       Disabled",
            with: "On-Demand       $12.50"
        )
        let unavailable = try fixture().replacingOccurrences(
            of: "On-Demand       Disabled",
            with: "On-Demand       Unavailable"
        )

        let unlimitedSpend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(unlimited)),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)
        let unavailableSpend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(unavailable)),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)

        #expect(unlimitedSpend.freshness == .live)
        #expect(unlimitedSpend.amount == 12.5)
        #expect(unlimitedSpend.currency == "usd")
        #expect(unavailableSpend.freshness == .live)
        #expect(unavailableSpend.amount == nil)
        #expect(unavailableSpend.currency == nil)
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
            (.workspaceTrustRequired, .cursorTrustRequired),
            (.mcpApprovalRequired, .cursorMCPApprovalRequired),
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
        #expect(CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nv2026.09.15-d2fe57e\nPlan, search, build anything\nAuto Balance"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nA new onboarding screen"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Ask (shift+tab to cycle)"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nWorkspace Trust Required\n[a] Trust this workspace"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nMCP Server Approval Required\nPlan, search, build anything"))
        #expect(CursorUsageCLIProbe.isMCPApprovalPrompt("MCP Server Approval Required\nReview servers"))
        #expect(CursorUsageCLIProbe.isWorkspaceTrustPrompt("/!\\ Workspace Trust Required\n[a] Trust this workspace\n[q] Quit"))
        #expect(CursorUsageCLIProbe.isLoginPrompt("Cursor Agent\nv2026.09.28-64d2043\nPress any key to log in..."))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nPress any key to log in...\nAsk (shift+tab to cycle)"))
        #expect(CursorUsageCLIProbe.containsBackgroundColorQuery(Data("\u{1B}[2J\u{1B}]11;?\u{07}".utf8)))
        #expect(!CursorUsageCLIProbe.containsBackgroundColorQuery(Data("\u{1B}[2J\u{1B}[H".utf8)))

        #expect(CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /usage\n/context"))
        // The live TUI pads the arrow-to-command gap with several spaces and trails the
        // row with a description; both must still classify as the selected /usage row.
        #expect(CursorUsageCLIProbe.isUsageAutocompleteSelected("→  /usage    Show plan and on-demand usage"))
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("/usage\n/context"))
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /context\n/usage"))
        // Token boundary: a differently-named command must never satisfy the gate.
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /usages\n/context"))

        #expect(CursorUsageCLIProbe.isUsagePanel("Monthly plan and on-demand usage\nIncluded 1% used"))
        #expect(CursorUsageCLIProbe.isUsagePanel("Monthly plan and on-demand usage\n  Auto 1% used"))
        #expect(CursorUsageCLIProbe.isUsagePanel("Monthly plan and on-demand usage\nAPI 3% used"))
        #expect(!CursorUsageCLIProbe.isUsagePanel("Monthly plan and on-demand usage\nLoading…"))
        #expect(!CursorUsageCLIProbe.isUsagePanel("Included 1% used"))
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

    @Test func freshWorkspaceTrustNeverReceivesPTYInput() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-trust")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        #expect(await probe.capturePanel() == .workspaceTrustRequired)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    @Test func mcpApprovalNeverReceivesPTYInput() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-mcp")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        #expect(await probe.capturePanel() == .mcpApprovalRequired)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    /// The signed-out screen starts a browser login on any byte, including an
    /// unsolicited OSC 11 reply, so it must be classified before anything is written.
    @Test func signedOutScreenNeverReceivesPTYInput() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-login")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        #expect(await probe.capturePanel() == .loginRequired)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    /// R2: the gate can paint after the ready frame. The old sleep-then-type path would
    /// have sent `/usage`, whose `a` is the trust menu's approve key.
    @Test(arguments: ["cursor-agent-late-trust", "cursor-agent-late-mcp"])
    func gatePaintedAfterReadyPromptNeverReceivesPTYInput(_ fixture: String) async throws {
        let (executable, workspace) = try fakeCursorAgent(named: fixture)
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        let expected: CursorPanelResult = fixture.hasSuffix("trust")
            ? .workspaceTrustRequired : .mcpApprovalRequired
        #expect(await probe.capturePanel() == expected)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    @Test func currentCursorPromptOpensUsagePanelThroughPTY() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-ready")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )
        let snapshot = await CursorProvider(source: probe, now: { augustFirst2026 }).fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.planLabel == "Pro+")
        #expect(snapshot.windows.map(\.utilization) == [1, 3])
        #expect(snapshot.windows.map(\.kind) == namedPoolKinds)
        // The probe trusts only its own empty workspace up front; current CLIs honour
        // the flag, so most users never see the trust handoff.
        let argv = try String(contentsOf: workspace.appendingPathComponent("argv"), encoding: .utf8)
        #expect(argv.contains("--trust"))
    }

    private func snapshot(for text: String) async -> UsageSnapshot {
        await CursorProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        ).fetchSnapshot()
    }

    private func fakeCursorAgent(named name: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-cursor-pty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: name, withExtension: "zsh"))
        let executable = root.appendingPathComponent("cursor-agent")
        try FileManager.default.copyItem(at: fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (executable, root.appendingPathComponent("workspace", isDirectory: true))
    }

    @Test func probeRecoversWhenCursorAgentIsInstalledAfterProbeCreation() async {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-late-cursor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: executable) }
        let path = MutableCursorExecutablePath()
        let probe = CursorUsageCLIProbe(cursorPathResolver: { path.value })

        #expect(await probe.capturePanel() == .cliNotFound)

        let script = """
        #!/bin/sh
        printf '%s' '{"isAuthenticated":false}'
        """
        #expect(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data(script.utf8),
            attributes: [.posixPermissions: 0o700]
        ))
        path.value = executable.path

        #expect(await probe.capturePanel() == .loginRequired)
    }
}

private final class MutableCursorExecutablePath: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    var value: String? {
        get { lock.withLock { path } }
        set { lock.withLock { path = newValue } }
    }
}

@Suite struct CursorConnectionTests {
    @Test func workspaceTrustScriptUsesExactQuotedFolderWithoutAutoApproval() throws {
        let workspace = "/Users/test/Library/Application Support/Headroom/CursorProbe"
        let script = CursorCLI.workspaceTrustScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            workspaceDirectory: workspace,
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("--mode ask --workspace '/Users/test/Library/Application Support/Headroom/CursorProbe'"))
        #expect(script.contains("unset CURSOR_API_KEY CURSOR_API_ENDPOINT"))
        #expect(script.contains("[a] Trust this workspace"))
        // The handoff exists for CLIs that ignore `--trust`; the user decides there.
        #expect(!script.contains("--trust"))
        #expect(!script.contains("--force"))

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

    @Test func mcpApprovalScriptUsesOfficialCLIWithoutAutomaticApproval() throws {
        let script = CursorCLI.mcpApprovalScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            workspaceDirectory: "/tmp/Headroom CursorProbe",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("Review Cursor Agent’s external tools"))
        #expect(script.contains("--workspace '/tmp/Headroom CursorProbe'"))
        #expect(!script.contains("--approve-mcps"))

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

    @Test func loginHandoffClearsAPIOverridesBeforeRunningOfficialCLI() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-cursor-login-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("cursor-agent")
        try """
        #!/bin/zsh
        [[ "$1" == login && -z "${CURSOR_API_KEY-}" && -z "${CURSOR_API_ENDPOINT-}" ]]
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let script = root.appendingPathComponent("login.command")
        try CursorCLI.loginScript(executablePath: executable.path)
            .write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.environment = [
            "TERM": "xterm-256color",
            "CURSOR_API_KEY": "test-override",
            "CURSOR_API_ENDPOINT": "https://example.invalid",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func generatedLoginScriptUsesOnlyOfficialCommandAndParsesAsZsh() throws {
        let script = CursorCLI.loginScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("'/Users/test/.local/bin/cursor-agent' login"))
        #expect(script.contains("unset CURSOR_API_KEY CURSOR_API_ENDPOINT"))
        #expect(CursorCLI.manualLoginCommand(executablePath: "/Users/test/.local/bin/cursor-agent")
            == "env -u CURSOR_API_KEY -u CURSOR_API_ENDPOINT '/Users/test/.local/bin/cursor-agent' login")
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
