import Foundation

/// The one way a phone process (app, widget extension, intents, controls) loads what to show
/// (KTD6, KTD13). Hosts always consume `CompanionResolvedSnapshot` and its freshness inputs and
/// never construct `iCloudSnapshotSync` or `CompanionSnapshotLoader` themselves.
///
/// With `CompanionLoaderAdoption.isEnabled` off (the default until the KTD22 device gate
/// passes), `load()` runs build 33's loading path exactly — the v3 key plus the
/// `widget-snapshot.json` adoption rules — and lifts the winner through the resolver's v3-only
/// rules with an empty v4 cache, so no v4 cache is ever served. With it on, `load()` is
/// `CompanionSnapshotLoader` over the real KVS store, the App Group `CompanionSnapshotCache` and
/// the KVS scope-marker provider.
public struct CompanionPhoneSnapshotSource: Sendable {
    private let loadSnapshot: @Sendable () -> CompanionResolvedSnapshot
    private let handleChange: @Sendable (iCloudKeyValueChange) -> Void

    /// Test seam.
    public init(load: @escaping @Sendable () -> CompanionResolvedSnapshot) {
        self.init(load: load, handle: { _ in })
    }

    /// Test seam that also observes forwarded KVS change notifications.
    public init(
        load: @escaping @Sendable () -> CompanionResolvedSnapshot,
        handle: @escaping @Sendable (iCloudKeyValueChange) -> Void
    ) {
        loadSnapshot = load
        handleChange = handle
    }

    /// Production composition for any phone process (app, widget extension, intents).
    /// `demo`: when it returns a snapshot, nothing reads or writes iCloud or any cache (KTD21).
    public static func production(
        appGroupIdentifier: String = WidgetSnapshotCache.appGroupSuiteName,
        demo: (@Sendable () -> CompanionResolvedSnapshot?)? = nil
    ) -> CompanionPhoneSnapshotSource {
        let store = UbiquitousKeyValueSyncStore()
        guard CompanionLoaderAdoption.isEnabled else {
            return build33(
                store: store, compatibilityCache: compatibilityCache(appGroupIdentifier: appGroupIdentifier),
                coordinator: CompanionFileCacheCoordinator(appGroupIdentifier: appGroupIdentifier), demo: demo)
        }
        return adopted(
            store: store, cache: appGroupCache(appGroupIdentifier: appGroupIdentifier, store: store),
            demo: demo)
    }

    public func load() -> CompanionResolvedSnapshot {
        loadSnapshot()
    }

    /// Forward `NSUbiquitousKeyValueStore.didChangeExternallyNotification` here (as a typed
    /// `iCloudKeyValueChange`). With adoption on, an account change clears every cache at once;
    /// the scope check on every load stays the authority (KTD22). A no-op on the build-33 path.
    public func handle(_ change: iCloudKeyValueChange) {
        handleChange(change)
    }

    // MARK: Compositions (internal so tests drive both with doubles)

    /// Adoption off: build 33's path, lifted. `now` only stamps first-seen, which an empty v4
    /// cache cannot persist, so the freshness rule's `generatedAt + allowance` bound governs.
    /// `coordinator` serializes the compatibility-file write across the app, widget and intents
    /// processes (KTD6.8's anchor); nil without an App Group container.
    static func build33(
        store: (any iCloudKeyValueSyncing)?, compatibilityCache: WidgetSnapshotCache,
        coordinator: (any CompanionCacheCoordinating)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        demo: (@Sendable () -> CompanionResolvedSnapshot?)?
    ) -> CompanionPhoneSnapshotSource {
        CompanionPhoneSnapshotSource(load: {
            if let demo, let snapshot = demo() { return snapshot }
            let outcome = CompanionBuild33Loading.load(
                sync: iCloudSnapshotSync(store: store), cache: compatibilityCache, rule: .appRefresh,
                coordinator: coordinator)
            return CompanionBuild33Loading.lift(outcome, now: now())
        })
    }

    /// Adoption on: the scoped loader. `synchronize()` reloads the on-disk KVS copy first, so
    /// the scope marker check reads the live local value in every process (KTD22).
    static func adopted(
        store: any iCloudKeyValueSyncing, cache: CompanionSnapshotCache?,
        now: @escaping @Sendable () -> Date = Date.init,
        demo: (@Sendable () -> CompanionResolvedSnapshot?)?
    ) -> CompanionPhoneSnapshotSource {
        guard let cache else {
            // No App Group container or anchor: nothing can be scoped, so nothing is served.
            return CompanionPhoneSnapshotSource(load: {
                if let demo, let snapshot = demo() { return snapshot }
                return CompanionResolvedSnapshot(state: .accountScopeUnavailable)
            })
        }
        let loader = CompanionSnapshotLoader(store: store, cache: cache, now: now)
        return CompanionPhoneSnapshotSource(
            load: {
                // KTD21: demo is decided before iCloud is touched, synchronize included.
                if let demo, let snapshot = demo() { return snapshot }
                store.synchronize()
                return loader.load()
            },
            handle: { loader.handle($0) })
    }

    static func appGroupCache(appGroupIdentifier: String, store: any iCloudKeyValueSyncing)
        -> CompanionSnapshotCache?
    {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier),
            let coordinator = CompanionFileCacheCoordinator(appGroupIdentifier: appGroupIdentifier)
        else { return nil }
        return CompanionSnapshotCache(
            storage: CompanionDirectoryCacheStorage(directory: container), coordinator: coordinator,
            scope: CompanionKVSScopeMarker(store: store))
    }

    /// Build 33's App Group `widget-snapshot.json`, exactly as the hosts open it today.
    static func compatibilityCache(appGroupIdentifier: String) -> WidgetSnapshotCache {
        guard appGroupIdentifier != WidgetSnapshotCache.appGroupSuiteName else { return .appGroup() }
        return WidgetSnapshotCache(
            defaults: nil,
            fileURL: FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
                .appendingPathComponent(CompanionCacheFile.v3Compatibility.rawValue))
    }
}

// MARK: - Build 33 loading (shared copy of the hosts' private path)

/// Build 33's phone loading path, lifted unchanged out of `IOSCompanionView.refresh()` and
/// `HeadroomIOSTimelineProvider.resolvedState()` so one Core copy serves every process while
/// adoption is off. The hosts keep their private copies until U8 and U13 adopt the source.
enum CompanionBuild33Loading {
    /// The two hosts disagree only on a same-time remote with different content.
    enum AdoptionRule: Equatable, Sendable {
        /// `IOSCompanionView`: adopt a newer remote, or a same-time remote that differs, then
        /// re-read the cache before resolving. The shared source uses this rule, so every
        /// process shows what the app shows (the widget's rule kept older-equal content).
        case appRefresh
        /// `HeadroomIOSTimelineProvider`: adopt only a strictly newer remote and resolve
        /// against the read taken before the write.
        case widgetTimeline
    }

    struct Outcome: Equatable, Sendable {
        let syncRead: iCloudSnapshotSyncRead
        /// The cache read the resolution used (post-write re-read under `.appRefresh`).
        let cacheRead: WidgetSnapshotCacheRead
        let resolution: IOSWidgetResolution
        /// The remote was adoptable against the first read, so a write was attempted. The app
        /// reloads widget timelines on this, whether or not the write succeeded or the write's
        /// own re-check found a newer cache.
        let adoptedRemote: Bool
    }

    static func adoptable(
        remote: WidgetSnapshotEnvelope, into cacheRead: WidgetSnapshotCacheRead, rule: AdoptionRule
    ) -> Bool {
        guard let cached = cacheRead.envelope else { return true }
        if remote.generatedAt > cached.generatedAt { return true }
        return rule == .appRefresh && remote.generatedAt == cached.generatedAt && remote != cached
    }

    static func load(
        sync: iCloudSnapshotSync, cache: WidgetSnapshotCache, rule: AdoptionRule,
        coordinator: (any CompanionCacheCoordinating)? = nil
    ) -> Outcome {
        let syncRead = sync.read()
        let cacheRead = cache.read()
        var resolvedCacheRead = cacheRead
        var adopted = false
        if case .snapshot(let envelope) = syncRead,
            adoptable(remote: envelope.snapshot, into: cacheRead, rule: rule)
        {
            adopted = true
            // Review 2 #3: loads overlap (the app runs each detached; the widget and intents
            // load in their own processes), so the read above may be stale by now. The write
            // re-reads the file it replaces and keeps a newer envelope another load already
            // wrote. Coordinated, the re-check and the replacement are one transaction; if
            // coordination fails nothing is written uncoordinated (KTD6.8).
            let commit = { () -> WidgetSnapshotCacheRead in
                if adoptable(remote: envelope.snapshot, into: cache.read(), rule: rule) {
                    try? cache.write(envelope.snapshot)
                }
                return cache.read()
            }
            let committed: WidgetSnapshotCacheRead?
            if let coordinator { committed = coordinator.coordinate(commit) } else { committed = commit() }
            if rule == .appRefresh { resolvedCacheRead = committed ?? cache.read() }
        }
        return Outcome(
            syncRead: syncRead, cacheRead: resolvedCacheRead,
            resolution: IOSWidgetSnapshotState.resolve(cacheRead: resolvedCacheRead, syncRead: syncRead),
            adoptedRemote: adopted)
    }

    /// Lifts build 33's winner into the resolved model through the resolver's v3-only rules
    /// (KTD6.5, KTD6.7) with an empty v4 cache. Non-content states map to their closest
    /// resolved state: "iCloud Not Available" is the scope-unavailable state, a schema mismatch
    /// asks for a newer iPhone build, a corrupt key with nothing cached is U10's "Snapshot
    /// Unreadable", and missing content (or only a corrupt local file) waits for the Mac.
    static func lift(_ outcome: Outcome, now: Date) -> CompanionResolvedSnapshot {
        switch outcome.resolution.state {
        case .content, .disabled:
            break
        case .setupNeeded:
            return CompanionResolvedSnapshot(state: .accountScopeUnavailable)
        case .incompatibleSchema:
            return CompanionResolvedSnapshot(state: .waiting(.updatePhone))
        case .corrupt where outcome.syncRead == .corrupt:
            // Build 33 resolves cached content first, so nothing usable stands in for the key.
            return CompanionResolvedSnapshot(state: .unreadable)
        case .waitingForMac, .corrupt, .demo:
            return CompanionResolvedSnapshot(state: .waiting(nil))
        }
        guard let winner = winner(outcome),
            let bytes = try? SyncedWidgetSnapshotCodec.encode(currentSchema(winner.envelope))
        else { return CompanionResolvedSnapshot(state: .waiting(nil)) }
        let resolved = CompanionSnapshotResolver.resolve(
            CompanionResolverInput(manifest: nil, v3: bytes, cache: .empty, now: now)
        ).snapshot
        guard winner.lineageUnknown, let content = resolved.content, content.notice == .updateMac else {
            return resolved
        }
        // The compatibility file carries no lineage, so a cache-only winner is no evidence of
        // an old Mac (R14): never claim "Update Headroom on your Mac" from it.
        return CompanionResolvedSnapshot(state: .content(content.withoutNotice()), diagnostics: resolved.diagnostics)
    }

    /// Stamps the inner envelope's current schema so the lift's round trip through the
    /// resolver is lossless (see `WidgetSnapshotEnvelope.atCurrentSchema`).
    private static func currentSchema(_ envelope: SyncedWidgetSnapshotEnvelope) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            schemaVersion: envelope.schemaVersion, publishedAt: envelope.publishedAt,
            sourceID: envelope.sourceID, sourcePlatform: envelope.sourcePlatform,
            snapshot: envelope.snapshot.atCurrentSchema,
            companionSourceID: envelope.companionSourceID,
            companionGeneration: envelope.companionGeneration)
    }

    private struct Winner {
        let envelope: SyncedWidgetSnapshotEnvelope
        let lineageUnknown: Bool
    }

    private static func winner(_ outcome: Outcome) -> Winner? {
        switch outcome.resolution.origin {
        case .sync:
            return outcome.syncRead.envelope.map { Winner(envelope: $0, lineageUnknown: false) }
        case .cache:
            guard let cached = outcome.cacheRead.envelope else { return nil }
            if let synced = outcome.syncRead.envelope, synced.snapshot == cached {
                // The cache holds what the key holds: the key's wrapper is the provenance.
                return Winner(envelope: synced, lineageUnknown: false)
            }
            return Winner(
                envelope: SyncedWidgetSnapshotEnvelope(
                    publishedAt: cached.generatedAt, sourceID: "", sourcePlatform: .unknown, snapshot: cached),
                lineageUnknown: true)
        case .demo, nil:
            return nil
        }
    }
}

extension CompanionResolvedContent {
    fileprivate func withoutNotice() -> CompanionResolvedContent {
        CompanionResolvedContent(
            origin: origin, notice: nil, sourceID: sourceID, generation: generation,
            generatedAt: generatedAt, chosenIntervalSeconds: chosenIntervalSeconds, display: display,
            widgetProviderSelection: widgetProviderSelection, widgetSparkEnabled: widgetSparkEnabled,
            reminderSummary: reminderSummary, answeredRequests: answeredRequests, ladder: ladder,
            providers: providers, apiSpend: apiSpend, freshness: freshness)
    }
}
