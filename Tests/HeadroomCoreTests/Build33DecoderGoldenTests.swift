import Foundation
import Testing

@testable import HeadroomCore

/// KTD5 / V1: the v3 key a 1.5 Mac emits, including the additive lineage pair, must
/// decode in the frozen pre-parity schema-3 reader (see Build33FrozenDecoder.swift for
/// its honest provenance: comparator 06d082af, not a proven archive source).
@Suite
struct Build33DecoderGoldenTests {
    static let macID = "6f1c2c1e-1b7a-4d6b-9d55-8f6f3b8f2a01"
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func goldenModel() -> SyncedWidgetSnapshotEnvelope {
        let fable = WidgetWindowSummary(
            kind: .other("Weekly (Fable)"), label: "Weekly (Fable)", percentRemaining: 72.3,
            utilization: 27.654321, resetSchedule: .scheduled(t0.addingTimeInterval(86_400)),
            resetLabel: nil, observedAt: t0.addingTimeInterval(-3_600), severity: .healthy,
            freshness: .unavailable(since: t0.addingTimeInterval(-600)))
        let claude = WidgetProviderSummary(
            id: "claude", displayName: "Claude", planLabel: "Max", freshness: .live,
            windows: [
                WidgetWindowSummary(
                    kind: .fiveHour, label: "5h", percentRemaining: 15.1, utilization: 84.95,
                    resetSchedule: .scheduled(t0.addingTimeInterval(3_600)), resetLabel: nil,
                    observedAt: t0, severity: .low),
                fable,
            ],
            renewalDate: nil)
        let grok = WidgetProviderSummary(
            id: "grok", displayName: "Grok", planLabel: nil, freshness: .live,
            windows: [
                WidgetWindowSummary(
                    kind: .other("Weekly"), label: "Weekly", percentRemaining: 56, utilization: 44,
                    resetSchedule: .unresolved(.absent), resetLabel: nil, observedAt: t0,
                    severity: .healthy, billingPeriodDuration: 604_800)
            ],
            renewalDate: nil)
        let cursor = WidgetProviderSummary(
            id: "cursor", displayName: "Cursor", planLabel: "Pro",
            freshness: .stale(message: CompanionAttentionCopy.account(.retrying), needsAttention: false),
            windows: [], renewalDate: nil)
        let spend = WidgetAPISpendSummary(
            id: "claude", displayName: "Anthropic", amount: 12.5, currency: "USD",
            periodLabel: "Oct 1 – Oct 31", kind: .periodSpend, capturedAt: t0.addingTimeInterval(-120),
            freshness: .stale(message: CompanionAttentionCopy.spend(.keyRejected), needsAttention: true),
            attention: .keyRejected)
        return SyncedWidgetSnapshotEnvelope(
            publishedAt: t0, sourceID: "Mac", sourcePlatform: .macOS,
            snapshot: WidgetSnapshotEnvelope(
                generatedAt: t0, status: .enabled, providers: [claude, grok, cursor],
                apiSpendProviders: [spend], widgetProviderSelection: ["claude", "grok"]),
            companionSourceID: macID, companionGeneration: 42)
    }

    /// Pinned bytes of the 1.5 Mac's v3 key for `goldenModel()` (sorted keys). Changing the
    /// v3 wire shape changes this literal, which forces a fresh look at KTD5.
    static let goldenJSON = #"{"companionGeneration":42,"companionSourceID":"6f1c2c1e-1b7a-4d6b-9d55-8f6f3b8f2a01","publishedAt":811692800,"schemaVersion":1,"snapshot":{"apiSpendProviders":[{"amount":12.5,"attention":"keyRejected","capturedAt":811692680,"currency":"USD","displayName":"Anthropic","freshness":{"stale":{"message":"Replace the rejected key on your Mac","needsAttention":true}},"id":"claude","kind":"periodSpend","periodLabel":"Oct 1 – Oct 31"}],"generatedAt":811692800,"providers":[{"displayName":"Claude","freshness":{"live":{}},"id":"claude","planLabel":"Max","windows":[{"freshness":{"live":{}},"id":"fiveHour","kind":{"fiveHour":{}},"label":"5h","observedAt":811692800,"percentRemaining":15.1,"resetDeadline":811696400,"resetKind":"scheduled","severity":"low","utilization":84.95},{"freshness":{"unavailable":{"since":811692200}},"id":"other:Weekly (Fable)","kind":{"other":{"_0":"Weekly (Fable)"}},"label":"Weekly (Fable)","observedAt":811689200,"percentRemaining":72.3,"resetDeadline":811779200,"resetKind":"scheduled","severity":"healthy","utilization":27.654321}]},{"displayName":"Grok","freshness":{"live":{}},"id":"grok","windows":[{"billingPeriodDuration":604800,"freshness":{"live":{}},"id":"other:Weekly","kind":{"other":{"_0":"Weekly"}},"label":"Weekly","observedAt":811692800,"percentRemaining":56,"resetKind":"unresolved","resetReason":"absent","severity":"healthy","utilization":44}]},{"displayName":"Cursor","freshness":{"stale":{"message":"Couldn’t read usage. Your Mac will try again.","needsAttention":false}},"id":"cursor","planLabel":"Pro","windows":[]}],"schemaVersion":3,"status":"enabled","widgetProviderSelection":["claude","grok"]},"sourceID":"Mac","sourcePlatform":"macOS"}"#

    @Test func goldenV3WithLineageIsPinnedAndDecodesInTheFrozenReader() throws {
        let bytes = Data(Self.goldenJSON.utf8)
        #expect(try CompanionSyncCodec.encode(Self.goldenModel()) == bytes)
        let frozen = try #require(Build33Codec.decode(bytes).envelope)
        // Build 33 shows "<sourceID> on Mac": the lineage UUID never lands there.
        #expect(frozen.sourceID == "Mac" && frozen.sourcePlatform == .macOS)
        #expect(frozen.snapshot.providers.map(\.id) == ["claude", "grok", "cursor"])
        let claude = frozen.snapshot.providers[0]
        #expect(claude.windows.map(\.percentRemaining) == [15.1, 72.3])
        #expect(claude.windows[1].freshness == .unavailable(since: Self.t0.addingTimeInterval(-600)))
        let grok = frozen.snapshot.providers[1].windows[0]
        #expect(grok.resetSchedule == .unresolved(.absent) && grok.billingPeriodDuration == 604_800)
        #expect(frozen.snapshot.providers[2].freshness
            == .stale(message: "Couldn’t read usage. Your Mac will try again.", needsAttention: false))
        #expect(frozen.snapshot.apiSpendProviders.first?.attention == .keyRejected)
        #expect(frozen.snapshot.widgetProviderSelection == ["claude", "grok"])
        // The current reader keeps the lineage the frozen one ignores.
        let current = try #require(SyncedWidgetSnapshotCodec.decode(bytes).envelope)
        #expect(current == Self.goldenModel())
        #expect(current.companionLineage == CompanionV3Lineage(sourceID: Self.macID, generation: 42))
    }

    /// Every reset reason the Mac can emit must be one the frozen reader knows; a new
    /// reason would make build 33 reject the key (KTD5 stop condition).
    @Test func everyCurrentResetReasonAndDisabledEnvelopeDecodeInTheFrozenReader() throws {
        for reason in ResetUnresolvedReason.allCases {
            let snapshot = UsageSnapshot(
                providerID: .grok,
                windows: [
                    UsageWindow(
                        kind: .billingPeriod(label: "Monthly", duration: 2_592_000.5), utilization: 12.5,
                        resetSchedule: ResetSchedule.unresolved(reason))
                ],
                planLabel: nil, capturedAt: Self.t0, freshness: .live)
            let bytes = try encodedV3(snapshots: [.grok: snapshot], order: [.grok])
            let frozen = try #require(Build33Codec.decode(bytes).envelope, "\(reason)")
            #expect(frozen.snapshot.providers.first?.windows.first?.resetSchedule
                == .unresolved(try #require(Build33ResetUnresolvedReason(rawValue: reason.rawValue))))
        }
        let disabled = SyncedWidgetSnapshotEnvelope(
            publishedAt: Self.t0, sourceID: "Mac", sourcePlatform: .macOS,
            snapshot: .disabled(generatedAt: Self.t0), companionSourceID: Self.macID, companionGeneration: 7)
        let frozen = try #require(Build33Codec.decode(try SyncedWidgetSnapshotCodec.encode(disabled)).envelope)
        #expect(frozen.snapshot.status == .disabled && frozen.snapshot.providers.isEmpty)
    }

    /// V1: the Mac's actual v3 projection for every demo scenario, wrapped with the lineage
    /// pair and encoded by the production codec, decodes in the frozen reader.
    @Test func everyDemoScenarioProjectionDecodesInTheFrozenReader() async throws {
        var scenarios: [(String, [ProviderID: UsageSnapshot])] = []
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            let fixture = DemoFixture.multiFixture(for: scenario)
            var primaries: [ProviderID: UsageSnapshot] = [:]
            for provider in fixture.providers where primaries[provider.id] == nil {
                primaries[provider.id] = await provider.fetchSnapshot()
            }
            scenarios.append((scenario.rawValue, primaries))
        }
        scenarios.append((
            "single", [
                .claude: DemoFixture.claudeSnapshot, .codex: DemoFixture.codexSnapshot,
                .grok: DemoFixture.grokSnapshot, .cursor: DemoFixture.cursorSnapshot,
            ]))
        scenarios.append(("partial", [.claude: DemoFixture.claudePartialCaptureSnapshot]))
        let spend: [ProviderID: APISpendSnapshot] = [
            .claude: DemoFixture.anthropicSpendKeyRejectedRetained, .codex: DemoFixture.openAISpendStaleRetained,
            .grok: DemoFixture.xaiBalanceSpend, .cursor: DemoFixture.cursorOnDemandSpend,
        ]
        for (name, snapshots) in scenarios {
            let order = DemoFixture.registeredProviderOrder.filter { snapshots[$0] != nil }
            let bytes = try encodedV3(snapshots: snapshots, order: order, spend: spend)
            let frozen = try #require(Build33Codec.decode(bytes).envelope, "\(name)")
            let current = try #require(SyncedWidgetSnapshotCodec.decode(bytes).envelope)
            #expect(frozen.snapshot.providers.map(\.id) == current.snapshot.providers.map(\.id), "\(name)")
            #expect(
                frozen.snapshot.providers.map { $0.windows.map(\.percentRemaining) }
                    == current.snapshot.providers.map { $0.windows.map(\.percentRemaining) }, "\(name)")
            #expect(frozen.snapshot.apiSpendProviders.count == 4, "\(name)")
        }
    }

    /// `widget-snapshot.json` as the coordinated cache writes it stays build-33 readable.
    @Test func compatibilityFileBytesDecodeInTheFrozenInnerReader() throws {
        let storage = MemoryCacheStorage()
        let store = SpyKeyValueStore()
        store.seed(iCloudSnapshotSync.snapshotKey, try SyncedWidgetSnapshotCodec.encode(Self.goldenModel()))
        let loader = CompanionSnapshotLoader(
            store: store,
            cache: CompanionSnapshotCache(
                storage: storage, coordinator: BarrierCoordinator(anchor: SharedAnchor()),
                scope: FakeAccountScope("apple-id")),
            now: { Self.t0 })
        #expect(loader.load().content?.origin == .v3)
        let inner = try #require(storage[.v3Compatibility])
        let frozen = try Build33Codec.decodeInner(inner)
        #expect(frozen.providers.map(\.id) == ["claude", "grok", "cursor"])
        #expect(frozen.generatedAt == Self.t0)
    }

    /// KTD16 (OpenCode plan): build 33 reads only the v3 key and knows no OpenCode. The phone
    /// export of a live, a limited and a no-Go OpenCode account beside Claude decodes in the
    /// frozen reader; OpenCode arrives as an unknown provider ID that build 33 draws with its
    /// generic art, its monthly row as a 30-day `other` window, and the limited window as 0% left.
    @Test func openCodeInTheV3KeyDecodesInTheFrozenReaderAsAnUnknownProvider() throws {
        let claude = UsageSnapshot(
            providerID: .claude,
            windows: [UsageWindow(kind: .fiveHour, utilization: 40, resetsAt: Self.t0.addingTimeInterval(3_600))],
            planLabel: "Max", capturedAt: Self.t0, freshness: .live)
        for (name, opencode, remaining) in [
            ("go", OpenCodePhoneFixture.go(), [71.0, 53, 38]),
            ("limited", OpenCodePhoneFixture.limited(), [71.0, 53, 0]),
            ("noGo", OpenCodePhoneFixture.noGo(), [100.0]),
        ] {
            let projected = WidgetSnapshotProjector.project(
                snapshots: [.claude: claude, .opencode: opencode], providerOrder: [.claude, .opencode],
                displayNames: [:], renewalDate: { _ in nil }, widgetsEnabled: true, generatedAt: Self.t0,
                context: .phoneSync(attention: [:]))
            let bytes = try SyncedWidgetSnapshotCodec.encode(
                SyncedWidgetSnapshotEnvelope(
                    publishedAt: Self.t0, sourceID: "Mac", sourcePlatform: .macOS, snapshot: projected,
                    companionSourceID: Self.macID, companionGeneration: 11))
            let frozen = try #require(Build33Codec.decode(bytes).envelope, "\(name)")
            #expect(frozen.snapshot.providers.map(\.id) == ["claude", "opencode"], "\(name)")
            let row = try #require(frozen.snapshot.providers.last)
            #expect(row.displayName == "OpenCode")
            #expect(row.windows.map(\.percentRemaining) == remaining, "\(name)")
            #expect(row.windows.last?.billingPeriodDuration == 2_592_000, "\(name)")
            if name == "noGo" { #expect(row.planLabel == "No Go plan") }
            if name == "limited" {
                #expect(row.windows.last?.resetSchedule == .scheduled(OpenCodePhoneFixture.monthlyReset))
            }
        }
    }

    private func encodedV3(
        snapshots: [ProviderID: UsageSnapshot], order: [ProviderID],
        spend: [ProviderID: APISpendSnapshot] = [:]
    ) throws -> Data {
        let projected = WidgetSnapshotProjector.project(
            snapshots: snapshots, providerOrder: order,
            displayNames: Dictionary(uniqueKeysWithValues: order.map { ($0, $0.displayName) }),
            renewalDate: { _ in nil }, widgetsEnabled: true, showsCodexSparkCounters: true,
            apiSpendSnapshots: spend, apiSpendProviderOrder: Array(spend.keys).sorted { $0.raw < $1.raw },
            generatedAt: Self.t0)
        return try SyncedWidgetSnapshotCodec.encode(
            SyncedWidgetSnapshotEnvelope(
                publishedAt: Self.t0, sourceID: "Mac", sourcePlatform: .macOS, snapshot: projected,
                companionSourceID: Self.macID, companionGeneration: 9))
    }
}
