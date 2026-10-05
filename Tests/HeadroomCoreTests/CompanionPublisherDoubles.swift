import Foundation
@testable import HeadroomCore

// U5 doubles. Kept out of Mocks.swift per the parity plan's stream rules.

/// The existing widget spies keep their assertions: the phone path now receives a full
/// capture, and they record its paired schema-3 export.
extension SpyWidgetExporter: CompanionPhoneSyncing {
    @MainActor func submit(_ capture: CompanionPublishCapture) {
        export(capture.v3)
    }
}

extension FailingWidgetExporter: CompanionPhoneSyncing {
    @MainActor func submit(_ capture: CompanionPublishCapture) {
        export(capture.v3)
    }
}

/// Records every capture the store submits, and the provider it binds.
@MainActor
final class SpyPhoneSync: CompanionPhoneSyncing {
    private(set) var captures: [CompanionPublishCapture] = []
    private(set) var captureProvider: (@MainActor @Sendable () -> CompanionPublishCapture?)?
    private(set) var flushes = 0

    var last: CompanionPublishCapture? { captures.last }

    func submit(_ capture: CompanionPublishCapture) {
        captures.append(capture)
    }

    func bind(captureProvider: @escaping @MainActor @Sendable () -> CompanionPublishCapture?) {
        self.captureProvider = captureProvider
    }

    func flushNow() async {
        flushes += 1
    }
}

/// A KVS double that logs every mutation in order, so tests can assert write order,
/// counts and the exact sync-off sequence.
final class RecordingKeyValueStore: iCloudKeyValueSyncing, @unchecked Sendable {
    enum Operation: Hashable {
        case set(String)
        case remove(String)
    }

    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var log: [Operation] = []
    private var rejecting = false

    var operations: [Operation] { lock.withLock { log } }
    /// While true every `set` is refused (iCloud's quota or a full disk), storing nothing.
    var rejectsWrites: Bool {
        get { lock.withLock { rejecting } }
        set { lock.withLock { rejecting = newValue } }
    }
    var setCount: Int { lock.withLock { log.filter { if case .set = $0 { true } else { false } }.count } }
    var allKeys: [String] { lock.withLock { storage.keys.sorted() } }

    func data(forKey key: String) -> Data? {
        lock.withLock { storage[key] }
    }

    @discardableResult func set(_ data: Data, forKey key: String) -> Bool {
        lock.withLock {
            guard !rejecting else { return false }
            storage[key] = data
            log.append(.set(key))
            return true
        }
    }

    @discardableResult func synchronize() -> Bool { true }

    func removeValue(forKey key: String) {
        lock.withLock {
            storage[key] = nil
            log.append(.remove(key))
        }
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.withLock { storage.keys.filter { $0.hasPrefix(prefix) }.sorted() }
    }

    /// Simulates another writer (or a lost write) without logging an app operation.
    func seed(_ key: String, _ data: Data?) {
        lock.withLock { storage[key] = data }
    }

    func clearLog() {
        lock.withLock { log = [] }
    }
}

/// A settable clock for the publisher.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Counts lifecycle calls in order.
actor RecordingLifecycle: CompanionSyncLifecycle {
    private(set) var events: [String] = []

    func companionSyncDidEnable() async { events.append("enable") }
    func companionSyncDidPurge() async { events.append("purge") }
    func companionSyncAccountDidChange() async { events.append("account") }
}

/// The publisher's timer sleep with the real clock taken out: records every requested delay
/// and then parks (cancellably) so only the test's own `tick()` calls drive decisions.
final class RecordingSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var delays: [TimeInterval] = []
    private var cursor = 0

    var requested: [TimeInterval] { lock.withLock { delays } }

    /// The next delay the publisher scheduled, in order. The timer task records it once it
    /// starts, so this waits (bounded) rather than racing it.
    func next() async -> TimeInterval? {
        for _ in 0..<2_000 {
            let delay: TimeInterval? = lock.withLock {
                guard cursor < delays.count else { return nil }
                cursor += 1
                return delays[cursor - 1]
            }
            if let delay { return delay }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return nil
    }

    var sleep: @Sendable (TimeInterval) async -> Void {
        { [self] seconds in
            lock.withLock { delays.append(seconds) }
            try? await Task.sleep(for: .seconds(3_600))
        }
    }
}
