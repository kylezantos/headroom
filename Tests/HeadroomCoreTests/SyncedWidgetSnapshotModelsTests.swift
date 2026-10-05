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

    @Test func currentSnapshotSchemaRejectsFreshnessBlindClientsButAcceptsLegacyPayloads() throws {
        #expect(WidgetSnapshotEnvelope.schemaVersion == 3)
        #expect(SyncedWidgetSnapshotEnvelope.schemaVersion == 1)

        let decoded = SyncedWidgetSnapshotCodec.decode(try legacyData(schemaVersion: 1))

        #expect(decoded.envelope?.snapshot.schemaVersion == 1)
        #expect(decoded.envelope?.snapshot.providers.first?.windows.first?.resetSchedule == .scheduled(reset))
        #expect(decoded.envelope?.snapshot.providers.first?.windows.first?.utilization == nil)
    }

    @Test func legacyWidgetSentinelsMigrateWithoutInventingResetEvidence() throws {
        for schemaVersion in [1, 2] {
            let decoded = SyncedWidgetSnapshotCodec.decode(
                try legacyData(schemaVersion: schemaVersion, usesSentinelReset: true)
            )
            let window = try #require(decoded.envelope?.snapshot.providers.first?.windows.first)

            #expect(window.resetSchedule == .unresolved(.legacyUnknown))
            #expect(window.utilization == nil)
            #expect(window.observedAt == generatedAt)
            #expect(Countdown.resetText(schedule: window.resetSchedule, utilization: window.utilization, isLive: window.freshness.isLive, now: generatedAt) == "Reset info unavailable")
        }
    }

    @Test func futureSnapshotSchemaIsIncompatible() throws {
        let futureSnapshot = WidgetSnapshotEnvelope(
            schemaVersion: WidgetSnapshotEnvelope.schemaVersion + 1,
            generatedAt: generatedAt,
            status: .enabled,
            providers: []
        )
        let envelope = makeSyncedEnvelope(snapshot: futureSnapshot)

        #expect(
            SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))
                == .incompatibleSchema
        )
    }

    @Test func windowEncodingKeepsLegacyIDAndMissingFreshnessDefaultsToLive() throws {
        let window = liveSnapshot.providers[0].windows[0]
        let encoded = try JSONEncoder().encode(window)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["id"] as? String == window.id)
        object.removeValue(forKey: "freshness")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WidgetWindowSummary.self, from: legacyData)

        #expect(decoded.id == window.id)
        #expect(decoded.freshness == .live)
    }

    @Test func billingPeriodUsesAdditiveV2Discriminator() throws {
        #expect(WidgetSnapshotEnvelope.schemaVersion == 3)
        let window = WidgetWindowSummary(
            kind: .other("Monthly"),
            label: "Monthly",
            percentRemaining: 64,
            resetsAt: reset,
            resetLabel: nil,
            severity: .healthy,
            freshness: .stale(observedAt: generatedAt),
            billingPeriodDuration: 30 * 24 * 60 * 60
        )

        let encoded = try JSONEncoder().encode(window)
        let decoded = try JSONDecoder().decode(WidgetWindowSummary.self, from: encoded)
        #expect(decoded.isBillingPeriod)
        #expect(decoded.isSubscriptionWindow)
        #expect(decoded.freshness == .stale(observedAt: generatedAt))

        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "billingPeriodDuration")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(WidgetWindowSummary.self, from: legacyData)
        #expect(legacy.kind == .other("Monthly"))
        #expect(!legacy.isBillingPeriod)
        #expect(!legacy.isSubscriptionWindow)
        #expect(legacy.freshness == .stale(observedAt: generatedAt))
    }

    @Test func unresolvedV3WindowEncodesNoDeadlineAndPreservesExactEvidence() throws {
        let observedAt = generatedAt.addingTimeInterval(-60)
        let window = WidgetWindowSummary(
            kind: .fiveHour,
            label: "5h",
            percentRemaining: 100,
            utilization: 0,
            resetSchedule: .unresolved(.absent),
            resetLabel: nil,
            observedAt: observedAt,
            severity: .healthy
        )

        let data = try JSONEncoder().encode(window)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["resetKind"] as? String == "unresolved")
        #expect(object["resetReason"] as? String == "absent")
        #expect(object["resetDeadline"] == nil)

        let decoded = try JSONDecoder().decode(WidgetWindowSummary.self, from: data)
        #expect(decoded.resetSchedule == .unresolved(.absent))
        #expect(decoded.utilization == 0)
        #expect(decoded.observedAt == observedAt)
    }

    @Test func unsupportedInnerSchemaWinsOverMalformedPayload() {
        let payload = """
        {
          "schemaVersion": 1,
          "publishedAt": 2100,
          "sourceID": "test-mac",
          "sourcePlatform": "macOS",
          "snapshot": {
            "schemaVersion": 999,
            "generatedAt": "malformed-on-purpose",
            "status": {"not": "valid"},
            "providers": "not-an-array"
          }
        }
        """

        #expect(SyncedWidgetSnapshotCodec.decode(Data(payload.utf8)) == .incompatibleSchema)
    }

    @Test func liveSnapshotWithAPISpendRoundTrips() throws {
        let envelope = makeSyncedEnvelope(snapshot: liveSnapshotWithAPISpend)

        let decoded = SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))

        #expect(decoded == .snapshot(envelope))
        #expect(decoded.envelope?.snapshot.apiSpendProviders.first?.displayName == "OpenAI API")
        #expect(decoded.envelope?.snapshot.apiSpendProviders.first?.amount == 19.25)
    }

    @Test func widgetProviderSelectionSurvivesSyncAndLegacyPayloadFallsBack() throws {
        let selected = WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: liveSnapshot.providers,
            widgetProviderSelection: ["claude"]
        )
        let decoded = SyncedWidgetSnapshotCodec.decode(
            try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: selected))
        )

        #expect(decoded.envelope?.snapshot.widgetProviderSelection == ["claude"])
        #expect(decoded.envelope?.snapshot.widgetProviders.map(\.id) == ["claude"])

        let legacy = SyncedWidgetSnapshotCodec.decode(try legacyData(schemaVersion: 2))

        #expect(legacy.envelope?.snapshot.widgetProviderSelection == nil)
        #expect(legacy.envelope?.snapshot.widgetProviders.map(\.id) == ["claude"])
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

    @Test func legacyWidgetSnapshotWithoutAPISpendDecodesWithEmptySpendList() throws {
        let legacyPayload = """
        {
          "schemaVersion": 1,
          "publishedAt": 2100,
          "sourceID": "test-mac",
          "sourcePlatform": "macOS",
          "snapshot": {
            "schemaVersion": 1,
            "generatedAt": 2000,
            "status": "enabled",
            "providers": []
          }
        }
        """

        let decoded = SyncedWidgetSnapshotCodec.decode(Data(legacyPayload.utf8))

        #expect(decoded.envelope?.snapshot.apiSpendProviders == [])
    }

    @Test func unsupportedSchemaReturnsIncompatible() throws {
        let envelope = makeSyncedEnvelope(schemaVersion: 999, snapshot: liveSnapshot)

        let decoded = SyncedWidgetSnapshotCodec.decode(try JSONEncoder().encode(envelope))

        #expect(decoded == .incompatibleSchema)
    }

    @Test func encodedPayloadContainsNoKnownSecretStrings() throws {
        let data = try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: liveSnapshot))
        // U4 (V8): the v4 manifest and provider keys pass the same scan.
        let provider = CompanionFixtures.bytes(
            CompanionFixtures.payload(extras: [CompanionFixtures.account("x1", title: "Work")]))
        let manifest = CompanionFixtures.bytes(
            CompanionFixtures.manifest(entries: ["claude": CompanionFixtures.entry(provider, generation: 1)]))
        let payload = [data, provider, manifest].map { String(decoding: $0, as: UTF8.self) }.joined()

        #expect(!payload.contains("access_token"))
        #expect(!payload.contains("refresh_token"))
        #expect(!payload.contains("/Users/"))
        #expect(!payload.contains("Claude Code-credentials"))
        #expect(!payload.contains("Authorization"))
        #expect(!payload.contains("x-api-key"))
        #expect(!payload.contains("api.openai.com"))
        #expect(!payload.contains("api.anthropic.com"))
    }

    @Test func newestValidKeepsLocalWhenRemoteIsOlderOrInvalid() {
        let local = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), snapshot: liveSnapshot)
        let older = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 5), snapshot: .disabled(generatedAt: generatedAt))

        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .snapshot(older)) == .snapshot(local))
        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .corrupt) == .snapshot(local))
    }

    @Test func newestValidSurfacesIncompatibleRemoteWithoutFallingBack() {
        let local = makeSyncedEnvelope(snapshot: liveSnapshot)

        #expect(
            SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .incompatibleSchema)
                == .incompatibleSchema
        )
    }

    @Test func newestValidUsesRemoteWhenNewer() {
        let local = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), snapshot: liveSnapshot)
        let newer = makeSyncedEnvelope(
            publishedAt: Date(timeIntervalSince1970: 11),
            snapshot: .disabled(generatedAt: generatedAt.addingTimeInterval(1))
        )

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

    private var liveSnapshotWithAPISpend: WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: [],
            apiSpendProviders: [
                WidgetAPISpendSummary(
                    id: "codex",
                    displayName: "OpenAI API",
                    amount: 19.25,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: generatedAt,
                    freshness: .live
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

    private func legacyData(schemaVersion: Int, usesSentinelReset: Bool = false) throws -> Data {
        let encoded = try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: liveSnapshot))
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var snapshot = try #require(root["snapshot"] as? [String: Any])
        snapshot["schemaVersion"] = schemaVersion
        snapshot.removeValue(forKey: "widgetProviderSelection")
        var providers = try #require(snapshot["providers"] as? [[String: Any]])
        for providerIndex in providers.indices {
            var windows = try #require(providers[providerIndex]["windows"] as? [[String: Any]])
            for windowIndex in windows.indices {
                windows[windowIndex]["resetsAt"] = usesSentinelReset
                    ? snapshot["generatedAt"]
                    : windows[windowIndex]["resetDeadline"]
                windows[windowIndex].removeValue(forKey: "resetKind")
                windows[windowIndex].removeValue(forKey: "resetDeadline")
                windows[windowIndex].removeValue(forKey: "resetReason")
                windows[windowIndex].removeValue(forKey: "utilization")
                windows[windowIndex].removeValue(forKey: "resetTimeZoneIdentifier")
                windows[windowIndex].removeValue(forKey: "observedAt")
            }
            providers[providerIndex]["windows"] = windows
        }
        snapshot["providers"] = providers
        root["snapshot"] = snapshot
        return try JSONSerialization.data(withJSONObject: root)
    }
}
