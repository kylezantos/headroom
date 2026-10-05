import Foundation

// MARK: - Resolved model (KTD6)

/// Where the shown content came from. Check-now requests go out only for `.v4` (KTD14.1).
public enum CompanionSnapshotOrigin: Equatable, Sendable {
    case v4
    /// The primary-only v3 key, lifted into the v4 model (KTD6.7).
    case v3
}

/// The one line that explains a compatibility gap (R14, KTD6.6).
public enum CompanionCompatibilityNotice: Equatable, Sendable {
    /// "Update Headroom on your Mac to see every account": a lineage-less v3 won.
    case updateMac
    /// "Update Headroom on this iPhone": the v4 data needs a newer reader.
    case updatePhone

    public var message: String {
        switch self {
        case .updateMac: "Update Headroom on your Mac to see every account"
        case .updatePhone: "Update Headroom on this iPhone"
        }
    }
}

/// Category-only diagnostics. No payload, title or source value ever enters these.
public enum CompanionResolverDiagnostic: Equatable, Sendable {
    case providerDigestMismatch(String)
    case providerImmutableGenerationViolation(String)
    case providerForeignSource(String)
    case providerUnreadable(String)
    case providerNeedsNewerReader(String)
    case manifestUnreadableUsedCache
    case manifestGenerationReset
    case olderManifestIgnored
    /// KTD6.5: a same-lineage v3 mirror ran ahead of its manifest by more than the dim
    /// threshold, so the v4 channel looks stuck and the mirror is shown.
    case v4ChannelStuck
    case v3DisabledOverriddenByNewerManifest
}

/// Per-provider lag against the manifest's expected payload generation (KTD6.3).
public enum CompanionProviderLag: Equatable, Sendable {
    case current
    /// Shown below the manifest's generation, still inside the grace period.
    case lagging(since: Date)
    /// Past the grace period: every row reads "Last known".
    case lastKnown(since: Date)

    public var showsLastKnown: Bool {
        if case .lastKnown = self { true } else { false }
    }
}

public enum CompanionProviderSource: Equatable, Sendable {
    case v4(CompanionPayloadEvidence)
    /// That Mac's v3 main account, used while the provider key is unusable.
    case v3Main
    /// No usable key and no v3 main: a skeleton that becomes "Waiting for your Mac" once
    /// the surface's freshness rule dims (KTD6.3).
    case skeleton
}

public struct CompanionResolvedWindow: Equatable, Sendable, Identifiable {
    public let summary: WidgetWindowSummary
    /// Flagged by the Mac; the app filters by the phone's Spark switch and the widget
    /// projection by the Mac's widget Spark switch (KTD13). No label heuristics here.
    public let isSpark: Bool

    public var id: String { summary.id }

    public init(summary: WidgetWindowSummary, isSpark: Bool) {
        self.summary = summary
        self.isSpark = isSpark
    }
}

public struct CompanionResolvedAccount: Equatable, Sendable, Identifiable {
    /// Headroom's local account ID; nil for a lifted v3 main, which carries none.
    public let accountID: String?
    public let title: String
    public let planName: String?
    public let freshness: WidgetProviderFreshness
    public let attention: CompanionAttention?
    public let bankedResets: Int?
    public let capturedAt: Date?
    public let windows: [CompanionResolvedWindow]
    public let isMain: Bool

    public var id: String { accountID ?? "main" }
    public var widgetWindows: [WidgetWindowSummary] { windows.map(\.summary) }
}

public struct CompanionResolvedProvider: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let source: CompanionProviderSource
    public let capabilityAttention: CompanionAttention?
    public let mainAccount: CompanionResolvedAccount?
    public let extraAccounts: [CompanionResolvedAccount]
    /// KTD7: "N more on your Mac" at the end of a capped stack.
    public let omittedAccountCount: Int
    public let lag: CompanionProviderLag
    public let payloadGeneration: Int64?
    public let effectiveIntervalSeconds: Double?

    public var accounts: [CompanionResolvedAccount] {
        (mainAccount.map { [$0] } ?? []) + extraAccounts
    }
}

public struct CompanionResolvedContent: Equatable, Sendable {
    public let origin: CompanionSnapshotOrigin
    public let notice: CompanionCompatibilityNotice?
    /// The Mac lineage, when known (v4, or a v3 mirror that declares one).
    public let sourceID: String?
    public let generation: Int64?
    public let generatedAt: Date
    public let chosenIntervalSeconds: Int?
    /// nil means defaults, Spark off and the old-Mac appearance note (KTD11).
    public let display: CompanionDisplayBlock?
    public let widgetProviderSelection: [String]?
    public let widgetSparkEnabled: Bool
    public let reminderSummary: CompanionReminderSummary?
    public let answeredRequests: [CompanionAnsweredRequest]
    public let ladder: CompanionDropLadder
    public let providers: [CompanionResolvedProvider]
    /// API spend rows in the Mac's spend order; a spend-only key has no provider card.
    public let apiSpend: [WidgetAPISpendSummary]
    public let freshness: CompanionFreshnessInputs
}

public enum CompanionResolvedState: Equatable, Sendable {
    /// KTD22: the local iCloud-account scope is unverified; no cached account content.
    case accountScopeUnavailable
    /// "Companion Sync Paused": a disabled tombstone or disabled v3 (never "old Mac").
    case paused
    /// Nothing readable yet; the notice says when a newer reader is needed.
    case waiting(CompanionCompatibilityNotice?)
    case content(CompanionResolvedContent)
}

public struct CompanionResolvedSnapshot: Equatable, Sendable {
    public let state: CompanionResolvedState
    public let diagnostics: [CompanionResolverDiagnostic]

    public init(state: CompanionResolvedState, diagnostics: [CompanionResolverDiagnostic] = []) {
        self.state = state
        self.diagnostics = diagnostics
    }

    public var content: CompanionResolvedContent? {
        if case .content(let content) = state { content } else { nil }
    }

    /// KTD13: the Home Screen widget envelope, computed from the resolved model (v4 or
    /// lifted v3), never a pass-through of the v3 key. Main accounts only, always
    /// "left", Spark rows filtered by the Mac's widget Spark switch.
    public func primaryProjection() -> WidgetSnapshotEnvelope? {
        guard let content else { return nil }
        let providers = content.providers.map { provider -> WidgetProviderSummary in
            guard let main = provider.mainAccount else {
                // Matches the Mac projector's `.pending(for:)` row for a provider with no data.
                return WidgetProviderSummary(
                    id: provider.id, displayName: provider.displayName, planLabel: nil,
                    freshness: .pending, windows: [], renewalDate: nil)
            }
            return WidgetProviderSummary(
                id: provider.id, displayName: provider.displayName, planLabel: main.planName,
                freshness: main.freshness,
                windows: main.windows.filter { !$0.isSpark || content.widgetSparkEnabled }
                    .map(\.summary),
                renewalDate: nil)
        }
        return WidgetSnapshotEnvelope(
            generatedAt: content.generatedAt, status: .enabled, providers: providers,
            apiSpendProviders: content.apiSpend,
            widgetProviderSelection: content.widgetProviderSelection)
    }

    /// The windows a surface shows: every account in the app and Siri, main accounts on
    /// Home Screen, Lock Screen and Control.
    public func shownWindows(for surface: CompanionFreshnessSurface) -> [WidgetWindowSummary] {
        guard let content else { return [] }
        return content.providers.flatMap { provider in
            surface.showsMainAccountsOnly
                ? (provider.mainAccount?.widgetWindows ?? [])
                : provider.accounts.flatMap(\.widgetWindows)
        }
    }
}

// MARK: - Resolver

/// Raw, already scope-verified reads plus the checked cache. The loader gathers these;
/// the resolver never touches KVS, files or identity (KTD6, KTD22).
public struct CompanionResolverInput: Sendable {
    public var manifest: Data?
    /// Raw provider key bytes by provider ID.
    public var providerKeys: [String: Data]
    public var v3: Data?
    public var cache: CompanionCacheContents
    public var now: Date

    public init(
        manifest: Data?, providerKeys: [String: Data] = [:], v3: Data?,
        cache: CompanionCacheContents = .empty, now: Date
    ) {
        self.manifest = manifest
        self.providerKeys = providerKeys
        self.v3 = v3
        self.cache = cache
        self.now = now
    }
}

public struct CompanionResolution: Equatable, Sendable {
    public let snapshot: CompanionResolvedSnapshot
    /// What the coordinated transaction persists, including first-seen times created at
    /// `now` for anything seen for the first time.
    public let cache: CompanionCacheContents
}

/// KTD6 rules 1–8 as one pure function. Run it inside the coordinated cache transaction
/// so first-seen creation and the merge are serialized across processes.
public enum CompanionSnapshotResolver {
    public static func resolve(_ input: CompanionResolverInput) -> CompanionResolution {
        var run = Run(input: input)
        let snapshot = run.resolve()
        return CompanionResolution(snapshot: snapshot, cache: run.cache)
    }

    static func manifestFirstSeenKey(sourceID: String, generation: Int64, generatedAt: CompanionWireDate)
        -> String
    {
        // generatedAt is part of the key so a generation reset never reuses an old first-seen.
        "m|\(sourceID)|\(generation)|\(generatedAt.epochSeconds)"
    }

    static func lagFirstSeenKey(sourceID: String, providerID: String, expected: Int64) -> String {
        "lag|\(sourceID)|\(providerID)|\(expected)"
    }

    static func v3FirstSeenKey(_ envelope: SyncedWidgetSnapshotEnvelope) -> String {
        "v3|\(envelope.companionLineage?.sourceID ?? "-")|\(envelope.snapshot.generatedAt.timeIntervalSince1970)"
    }
}

private struct ManifestCandidate {
    let manifest: CompanionActiveManifest
    let raw: Data
}

private struct PayloadCandidate {
    let payload: CompanionProviderPayload
    let raw: Data
    let evidence: CompanionPayloadEvidence
}

extension CompanionSnapshotResolver {
    fileprivate struct Run {
        let input: CompanionResolverInput
        var cache: CompanionCacheContents
        var diagnostics: [CompanionResolverDiagnostic] = []
        var usedFirstSeen: Set<String> = []
        /// The v3 content this run reconciled; the source of the "that Mac's v3 main" fallback.
        var reconciledV3: SyncedWidgetSnapshotEnvelope?

        init(input: CompanionResolverInput) {
            self.input = input
            self.cache = input.cache
        }

        mutating func resolve() -> CompanionResolvedSnapshot {
            let remote = CompanionSyncCodec.decodeManifest(input.manifest)
            let v3 = reconcileV3()
            reconciledV3 = v3

            // Rule 5: status before anything else. A tombstone always wins (Decision 1).
            if case .value(.disabled) = remote { return pause(keepingV3: v3?.snapshot.status == .disabled ? v3 : nil) }

            var readerTooOld = false
            var effective: ManifestCandidate?
            switch remote {
            case .value(.active(let manifest)):
                effective = adopt(ManifestCandidate(manifest: manifest, raw: input.manifest!))
            case .unsupportedReader, .unsupportedControlState:
                // Rule 6: v4 needs a newer reader; an unreadable v4 never hides readable v3.
                readerTooOld = true
            case .missing, .corrupt, .unsupportedSchema:
                if cache.paused { return pause(keepingV3: v3?.snapshot.status == .disabled ? v3 : nil) }
                effective = cachedManifest()
                if effective != nil, remote != .missing { diagnostics.append(.manifestUnreadableUsedCache) }
            case .value(.disabled):
                break
            }
            if effective != nil { cache.paused = false }

            if let v3, v3.snapshot.status == .disabled {
                if let manifest = effective?.manifest, manifest.generatedAt.date > v3.snapshot.generatedAt {
                    diagnostics.append(.v3DisabledOverriddenByNewerManifest)
                } else {
                    return pause(keepingV3: v3)
                }
            }

            guard !readerTooOld else {
                cache.manifest = nil
                cache.providers = [:]
                guard let v3 else { return finish(.waiting(.updatePhone)) }
                return finish(.content(lift(v3, notice: .updatePhone)))
            }

            guard let manifestCandidate = effective else {
                cache.manifest = nil
                cache.providers = [:]
                guard let v3 else { return finish(.waiting(nil)) }
                // A mirror alone (manifest not yet arrived) shows main accounts without the
                // update line; a lineage-less v3 is an older Mac (R14).
                return finish(.content(lift(v3, notice: v3.companionLineage == nil ? .updateMac : nil)))
            }

            let manifest = manifestCandidate.manifest
            let assembled = assembleV4(manifest)
            let threshold = CompanionFreshnessRule.threshold(
                largestEffectiveIntervalSeconds: largestInterval(manifest), isV3Only: false)

            if let v3 {
                let ahead = v3.snapshot.generatedAt.timeIntervalSince(manifest.generatedAt.date)
                if let lineage = v3.companionLineage {
                    if lineage.sourceID == manifest.sourceID {
                        // A mirror never wins while its manifest is readable, unless the v4
                        // channel looks stuck (ahead by more than the dim threshold).
                        if ahead > threshold {
                            diagnostics.append(.v4ChannelStuck)
                            return finish(.content(lift(v3, notice: nil)))
                        }
                    } else if ahead > 0 {
                        // Across lineages, generatedAt orders the data (KTD6.4).
                        return finish(.content(lift(v3, notice: nil)))
                    }
                } else if ahead > 0 {
                    return finish(.content(lift(v3, notice: .updateMac)))
                }
            }
            return finish(.content(assembled))
        }

        // MARK: v3

        /// The newest readable v3 between the fresh key read and the scoped cache. Only a
        /// fresh read of the key replaces the cached copy, never a v4 projection.
        mutating func reconcileV3() -> SyncedWidgetSnapshotEnvelope? {
            switch SyncedWidgetSnapshotCodec.decode(input.v3) {
            case .snapshot(let remote):
                if let cached = cache.v3?.envelope,
                    cached.snapshot.generatedAt > remote.snapshot.generatedAt
                {
                    return cached
                }
                cache.v3 = CompanionCachedV3(keyRead: remote)
                return remote
            case .incompatibleSchema:
                // An incompatible v3 never hides a readable v4, and is never shown.
                return nil
            case .missing, .corrupt:
                return cache.v3?.envelope
            }
        }

        mutating func pause(keepingV3 v3: SyncedWidgetSnapshotEnvelope?) -> CompanionResolvedSnapshot {
            // KTD22: keep only the paused state; account-bearing caches go.
            cache = CompanionCacheContents(paused: true, v3: v3.map { CompanionCachedV3(keyRead: $0) })
            return CompanionResolvedSnapshot(state: .paused, diagnostics: diagnostics)
        }

        mutating func finish(_ state: CompanionResolvedState) -> CompanionResolvedSnapshot {
            cache.firstSeen = cache.firstSeen.filter { usedFirstSeen.contains($0.key) }
            return CompanionResolvedSnapshot(state: state, diagnostics: diagnostics)
        }

        mutating func firstSeen(_ key: String) -> Date {
            usedFirstSeen.insert(key)
            if let existing = cache.firstSeen[key] { return existing.date }
            // Created once, inside the transaction, at whole-second precision.
            let created = CompanionWireDate(date: input.now) ?? CompanionWireDate(epochSeconds: 0)!
            cache.firstSeen[key] = created
            return created.date
        }

        // MARK: Lineage and generation (rule 4)

        func cachedManifest() -> ManifestCandidate? {
            guard let cached = cache.manifest,
                case .value(.active(let manifest)) = CompanionSyncCodec.decodeManifest(cached.raw)
            else { return nil }
            return ManifestCandidate(manifest: manifest, raw: cached.raw)
        }

        mutating func adopt(_ remote: ManifestCandidate) -> ManifestCandidate {
            let manifest = remote.manifest
            if let cached = cachedManifest() {
                let old = cached.manifest
                if old.sourceID == manifest.sourceID {
                    if manifest.generation == old.generation { return cached }
                    if manifest.generation < old.generation {
                        guard manifest.generatedAt.epochSeconds > old.generatedAt.epochSeconds else {
                            diagnostics.append(.olderManifestIgnored)
                            return cached
                        }
                        // A counter reset under one lineage: a new epoch, not stale data.
                        diagnostics.append(.manifestGenerationReset)
                        cache.providers = [:]
                    }
                } else {
                    guard manifest.generatedAt.epochSeconds > old.generatedAt.epochSeconds else {
                        diagnostics.append(.olderManifestIgnored)
                        return cached
                    }
                }
            }
            // A new lineage drops every other lineage's cached copies (KTD6.4).
            cache.providers = cache.providers.filter { $0.value.sourceID == manifest.sourceID }
            cache.manifest = CompanionCachedManifest(
                raw: remote.raw, sourceID: manifest.sourceID, generation: manifest.generation,
                generatedAt: manifest.generatedAt)
            return remote
        }

        func largestInterval(_ manifest: CompanionActiveManifest) -> Double {
            manifest.providers.values.map(\.effectiveIntervalSeconds).max()
                ?? Double(manifest.chosenIntervalSeconds)
        }

        // MARK: Providers (rules 2, 3, 7)

        mutating func assembleV4(_ manifest: CompanionActiveManifest) -> CompanionResolvedContent {
            var wanted = manifest.knownProviderOrder
            for id in manifest.knownSpendOrder where !wanted.contains(id) { wanted.append(id) }
            var chosen: [String: PayloadCandidate] = [:]
            for providerID in wanted {
                if let candidate = choosePayload(providerID, manifest: manifest) {
                    chosen[providerID] = candidate
                }
            }
            cache.providers = cache.providers.filter {
                wanted.contains($0.key) && $0.value.sourceID == manifest.sourceID
            }

            let v3Mirror =
                reconciledV3?.companionLineage?.sourceID == manifest.sourceID ? reconciledV3 : nil
            var providers: [CompanionResolvedProvider] = []
            for providerID in manifest.knownProviderOrder {
                let entry = manifest.providers[providerID]
                if let candidate = chosen[providerID], candidate.payload.mode == .subscription {
                    providers.append(
                        resolvedProvider(candidate, entry: entry, manifest: manifest))
                } else if chosen[providerID] == nil,
                    let summary = v3Mirror?.snapshot.providers.first(where: { $0.id == providerID })
                {
                    providers.append(liftedProvider(summary, interval: entry?.effectiveIntervalSeconds))
                } else if chosen[providerID]?.payload.mode != .spendOnly {
                    providers.append(
                        CompanionResolvedProvider(
                            id: providerID, displayName: ProviderID(providerID).displayName,
                            source: .skeleton, capabilityAttention: nil, mainAccount: nil,
                            extraAccounts: [], omittedAccountCount: 0, lag: .current,
                            payloadGeneration: nil,
                            effectiveIntervalSeconds: entry?.effectiveIntervalSeconds))
                }
            }
            let spend = manifest.knownSpendOrder.compactMap { chosen[$0]?.payload.apiSpend?.widgetSummary }
            let key = CompanionSnapshotResolver.manifestFirstSeenKey(
                sourceID: manifest.sourceID, generation: manifest.generation,
                generatedAt: manifest.generatedAt)
            return CompanionResolvedContent(
                origin: .v4, notice: nil, sourceID: manifest.sourceID,
                generation: manifest.generation, generatedAt: manifest.generatedAt.date,
                chosenIntervalSeconds: manifest.chosenIntervalSeconds, display: manifest.display,
                widgetProviderSelection: normalizedSelection(
                    manifest.widgetProviderSelection, available: manifest.knownProviderOrder),
                widgetSparkEnabled: manifest.widgetSparkEnabled,
                reminderSummary: manifest.reminderSummary,
                answeredRequests: manifest.answeredRequests, ladder: manifest.ladder,
                providers: providers, apiSpend: spend,
                freshness: CompanionFreshnessInputs(
                    generatedAt: manifest.generatedAt.date, firstSeen: firstSeen(key),
                    largestEffectiveIntervalSeconds: largestInterval(manifest), isV3Only: false))
        }

        /// Decision 4: equal generation needs the exact-byte digest; ahead and behind keys
        /// are structurally checked; the highest usable same-source candidate wins, and a
        /// same-generation mutation never replaces previously checked bytes.
        mutating func choosePayload(_ providerID: String, manifest: CompanionActiveManifest)
            -> PayloadCandidate?
        {
            let entry = manifest.providers[providerID]
            var remote: PayloadCandidate?
            if let raw = input.providerKeys[providerID] {
                switch CompanionSyncCodec.decodeProviderPayload(raw, providerID: providerID) {
                case .value(let payload) where payload.sourceID == manifest.sourceID:
                    if let entry, payload.payloadGeneration == entry.payloadGeneration {
                        if CompanionSyncCodec.digest(raw) == entry.digest {
                            remote = PayloadCandidate(payload: payload, raw: raw, evidence: .manifestDigestMatched)
                        } else {
                            diagnostics.append(.providerDigestMismatch(providerID))
                        }
                    } else {
                        remote = PayloadCandidate(payload: payload, raw: raw, evidence: .structural)
                    }
                case .value:
                    // KTD12: never assemble a provider from another Mac's key.
                    diagnostics.append(.providerForeignSource(providerID))
                case .unsupportedReader, .unsupportedSchema, .unsupportedControlState:
                    diagnostics.append(.providerNeedsNewerReader(providerID))
                case .corrupt:
                    diagnostics.append(.providerUnreadable(providerID))
                case .missing:
                    break
                }
            }

            var cached: PayloadCandidate?
            if let stored = cache.providers[providerID], stored.sourceID == manifest.sourceID,
                stored.observedDigest == CompanionSyncCodec.digest(stored.raw),
                case .value(let payload) = CompanionSyncCodec.decodeProviderPayload(
                    stored.raw, providerID: providerID),
                payload.sourceID == manifest.sourceID
            {
                var evidence = stored.evidence
                var usable = true
                if let entry, payload.payloadGeneration == entry.payloadGeneration {
                    if CompanionSyncCodec.digest(stored.raw) == entry.digest {
                        // The manifest caught up with an ahead key: now exactly verified.
                        evidence = .manifestDigestMatched
                    } else if stored.evidence == .structural {
                        diagnostics.append(.providerDigestMismatch(providerID))
                        usable = false
                    } else {
                        // Previously verified bytes for this generation are immutable.
                        diagnostics.append(.providerImmutableGenerationViolation(providerID))
                    }
                }
                if usable {
                    cached = PayloadCandidate(payload: payload, raw: stored.raw, evidence: evidence)
                }
            }

            let best: PayloadCandidate?
            switch (remote, cached) {
            case (let r?, let c?):
                if r.payload.payloadGeneration == c.payload.payloadGeneration {
                    if r.raw != c.raw { diagnostics.append(.providerImmutableGenerationViolation(providerID)) }
                    best = c.evidence == .manifestDigestMatched || r.evidence != .manifestDigestMatched ? c : r
                } else {
                    best = r.payload.payloadGeneration > c.payload.payloadGeneration ? r : c
                }
            case (let r?, nil): best = r
            case (nil, let c?): best = c
            case (nil, nil): best = nil
            }
            if let best {
                cache.providers[providerID] = CompanionCachedProvider(
                    raw: best.raw, sourceID: manifest.sourceID, providerID: providerID,
                    generation: best.payload.payloadGeneration, evidence: best.evidence)
            } else {
                cache.providers[providerID] = nil
            }
            return best
        }

        mutating func resolvedProvider(
            _ candidate: PayloadCandidate, entry: CompanionManifestProviderEntry?,
            manifest: CompanionActiveManifest
        ) -> CompanionResolvedProvider {
            let payload = candidate.payload
            var lag = CompanionProviderLag.current
            if let entry, payload.payloadGeneration < entry.payloadGeneration {
                // First-seen belongs to the expected generation, so heartbeats that keep it
                // do not restart the grace (Decision 4).
                let since = firstSeen(
                    CompanionSnapshotResolver.lagFirstSeenKey(
                        sourceID: manifest.sourceID, providerID: payload.providerID,
                        expected: entry.payloadGeneration))
                let grace = CompanionFreshnessRule.lagGrace(
                    chosenIntervalSeconds: manifest.chosenIntervalSeconds)
                lag = input.now.timeIntervalSince(since) >= grace
                    ? .lastKnown(since: since) : .lagging(since: since)
            }
            return CompanionResolvedProvider(
                id: payload.providerID, displayName: ProviderID(payload.providerID).displayName,
                source: .v4(candidate.evidence), capabilityAttention: payload.capabilityAttention,
                mainAccount: payload.mainAccount.map { Self.account($0, isMain: true) },
                extraAccounts: payload.accounts.map { Self.account($0, isMain: false) },
                omittedAccountCount: payload.omittedAccountCount, lag: lag,
                payloadGeneration: payload.payloadGeneration,
                effectiveIntervalSeconds: entry?.effectiveIntervalSeconds)
        }

        static func account(_ account: CompanionAccountSummary, isMain: Bool) -> CompanionResolvedAccount {
            let windows: [CompanionResolvedWindow] =
                account.freshness == .unknown
                ? []
                : account.windows.compactMap { window in
                    window.widgetSummary(accountCapturedAt: account.capturedAt).map {
                        CompanionResolvedWindow(summary: $0, isSpark: window.isSpark)
                    }
                }
            return CompanionResolvedAccount(
                accountID: account.id, title: account.displayTitle, planName: account.planName,
                freshness: account.widgetFreshness, attention: account.attention,
                bankedResets: account.bankedResets,
                capturedAt: account.freshness == .unknown ? nil : account.capturedAt?.date,
                windows: windows, isMain: isMain)
        }

        // MARK: v3 lift (rule 7)

        mutating func lift(_ v3: SyncedWidgetSnapshotEnvelope, notice: CompanionCompatibilityNotice?)
            -> CompanionResolvedContent
        {
            let lineage = v3.companionLineage
            return CompanionResolvedContent(
                origin: .v3, notice: notice, sourceID: lineage?.sourceID,
                generation: lineage?.generation, generatedAt: v3.snapshot.generatedAt,
                chosenIntervalSeconds: nil, display: nil,
                widgetProviderSelection: v3.snapshot.widgetProviderSelection,
                widgetSparkEnabled: false, reminderSummary: nil, answeredRequests: [],
                ladder: .full,
                providers: v3.snapshot.providers.map { liftedProvider($0, interval: nil) },
                apiSpend: v3.snapshot.apiSpendProviders,
                freshness: CompanionFreshnessInputs(
                    generatedAt: v3.snapshot.generatedAt,
                    firstSeen: firstSeen(CompanionSnapshotResolver.v3FirstSeenKey(v3)),
                    largestEffectiveIntervalSeconds: nil, isV3Only: true))
        }

        func liftedProvider(_ summary: WidgetProviderSummary, interval: Double?) -> CompanionResolvedProvider {
            let windows = summary.windows.map {
                CompanionResolvedWindow(summary: Self.normalized($0), isSpark: false)
            }
            let main = CompanionResolvedAccount(
                accountID: nil, title: summary.displayName, planName: summary.planLabel,
                freshness: summary.freshness, attention: nil, bankedResets: nil,
                capturedAt: nil, windows: windows, isMain: true)
            return CompanionResolvedProvider(
                id: summary.id, displayName: summary.displayName, source: .v3Main,
                capabilityAttention: nil, mainAccount: main, extraAccounts: [],
                omittedAccountCount: 0, lag: .current, payloadGeneration: nil,
                effectiveIntervalSeconds: interval)
        }

        /// KTD6.2: the phone applies the shared normalization idempotently to lifted rows,
        /// and severity derives from the normalized value.
        static func normalized(_ window: WidgetWindowSummary) -> WidgetWindowSummary {
            guard let display = UsageDisplayValue(percentRemaining: window.percentRemaining) else {
                return window
            }
            return WidgetWindowSummary(
                kind: window.kind, label: window.label, percentRemaining: display.percentRemaining,
                utilization: window.utilization, resetSchedule: window.resetSchedule,
                resetLabel: window.resetLabel, resetTimeZoneIdentifier: window.resetTimeZoneIdentifier,
                observedAt: window.observedAt, severity: WidgetUsageSeverity(display.severity),
                freshness: window.freshness, billingPeriodDuration: window.billingPeriodDuration)
        }

        func normalizedSelection(_ selection: [String]?, available: [String]) -> [String]? {
            selection.map { ids in
                var seen: Set<String> = []
                return ids.filter { available.contains($0) && seen.insert($0).inserted }
            }
        }
    }
}
