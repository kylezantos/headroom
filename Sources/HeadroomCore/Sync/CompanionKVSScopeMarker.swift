import Foundation

// KTD22 deviation, pending Kyle's sign-off. KTD22 names `FileManager.ubiquityIdentityToken` as
// the account-scope candidate and says the scope "never syncs". That token failed the signed
// P5 gate (app and widget disagreed for one account) and Apple documents it as nil with iCloud
// Drive off, which the plan must support. This candidate is a random UUID stored in the same
// iCloud key-value store the cached content comes from (u4-identity-diagnosis.md §4). Apple
// documents that an Apple-account change replaces that store, so a different account shows a
// different marker or none. It syncs, but carries no identity: it says which store a cache came
// from, never who the person is. It is unverified on device until the "Marker candidate" check
// in docs/qa/2026-10-04-companion-identity-candidate-gate.md passes, so `CompanionLoaderAdoption`
// stays off.

/// The reader side of the KVS scope marker: every loader (app, widget, Siri, Control) compares
/// the live local marker with the sidecar's archive. Readers never write the key.
public struct CompanionKVSScopeMarker: CompanionAccountScopeProviding {
    public static let key = CompanionSyncKeys.scopeMarker
    /// A UUID string is 36 bytes; anything far larger was not written by Headroom.
    public static let maximumBytes = 128

    private let store: any iCloudKeyValueSyncing

    /// - Parameter store: the device's local KVS copy. The caller synchronizes it once before a
    ///   load, so the check reads what is on disk now, not an earlier in-memory image.
    public init(store: any iCloudKeyValueSyncing) {
        self.store = store
    }

    /// The marker's bytes as stored, or nil when absent, empty, oversized or not Data. Readers
    /// treat all of those as "no scope"; the writer treats every present value as taken.
    public static func liveMarker(in store: any iCloudKeyValueSyncing) -> Data? {
        guard let data = store.data(forKey: key), !data.isEmpty, data.count <= maximumBytes else { return nil }
        return data
    }

    /// The archive is the marker's bytes, so equality is the marker's own (byte) equality.
    public func check(against archive: Data?) -> CompanionScopeCheck {
        guard let live = Self.liveMarker(in: store) else { return .unavailable }
        return archive == live ? .unchanged : .changed(archive: live)
    }
}

/// What one `ensureMarker()` call did. Enum only: the marker value never reaches UI or logs.
public enum CompanionScopeMarkerWriteResult: String, Equatable, Sendable {
    /// A value already exists under the key; it is never rewritten.
    case present
    case written
    /// An initial download is in flight (Apple: schedule writes after a delay).
    case deferredForInitialSync
    /// The store refused local acceptance; the next call tries again.
    case rejected
}

/// The marker's writer, created by every phone process's adopted loader (app, widget extension,
/// Siri, controls); the Mac never writes it. It writes a fresh random UUID only when the key is
/// absent and never writes a remembered value from memory or the sidecar, so a marker can never
/// be carried from one account's store into another's. A widget that writes into a new account's
/// empty store still mismatches the sidecar's old archive, so caches are invalidated, not served.
///
/// Fail-safe races: two devices writing at once leaves the last writer's value and costs the
/// other device one invalidation; a write the system discards during an initial download is
/// retried after the deferral; a deleted key blocks cached content until a new marker starts a
/// fresh scope.
public final class CompanionKVSScopeMarkerWriter: @unchecked Sendable {
    /// How long a write waits after an initial-sync or account-change notification.
    public static let initialSyncDeferral: TimeInterval = 60

    private let store: any iCloudKeyValueSyncing
    private let now: @Sendable () -> Date
    private let makeMarker: @Sendable () -> String
    private let lock = NSLock()
    private var deferredUntil: Date?

    public init(
        store: any iCloudKeyValueSyncing,
        now: @escaping @Sendable () -> Date = Date.init,
        makeMarker: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.store = store
        self.now = now
        self.makeMarker = makeMarker
    }

    /// Feed every `didChangeExternallyNotification` here. `initialSyncChange` means a write was
    /// discarded because the first download has not finished; `accountChange` means one is
    /// about to start. Both defer the next write.
    public func record(_ change: iCloudKeyValueChange) {
        switch change.reason {
        case .initialSyncChange, .accountChange:
            lock.withLock { deferredUntil = now().addingTimeInterval(Self.initialSyncDeferral) }
        case .serverChange, .quotaViolationChange, .unknown:
            break
        }
    }

    @discardableResult
    public func ensureMarker() -> CompanionScopeMarkerWriteResult {
        lock.withLock {
            if let deferredUntil, now() < deferredUntil { return .deferredForInitialSync }
            deferredUntil = nil
            store.synchronize()
            // Presence, not readability: a value of another type still counts as taken.
            let key = CompanionKVSScopeMarker.key
            guard store.data(forKey: key) == nil, !store.keys(withPrefix: key).contains(key) else {
                return .present
            }
            guard store.set(Data(makeMarker().utf8), forKey: key) else { return .rejected }
            // Flush to disk now so the widget's next synchronize reads it.
            store.synchronize()
            return .written
        }
    }
}
