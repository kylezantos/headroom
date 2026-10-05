import Foundation

@testable import HeadroomCore

/// One device's local KVS copy for the scope-marker suites. Its own file per the parity
/// plan's stream rule. Besides Data values it can hold an opaque value of another type
/// (as a String written by some other code would be), which `data(forKey:)` cannot read
/// but key enumeration still lists.
final class MarkerKeyValueStore: iCloudKeyValueSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var opaque: Set<String> = []
    private(set) var synchronizations = 0
    private(set) var mutations = 0
    private(set) var reads = 0
    var rejectsWrites = false

    func data(forKey key: String) -> Data? {
        lock.withLock {
            reads += 1
            return values[key]
        }
    }

    @discardableResult func set(_ data: Data, forKey key: String) -> Bool {
        lock.withLock {
            guard !rejectsWrites else { return false }
            mutations += 1
            values[key] = data
            opaque.remove(key)
            return true
        }
    }

    @discardableResult func synchronize() -> Bool {
        lock.withLock { synchronizations += 1 }
        return true
    }

    func removeValue(forKey key: String) {
        lock.withLock {
            mutations += 1
            values[key] = nil
            opaque.remove(key)
        }
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.withLock { (Set(values.keys).union(opaque)).filter { $0.hasPrefix(prefix) }.sorted() }
    }

    // MARK: Test-only state changes (not counted as app writes)

    var marker: String? {
        get { lock.withLock { values[CompanionSyncKeys.scopeMarker].flatMap { String(data: $0, encoding: .utf8) } } }
        set { lock.withLock { values[CompanionSyncKeys.scopeMarker] = newValue.map { Data($0.utf8) } } }
    }

    func seed(_ key: String, _ data: Data?) { lock.withLock { values[key] = data } }

    func seedOpaque(_ key: String) {
        lock.withLock {
            values[key] = nil
            opaque.insert(key)
        }
    }

    /// The system replacing this device's store with another account's data (Apple:
    /// `NSUbiquitousKeyValueStoreAccountChange`), or a sync delivering another device's image.
    func replace(with other: MarkerKeyValueStore) {
        let image = other.lock.withLock { other.values }
        lock.withLock {
            values = image
            opaque = []
        }
    }

    /// Account A's Mac publish: a v4 manifest, one Claude key with an extra account, a v3 mirror.
    func publishAccount(marker: String?, extraTitle: String = "Work") {
        typealias F = CompanionFixtures
        let payload = F.bytes(F.payload(extras: [F.account("x1", title: extraTitle)]))
        lock.withLock {
            values = [:]
            values[CompanionSyncKeys.manifest] = F.bytes(F.manifest(entries: ["claude": F.entry(payload, generation: 1)]))
            values[CompanionSyncKeys.provider("claude")!] = payload
            values[iCloudSnapshotSync.snapshotKey] = F.v3Bytes(F.v3(lineage: (F.macA, 1)))
            values[CompanionSyncKeys.scopeMarker] = marker.map { Data($0.utf8) }
        }
    }
}

/// A settable clock for the writer's initial-sync deferral.
final class MarkerClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
