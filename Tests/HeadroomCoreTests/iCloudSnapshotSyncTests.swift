import Foundation
import Testing
@testable import HeadroomCore

struct iCloudSnapshotSyncTests {
    private let generatedAt = Date(timeIntervalSince1970: 1_000)
    private let publishedAt = Date(timeIntervalSince1970: 1_500)

    @Test func publishWritesSingleKeyAndReadReturnsSnapshot() throws {
        let store = MemoryiCloudKeyValueStore()
        let sync = iCloudSnapshotSync(store: store)
        let envelope = syncedEnvelope()

        try sync.publish(envelope)

        #expect(store.keys == [iCloudSnapshotSync.snapshotKey])
        #expect(sync.read() == .snapshot(envelope))
        #expect(store.synchronizeCount == 0)
    }

    @Test func readPrefersNewestLocalOrRemoteSnapshot() throws {
        let store = MemoryiCloudKeyValueStore()
        let local = syncedEnvelope(publishedAt: Date(timeIntervalSince1970: 20), sourceID: "local")
        let remote = syncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), sourceID: "remote")
        try store.seed(remote)
        let sync = iCloudSnapshotSync(store: store, localEnvelope: { local })

        #expect(sync.read() == .snapshot(local))

        let newerRemote = syncedEnvelope(
            publishedAt: Date(timeIntervalSince1970: 30),
            sourceID: "remote",
            generatedAt: generatedAt.addingTimeInterval(1)
        )
        try store.seed(newerRemote)
        #expect(sync.read() == .snapshot(newerRemote))
    }

    @Test func equalSnapshotGenerationKeepsLocalRegardlessOfPublicationMetadata() throws {
        let store = MemoryiCloudKeyValueStore()
        let local = syncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), sourceID: "a")
        let remote = syncedEnvelope(publishedAt: Date(timeIntervalSince1970: 20), sourceID: "b")
        try store.seed(remote)
        let sync = iCloudSnapshotSync(store: store, localEnvelope: { local })

        #expect(sync.read() == .snapshot(local))
    }

    @Test func unavailableStoreReturnsUnavailableAndThrowsOnPublish() {
        let sync = iCloudSnapshotSync(store: nil)

        #expect(sync.read() == .unavailable)
        #expect(throws: iCloudSnapshotSyncError.unavailable) {
            try sync.publish(syncedEnvelope())
        }
    }

    @Test func missingCorruptAndIncompatibleStatesAreSafe() throws {
        let store = MemoryiCloudKeyValueStore()
        let sync = iCloudSnapshotSync(store: store)

        #expect(sync.read() == .missing)

        store.set(Data("not-json".utf8), forKey: iCloudSnapshotSync.snapshotKey)
        #expect(sync.read() == .corrupt)

        let incompatible = SyncedWidgetSnapshotEnvelope(
            schemaVersion: 999,
            publishedAt: publishedAt,
            sourceID: "mac",
            sourcePlatform: .macOS,
            snapshot: .disabled(generatedAt: generatedAt)
        )
        store.set(try JSONEncoder().encode(incompatible), forKey: iCloudSnapshotSync.snapshotKey)
        #expect(sync.read() == .incompatibleSchema)
    }

    @Test func writeFailureThrowsAndDoesNotPretendSuccess() {
        let store = MemoryiCloudKeyValueStore()
        store.shouldFailWrites = true
        let sync = iCloudSnapshotSync(store: store)

        #expect(throws: iCloudSnapshotSyncError.writeFailed) {
            try sync.publish(syncedEnvelope())
        }
    }

    @Test func publisherWrapsWidgetSnapshotWithMacMetadata() {
        let store = MemoryiCloudKeyValueStore()
        let sync = iCloudSnapshotSync(store: store)
        let publisher = iCloudSnapshotPublisher(
            sync: sync,
            now: { publishedAt },
            sourceID: { "mac-1" }
        )

        publisher.export(.disabled(generatedAt: generatedAt))

        let read = sync.read()
        #expect(read.envelope?.publishedAt == publishedAt)
        #expect(read.envelope?.sourceID == "mac-1")
        #expect(read.envelope?.sourcePlatform == .macOS)
        #expect(read.envelope?.snapshot.status == .disabled)
    }

    private func syncedEnvelope(
        publishedAt: Date? = nil,
        sourceID: String = "mac",
        generatedAt: Date? = nil
    ) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            publishedAt: publishedAt ?? self.publishedAt,
            sourceID: sourceID,
            sourcePlatform: .macOS,
            snapshot: .disabled(generatedAt: generatedAt ?? self.generatedAt)
        )
    }
}

final class MemoryiCloudKeyValueStore: iCloudKeyValueSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    var shouldFailWrites = false
    private(set) var synchronizeCount = 0

    var keys: [String] { lock.withLock { storage.keys.sorted() } }

    func data(forKey key: String) -> Data? {
        lock.withLock { storage[key] }
    }

    @discardableResult func set(_ data: Data, forKey key: String) -> Bool {
        lock.withLock {
            guard !shouldFailWrites else { return false }
            storage[key] = data
            return true
        }
    }

    @discardableResult func synchronize() -> Bool {
        lock.withLock {
            synchronizeCount += 1
            return !shouldFailWrites
        }
    }

    func removeValue(forKey key: String) {
        lock.withLock { _ = storage.removeValue(forKey: key) }
    }

    func keys(withPrefix prefix: String) -> [String] {
        lock.withLock { storage.keys.filter { $0.hasPrefix(prefix) }.sorted() }
    }

    func seed(_ envelope: SyncedWidgetSnapshotEnvelope) throws {
        storage[iCloudSnapshotSync.snapshotKey] = try SyncedWidgetSnapshotCodec.encode(envelope)
    }
}
