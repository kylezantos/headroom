import Foundation
import Testing

@testable import HeadroomCore

/// KTD6.8 "Cache" and "Cache transaction" scenarios: one coordinated transaction, barrier-held
/// cross-process writers, shared first-seen and the build-33 compatibility file.
@Suite
struct CompanionCacheCoordinationTests {
    typealias F = CompanionFixtures
    private let anchor = SharedAnchor()
    private let storage = MemoryCacheStorage()
    private let scope = FakeAccountScope("apple-id-a")

    private func publish(_ generation: Int64, at offset: Int64 = 0, into store: SpyKeyValueStore, extras: Int = 0) {
        let payload = F.bytes(
            F.payload(
                generation: generation,
                extras: (0..<extras).map { F.account("x\($0)", title: "Extra \($0)") }))
        store.publish(
            manifest: F.manifest(
                generation: generation, generatedAt: offset,
                entries: ["claude": F.entry(payload, generation: generation)]),
            providers: ["claude": payload])
    }

    private func process(_ store: SpyKeyValueStore?, now: Int64 = 60, gatedEntry: Int? = nil) -> SimulatedProcess {
        SimulatedProcess(
            storage: storage, anchor: anchor, scope: scope, store: store, now: F.date(now).date,
            gatedEntry: gatedEntry)
    }

    private func arrive(_ coordinator: BarrierCoordinator) {
        #expect(coordinator.arrived.wait(timeout: .now() + 10) == .success)
    }

    /// Both writers capture against generation 10; writer 11 is held at the transaction
    /// gate until 12 commits, then re-reads inside the transaction and loses.
    @Test func olderWriterHeldAtTheGateLosesToTheNewerCommit() throws {
        let seed = SpyKeyValueStore()
        publish(10, into: seed)
        _ = process(seed).loader.load()
        #expect(storage.sidecar != nil)

        let eleven = SpyKeyValueStore(), twelve = SpyKeyValueStore()
        publish(11, at: 10, into: eleven, extras: 1)
        publish(12, at: 20, into: twelve, extras: 2)
        let app = process(eleven, gatedEntry: 2)
        let pending = ThreadResult { app.loader.load() }
        arrive(app.coordinator)
        let widget = process(twelve).loader.load()
        #expect(widget.content?.generation == 12)
        app.coordinator.gate.signal()
        let late = pending.wait()

        #expect(late.content?.generation == 12)
        #expect(late.content?.providers.first?.accounts.count == 3)
        let cached = try #require(storage[.v4])
        let file = try JSONDecoder().decode(CompanionV4CacheFile.self, from: cached)
        #expect(file.manifest?.generation == 12 && file.providers["claude"]?.generation == 12)
    }

    @Test func concurrentFirstSeenCreationProducesOneSharedTime() throws {
        let store = SpyKeyValueStore()
        publish(1, into: store)
        _ = process(store, now: 0).loader.load()  // establish scope only
        publish(2, at: 30, into: store)
        let app = process(store, now: 100, gatedEntry: 2)
        let widget = process(store, now: 140, gatedEntry: 2)
        let first = ThreadResult { app.loader.load() }
        let second = ThreadResult { widget.loader.load() }
        arrive(app.coordinator)
        arrive(widget.coordinator)
        widget.coordinator.gate.signal()
        let widgetSnapshot = second.wait()
        app.coordinator.gate.signal()
        let appSnapshot = first.wait()
        let shared = try #require(widgetSnapshot.content?.freshness.firstSeen)
        #expect(shared == F.date(140).date)
        #expect(appSnapshot.content?.freshness.firstSeen == shared)
        #expect(
            CompanionFreshnessRule.dimsAt(try #require(appSnapshot.content?.freshness), surface: .widget)
                == CompanionFreshnessRule.dimsAt(try #require(widgetSnapshot.content?.freshness), surface: .widget))
    }

    /// A captured write racing an account-scope invalidation cannot restore old content,
    /// whether identity stays on the new account or returns to the old one (A → B → A).
    @Test(arguments: [false, true])
    func capturedWriterCannotRestoreContentAfterAnAccountChange(returnToA: Bool) throws {
        let storeA = SpyKeyValueStore()
        publish(5, into: storeA, extras: 1)
        _ = process(storeA).loader.load()

        let writer = process(storeA, gatedEntry: 2)
        let pending = ThreadResult { writer.loader.load() }
        arrive(writer.coordinator)
        scope.identity = "apple-id-b"
        let otherProcess = process(SpyKeyValueStore()).loader.load()
        #expect(otherProcess.state == .waiting(nil))
        if returnToA { scope.identity = "apple-id-a" }
        writer.coordinator.gate.signal()
        let late = pending.wait()

        #expect(late.state == .accountScopeUnavailable)
        #expect(storage[.v4] == nil && storage[.v3Compatibility] == nil)
        #expect(storage.sidecar?.firstSeen.isEmpty == true)
    }

    @Test func v4WritesNeverTouchTheCompatibilityFileWhichOnlyGetsV3KeyBytes() throws {
        let store = SpyKeyValueStore()
        publish(1, into: store)
        _ = process(store).loader.load()
        #expect(!storage.writes.contains(.v3Compatibility))

        let v3 = F.v3(generatedAt: 0, lineage: (F.macA, 1))
        store.seed(iCloudSnapshotSync.snapshotKey, F.v3Bytes(v3))
        storage.resetLog()
        _ = process(store).loader.load()
        #expect(storage.writes.filter { $0 == .v3Compatibility }.count == 1)
        #expect(storage[.v3Compatibility] == (try CompanionSyncCodec.encode(v3.snapshot)))

        storage.resetLog()
        publish(2, at: 30, into: store)
        store.seed(iCloudSnapshotSync.snapshotKey, F.v3Bytes(v3))
        _ = process(store).loader.load()
        #expect(storage.writes.contains(.v4))
        #expect(!storage.writes.contains(.v3Compatibility))
    }

    /// V6: an incompatible v4 cache file does not block cached v3.
    @Test func incompatibleV4CacheFileDoesNotBlockV3() throws {
        let store = SpyKeyValueStore()
        store.seed(iCloudSnapshotSync.snapshotKey, F.v3Bytes(F.v3()))
        _ = process(store).loader.load()
        storage[.v4] = Data(#"{"format":99}"#.utf8)
        let offline = process(nil).loader.load()
        #expect(offline.content?.origin == .v3 && offline.content?.notice == .updateMac)
    }

    @Test func interruptedCommitServesNothingCachedAndIsRebuilt() throws {
        let store = SpyKeyValueStore()
        publish(3, into: store, extras: 1)
        _ = process(store).loader.load()
        var sidecar = try #require(storage.sidecar)
        sidecar.committed = false
        storage[.sidecar] = try CompanionSyncCodec.encode(sidecar)
        let offline = process(nil).loader.load()
        #expect(offline.state == .waiting(nil))
        #expect(storage[.v4] == nil && storage.sidecar?.committed == true)
        #expect(process(store).loader.load().content?.generation == 3)
    }

    @Test func failedCoordinationServesNothing() throws {
        let store = SpyKeyValueStore()
        publish(1, into: store)
        let process = process(store)
        process.coordinator.fails = true
        #expect(process.loader.load().state == .accountScopeUnavailable)
        #expect(store.reads == 0)
        #expect(storage[.sidecar] == nil)
    }

    @Test func directoryStorageReplacesFilesAtomicallyAndTreatsMissingAsNil() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = CompanionDirectoryCacheStorage(directory: directory)
        #expect(try disk.read(.v4) == nil)
        try disk.write(Data("one".utf8), to: .v4)
        try disk.write(Data("two".utf8), to: .v4)
        #expect(try disk.read(.v4) == Data("two".utf8))
        try disk.remove(.v4)
        try disk.remove(.v4)
        #expect(try disk.read(.v4) == nil)
        let coordinator = CompanionFileCacheCoordinator(
            anchor: directory.appendingPathComponent(CompanionFileCacheCoordinator.anchorFileName))
        #expect(coordinator.coordinate { 7 } == 7)
    }
}
