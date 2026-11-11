import Foundation

// FROZEN TEST ORACLE: the on-disk shapes macOS 1.6.2 (46) reads and rewrites.
//
// Copied from tag v1.6.2 (commit 6d522a8d31cb8b57a7a42364f9c43465d924d543), blobs
//   Sources/HeadroomCore/Engine/UsageContinuityCache.swift                   1ed93f483fea463049d05466205406dc1b0c87ee
//   Sources/HeadroomCore/Notifications/UseItUpLedger.swift                   06612810779048c7acf17279806d8904fb424bdb
//   Sources/HeadroomCore/Notifications/BankedResetNotificationBaseline.swift b4efef224fb754ce9afba14c7026a139d203c693
//   Sources/HeadroomCore/Settings/BankedResetAcknowledgements.swift          49eaedeced75c668278113e1db1a68a21ee89fdb
//   Sources/HeadroomCore/Models/Account.swift                                8cd73722efaad02e2bdf6742f660c34a5582558f
//
// Stored properties and coding only, renamed with a `Release162` prefix and never
// updated. Each type is `Codable` with synthesized coding, as it is in 1.6.2, so a
// decode-then-encode here drops exactly what that build would drop when it rewrites a
// store. The schema-1 continuity lift is not reproduced: this build writes schema 2.

struct Release162ProviderID: Codable, Equatable { let raw: String }
struct Release162AccountID: Codable, Equatable { let raw: String }

struct Release162AccountKey: Codable, Equatable {
    let providerID: Release162ProviderID
    let accountID: Release162AccountID
}

struct Release162ProviderAccount: Codable, Equatable {
    let id: Release162AccountID
    let providerID: Release162ProviderID
    var label: String
    let isBuiltIn: Bool
}

struct Release162ContinuityEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2
    let schemaVersion: Int
    let records: [Release162StoredSnapshot]
}

struct Release162StoredSnapshot: Codable, Equatable {
    let key: Release162AccountKey
    let windows: [Release162StoredWindow]
    let planLabel: String?
    let accountEmail: String?
    let bankedResets: Int?
    let capturedAt: Date?
}

enum Release162StoredWindowKind: String, Codable {
    case fiveHour, weekly, billingPeriod, other
}

struct Release162StoredWindow: Codable, Equatable {
    let kind: Release162StoredWindowKind
    let otherLabel: String?
    let billingPeriodDuration: TimeInterval?
    let utilization: Double
    let reset: Release162StoredResetEvidence
    let resetLabel: String?
    let resetTimeZoneIdentifier: String?
    let observedAt: Date?
    let staleObservedAt: Date?
    let unavailableSince: Date?
}

struct Release162StoredResetEvidence: Codable, Equatable {
    enum Kind: String, Codable { case scheduled, unresolved }
    let kind: Kind
    let deadline: Date?
    let reason: String?
}

struct Release162UseItUpLedgerEntry: Codable, Equatable {
    let account: Release162AccountKey
    let windowID: String
    let deadline: Date
    let firedKeys: [String]
}

struct Release162UseItUpStored: Codable, Equatable {
    var entries: [Release162UseItUpLedgerEntry] = []
}

struct Release162BankedEntry: Codable, Equatable {
    let account: Release162AccountKey
    let count: Int
}

/// Both banked stores (`bankedResetNotificationBaseline.v1` and
/// `bankedResetAcknowledgements.v1`) share this shape in 1.6.2.
struct Release162BankedStored: Codable, Equatable {
    var entries: [Release162BankedEntry] = []
}

enum Release162Stores {
    static let continuityKey = "usageContinuitySnapshots.v2"
    static let useItUpKey = "useItUpLedger.v1"
    static let bankedBaselineKey = "bankedResetNotificationBaseline.v1"
    static let bankedAcknowledgementsKey = "bankedResetAcknowledgements.v1"
    static let accountsKey = "providerAccounts.v1"

    /// Decodes what is stored under `key` the way 1.6.2 does, or nil when it cannot.
    static func decode<Value: Decodable>(_ type: Value.Type, key: String, in defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// 1.6.2 loads a store, changes it and writes all of it back. This is that rewrite
    /// with no change: whatever a newer build added is gone afterwards.
    static func rewrite<Value: Codable>(_ type: Value.Type, key: String, in defaults: UserDefaults) {
        guard let value = decode(type, key: key, in: defaults),
              let data = try? JSONEncoder().encode(value)
        else { return }
        defaults.set(data, forKey: key)
    }
}
