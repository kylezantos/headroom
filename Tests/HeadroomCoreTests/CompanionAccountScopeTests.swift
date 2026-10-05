import Foundation
import Testing

@testable import HeadroomCore

/// KTD22 "Account scope" scenarios, through the loader with injected doubles only. These
/// prove the seam's rules; they do not establish a platform identity signal (P5).
@Suite
struct CompanionAccountScopeTests {
    typealias F = CompanionFixtures
    private let anchor = SharedAnchor()
    private let storage = MemoryCacheStorage()
    private let scope = FakeAccountScope("apple-id-a")

    private func loader(_ store: (any iCloudKeyValueSyncing)?, now: Int64 = 60) -> CompanionSnapshotLoader {
        SimulatedProcess(storage: storage, anchor: anchor, scope: scope, store: store, now: F.date(now).date).loader
    }

    private func accountAStore() -> SpyKeyValueStore {
        let store = SpyKeyValueStore()
        let payload = F.bytes(F.payload(extras: [F.account("x1", title: "Work")]))
        store.publish(
            manifest: F.manifest(entries: ["claude": F.entry(payload, generation: 1)]),
            providers: ["claude": payload], v3: F.v3(lineage: (F.macA, 1)))
        return store
    }

    /// With the app closed, switching to an Apple ID with no Headroom keys makes widget,
    /// Siri and Control loads return no prior-account content and clears both caches.
    @Test func switchToAnEmptyAppleIDServesNoPriorAccountContentOnAnySurface() throws {
        let a = accountAStore()
        let loaded = loader(a).load()
        #expect(loaded.content?.providers.first?.accounts.count == 2)
        #expect(storage[.v4] != nil && storage[.v3Compatibility] != nil)

        scope.identity = "apple-id-b"
        let emptyB = SpyKeyValueStore()
        for _ in ["widget", "siri", "control"] {
            let snapshot = loader(emptyB).load()
            #expect(snapshot.state == .waiting(nil))
            #expect(snapshot.primaryProjection() == nil)
        }
        #expect(storage[.v4] == nil && storage[.v3Compatibility] == nil)
        #expect(storage.sidecar?.firstSeen.isEmpty == true)
        // Even offline (no KVS at all) nothing from A comes back.
        #expect(loader(nil).load().content == nil)
    }

    @Test func unavailableScopeNeverFallsBackToCachedAccountContent() throws {
        _ = loader(accountAStore()).load()
        scope.identity = nil
        let spy = SpyKeyValueStore()
        let snapshot = loader(spy).load()
        #expect(snapshot.state == .accountScopeUnavailable)
        // Identity is checked before any KVS read, including missing-key paths.
        #expect(spy.reads == 0)
        #expect(storage[.v4] == nil && storage[.v3Compatibility] == nil)
        // Signing back in starts a fresh boundary: nothing is restored from before.
        scope.identity = "apple-id-a"
        #expect(loader(nil).load().state == .waiting(nil))
    }

    @Test func verifiedUnchangedScopePreservesOfflineReads() throws {
        _ = loader(accountAStore()).load()
        let offline = loader(nil, now: 120).load()
        let content = try #require(offline.content)
        #expect(content.origin == .v4 && content.providers.first?.accounts.count == 2)
        #expect(content.freshness.firstSeen == F.date(60).date)
    }

    /// Untagged compatibility caches (a build-33 `widget-snapshot.json` with no sidecar)
    /// are adopted only from a fresh current-scope read of the v3 key.
    @Test func untaggedCompatibilityCacheIsAdoptedOnlyFromAFreshV3Read() throws {
        let legacy = F.v3(generatedAt: -600).snapshot
        storage[.v3Compatibility] = try JSONEncoder().encode(legacy)
        let missing = loader(SpyKeyValueStore()).load()
        #expect(missing.state == .waiting(nil))
        #expect(storage[.v3Compatibility] == nil)

        storage[.v3Compatibility] = try JSONEncoder().encode(legacy)
        let fresh = F.v3(generatedAt: 0)
        let store = SpyKeyValueStore()
        store.seed(iCloudSnapshotSync.snapshotKey, F.v3Bytes(fresh))
        let adopted = loader(store).load()
        #expect(adopted.content?.origin == .v3 && adopted.content?.generatedAt == fresh.snapshot.generatedAt)
        #expect(storage[.v3Compatibility] == (try CompanionSyncCodec.encode(fresh.snapshot)))
        #expect(storage.sidecar?.v3Wrapper != nil)
    }

    @Test func accountChangeNotificationInvalidatesWithoutBeingTheOnlyTrigger() throws {
        let a = accountAStore()
        let process = loader(a)
        _ = process.load()
        let epoch = try #require(storage.sidecar?.epoch)
        process.handle(iCloudKeyValueChange(reason: .serverChange, changedKeys: [CompanionSyncKeys.manifest]))
        #expect(storage.sidecar?.epoch == epoch)
        process.handle(
            iCloudKeyValueChange(
                userInfo: [
                    NSUbiquitousKeyValueStoreChangeReasonKey: NSNumber(value: NSUbiquitousKeyValueStoreAccountChange)
                ]))
        #expect(storage[.v4] == nil && storage.sidecar?.epoch != epoch)
        // The next load re-establishes the scope and reads the current store again.
        #expect(process.load().content?.origin == .v4)
    }

    @Test func demoNeverReadsOrWritesICloudOrAnyCache() throws {
        let spy = SpyKeyValueStore()
        let demoSnapshot = CompanionResolvedSnapshot(state: .paused)
        let demo = CompanionSnapshotLoader(
            store: spy,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: anchor), scope: scope),
            demo: { demoSnapshot })
        #expect(demo.load() == demoSnapshot)
        #expect(spy.reads == 0 && spy.mutations == 0)
        #expect(storage.writes.isEmpty && storage.removals.isEmpty && scope.checks == 0)
    }

    @Test func sidecarCarriesNoExportedIdentityAndEpochsNeverRepeat() throws {
        _ = loader(accountAStore()).load()
        let first = try #require(storage.sidecar?.epoch)
        scope.identity = "apple-id-b"
        _ = loader(nil).load()
        scope.identity = "apple-id-a"
        _ = loader(nil).load()
        let third = try #require(storage.sidecar?.epoch)
        #expect(first != third)
        // Snapshots and diagnostics never carry the scope archive.
        let snapshot = loader(accountAStore()).load()
        #expect(!String(describing: snapshot).contains("apple-id"))
    }

    @Test func kvsChangeEventsAreTypedWithKeyNamesOnly() throws {
        let quota = iCloudKeyValueChange(
            userInfo: [
                NSUbiquitousKeyValueStoreChangeReasonKey: NSNumber(value: NSUbiquitousKeyValueStoreQuotaViolationChange),
                NSUbiquitousKeyValueStoreChangedKeysKey: [CompanionSyncKeys.receipt, CompanionSyncKeys.manifest],
            ])
        #expect(quota.reason == .quotaViolationChange)
        #expect(quota.changedKeys == [CompanionSyncKeys.manifest, CompanionSyncKeys.receipt])
        #expect(quota.touches(prefix: CompanionSyncKeys.namespace))
        #expect(quota.quotaEvent(at: F.date().date) == iCloudKeyValueQuotaEvent(observedAt: F.date().date))
        #expect(iCloudKeyValueChange(userInfo: nil).reason == .unknown)
        #expect(iCloudKeyValueChange(userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSNumber(value: 99)]).reason == .unknown)
        #expect(iCloudKeyValueChange(reason: .serverChange, changedKeys: []).quotaEvent(at: .now) == nil)

        let memory = MemoryiCloudKeyValueStore()
        memory.set(Data([1]), forKey: CompanionSyncKeys.manifest)
        memory.set(Data([2]), forKey: CompanionSyncKeys.request(deviceUUID: UUID().uuidString)!)
        memory.set(Data([3]), forKey: iCloudSnapshotSync.snapshotKey)
        #expect(memory.keys(withPrefix: CompanionSyncKeys.namespace).count == 2)
        memory.removeValue(forKey: CompanionSyncKeys.manifest)
        memory.removeValue(forKey: CompanionSyncKeys.manifest)
        #expect(memory.keys(withPrefix: CompanionSyncKeys.namespace).count == 1)
        #expect(memory.data(forKey: iCloudSnapshotSync.snapshotKey) == Data([3]))
    }
}
