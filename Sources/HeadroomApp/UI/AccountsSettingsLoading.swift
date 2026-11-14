#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
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

    var body: some View {
        let loading = SettingsAccountLoadingState.resolve(status: status,
            waitingForClaudeCode: waitingForClaudeCode, phase: SetupSessions.waitingPhase(for: account),
            isProbing: store.probingAccounts.contains(account.key), level: level,
            reduceMotion: reduceMotion)
        if loading.showsPill && showsStatus {
            MiniPill(mode: loading.mode, level: loading.level)
                .foregroundStyle(.secondary)
        }
    }
}

/// CA-M3: the vessel a removed row drains in its own slot. It reads the drain's progress per
/// frame from the environment, so the tile's body renders once for the whole drain.
struct SettingsAccountDrainPill: View {
    let level: Double
    @Environment(\.settingsAccountExitProgress) private var exitProgress

    var body: some View {
        let loading = SettingsAccountLoadingState.resolve(status: .connected, phase: nil,
            isProbing: false, level: level, exitProgress: max(exitProgress, .leastNonzeroMagnitude))
        MiniPill(mode: loading.mode, level: loading.level)
            .foregroundStyle(.secondary)
    }
}

/// CA-M3 (MOT-03): a removed row holds its slot while its vessel drains, and only then does
/// the gap close. This partly overturns the loading plan's KTD12, which let the exit own its
/// drain "independently of reorder": the row left layout at once, so the next row slid under
/// it about 0.37s into a 1.1s drain, and a last row hung below the tile's contracted edge.
/// The drain's look and length are unchanged; only its order against the gap is.
enum SettingsAccountExit {
    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : LoadingMotionConstants.drainDuration
    }

    /// Under Reduce Motion a removal stays instant, as it was (no held slot, no drain).
    static func holdsSlot(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The text stays solid for the first 0.8s and fades over the drain's last 0.3s.
    static let solidFraction = 0.8 / LoadingMotionConstants.drainDuration

    static func drainOpacity(progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        guard clamped > solidFraction else { return 1 }
        return max(0, 1 - (clamped - solidFraction) / (1 - solidFraction))
    }

    /// Insertion keeps the shared reveal. Removal is an 80ms `partOut` fade (CA-M2, KTD8):
    /// a drained row is already transparent when it leaves, and any other removal is gone
    /// before a neighbour reaches it while the gap closes on the scope's `reorder`.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .settingsReveal,
            removal: AnyTransition.opacity.animation(HeadroomMotion.partOut)
        )
    }
}

/// CA-M3: what a draining row draws, frozen at the moment its removal succeeded. The store
/// has already let the account go, so nothing here reads it again.
struct SettingsAccountDrainingRow: Equatable, Identifiable {
    let row: DisplayAccount
    let title: String
    let detail: String?
    let level: Double
    /// The row's position in the list when it was removed; it drains there.
    let index: Int

    var id: AccountID { row.id }
}

/// CA-M3: the provider list as drawn, the store's rows with each draining row back in the slot
/// it held. A live row with the same id wins (a stop-tracked built-in shown again mid-drain),
/// so no id is drawn twice. Once a drain finishes and its row leaves this list, the list is
/// the store's rows exactly, so nothing is left below the tile's contracted edge.
enum SettingsAccountListItem: Identifiable, Equatable {
    case live(DisplayAccount)
    case draining(SettingsAccountDrainingRow)

    var id: AccountID {
        switch self {
        case .live(let row): row.id
        case .draining(let row): row.id
        }
    }

    /// CA-M3 review fix: one draining row per account. Stop-tracking the built-in row, Show
    /// Default Login and stop-tracking again inside one drain would otherwise queue two rows
    /// with one `AccountID`, a duplicate `ForEach` id. The newer capture replaces the older in
    /// place; it keeps the running drain's view, so it ends on that drain's clock.
    static func addingDrain(
        _ row: SettingsAccountDrainingRow, to draining: [SettingsAccountDrainingRow]
    ) -> [SettingsAccountDrainingRow] {
        var next = draining
        if let index = next.firstIndex(where: { $0.id == row.id }) {
            next[index] = row
        } else {
            next.append(row)
        }
        return next
    }

    static func items(rows: [DisplayAccount], draining: [SettingsAccountDrainingRow]) -> [Self] {
        var items = rows.map(Self.live)
        let liveIDs = Set(rows.map(\.id))
        for row in draining.sorted(by: { $0.index < $1.index }) where !liveIDs.contains(row.id) {
            items.insert(.draining(row), at: min(row.index, items.count))
        }
        return items
    }
}

/// CA-M3: drives one draining row's progress, so its vessel drains and its text fades on one
/// clock.
struct SettingsAccountDrainModifier: @preconcurrency AnimatableModifier {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.settingsAccountExitProgress, progress)
            .opacity(SettingsAccountExit.drainOpacity(progress: progress))
    }
}
