import Foundation
import Observation

public enum SetupHandoffMode: Sendable, Equatable {
    case standard
    case deviceCode
}

/// Why Headroom opened the official CLI. Purpose stays separate from login mode:
/// a reset currently uses standard login, while Codex/Grok can use device-code mode
/// for either ordinary setup or a future reset flow.
public enum SetupHandoffPurpose: String, Sendable, Equatable {
    case setup
    case reset
    case trust
    case approval
}

/// Redaction-safe outcome from the official CLI wrapper. Headroom keeps only whether
/// the process reported success; provider output and authentication details never
/// cross the Terminal handoff boundary.
public enum SetupHandoffCompletion: Sendable, Equatable {
    case succeeded
    case failed
    case unknown
}

public enum SetupSessionFailure: Error, Sendable, Equatable {
    case executableMissing
    /// R6/KTD1 (2026-09-19 sign-in plan): the installed CLI is too old for the handoff to
    /// finish, so staging refuses instead of opening a Terminal window that cannot be
    /// confirmed. Distinct from `executableMissing`, which points at installation.
    case updateRequired
    case stagingFailed
    case terminalRejected
    case pasteboardFailed
    case retryExhausted
    /// KTD7 (2026-09-19 sign-in plan): the bounded Claude wait expired with Terminal still
    /// open. Separate from `retryExhausted` because that state offers every other provider
    /// Sign In and Check Now, which a still-open handoff must not.
    case waitingTimedOut
    /// KTD10 (2026-09-19 sign-in plan): Terminal exited and the final check still reports
    /// the account signed out. `auth login`'s exit status on an abandoned sign-in is
    /// unobserved, so this never depends on the wrapper's recorded completion.
    case closedBeforeSignIn
    case provider(ProviderSetupOutcome)
    case providerCapability(ProviderCapabilityState)
}

/// KTD6 (2026-09-19 sign-in plan): how a waiting session learns it can stop waiting.
/// The policy is chosen once, when the handoff is staged, and saved with it — never
/// re-derived from a CLI version that can change while the original Terminal is open.
public enum SetupWaitingPolicy: String, Sendable, Equatable, CaseIterable {
    /// Today’s bounded retry ladder. Every provider but Claude, OpenCode and Antigravity.
    case retryLadder
    /// One check a fixed delay after each landed result. Claude's `interactive` launch,
    /// where the CLI's own screens can be satisfied without the process exiting.
    case polled
    /// No checks at all: every one would read signed-out until the CLI process exits, and
    /// the marker monitor reports that exit within 500 ms.
    case exitSignalled

    /// KTD6: a `signIn` script and every `.reset` drive an `auth` subcommand that owns the
    /// window and then exits, so the exit is the only meaningful signal. Purpose decides
    /// reset, because a reset's stamped kind only describes the script's shape.
    public static func staged(
        providerID: ProviderID,
        purpose: SetupHandoffPurpose,
        claudeScriptKind: ClaudeSetupScriptKind?
    ) -> Self {
        if let policy = exitSignalledOpenCode(providerID: providerID, purpose: purpose) { return policy }
        if let policy = exitSignalledAntigravity(providerID: providerID, purpose: purpose) { return policy }
        guard providerID == .claude else { return .retryLadder }
        if purpose == .reset { return .exitSignalled }
        return claudeScriptKind == .signIn ? .exitSignalled : .polled
    }

    /// KTD8: a handoff opened by a build that saved no record. Purpose is all that
    /// survives in the marker, and a `.setup` handoff on a current CLI is overwhelmingly
    /// the sign-in script; `.trust` is always the interactive launch.
    public static func restored(providerID: ProviderID, purpose: SetupHandoffPurpose) -> Self {
        if let policy = exitSignalledOpenCode(providerID: providerID, purpose: purpose) { return policy }
        if let policy = exitSignalledAntigravity(providerID: providerID, purpose: purpose) { return policy }
        guard providerID == .claude else { return .retryLadder }
        return purpose == .setup || purpose == .reset ? .exitSignalled : .polled
    }

    /// KTD11 (OpenCode plan): the device login can outlast the 55-second ladder, and every
    /// check before it exits would read signed out, so OpenCode sign-in and reset wait on the
    /// process exit with the five-minute timeout, as Claude's sign-in script does.
    private static func exitSignalledOpenCode(
        providerID: ProviderID,
        purpose: SetupHandoffPurpose
    ) -> Self? {
        guard providerID == .opencode, purpose == .setup || purpose == .reset else { return nil }
        return .exitSignalled
    }

    /// A usage read on a signed-out `agy` opens another browser sign-in, so no check runs
    /// while the Terminal sign-in is open: one runs after it exits, as for OpenCode.
    private static func exitSignalledAntigravity(
        providerID: ProviderID,
        purpose: SetupHandoffPurpose
    ) -> Self? {
        guard providerID == .antigravity, purpose == .setup || purpose == .reset else { return nil }
        return .exitSignalled
    }
}

public enum SetupSessionState: Sendable, Equatable {
    case idle
    case preparing
    case waiting(attempt: Int)
    case verifying
    case blockedByOpenHandoff
    case blockedByProviderLogin(providerID: ProviderID, active: AccountKey)
    case connected
    case failed(SetupSessionFailure)
    case cancelled
    case removing
    case removalFailed
    case removed
}

/// QA1 (2026-09-20 sign-in QA): identifies one specific `.connected` payoff. Starting any
/// later session advances the
/// coordinator generation, so a delayed UI callback carrying an older token cannot settle it.
public struct SetupConnectedPayoffToken: Sendable, Equatable {
    fileprivate let accountKey: AccountKey
    fileprivate let generation: Int
}

/// Opaque handoff prepared by the injected production boundary. The coordinator keeps
/// only account identity and the user-selected mode; AppKit/script details stay outside
/// HeadroomCore tests.
public struct PreparedSetupHandoff: Sendable, Equatable {
    public let accountKey: AccountKey
    public let mode: SetupHandoffMode
    public let purpose: SetupHandoffPurpose
    /// KTD1/KTD6 (2026-09-19 sign-in plan): which Claude script staging actually wrote, so
    /// the waiting policy reads the staged decision instead of re-deriving it from a CLI
    /// version that can change while the original Terminal is still open. Nil for providers
    /// that stage one script kind.
    public let claudeScriptKind: ClaudeSetupScriptKind?
    public init(
        accountKey: AccountKey,
        mode: SetupHandoffMode = .standard,
        purpose: SetupHandoffPurpose = .setup,
        claudeScriptKind: ClaudeSetupScriptKind? = nil
    ) {
        self.accountKey = accountKey
        self.mode = mode
        self.purpose = purpose
        self.claudeScriptKind = claudeScriptKind
    }
}

public typealias SetupPreparationResult = Result<PreparedSetupHandoff, SetupSessionFailure>
public typealias SetupOpenResult = Result<Void, SetupSessionFailure>

@MainActor
public protocol SetupRetryCancellation: AnyObject {
    func cancel()
}

@MainActor
public protocol SetupRetryScheduling: AnyObject {
    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor @Sendable () -> Void
    ) -> any SetupRetryCancellation
}

@MainActor
public final class TaskSetupRetryScheduler: SetupRetryScheduling {
    public init() {}

    public func schedule(
        after delay: Duration,
        operation: @escaping @MainActor @Sendable () -> Void
    ) -> any SetupRetryCancellation {
        TaskSetupRetryCancellation(delay: delay, operation: operation)
    }
}

@MainActor
private final class TaskSetupRetryCancellation: SetupRetryCancellation {
    private var task: Task<Void, Never>?

    init(delay: Duration, operation: @escaping @MainActor @Sendable () -> Void) {
        task = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            operation()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Account-scoped setup lifecycle. It owns async preparation, the final pre-open
/// cancellation check, bounded verification retries, provider-scoped login serialization,
/// and view-independent settlement.
@MainActor
@Observable
public final class SetupSessionCoordinator {
    private struct StartIntent {
        let purpose: SetupHandoffPurpose
        let allowsBlocked: Bool

        static func begin(_ purpose: SetupHandoffPurpose) -> Self {
            Self(purpose: purpose, allowsBlocked: false)
        }

        static func continueBlocked(_ purpose: SetupHandoffPurpose) -> Self {
            Self(purpose: purpose, allowsBlocked: true)
        }
    }

    public typealias Prepare = @MainActor @Sendable (
        ProviderAccount,
        SetupHandoffMode,
        SetupHandoffPurpose
    ) async -> SetupPreparationResult
    public typealias LegacyPrepare = @MainActor @Sendable (
        ProviderAccount,
        SetupHandoffMode
    ) async -> SetupPreparationResult
    public typealias Open = @MainActor @Sendable (PreparedSetupHandoff) async -> SetupOpenResult
    public typealias Discard = @MainActor @Sendable (PreparedSetupHandoff) async -> Void
    public typealias AccountExists = @MainActor @Sendable (AccountKey) -> Bool
    public typealias RequestRefresh = @MainActor @Sendable (AccountKey) -> Void
    public typealias ResetBoundary = @MainActor @Sendable (AccountKey) -> Void
    /// KTD9 (2026-09-19 sign-in plan): rejects results launched before the handoff's
    /// Terminal exited, without blanking a healthy snapshot the way a reset does.
    public typealias HandoffBoundary = @MainActor @Sendable (AccountKey) -> Void

    private var states: [AccountKey: SetupSessionState] = [:] {
        didSet {
            guard let onStatesChange else { return }
            let changed = Set(oldValue.keys).union(states.keys).filter { oldValue[$0] != states[$0] }
            if !changed.isEmpty { onStatesChange(Set(changed.map(\.providerID))) }
        }
    }
    /// Default-login plan U10 (KTD11): the store's hook for setup states, which gate the
    /// one-row merge. Called in the same turn as the change, with the providers it touched.
    @ObservationIgnored public var onStatesChange: (@MainActor (Set<ProviderID>) -> Void)?
    private var generations: [AccountKey: Int] = [:]
    @ObservationIgnored private var preparationTasks: [AccountKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryTasks: [AccountKey: any SetupRetryCancellation] = [:]
    @ObservationIgnored private var waitingTimeoutTasks: [AccountKey: any SetupRetryCancellation] = [:]
    @ObservationIgnored private var waitingPolicies: [AccountKey: SetupWaitingPolicy] = [:]
    @ObservationIgnored private var verificationStopLossTasks: [AccountKey: any SetupRetryCancellation] = [:]
    @ObservationIgnored private var activeLogins: [ProviderID: AccountKey] = [:]
    @ObservationIgnored private var activeHandoffs: Set<AccountKey> = []
    @ObservationIgnored private var handoffsAwaitingFinalRefresh: [AccountKey: SetupHandoffCompletion] = [:]
    @ObservationIgnored private var verificationCapabilityFailures: [AccountKey: ProviderCapabilityState] = [:]
    @ObservationIgnored private var sessionModes: [AccountKey: SetupHandoffMode] = [:]
    @ObservationIgnored private var sessionPurposes: [AccountKey: SetupHandoffPurpose] = [:]
    @ObservationIgnored private var blockedSessionPurposes: [AccountKey: SetupHandoffPurpose] = [:]

    @ObservationIgnored private let scheduler: any SetupRetryScheduling
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private let verificationStopLoss: Duration
    @ObservationIgnored private let waitingTimeout: Duration
    @ObservationIgnored private let polledCheckDelay: Duration
    @ObservationIgnored private let prepare: Prepare
    @ObservationIgnored private let open: Open
    @ObservationIgnored private let discard: Discard
    @ObservationIgnored private let accountExists: AccountExists
    @ObservationIgnored private let requestRefresh: RequestRefresh
    @ObservationIgnored private let resetBoundary: ResetBoundary
    @ObservationIgnored private let handoffBoundary: HandoffBoundary

    public init(
        scheduler: any SetupRetryScheduling = TaskSetupRetryScheduler(),
        retryDelays: [Duration] = [.seconds(3), .seconds(7), .seconds(15), .seconds(30)],
        // KTD13 (2026-09-19 polling plan): verification requests jump the per-account
        // queue, so the bound covers one in-flight probe plus the request's own worst-case
        // probe (about 80 seconds each on the PTY fallback path) with margin. It no longer
        // scales with the account count.
        verificationStopLoss: Duration = .seconds(240),
        // KTD7: the bounded wait the user asked for. It equals
        // `AccountStorage.preparedMarkerGracePeriod`, which only matters when the wrapper
        // never claims its marker — both orders converge on R11's message.
        waitingTimeout: Duration = .seconds(300),
        // KTD6: one polled check per landed result. A Claude probe costs 3–5s on the print
        // path and holds the store's global refresh flag, so the gap is comfortably longer
        // than the probe rather than a tight interval.
        polledCheckDelay: Duration = .seconds(10),
        prepare: @escaping Prepare,
        open: @escaping Open,
        discard: @escaping Discard = { _ in },
        accountExists: @escaping AccountExists,
        requestRefresh: @escaping RequestRefresh,
        resetBoundary: @escaping ResetBoundary = { _ in },
        handoffBoundary: @escaping HandoffBoundary = { _ in }
    ) {
        self.scheduler = scheduler
        self.retryDelays = retryDelays
        self.verificationStopLoss = verificationStopLoss
        self.waitingTimeout = waitingTimeout
        self.polledCheckDelay = polledCheckDelay
        self.prepare = prepare
        self.open = open
        self.discard = discard
        self.accountExists = accountExists
        self.requestRefresh = requestRefresh
        self.resetBoundary = resetBoundary
        self.handoffBoundary = handoffBoundary
    }

    /// Source compatibility for test and preview harnesses that do not need to inspect
    /// purpose during preparation. The coordinator still stamps the requested typed
    /// purpose onto the returned handoff before opening it.
    public convenience init(
        scheduler: any SetupRetryScheduling = TaskSetupRetryScheduler(),
        retryDelays: [Duration] = [.seconds(3), .seconds(7), .seconds(15), .seconds(30)],
        verificationStopLoss: Duration = .seconds(240),
        waitingTimeout: Duration = .seconds(300),
        polledCheckDelay: Duration = .seconds(10),
        prepare legacyPrepare: @escaping LegacyPrepare,
        open: @escaping Open,
        discard: @escaping Discard = { _ in },
        accountExists: @escaping AccountExists,
        requestRefresh: @escaping RequestRefresh,
        resetBoundary: @escaping ResetBoundary = { _ in },
        handoffBoundary: @escaping HandoffBoundary = { _ in }
    ) {
        self.init(
            scheduler: scheduler,
            retryDelays: retryDelays,
            verificationStopLoss: verificationStopLoss,
            waitingTimeout: waitingTimeout,
            polledCheckDelay: polledCheckDelay,
            prepare: { account, mode, purpose in
                await legacyPrepare(account, mode).map { handoff in
                    PreparedSetupHandoff(
                        accountKey: handoff.accountKey,
                        mode: handoff.mode,
                        purpose: purpose,
                        claudeScriptKind: handoff.claudeScriptKind
                    )
                }
            },
            open: open,
            discard: discard,
            accountExists: accountExists,
            requestRefresh: requestRefresh,
            resetBoundary: resetBoundary,
            handoffBoundary: handoffBoundary
        )
    }

    public func state(for key: AccountKey) -> SetupSessionState {
        states[key] ?? .idle
    }

    public func sessionMode(for key: AccountKey) -> SetupHandoffMode? {
        sessionModes[key]
    }

    public func sessionPurpose(for key: AccountKey) -> SetupHandoffPurpose? {
        sessionPurposes[key]
    }

    public func hasActiveHandoff(for key: AccountKey) -> Bool {
        activeHandoffs.contains(key)
    }

    /// Whether a fresh begin of `purpose` would start a new session for `key`, rather than
    /// being refused (a session already in progress, settled or removed) or turned into
    /// `.blockedByOpenHandoff`. `start` decides with the same rule, so a caller that records
    /// app state for the new session (the Claude interactive-launch reason) never writes
    /// over the session that is still running.
    public func acceptsNewStart(for key: AccountKey, purpose: SetupHandoffPurpose) -> Bool {
        !activeHandoffs.contains(key)
            && Self.stateAcceptsStart(state(for: key), intent: .begin(purpose))
    }

    private static func stateAcceptsStart(_ state: SetupSessionState, intent: StartIntent) -> Bool {
        switch state {
        case .connected where intent.purpose == .reset:
            true
        case .preparing, .waiting, .verifying, .connected, .removing, .removed:
            false
        case .blockedByProviderLogin where !intent.allowsBlocked:
            false
        default:
            true
        }
    }

    /// KTD6/KTD11: what this session is waiting on, so a surface can say whether Headroom
    /// is checking or waiting for the Terminal window to close. Like `hasActiveHandoff`,
    /// this reads unobserved storage — every phase change it describes coincides with a
    /// change to the observed `states` dictionary, which is what repaints the view.
    public func waitingPolicy(for key: AccountKey) -> SetupWaitingPolicy? {
        waitingPolicies[key]
    }

    /// KTD11: the completion the wrapper recorded for the handoff this session is still
    /// confirming, or nil when no final refresh is outstanding. Lets a confirming surface
    /// distinguish "sign-in reported finished" from a window that closed with no verdict.
    public func finalVerificationCompletion(for key: AccountKey) -> SetupHandoffCompletion? {
        handoffsAwaitingFinalRefresh[key]
    }

    public func begin(for account: ProviderAccount, mode: SetupHandoffMode = .standard) {
        start(account, mode: mode, intent: .begin(.setup))
    }

    public func beginWorkspaceTrust(for account: ProviderAccount) {
        start(account, mode: .standard, intent: .begin(.trust))
    }

    public func beginCursorMCPApproval(for account: ProviderAccount) {
        start(account, mode: .standard, intent: .begin(.approval))
    }

    /// Reset differs from ordinary setup only in settlement: existing live usage is
    /// ignored until the external handoff ends and a post-handoff capture arrives.
    public func beginReset(for account: ProviderAccount) {
        start(account, mode: .standard, intent: .begin(.reset))
    }

    /// A blocked request never starts on its own when the previous provider slot clears.
    /// This method is the fresh, account-specific user action required to continue.
    public func continueSetup(for account: ProviderAccount, mode: SetupHandoffMode? = nil) {
        start(
            account,
            mode: mode ?? sessionModes[account.key] ?? .standard,
            intent: .continueBlocked(blockedSessionPurposes[account.key] ?? .setup)
        )
    }

    private func start(
        _ account: ProviderAccount,
        mode: SetupHandoffMode,
        intent: StartIntent
    ) {
        let key = account.key
        // The Terminal wrapper can outlive the retry ladder. Make a second start
        // observable instead of silently ignoring it, while preserving the original
        // handoff and completion marker until the wrapper exits.
        if activeHandoffs.contains(key) {
            retryTasks.removeValue(forKey: key)?.cancel()
            states[key] = .blockedByOpenHandoff
            return
        }
        guard Self.stateAcceptsStart(state(for: key), intent: intent) else { return }
        if Self.requiresExclusiveLoginSlot(account.providerID),
           let activeLogin = activeLogins[account.providerID],
           activeLogin != key {
            states[key] = .blockedByProviderLogin(
                providerID: account.providerID,
                active: activeLogin
            )
            sessionModes[key] = mode
            blockedSessionPurposes[key] = intent.purpose
            return
        }
        if Self.requiresExclusiveLoginSlot(account.providerID) {
            activeLogins[account.providerID] = key
        }

        blockedSessionPurposes.removeValue(forKey: key)
        sessionPurposes[key] = intent.purpose
        if intent.purpose == .reset {
            resetBoundary(key)
        }
        invalidateWork(for: key, finalState: nil, releaseLoginSlot: false)
        sessionModes[key] = mode
        let generation = generations[key] ?? 0
        states[key] = .preparing
        preparationTasks[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generations[key] == generation {
                    self.preparationTasks[key] = nil
                }
            }
            let result = await self.prepare(account, mode, intent.purpose)
            guard self.isCurrent(key, generation: generation), self.accountExists(key) else {
                if case .success(let handoff) = result {
                    await self.discard(handoff)
                }
                self.finishCancelledIfCurrent(key, generation: generation)
                return
            }
            switch result {
            case .failure(let failure):
                self.fail(key, failure: failure, generation: generation)
            case .success(let handoff):
                // Reserve the external-process lifetime before crossing the opener's
                // async boundary. Cancellation during that boundary must not free the
                // provider-scoped callback slot while Terminal may still be opening.
                self.activeHandoffs.insert(key)
                let openResult = await self.open(handoff)
                if case .failure = openResult {
                    self.activeHandoffs.remove(key)
                }
                guard self.isCurrent(key, generation: generation), self.accountExists(key) else {
                    if case .failure = openResult, self.activeLogins[key.providerID] == key {
                        self.activeLogins.removeValue(forKey: key.providerID)
                    }
                    self.finishCancelledIfCurrent(key, generation: generation)
                    return
                }
                guard case .success = openResult else {
                    if case .failure(let failure) = openResult {
                        self.fail(key, failure: failure, generation: generation)
                    }
                    return
                }
                self.beginWaiting(
                    key,
                    generation: generation,
                    policy: .staged(
                        providerID: key.providerID,
                        purpose: handoff.purpose,
                        claudeScriptKind: handoff.claudeScriptKind
                    )
                )
            }
        }
    }

    /// KTD8: return an already-open handoff to `.waiting` without going through `start`,
    /// which would answer the open handoff with `.blockedByOpenHandoff` and cancel its
    /// scheduled work. The wait is re-armed in full, per R10.
    public func resumeWaiting(for key: AccountKey) {
        guard activeHandoffs.contains(key) else { return }
        switch state(for: key) {
        case .waiting, .blockedByOpenHandoff, .failed:
            break
        default:
            return
        }
        invalidateWork(for: key, finalState: nil, releaseLoginSlot: false)
        beginWaiting(
            key,
            generation: generations[key] ?? 0,
            policy: waitingPolicies[key]
                ?? .restored(providerID: key.providerID, purpose: sessionPurposes[key] ?? .setup)
        )
    }

    /// KTD6/KTD7: one entry point for every way a session starts waiting, so the timeout
    /// and the policy's own scheduling can never drift apart.
    private func beginWaiting(
        _ key: AccountKey,
        generation: Int,
        policy: SetupWaitingPolicy,
        remainingTimeout: Duration? = nil
    ) {
        waitingPolicies[key] = policy
        states[key] = .waiting(attempt: 0)
        if policy != .retryLadder {
            scheduleWaitingTimeout(
                for: key,
                generation: generation,
                after: remainingTimeout ?? waitingTimeout
            )
        }
        switch policy {
        case .retryLadder:
            scheduleRetry(for: key, generation: generation, index: 0)
        case .polled:
            schedulePolledCheck(for: key, generation: generation)
        case .exitSignalled:
            break
        }
    }

    public func cancel(_ key: AccountKey) {
        invalidateWork(for: key, finalState: .cancelled, releaseLoginSlot: true)
    }

    /// Abandons an external handoff immediately. Removing the handoff first is
    /// intentional: `invalidateWork` only releases the provider login slot when no
    /// external handoff remains associated with the account.
    public func forceCancel(_ key: AccountKey) {
        activeHandoffs.remove(key)
        invalidateWork(for: key, finalState: .cancelled, releaseLoginSlot: true)
    }

    /// Isolated composition teardown also joins preparation suspended at an injected boundary.
    public func cancelAndWait(for keys: Set<AccountKey>) async {
        let tasks = keys.compactMap { preparationTasks[$0] }
        for key in keys { forceCancel(key) }
        for task in tasks { await task.value }
    }

    public func connectedPayoffToken(for key: AccountKey) -> SetupConnectedPayoffToken? {
        guard state(for: key) == .connected else { return nil }
        return SetupConnectedPayoffToken(
            accountKey: key,
            generation: generations[key] ?? 0
        )
    }

    /// QA1: the delayed Connected chip may finish after a reset has already started. Require the
    /// generation captured when the chip appeared so that stale presentation work cannot
    /// settle the newer session.
    @discardableResult
    public func settleConnected(
        _ key: AccountKey,
        token: SetupConnectedPayoffToken
    ) -> Bool {
        guard token.accountKey == key,
              token.generation == generations[key] ?? 0,
              state(for: key) == .connected else { return false }
        states[key] = .idle
        sessionModes.removeValue(forKey: key)
        return true
    }

    /// Restore/settle the durable external-process marker independently of any view.
    /// A restored handoff keeps its provider's exclusive callback slot occupied until its
    /// wrapper exits or a live provider result proves the callback completed.
    public func restoreActiveHandoff(
        _ key: AccountKey,
        mode: SetupHandoffMode = .standard,
        purpose: SetupHandoffPurpose = .setup,
        policy: SetupWaitingPolicy? = nil,
        startedAt: Date? = nil,
        now: Date = .now
    ) {
        activeHandoffs.insert(key)
        sessionModes[key] = mode
        sessionPurposes[key] = purpose
        blockedSessionPurposes.removeValue(forKey: key)
        if purpose == .reset { resetBoundary(key) }
        if Self.requiresExclusiveLoginSlot(key.providerID) {
            activeLogins[key.providerID] = key
        }
        // KTD8: the policy is the one saved when the handoff opened. Only a handoff from a
        // build that wrote no record falls back, and then by purpose alone.
        let restoredPolicy = policy ?? .restored(providerID: key.providerID, purpose: purpose)
        waitingPolicies[key] = restoredPolicy
        guard state(for: key) == .idle else { return }
        guard restoredPolicy != .retryLadder else {
            // Unchanged for every other provider: a restored handoff resumes no ladder.
            states[key] = .waiting(attempt: 0)
            return
        }
        // R15: the timeout is measured from the handoff's original start, so a wait that
        // expired while Headroom was closed lands in the timeout state instead of being
        // granted a second full five minutes.
        let elapsed = startedAt.map { now.timeIntervalSince($0) } ?? 0
        let remaining = waitingTimeout - .seconds(elapsed)
        guard remaining > .zero else {
            states[key] = .failed(.waitingTimedOut)
            return
        }
        beginWaiting(
            key,
            generation: generations[key] ?? 0,
            policy: restoredPolicy,
            remainingTimeout: remaining
        )
    }

    public func handoffDidEnd(
        _ key: AccountKey,
        completion: SetupHandoffCompletion = .unknown,
        purpose: SetupHandoffPurpose? = nil
    ) {
        if let purpose {
            sessionPurposes[key] = purpose
            blockedSessionPurposes.removeValue(forKey: key)
        }
        activeHandoffs.remove(key)
        if activeLogins[key.providerID] == key { activeLogins.removeValue(forKey: key.providerID) }
        switch state(for: key) {
        // KTD7: the bounded wait's own failure joins `.retryExhausted` here, so a sign-in
        // that finishes after the timeout still verifies with no user action (R9).
        case .idle, .waiting, .blockedByOpenHandoff, .failed(.retryExhausted),
             .failed(.waitingTimedOut):
            // KTD9: the boundary is crossed before the refresh below, so that refresh
            // carries the new generation and only checks launched after the exit can
            // settle this verification.
            handoffBoundary(key)
            if sessionPurposes[key] == .reset { resetBoundary(key) }
            invalidateWork(for: key, finalState: nil, releaseLoginSlot: false)
            handoffsAwaitingFinalRefresh[key] = completion
            states[key] = .verifying
            scheduleVerificationStopLoss(for: key, generation: generations[key] ?? 0)
            requestRefresh(key)
        default:
            break
        }
    }

    public func markRemoving(_ key: AccountKey) {
        invalidateWork(for: key, finalState: .removing, releaseLoginSlot: true)
    }

    public func markRemovalFailed(_ key: AccountKey) {
        states[key] = .removalFailed
    }

    public func cancelRemoval(_ key: AccountKey) {
        guard state(for: key) == .removalFailed else { return }
        states[key] = .idle
    }

    public func markRemoved(_ key: AccountKey) {
        invalidateWork(for: key, finalState: .removed, releaseLoginSlot: true)
    }

    /// A stop-tracked built-in reuses its `.primary` key when tracking resumes, so the
    /// `.removed` sentinel must be cleared — otherwise every later `begin`/`receive`
    /// for the resurfaced row silently no-ops until relaunch (code-review finding).
    /// Only the removal sentinel is reset; any other state is live session lifecycle.
    public func markReinstated(_ key: AccountKey) {
        guard state(for: key) == .removed else { return }
        states[key] = .idle
    }

    public func receive(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard state(for: key) != .removed, state(for: key) != .cancelled else { return }
        if snapshot.freshness == .live {
            if (sessionPurposes[key] == .reset || blockedSessionPurposes[key] == .reset),
               handoffsAwaitingFinalRefresh[key] == nil {
                return
            }
            // Live data is a setup payoff only when this account already has setup
            // lifecycle state. Ordinary live-to-live polling must leave an idle
            // session idle, or a later reconnect can be blocked by a stale
            // `.connected` state that no view transition observes and settles.
            switch state(for: key) {
            case .idle, .connected, .removing, .removalFailed, .removed:
                return
            default:
                break
            }
            activeHandoffs.remove(key)
            invalidateWork(for: key, finalState: .connected, releaseLoginSlot: true)
            return
        }
        guard case .stale(let reason) = snapshot.freshness else { return }
        rearmPolledCheckIfWaiting(key)
        if let completion = handoffsAwaitingFinalRefresh[key] {
            let failure: SetupSessionFailure
            if let outcome = reason.providerSetupOutcome {
                if outcome == .claudeLoginRequired || outcome == .opencodeSignedOut
                    || outcome == .opencodeConsoleSignInRequired || outcome == .antigravitySignedOut {
                    // KTD10: whatever status the wrapper recorded, the account is still
                    // signed out, so the window closed before sign-in finished (R11).
                    failure = .closedBeforeSignIn
                } else if outcome == .codexAuthAbsent {
                    failure = .provider(
                        completion == .succeeded
                            ? .codexStorageMismatch
                            : .codexCallbackIncomplete
                    )
                } else {
                    failure = .provider(outcome)
                }
            } else {
                failure = .retryExhausted
            }
            invalidateWork(for: key, finalState: .failed(failure), releaseLoginSlot: true)
            return
        }
        guard let outcome = reason.providerSetupOutcome else { return }
        switch outcome {
        case .codexPermissionDenied, .codexMalformedAuth, .codexStorageMismatch,
             .codexCallbackIncomplete, .codexCLIMissing, .claudeCLIMissing,
             .grokCLIMissing, .grokPermissionDenied, .grokUnsafePermissions,
             .grokMalformedAuth, .cursorCLIMissing, .copilotCLIMissing, .opencodeCLIMissing,
             .antigravityCLIMissing:
            invalidateWork(for: key, finalState: .failed(.provider(outcome)), releaseLoginSlot: true)
        default:
            break
        }
    }

    /// Provider capability is shared installation state, not an account snapshot.
    /// Only sessions already awaiting their final refresh are affected.
    public func receiveCapabilityFailure(
        _ state: ProviderCapabilityState,
        for providerID: ProviderID
    ) {
        let keys = handoffsAwaitingFinalRefresh.keys.filter { $0.providerID == providerID }
        switch state {
        case .confirmedAbsent:
            for key in keys {
                invalidateWork(
                    for: key,
                    finalState: .failed(.providerCapability(.confirmedAbsent)),
                    releaseLoginSlot: true
                )
            }
            rearmPolledChecks(for: providerID)
        case .inconclusive:
            for key in keys where self.state(for: key) == .verifying {
                verificationCapabilityFailures[key] = state
            }
            rearmPolledChecks(for: providerID)
        case .unknown, .discovering, .available:
            break
        }
    }

    /// KTD6: a capability failure short-circuits `receive`, so without this the polled chain
    /// would stop on one inconclusive locator result and the session would sit unchecked
    /// until its timeout.
    private func rearmPolledChecks(for providerID: ProviderID) {
        for key in waitingPolicies.keys where key.providerID == providerID {
            rearmPolledCheckIfWaiting(key)
        }
    }

    private func scheduleRetry(for key: AccountKey, generation: Int, index: Int) {
        retryTasks[key]?.cancel()
        guard index < retryDelays.count else {
            fail(key, failure: .retryExhausted, generation: generation)
            return
        }
        retryTasks[key] = scheduler.schedule(after: retryDelays[index]) { [weak self] in
            guard let self,
                  self.isCurrent(key, generation: generation),
                  self.accountExists(key),
                  self.state(for: key) != .removed
            else { return }
            self.states[key] = .verifying
            self.requestRefresh(key)
            guard self.isCurrent(key, generation: generation) else { return }
            self.states[key] = .waiting(attempt: index + 1)
            self.scheduleRetry(for: key, generation: generation, index: index + 1)
        }
    }

    /// KTD6: the polled chain is one check at a time. The check itself schedules nothing —
    /// the next one is armed when its result lands, from `receive` or from
    /// `receiveCapabilityFailure` — so a slow probe can never stack checks behind itself.
    private func schedulePolledCheck(for key: AccountKey, generation: Int) {
        retryTasks.removeValue(forKey: key)?.cancel()
        retryTasks[key] = scheduler.schedule(after: polledCheckDelay) { [weak self] in
            guard let self,
                  self.isCurrent(key, generation: generation),
                  self.accountExists(key),
                  case .waiting = self.state(for: key)
            else { return }
            self.retryTasks.removeValue(forKey: key)
            self.requestRefresh(key)
        }
    }

    /// KTD6: re-arm the polled chain from a landed result. Cancel-and-replace, so two
    /// results arriving before the next check fires still leave exactly one armed.
    private func rearmPolledCheckIfWaiting(_ key: AccountKey) {
        guard waitingPolicies[key] == .polled, case .waiting = state(for: key) else { return }
        schedulePolledCheck(for: key, generation: generations[key] ?? 0)
    }

    /// KTD7: the bounded wait. It is guarded by its generation and by `.waiting`, so a
    /// Terminal exit that lands first leaves it inert rather than failing a verification
    /// already in progress. Firing leaves the handoff open: the window is still there.
    private func scheduleWaitingTimeout(
        for key: AccountKey,
        generation: Int,
        after delay: Duration
    ) {
        waitingTimeoutTasks[key]?.cancel()
        waitingTimeoutTasks[key] = scheduler.schedule(after: delay) { [weak self] in
            guard let self,
                  self.isCurrent(key, generation: generation),
                  self.accountExists(key),
                  case .waiting = self.state(for: key)
            else { return }
            self.fail(key, failure: .waitingTimedOut, generation: generation)
        }
    }

    private func scheduleVerificationStopLoss(for key: AccountKey, generation: Int) {
        verificationStopLossTasks[key]?.cancel()
        verificationStopLossTasks[key] = scheduler.schedule(after: verificationStopLoss) { [weak self] in
            guard let self,
                  self.isCurrent(key, generation: generation),
                  self.accountExists(key),
                  self.state(for: key) == .verifying,
                  self.handoffsAwaitingFinalRefresh[key] != nil
            else { return }
            let failure = self.verificationCapabilityFailures[key]
                .map(SetupSessionFailure.providerCapability)
                ?? .retryExhausted
            self.fail(key, failure: failure, generation: generation)
        }
    }

    private func fail(_ key: AccountKey, failure: SetupSessionFailure, generation: Int) {
        guard isCurrent(key, generation: generation) else { return }
        invalidateWork(for: key, finalState: .failed(failure), releaseLoginSlot: true)
    }

    private func finishCancelledIfCurrent(_ key: AccountKey, generation: Int) {
        guard isCurrent(key, generation: generation) else { return }
        invalidateWork(for: key, finalState: .cancelled, releaseLoginSlot: true)
    }

    private func isCurrent(_ key: AccountKey, generation: Int) -> Bool {
        generations[key] == generation && !Task.isCancelled
    }

    private func invalidateWork(
        for key: AccountKey,
        finalState: SetupSessionState?,
        releaseLoginSlot: Bool
    ) {
        generations[key, default: 0] += 1
        preparationTasks.removeValue(forKey: key)?.cancel()
        retryTasks.removeValue(forKey: key)?.cancel()
        waitingTimeoutTasks.removeValue(forKey: key)?.cancel()
        verificationStopLossTasks.removeValue(forKey: key)?.cancel()
        handoffsAwaitingFinalRefresh.removeValue(forKey: key)
        verificationCapabilityFailures.removeValue(forKey: key)
        if let finalState {
            switch finalState {
            case .connected, .cancelled, .removing, .removed:
                sessionModes.removeValue(forKey: key)
                sessionPurposes.removeValue(forKey: key)
                blockedSessionPurposes.removeValue(forKey: key)
                waitingPolicies.removeValue(forKey: key)
            case .failed where !activeHandoffs.contains(key):
                // A wrapper that is still open can rescue a retry failure later. Once
                // no external handoff remains, a terminal failure must disarm reset so
                // ordinary future polling can recover instead of being suppressed.
                // KTD8: the policy goes with it — resume has nothing left to resume.
                sessionPurposes.removeValue(forKey: key)
                blockedSessionPurposes.removeValue(forKey: key)
                waitingPolicies.removeValue(forKey: key)
            default:
                break
            }
        }
        if releaseLoginSlot,
           activeLogins[key.providerID] == key,
           !activeHandoffs.contains(key) {
            activeLogins.removeValue(forKey: key.providerID)
        }
        if let finalState { states[key] = finalState }
    }

    /// Grok's production loopback login binds an ephemeral port and device auth binds no
    /// callback listener (verified 2026-08-01), and OpenCode's device login binds none either
    /// (KTD11, U12 (b), checked against v2.2.5 source and live), so only Codex currently needs an exclusive
    /// provider slot. The keyed representation is ready for any future fixed-port CLI.
    private static func requiresExclusiveLoginSlot(_ providerID: ProviderID) -> Bool {
        providerID == .codex
    }
}
