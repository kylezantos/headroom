import Foundation
import Testing

@testable import HeadroomCore

/// The KVS scope-marker candidate (KTD22 amendment, pending Kyle's sign-off): the marker lives
/// in the same iCloud key-value store the cached content comes from, so an account change
/// replaces it. These prove the rules with an in-memory store; the platform behaviour still
/// needs the companion identity gate's device check.
@Suite
struct CompanionKVSScopeMarkerTests {
    typealias F = CompanionFixtures
    private let anchor = SharedAnchor()
    private let storage = MemoryCacheStorage()

    /// One process on this device: its own coordinator over the shared App Group storage, its
    /// own marker check over the device's local KVS copy.
    private func loader(
        _ store: MarkerKeyValueStore, storage: MemoryCacheStorage? = nil, now: Int64 = 60
    ) -> CompanionSnapshotLoader {
        CompanionSnapshotLoader(
            store: store,
            cache: CompanionSnapshotCache(
                storage: storage ?? self.storage, coordinator: BarrierCoordinator(anchor: anchor),
                scope: CompanionKVSScopeMarker(store: store)),
            now: { F.date(now).date })
    }

    private func accountA(marker: String? = "marker-a") -> MarkerKeyValueStore {
        let store = MarkerKeyValueStore()
        store.publishAccount(marker: marker)
        return store
    }

    private func hasCachedContent(_ storage: MemoryCacheStorage? = nil) -> Bool {
        let storage = storage ?? self.storage
        return storage[.v4] != nil || storage[.v3Compatibility] != nil
    }

    // MARK: check(against:)

    @Test func checkComparesTheLiveMarkerBytesWithTheArchive() {
        let store = MarkerKeyValueStore()
        let marker = CompanionKVSScopeMarker(store: store)
        #expect(marker.check(against: nil) == .unavailable)
        #expect(marker.check(against: Data("marker-a".utf8)) == .unavailable)
        store.marker = "marker-a"
        #expect(marker.check(against: nil) == .changed(archive: Data("marker-a".utf8)))
        #expect(marker.check(against: Data("marker-a".utf8)) == .unchanged)
        #expect(marker.check(against: Data("marker-b".utf8)) == .changed(archive: Data("marker-a".utf8)))
    }

    @Test func emptyOversizedOrUnreadableMarkersAreUnavailable() {
        let store = MarkerKeyValueStore()
        let marker = CompanionKVSScopeMarker(store: store)
        store.seed(CompanionSyncKeys.scopeMarker, Data())
        #expect(marker.check(against: nil) == .unavailable)
        store.seed(CompanionSyncKeys.scopeMarker, Data(repeating: 65, count: CompanionKVSScopeMarker.maximumBytes + 1))
        #expect(marker.check(against: nil) == .unavailable)
        store.seedOpaque(CompanionSyncKeys.scopeMarker)
        #expect(marker.check(against: nil) == .unavailable)
    }

    /// The check reads the live local value each call (after the caller's synchronize); it
    /// never writes the store and never synchronizes on its own.
    @Test func checkNeverWritesOrSynchronizes() {
        let store = accountA()
        _ = CompanionKVSScopeMarker(store: store).check(against: nil)
        #expect(store.mutations == 0 && store.synchronizations == 0)
    }

    // MARK: Through the loader

    @Test func offlineWithAnUnchangedMarkerKeepsServingTheCache() throws {
        let store = accountA()
        let first = loader(store).load()
        #expect(first.content?.providers.first?.accounts.count == 2)
        let epoch = storage.sidecar?.epoch
        // Offline: no new payloads arrive, the local marker is unchanged.
        let offline = MarkerKeyValueStore()
        offline.marker = "marker-a"
        let later = loader(offline, now: 600).load()
        let content = try #require(later.content)
        #expect(content.origin == .v4 && content.providers.first?.accounts.count == 2)
        #expect(content.freshness.firstSeen == F.date(60).date)
        #expect(storage.sidecar?.epoch == epoch)
    }

    /// The account switches while the app is closed: the system replaced the local store, so
    /// the widget's own check sees another marker (or none) and the loader invalidates.
    @Test(arguments: ["marker-b", nil] as [String?])
    func switchingAccountsWhileTheAppIsClosedBlocksTheWidget(newMarker: String?) throws {
        let device = accountA()
        _ = loader(device).load()  // the app filled the cache under A
        #expect(hasCachedContent())

        let accountB = MarkerKeyValueStore()
        accountB.marker = newMarker  // an empty Apple ID: no Headroom payloads at all
        device.replace(with: accountB)

        let widget = loader(device).load()
        #expect(widget.content == nil)
        #expect(widget.primaryProjection() == nil)
        #expect(widget.state == (newMarker == nil ? .accountScopeUnavailable : .waiting(nil)))
        #expect(!hasCachedContent())
        #expect(storage.sidecar?.firstSeen.isEmpty == true)
        #expect(storage.sidecar?.scopeArchive == newMarker.map { Data($0.utf8) })
    }

    /// A → B → A: B's mirror differs from A's marker, so returning rebuilds from A's current
    /// payloads only; nothing cached before the round trip comes back.
    @Test func returningToTheFirstAccountNeverRestoresTheEarlierCache() throws {
        let device = accountA()
        _ = loader(device).load()
        let epochA = try #require(storage.sidecar?.epoch)

        let accountB = MarkerKeyValueStore()
        accountB.marker = "marker-b"
        device.replace(with: accountB)
        #expect(loader(device).load().content == nil)
        let epochB = try #require(storage.sidecar?.epoch)

        // Back on A, whose store currently holds only its marker (payloads not re-delivered).
        let returned = MarkerKeyValueStore()
        returned.marker = "marker-a"
        device.replace(with: returned)
        let back = loader(device).load()
        #expect(back.content == nil)
        #expect(!hasCachedContent())
        let epochA2 = try #require(storage.sidecar?.epoch)
        #expect(Set([epochA, epochB, epochA2]).count == 3)

        // Once A's payloads arrive, content is rebuilt from them.
        device.publishAccount(marker: "marker-a")
        #expect(loader(device).load().content?.origin == .v4)
    }

    @Test func aDeletedMarkerBlocksUntilANewOneStartsAFreshScope() throws {
        let device = accountA()
        _ = loader(device).load()
        let epoch = storage.sidecar?.epoch
        device.seed(CompanionSyncKeys.scopeMarker, nil)
        #expect(loader(device).load().state == .accountScopeUnavailable)
        #expect(!hasCachedContent())

        let writer = CompanionKVSScopeMarkerWriter(store: device, makeMarker: { "marker-new" })
        #expect(writer.ensureMarker() == .written)
        let rebuilt = loader(device).load()
        #expect(rebuilt.content?.origin == .v4)
        #expect(storage.sidecar?.epoch != epoch)
        #expect(storage.sidecar?.scopeArchive == Data("marker-new".utf8))
    }

    // MARK: The app-only writer

    @Test func writerCreatesAMarkerOnlyWhenAbsentAndFlushesIt() {
        let store = MarkerKeyValueStore()
        let writer = CompanionKVSScopeMarkerWriter(store: store, makeMarker: { "marker-1" })
        #expect(writer.ensureMarker() == .written)
        #expect(store.marker == "marker-1")
        #expect(store.mutations == 1)
        // Synchronized before the presence check and after the write, so the widget sees it.
        #expect(store.synchronizations == 2)
        #expect(writer.ensureMarker() == .present)
        #expect(store.mutations == 1)
    }

    @Test func writerNeverRewritesAnExistingValue() {
        let store = MarkerKeyValueStore()
        store.marker = "marker-existing"
        let writer = CompanionKVSScopeMarkerWriter(store: store, makeMarker: {
            "marker-\(UUID().uuidString)"
        })
        for _ in 0..<3 {
            #expect(writer.ensureMarker() == .present)
        }
        #expect(store.marker == "marker-existing")
        #expect(store.mutations == 0)

        // Present but unreadable as Data (another type): still present, still never rewritten.
        let opaque = MarkerKeyValueStore()
        opaque.seedOpaque(CompanionSyncKeys.scopeMarker)
        #expect(CompanionKVSScopeMarkerWriter(store: opaque).ensureMarker() == .present)
        #expect(opaque.mutations == 0)
        // Empty or oversized values are present too: unavailable to readers, never replaced.
        let empty = MarkerKeyValueStore()
        empty.seed(CompanionSyncKeys.scopeMarker, Data())
        #expect(CompanionKVSScopeMarkerWriter(store: empty).ensureMarker() == .present)
        #expect(empty.mutations == 0)
    }

    @Test func writerMintsAFreshRandomUUIDByDefault() throws {
        let first = MarkerKeyValueStore()
        let second = MarkerKeyValueStore()
        _ = CompanionKVSScopeMarkerWriter(store: first).ensureMarker()
        _ = CompanionKVSScopeMarkerWriter(store: second).ensureMarker()
        let a = try #require(first.marker)
        #expect(UUID(uuidString: a)?.uuidString == a)
        #expect(a != second.marker)
    }

    @Test func aRejectedLocalWriteIsReportedAndRetriedNextTime() {
        let store = MarkerKeyValueStore()
        store.rejectsWrites = true
        let writer = CompanionKVSScopeMarkerWriter(store: store, makeMarker: { "marker-1" })
        #expect(writer.ensureMarker() == .rejected)
        #expect(store.marker == nil)
        store.rejectsWrites = false
        #expect(writer.ensureMarker() == .written)
    }

    @Test(arguments: [iCloudKeyValueChangeReason.initialSyncChange, .accountChange])
    func writerDefersWhileAnInitialSyncIsInFlight(reason: iCloudKeyValueChangeReason) {
        let store = MarkerKeyValueStore()
        let clock = MarkerClock(F.date(0).date)
        let writer = CompanionKVSScopeMarkerWriter(
            store: store, now: { clock.now }, makeMarker: { "marker-1" })
        writer.record(iCloudKeyValueChange(reason: reason, changedKeys: []))
        #expect(writer.ensureMarker() == .deferredForInitialSync)
        #expect(store.mutations == 0)
        clock.now = clock.now.addingTimeInterval(CompanionKVSScopeMarkerWriter.initialSyncDeferral - 1)
        #expect(writer.ensureMarker() == .deferredForInitialSync)
        // The downloaded store may already carry the account's marker: then nothing is written.
        clock.now = clock.now.addingTimeInterval(2)
        store.marker = "marker-downloaded"
        #expect(writer.ensureMarker() == .present)
        #expect(store.marker == "marker-downloaded")
        #expect(store.mutations == 0)
    }

    @Test func otherChangeReasonsDoNotDefer() {
        let store = MarkerKeyValueStore()
        let writer = CompanionKVSScopeMarkerWriter(store: store, makeMarker: { "marker-1" })
        for reason in [iCloudKeyValueChangeReason.serverChange, .quotaViolationChange, .unknown] {
            writer.record(iCloudKeyValueChange(reason: reason, changedKeys: []))
        }
        #expect(writer.ensureMarker() == .written)
    }

    /// Two devices both see no marker and write; KVS keeps the last writer. The losing device
    /// invalidates exactly once more, then stays stable, and neither writer rewrites again.
    @Test func twoWriterRaceCostsAtMostOneExtraInvalidation() throws {
        let phone = MarkerKeyValueStore()
        let pad = MarkerKeyValueStore()
        let phoneStorage = MemoryCacheStorage()
        let phoneWriter = CompanionKVSScopeMarkerWriter(store: phone, makeMarker: { "marker-phone" })
        let padWriter = CompanionKVSScopeMarkerWriter(store: pad, makeMarker: { "marker-pad" })
        #expect(phoneWriter.ensureMarker() == .written)
        #expect(padWriter.ensureMarker() == .written)

        var epochs: [String] = []
        func phoneLoad() throws {
            _ = loader(phone, storage: phoneStorage).load()
            let epoch = try #require(phoneStorage.sidecar?.epoch)
            if epochs.last != epoch { epochs.append(epoch) }
        }
        try phoneLoad()  // establishes the phone's first scope
        try phoneLoad()
        #expect(epochs.count == 1)

        // Sync settles on the pad's value (last writer wins) on both devices.
        phone.replace(with: pad)
        try phoneLoad()
        #expect(phoneWriter.ensureMarker() == .present)
        #expect(padWriter.ensureMarker() == .present)
        try phoneLoad()
        try phoneLoad()
        #expect(epochs.count == 2)
        #expect(phone.marker == "marker-pad")
    }

    // MARK: Key placement

    @Test func theMarkerLivesOutsideEverySweptNamespace() {
        let key = CompanionSyncKeys.scopeMarker
        #expect(key == "headroom.scope.v1")
        #expect(CompanionKVSScopeMarker.key == key)
        #expect(!key.hasPrefix(CompanionSyncKeys.namespace))
        #expect(!key.hasPrefix("headroom.sync"))
        #expect(key.utf8.count <= CompanionSyncKeys.maximumKeyBytes)
        let store = accountA()
        #expect(!store.keys(withPrefix: CompanionSyncKeys.namespace).contains(key))
        // A v4 prefix sweep (KTD22 sync-off) leaves the marker in place.
        for swept in store.keys(withPrefix: CompanionSyncKeys.namespace) { store.removeValue(forKey: swept) }
        #expect(store.marker == "marker-a")
    }

    // MARK: Adoption-on composition

    @Test func adoptedSourceSynchronizesThenChecksTheMarkerOnEveryLoad() throws {
        let device = accountA()
        let source = CompanionPhoneSnapshotSource.adopted(
            store: device,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: anchor),
                scope: CompanionKVSScopeMarker(store: device)),
            now: { F.date(60).date }, demo: nil)
        #expect(source.load().content?.origin == .v4)
        #expect(device.synchronizations == 1)
        #expect(device.mutations == 0)  // a present marker is never rewritten

        let accountB = MarkerKeyValueStore()
        accountB.marker = "marker-b"
        device.replace(with: accountB)
        #expect(source.load().content == nil)
        #expect(device.synchronizations == 2)
        #expect(!hasCachedContent())
    }

    /// After an update, a placed widget can load before the app ever runs: whichever phone process
    /// loads first creates the marker, and a new scope serves no earlier cached content.
    @Test func adoptedSourceCreatesAMissingMarkerBeforeItsFirstLoad() throws {
        let device = accountA(marker: nil)
        let source = CompanionPhoneSnapshotSource.adopted(
            store: device,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: anchor),
                scope: CompanionKVSScopeMarker(store: device)),
            now: { F.date(60).date }, demo: nil)
        #expect(device.marker == nil)
        #expect(source.load().content?.origin == .v4)
        #expect(device.marker != nil)
        let written = device.marker
        _ = source.load()
        #expect(device.marker == written)  // never rewritten once present
    }

    /// An initial-sync notice defers the write, so the first download can't race a new marker.
    @Test func adoptedSourceDefersTheMarkerAfterAnInitialSyncNotice() throws {
        let device = accountA(marker: nil)
        let source = CompanionPhoneSnapshotSource.adopted(
            store: device,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: anchor),
                scope: CompanionKVSScopeMarker(store: device)),
            now: { F.date(60).date }, demo: nil)
        source.handle(iCloudKeyValueChange(reason: .initialSyncChange, changedKeys: []))
        #expect(source.load().state == .accountScopeUnavailable)
        #expect(device.marker == nil)
    }

    @Test func adoptedSourceForwardsAccountChangesToTheLoader() throws {
        let device = accountA()
        let source = CompanionPhoneSnapshotSource.adopted(
            store: device,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: anchor),
                scope: CompanionKVSScopeMarker(store: device)),
            now: { F.date(60).date }, demo: nil)
        _ = source.load()
        #expect(hasCachedContent())
        source.handle(iCloudKeyValueChange(reason: .serverChange, changedKeys: []))
        #expect(hasCachedContent())
        source.handle(iCloudKeyValueChange(reason: .accountChange, changedKeys: []))
        #expect(!hasCachedContent())
    }

    @Test func adoptedDemoNeverTouchesICloud() {
        let device = accountA()
        let demo = CompanionResolvedSnapshot(state: .paused)
        let source = CompanionPhoneSnapshotSource.adopted(
            store: device,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: anchor),
                scope: CompanionKVSScopeMarker(store: device)),
            demo: { demo })
        #expect(source.load() == demo)
        #expect(device.synchronizations == 0 && device.reads == 0)
        #expect(storage.writes.isEmpty)
    }

    @Test func adoptedSourceWithoutAnAppGroupServesNothing() {
        let device = accountA()
        let source = CompanionPhoneSnapshotSource.adopted(store: device, cache: nil, demo: nil)
        #expect(source.load().state == .accountScopeUnavailable)
        #expect(device.reads == 0)
    }
}
