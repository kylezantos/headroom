import Foundation

// MARK: - Checked cache contents (KTD6.8, contract Decision 4)

/// How a cached provider payload was accepted. Structural evidence is never presented as
/// digest-verified (Decision 4): only an equal-generation SHA-256 match earns that.
public enum CompanionPayloadEvidence: String, Codable, Equatable, Sendable {
    case structural
    case manifestDigestMatched
}

/// The latest checked manifest, raw bytes retained so a later read re-decodes the same tree.
public struct CompanionCachedManifest: Codable, Equatable, Sendable {
    public let raw: Data
    public let sourceID: String
    public let generation: Int64
    public let generatedAt: CompanionWireDate

    public init(raw: Data, sourceID: String, generation: Int64, generatedAt: CompanionWireDate) {
        self.raw = raw
        self.sourceID = sourceID
        self.generation = generation
        self.generatedAt = generatedAt
    }
}

/// One checked provider payload keyed by (source, provider, generation). Raw bytes are
/// kept so the digest is always over what the Mac stored, never a re-encoding.
public struct CompanionCachedProvider: Codable, Equatable, Sendable {
    public let raw: Data
    public let sourceID: String
    public let providerID: String
    public let generation: Int64
    public let evidence: CompanionPayloadEvidence
    /// SHA-256 of `raw`, recorded locally. It detects local mutation; it does not by
    /// itself authenticate against a manifest.
    public let observedDigest: String

    public init(
        raw: Data, sourceID: String, providerID: String, generation: Int64,
        evidence: CompanionPayloadEvidence
    ) {
        self.raw = raw
        self.sourceID = sourceID
        self.providerID = providerID
        self.generation = generation
        self.evidence = evidence
        self.observedDigest = CompanionSyncCodec.digest(raw)
    }
}

/// The last readable v3 key content seen under the current account scope. The inner
/// envelope is what `widget-snapshot.json` stores; lineage rides in the sidecar.
public struct CompanionCachedV3: Codable, Equatable, Sendable {
    public let envelope: SyncedWidgetSnapshotEnvelope

    public init(envelope: SyncedWidgetSnapshotEnvelope) {
        self.envelope = envelope
    }
}

/// Everything the coordinated transaction reads and writes, as one value. Never a
/// finished screen state: the resolver rebuilds presentation from these checked inputs.
public struct CompanionCacheContents: Codable, Equatable, Sendable {
    public var manifest: CompanionCachedManifest?
    public var providers: [String: CompanionCachedProvider]
    /// Shared first-seen times, created once inside the transaction (KTD6.8, KTD15).
    public var firstSeen: [String: CompanionWireDate]
    /// KTD22: after a disabled tombstone or disabled v3 only the paused state survives.
    public var paused: Bool
    public var v3: CompanionCachedV3?

    public init(
        manifest: CompanionCachedManifest? = nil,
        providers: [String: CompanionCachedProvider] = [:],
        firstSeen: [String: CompanionWireDate] = [:],
        paused: Bool = false,
        v3: CompanionCachedV3? = nil
    ) {
        self.manifest = manifest
        self.providers = providers
        self.firstSeen = firstSeen
        self.paused = paused
        self.v3 = v3
    }

    public static let empty = CompanionCacheContents()
}
