import Foundation

public struct SyncedWidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let publishedAt: Date
    public let sourceID: String
    public let sourcePlatform: SyncedWidgetSnapshotSourcePlatform
    public let snapshot: WidgetSnapshotEnvelope
    /// KTD5: the 1.5 Mac's random lineage UUID and publish generation, additive fields
    /// build 33 ignores. Never written into `sourceID`, which build 33 displays.
    public let companionSourceID: String?
    public let companionGeneration: Int64?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        publishedAt: Date,
        sourceID: String,
        sourcePlatform: SyncedWidgetSnapshotSourcePlatform,
        snapshot: WidgetSnapshotEnvelope,
        companionSourceID: String? = nil,
        companionGeneration: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.publishedAt = publishedAt
        self.sourceID = sourceID
        self.sourcePlatform = sourcePlatform
        self.snapshot = snapshot
        self.companionSourceID = companionSourceID
        self.companionGeneration = companionGeneration
    }

    /// The declared v4 lineage, only when both fields agree with the contract: a canonical
    /// UUID and a nonnegative generation. A malformed or half pair is no lineage (KTD6.5).
    public var companionLineage: CompanionV3Lineage? {
        guard let companionSourceID, let companionGeneration, companionGeneration >= 0,
            let uuid = try? CompanionTransportValidation.uuid(companionSourceID),
            uuid == companionSourceID
        else { return nil }
        return CompanionV3Lineage(sourceID: uuid, generation: companionGeneration)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, publishedAt, sourceID, sourcePlatform, snapshot
        case companionSourceID, companionGeneration
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        publishedAt = try c.decode(Date.self, forKey: .publishedAt)
        sourceID = try c.decode(String.self, forKey: .sourceID)
        sourcePlatform = try c.decode(SyncedWidgetSnapshotSourcePlatform.self, forKey: .sourcePlatform)
        snapshot = try c.decode(WidgetSnapshotEnvelope.self, forKey: .snapshot)
        // Contract: a malformed lineage is ignored, never a reason to reject readable v3.
        companionSourceID = try? c.decodeIfPresent(String.self, forKey: .companionSourceID)
        companionGeneration = try? c.decodeIfPresent(Int64.self, forKey: .companionGeneration)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(publishedAt, forKey: .publishedAt)
        try c.encode(sourceID, forKey: .sourceID)
        try c.encode(sourcePlatform, forKey: .sourcePlatform)
        try c.encode(snapshot, forKey: .snapshot)
        try c.encodeIfPresent(companionSourceID, forKey: .companionSourceID)
        try c.encodeIfPresent(companionGeneration, forKey: .companionGeneration)
    }
}

public struct CompanionV3Lineage: Equatable, Sendable {
    public let sourceID: String
    public let generation: Int64
}

public enum SyncedWidgetSnapshotSourcePlatform: String, Codable, Sendable {
    case macOS
    case iOS
    case unknown
}

public enum SyncedWidgetSnapshotDecodeResult: Equatable, Sendable {
    case missing
    case incompatibleSchema
    case corrupt
    case snapshot(SyncedWidgetSnapshotEnvelope)

    public var envelope: SyncedWidgetSnapshotEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

public enum SyncedWidgetSnapshotCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ envelope: SyncedWidgetSnapshotEnvelope) throws -> Data {
        try encoder.encode(envelope)
    }

    public static func decode(_ data: Data?) -> SyncedWidgetSnapshotDecodeResult {
        guard let data else { return .missing }
        do {
            let header = try decoder.decode(SyncedWidgetSnapshotHeader.self, from: data)
            guard header.schemaVersion == SyncedWidgetSnapshotEnvelope.schemaVersion,
                  WidgetSnapshotEnvelope.supports(schemaVersion: header.snapshot.schemaVersion)
            else { return .incompatibleSchema }
            let envelope = try decoder.decode(SyncedWidgetSnapshotEnvelope.self, from: data)
            return .snapshot(envelope)
        } catch {
            return .corrupt
        }
    }
}

/// The iCloud path checks compatibility before decoding the full tree so an unsupported
/// payload cannot be mislabeled corrupt because a future child shape is unknown. The
/// local macOS `WidgetSnapshotCache` intentionally has no supports gate; it is written
/// and read by the same installed app version.
private struct SyncedWidgetSnapshotHeader: Decodable {
    struct Snapshot: Decodable { let schemaVersion: Int }
    let schemaVersion: Int
    let snapshot: Snapshot
}

public enum SyncedWidgetSnapshotResolution {
    public static func newestValid(
        local: SyncedWidgetSnapshotEnvelope?,
        remote: SyncedWidgetSnapshotDecodeResult
    ) -> SyncedWidgetSnapshotDecodeResult {
        if remote == .incompatibleSchema { return .incompatibleSchema }
        guard case .snapshot(let remoteEnvelope) = remote else {
            return local.map(SyncedWidgetSnapshotDecodeResult.snapshot) ?? remote
        }
        guard let local else { return .snapshot(remoteEnvelope) }
        if remoteEnvelope.snapshot.generatedAt > local.snapshot.generatedAt { return .snapshot(remoteEnvelope) }
        return .snapshot(local)
    }
}
