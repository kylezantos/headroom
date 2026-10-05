import Foundation

public enum iCloudSnapshotSyncRead: Equatable, Sendable {
    case unavailable
    case missing
    case corrupt
    case incompatibleSchema
    case snapshot(SyncedWidgetSnapshotEnvelope)

    public var envelope: SyncedWidgetSnapshotEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

public enum iCloudSnapshotSyncError: Error, Equatable, Sendable {
    case unavailable
    case writeFailed
}

public protocol iCloudKeyValueSyncing: Sendable {
    func data(forKey key: String) -> Data?
    /// Reports local acceptance only, never remote delivery (KTD22).
    @discardableResult func set(_ data: Data, forKey key: String) -> Bool
    /// Never proof of identity or server delivery.
    @discardableResult func synchronize() -> Bool
    /// Idempotent: removing a missing key is a no-op (KTD6.1 seam, KTD22 sync-off sweep).
    func removeValue(forKey key: String)
    /// Key names under a prefix, for launch scans and prefix deletes. Never payloads.
    func keys(withPrefix prefix: String) -> [String]
}

/// Why KVS reported an external change (KTD6.1 seam). An unknown reason re-reads
/// conservatively; an account change invalidates caches independently (KTD22).
public enum iCloudKeyValueChangeReason: Equatable, Sendable {
    case serverChange
    case initialSyncChange
    case quotaViolationChange
    case accountChange
    case unknown

    public init(rawReason: Int?) {
        switch rawReason {
        case NSUbiquitousKeyValueStoreServerChange: self = .serverChange
        case NSUbiquitousKeyValueStoreInitialSyncChange: self = .initialSyncChange
        case NSUbiquitousKeyValueStoreQuotaViolationChange: self = .quotaViolationChange
        case NSUbiquitousKeyValueStoreAccountChange: self = .accountChange
        default: self = .unknown
        }
    }
}

/// A typed `didChangeExternallyNotification`: the reason and changed key names only.
public struct iCloudKeyValueChange: Equatable, Sendable {
    public let reason: iCloudKeyValueChangeReason
    public let changedKeys: [String]

    public init(reason: iCloudKeyValueChangeReason, changedKeys: [String]) {
        self.reason = reason
        self.changedKeys = changedKeys
    }

    public init(userInfo: [AnyHashable: Any]?) {
        let raw = (userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue
        self.init(
            reason: iCloudKeyValueChangeReason(rawReason: raw),
            changedKeys: (userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []).sorted())
    }

    /// The quota signal (KTD7): a typed event and time only, a diagnostic that may force
    /// one extra ladder step when measured bytes were under budget.
    public func quotaEvent(at date: Date) -> iCloudKeyValueQuotaEvent? {
        reason == .quotaViolationChange ? iCloudKeyValueQuotaEvent(observedAt: date) : nil
    }

    /// Whether any changed key belongs to the given prefix (e.g. the v4 namespace).
    public func touches(prefix: String) -> Bool {
        changedKeys.contains { $0.hasPrefix(prefix) }
    }
}

public struct iCloudKeyValueQuotaEvent: Equatable, Sendable {
    public let observedAt: Date
}

public struct iCloudSnapshotSync: Sendable {
    public static let snapshotKey = "headroom.syncedWidgetSnapshot"

    private let store: (any iCloudKeyValueSyncing)?
    private let key: String
    private let localEnvelope: @Sendable () -> SyncedWidgetSnapshotEnvelope?

    public init(
        store: (any iCloudKeyValueSyncing)?,
        key: String = Self.snapshotKey,
        localEnvelope: @escaping @Sendable () -> SyncedWidgetSnapshotEnvelope? = { nil }
    ) {
        self.store = store
        self.key = key
        self.localEnvelope = localEnvelope
    }

    public func read() -> iCloudSnapshotSyncRead {
        guard let store else { return .unavailable }
        let remote = SyncedWidgetSnapshotCodec.decode(store.data(forKey: key))
        return read(from: SyncedWidgetSnapshotResolution.newestValid(local: localEnvelope(), remote: remote))
    }

    public func publish(_ envelope: SyncedWidgetSnapshotEnvelope) throws {
        guard let store else { throw iCloudSnapshotSyncError.unavailable }
        let data = try SyncedWidgetSnapshotCodec.encode(envelope)
        guard store.set(data, forKey: key) else {
            throw iCloudSnapshotSyncError.writeFailed
        }
    }

    private func read(from result: SyncedWidgetSnapshotDecodeResult) -> iCloudSnapshotSyncRead {
        switch result {
        case .missing:
            .missing
        case .incompatibleSchema:
            .incompatibleSchema
        case .corrupt:
            .corrupt
        case .snapshot(let envelope):
            .snapshot(envelope)
        }
    }
}

public struct iCloudSnapshotPublisher: WidgetSnapshotExporting {
    private let sync: iCloudSnapshotSync
    private let now: @Sendable () -> Date
    private let sourceID: @Sendable () -> String

    public init(
        sync: iCloudSnapshotSync,
        now: @escaping @Sendable () -> Date = Date.init,
        sourceID: @escaping @Sendable () -> String = { "Mac" }
    ) {
        self.sync = sync
        self.now = now
        self.sourceID = sourceID
    }

    public func export(_ envelope: WidgetSnapshotEnvelope) {
        let synced = SyncedWidgetSnapshotEnvelope(
            publishedAt: now(),
            sourceID: sourceID(),
            sourcePlatform: .macOS,
            snapshot: envelope
        )
        try? sync.publish(synced)
    }
}

#if canImport(Foundation)
public struct UbiquitousKeyValueSyncStore: iCloudKeyValueSyncing, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) -> Bool {
        store.set(data, forKey: key)
        return true
    }

    public func synchronize() -> Bool {
        store.synchronize()
    }

    public func removeValue(forKey key: String) {
        store.removeObject(forKey: key)
    }

    public func keys(withPrefix prefix: String) -> [String] {
        store.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}
#endif
