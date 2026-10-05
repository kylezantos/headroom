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

extension CompanionCachedV3 {
    /// Only the resolver's fresh v3-key read and the scoped storage load construct this,
    /// so `widget-snapshot.json` can never receive a projection built from v4 (KTD6.8).
    init(keyRead envelope: SyncedWidgetSnapshotEnvelope) {
        self.envelope = envelope
    }
}

// MARK: - Storage (KTD6.8)

/// The three App Group files of one scope. The v4 cache is a separate file; the
/// compatibility file keeps build 33's name and inner-envelope shape.
public enum CompanionCacheFile: String, Sendable, CaseIterable {
    case sidecar = "companion-account-scope.json"
    case v4 = "companion-snapshot-v4.json"
    case v3Compatibility = "widget-snapshot.json"
}

/// File I/O seam. `write` must atomically replace the whole file.
public protocol CompanionCacheStoring: Sendable {
    func read(_ file: CompanionCacheFile) throws -> Data?
    func write(_ data: Data, to file: CompanionCacheFile) throws
    func remove(_ file: CompanionCacheFile) throws
}

/// App Group directory storage with atomic replacement. Storage only: nothing in U4
/// adopts it into the app or widget loaders (KTD22 gate).
public struct CompanionDirectoryCacheStorage: CompanionCacheStoring {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func read(_ file: CompanionCacheFile) throws -> Data? {
        do {
            return try Data(contentsOf: directory.appendingPathComponent(file.rawValue))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func write(_ data: Data, to file: CompanionCacheFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(file.rawValue), options: [.atomic])
    }

    public func remove(_ file: CompanionCacheFile) throws {
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(file.rawValue))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

/// The v4 cache file: checked raw manifest and provider bytes keyed by source/provider/
/// generation. First-seen and paused state live only in the sidecar.
struct CompanionV4CacheFile: Codable, Equatable {
    static let currentFormat = 1
    var format = Self.currentFormat
    var manifest: CompanionCachedManifest?
    var providers: [String: CompanionCachedProvider]
}

// MARK: - The coordinated cache (KTD6.8, KTD22)

/// Every companion cache read, write and invalidation goes through one coordinated
/// transaction that encloses the account-scope check, the re-read, the merge and the
/// atomic replacement. A writer captured under an older scope epoch cannot write or serve.
public struct CompanionSnapshotCache: Sendable {
    private let storage: any CompanionCacheStoring
    private let coordinator: any CompanionCacheCoordinating
    private let scope: any CompanionAccountScopeProviding

    public init(
        storage: any CompanionCacheStoring, coordinator: any CompanionCacheCoordinating,
        scope: any CompanionAccountScopeProviding
    ) {
        self.storage = storage
        self.coordinator = coordinator
        self.scope = scope
    }

    /// Verifies the current scope before any KVS read. A changed scope invalidates every
    /// cache and first-seen time and starts a new epoch; an unavailable scope invalidates
    /// and returns nil, so no cached account content is ever served without identity.
    public func captureScope() -> CompanionScopeCapture? {
        coordinator.coordinate { () -> CompanionScopeCapture? in
            let sidecar = readSidecar()
            switch scope.check(against: sidecar?.scopeArchive) {
            case .unavailable:
                invalidateLocked(archive: nil, previous: sidecar)
                return nil
            case .changed(let archive):
                return CompanionScopeCapture(epoch: invalidateLocked(archive: archive, previous: sidecar).epoch)
            case .unchanged:
                guard let sidecar else { return nil }
                return CompanionScopeCapture(epoch: sidecar.epoch)
            }
        } ?? nil
    }

    /// The single transaction: revalidates the captured scope and epoch, re-reads the
    /// sidecar and both caches, runs `merge` on the checked contents and atomically
    /// commits any change. Returns nil (serve nothing cached) when the scope moved since
    /// `capture`, identity is unavailable, or coordination failed.
    public func transact<Result>(
        capture: CompanionScopeCapture,
        _ merge: (CompanionCacheContents) -> (CompanionCacheContents, Result)
    ) -> Result? {
        coordinator.coordinate { () -> Result? in
            guard let sidecar = verifiedSidecar(capture) else { return nil }
            let contents = load(sidecar)
            let (updated, result) = merge(contents)
            // Re-check before committing or serving: identity may change mid-transaction.
            guard verifiedSidecar(capture) != nil else { return nil }
            // After an interrupted commit nothing on disk is trusted: rewrite everything.
            if updated != contents || !sidecar.committed {
                guard commit(updated, previous: contents, sidecar: sidecar) else { return nil }
            }
            return result
        } ?? nil
    }

    /// Account-change notifications accelerate invalidation; they are never its only
    /// trigger (KTD22). The next capture re-establishes identity under a new epoch.
    public func invalidate() {
        _ = coordinator.coordinate { invalidateLocked(archive: nil, previous: readSidecar()) }
    }

    // MARK: Locked helpers (call only inside `coordinate`)

    private func verifiedSidecar(_ capture: CompanionScopeCapture) -> CompanionScopeSidecar? {
        let sidecar = readSidecar()
        switch scope.check(against: sidecar?.scopeArchive) {
        case .unavailable:
            invalidateLocked(archive: nil, previous: sidecar)
            return nil
        case .changed(let archive):
            invalidateLocked(archive: archive, previous: sidecar)
            return nil
        case .unchanged:
            guard let sidecar, sidecar.epoch == capture.epoch else { return nil }
            return sidecar
        }
    }

    private func readSidecar() -> CompanionScopeSidecar? {
        guard let data = try? storage.read(.sidecar),
            let sidecar = try? JSONDecoder().decode(CompanionScopeSidecar.self, from: data),
            sidecar.format == CompanionScopeSidecar.currentFormat
        else { return nil }
        return sidecar
    }

    @discardableResult
    private func invalidateLocked(archive: Data?, previous: CompanionScopeSidecar?) -> CompanionScopeSidecar {
        // Dirty marker first, so an interruption anywhere below serves nothing.
        let revision = (previous?.revision ?? 0) + 1
        var sidecar = CompanionScopeSidecar(scopeArchive: archive, revision: revision, committed: false)
        try? storage.write(encode(sidecar), to: .sidecar)
        try? storage.remove(.v4)
        try? storage.remove(.v3Compatibility)
        sidecar.committed = true
        try? storage.write(encode(sidecar), to: .sidecar)
        return sidecar
    }

    private func load(_ sidecar: CompanionScopeSidecar) -> CompanionCacheContents {
        // An interrupted commit leaves nothing trustworthy to serve.
        guard sidecar.committed else { return .empty }
        var contents = CompanionCacheContents(firstSeen: sidecar.firstSeen, paused: sidecar.paused)
        // An incompatible or corrupt v4 file never blocks v3 (V6).
        if let data = try? storage.read(.v4),
            let file = try? JSONDecoder().decode(CompanionV4CacheFile.self, from: data),
            file.format == CompanionV4CacheFile.currentFormat
        {
            contents.manifest = file.manifest
            contents.providers = file.providers
        }
        if let wrapper = sidecar.v3Wrapper, let data = try? storage.read(.v3Compatibility),
            let inner = try? JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: data)
        {
            contents.v3 = CompanionCachedV3(keyRead: wrapper.envelope(with: inner))
        }
        return contents
    }

    private func commit(
        _ updated: CompanionCacheContents, previous: CompanionCacheContents,
        sidecar: CompanionScopeSidecar
    ) -> Bool {
        var next = sidecar
        next.revision += 1
        next.committed = false
        do {
            try storage.write(encode(next), to: .sidecar)
            let rewriteAll = !sidecar.committed
            if rewriteAll || updated.manifest != previous.manifest || updated.providers != previous.providers {
                if updated.manifest == nil, updated.providers.isEmpty {
                    try storage.remove(.v4)
                } else {
                    try storage.write(
                        encode(CompanionV4CacheFile(manifest: updated.manifest, providers: updated.providers)),
                        to: .v4)
                }
            }
            // Only the inner envelope decoded from the v3 key ever reaches the compatibility
            // file, in build 33's default date encoding (sorted keys only make it
            // deterministic); v4 writes never touch it.
            if rewriteAll || updated.v3 != previous.v3 {
                if let v3 = updated.v3 {
                    try storage.write(CompanionSyncCodec.encode(v3.envelope.snapshot), to: .v3Compatibility)
                } else {
                    try storage.remove(.v3Compatibility)
                }
            }
            next.firstSeen = updated.firstSeen
            next.paused = updated.paused
            next.v3Wrapper = updated.v3.map { CompanionV3WrapperMetadata($0.envelope) }
            next.committed = true
            try storage.write(encode(next), to: .sidecar)
            return true
        } catch {
            return false
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        // Encoding these local Codable values cannot fail; an empty file reads as missing.
        (try? CompanionSyncCodec.encode(value)) ?? Data()
    }
}
