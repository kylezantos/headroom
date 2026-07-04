import Foundation
import Testing
@testable import HeadroomCore

struct SyncedWidgetSnapshotModelsTests {
    private let generatedAt = Date(timeIntervalSince1970: 2_000)
    private let publishedAt = Date(timeIntervalSince1970: 2_100)
    private let reset = Date(timeIntervalSince1970: 3_000)

    @Test func liveSnapshotRoundTrips() throws {
        let envelope = makeSyncedEnvelope(snapshot: liveSnapshot)

        let decoded = SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))

        #expect(decoded == .snapshot(envelope))
    }

    @Test func disabledSnapshotRoundTripsWithoutProviders() throws {
        let envelope = makeSyncedEnvelope(snapshot: .disabled(generatedAt: generatedAt))

        let decoded = SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))

        #expect(decoded.envelope?.snapshot.status == .disabled)
        #expect(decoded.envelope?.snapshot.providers.isEmpty == true)
    }

    @Test func unknownProviderAndWindowRoundTrip() throws {
        let snapshot = WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "future-provider",
                    displayName: "Future",
                    planLabel: nil,
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .other("daily"),
                            label: "Daily",
                            percentRemaining: 42,
                            resetsAt: reset,
                            resetLabel: nil,
                            severity: .healthy
                        ),
                    ],
                    renewalDate: nil
                ),
            ]
        )

        let decoded = SyncedWidgetSnapshotCodec.decode(
            try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: snapshot))
        )

        #expect(decoded.envelope?.snapshot.providers[0].id == "future-provider")
        #expect(decoded.envelope?.snapshot.providers[0].windows[0].kind == .other("daily"))
    }

    @Test func subscriptionWindowsFilterDecodedLegacyAllowanceWindows() {
        let provider = WidgetProviderSummary(
            id: "codex",
            displayName: "Codex",
            planLabel: nil,
            freshness: .live,
            windows: [
                WidgetWindowSummary(
                    kind: .weekly,
                    label: "Weekly",
                    percentRemaining: 75,
                    resetsAt: reset,
                    resetLabel: nil,
                    severity: .healthy
                ),
                WidgetWindowSummary(
                    kind: .other("GPT-5.3"),
                    label: "GPT-5.3",
                    percentRemaining: 10,
                    resetsAt: reset,
                    resetLabel: nil,
                    severity: .critical
                ),
            ],
            renewalDate: nil
        )

        #expect(provider.subscriptionWindows.map(\.kind) == [.weekly])
        #expect(provider.weeklyWindow?.percentRemaining == 75)
    }

    @Test func invalidDataReturnsCorrupt() {
        #expect(SyncedWidgetSnapshotCodec.decode(Data("not-json".utf8)) == .corrupt)
    }

    @Test func unsupportedSchemaReturnsIncompatible() throws {
        let envelope = makeSyncedEnvelope(schemaVersion: 999, snapshot: liveSnapshot)

        let decoded = SyncedWidgetSnapshotCodec.decode(try JSONEncoder().encode(envelope))

        #expect(decoded == .incompatibleSchema)
    }

    @Test func encodedPayloadContainsNoKnownSecretStrings() throws {
        let data = try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: liveSnapshot))
        let payload = String(decoding: data, as: UTF8.self)

        #expect(!payload.contains("access_token"))
        #expect(!payload.contains("refresh_token"))
        #expect(!payload.contains("/Users/"))
        #expect(!payload.contains("Claude Code-credentials"))
        #expect(!payload.contains("Authorization"))
    }

    @Test func newestValidKeepsLocalWhenRemoteIsOlderOrInvalid() {
        let local = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), snapshot: liveSnapshot)
        let older = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 5), snapshot: .disabled(generatedAt: generatedAt))

        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .snapshot(older)) == .snapshot(local))
        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .corrupt) == .snapshot(local))
    }

    @Test func newestValidUsesRemoteWhenNewer() {
        let local = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), snapshot: liveSnapshot)
        let newer = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 11), snapshot: .disabled(generatedAt: generatedAt))

        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .snapshot(newer)) == .snapshot(newer))
    }

    private var liveSnapshot: WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "claude",
                    displayName: "Claude",
                    planLabel: "max",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 80,
                            resetsAt: reset,
                            resetLabel: "Resets tomorrow",
                            severity: .healthy
                        ),
                    ],
                    renewalDate: nil
                ),
            ]
        )
    }

    private func makeSyncedEnvelope(
        schemaVersion: Int = SyncedWidgetSnapshotEnvelope.schemaVersion,
        publishedAt: Date? = nil,
        snapshot: WidgetSnapshotEnvelope
    ) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            schemaVersion: schemaVersion,
            publishedAt: publishedAt ?? self.publishedAt,
            sourceID: "test-mac",
            sourcePlatform: .macOS,
            snapshot: snapshot
        )
    }
}
