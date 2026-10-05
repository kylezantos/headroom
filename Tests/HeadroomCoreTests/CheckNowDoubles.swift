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
