import Foundation

@testable import HeadroomCore

/// U4 test doubles for the account-scope, cache-storage and coordination seams. Their own
/// file per the parity plan's stream rule; nothing here touches iCloud or the file system.

/// A switchable local identity. Equality is the identity's own (here, its name), standing
/// in for `isEqual` on an unarchived opaque token; nil models "no iCloud account".
final class FakeAccountScope: CompanionAccountScopeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    private(set) var checks = 0

    init(_ identity: String?) { current = identity }

    var identity: String? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func check(against archive: Data?) -> CompanionScopeCheck {
        lock.withLock {
            checks += 1
            guard let current else { return .unavailable }
            let token = Data(current.utf8)
            return archive == token ? .unchanged : .changed(archive: token)
        }
    }
}

/// In-memory App Group files with a write log, so tests can prove which file a commit touched.
final class MemoryCacheStorage: CompanionCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [CompanionCacheFile: Data] = [:]
    private(set) var writes: [CompanionCacheFile] = []
    private(set) var removals: [CompanionCacheFile] = []

    func read(_ file: CompanionCacheFile) throws -> Data? { lock.withLock { files[file] } }

    func write(_ data: Data, to file: CompanionCacheFile) throws {
        lock.withLock {
            files[file] = data
            writes.append(file)
        }
    }

    func remove(_ file: CompanionCacheFile) throws {
        lock.withLock {
            files[file] = nil
            removals.append(file)
        }
    }

    subscript(file: CompanionCacheFile) -> Data? {
        get { lock.withLock { files[file] } }
        set { lock.withLock { files[file] = newValue } }
    }

    func resetLog() {
        lock.withLock {
            writes = []
            removals = []
        }
    }

    var sidecar: CompanionScopeSidecar? {
        self[.sidecar].flatMap { try? JSONDecoder().decode(CompanionScopeSidecar.self, from: $0) }
    }
}

/// The App Group anchor every simulated process coordinates on.
final class SharedAnchor: @unchecked Sendable {
    let lock = NSLock()
}

/// One process's coordinator. Optionally parks its Nth entry *before* taking the anchor,
/// signalling `arrived` and waiting on `gate`: the barrier the race scenarios need.
final class BarrierCoordinator: CompanionCacheCoordinating, @unchecked Sendable {
    private let anchor: SharedAnchor
    private let counter = NSLock()
    private var entries = 0
    private let gatedEntry: Int?
    let arrived = DispatchSemaphore(value: 0)
    let gate = DispatchSemaphore(value: 0)
    var fails = false

    init(anchor: SharedAnchor, gatedEntry: Int? = nil) {
        self.anchor = anchor
        self.gatedEntry = gatedEntry
    }

    func coordinate<T>(_ body: () -> T) -> T? {
        let entry: Int = counter.withLock {
            entries += 1
            return entries
        }
        if entry == gatedEntry {
            arrived.signal()
            gate.wait()
        }
        guard !fails else { return nil }
        anchor.lock.lock()
        defer { anchor.lock.unlock() }
        return body()
    }
}

/// A KVS double that counts every read and write, for demo isolation and scope-first checks.
final class SpyKeyValueStore: iCloudKeyValueSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private(set) var reads = 0
    private(set) var mutations = 0

    func data(forKey key: String) -> Data? {
        lock.withLock {
            reads += 1
            return storage[key]
        }
    }

    @discardableResult func set(_ data: Data, forKey key: String) -> Bool {
        lock.withLock {
            mutations += 1
            storage[key] = data
            return true
        }
    }

    @discardableResult func synchronize() -> Bool { true }

    func removeValue(forKey key: String) {
        lock.withLock {
            mutations += 1
            storage[key] = nil
        }
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.withLock { storage.keys.filter { $0.hasPrefix(prefix) }.sorted() }
    }

    /// Seeds keys without counting as an app write.
    func seed(_ key: String, _ data: Data?) {
        lock.withLock { storage[key] = data }
    }

    func clear() { lock.withLock { storage = [:] } }

    /// Publishes a Mac state: manifest, provider keys and optional v3, as one store image.
    func publish(manifest: CompanionManifest?, providers: [String: Data], v3: SyncedWidgetSnapshotEnvelope? = nil) {
        lock.withLock {
            storage = [:]
            if let manifest { storage[CompanionSyncKeys.manifest] = CompanionFixtures.bytes(manifest) }
            for (id, data) in providers { storage[CompanionSyncKeys.provider(id)!] = data }
            if let v3 { storage[iCloudSnapshotSync.snapshotKey] = CompanionFixtures.v3Bytes(v3) }
        }
    }
}

/// One simulated process: its own coordinator and clock over shared storage and anchor.
struct SimulatedProcess {
    let loader: CompanionSnapshotLoader
    let coordinator: BarrierCoordinator

    init(
        storage: MemoryCacheStorage, anchor: SharedAnchor, scope: FakeAccountScope,
        store: (any iCloudKeyValueSyncing)?, now: Date, gatedEntry: Int? = nil
    ) {
        coordinator = BarrierCoordinator(anchor: anchor, gatedEntry: gatedEntry)
        loader = CompanionSnapshotLoader(
            store: store,
            cache: CompanionSnapshotCache(storage: storage, coordinator: coordinator, scope: scope),
            now: { now })
    }
}

/// Runs `work` on a dedicated thread and returns a handle to await its result.
final class ThreadResult<T: Sendable>: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var value: T?

    init(_ work: @escaping @Sendable () -> T) {
        let thread = Thread { [self] in
            value = work()
            done.signal()
        }
        thread.start()
    }

    func wait() -> T {
        done.wait()
        return value!
    }
}
