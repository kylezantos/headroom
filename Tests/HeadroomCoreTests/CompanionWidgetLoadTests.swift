import Foundation
import Testing
@testable import HeadroomCore

/// U13 (iOS parity plan): the iPhone widget loads through the shared phone source and takes
/// the resolver's primary-only projection plus its freshness inputs (KTD13, KTD15).
struct CompanionWidgetLoadTests {
    typealias F = CompanionFixtures
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("headroom-widget-load-tests-\(UUID().uuidString)", isDirectory: true)

    private func source(_ v3: SyncedWidgetSnapshotEnvelope?) -> CompanionPhoneSnapshotSource {
        let store = SpyKeyValueStore()
        store.seed(iCloudSnapshotSync.snapshotKey, v3.map(F.v3Bytes))
        return CompanionPhoneSnapshotSource.build33(
            store: store,
            compatibilityCache: WidgetSnapshotCache(defaults: nil, fileURL: directory.appendingPathComponent("widget-snapshot.json")),
            now: { Self.now }, demo: nil)
    }

    /// KTD13, run from the widget path: the shared source's lift, projected for the widget,
    /// equals what the Mac's v3 projector published, for every demo variant.
    @Test func theWidgetEnvelopeEqualsTheMacsV3ForEveryDemoVariant() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        for variant in ["full", "noSpend", "claudeOnly", "claudeOnlyNoSpend", "codexFiveHourReturns", "attention", "fourProviders"] {
            let inner = DemoScreenshotData.envelope(for: variant)
            let providers = inner.providers.map {
                WidgetProviderSummary(id: $0.id, displayName: $0.displayName, planLabel: $0.planLabel,
                                      freshness: $0.freshness, windows: $0.windows, renewalDate: nil)
            }
            let canonical = WidgetSnapshotEnvelope(
                generatedAt: CompanionWireDate.canonicalize(inner.generatedAt)!, status: inner.status,
                providers: providers, apiSpendProviders: inner.apiSpendProviders,
                widgetProviderSelection: inner.widgetProviderSelection)
            let v3 = SyncedWidgetSnapshotEnvelope(
                publishedAt: canonical.generatedAt, sourceID: "Mac", sourcePlatform: .macOS, snapshot: canonical,
                companionSourceID: F.macA, companionGeneration: 3)
            let decoded = try #require(SyncedWidgetSnapshotCodec.decode(F.v3Bytes(v3)).envelope)
            let load = CompanionWidgetLoad.from(source(v3).load(), isDemo: false)
            #expect(load.state == .content(decoded.snapshot), "variant \(variant)")
            // v3-only: the widget dims on the 120-minute rule against the Mac's publish time.
            #expect(load.freshness?.isV3Only == true)
            #expect(load.freshness?.generatedAt == decoded.snapshot.generatedAt)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func nonContentStatesMapToTheBuild33Cards() {
        #expect(CompanionWidgetLoad.from(CompanionResolvedSnapshot(state: .paused), isDemo: false)
            == CompanionWidgetLoad(state: .disabled, freshness: nil))
        #expect(CompanionWidgetLoad.from(CompanionResolvedSnapshot(state: .accountScopeUnavailable), isDemo: false).state == .setupNeeded)
        #expect(CompanionWidgetLoad.from(CompanionResolvedSnapshot(state: .waiting(nil)), isDemo: false).state == .waitingForMac)
        #expect(CompanionWidgetLoad.from(CompanionResolvedSnapshot(state: .waiting(.updateMac)), isDemo: false).state == .waitingForMac)
        #expect(CompanionWidgetLoad.from(CompanionResolvedSnapshot(state: .waiting(.updatePhone)), isDemo: false).state == .incompatibleSchema)
    }

    @Test func aMissingKeyWaitsForTheMac() {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(CompanionWidgetLoad.from(source(nil).load(), isDemo: false) == CompanionWidgetLoad(state: .waitingForMac, freshness: nil))
    }

    @Test func aDisabledMacShowsTheDisabledCard() {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(CompanionWidgetLoad.from(source(F.v3(status: .disabled)).load(), isDemo: false).state == .disabled)
    }

    /// R30: demo content wears the DEMO capsule and keeps its freshness, so the dimmed demo
    /// variant dims the widget the way it dims the app.
    @Test func demoSnapshotsAreDemoEntriesWithTheirFreshness() throws {
        let store = CompanionDemoModeStore(defaults: nil, now: { Self.now })
        for variant in [CompanionDemoVariant.multiAccount, .dimmed, .pastReset] {
            let snapshot = store.snapshot(variant)
            let content = try #require(snapshot.content)
            let load = CompanionWidgetLoad.from(snapshot, isDemo: true)
            #expect(load.state == .demo(try #require(snapshot.primaryProjection())))
            #expect(load.freshness == content.freshness)
        }
        let dimmed = try #require(CompanionWidgetLoad.from(store.snapshot(.dimmed), isDemo: true).freshness)
        #expect(CompanionFreshnessRule.isDimmed(dimmed, surface: .widget, at: Self.now))
        let fresh = try #require(CompanionWidgetLoad.from(store.snapshot(.multiAccount), isDemo: true).freshness)
        #expect(!CompanionFreshnessRule.isDimmed(fresh, surface: .widget, at: Self.now))
    }
}
