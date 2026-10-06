import Foundation

// Mac-only by folder (KTD4). The store captures its state on the main actor; one serial
// actor encodes, measures and writes v3 and v4 together (KTD5, KTD7, KTD8, KTD22).

// MARK: - Capture

public enum CompanionPublishStatus: Sendable, Equatable {
    case enabled
    case disabled
}

/// One provider key's content before it is stamped with a lineage and generation.
public struct CompanionCapturedProvider: Sendable, Equatable {
    public let providerID: String
    public let mode: CompanionPayloadMode
    public let capabilityAttention: CompanionAttention?
    public let mainAccount: CompanionAccountSummary?
    /// Extra accounts in Make Main order, main removed (KTD6.1).
    public let extraAccounts: [CompanionAccountSummary]
    public let apiSpend: CompanionSpendSummary?
    public let effectiveIntervalSeconds: Double

    public init(
        providerID: String, mode: CompanionPayloadMode,
        capabilityAttention: CompanionAttention? = nil,
        mainAccount: CompanionAccountSummary?, extraAccounts: [CompanionAccountSummary] = [],
        apiSpend: CompanionSpendSummary? = nil, effectiveIntervalSeconds: Double
    ) {
        self.providerID = providerID
        self.mode = mode
        self.capabilityAttention = capabilityAttention
        self.mainAccount = mainAccount
        self.extraAccounts = extraAccounts
        self.apiSpend = apiSpend
        self.effectiveIntervalSeconds = effectiveIntervalSeconds
    }

    public func payload(sourceID: String, generation: Int64) throws -> CompanionProviderPayload {
        try CompanionProviderPayload(
            sourceID: sourceID, providerID: providerID, payloadGeneration: generation, mode: mode,
            capabilityAttention: capabilityAttention, mainAccount: mainAccount,
            accounts: extraAccounts, apiSpend: apiSpend)
    }
}

/// The whole phone-bound state at one moment. The facade stamps `generation` on the
/// main actor when the state is captured (KTD8), so generation order is capture order.
public struct CompanionPublishCapture: Sendable, Equatable {
    public internal(set) var generation: Int64
    public let generatedAt: CompanionWireDate
    public let status: CompanionPublishStatus
    /// Every key to write: subscription providers in display order, then spend-only ones.
    public let providers: [CompanionCapturedProvider]
    public let providerOrder: [String]
    public let spendOrder: [String]
    public let chosenIntervalSeconds: Int
    public let display: CompanionDisplayBlock?
    public let widgetProviderSelection: [String]?
    public let widgetSparkEnabled: Bool
    public let reminderSummary: CompanionReminderSummary?
    /// KTD14.3 / Decision 2: the Mac's recent check-now answers, echoed in the manifest so a
    /// phone can complete from the snapshot before the receipt arrives.
    public internal(set) var answeredRequests: [CompanionAnsweredRequest]
    /// The paired schema-3 phone export of the same state (KTD5, KTD13).
    public let v3: WidgetSnapshotEnvelope

    public init(
        generation: Int64 = 0, generatedAt: CompanionWireDate, status: CompanionPublishStatus,
        providers: [CompanionCapturedProvider] = [], providerOrder: [String] = [],
        spendOrder: [String] = [], chosenIntervalSeconds: Int,
        display: CompanionDisplayBlock? = nil, widgetProviderSelection: [String]? = nil,
        widgetSparkEnabled: Bool = false, reminderSummary: CompanionReminderSummary? = nil,
        answeredRequests: [CompanionAnsweredRequest] = [],
        v3: WidgetSnapshotEnvelope
    ) {
        self.generation = generation
        self.generatedAt = generatedAt
        self.status = status
        self.providers = providers
        self.providerOrder = providerOrder
        self.spendOrder = spendOrder
        self.chosenIntervalSeconds = chosenIntervalSeconds
        self.display = display
        self.widgetProviderSelection = widgetProviderSelection
        self.widgetSparkEnabled = widgetSparkEnabled
        self.reminderSummary = reminderSummary
        self.answeredRequests = CompanionAnsweredRequest.terminalHistory(answeredRequests)
        self.v3 = v3
    }

    /// Sync off: no account content is captured at all.
    public static func disabled(at generatedAt: CompanionWireDate, chosenIntervalSeconds: Int) -> Self {
        Self(
            generatedAt: generatedAt, status: .disabled, chosenIntervalSeconds: chosenIntervalSeconds,
            v3: .disabled(generatedAt: generatedAt.date))
    }

    /// KTD8: a change here forces an immediate flush instead of waiting out the spacing:
    /// status, account set, main account, titles, display block, intervals, widget
    /// selection (and the provider set, which is how provider on/off shows up).
    struct Structure: Equatable {
        let status: CompanionPublishStatus
        let providerOrder: [String]
        let spendOrder: [String]
        let accounts: [String: [String]]
        let titles: [String: [String]]
        let display: CompanionDisplayBlock?
        let chosenIntervalSeconds: Int
        let effectiveIntervals: [String: Double]
        let widgetProviderSelection: [String]?
        let widgetSparkEnabled: Bool
    }

    var structure: Structure {
        var accounts: [String: [String]] = [:]
        var titles: [String: [String]] = [:]
        var intervals: [String: Double] = [:]
        for provider in providers {
            let all = (provider.mainAccount.map { [$0] } ?? []) + provider.extraAccounts
            accounts[provider.providerID] = all.map(\.id)
            titles[provider.providerID] = all.map(\.title)
            intervals[provider.providerID] = provider.effectiveIntervalSeconds
        }
        return Structure(
            status: status, providerOrder: providerOrder, spendOrder: spendOrder,
            accounts: accounts, titles: titles, display: display,
            chosenIntervalSeconds: chosenIntervalSeconds, effectiveIntervals: intervals,
            widgetProviderSelection: widgetProviderSelection, widgetSparkEnabled: widgetSparkEnabled)
    }
}

// MARK: - Publish image (pure)

/// Builds the exact bytes of one publish. Pure, so the KTD13 parity test and the
/// publisher share it: the parity test resolves these bytes on the phone side.
public enum CompanionPublishImage {
    /// The build-33-visible source label; the lineage UUID never goes here (KTD5).
    public static let v3SourceLabel = "Mac"

    public static func manifest(
        capture: CompanionPublishCapture, sourceID: String, macAppVersion: String?,
        entries: [String: CompanionManifestProviderEntry], ladderLevel: Int
    ) throws -> CompanionActiveManifest {
        try CompanionActiveManifest(
            sourceID: sourceID, generation: capture.generation, generatedAt: capture.generatedAt,
            macAppVersion: macAppVersion, providerOrder: capture.providerOrder, providers: entries,
            spendOrder: capture.spendOrder, chosenIntervalSeconds: capture.chosenIntervalSeconds,
            display: capture.display, widgetProviderSelection: capture.widgetProviderSelection,
            widgetSparkEnabled: capture.widgetSparkEnabled,
            reminderSummary: capture.reminderSummary, answeredRequests: capture.answeredRequests,
            dropLadderLevel: ladderLevel)
    }

    /// The v3 key: one shared `generatedAt` with the manifest and the lineage pair.
    public static func v3Bytes(capture: CompanionPublishCapture, sourceID: String) throws -> Data {
        try SyncedWidgetSnapshotCodec.encode(
            SyncedWidgetSnapshotEnvelope(
                publishedAt: capture.generatedAt.date, sourceID: v3SourceLabel,
                sourcePlatform: .macOS, snapshot: capture.v3,
                companionSourceID: sourceID, companionGeneration: capture.generation))
    }

    public static func entry(for bytes: Data, generation: Int64, interval: Double) throws
        -> CompanionManifestProviderEntry
    {
        try CompanionManifestProviderEntry(
            payloadGeneration: generation, digest: CompanionSyncCodec.digest(bytes),
            effectiveIntervalSeconds: interval.isFinite && interval > 0 ? interval : 60)
    }

    /// Every key of a from-scratch publish of `capture`, for tests and the parity check.
    public static func fullImage(
        capture: CompanionPublishCapture, sourceID: String, macAppVersion: String? = nil
    ) throws -> (manifest: Data, providers: [String: Data], v3: Data, ladderLevel: Int) {
        let payloads = capture.providers.compactMap {
            try? $0.payload(sourceID: sourceID, generation: capture.generation)
        }
        let intervals = Dictionary(
            uniqueKeysWithValues: capture.providers.map { ($0.providerID, $0.effectiveIntervalSeconds) })
        func entries(_ values: [String: Data]) throws -> [String: CompanionManifestProviderEntry] {
            try values.reduce(into: [:]) { result, item in
                result[item.key] = try entry(
                    for: item.value, generation: capture.generation, interval: intervals[item.key] ?? 60)
            }
        }
        let fit = try CompanionPayloadBudget.fit(payloads: payloads, protocolValues: [:]) { level, values in
            try CompanionSyncCodec.encode(
                CompanionManifest.active(
                    manifest(
                        capture: capture, sourceID: sourceID, macAppVersion: macAppVersion,
                        entries: entries(values), ladderLevel: level)))
        }
        return (fit.manifest, fit.providerValues, try v3Bytes(capture: capture, sourceID: sourceID), fit.ladderLevel)
    }

    /// Change detection that ignores timestamps (KTD8): capture and observation times
    /// become a fixed sentinel and the generation is zeroed, so only content differs.
    /// Separate from the integrity digest, which covers the exact stored bytes.
    static func fingerprint(_ payload: CompanionProviderPayload) -> String {
        let sentinel = CompanionWireDate(epochSeconds: 0)!
        func neutral(_ account: CompanionAccountSummary) -> CompanionAccountSummary {
            let windows = account.windows.map { window in
                (try? CompanionSlimWindow(
                    kind: window.kind, kindName: window.kindName,
                    billingPeriodDuration: window.billingPeriodDuration,
                    percentRemaining: window.percentRemaining, utilization: window.utilization,
                    resetKind: window.resetKind, resetDeadline: window.resetDeadline,
                    resetReason: window.resetReason, freshness: window.freshness,
                    observedAtOverride: window.observedAtOverride.map { _ in sentinel },
                    unavailableSince: window.unavailableSince, isSpark: window.isSpark)) ?? window
            }
            return (try? CompanionAccountSummary(
                id: account.id, title: account.title, planName: account.planName,
                freshness: account.freshness, capturedAt: account.capturedAt.map { _ in sentinel },
                attention: account.attention, needsAttention: account.needsAttention,
                bankedResets: account.bankedResets, windows: windows)) ?? account
        }
        let spend = payload.apiSpend.map { spend in
            (try? CompanionSpendSummary(
                id: spend.id, displayName: spend.displayName, amount: spend.amount,
                currency: spend.currency, periodLabel: spend.periodLabel, kind: spend.kind,
                capturedAt: spend.capturedAt.map { _ in sentinel }, freshness: spend.freshness,
                attention: spend.attention, needsAttention: spend.needsAttention)) ?? spend
        }
        let stripped = try? CompanionProviderPayload(
            sourceID: payload.sourceID, providerID: payload.providerID, payloadGeneration: 0,
            mode: payload.mode, capabilityAttention: payload.capabilityAttention,
            mainAccount: payload.mainAccount.map(neutral), accounts: payload.accounts.map(neutral),
            omittedAccountCount: payload.omittedAccountCount, apiSpend: spend)
        let bytes = (try? CompanionSyncCodec.encode(stripped ?? payload)) ?? Data()
        return CompanionSyncCodec.digest(bytes)
    }

    /// Every observation the payload carries, keyed by what it observes (KTD8 honest
    /// stamp): account capture times, retained-row overrides and the spend capture time.
    static func observations(_ payload: CompanionProviderPayload) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for account in payload.allAccounts {
            if let captured = account.capturedAt { result["a|\(account.id)"] = captured.epochSeconds }
            for window in account.windows {
                guard let observed = window.observedAtOverride else { continue }
                let name = "\(window.kind.rawValue)|\(window.kindName ?? "")"
                result["w|\(account.id)|\(name)"] = observed.epochSeconds
            }
        }
        if let captured = payload.apiSpend?.capturedAt { result["s"] = captured.epochSeconds }
        return result
    }
}

// MARK: - Lineage and diagnostics (Mac preferences)

/// KTD6.4: a random UUID made once per Mac install and a counter that only increases
/// within it. Never a host, serial or user name.
public final class CompanionLineage: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    static let sourceIDKey = "companionSync.sourceID.v1"
    static let generationKey = "companionSync.generation.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var sourceID: String {
        lock.withLock {
            if let stored = defaults.string(forKey: Self.sourceIDKey),
                let uuid = UUID(uuidString: stored)
            {
                return uuid.uuidString.lowercased()
            }
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: Self.sourceIDKey)
            return created
        }
    }

    /// Persisted before it is used, so a relaunch can never reissue a generation.
    public func nextGeneration() -> Int64 {
        lock.withLock {
            let next = (defaults.object(forKey: Self.generationKey) as? NSNumber)?.int64Value ?? 0
            let issued = max(0, next) + 1
            defaults.set(NSNumber(value: issued), forKey: Self.generationKey)
            return issued
        }
    }

    /// The last issued generation, for diagnostics only.
    public var currentGeneration: Int64? {
        lock.withLock { (defaults.object(forKey: Self.generationKey) as? NSNumber)?.int64Value }
    }

    public var hasLineage: Bool {
        lock.withLock { defaults.string(forKey: Self.sourceIDKey) != nil }
    }
}

/// What `--dump-phone-sync` and the Settings footnote read (KTD22 diagnostics). Key
/// names, byte counts, times and categories only; never payload contents.
public struct CompanionPublishDiagnostics: Codable, Equatable, Sendable {
    public var lastPublishAt: Date?
    public var lastGeneration: Int64?
    public var ladderLevel: Int
    /// Bytes per key at the last publish, the v3 key included.
    public var keyBytes: [String: Int]
    public var lastQuotaEventAt: Date?
    /// A static category (`overBudget`, `writeFailed`), never an interpolated error.
    public var lastFailure: String?
    public var lastSweepAt: Date?

    public init(
        lastPublishAt: Date? = nil, lastGeneration: Int64? = nil, ladderLevel: Int = 0,
        keyBytes: [String: Int] = [:], lastQuotaEventAt: Date? = nil, lastFailure: String? = nil,
        lastSweepAt: Date? = nil
    ) {
        self.lastPublishAt = lastPublishAt
        self.lastGeneration = lastGeneration
        self.ladderLevel = ladderLevel
        self.keyBytes = keyBytes
        self.lastQuotaEventAt = lastQuotaEventAt
        self.lastFailure = lastFailure
        self.lastSweepAt = lastSweepAt
    }
}

public final class CompanionPublishDiagnosticsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    static let key = "companionSync.diagnostics.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> CompanionPublishDiagnostics {
        guard let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode(CompanionPublishDiagnostics.self, from: data)
        else { return CompanionPublishDiagnostics() }
        return decoded
    }

    public func save(_ diagnostics: CompanionPublishDiagnostics) {
        guard let data = try? JSONEncoder().encode(diagnostics) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Publisher

/// The one serial, coalesced publisher (KTD8). A publish is one store-wide flush that
/// writes the changed provider keys, the manifest and the v3 key together under one
/// `generatedAt`. Flushes are spaced at least `flushSpacing` apart; merges in between
/// only replace the pending capture. Forced flushes skip the spacing.
public actor CompanionPublisher {
    public struct Configuration: Sendable {
        public var sourceID: String
        public var macAppVersion: String?
        public var flushSpacing: TimeInterval
        public var now: @Sendable () -> Date
        /// Off in tests, which drive `tick()` against an injected clock instead.
        public var autoSchedule: Bool
        public var sleep: @Sendable (TimeInterval) async -> Void

        public init(
            sourceID: String, macAppVersion: String? = nil, flushSpacing: TimeInterval = 60,
            now: @escaping @Sendable () -> Date = Date.init, autoSchedule: Bool = true,
            sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
                try? await Task.sleep(for: .seconds(max(0, seconds)))
            }
        ) {
            self.sourceID = sourceID
            self.macAppVersion = macAppVersion
            self.flushSpacing = flushSpacing
            self.now = now
            self.autoSchedule = autoSchedule
            self.sleep = sleep
        }
    }

    public enum FlushOutcome: Equatable, Sendable {
        case published(generation: Int64, writes: Int)
        case unchanged
        case swept
        case overBudget
        case writeFailed
    }

    private struct PublishedProvider {
        let fingerprint: String
        let digest: String
        let entry: CompanionManifestProviderEntry
        let observations: [String: Int64]
        let bytes: Int
    }

    private let store: any iCloudKeyValueSyncing
    private let configuration: Configuration
    private let diagnosticsStore: CompanionPublishDiagnosticsStore?
    private let participants: [any CompanionSyncLifecycle]
    private let onDiagnostics: (@Sendable (CompanionPublishDiagnostics) -> Void)?

    private var pending: CompanionPublishCapture?
    private var pendingForced = false
    private var captureProvider: (@MainActor @Sendable () -> CompanionPublishCapture?)?

    private var published: [String: PublishedProvider] = [:]
    private var publishedManifestDigest: String?
    private var publishedManifestFingerprint: String?
    private var publishedV3Digest: String?
    private var publishedStructure: CompanionPublishCapture.Structure?
    private var publishedInterval: TimeInterval?
    private var lastWriteAt: Date?
    /// Every heartbeat attempt and every failed flush. The heartbeat is due one interval
    /// after the later of this and `lastWriteAt`, so a heartbeat that cannot write (over
    /// budget, a failed write, no capture) waits a whole interval, not the timer's 1 s floor.
    private var lastAttemptAt: Date?
    private var lastPublishedGeneration: Int64 = -1
    /// KTD8: every key on the first publish after launch, after sync turns on and after
    /// an iCloud account change, whatever the coalescer's memory says.
    private var writeAll = true
    private var lastStatus: CompanionPublishStatus?
    private var sweptWhileDisabled = false
    private var quotaFloor = 0
    private var lastFit = true
    private var diagnostics: CompanionPublishDiagnostics
    private var timer: Task<Void, Never>?
    /// Participant calls run in decision order on one chain, so the actor never suspends
    /// mid-decision (a suspension would let a newer flush interleave with an older one).
    private var participantChain: Task<Void, Never>?

    public init(
        store: any iCloudKeyValueSyncing,
        configuration: Configuration,
        diagnosticsStore: CompanionPublishDiagnosticsStore? = nil,
        participants: [any CompanionSyncLifecycle] = [],
        onDiagnostics: (@Sendable (CompanionPublishDiagnostics) -> Void)? = nil
    ) {
        self.store = store
        self.configuration = configuration
        self.diagnosticsStore = diagnosticsStore
        self.participants = participants
        self.onDiagnostics = onDiagnostics
        self.diagnostics = diagnosticsStore?.load() ?? CompanionPublishDiagnostics()
    }

    /// Heartbeats and forced republishes ask the main actor for a freshly stamped capture.
    public func setCaptureProvider(_ provider: @escaping @MainActor @Sendable () -> CompanionPublishCapture?) {
        captureProvider = provider
    }

    public var currentDiagnostics: CompanionPublishDiagnostics { diagnostics }

    /// A new capture. Superseded work is dropped: a capture never replaces a newer
    /// pending one, and nothing at or below the last published generation is written.
    public func receive(_ capture: CompanionPublishCapture, forced: Bool = false) async {
        guard capture.generation > lastPublishedGeneration,
            capture.generation > (pending?.generation ?? -1)
        else { return }
        pending = capture
        pendingForced = pendingForced || forced
        await evaluate()
    }

    /// Re-evaluates due work now: the timer's entry point, and the test seam.
    public func tick() async {
        await evaluate()
    }

    /// KTD8 / KTD14.5: check-now finish. Publishes now, skipping the spacing, and returns the
    /// generation the phone must assemble — this capture's, or a newer one already stamped
    /// after it (which, being captured later, carries the same answers). Nil when nothing
    /// could be published (sync off, over budget, a failed write).
    public func publishForced(_ capture: CompanionPublishCapture) async -> Int64? {
        var target = capture
        if let pending, pending.generation > target.generation { target = pending }
        guard target.generation > lastPublishedGeneration else {
            return lastPublishedGeneration >= capture.generation ? lastPublishedGeneration : nil
        }
        pending = nil
        pendingForced = false
        let now = configuration.now()
        guard target.status == .enabled else {
            pending = target
            pendingForced = true
            await evaluate()
            return nil
        }
        enterEnabled()
        let outcome = await flush(target, forced: true, heartbeat: false, now: now, includeFreshObservations: true)
        schedule(now: configuration.now())
        switch outcome {
        case .published(let generation, _): return generation
        case .unchanged: return lastPublishedGeneration >= capture.generation ? lastPublishedGeneration : nil
        case .swept, .overBudget, .writeFailed: return nil
        }
    }

    /// KTD8: pending writes flush on system sleep and app quit, spacing or not.
    public func flushPending() async {
        guard pending != nil else { return }
        pendingForced = true
        await evaluate()
    }

    /// KTD22: republish every key to the new store, and let participants reset.
    public func accountDidChange() async {
        published = [:]
        publishedManifestDigest = nil
        publishedV3Digest = nil
        writeAll = true
        // While sync is off, the new account's store gets the sweep too (KTD22).
        sweptWhileDisabled = false
        notifyParticipants { await $0.companionSyncAccountDidChange() }
        await republishNow()
    }

    /// KTD7: the quota signal is a diagnostic that forces one extra ladder step, only
    /// when it fires while the measured bytes were under budget.
    public func recordQuotaEvent(_ event: iCloudKeyValueQuotaEvent) async {
        diagnostics.lastQuotaEventAt = event.observedAt
        if lastFit { quotaFloor = min(2, max(quotaFloor, diagnostics.ladderLevel) + 1) }
        saveDiagnostics()
        await republishNow()
    }

    // MARK: Decisions

    private func republishNow() async {
        if pending == nil, let captureProvider, let fresh = await captureProvider(),
            fresh.generation > lastPublishedGeneration
        {
            pending = fresh
        }
        pendingForced = true
        await evaluate()
    }

    private func evaluate() async {
        let now = configuration.now()
        if let capture = pending {
            if capture.status == .disabled {
                pending = nil
                pendingForced = false
                if lastStatus != .disabled || !sweptWhileDisabled {
                    sweep(capture)
                }
                lastStatus = .disabled
                lastPublishedGeneration = max(lastPublishedGeneration, capture.generation)
                schedule(now: now)
                return
            }
            enterEnabled()
            let structural = publishedStructure.map { $0 != capture.structure } ?? true
            let spaced = lastWriteAt.map { now.timeIntervalSince($0) >= configuration.flushSpacing } ?? true
            if pendingForced || structural || writeAll || spaced {
                let forced = pendingForced || structural || writeAll
                pending = nil
                pendingForced = false
                _ = await flush(capture, forced: forced, heartbeat: false, now: now)
            }
        } else if lastStatus == .enabled, let base = heartbeatBase, let interval = publishedInterval,
            now.timeIntervalSince(base) >= interval, let captureProvider
        {
            // Heartbeat: nothing dirty for a whole chosen interval. Ask for a fresh capture
            // so the manifest and the v3 mirror move together under a new generatedAt.
            lastAttemptAt = now
            if let fresh = await captureProvider(), fresh.generation > lastPublishedGeneration {
                if fresh.status == .disabled {
                    pending = fresh
                    await evaluate()
                    return
                }
                _ = await flush(fresh, forced: false, heartbeat: true, now: configuration.now())
            }
        }
        schedule(now: configuration.now())
    }

    /// The latest write or attempt; nil until the first successful write.
    private var heartbeatBase: Date? {
        guard let lastWriteAt else { return nil }
        return max(lastWriteAt, lastAttemptAt ?? lastWriteAt)
    }

    private func enterEnabled() {
        guard lastStatus != .enabled else { return }
        // Sync on (or the first enabled capture this launch): write everything.
        if lastStatus == .disabled { writeAll = true }
        lastStatus = .enabled
        sweptWhileDisabled = false
        notifyParticipants { await $0.companionSyncDidEnable() }
    }

    private func schedule(now: Date) {
        guard configuration.autoSchedule else { return }
        timer?.cancel()
        let wake: Date?
        if pending != nil {
            wake = lastWriteAt.map { $0.addingTimeInterval(configuration.flushSpacing) } ?? now
        } else if lastStatus == .enabled, let base = heartbeatBase, let interval = publishedInterval {
            wake = base.addingTimeInterval(interval)
        } else {
            wake = nil
        }
        guard let wake else { return }
        let delay = max(1, wake.timeIntervalSince(now))
        let sleep = configuration.sleep
        timer = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    // MARK: Writes

    /// One store-wide flush. Provider keys are rewritten only when their content changed
    /// (timestamps ignored), when an included observation advanced by at least one chosen
    /// interval (any advance at check-now completion), when iCloud no longer holds the bytes
    /// last written, or on write-all.
    @discardableResult
    private func flush(
        _ capture: CompanionPublishCapture, forced: Bool, heartbeat: Bool, now: Date,
        includeFreshObservations: Bool = false
    ) async -> FlushOutcome {
        let sourceID = configuration.sourceID
        let generation = capture.generation
        // KTD8: never a lower generation after a higher one, even if a capture provider
        // call let a newer flush land first.
        guard generation > lastPublishedGeneration else { return .unchanged }
        let interval = TimeInterval(capture.chosenIntervalSeconds)
        let payloads = capture.providers.compactMap { try? $0.payload(sourceID: sourceID, generation: generation) }
        let intervals = Dictionary(
            uniqueKeysWithValues: capture.providers.map { ($0.providerID, $0.effectiveIntervalSeconds) })

        // Contract Decision 3: the measured set is every value under the v4 namespace,
        // including keys a newer build wrote that this one does not know. Provider keys and
        // the manifest are this flush's own and are added below as they will stand.
        var protocolValues: [String: Data] = [:]
        for key in store.keys(withPrefix: CompanionSyncKeys.namespace)
        where key != CompanionSyncKeys.manifest && !key.hasPrefix(CompanionSyncKeys.providerPrefix) {
            if let data = store.data(forKey: key) { protocolValues[key] = data }
        }

        let fit: CompanionBudgetFit
        do {
            fit = try CompanionPayloadBudget.fit(
                payloads: payloads, protocolValues: protocolValues, minimumLevel: quotaFloor
            ) { level, values in
                let entries = try values.reduce(into: [String: CompanionManifestProviderEntry]()) { result, item in
                    result[item.key] = try CompanionPublishImage.entry(
                        for: item.value, generation: generation, interval: intervals[item.key] ?? interval)
                }
                return try CompanionSyncCodec.encode(
                    CompanionManifest.active(
                        CompanionPublishImage.manifest(
                            capture: capture, sourceID: sourceID,
                            macAppVersion: configuration.macAppVersion, entries: entries,
                            ladderLevel: level)))
            }
        } catch {
            // Decision 3: stop and keep the last valid content rather than cap accounts.
            lastFit = false
            recordFailure("overBudget", at: now)
            return .overBudget
        }

        var rewrites: [String: Data] = [:]
        var entries: [String: CompanionManifestProviderEntry] = [:]
        var nextPublished: [String: PublishedProvider] = [:]
        for payload in fit.payloads {
            let id = payload.providerID
            guard let key = CompanionSyncKeys.provider(id), let bytes = fit.providerValues[id] else { continue }
            let fingerprint = CompanionPublishImage.fingerprint(payload)
            let observations = CompanionPublishImage.observations(payload)
            let held = store.data(forKey: key).map(CompanionSyncCodec.digest)
            let prior = published[id]
            let advanced = prior.map { prior in
                observations.contains { name, value in
                    prior.observations[name].map {
                        // KTD14.5: a completed check must deliver its actual readings before
                        // the phone reports success, even when usage percentages stayed put.
                        includeFreshObservations ? value > $0 : Double(value - $0) >= interval
                    } ?? false
                }
            } ?? true
            let rewrite = writeAll || prior == nil || prior?.fingerprint != fingerprint
                || held != prior?.digest || advanced
            if rewrite {
                guard let entry = try? CompanionPublishImage.entry(
                    for: bytes, generation: generation, interval: intervals[id] ?? interval)
                else { continue }
                rewrites[id] = bytes
                entries[id] = entry
                nextPublished[id] = PublishedProvider(
                    fingerprint: fingerprint, digest: entry.digest, entry: entry,
                    observations: observations, bytes: bytes.count)
            } else if let prior {
                // Unchanged: the manifest keeps the generation that key was written in.
                entries[id] = try? CompanionManifestProviderEntry(
                    payloadGeneration: prior.entry.payloadGeneration, digest: prior.entry.digest,
                    effectiveIntervalSeconds: intervals[id] ?? prior.entry.effectiveIntervalSeconds)
                nextPublished[id] = PublishedProvider(
                    fingerprint: prior.fingerprint, digest: prior.digest,
                    entry: entries[id] ?? prior.entry, observations: prior.observations,
                    bytes: prior.bytes)
            }
        }

        let keep = Set(nextPublished.keys.compactMap(CompanionSyncKeys.provider))
        let stale = store.keys(withPrefix: CompanionSyncKeys.providerPrefix).filter { !keep.contains($0) }

        guard let manifest = try? CompanionPublishImage.manifest(
            capture: capture, sourceID: sourceID, macAppVersion: configuration.macAppVersion,
            entries: entries, ladderLevel: fit.ladderLevel),
            let manifestBytes = try? CompanionSyncCodec.encode(CompanionManifest.active(manifest)),
            let v3Bytes = try? CompanionPublishImage.v3Bytes(capture: capture, sourceID: sourceID)
        else {
            recordFailure("encodeFailed", at: now)
            return .writeFailed
        }
        let manifestFingerprint = Self.manifestFingerprint(manifest)
        let heldManifest = store.data(forKey: CompanionSyncKeys.manifest).map(CompanionSyncCodec.digest)
        let heldV3 = store.data(forKey: iCloudSnapshotSync.snapshotKey).map(CompanionSyncCodec.digest)
        let needsWrite = forced || heartbeat || writeAll || !rewrites.isEmpty || !stale.isEmpty
            || manifestFingerprint != publishedManifestFingerprint
            || heldManifest != publishedManifestDigest || heldV3 != publishedV3Digest
        guard needsWrite else { return .unchanged }

        // Measure the image exactly as it will stand after this write.
        var image = protocolValues
        for (id, record) in nextPublished {
            guard let key = CompanionSyncKeys.provider(id) else { continue }
            image[key] = rewrites[id] ?? store.data(forKey: key) ?? Data(count: record.bytes)
        }
        image[CompanionSyncKeys.manifest] = manifestBytes
        let measurement = CompanionBudgetMeasurement(image)
        guard measurement.fits else {
            lastFit = false
            recordFailure("overBudget", at: now)
            return .overBudget
        }

        // Provider keys first, so a phone that sees the new manifest finds them.
        var writes = 0
        for (id, bytes) in rewrites.sorted(by: { $0.key < $1.key }) {
            guard let key = CompanionSyncKeys.provider(id), store.set(bytes, forKey: key) else {
                recordFailure("writeFailed", at: now)
                return .writeFailed
            }
            writes += 1
        }
        guard store.set(manifestBytes, forKey: CompanionSyncKeys.manifest),
            store.set(v3Bytes, forKey: iCloudSnapshotSync.snapshotKey)
        else {
            recordFailure("writeFailed", at: now)
            return .writeFailed
        }
        writes += 2
        // KTD22: a provider dropped from the manifest loses its key in the same publish.
        for key in stale { store.removeValue(forKey: key) }

        published = nextPublished
        publishedManifestDigest = CompanionSyncCodec.digest(manifestBytes)
        publishedManifestFingerprint = manifestFingerprint
        publishedV3Digest = CompanionSyncCodec.digest(v3Bytes)
        if let previous = publishedStructure, previous.accounts != capture.structure.accounts {
            // The ladder is recomputed from content; a quota step does not outlive the
            // account set it was measured against.
            quotaFloor = 0
        }
        publishedStructure = capture.structure
        publishedInterval = interval
        lastWriteAt = now
        lastPublishedGeneration = generation
        writeAll = false
        lastFit = true

        var bytes = measurement.valueBytes
        bytes[iCloudSnapshotSync.snapshotKey] = v3Bytes.count
        diagnostics.lastPublishAt = now
        diagnostics.lastGeneration = generation
        diagnostics.ladderLevel = fit.ladderLevel
        diagnostics.keyBytes = bytes
        diagnostics.lastFailure = nil
        saveDiagnostics()
        return .published(generation: generation, writes: writes)
    }

    /// KTD22 sync-off order: the disabled v3 envelope, then the disabled manifest
    /// tombstone, then every provider, receipt and request key and any other key under the
    /// v4 namespace (contract Decision 3, AE4), then participants. The scope marker lives
    /// outside the namespace and is never swept.
    private func sweep(_ capture: CompanionPublishCapture) {
        let sourceID = configuration.sourceID
        let stamp = capture.generatedAt.date
        let disabledV3 = SyncedWidgetSnapshotEnvelope(
            publishedAt: stamp, sourceID: CompanionPublishImage.v3SourceLabel,
            sourcePlatform: .macOS, snapshot: .disabled(generatedAt: stamp),
            companionSourceID: sourceID, companionGeneration: capture.generation)
        if let bytes = try? SyncedWidgetSnapshotCodec.encode(disabledV3) {
            store.set(bytes, forKey: iCloudSnapshotSync.snapshotKey)
        }
        if let tombstone = try? CompanionManifest.disabledTombstone(sourceID: sourceID),
            let bytes = try? CompanionSyncCodec.encode(tombstone)
        {
            store.set(bytes, forKey: CompanionSyncKeys.manifest)
        }
        for key in store.keys(withPrefix: CompanionSyncKeys.providerPrefix) { store.removeValue(forKey: key) }
        store.removeValue(forKey: CompanionSyncKeys.receipt)
        for key in store.keys(withPrefix: CompanionSyncKeys.requestPrefix) { store.removeValue(forKey: key) }
        for key in store.keys(withPrefix: CompanionSyncKeys.namespace) where key != CompanionSyncKeys.manifest {
            store.removeValue(forKey: key)
        }
        notifyParticipants { await $0.companionSyncDidPurge() }

        sweptWhileDisabled = true
        published = [:]
        publishedManifestDigest = nil
        publishedManifestFingerprint = nil
        publishedV3Digest = nil
        publishedStructure = nil
        writeAll = true
        let now = configuration.now()
        diagnostics.lastSweepAt = now
        diagnostics.lastGeneration = capture.generation
        diagnostics.keyBytes = [:]
        saveDiagnostics()
    }

    /// Waits for every participant call issued so far (tests, and quit).
    public func participantsIdle() async {
        await participantChain?.value
    }

    private func notifyParticipants(_ call: @escaping @Sendable (any CompanionSyncLifecycle) async -> Void) {
        guard !participants.isEmpty else { return }
        let previous = participantChain
        let participants = participants
        participantChain = Task {
            await previous?.value
            for participant in participants { await call(participant) }
        }
    }

    /// A failed flush counts as an attempt, so the next heartbeat backs off a whole interval.
    private func recordFailure(_ reason: String, at now: Date) {
        lastAttemptAt = now
        diagnostics.lastFailure = reason
        saveDiagnostics()
    }

    private func saveDiagnostics() {
        diagnosticsStore?.save(diagnostics)
        onDiagnostics?(diagnostics)
    }

    private static func manifestFingerprint(_ manifest: CompanionActiveManifest) -> String {
        let stripped = try? CompanionActiveManifest(
            sourceID: manifest.sourceID, generation: 0, generatedAt: CompanionWireDate(epochSeconds: 0)!,
            macAppVersion: manifest.macAppVersion, providerOrder: manifest.providerOrder,
            providers: manifest.providers, spendOrder: manifest.spendOrder,
            chosenIntervalSeconds: manifest.chosenIntervalSeconds, display: manifest.display,
            widgetProviderSelection: manifest.widgetProviderSelection,
            widgetSparkEnabled: manifest.widgetSparkEnabled,
            reminderSummary: manifest.reminderSummary, answeredRequests: manifest.answeredRequests,
            dropLadderLevel: manifest.dropLadderLevel)
        let bytes = stripped.flatMap { try? CompanionSyncCodec.encode(CompanionManifest.active($0)) } ?? Data()
        return CompanionSyncCodec.digest(bytes)
    }
}

// MARK: - Main-actor facade

/// The store's phone-sync seam (KTD8). The store hands over a fresh capture on every
/// change that reaches the phone; the conformer stamps and publishes it.
public protocol CompanionPhoneSyncing: AnyObject {
    @MainActor func submit(_ capture: CompanionPublishCapture)
    /// Heartbeats and forced republishes call back for a fresh capture.
    @MainActor func bind(captureProvider: @escaping @MainActor @Sendable () -> CompanionPublishCapture?)
    /// KTD8: flush pending writes now (system sleep, app quit).
    @MainActor func flushNow() async
    /// KTD14.5: check-now finish (and cooldown). Stamps the next generation, lets `answering`
    /// build the manifest's answered list with it, publishes immediately and returns the
    /// generation the phone must assemble; nil when nothing was published.
    @MainActor func submitForced(
        _ capture: CompanionPublishCapture, answering: (Int64) -> [CompanionAnsweredRequest]
    ) async -> Int64?
}

extension CompanionPhoneSyncing {
    @MainActor public func bind(captureProvider: @escaping @MainActor @Sendable () -> CompanionPublishCapture?) {}
    @MainActor public func flushNow() async {}
    @MainActor public func submitForced(
        _ capture: CompanionPublishCapture, answering: (Int64) -> [CompanionAnsweredRequest]
    ) async -> Int64? { nil }
}

/// What the Settings footnote shows (KTD22): the last publish, the ladder and the last
/// quota event. Times and counts only.
public struct CompanionSyncStatus: Equatable, Sendable {
    public let lastPublishAt: Date?
    public let ladderLevel: Int
    public let lastQuotaEventAt: Date?
    public let lastFailure: String?

    public init(_ diagnostics: CompanionPublishDiagnostics) {
        lastPublishAt = diagnostics.lastPublishAt
        ladderLevel = diagnostics.ladderLevel
        lastQuotaEventAt = diagnostics.lastQuotaEventAt
        lastFailure = diagnostics.lastFailure
    }
}

/// Stamps each capture with the next generation on the main actor, so generation order
/// is capture order (KTD8), and forwards it to the serial publisher.
@MainActor
@Observable
public final class CompanionPhoneSync: CompanionPhoneSyncing {
    public private(set) var status: CompanionSyncStatus
    public let publisher: CompanionPublisher
    private let lineage: CompanionLineage
    @ObservationIgnored private var lastForwardedStatus: CompanionPublishStatus?
    @ObservationIgnored private var captureProvider: (@MainActor @Sendable () -> CompanionPublishCapture?)?

    public init(
        store: any iCloudKeyValueSyncing,
        lineage: CompanionLineage,
        diagnosticsStore: CompanionPublishDiagnosticsStore?,
        macAppVersion: String?,
        participants: [any CompanionSyncLifecycle] = [],
        configure: (inout CompanionPublisher.Configuration) -> Void = { _ in }
    ) {
        var configuration = CompanionPublisher.Configuration(
            sourceID: lineage.sourceID, macAppVersion: macAppVersion)
        configure(&configuration)
        self.lineage = lineage
        self.status = CompanionSyncStatus(diagnosticsStore?.load() ?? CompanionPublishDiagnostics())
        let box = WeakBox()
        let update: @Sendable (CompanionPublishDiagnostics) -> Void = { diagnostics in
            Task { @MainActor in box.value?.status = CompanionSyncStatus(diagnostics) }
        }
        self.publisher = CompanionPublisher(
            store: store, configuration: configuration, diagnosticsStore: diagnosticsStore,
            participants: participants, onDiagnostics: update)
        box.value = self
    }

    public func submit(_ capture: CompanionPublishCapture) {
        // While sync stays off, one sweep per launch or transition is enough.
        if capture.status == .disabled, lastForwardedStatus == .disabled { return }
        lastForwardedStatus = capture.status
        let stamped = stamp(capture)
        Task { [publisher] in await publisher.receive(stamped) }
    }

    /// U6 (KTD14.5): check-now finish forces an immediate flush of every changed provider
    /// key plus the manifest, which echoes the answers stamped with this generation.
    public func submitForced(
        _ capture: CompanionPublishCapture, answering: (Int64) -> [CompanionAnsweredRequest]
    ) async -> Int64? {
        lastForwardedStatus = capture.status
        var stamped = stamp(capture)
        stamped.answeredRequests = CompanionAnsweredRequest.terminalHistory(answering(stamped.generation))
        return await publisher.publishForced(stamped)
    }

    public func bind(captureProvider: @escaping @MainActor @Sendable () -> CompanionPublishCapture?) {
        self.captureProvider = captureProvider
        let stamping: @MainActor @Sendable () -> CompanionPublishCapture? = { [weak self] in
            guard let self, let capture = self.captureProvider?() else { return nil }
            self.lastForwardedStatus = capture.status
            return self.stamp(capture)
        }
        Task { [publisher] in await publisher.setCaptureProvider(stamping) }
    }

    public func flushNow() async {
        await publisher.flushPending()
    }

    public func accountDidChange() {
        Task { [publisher] in await publisher.accountDidChange() }
    }

    public func recordQuotaEvent(_ event: iCloudKeyValueQuotaEvent) {
        Task { [publisher] in await publisher.recordQuotaEvent(event) }
    }

    private func stamp(_ capture: CompanionPublishCapture) -> CompanionPublishCapture {
        var stamped = capture
        stamped.generation = lineage.nextGeneration()
        return stamped
    }

    private final class WeakBox: @unchecked Sendable {
        weak var value: CompanionPhoneSync?
    }
}
