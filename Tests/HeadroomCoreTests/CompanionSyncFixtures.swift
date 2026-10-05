import Foundation

@testable import HeadroomCore

/// U4 fixtures shared by the envelope, resolver, cache and budget suites. Kept out of
/// `Mocks.swift` per the parity plan's stream rule.
enum CompanionFixtures {
    static let macA = "6f1c2c1e-1b7a-4d6b-9d55-8f6f3b8f2a01"
    static let macB = "0b5e2a44-7c39-4a8e-8f43-2d1b7b9b1c02"
    static let base: Int64 = 1_790_000_000

    static func date(_ offset: Int64 = 0) -> CompanionWireDate {
        CompanionWireDate(epochSeconds: base + offset)!
    }

    static func window(
        _ kind: CompanionWindowKind = .fiveHour, name: String? = nil, duration: Double? = nil,
        remaining: Double = 63, utilization: Double? = 37,
        resetAt: Int64? = 3_600, freshness: CompanionWindowFreshness = .live,
        observed: CompanionWireDate? = nil, since: CompanionWireDate? = nil, spark: Bool = false
    ) -> CompanionSlimWindow {
        try! CompanionSlimWindow(
            kind: kind, kindName: name, billingPeriodDuration: duration,
            percentRemaining: remaining, utilization: utilization,
            resetKind: resetAt == nil ? .unresolved : .scheduled,
            resetDeadline: resetAt.map { date($0) },
            resetReason: resetAt == nil ? .absent : nil,
            freshness: freshness, observedAtOverride: observed, unavailableSince: since,
            isSpark: spark)
    }

    static func account(
        _ id: String = "primary", title: String = "Personal", plan: String? = "Max",
        captured: Int64 = 0, windows: [CompanionSlimWindow]? = nil, banked: Int? = nil
    ) -> CompanionAccountSummary {
        try! CompanionAccountSummary(
            id: id, title: title, planName: plan, capturedAt: date(captured),
            bankedResets: banked,
            windows: windows ?? [window(.fiveHour), window(.weekly, remaining: 40, resetAt: 86_400)])
    }

    static func payload(
        _ provider: String = "claude", source: String = macA, generation: Int64 = 1,
        main: CompanionAccountSummary? = account(), extras: [CompanionAccountSummary] = [],
        spend: CompanionSpendSummary? = nil, mode: CompanionPayloadMode = .subscription,
        capability: CompanionAttention? = nil
    ) -> CompanionProviderPayload {
        try! CompanionProviderPayload(
            sourceID: source, providerID: provider, payloadGeneration: generation, mode: mode,
            capabilityAttention: capability, mainAccount: mode == .spendOnly ? nil : main,
            accounts: extras, apiSpend: spend)
    }

    static func bytes<T: Encodable>(_ value: T) -> Data { try! CompanionSyncCodec.encode(value) }

    static func entry(_ data: Data, generation: Int64, interval: Double = 300)
        -> CompanionManifestProviderEntry
    {
        try! CompanionManifestProviderEntry(
            payloadGeneration: generation, digest: CompanionSyncCodec.digest(data),
            effectiveIntervalSeconds: interval)
    }

    static func manifest(
        source: String = macA, generation: Int64 = 1, generatedAt: Int64 = 0,
        order: [String] = ["claude"], entries: [String: CompanionManifestProviderEntry],
        spendOrder: [String] = [], interval: Int = 300, display: CompanionDisplayBlock? = nil,
        selection: [String]? = nil, widgetSpark: Bool = false, ladder: Int = 0,
        answered: [CompanionAnsweredRequest] = []
    ) -> CompanionManifest {
        .active(
            try! CompanionActiveManifest(
                sourceID: source, generation: generation, generatedAt: date(generatedAt),
                macAppVersion: "1.5", providerOrder: order, providers: entries,
                spendOrder: spendOrder, chosenIntervalSeconds: interval, display: display,
                widgetProviderSelection: selection, widgetSparkEnabled: widgetSpark,
                answeredRequests: answered, dropLadderLevel: ladder))
    }

    /// A v3 wrapper as KTD5 publishes it, optionally carrying the 1.5 lineage pair.
    static func v3(
        generatedAt: Int64 = 0, providers: [WidgetProviderSummary] = [v3Provider()],
        status: WidgetExportStatus = .enabled, lineage: (String, Int64)? = nil,
        spend: [WidgetAPISpendSummary] = []
    ) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            publishedAt: date(generatedAt).date, sourceID: "Mac", sourcePlatform: .macOS,
            snapshot: WidgetSnapshotEnvelope(
                generatedAt: date(generatedAt).date, status: status,
                providers: status == .enabled ? providers : [], apiSpendProviders: spend),
            companionSourceID: lineage?.0, companionGeneration: lineage?.1)
    }

    static func v3Provider(
        _ id: String = "claude", remaining: Double = 55, plan: String? = "Max"
    ) -> WidgetProviderSummary {
        WidgetProviderSummary(
            id: id, displayName: ProviderID(id).displayName, planLabel: plan, freshness: .live,
            windows: [
                WidgetWindowSummary(
                    kind: .fiveHour, label: "5h", percentRemaining: remaining,
                    utilization: 100 - remaining, resetSchedule: .scheduled(date(3_600).date),
                    resetLabel: nil, observedAt: date(0).date,
                    severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: remaining)))
            ],
            renewalDate: nil)
    }

    static func v3Bytes(_ envelope: SyncedWidgetSnapshotEnvelope) -> Data {
        try! SyncedWidgetSnapshotCodec.encode(envelope)
    }
}
