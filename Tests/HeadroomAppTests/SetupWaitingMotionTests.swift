import HeadroomCore
import Testing
@testable import Headroom

@Suite(.sharedAppState) struct SetupWaitingMotionTests {
    @Test func guidedCardsDistinguishUserWaitFromVerification() {
        let confirming = SetupWaitingPhase.confirming(.signIn, reportedFinished: true)
        for phase in [SetupWaitingPhase.waitingForUser(.signIn), confirming] {
            let content = claudeWaitingCardContent(state: .waiting(attempt: 0), phase: phase,
                hasActiveHandoff: true, failureMessage: nil, failureDetail: nil)
            let expected: LoadingMotion = phase == confirming ? .slosh : .drip
            #expect(content.loadingMotion(reduceMotion: false).motion == expected)
            #expect(CodexWaitingCard(phase: phase, onReopen: {}).loadingMotion(reduceMotion: false).motion == expected)
        }
    }
    @Test func everyProviderUsesApprovedSmallDripAndWorkingSlosh() {
        for provider in [ProviderID.claude, .codex, .grok, .cursor] {
            let account = ProviderAccount.builtIn(for: provider)
            let row = CardRowWaitingLine(account: account, showsStopWaiting: false)
            #expect(row.loadingMotion(phase: .openingTerminal, reduceMotion: false).motion == .slosh)
            #expect(row.loadingMotion(phase: .waitingForUser(.signIn), reduceMotion: false).motion == .drip)
            #expect(row.loadingMotion(phase: .waitingForUser(.signIn), reduceMotion: true).level == 0)
            #expect(row.loadingMotion(phase: .confirming(.signIn, reportedFinished: true), reduceMotion: true).level > 0)
        }
    }
    @Test func failedClaudeShellDoesNotClaimWork() {
        let content = claudeWaitingCardContent(state: .failed(.waitingTimedOut), phase: .confirming(.signIn, reportedFinished: true),
            hasActiveHandoff: true, failureMessage: nil, failureDetail: nil)
        #expect(content.loadingMotion(reduceMotion: false).motion == .still)
    }
}
