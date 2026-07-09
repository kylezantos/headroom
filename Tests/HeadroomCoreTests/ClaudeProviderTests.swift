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

struct ClaudeUsageParserTests {
    @Test func parsesSettledWindows() {
        let windows = ClaudeUsageParser.parse(usagePanelFixture)
        // Three windows, in canonical order: session, weekly (all models), other.
        #expect(windows.count == 3)
        #expect(windows[0].kind == .fiveHour)
        #expect(windows[0].percentUsed == 100)
        #expect(windows[0].resetLabel == "Resets 10:10am")

        #expect(windows[1].kind == .weekly)
        #expect(windows[1].percentUsed == 38)          // settled value, not the 37 mid-scan
        #expect(windows[1].resetLabel == "Resets Jul 2 at 10am")

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
        let snap = await provider(.panel(usagePanelFixture)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.count == 3)
        // percentUsed 100 -> 0 remaining; 38 -> 62 remaining.
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 0)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 62)
        #expect(snap.windows.first { $0.kind == .weekly }?.resetLabel == "Resets Jul 2 at 10am")
    }

    @Test func liveSnapshotCarriesPlanTier() async {
        let panel = """
        Fable 5 with high effort · Claude Max  ~/dir
        Current session
        ████ 16% used
        Resets 8:10pm (America/Los_Angeles)
        """
        let snap = await provider(.panel(panel)).fetchSnapshot()
        #expect(snap.planLabel == "Max")
    }

    @Test func missingCLIDegradesToNotLoggedIn() async {
        let snap = await provider(.cliNotFound).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.isPermanent)
    }

    @Test func captureFailureIsTransient() async {
        let snap = await provider(.failed).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(!reason.isPermanent)   // will retry next cycle
    }

    @Test func loggedOutPanelAsksToLogIn() async {
        let snap = await provider(.panel("Please run /login to log in to Claude")).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.isPermanent)    // needsReauth
    }

    @Test func trustPromptAsksUserToOpenClaude() async {
        let snap = await provider(.panel("Quick safety check: Is this a project you created or one you trust?")).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason == .needsReauth(ClaudeUsageWorkspace.trustRequiredMessage))
    }
}
