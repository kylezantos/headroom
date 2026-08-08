import Foundation
import Observation

public enum SetupHandoffMode: Sendable, Equatable {
    case standard
    case deviceCode
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
    case stagingFailed
    case terminalRejected
    case pasteboardFailed
    case retryExhausted
    case provider(ProviderSetupOutcome)
    case providerCapability(ProviderCapabilityState)
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

/// Opaque handoff prepared by the injected production boundary. The coordinator keeps
/// only account identity and the user-selected mode; AppKit/script details stay outside
/// HeadroomCore tests.
public struct PreparedSetupHandoff: Sendable, Equatable {
    public let accountKey: AccountKey
    public let mode: SetupHandoffMode
    public init(accountKey: AccountKey, mode: SetupHandoffMode = .standard) {
        self.accountKey = accountKey
        self.mode = mode
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
    public typealias Prepare = @MainActor @Sendable (ProviderAccount, SetupHandoffMode) async -> SetupPreparationResult
    public typealias Open = @MainActor @Sendable (PreparedSetupHandoff) async -> SetupOpenResult
    public typealias Discard = @MainActor @Sendable (PreparedSetupHandoff) async -> Void
    public typealias AccountExists = @MainActor @Sendable (AccountKey) -> Bool
    public typealias RequestRefresh = @MainActor @Sendable (AccountKey) -> Void

    private var states: [AccountKey: SetupSessionState] = [:]
    private var generations: [AccountKey: Int] = [:]
    @ObservationIgnored private var preparationTasks: [AccountKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryTasks: [AccountKey: any SetupRetryCancellation] = [:]
    @ObservationIgnored private var verificationStopLossTasks: [AccountKey: any SetupRetryCancellation] = [:]
    @ObservationIgnored private var activeLogins: [ProviderID: AccountKey] = [:]
    @ObservationIgnored private var activeHandoffs: Set<AccountKey> = []
    @ObservationIgnored private var handoffsAwaitingFinalRefresh: [AccountKey: SetupHandoffCompletion] = [:]
    @ObservationIgnored private var verificationCapabilityFailures: [AccountKey: ProviderCapabilityState] = [:]
    @ObservationIgnored private var sessionModes: [AccountKey: SetupHandoffMode] = [:]

    @ObservationIgnored private let scheduler: any SetupRetryScheduling
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private let verificationStopLoss: Duration
    @ObservationIgnored private let prepare: Prepare
    @ObservationIgnored private let open: Open
    @ObservationIgnored private let discard: Discard
    @ObservationIgnored private let accountExists: AccountExists
    @ObservationIgnored private let requestRefresh: RequestRefresh

    public init(
        scheduler: any SetupRetryScheduling = TaskSetupRetryScheduler(),
        retryDelays: [Duration] = [.seconds(3), .seconds(7), .seconds(15), .seconds(30)],
        // Five serial Claude probes at the 40-second worst-case path, plus one probe
        // of margin. This intentionally exceeds the short retry ladder.
        verificationStopLoss: Duration = .seconds(240),
        prepare: @escaping Prepare,
        open: @escaping Open,
        discard: @escaping Discard = { _ in },
        accountExists: @escaping AccountExists,
        requestRefresh: @escaping RequestRefresh
    ) {
        self.scheduler = scheduler
        self.retryDelays = retryDelays
        self.verificationStopLoss = verificationStopLoss
        self.prepare = prepare
        self.open = open
        self.discard = discard
        self.accountExists = accountExists
        self.requestRefresh = requestRefresh
    }

    public func state(for key: AccountKey) -> SetupSessionState {
        states[key] ?? .idle
    }

    public func sessionMode(for key: AccountKey) -> SetupHandoffMode? {
        sessionModes[key]
    }

    public func hasActiveHandoff(for key: AccountKey) -> Bool {
        activeHandoffs.contains(key)
    }

    public func begin(for account: ProviderAccount, mode: SetupHandoffMode = .standard) {
        start(account, mode: mode, allowBlocked: false)
    }

    /// A blocked request never starts on its own when the previous provider slot clears.
    /// This method is the fresh, account-specific user action required to continue.
    public func continueSetup(for account: ProviderAccount, mode: SetupHandoffMode? = nil) {
        start(account, mode: mode ?? sessionModes[account.key] ?? .standard, allowBlocked: true)
    }

    private func start(_ account: ProviderAccount, mode: SetupHandoffMode, allowBlocked: Bool) {
        let key = account.key
        // The Terminal wrapper can outlive the retry ladder. Make a second start
        // observable instead of silently ignoring it, while preserving the original
        // handoff and completion marker until the wrapper exits.
        if activeHandoffs.contains(key) {
            retryTasks.removeValue(forKey: key)?.cancel()
            states[key] = .blockedByOpenHandoff
            return
        }
        switch state(for: key) {
        case .preparing, .waiting, .verifying, .connected, .removing, .removed:
            return
        case .blockedByProviderLogin where !allowBlocked:
            return
        default:
            break
        }
        if Self.requiresExclusiveLoginSlot(account.providerID),
           let activeLogin = activeLogins[account.providerID],
           activeLogin != key {
            states[key] = .blockedByProviderLogin(
                providerID: account.providerID,
                active: activeLogin
            )
            sessionModes[key] = mode
            return
        }
        if Self.requiresExclusiveLoginSlot(account.providerID) {
            activeLogins[account.providerID] = key
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
            let result = await self.prepare(account, mode)
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
                self.states[key] = .waiting(attempt: 0)
                self.scheduleRetry(for: key, generation: generation, index: 0)
            }
        }
    }

    public func cancel(_ key: AccountKey) {
        invalidateWork(for: key, finalState: .cancelled, releaseLoginSlot: true)
    }

    public func settleConnected(_ key: AccountKey) {
        guard state(for: key) == .connected else { return }
        states[key] = .idle
        sessionModes.removeValue(forKey: key)
    }

    /// Restore/settle the durable external-process marker independently of any view.
    /// A restored handoff keeps its provider's exclusive callback slot occupied until its
    /// wrapper exits or a live provider result proves the callback completed.
    public func restoreActiveHandoff(
        _ key: AccountKey,
        mode: SetupHandoffMode = .standard
    ) {
        activeHandoffs.insert(key)
        sessionModes[key] = mode
        if Self.requiresExclusiveLoginSlot(key.providerID) {
            activeLogins[key.providerID] = key
        }
        if state(for: key) == .idle { states[key] = .waiting(attempt: 0) }
    }

    public func handoffDidEnd(
        _ key: AccountKey,
        completion: SetupHandoffCompletion = .unknown
    ) {
        activeHandoffs.remove(key)
        if activeLogins[key.providerID] == key { activeLogins.removeValue(forKey: key.providerID) }
        switch state(for: key) {
        case .idle, .waiting, .blockedByOpenHandoff, .failed(.retryExhausted):
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

    public func receive(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard state(for: key) != .removed else { return }
        if snapshot.freshness == .live {
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
        if let completion = handoffsAwaitingFinalRefresh[key] {
            let failure: SetupSessionFailure
            if let outcome = reason.providerSetupOutcome {
                if outcome == .codexAuthAbsent {
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
             .grokMalformedAuth, .cursorCLIMissing:
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
        case .inconclusive:
            for key in keys where self.state(for: key) == .verifying {
                verificationCapabilityFailures[key] = state
            }
        case .unknown, .discovering, .available:
            break
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
        verificationStopLossTasks.removeValue(forKey: key)?.cancel()
        handoffsAwaitingFinalRefresh.removeValue(forKey: key)
        verificationCapabilityFailures.removeValue(forKey: key)
        if let finalState {
            switch finalState {
            case .connected, .cancelled, .removing, .removed:
                sessionModes.removeValue(forKey: key)
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
    /// callback listener (verified 2026-08-01), so only Codex currently needs an exclusive
    /// provider slot. The keyed representation is ready for any future fixed-port CLI.
    private static func requiresExclusiveLoginSlot(_ providerID: ProviderID) -> Bool {
        providerID == .codex
    }
}
