import Foundation
import Testing
@testable import HeadroomCore

struct IOSWidgetTimelineMappingTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func liveCacheMapsToContent() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot)) == .content(snapshot))
    }

    @Test func disabledCacheMapsToDisabled() {
        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(.disabled(generatedAt: now))) == .disabled)
    }

    @Test func emptyCacheFallsBackToRemoteSnapshot() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let synced = SyncedWidgetSnapshotEnvelope(
            publishedAt: now,
            sourceID: "mac",
            sourcePlatform: .macOS,
            snapshot: snapshot
        )

        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .snapshot(synced)) == .content(snapshot))
    }

    @Test func noLocalOrRemoteSnapshotWaitsForMac() {
        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .missing) == .waitingForMac)
    }

    @Test func corruptAndIncompatibleStatesAreTyped() {
        #expect(IOSWidgetSnapshotState.from(cacheRead: .corrupt) == .corrupt)
        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .incompatibleSchema) == .incompatibleSchema)
    }

    @Test func newerRemoteSnapshotWinsOverStaleCache() {
        let stale = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let fresh = WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(3_600), status: .enabled, providers: [])

        let resolution = IOSWidgetSnapshotState.resolve(
            cacheRead: .snapshot(stale),
            syncRead: .snapshot(synced(fresh))
        )
        #expect(resolution.state == .content(fresh))
        #expect(resolution.origin == .sync)
    }

    @Test func newerCacheWinsOverStaleRemote() {
        let fresh = WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(3_600), status: .enabled, providers: [])
        let stale = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        let resolution = IOSWidgetSnapshotState.resolve(
            cacheRead: .snapshot(fresh),
            syncRead: .snapshot(synced(stale))
        )
        #expect(resolution.state == .content(fresh))
        #expect(resolution.origin == .cache)
    }

    @Test func liveCacheSurvivesMissingOrCorruptSync() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot), syncRead: .missing) == .content(snapshot))
        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot), syncRead: .corrupt) == .content(snapshot))
    }

    @Test func newerRemoteDisabledSnapshotPausesOverStaleContent() {
        let stale = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let disabled = WidgetSnapshotEnvelope.disabled(generatedAt: now.addingTimeInterval(3_600))

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(stale), syncRead: .snapshot(synced(disabled))) == .disabled)
    }

    private func synced(_ snapshot: WidgetSnapshotEnvelope) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            publishedAt: now,
            sourceID: "mac",
            sourcePlatform: .macOS,
            snapshot: snapshot
        )
    }
}
