import Foundation
import HeadroomCore

/// KTD16: fixed captures advance this clock only at real request checkpoints.
final class LoadingDemoClock: @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: Date?
    init(pinned: Date? = nil) { self.pinned = pinned }
    func now() -> Date { lock.withLock { pinned ?? Date() } }
    func set(_ date: Date?) { lock.withLock { pinned = date } }
}

/// A held real fetch, not a forged store phase. Cancellation always releases its waiter.
actor LoadingDemoCheckpoint {
    private var held = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private(set) var entries = 0
    var waiterCount: Int { waiters.count }
    func hold() { held = true }
    func release() {
        held = false
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
    func enter() async {
        entries += 1
        guard held else { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || !held { continuation.resume() }
                else { waiters[id] = continuation }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: UUID) { waiters.removeValue(forKey: id)?.resume() }
}

actor LoadingDemoSources {
    private var signedOut: Set<AccountKey>
    private var completed: Set<AccountKey> = []
    private let pending: Set<AccountKey>
    private var probes: [AccountKey: LoadingDemoCheckpoint] = [:]
    private var spends: [ProviderID: LoadingDemoCheckpoint] = [:]
    private var delays: [UUID: Task<Void, Error>] = [:]
    private var stopped = false
    var pendingDelayCount: Int { delays.count }
    init(signedOut: Set<AccountKey> = [], pending: Set<AccountKey> = []) {
        self.signedOut = signedOut
        self.pending = pending
    }
    func beginHandoff(_ key: AccountKey) { signedOut.insert(key); completed.remove(key) }
    func completeHandoff(_ key: AccountKey) { signedOut.remove(key); completed.insert(key) }
    func checkpoint(for key: AccountKey) -> LoadingDemoCheckpoint {
        if let checkpoint = probes[key] { return checkpoint }
        let checkpoint = LoadingDemoCheckpoint()
        probes[key] = checkpoint
        return checkpoint
    }
    func spendCheckpoint(for id: ProviderID) -> LoadingDemoCheckpoint {
        if let checkpoint = spends[id] { return checkpoint }
        let checkpoint = LoadingDemoCheckpoint()
        spends[id] = checkpoint
        return checkpoint
    }
    func snapshot(for key: AccountKey, at date: Date, needsSetup: Bool) -> UsageSnapshot {
        if signedOut.contains(key) || (needsSetup && !completed.contains(key)) {
            return .stale(for: key.providerID, reason: .notLoggedIn(UsageStore.finishSignInMessage))
        }
        if pending.contains(key) { return .pending(for: key.providerID) }
        return DemoFixture.loadingSnapshot(for: key.providerID, at: date)
    }
    func sleep(for duration: Duration) async -> Bool {
        guard !stopped, !Task.isCancelled else { return false }
        guard duration > .zero else { return true }
        let id = UUID()
        let task = Task { try await Task.sleep(for: duration) }
        delays[id] = task
        defer { delays[id] = nil }
        do { try await task.value; return !stopped && !Task.isCancelled }
        catch { return false }
    }
    func releaseAll() async {
        stopped = true
        let tasks = Array(delays.values)
        for task in tasks { task.cancel() }
        for checkpoint in probes.values { await checkpoint.release() }
        for checkpoint in spends.values { await checkpoint.release() }
        for task in tasks { _ = try? await task.value }
    }
    func waiterCount() async -> Int {
        var count = 0
        for checkpoint in probes.values { count += await checkpoint.waiterCount }
        for checkpoint in spends.values { count += await checkpoint.waiterCount }
        return count
    }
}

private struct LoadingDemoUsageProvider: UsageProvider {
    let id: ProviderID
    let accountID: AccountID
    var displayName: String { id.displayName }
    var pollingLane: ProviderPollingLane { id == .codex ? .concurrent : .serial("demo-\(id.raw)") }
    var accountCapacity: Int { id == .cursor || id == .copilot ? 1 : AccountRegistry.testedEnvelope }
    let sources: LoadingDemoSources
    let clock: LoadingDemoClock
    let delay: Duration
    let needsSetup: Bool
    func fetchSnapshot() async -> UsageSnapshot {
        let checkpoint = await sources.checkpoint(for: accountKey)
        await checkpoint.enter()
        guard await sources.sleep(for: delay) else { return .stale(for: id, reason: .transient("Demo cancelled")) }
        return await sources.snapshot(for: accountKey, at: clock.now(), needsSetup: needsSetup)
    }
}

private struct LoadingDemoSpendProvider: APISpendProvider {
    let id: ProviderID
    var displayName: String { id == .claude ? "Anthropic API" : "OpenAI API" }
    let sources: LoadingDemoSources
    let clock: LoadingDemoClock
    let delay: Duration
    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        await sources.spendCheckpoint(for: id).enter()
        guard await sources.sleep(for: delay) else {
            return .stale(providerID: id, displayName: displayName, periodLabel: period.label, reason: .transient("Demo cancelled"))
        }
        return APISpendSnapshot(providerID: id, displayName: displayName, amount: id == .claude ? 142.67 : 58.90,
                                currency: "usd", periodLabel: period.label, capturedAt: clock.now(), freshness: .live)
    }
}

/// Owned by App.init or a focused render/test composition, never by App.body.
@MainActor
final class LoadingDemoController {
    let clock: LoadingDemoClock
    let sources: LoadingDemoSources
    let preparation = LoadingDemoCheckpoint()
    let accountStorage = DemoAccountStorage()
    let loading: Bool
    let automaticCompletion: Bool
    private let preparationDelay: Duration
    private let waitingDelay: Duration
    private let probeDelay: Duration?
    private let spendDelay: Duration
    private weak var store: UsageStore?
    private(set) var coordinator: SetupSessionCoordinator?
    private var keys: Set<AccountKey> = []
    private var driverTasks: [AccountKey: Task<Void, Never>] = [:]
    private var driverIDs: [AccountKey: UUID] = [:]
    private var cancelledDrivers: [Task<Void, Never>] = []
    private var launchTask: Task<Void, Never>?
    private var workTasks: [UUID: Task<Void, Never>] = [:]
    private(set) var cancellationKeys: [AccountKey] = []
    private(set) var preparedKeys: [AccountKey] = []
    private(set) var openedKeys: [AccountKey] = []
    private(set) var discardedKeys: [AccountKey] = []
    var ownedTaskCount: Int { driverTasks.count + cancelledDrivers.count + workTasks.count + (launchTask == nil ? 0 : 1) }

    init(loading: Bool = true, clock: LoadingDemoClock = LoadingDemoClock(), automaticCompletion: Bool = true,
         preparationDelay: Duration = .seconds(1.2), waitingDelay: Duration = .seconds(4),
         probeDelay: Duration? = nil, spendDelay: Duration = .seconds(3)) {
        self.loading = loading
        self.clock = clock
        self.automaticCompletion = automaticCompletion
        self.preparationDelay = preparationDelay
        self.waitingDelay = waitingDelay
        self.probeDelay = probeDelay
        self.spendDelay = spendDelay
        sources = LoadingDemoSources(
            signedOut: loading ? [AccountKey(providerID: .codex, accountID: .primary)] : [],
            pending: loading ? [AccountKey(providerID: .claude, accountID: AccountID("loading-pending"))] : [])
    }

    func provider(for account: ProviderAccount, needsSetup: Bool = false) -> any UsageProvider {
        keys.insert(account.key)
        let delay = probeDelay ?? (loading ? .seconds(account.providerID == .claude ? 2.4 : account.providerID == .grok ? 3.2 : 1.5) : .zero)
        return LoadingDemoUsageProvider(id: account.providerID, accountID: account.id, sources: sources,
                                        clock: clock, delay: delay, needsSetup: needsSetup)
    }

    func spendProviders() -> [any APISpendProvider] {
        [ProviderID.claude, .codex].map { LoadingDemoSpendProvider(id: $0, sources: sources, clock: clock, delay: spendDelay) }
    }

    func configure(store: UsageStore) {
        precondition(coordinator == nil, "A demo controller owns one composition")
        self.store = store
        keys.formUnion(store.providerOrder.flatMap { store.accounts(for: $0).map(\.key) })
        let coordinator = SetupSessionCoordinator(
            prepare: { [weak self] account, mode, purpose in
                guard let self else { return .failure(.stagingFailed) }
                self.keys.insert(account.key)
                await self.sources.beginHandoff(account.key)
                await self.preparation.enter()
                do { try await Task.sleep(for: self.preparationDelay) } catch { return .failure(.stagingFailed) }
                guard !Task.isCancelled else { return .failure(.stagingFailed) }
                self.preparedKeys.append(account.key)
                return .success(PreparedSetupHandoff(accountKey: account.key, mode: mode,
                    purpose: purpose, claudeScriptKind: account.providerID == .claude ? .signIn : nil))
            },
            open: { [weak self] handoff in
                guard let self else { return .failure(.terminalRejected) }
                self.openedKeys.append(handoff.accountKey)
                self.accountStorage.beginHandoff(handoff.accountKey)
                if self.automaticCompletion {
                    if let previous = self.driverTasks[handoff.accountKey] {
                        previous.cancel()
                        self.cancelledDrivers.append(previous)
                    }
                    let id = UUID()
                    self.driverIDs[handoff.accountKey] = id
                    self.driverTasks[handoff.accountKey] = Task { [weak self] in
                        guard let self else { return }
                        defer {
                            if self.driverIDs[handoff.accountKey] == id {
                                self.driverTasks[handoff.accountKey] = nil
                                self.driverIDs[handoff.accountKey] = nil
                            }
                        }
                        do { try await Task.sleep(for: self.waitingDelay) } catch { return }
                        await self.completeHandoff(handoff.accountKey)
                    }
                }
                return .success(())
            },
            discard: { [weak self] handoff in
                self?.discardedKeys.append(handoff.accountKey)
                self?.accountStorage.endHandoff(handoff.accountKey)
            },
            accountExists: { [weak store] key in store?.accounts(for: key.providerID).contains(where: { $0.key == key }) == true },
            requestRefresh: { [weak store] key in store?.refreshAccountNow(key, origin: .setupCheck) },
            resetBoundary: { [weak store] key in store?.invalidateUsageForAccountReset(key) },
            handoffBoundary: { [weak store] key in store?.invalidateUsageForHandoffBoundary(key) })
        self.coordinator = coordinator
        SetupSessions.configureDemo(store: store, coordinator: coordinator, now: clock.now, cancellationCleanup: { [weak self] account, prepared in
            precondition(prepared == nil, "Inert demos never stage scripts")
            self?.cancellationKeys.append(account.key)
            self?.accountStorage.endHandoff(account.key)
            if let self, let task = self.driverTasks.removeValue(forKey: account.key) {
                task.cancel()
                self.driverIDs[account.key] = nil
                self.cancelledDrivers.append(task)
            }
        })
    }

    func completeHandoff(_ key: AccountKey) async {
        guard coordinator?.hasActiveHandoff(for: key) == true else { return }
        await sources.completeHandoff(key)
        guard coordinator?.hasActiveHandoff(for: key) == true else { return }
        coordinator?.handoffDidEnd(key, completion: .succeeded)
        accountStorage.endHandoff(key)
    }

    /// Finite native walkthrough; subsequent Refresh/Check Now use the same delayed sources.
    func start() {
        guard loading, launchTask == nil, let store else { return }
        launchTask = Task { [weak self, weak store] in
            guard let self, let store else { return }
            defer { self.launchTask = nil }
            await store.refreshAll()
            guard !Task.isCancelled,
                  let account = store.primaryAccount(for: .codex) else { return }
            SetupSessions.openSetup(for: account, onRetry: {})
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if let work = store.accounts(for: .claude).first(where: { $0.id == AccountID("loading-work") }) {
                store.refreshAccountNow(work.key, origin: .accountAction)
            }
        }
    }

    @discardableResult func refresh(spendOnly: Bool = false) -> UUID {
        let id = UUID()
        workTasks[id] = Task { [weak self, weak store] in
            defer { self?.workTasks[id] = nil }
            if spendOnly { await store?.refreshAPISpendOnly() }
            else { await store?.refreshAll() }
        }
        return id
    }

    func shutdown() async {
        let tasks = Array(driverTasks.values) + cancelledDrivers + Array(workTasks.values) + [launchTask].compactMap { $0 }
        for task in tasks { task.cancel() }
        if let coordinator {
            await coordinator.cancelAndWait(for: keys)
            SetupSessions.tearDownDemo(coordinator: coordinator, keys: keys)
        }
        for key in keys { accountStorage.endHandoff(key) }
        await preparation.release()
        await sources.releaseAll()
        for task in tasks { await task.value }
        await store?.waitForAccountProbesToFinish()
        driverTasks.removeAll()
        driverIDs.removeAll()
        cancelledDrivers.removeAll()
        workTasks.removeAll()
        launchTask = nil
        coordinator = nil
        store = nil
    }
}
