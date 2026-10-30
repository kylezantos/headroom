import Testing
import Foundation
@testable import HeadroomCore

/// A real (ANSI-stripped) capture of `claude`'s `/usage` panel, including the messy
/// intermediate render states the parser must survive. The settled values are:
/// session 100% used, week (all models) 38% used, week (Fable) 62% used.
private let usagePanelFixture = """
Settings Status Config Usage Stats
Session
Usage: 0 input, 0 output, 0 cache read, 0 cache write
Current session
██████████████████████████████████████████████████ 100% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
██████████████████▌ 37% used
Resets Jul 2 at 10am (America/Los_Angeles)
Scanning local sessions…
Settings Status Config Usage Stats
Current session
██████████████████████████████████████████████████ 100% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
███████████████████ 38% used
Resets Jul 2 at 10am (America/Los_Angeles)
Current week (Fable)
███████████████████████████████ 62% used
Resets Jul 2 at 10am (America/Los_Angeles)
What's contributing to your limits usage?
"""

/// A real capture of `claude -p "/usage"` — the print-mode report the probe now
/// prefers. Each window ships whole on one line, with no TUI repaints to survive.
private let printUsageReportFixture = """
You are currently using your subscription to power your Claude Code usage

Current session: 6% used · resets Jul 31 at 5:20pm (America/Los_Angeles)
Current week (all models): 4% used · resets Aug 6 at 10am (America/Los_Angeles)
Current week (Fable): 7% used · resets Aug 6 at 10am (America/Los_Angeles)

What's contributing to your limits usage?
Approximate, based on local sessions on this machine — does not include other devices or claude.ai. Behaviors are independent characteristics, not a breakdown.

Last 24h · 27 requests · 2 sessions
  Top skills: /compound-engineering:ce-plan 24%
  Top plugins: compound-engineering 24%
"""

struct ClaudeUsageParserTests {
    @Test func parsesSettledWindows() {
        let windows = ClaudeUsageParser.parse(usagePanelFixture)
        // Three windows, in canonical order: session, weekly (all models), other.
        #expect(windows.count == 3)
        #expect(windows[0].kind == .fiveHour)
        #expect(windows[0].percentUsed == 100)
        #expect(windows[0].resetLabel == "Resets 10:10am")
        #expect(windows[0].resetTimeZoneIdentifier == "America/Los_Angeles")

        #expect(windows[1].kind == .weekly)
        #expect(windows[1].percentUsed == 38)          // settled value, not the 37 mid-scan
        #expect(windows[1].resetLabel == "Resets Jul 2 at 10am")
        #expect(windows[1].resetTimeZoneIdentifier == "America/Los_Angeles")

        #expect(windows[2].kind == .other("Weekly (Fable)"))
        #expect(windows[2].percentUsed == 62)
    }

    @Test func lastRenderWins() {
        // The weekly window appears as 37% then 38%; the settled 38% must win.
        let windows = ClaudeUsageParser.parse(usagePanelFixture)
        #expect(windows.first { $0.kind == .weekly }?.percentUsed == 38)
    }

    @Test func toleratesUnknownAndEmpty() {
        #expect(ClaudeUsageParser.parse("").isEmpty)
        #expect(ClaudeUsageParser.parse("garbage with no windows\nRandom line").isEmpty)
    }

    @Test func ignoresParagraphMentioningWeeklyLimit() {
        // A long sentence mentioning "weekly usage limit" must not be parsed as a window.
        let text = "Until July 7, you can use up to 50% of your plan's weekly usage limit on Fable 5."
        #expect(ClaudeUsageParser.parse(text).isEmpty)
    }

    @Test func normalizesResetLabelRenderArtifacts() {
        let text = """
        Current week (all models)
        █████ 5% used
        Resets Jul 9  t 10am (America/Los_Angeles)
        """
        #expect(ClaudeUsageParser.parse(text).first?.resetLabel == "Resets Jul 9 at 10am")
    }

    @Test func toleratesDroppedLettersFromTUIRepaint() {
        let text = """
        Current week (Fable)
        ████████████████████████████████████████████▌ 89% us d
        R sets Jul 9 at 9:59am (America/Los_Angeles)
        """
        let window = ClaudeUsageParser.parse(text).first
        #expect(window?.kind == .other("Weekly (Fable)"))
        #expect(window?.percentUsed == 89)
        #expect(window?.resetLabel == "Resets Jul 9 at 9:59am")
    }

    @Test func parsesPrintModeReport() {
        let windows = ClaudeUsageParser.parse(printUsageReportFixture)
        #expect(windows.count == 3)
        #expect(windows[0].kind == .fiveHour)
        #expect(windows[0].percentUsed == 6)
        #expect(windows[0].resetLabel == "Resets Jul 31 at 5:20pm")
        #expect(windows[0].resetTimeZoneIdentifier == "America/Los_Angeles")

        #expect(windows[1].kind == .weekly)
        #expect(windows[1].percentUsed == 4)
        #expect(windows[1].resetLabel == "Resets Aug 6 at 10am")

        #expect(windows[2].kind == .other("Weekly (Fable)"))
        #expect(windows[2].percentUsed == 7)
        #expect(windows[2].resetLabel == "Resets Aug 6 at 10am")
    }

    @Test func printModeCostReportParsesEmpty() {
        // `-p "/usage"` on an API-key (non-subscription) login prints a cost report
        // instead — it must never be mistaken for a usage capture.
        let costReport = """
        Total cost:            $0.0000
        Total duration (API):  0s
        Total duration (wall): 0s
        Total code changes:    0 lines added, 0 lines removed
        Usage:                 0 input, 0 output, 0 cache read, 0 cache write
        """
        #expect(ClaudeUsageParser.parse(costReport).isEmpty)
    }

    @Test func extractsPlanTierFromHeader() {
        // The tier appears in the panel header line, e.g. "… · Claude Max".
        #expect(ClaudeUsageParser.plan(in: "Fable 5 with high effort · Claude Max  ~/dir") == "Max")
        #expect(ClaudeUsageParser.plan(in: "Sonnet 5 · Claude Pro") == "Pro")
        #expect(ClaudeUsageParser.plan(in: "Opus 4.8 · Claude Max 20x") == "Max 20x")
    }

    @Test func planTierDoesNotMatchClaudeCodeOrPromoText() {
        // "Claude Code" (the product name) and promo copy must not be read as a tier.
        #expect(ClaudeUsageParser.plan(in: "Claude Code v2.1.199") == nil)
        #expect(ClaudeUsageParser.plan(in: "up to 50% of your plan's weekly usage limit") == nil)
        #expect(ClaudeUsageParser.plan(in: "") == nil)
    }
}

struct ClaudeProviderTests {
    private func provider(_ result: ClaudePanelResult) -> ClaudeProvider {
        ClaudeProvider(source: MockClaudeSource(result: result),
                       now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    @Test func panelBecomesLiveSnapshot() async {
        let snap = await provider(.panel(text: usagePanelFixture, planHint: nil)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.count == 3)
        // percentUsed 100 -> 0 remaining; 38 -> 62 remaining.
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 0)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 62)
        #expect(snap.windows.first { $0.kind == .weekly }?.resetLabel == "Resets Jul 2 at 10am")
    }

    @Test func percentageWithoutResetStaysLiveWithoutFabricatedDeadline() async {
        let panel = """
        Current session
        ████ 0% used
        Current week (all models)
        ████ 12% used
        """

        let snap = await provider(.panel(text: panel, planHint: nil)).fetchSnapshot()
        let session = snap.windows.first { $0.kind == .fiveHour }
        let weekly = snap.windows.first { $0.kind == .weekly }

        #expect(snap.freshness == .live)
        #expect(session?.resetSchedule == .unresolved(.absent))
        #expect(weekly?.resetSchedule == .unresolved(.absent))
        #expect(session.map { Countdown.resetText(for: $0, now: snap.capturedAt!) } == "Available")
        #expect(weekly.map { Countdown.resetText(for: $0, now: snap.capturedAt!) } == "Reset info unavailable")
    }

    @Test func malformedAndInvalidZoneResetEvidenceRemainTyped() async throws {
        let malformed = """
        Current session
        ████ 12% used
        Resets bearer-secret (America/Los_Angeles)
        """
        let invalidZone = """
        Current session
        ████ 12% used
        Resets 10:10am (secret-zone)
        """

        let malformedSnapshot = await provider(.panel(text: malformed, planHint: nil)).fetchSnapshot()
        let invalidZoneSnapshot = await provider(.panel(text: invalidZone, planHint: nil)).fetchSnapshot()

        #expect(malformedSnapshot.windows.first?.resetSchedule == .unresolved(.unparseable))
        #expect(invalidZoneSnapshot.windows.first?.resetSchedule == .unresolved(.invalidZone))
        #expect(malformedSnapshot.windows.first?.percentUsed == 12)
        #expect(invalidZoneSnapshot.windows.first?.percentUsed == 12)
        #expect(malformedSnapshot.windows.first?.resetLabel == nil)
        #expect(malformedSnapshot.windows.first?.resetTimeZoneIdentifier == nil)
        #expect(invalidZoneSnapshot.windows.first?.resetLabel == "Resets 10:10am")
        #expect(invalidZoneSnapshot.windows.first?.resetTimeZoneIdentifier == nil)

        let projected = WidgetSnapshotProjector.project(
            snapshots: [.claude: malformedSnapshot],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: malformedSnapshot.capturedAt!
        )
        let synced = SyncedWidgetSnapshotEnvelope(
            publishedAt: malformedSnapshot.capturedAt!,
            sourceID: "test-mac",
            sourcePlatform: .macOS,
            snapshot: projected
        )
        let payload = String(decoding: try SyncedWidgetSnapshotCodec.encode(synced), as: UTF8.self)
        #expect(!payload.contains("bearer-secret"))
        #expect(!payload.contains("secret-zone"))
    }

    @Test func providerCapturesOneTimeAnchorForEveryWindow() async {
        let capture = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = CountingClock(value: capture)
        let panel = """
        Current session
        ████ 12% used
        Current week (all models)
        ████ 24% used
        """
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .panel(text: panel, planHint: nil)),
            now: { clock.read() }
        )

        let snapshot = await provider.fetchSnapshot()

        #expect(clock.callCount == 1)
        #expect(snapshot.capturedAt == capture)
        #expect(snapshot.windows.allSatisfy { $0.resetSchedule == .unresolved(.absent) })
    }

    @Test func liveSnapshotCarriesPlanTier() async {
        let panel = """
        Fable 5 with high effort · Claude Max  ~/dir
        Current session
        ████ 16% used
        Resets 8:10pm (America/Los_Angeles)
        """
        let snap = await provider(.panel(text: panel, planHint: nil)).fetchSnapshot()
        #expect(snap.planLabel == "Max")
    }

    @Test func printReportBecomesLiveSnapshotWithPlanHint() async {
        // The print-mode report has no "· Claude Max" header, so the tier comes from
        // the probe's auth-status hint.
        let snap = await provider(.panel(text: printUsageReportFixture, planHint: "Max")).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.count == 3)
        #expect(snap.windows.first { $0.kind == .other("Weekly (Fable)") }?.percentRemaining == 93)
        #expect(snap.planLabel == "Max")
    }

    @Test func panelHeaderTierWinsOverPlanHint() async {
        // The interactive panel's own header carries multiplier fidelity ("Max 20x")
        // that auth-status lacks — text wins when both are present.
        let panel = """
        Opus 4.8 · Claude Max 20x
        Current session
        ████ 16% used
        Resets 8:10pm (America/Los_Angeles)
        """
        let snap = await provider(.panel(text: panel, planHint: "Max")).fetchSnapshot()
        #expect(snap.planLabel == "Max 20x")
    }

    @Test func printUsageVersionGate() {
        // 2.1.217 is the oldest CLI verified to dispatch /usage locally in print mode.
        #expect(ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "2.1.217 (Claude Code)"))
        #expect(ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "2.1.220 (Claude Code)"))
        #expect(ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "2.2.0 (Claude Code)"))
        #expect(ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "3.0.0 (Claude Code)"))
        #expect(!ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "2.1.216 (Claude Code)"))
        #expect(!ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "1.0.98 (Claude Code)"))
        #expect(!ClaudeUsageCLIProbe.printUsageSupported(versionOutput: ""))
        #expect(!ClaudeUsageCLIProbe.printUsageSupported(versionOutput: "not a version"))
    }

    // KTD4 (2026-09-19 sign-in plan): the sign-in floor is a separate three-answer
    // predicate, because "unreadable" must keep the interactive launch rather than
    // block sign-in the way a readable-but-old version does.
    @Test func signInVersionGateSeparatesTooOldFromUnreadable() {
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "2.1.41 (Claude Code)") == .supported)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "2.1.278 (Claude Code)") == .supported)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "3.0.0 (Claude Code)") == .supported)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "2.1.40 (Claude Code)") == .tooOld)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "2.0.99 (Claude Code)") == .tooOld)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "1.0.98 (Claude Code)") == .tooOld)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "") == .unreadable)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "garbage") == .unreadable)
        #expect(ClaudeUsageCLIProbe.signInSupport(versionOutput: "2.1") == .unreadable)
    }

    @Test func confirmedCLIMissIsProviderCapabilityRatherThanAccountSetup() async {
        let result = await provider(.cliNotFound).fetchResult()
        #expect(result.capability == .confirmedAbsent)
        guard case .stale(let reason) = result.snapshot.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason.providerSetupOutcome == nil)
        #expect(!reason.isPermanent)
    }

    @Test func inconclusiveCLIDiscoveryRemainsRetryableProviderCapability() async {
        let result = await provider(.cliInconclusive(.shellTimeout)).fetchResult()
        #expect(result.capability == .inconclusive(.shellTimeout))
        guard case .stale(let reason) = result.snapshot.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason.providerSetupOutcome == nil)
        #expect(!reason.isPermanent)
    }

    @Test func captureFailureIsTransient() async {
        let snap = await provider(.transientCapture).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeTransientCapture)
    }

    @Test func probeInvalidatesLaunchRaceAndRetriesWithRediscoveredExecutable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replacement = directory.appendingPathComponent("claude")
        try Data("#!/bin/zsh\nprint 'Select login method'\n".utf8).write(to: replacement)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)

        let missing = directory.appendingPathComponent("moved-claude").path
        let searches = ExecutableSearchSequence([
            .completed(candidates: [missing]),
            .completed(candidates: [replacement.path]),
        ])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: ProbeHintStore(),
            shellSearch: { await searches.next() },
            // Model a time-of-check/time-of-use race: the first candidate passes
            // discovery but disappears before Process launches it.
            validate: { _ in .executable }
        )
        let result = await ClaudeUsageCLIProbe(
            locator: locator,
            workingDirectory: directory.path
        ).capturePanel()

        #expect(result == .loginRequired)
        #expect(await searches.count == 2)
    }

    @Test func directUsageDoesNotLaunchAuthStatusForEitherConfigHome() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-direct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        let trace = directory.appendingPathComponent("trace")
        try """
        #!/bin/zsh
        print -r -- "$*|${CLAUDE_CONFIG_DIR:-built-in}" >> "$HEADROOM_FIXTURE_TRACE"
        if [[ "$1" == "--version" ]]; then
          print '2.1.302 (Claude Code)'
        elif [[ "$1" == "-p" && "$2" == "/usage" ]]; then
          print 'Current session: 10% used'
          print 'Current week (all models): 20% used'
        else
          print '{"loggedIn":false}'
        fi
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let locator = CLIExecutableLocator(
            executableName: "claude", fallbackPaths: [executable.path],
            hintStore: ProbeHintStore(), shellSearch: { .completed(candidates: [executable.path]) },
            validate: { _ in .executable }
        )
        for home in [nil, directory.appendingPathComponent("extra").path] as [String?] {
            var overrides = ["HEADROOM_FIXTURE_TRACE": trace.path]
            overrides["CLAUDE_CONFIG_DIR"] = home
            let result = await ClaudeUsageCLIProbe(
                locator: locator, workingDirectory: directory.path,
                environmentOverrides: overrides
            ).capturePanel()
            guard case .panel(let text, let hint) = result else {
                Issue.record("expected direct usage report"); continue
            }
            #expect(ClaudeUsageParser.parse(text).count == 2)
            #expect(hint == nil)
        }
        let commands = try String(contentsOf: trace, encoding: .utf8)
        #expect(!commands.contains("auth status"))
        #expect(commands.contains("-p /usage --no-session-persistence|built-in"))
        #expect(commands.contains("-p /usage --no-session-persistence|\(directory.path)/extra"))
    }

    @Test(arguments: [
        ("Select login method", ClaudePanelResult.loginRequired),
        ("Quick safety check: trust this folder?", ClaudePanelResult.workspaceTrustRequired),
        ("Unrecognized new onboarding screen", ClaudePanelResult.unknownUI),
        ("Claude  in  Chrome  extension  detected\n❯  No,  keep  browser  tools  off\n  Yes,  use  my  browser",
         ClaudePanelResult.startupQuestion),
        ("Claude Code v2.1.302\n❯ Try \"edit a file\"\nNot logged in · Run /login", ClaudePanelResult.loginRequired),
        ("Claude Code\n? for shortcuts\nNot logged in · Please run /login", ClaudePanelResult.loginRequired),
    ])
    func directUsageFallbackNeverTypesIntoSetupScreens(boot: String, expected: ClaudePanelResult) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        let input = directory.appendingPathComponent("input")
        try """
        #!/bin/zsh
        if [[ "$1" == "--version" ]]; then
          print '2.1.216 (Claude Code)'
          exit 0
        fi
        print -r -- "$HEADROOM_FIXTURE_BOOT"
        if read -r -t 8 captured; then
          print -r -- "$captured" > "$HEADROOM_FIXTURE_INPUT"
        fi
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let locator = CLIExecutableLocator(
            executableName: "claude", fallbackPaths: [executable.path],
            hintStore: ProbeHintStore(), shellSearch: { .completed(candidates: [executable.path]) },
            validate: { _ in .executable }
        )
        let result = await ClaudeUsageCLIProbe(
            locator: locator, workingDirectory: directory.path,
            environmentOverrides: ["HEADROOM_FIXTURE_BOOT": boot, "HEADROOM_FIXTURE_INPUT": input.path],
            bootTimeout: 4, panelTimeout: 4
        ).capturePanel()
        #expect(result == expected)
        let received = (try? String(contentsOf: input, encoding: .utf8)) ?? ""
        #expect(!received.contains("/usage"))
    }

    @Test func signedOutPrintReportReturnsLoginRequiredWithoutOpeningPTY() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-signed-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        let trace = directory.appendingPathComponent("trace")
        try """
        #!/bin/zsh
        print -r -- "$*" >> "$HEADROOM_FIXTURE_TRACE"
        if [[ "$1" == "--version" ]]; then
          print '2.1.302 (Claude Code)'
        else
          print 'Not logged in · Please run /login'
        fi
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let locator = CLIExecutableLocator(
            executableName: "claude", fallbackPaths: [executable.path],
            hintStore: ProbeHintStore(), shellSearch: { .completed(candidates: [executable.path]) },
            validate: { _ in .executable }
        )
        let result = await ClaudeUsageCLIProbe(
            locator: locator, workingDirectory: directory.path,
            environmentOverrides: ["HEADROOM_FIXTURE_TRACE": trace.path],
            bootTimeout: 1, panelTimeout: 1
        ).capturePanel()
        #expect(result == .loginRequired)
        let commands = try String(contentsOf: trace, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(commands == ["--version", "-p /usage --no-session-persistence", ""])
    }

    @Test func loggedOutPanelAsksToLogIn() async {
        let snap = await provider(.loginRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeLoginRequired)
    }

    @Test func loginRequiredResultReadsAsNeedsSignIn() async {
        // A fresh CLAUDE_CONFIG_DIR (extra account before its first sign-in) boots into
        // a first-run screen; the probe bails there before typing (an Enter on the
        // login selector would start a browser sign-in) and types the result. Must be
        // permanent — a transient blip would hide the account's Sign in affordance.
        let snap = await provider(.loginRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeLoginRequired)
    }

    @Test func probeClassifiesFirstRunScreens() {
        #expect(ClaudeUsageCLIProbe.isFirstRunScreen("Welcome!\nChoose the text style that looks best with your terminal"))
        #expect(ClaudeUsageCLIProbe.isFirstRunScreen("Select login method: 1. Claude account with subscription"))
        #expect(!ClaudeUsageCLIProbe.isFirstRunScreen("Current session\n38% used\nResets 2:15pm"))
    }

    @Test func bootClassifierFailsClosedBeforeInput() {
        #expect(ClaudeUsageCLIProbe.classifyBootText("") == .noOutput)
        #expect(ClaudeUsageCLIProbe.classifyBootText("Quick safety check: Is this a project you trust?") == .trustRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("Choose the text style that looks best") == .loginRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("""
        Claude Code v2.1.216
        Quick safety check: Is this a project you trust?
        ❯ Continue
        manual mode on · ← for agents
        """) == .trustRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("""
        Claude Code v2.1.216
        Select login method
        ❯ Claude account with subscription
        manual mode on · ← for agents
        """) == .loginRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("A brand new onboarding screen") == .unknown)
        #expect(ClaudeUsageCLIProbe.classifyBootText("Claude Code\n? for shortcuts") == .ready)
    }

    @Test func bootClassifierRecognizesCurrentPrompt() {
        let currentPrompt = """
        Claude Code v2.1.216
        Opus 4.8 with high effort
        ────────────────────────────────────────────────
        ❯ Try "how do I log an error?"
        ────────────────────────────────────────────────
        manual mode on · ← for agents
        """

        #expect(ClaudeUsageCLIProbe.classifyBootText(currentPrompt) == .ready)
    }

    @Test func bootClassifierRecognizes2_1_218Prompt() {
        // A real ANSI-stripped capture of the CLI 2.1.218 (Jul 2026) boot screen. That
        // release repaints via cursor positioning, so the stripped text carries carriage
        // returns but NO line feeds, and it dropped both "? for shortcuts" and the
        // "… for agents" tagline the classifier used to key on — the regression that made
        // it fall through to .unknown and never type /usage. The "❯" prompt marker and the
        // `Try "…"` placeholder must still classify it .ready.
        let boot218 = " 7  8      [<u [>1u [>4;2m [>0q     [<u [>1u [>4;2m        \r   ▐ ▛███▜ ▌   Claude Code   v2.1.218\r  ▝▜ █████ ▛▘  Fable 5 with high effort · Claude Max\r    ▘▘ ▝▝    ~/App Development/headroom\r  ● high · /effort\r  ────────────────────────────────────────────────────────────────────────────────\r  ❯  Try \"fix lint errors\"\r   ────────────────────────────────────────────────────────────────────────────────\r   ⚠ Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker  · res…\r   /rc connecting…\r   ⏸ manual mode on        \r   ⚠ 1 MCP server needs authentication  · run /mcp\r  kzmbp in headroom • Fable 5        \r          \r                /rc      "

        #expect(!boot218.contains("\n"))
        #expect(!boot218.localizedCaseInsensitiveContains("? for shortcuts"))
        #expect(!boot218.localizedCaseInsensitiveContains("for agents"))
        #expect(ClaudeUsageCLIProbe.classifyBootText(boot218) == .ready)

        // A menu-shaped screen that names "Claude Code" and shows a "❯" selector but no
        // input placeholder must still fail closed — banner + prompt alone is not enough.
        #expect(ClaudeUsageCLIProbe.classifyBootText("""
        Claude Code v2.1.218
        A brand new onboarding step we do not recognize
        ❯ Set up now
        """) == .unknown)
    }

    @Test func builtInProbeCannotInheritAnotherClaudeHome() {
        let builtIn = ClaudeUsageCLIProbe.environment(
            inherited: ["CLAUDE_CONFIG_DIR": "/wrong", "PATH": "/bin"],
            overrides: [:],
            loginPath: "/resolved/bin",
            workingDirectory: "/workspace"
        )
        let extra = ClaudeUsageCLIProbe.environment(
            inherited: ["CLAUDE_CONFIG_DIR": "/wrong"],
            overrides: ["CLAUDE_CONFIG_DIR": "/exact"],
            loginPath: "/resolved/bin",
            workingDirectory: "/workspace"
        )
        #expect(builtIn["CLAUDE_CONFIG_DIR"] == nil)
        #expect(extra["CLAUDE_CONFIG_DIR"] == "/exact")
    }

    @Test func loginMethodSelectorReadsAsNeedsSignIn() async {
        let snap = await provider(.loginRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeLoginRequired)
    }

    @Test func trustPromptAsksUserToOpenClaude() async {
        let snap = await provider(.workspaceTrustRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeTrustRequired)
    }

    @Test func startupQuestionAsksUserToOpenClaudeCode() async {
        let snap = await provider(.startupQuestion).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeStartupQuestion)
        #expect(reason.isPermanent)
        #expect(reason.providerSetupOutcome?.recoveryPresentation.primaryAction == .answerClaudeQuestion)
    }

    @Test func unknownInteractiveSurfaceNeverMasqueradesAsLoginOrTrust() async {
        let snap = await provider(.unknownUI).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeUnknownUI)
    }
}

private final class CountingClock: @unchecked Sendable {
    private let lock = NSLock()
    private let value: Date
    private var calls = 0

    init(value: Date) { self.value = value }

    var callCount: Int { lock.withLock { calls } }

    func read() -> Date {
        lock.withLock {
            calls += 1
            return value
        }
    }
}

private actor ExecutableSearchSequence {
    private var results: [CLIExecutableShellResult]
    private(set) var count = 0

    init(_ results: [CLIExecutableShellResult]) { self.results = results }

    func next() -> CLIExecutableShellResult {
        count += 1
        return results.removeFirst()
    }
}

private final class ProbeHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func hint(for executableName: String) -> String? { lock.withLock { value } }
    func setHint(_ path: String?, for executableName: String) { lock.withLock { value = path } }
}
