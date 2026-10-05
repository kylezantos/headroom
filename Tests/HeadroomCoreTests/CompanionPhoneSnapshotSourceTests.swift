import Foundation
import Testing

@testable import HeadroomCore

/// Characterizes build 33's phone loading path as `IOSCompanionView.refresh()` (`.appRefresh`)
/// and `HeadroomIOSTimelineProvider.resolvedState()` (`.widgetTimeline`) run it today, then
/// the shared source's lift through the resolver's v3-only rules (U4b, KTD6.5, KTD6.7).
@Suite
struct CompanionPhoneSnapshotSourceTests {
    typealias F = CompanionFixtures
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("headroom-phone-source-tests-\(UUID().uuidString)", isDirectory: true)

    private var cacheURL: URL { directory.appendingPathComponent("widget-snapshot.json") }
    private var cache: WidgetSnapshotCache { WidgetSnapshotCache(defaults: nil, fileURL: cacheURL) }

    private func store(_ v3: SyncedWidgetSnapshotEnvelope?) -> SpyKeyValueStore {
        let store = SpyKeyValueStore()
        store.seed(iCloudSnapshotSync.snapshotKey, v3.map(F.v3Bytes))
        return store
    }

    private func load(
        _ store: (any iCloudKeyValueSyncing)?, rule: CompanionBuild33Loading.AdoptionRule = .appRefresh,
        cache: WidgetSnapshotCache? = nil
    ) -> CompanionBuild33Loading.Outcome {
        CompanionBuild33Loading.load(sync: iCloudSnapshotSync(store: store), cache: cache ?? self.cache, rule: rule)
    }

    private func cached() -> WidgetSnapshotEnvelope? { cache.read().envelope }

    private func cleanup() { try? FileManager.default.removeItem(at: directory) }

    // MARK: Adoption rules (characterization)

    @Test func adoptionRulesMatchEachHost() {
        let older = F.v3(generatedAt: 0).snapshot
        let newer = F.v3(generatedAt: 60).snapshot
        let sameTimeDifferent = F.v3(generatedAt: 0, providers: [F.v3Provider(remaining: 10)]).snapshot
        for rule in [CompanionBuild33Loading.AdoptionRule.appRefresh, .widgetTimeline] {
            #expect(CompanionBuild33Loading.adoptable(remote: older, into: .empty, rule: rule))
            #expect(CompanionBuild33Loading.adoptable(remote: older, into: .corrupt, rule: rule))
            #expect(CompanionBuild33Loading.adoptable(remote: newer, into: .snapshot(older), rule: rule))
            #expect(!CompanionBuild33Loading.adoptable(remote: older, into: .snapshot(newer), rule: rule))
            #expect(!CompanionBuild33Loading.adoptable(remote: older, into: .snapshot(older), rule: rule))
        }
        // The hosts' one disagreement: a same-time remote with different content.
        #expect(CompanionBuild33Loading.adoptable(remote: sameTimeDifferent, into: .snapshot(older), rule: .appRefresh))
        #expect(!CompanionBuild33Loading.adoptable(remote: sameTimeDifferent, into: .snapshot(older), rule: .widgetTimeline))
    }

    @Test func newerKeyIsWrittenBackAndEachHostResolvesItsOwnWay() throws {
        defer { cleanup() }
        try cache.write(F.v3(generatedAt: 0).snapshot)
        let remote = F.v3(generatedAt: 60, lineage: (F.macA, 4))

        let app = load(store(remote), rule: .appRefresh)
        #expect(app.adoptedRemote)
        #expect(cached() == remote.snapshot)
        // The app re-reads after the write, so the tie resolves to the (now equal) cache.
        #expect(app.resolution == IOSWidgetResolution(state: .content(remote.snapshot), origin: .cache))

        try cache.write(F.v3(generatedAt: 0).snapshot)
        let widget = load(store(remote), rule: .widgetTimeline)
        #expect(widget.adoptedRemote)
        #expect(cached() == remote.snapshot)
        // The widget resolves against its pre-write read: the key wins on recency.
        #expect(widget.resolution == IOSWidgetResolution(state: .content(remote.snapshot), origin: .sync))
        #expect(widget.cacheRead == .snapshot(F.v3(generatedAt: 0).snapshot))
    }

    @Test func olderKeyNeverOverwritesANewerCache() throws {
        defer { cleanup() }
        let newer = F.v3(generatedAt: 120).snapshot
        try cache.write(newer)
        for rule in [CompanionBuild33Loading.AdoptionRule.appRefresh, .widgetTimeline] {
            let outcome = load(store(F.v3(generatedAt: 0)), rule: rule)
            #expect(!outcome.adoptedRemote)
            #expect(cached() == newer)
            #expect(outcome.resolution == IOSWidgetResolution(state: .content(newer), origin: .cache))
        }
    }

    /// Review 2 #3: the phone's loads overlap (the app runs each one detached), and the widget
    /// and intents processes load too. A load that read an older key and the old cache, then
    /// reaches its write after a newer load has already written, must leave the newer
    /// envelope in place. The older load parks between its reads and its write.
    @Test(arguments: [CompanionBuild33Loading.AdoptionRule.appRefresh, .widgetTimeline])
    func anOlderLoadFinishingLastNeverOverwritesTheNewerCache(rule: CompanionBuild33Loading.AdoptionRule) throws {
        defer { cleanup() }
        try cache.write(F.v3(generatedAt: 0).snapshot)
        let older = F.v3(generatedAt: 60, lineage: (F.macA, 4))
        let newer = F.v3(generatedAt: 120, lineage: (F.macA, 5))
        let anchor = SharedAnchor()
        let parked = BarrierCoordinator(anchor: anchor, gatedEntry: 1)
        let olderStore = store(older)
        let cache = self.cache
        let olderLoad = ThreadResult {
            CompanionBuild33Loading.load(
                sync: iCloudSnapshotSync(store: olderStore), cache: cache, rule: rule, coordinator: parked)
        }
        parked.arrived.wait()

        let newerLoad = CompanionBuild33Loading.load(
            sync: iCloudSnapshotSync(store: store(newer)), cache: cache, rule: rule,
            coordinator: BarrierCoordinator(anchor: anchor))
        #expect(newerLoad.adoptedRemote)
        #expect(cached() == newer.snapshot)

        parked.gate.signal()
        let late = olderLoad.wait()
        #expect(cached() == newer.snapshot, "the older key never replaces the newer cache")
        if rule == .appRefresh {
            // The app's rule re-reads what the transaction left, so it serves the newer cache.
            #expect(late.resolution == IOSWidgetResolution(state: .content(newer.snapshot), origin: .cache))
        }
        // Build 33's bytes are unchanged: the file is the newer key's inner envelope.
        #expect(try JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: Data(contentsOf: cacheURL)) == newer.snapshot)
    }

    /// A failed coordination writes nothing rather than replace the file uncoordinated; the
    /// load still resolves the newer key over the cache it read.
    @Test func aFailedCoordinationWritesNothing() throws {
        defer { cleanup() }
        let old = F.v3(generatedAt: 0).snapshot
        try cache.write(old)
        let failing = BarrierCoordinator(anchor: SharedAnchor())
        failing.fails = true
        let remote = F.v3(generatedAt: 60)
        let outcome = CompanionBuild33Loading.load(
            sync: iCloudSnapshotSync(store: store(remote)), cache: cache, rule: .appRefresh, coordinator: failing)
        #expect(cached() == old)
        #expect(outcome.resolution == IOSWidgetResolution(state: .content(remote.snapshot), origin: .sync))
    }

    @Test func missingOrCorruptKeyFallsBackToTheCache() throws {
        defer { cleanup() }
        let content = F.v3(generatedAt: 0).snapshot
        try cache.write(content)
        let corrupt = SpyKeyValueStore()
        corrupt.seed(iCloudSnapshotSync.snapshotKey, Data("{".utf8))
        for kvs in [store(nil), corrupt] {
            let outcome = load(kvs)
            #expect(outcome.resolution == IOSWidgetResolution(state: .content(content), origin: .cache))
            #expect(!outcome.adoptedRemote)
        }
    }

    @Test func nonContentStatesMatchBuild33() throws {
        defer { cleanup() }
        #expect(load(store(nil)).resolution.state == .waitingForMac)
        let corrupt = SpyKeyValueStore()
        corrupt.seed(iCloudSnapshotSync.snapshotKey, Data("{".utf8))
        #expect(load(corrupt).resolution.state == .corrupt)
        // No App Group container: "iCloud Not Available".
        let noContainer = WidgetSnapshotCache(defaults: nil, fileURL: nil)
        #expect(load(store(nil), cache: noContainer).resolution.state == .setupNeeded)
        // A content-bearing key still wins without a container.
        #expect(load(store(F.v3()), cache: noContainer).resolution.state == .content(F.v3().snapshot))
        // A disabled winner is the paused screen.
        #expect(load(store(F.v3(generatedAt: 60, status: .disabled))).resolution.state == .disabled)
    }

    @Test func anIncompatibleCacheBlocksContentAndIsNeverOverwritten() throws {
        defer { cleanup() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = Data(#"{"schemaVersion":99,"generatedAt":0,"status":"enabled","providers":[]}"#.utf8)
        try future.write(to: cacheURL)
        let outcome = load(store(F.v3(generatedAt: 60)))
        #expect(outcome.adoptedRemote)
        #expect(try Data(contentsOf: cacheURL) == future)
        #expect(outcome.resolution.state == .incompatibleSchema)
    }

    // MARK: Lift through the resolver's v3-only rules

    private func lift(_ outcome: CompanionBuild33Loading.Outcome) -> CompanionResolvedSnapshot {
        CompanionBuild33Loading.lift(outcome, now: F.date(30).date)
    }

    @Test func aKeyWinnerLiftsToOneAccountPerProviderWithItsLineage() throws {
        defer { cleanup() }
        let remote = F.v3(
            generatedAt: 60, providers: [F.v3Provider(), F.v3Provider("codex", remaining: 12)],
            lineage: (F.macA, 9))
        let snapshot = lift(load(store(remote)))
        let content = try #require(snapshot.content)
        #expect(content.origin == .v3)
        #expect(content.notice == nil)
        #expect(content.sourceID == F.macA && content.generation == 9)
        #expect(content.display == nil)
        #expect(content.providers.map(\.id) == ["claude", "codex"])
        #expect(content.providers.allSatisfy { $0.accounts.count == 1 && $0.source == .v3Main })
        #expect(content.freshness.isV3Only)
        #expect(content.freshness.generatedAt == remote.snapshot.generatedAt)
        #expect(snapshot.primaryProjection()?.providers.map(\.id) == ["claude", "codex"])
        #expect(snapshot.primaryProjection()?.generatedAt == remote.snapshot.generatedAt)
    }

    @Test func aLineagelessKeyFromAnOldMacCarriesTheUpdateMacLine() throws {
        defer { cleanup() }
        let content = try #require(lift(load(store(F.v3(generatedAt: 60)))).content)
        #expect(content.notice == .updateMac)
    }

    /// The compatibility file carries no lineage: a cache-only winner is no evidence of an old
    /// Mac, so it never claims "Update Headroom on your Mac".
    @Test func aCacheOnlyWinnerNeverClaimsAnOldMac() throws {
        defer { cleanup() }
        try cache.write(F.v3(generatedAt: 0).snapshot)
        let content = try #require(lift(load(store(nil))).content)
        #expect(content.origin == .v3)
        #expect(content.notice == nil)
        #expect(content.sourceID == nil)
        #expect(content.providers.map(\.id) == ["claude"])
    }

    @Test func aCacheWinnerEqualToTheKeyKeepsTheKeysLineage() throws {
        defer { cleanup() }
        let remote = F.v3(generatedAt: 60, lineage: (F.macB, 3))
        try cache.write(remote.snapshot)
        let outcome = load(store(remote))
        #expect(outcome.resolution.origin == .cache)
        let content = try #require(lift(outcome).content)
        #expect(content.sourceID == F.macB && content.generation == 3)
    }

    @Test func liftedNonContentStates() throws {
        defer { cleanup() }
        #expect(lift(load(store(nil))).state == .waiting(nil))
        let corrupt = SpyKeyValueStore()
        corrupt.seed(iCloudSnapshotSync.snapshotKey, Data("{".utf8))
        // U10: a corrupt key with no cached content is the Snapshot Unreadable screen.
        #expect(lift(load(corrupt)).state == .unreadable)
        let noContainer = WidgetSnapshotCache(defaults: nil, fileURL: nil)
        #expect(lift(load(store(nil), cache: noContainer)).state == .accountScopeUnavailable)
        // A disabled key is adopted into the cache, as build 33 does; it reads as paused.
        #expect(lift(load(store(F.v3(generatedAt: 60, status: .disabled)))).state == .paused)
        cleanup()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":99,"generatedAt":0,"status":"enabled","providers":[]}"#.utf8).write(to: cacheURL)
        #expect(lift(load(store(F.v3()))).state == .waiting(.updatePhone))
    }

    /// U10: "Snapshot Unreadable" means the Mac's key itself couldn't be read. Cached content
    /// still wins over a corrupt key (field contract), and a corrupt local file with no key
    /// is this device's problem, not the Mac's last update, so it keeps waiting.
    @Test func onlyACorruptKeyWithNothingCachedIsUnreadable() throws {
        defer { cleanup() }
        let corrupt = SpyKeyValueStore()
        corrupt.seed(iCloudSnapshotSync.snapshotKey, Data("{".utf8))
        try cache.write(F.v3(generatedAt: 0).snapshot)
        let content = try #require(lift(load(corrupt)).content)
        #expect(content.origin == .v3 && content.providers.map(\.id) == ["claude"])

        try Data("{".utf8).write(to: cacheURL)
        #expect(lift(load(store(nil))).state == .waiting(nil))
        #expect(lift(load(corrupt)).state == .unreadable)

        let source = CompanionPhoneSnapshotSource.build33(
            store: corrupt, compatibilityCache: WidgetSnapshotCache(defaults: nil, fileURL: directory.appendingPathComponent("absent.json")),
            now: { F.date(90).date }, demo: nil)
        #expect(source.load().state == .unreadable)
    }

    /// An older-schema envelope decodes into today's provider shape; the lift must not
    /// re-encode it under its old version number and lose it.
    @Test func anOlderSchemaWinnerSurvivesTheLift() throws {
        let v3 = F.v3(generatedAt: 60)
        let old = WidgetSnapshotEnvelope(
            schemaVersion: 2, generatedAt: v3.snapshot.generatedAt, status: .enabled,
            providers: v3.snapshot.providers)
        let outcome = CompanionBuild33Loading.Outcome(
            syncRead: .missing, cacheRead: .snapshot(old),
            resolution: IOSWidgetSnapshotState.resolve(cacheRead: .snapshot(old), syncRead: .missing),
            adoptedRemote: false)
        let content = try #require(lift(outcome).content)
        #expect(content.providers.map(\.id) == ["claude"])
    }

    // MARK: Source composition

    /// KTD22: Kyle approved the KVS marker on 2026-10-05, so phones load through the scoped
    /// loader; the build-33 path below stays the rollback.
    @Test func adoptionIsOn() {
        #expect(CompanionLoaderAdoption.isEnabled)
    }

    @Test func build33SourceWritesOnlyTheCompatibilityFileFromTheKey() throws {
        defer { cleanup() }
        let remote = F.v3(generatedAt: 60, lineage: (F.macA, 2))
        let kvs = store(remote)
        let source = CompanionPhoneSnapshotSource.build33(
            store: kvs, compatibilityCache: cache, now: { F.date(90).date }, demo: nil)
        let snapshot = source.load()
        #expect(snapshot.content?.origin == .v3)
        #expect(snapshot.content?.sourceID == F.macA)
        #expect(kvs.mutations == 0)
        // Build 33's bytes: the key's inner envelope, nothing projected from v4, no v4 file.
        #expect(try JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: Data(contentsOf: cacheURL)) == remote.snapshot)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["widget-snapshot.json"])
        // Later loads are stable and keep reading the key.
        #expect(source.load() == snapshot)
    }

    @Test func demoShortCircuitsBeforeICloudOrAnyCache() throws {
        defer { cleanup() }
        let kvs = store(F.v3())
        let demo = CompanionResolvedSnapshot(state: .waiting(nil), diagnostics: [.manifestGenerationReset])
        let source = CompanionPhoneSnapshotSource.build33(
            store: kvs, compatibilityCache: cache, demo: { demo })
        #expect(source.load() == demo)
        #expect(kvs.reads == 0 && kvs.mutations == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func aDemoClosureReturningNilFallsThroughToTheRealPath() throws {
        defer { cleanup() }
        let source = CompanionPhoneSnapshotSource.build33(
            store: store(F.v3()), compatibilityCache: cache, demo: { nil })
        #expect(source.load().content != nil)
    }

    @Test func testSeamForwardsLoadsAndChanges() {
        let seen = ChangeRecorder()
        let source = CompanionPhoneSnapshotSource(
            load: { CompanionResolvedSnapshot(state: .paused) }, handle: { seen.append($0) })
        #expect(source.load().state == .paused)
        source.handle(iCloudKeyValueChange(reason: .accountChange, changedKeys: []))
        #expect(seen.values.map(\.reason) == [.accountChange])
        // The load-only seam ignores changes.
        CompanionPhoneSnapshotSource(load: { CompanionResolvedSnapshot(state: .paused) })
            .handle(iCloudKeyValueChange(reason: .accountChange, changedKeys: []))
    }
}

final class ChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [iCloudKeyValueChange] = []
    var values: [iCloudKeyValueChange] { lock.withLock { recorded } }
    func append(_ change: iCloudKeyValueChange) { lock.withLock { recorded.append(change) } }
}

@Suite struct WidgetSnapshotEnvelopeSchemaStampTests {
    /// The cache writes the compatibility file from a decoded envelope; an older inner schema
    /// must come back out readable, not re-encoded under its old number in the new shape.
    @Test func anOlderSchemaEnvelopeReencodesReadably() throws {
        let old = WidgetSnapshotEnvelope(
            schemaVersion: 2, generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .enabled, providers: [])
        let bytes = try CompanionSyncCodec.encode(old.atCurrentSchema)
        let decoded = try JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: bytes)
        #expect(decoded.schemaVersion == WidgetSnapshotEnvelope.schemaVersion)
        #expect(decoded.generatedAt == old.generatedAt)
    }
}
