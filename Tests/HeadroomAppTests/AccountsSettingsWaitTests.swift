import Foundation
import SwiftUI
import Testing
import HeadroomCore
@testable import Headroom

@MainActor
@Suite struct AccountsSettingsWaitTests {
    @Test func verificationWorksAfterTheTerminalHandoffHasGone() {
        let phase = SetupWaitingPhase.resolve(state: .verifying, hasActiveHandoff: false,
                                             purpose: .setup)
        let loading = SettingsAccountLoadingState.resolve(status: .waiting, phase: phase,
                                                           isProbing: false)
        #expect(loading.mode == .slosh)
        #expect(loading.showsPill)
    }

    @Test func allProviderUserWaitsUseTheApprovedDrip() {
        for provider in [ProviderID.claude, .codex, .grok, .cursor] {
            let account = ProviderAccount.builtIn(for: provider)
            let phase = SetupWaitingPhase.resolve(state: .waiting(attempt: 0),
                                                 hasActiveHandoff: true, purpose: .setup)
            let loading = SettingsAccountLoadingState.resolve(status: .waiting, phase: phase,
                                                               isProbing: false)
            #expect(loading.mode == .drip, "\(account.providerID)")
            #expect(loading.level == 0)
        }
    }

    @Test func openingAndConfirmingKeepWorkingAndReduceMotionKeepsDistinctStills() {
        for phase in [SetupWaitingPhase.openingTerminal, .confirming(.signIn, reportedFinished: true)] {
            #expect(SettingsAccountLoadingState.resolve(status: .waiting, phase: phase,
                                                         isProbing: false).mode == .slosh)
            let still = SettingsAccountLoadingState.resolve(status: .waiting, phase: phase,
                                                            isProbing: false, reduceMotion: true)
            #expect(still.mode == .still)
            #expect(still.level > 0)
        }
        let wait = SettingsAccountLoadingState.resolve(status: .waiting,
                    phase: .waitingForUser(.deviceCode), isProbing: true, reduceMotion: true)
        #expect(wait.mode == .still)
        #expect(wait.level == 0)
    }

    @Test func waitingForClaudeCodeNeverClaimsAProbeOrUserAction() {
        let loading = SettingsAccountLoadingState.resolve(status: .fetching,
            waitingForClaudeCode: true, phase: nil, isProbing: true)
        #expect(loading.showsPill)
        #expect(loading.mode == .still)
    }

    @Test func queuedFetchingWaitsStillAndOnlyAnActualProbeSloshes() {
        #expect(SettingsAccountLoadingState.resolve(status: .fetching, phase: nil,
                                                     isProbing: false).mode == .still)
        #expect(SettingsAccountLoadingState.resolve(status: .fetching, phase: nil,
                                                     isProbing: true).mode == .slosh)
    }

    @Test func failedRemovalStopsWithoutStartingADrain() {
        #expect(SettingsAccountLoadingState.resolve(status: .removing, phase: nil,
                                                     isProbing: false).mode == .slosh)
        let failed = SettingsAccountLoadingState.resolve(status: .removalFailed,
            phase: .waitingForUser(.signIn), isProbing: true)
        #expect(failed.showsPill)
        #expect(failed.mode == .still)
    }

    @Test func builtInExitDrainsTheSelectedDisplayedWindowRatherThanADecorativeLevel() {
        let snapshot = UsageSnapshot(providerID: .claude, windows: [
            UsageWindow(kind: .fiveHour, utilization: 81, resetSchedule: .unresolved(.absent)),
            UsageWindow(kind: .weekly, utilization: 27, resetSchedule: .unresolved(.absent))
        ], planLabel: nil, capturedAt: Date(), freshness: .live)
        let level = SettingsAccountLoadingState.displayedLevel(snapshot: snapshot,
            mode: .remaining, choice: .weekly)
        #expect(abs(level - 0.73) < 0.0001)
        let start = SettingsAccountLoadingState.resolve(status: .connected, phase: nil,
            isProbing: false, level: level, exitProgress: 0.00001)
        let finish = SettingsAccountLoadingState.resolve(status: .connected, phase: nil,
            isProbing: false, level: level, exitProgress: 1)
        #expect(start.showsPill)
        #expect(MiniPillPose(mode: start.mode, level: start.level, date: Date(), reduceMotion: false).level > 0.72)
        #expect(MiniPillPose(mode: finish.mode, level: finish.level, date: Date(), reduceMotion: false).level == 0)
        #expect(SettingsAccountExit.duration(reduceMotion: false) == LoadingMotionConstants.drainDuration)
        #expect(SettingsAccountExit.duration(reduceMotion: true) == 0)
    }

    @Test func displayedLevelFollowsUsedModeAndPendingHasNoInventedPercentage() {
        let snapshot = UsageSnapshot(providerID: .codex, windows: [
            UsageWindow(kind: .weekly, utilization: 27, resetSchedule: .unresolved(.absent))
        ], planLabel: nil, capturedAt: Date(), freshness: .live)
        #expect(SettingsAccountLoadingState.displayedLevel(snapshot: snapshot,
            mode: .used, choice: .weekly) == 0.27)
        #expect(SettingsAccountLoadingState.displayedLevel(snapshot: .pending(for: .codex),
            mode: .remaining, choice: .weekly) == LoadingMotionConstants.decorativeLevel)
    }

    @Test func drainHonorsVisibleSelectedSparkAndFallsBackWhenHidden() async {
        let suite = "co.zantos.headroom.tests.settings-drain.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.showCodexSparkCountersInApp = true
        let snapshot = UsageSnapshot(providerID: .codex, windows: [
            UsageWindow(kind: .weekly, utilization: 27, resetSchedule: .unresolved(.absent)),
            UsageWindow(kind: .other("GPT-5.3-Codex-Spark Weekly"), utilization: 91,
                        resetSchedule: .unresolved(.absent))
        ], planLabel: nil, capturedAt: Date(), freshness: .live)
        let account = ProviderAccount.builtIn(for: .codex)
        let store = UsageStore(providers: [
            DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: snapshot)
        ], preferences: preferences)
        await store.refreshAll()
        let choice = MenuBarWindowChoice.window(id: "other:GPT-5.3-Codex-Spark Weekly")
        let visible = SettingsAccountLoadingState.displayedLevel(
            snapshot: store.appDisplaySnapshot(for: account.key), mode: .remaining, choice: choice)
        #expect(abs(visible - 0.09) < 0.0001)
        store.setShowCodexSparkCountersInApp(false)
        let hidden = SettingsAccountLoadingState.displayedLevel(
            snapshot: store.appDisplaySnapshot(for: account.key), mode: .remaining, choice: choice)
        #expect(abs(hidden - 0.73) < 0.0001)
    }
}
