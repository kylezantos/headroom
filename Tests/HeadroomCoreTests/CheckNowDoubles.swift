import Foundation

@testable import HeadroomCore

// U6 doubles. Kept out of Mocks.swift per the parity plan's stream rule.

/// The phone's App Group state, in memory.
final class MemoryCheckNowStateStore: CheckNowStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: CheckNowRequestState?

    func load() -> CheckNowRequestState? { lock.withLock { state } }
    func save(_ state: CheckNowRequestState?) { lock.withLock { self.state = state } }
}

/// A KVS double that counts `synchronize()` and logs writes, so phone tests can prove
/// "writes the request, then synchronizes" and "writes nothing".
final class CheckNowKeyValueStore: iCloudKeyValueSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var sets: [String] = []
    private var removes: [String] = []
    private var syncs = 0

    var setKeys: [String] { lock.withLock { sets } }
    var removedKeys: [String] { lock.withLock { removes } }
    var synchronizeCount: Int { lock.withLock { syncs } }

    func data(forKey key: String) -> Data? { lock.withLock { storage[key] } }

    @discardableResult func set(_ data: Data, forKey key: String) -> Bool {
        lock.withLock {
            storage[key] = data
            sets.append(key)
            return true
        }
    }

    @discardableResult func synchronize() -> Bool {
        lock.withLock { syncs += 1 }
        return true
    }

    func removeValue(forKey key: String) {
        lock.withLock {
            storage[key] = nil
            removes.append(key)
        }
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.withLock { storage.keys.filter { $0.hasPrefix(prefix) }.sorted() }
    }

    /// Another device's write (a phone request, the Mac's receipt) without logging it.
    func seed(_ key: String, _ data: Data?) {
        lock.withLock { storage[key] = data }
    }
}

/// A counter of request IDs, so tests name the IDs a client mints.
final class RequestIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 1

    func make() -> String {
        lock.withLock {
            defer { next += 1 }
            return String(format: "00000000-0000-4000-8000-%012d", next)
        }
    }
}

/// A controllable check-now host: full refreshes hold until the test completes them, joins
/// await the one in flight (the store's KTD14.4 guard), and each publish writes a manifest
/// marker into the KVS double so tests can see the flush land before the receipt.
@MainActor
final class FakeCheckNowHost: CheckNowHost {
    var syncEnabled = true
    var progress: CheckNowRunProgress?
    var publishFails = false
    var nextGeneration: Int64 = 10
    private(set) var refreshes = 0
    private(set) var startedAt: Date?
    private(set) var completedAt: Date?
    private(set) var publishes: [[CompanionAnsweredRequest]] = []
    private(set) var history: [CompanionAnsweredRequest] = []
    private var observer: (@MainActor () -> Void)?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let store: CheckNowKeyValueStore
    private let clock: ManualClock

    init(store: CheckNowKeyValueStore, clock: ManualClock) {
        self.store = store
        self.clock = clock
    }

    var checkNowSyncEnabled: Bool { syncEnabled }
    var checkNowFullRefreshStartedAt: Date? { startedAt }
    var checkNowLastFullRefreshCompletedAt: Date? { completedAt }
    var checkNowProgress: CheckNowRunProgress? { progress }

    func checkNowRunFullRefresh() async {
        if startedAt == nil {
            startedAt = clock.now
            refreshes += 1
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// A Mac-started refresh (launch, popover) that a request may join.
    func beginMacRefresh() -> Task<Void, Never> {
        startedAt = clock.now
        refreshes += 1
        return Task { await self.checkNowRunFullRefresh() }
    }

    var waitingCount: Int { waiters.count }

    func completeRefresh() {
        startedAt = nil
        completedAt = clock.now
        progress = nil
        let resumed = waiters
        waiters = []
        for waiter in resumed { waiter.resume() }
    }

    func report(total: Int, completed: Int, landed: CompanionLastLanded?) {
        progress = CheckNowRunProgress(total: total, completed: completed, lastLanded: landed)
        observer?()
    }

    func checkNowObserveProgress(_ observer: (@MainActor () -> Void)?) {
        self.observer = observer
    }

    func checkNowPublish(answering: (Int64) -> [CompanionAnsweredRequest]) async -> Int64? {
        let generation = nextGeneration
        nextGeneration += 1
        let answers = answering(generation)
        guard !publishFails else { return nil }
        publishes.append(answers)
        store.set(Data("generation \(generation)".utf8), forKey: CompanionSyncKeys.manifest)
        return generation
    }

    func checkNowSetAnsweredHistory(_ answers: [CompanionAnsweredRequest]) {
        history = answers
    }
}

/// A spend provider whose fetch a test can hold open.
final class GatedSpendProvider: APISpendProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Spend"
    let gate = FetchGate()

    init(id: ProviderID) { self.id = id }

    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        await gate.enter()
        return .stale(providerID: id, displayName: displayName, periodLabel: period.label, reason: .transient("offline"))
    }
}
