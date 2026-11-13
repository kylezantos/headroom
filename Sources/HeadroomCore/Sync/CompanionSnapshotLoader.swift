import Foundation

/// The one loader every phone surface will call (KTD6, KTD13): verify the local account
/// scope, read KVS, then resolve and merge inside the coordinated cache transaction.
///
/// Not adopted by the app or the widget extension in U4. The signed P5 account-identity
/// gate failed, and cached account content must never be served without a verified scope
/// (KTD22 stop condition), so this is built and tested against injected doubles only.
public struct CompanionSnapshotLoader: Sendable {
    private let store: (any iCloudKeyValueSyncing)?
    private let cache: CompanionSnapshotCache
    private let now: @Sendable () -> Date
    private let demo: (@Sendable () -> CompanionResolvedSnapshot?)?

    /// - Parameter demo: KTD21: when it returns a snapshot, nothing reads or writes
    ///   iCloud or any cache.
    public init(
        store: (any iCloudKeyValueSyncing)?,
        cache: CompanionSnapshotCache,
        now: @escaping @Sendable () -> Date = Date.init,
        demo: (@Sendable () -> CompanionResolvedSnapshot?)? = nil
    ) {
        self.store = store
        self.cache = cache
        self.now = now
        self.demo = demo
    }

    public func load() -> CompanionResolvedSnapshot {
        if let demo, let snapshot = demo() { return snapshot }
        // KTD22: identity first, before any KVS read, including missing-key paths.
        guard let capture = cache.captureScope() else { return Self.unavailable }
        let manifest = store?.data(forKey: CompanionSyncKeys.manifest)
        var providerKeys: [String: Data] = [:]
        for id in CompanionSyncKeys.readerKnownProviderIDs {
            if let key = CompanionSyncKeys.provider(id), let data = store?.data(forKey: key) {
                providerKeys[id] = data
            }
        }
        let v3 = store?.data(forKey: iCloudSnapshotSync.snapshotKey)
        let snapshot = cache.transact(capture: capture) { contents in
            // `now` is read inside the transaction, so first-seen is created exactly once.
            let resolution = CompanionSnapshotResolver.resolve(
                CompanionResolverInput(
                    manifest: manifest, providerKeys: providerKeys, v3: v3, cache: contents,
                    now: now()))
            return (resolution.cache, resolution.snapshot)
        }
        return snapshot ?? Self.unavailable
    }

    /// The app clears caches on `NSUbiquitousKeyValueStoreAccountChange`; the scope check
    /// on every load remains the authority (KTD22).
    public func handle(_ change: iCloudKeyValueChange) {
        if change.reason == .accountChange { cache.invalidate() }
    }

    private static let unavailable = CompanionResolvedSnapshot(state: .accountScopeUnavailable)
}
