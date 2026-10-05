import Foundation

// FROZEN TEST ORACLE: "pre-parity schema-3 reader from 06d082af".
//
// Provenance, stated honestly (see .context/ios-parity-work/u4-build33-provenance.md):
// copied from commit 06d082afe60c67f2837157bb8d37aa783ffcc3af, the best documented
// pre-parity source comparator, blobs
//   Sources/HeadroomCore/Sync/SyncedWidgetSnapshotModels.swift  bac20c7485b30119223eee81d5390210ade7d905
//   Sources/HeadroomCore/Widgets/WidgetSnapshotModels.swift     2196aabe976f16c10cbe75f7a0fd5192e83bde44
// plus the raw values of ResetUnresolvedReason, APISpendKind and APISpendAttention at that
// commit. It is NOT proven to be the source of the retained TestFlight 1.5 (33) archive:
// no source manifest links those artifact bytes to any commit. Passing these tests shows
// compatibility with this comparator, not with the archived binary.
//
// Decode paths only, types renamed with a `Build33` prefix and never updated. The schema
// 1/2 legacy lift is not reproduced: a 1.5 Mac only ever emits schema 3, and this oracle
// throws for older inner schemas rather than approximating that path.

enum Build33Platform: String, Decodable {
    case macOS, iOS, unknown
}

struct Build33SyncedEnvelope: Decodable {
    let schemaVersion: Int
    let publishedAt: Date
    let sourceID: String
    let sourcePlatform: Build33Platform
    let snapshot: Build33WidgetEnvelope
}

enum Build33DecodeResult {
    case missing, incompatibleSchema, corrupt
    case snapshot(Build33SyncedEnvelope)

    var envelope: Build33SyncedEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

enum Build33Codec {
    static func decode(_ data: Data?) -> Build33DecodeResult {
        guard let data else { return .missing }
        let decoder = JSONDecoder()
        do {
            let header = try decoder.decode(Header.self, from: data)
            guard header.schemaVersion == 1, (1...3).contains(header.snapshot.schemaVersion) else {
                return .incompatibleSchema
            }
            return .snapshot(try decoder.decode(Build33SyncedEnvelope.self, from: data))
        } catch {
            return .corrupt
        }
    }

    /// The App Group `widget-snapshot.json` path: inner envelope bytes.
    static func decodeInner(_ data: Data) throws -> Build33WidgetEnvelope {
        try JSONDecoder().decode(Build33WidgetEnvelope.self, from: data)
    }

    private struct Header: Decodable {
        struct Snapshot: Decodable { let schemaVersion: Int }
        let schemaVersion: Int
        let snapshot: Snapshot
    }
}

enum Build33ExportStatus: String, Decodable {
    case enabled, disabled
}

struct Build33WidgetEnvelope: Decodable {
    let schemaVersion: Int
    let generatedAt: Date
    let status: Build33ExportStatus
    let providers: [Build33ProviderSummary]
    let apiSpendProviders: [Build33APISpendSummary]
    let widgetProviderSelection: [String]?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, status, providers, apiSpendProviders, widgetProviderSelection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        status = try container.decode(Build33ExportStatus.self, forKey: .status)
        guard (1...3).contains(schemaVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "Unsupported widget snapshot schema")
        }
        guard schemaVersion >= 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "Legacy lift not frozen in this oracle")
        }
        providers = try container.decode([Build33ProviderSummary].self, forKey: .providers)
        apiSpendProviders =
            try container.decodeIfPresent([Build33APISpendSummary].self, forKey: .apiSpendProviders) ?? []
        widgetProviderSelection = try container.decodeIfPresent([String].self, forKey: .widgetProviderSelection)
    }
}

struct Build33ProviderSummary: Decodable {
    let id: String
    let displayName: String
    let planLabel: String?
    let freshness: Build33ProviderFreshness
    let windows: [Build33WindowSummary]
    let renewalDate: Date?
}

enum Build33APISpendKind: String, Decodable {
    case periodSpend, balance
}

enum Build33APISpendAttention: String, Decodable {
    case missingKey, keyRejected, keyLacksAccess, setupRequired, retryable
}

struct Build33APISpendSummary: Decodable {
    let id: String
    let displayName: String
    let amount: Double?
    let currency: String?
    let periodLabel: String
    let kind: Build33APISpendKind?
    let capturedAt: Date?
    let freshness: Build33ProviderFreshness
    let attention: Build33APISpendAttention?
}

enum Build33ProviderFreshness: Decodable, Equatable {
    case pending
    case live
    case stale(message: String, needsAttention: Bool)
}

enum Build33ResetUnresolvedReason: String {
    case absent, elapsed, unparseable, implausible, invalidZone, legacyUnknown
}

enum Build33ResetSchedule: Equatable {
    case scheduled(Date)
    case unresolved(Build33ResetUnresolvedReason)
}

enum Build33WindowFreshness: Decodable, Equatable {
    case live
    case stale(observedAt: Date)
    case unavailable(since: Date)
}

enum Build33WindowKind: Decodable, Equatable {
    case fiveHour
    case weekly
    case other(String)

    var id: String {
        switch self {
        case .fiveHour: "fiveHour"
        case .weekly: "weekly"
        case .other(let label): "other:\(label)"
        }
    }
}

enum Build33Severity: String, Decodable {
    case healthy, low, critical
}

struct Build33WindowSummary: Decodable {
    let id: String
    let kind: Build33WindowKind
    let label: String
    let percentRemaining: Double
    let utilization: Double?
    let resetSchedule: Build33ResetSchedule
    let resetLabel: String?
    let resetTimeZoneIdentifier: String?
    let observedAt: Date?
    let severity: Build33Severity
    let freshness: Build33WindowFreshness
    let billingPeriodDuration: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, percentRemaining, utilization, resetKind, resetDeadline, resetReason
        case resetLabel, resetTimeZoneIdentifier, observedAt, severity, freshness, billingPeriodDuration
    }

    private enum ResetKind: String, Decodable {
        case scheduled, unresolved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Build33WindowKind.self, forKey: .kind)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? kind.id
        label = try container.decode(String.self, forKey: .label)
        percentRemaining = try container.decode(Double.self, forKey: .percentRemaining)
        utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
        let resetKind = try container.decode(ResetKind.self, forKey: .resetKind)
        let resetDeadline = try container.decodeIfPresent(Date.self, forKey: .resetDeadline)
        let resetReason = try container.decodeIfPresent(String.self, forKey: .resetReason)
        switch resetKind {
        case .scheduled:
            guard let resetDeadline, resetReason == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .resetKind, in: container, debugDescription: "Scheduled reset requires only a deadline")
            }
            resetSchedule = .scheduled(resetDeadline)
        case .unresolved:
            guard resetDeadline == nil, let resetReason,
                let reason = Build33ResetUnresolvedReason(rawValue: resetReason)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .resetKind, in: container, debugDescription: "Unresolved reset requires only a known reason")
            }
            resetSchedule = .unresolved(reason)
        }
        resetLabel = try container.decodeIfPresent(String.self, forKey: .resetLabel)
        resetTimeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .resetTimeZoneIdentifier)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        severity = try container.decode(Build33Severity.self, forKey: .severity)
        freshness = try container.decodeIfPresent(Build33WindowFreshness.self, forKey: .freshness) ?? .live
        billingPeriodDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .billingPeriodDuration)
    }
}
