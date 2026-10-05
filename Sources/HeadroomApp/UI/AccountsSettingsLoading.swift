import SwiftUI
import HeadroomCore

/// R7–R9/KTD8: a queued fetch is not work, and a failed removal never starts an exit.
struct SettingsAccountLoadingState {
    let showsPill: Bool
    let mode: MiniPill.Mode
    let level: Double

    static func resolve(
        status: AccountsSettingsTile.AccountStatus,
        waitingForClaudeCode: Bool = false,
        phase: SetupWaitingPhase?,
        isProbing: Bool,
        level: Double = LoadingMotionConstants.decorativeLevel,
        reduceMotion: Bool = false,
        exitProgress: Double = 0
    ) -> Self {
        if exitProgress > 0, !reduceMotion {
            return Self(showsPill: true, mode: .drain(progress: exitProgress), level: level)
        }
        if status == .removalFailed {
            return Self(showsPill: true, mode: .still, level: level)
        }
        if status == .removing {
            return Self(showsPill: true, mode: reduceMotion ? .still : .slosh, level: level)
        }
        if waitingForClaudeCode {
            return Self(showsPill: true, mode: .still, level: level)
        }
        if let phase {
            // KTD10: Kyle approved the native 1× drip preview on 2026-10-04.
            let setup = SetupMotion.resolve(phase: phase, surface: .settings, level: level,
                                            reduceMotion: reduceMotion, rowDripApproved: true)
            return Self(showsPill: true, mode: setup.motion.miniPillMode, level: setup.level)
        }
        if status == .fetching || status == .waiting {
            return Self(showsPill: true, mode: isProbing && !reduceMotion ? .slosh : .still, level: level)
        }
        return Self(showsPill: false, mode: .still, level: level)
    }

    /// KTD12: use this account's selected window and percentage mode, including extras;
    /// the provider's main meter would drain the wrong account. Missing data is decorative.
    static func displayedLevel(snapshot: UsageSnapshot, mode: UsagePercentageMode,
                               choice: MenuBarWindowChoice) -> Double {
        guard snapshot.freshness != .pending else { return LoadingMotionConstants.decorativeLevel }
        let candidates = snapshot.windows.filter { !$0.freshness.isUnavailable }
        let window = candidates.first(where: { choice.matches($0.kind) })
            ?? candidates.min(by: { $0.percentRemaining < $1.percentRemaining })
        // KTD6.2: the same normalized fill the popover row and menu bar draw.
        return window.map { UsageMeterReading(window: $0).fraction(for: mode) } ?? LoadingMotionConstants.decorativeLevel
    }
}

private struct SettingsAccountExitProgressKey: EnvironmentKey {
    static let defaultValue = 0.0
}

private extension EnvironmentValues {
    var settingsAccountExitProgress: Double {
        get { self[SettingsAccountExitProgressKey.self] }
        set { self[SettingsAccountExitProgressKey.self] = newValue }
    }
}

/// KTD17: fast probe reads belong to the glyph, never the Accounts tile's body.
struct SettingsAccountWaitPill: View {
    let store: UsageStore
    let account: ProviderAccount
    let status: AccountsSettingsTile.AccountStatus
    let waitingForClaudeCode: Bool
    let showsStatus: Bool
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsAccountExitProgress) private var exitProgress

    var body: some View {
        let loading = SettingsAccountLoadingState.resolve(status: status,
            waitingForClaudeCode: waitingForClaudeCode, phase: SetupSessions.waitingPhase(for: account),
            isProbing: store.probingAccounts.contains(account.key), level: level,
            reduceMotion: reduceMotion, exitProgress: exitProgress)
        if loading.showsPill && (showsStatus || exitProgress > 0) {
            MiniPill(mode: loading.mode, level: loading.level)
                .foregroundStyle(.secondary)
        }
    }
}

enum SettingsAccountExit {
    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : LoadingMotionConstants.drainDuration
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .settingsReveal,
            removal: .modifier(active: SettingsAccountDrainModifier(progress: 1),
                               identity: SettingsAccountDrainModifier(progress: 0))
                // KTD12: this exit owns its full drain lifetime, independently of reorder.
                .animation(.linear(duration: duration(reduceMotion: reduceMotion)))
        )
    }
}

private struct SettingsAccountDrainModifier: @preconcurrency AnimatableModifier {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.settingsAccountExitProgress, progress)
            .opacity(1 - progress)
    }
}
