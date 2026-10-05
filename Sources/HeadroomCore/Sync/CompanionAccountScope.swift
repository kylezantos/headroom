import Foundation

/// The result of comparing the current local iCloud-account identity with the opaque
/// archive in the sidecar (KTD22). Values never sync, never reach UI or diagnostics.
public enum CompanionScopeCheck: Equatable, Sendable {
    /// No identity can be established: serve no cached account content.
    case unavailable
    /// The verified current identity equals the archived one; offline reads may proceed.
    case unchanged
    /// The identity differs from the archive, or no archive exists yet. Carries the new
    /// opaque local archive; every cache is invalidated before anything is served.
    case changed(archive: Data)
}

/// The injected local account-scope seam. U4 ships no production conformer: the signed
/// P5 gate for `FileManager.ubiquityIdentityToken` under the KVS-only entitlements failed
/// on device, so cached loading stays unadopted until a separately verified candidate
/// passes. Only test doubles implement this today.
public protocol CompanionAccountScopeProviding: Sendable {
    /// Compares the current identity with `archive` using the identity's own equality
    /// (never archive bytes, descriptions or hashes), sampling the identity fresh each call.
    func check(against archive: Data?) -> CompanionScopeCheck
}

/// What a loader holds between its scope check and its coordinated commit. A writer whose
/// epoch no longer matches the sidecar cannot write or serve (KTD6.8).
public struct CompanionScopeCapture: Equatable, Sendable {
    public let epoch: String
}

/// The v3 wrapper fields the inner `widget-snapshot.json` cannot hold. Lives in the
/// sidecar so the compatibility file keeps build-33-compatible bytes (KTD6.8).
public struct CompanionV3WrapperMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let publishedAt: Date
    public let sourceID: String
    public let sourcePlatform: SyncedWidgetSnapshotSourcePlatform
    public let companionSourceID: String?
    public let companionGeneration: Int64?

    init(_ envelope: SyncedWidgetSnapshotEnvelope) {
        schemaVersion = envelope.schemaVersion
        publishedAt = envelope.publishedAt
        sourceID = envelope.sourceID
        sourcePlatform = envelope.sourcePlatform
        companionSourceID = envelope.companionSourceID
        companionGeneration = envelope.companionGeneration
    }

    func envelope(with snapshot: WidgetSnapshotEnvelope) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            schemaVersion: schemaVersion, publishedAt: publishedAt, sourceID: sourceID,
            sourcePlatform: sourcePlatform, snapshot: snapshot,
            companionSourceID: companionSourceID, companionGeneration: companionGeneration)
    }
}

/// Local-only scope metadata, kept apart from both caches (KTD6.8, KTD22). It is the one
/// authoritative home for first-seen times and the paused marker.
public struct CompanionScopeSidecar: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public var format: Int
    /// The opaque, locally archived identity. Never exported.
    public var scopeArchive: Data?
    /// A fresh random value at every invalidation, so a writer captured before an account
    /// change can never match again, even after A → B → A or a lost sidecar.
    public var epoch: String
    /// Monotonic local commit revision.
    public var revision: Int64
    /// False while a multi-file commit is in flight: an interrupted commit suppresses all
    /// cached account content until it is rebuilt.
    public var committed: Bool
    public var firstSeen: [String: CompanionWireDate]
    public var paused: Bool
    /// Present only when `widget-snapshot.json` was written under this epoch from a fresh
    /// read of the v3 key. An untagged compatibility file is never served.
    public var v3Wrapper: CompanionV3WrapperMetadata?

    public init(
        format: Int = Self.currentFormat, scopeArchive: Data?, epoch: String = UUID().uuidString,
        revision: Int64 = 0, committed: Bool = true, firstSeen: [String: CompanionWireDate] = [:],
        paused: Bool = false, v3Wrapper: CompanionV3WrapperMetadata? = nil
    ) {
        self.format = format
        self.scopeArchive = scopeArchive
        self.epoch = epoch
        self.revision = revision
        self.committed = committed
        self.firstSeen = firstSeen
        self.paused = paused
        self.v3Wrapper = v3Wrapper
    }
}
