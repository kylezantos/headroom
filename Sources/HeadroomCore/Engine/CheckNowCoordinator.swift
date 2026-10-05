import Foundation

// Mac-only by folder (KTD4). iPhone parity U6 (KTD14, R18, R19): phone check-now requests
// make the running Mac refresh once and report progress back. The phone side is
// `Sync/CheckNowProtocol.swift`.

// MARK: - Host

/// One user-work progress reading, already in wire terms for the receipt (KTD14.6).
public struct CheckNowRunProgress: Equatable, Sendable {
    public let total: Int
    public let completed: Int
    public let lastLanded: CompanionLastLanded?

    public init(total: Int, completed: Int, lastLanded: CompanionLastLanded?) {
        self.total = total
        self.completed = completed
        self.lastLanded = lastLanded
    }
}

/// What the coordinator needs from the store. `UsageStore` conforms below; tests use a
/// controllable double.
@MainActor
public protocol CheckNowHost: AnyObject {
    /// "Sync usage to iPhone": requests are ignored while it is off (R19, KTD14.2).
    var checkNowSyncEnabled: Bool { get }
    /// Non-nil while a full refresh of any origin runs (KTD14.4).
    var checkNowFullRefreshStartedAt: Date? { get }
    /// The cooldown runs from here (KTD14.4).
    var checkNowLastFullRefreshCompletedAt: Date? { get }
    /// Runs the one full refresh, or awaits the one in flight (KTD14.4).
    func checkNowRunFullRefresh() async
    /// The scheduler's current user-work progress, nil when no user work is pending.
    var checkNowProgress: CheckNowRunProgress? { get }
    /// Called on every user-progress change (`schedulerUserProgressDidChange`).
    func checkNowObserveProgress(_ observer: (@MainActor () -> Void)?)
    /// KTD14.5: a forced flush of every changed provider key plus the manifest, whose
    /// answered list `answering` builds from the stamped generation. Returns the generation
    /// the phone must assemble; nil when nothing was published.
    func checkNowPublish(answering: (Int64) -> [CompanionAnsweredRequest]) async -> Int64?
    /// The answered history every later manifest echoes (Decision 2).
    func checkNowSetAnsweredHistory(_ answers: [CompanionAnsweredRequest])
}

// MARK: - Ledger (Mac preferences)

/// KTD14.3: the last handled request ID per device UUID and the last eight answers, kept in
/// Mac preferences so a relaunch never re-runs a handled request and the first manifest
/// after launch still echoes recent answers.
public final class CheckNowLedger: @unchecked Sendable { // UserDefaults is thread-safe
    static let lastHandledKey = "companionSync.checkNow.lastHandled.v1"
    static let answeredKey = "companionSync.checkNow.answered.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func lastHandled(device: String) -> String? {
        (defaults.dictionary(forKey: Self.lastHandledKey) as? [String: String])?[device]
    }

    public func recordHandled(device: String, requestID: String) {
        var handled = defaults.dictionary(forKey: Self.lastHandledKey) as? [String: String] ?? [:]
        handled[device] = requestID
        defaults.set(handled, forKey: Self.lastHandledKey)
    }

    public var answered: [CompanionAnsweredRequest] {
        get {
            defaults.data(forKey: Self.answeredKey)
                .flatMap { try? JSONDecoder().decode([CompanionAnsweredRequest].self, from: $0) } ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(CompanionAnsweredRequest.terminalHistory(newValue)) else { return }
            defaults.set(data, forKey: Self.answeredKey)
        }
    }
}

// MARK: - Coordinator

/// Intake, launch scan, dedupe, cooldown and receipts for phone check-now requests.
///
/// Requests arrive as typed KVS external changes filtered to `headroom.sync.v4.request.*`,
/// plus one launch scan (KVS sends no notification for keys already stored locally).
/// Requests seen before `start()` queue and join the launch refresh. Each accepted request
/// joins the one full refresh (KTD14.4); its finish is a forced flush followed by the
/// finished receipt (KTD14.5). Receipts are the only writes outside the publisher's
/// flushes, at most every 15 s while a check runs (KTD8).
@MainActor
public final class CheckNowCoordinator {
    public struct Configuration: Sendable {
        public var sourceID: String
        public var now: @Sendable () -> Date
        public var sleep: @Sendable (TimeInterval) async -> Void

        public init(
            sourceID: String, now: @escaping @Sendable () -> Date = Date.init,
            sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
                try? await Task.sleep(for: .seconds(max(0, seconds)))
            }
        ) {
            self.sourceID = sourceID
            self.now = now
            self.sleep = sleep
        }
    }

    private struct Intake {
        let device: String
        let request: CompanionRequest
    }

    private struct Run {
        /// Decision 2: every request joined to this refresh, by request ID → device UUID.
        var members: [String: String]
        let startedAt: Date
        /// The last non-nil progress; the scheduler clears its own once user work drains.
        var progress: CheckNowRunProgress?
    }

    private let store: any iCloudKeyValueSyncing
    private weak var host: (any CheckNowHost)?
    private let ledger: CheckNowLedger
    private let configuration: Configuration

    private var started = false
    private var queued: [String] = []
    private var run: Run?
    /// A finish or cooldown answer is publishing; intake waits for it.
    private var answering = false
    private var deferred: [Intake] = []
    private var history: [CompanionAnsweredRequest]
    private var lastReceiptWriteAt: Date?
    private var spacedReceipt: Task<Void, Never>?
    private var work: [UUID: Task<Void, Never>] = [:]

    /// Static categories only (`overBudget`), for `--dump-phone-sync`-style diagnostics.
    public private(set) var lastFailure: String?

    public init(
        store: any iCloudKeyValueSyncing, host: any CheckNowHost, ledger: CheckNowLedger,
        configuration: Configuration
    ) {
        self.store = store
        self.host = host
        self.ledger = ledger
        self.configuration = configuration
        self.history = ledger.answered
        host.checkNowSetAnsweredHistory(history)
    }

    /// The store has started its launch refresh. Scans existing request keys once, prunes
    /// the month-old ones and admits what was queued before now (KTD14.2, KTD14.8).
    public func start() {
        guard !started else { return }
        started = true
        guard host?.checkNowSyncEnabled == true else {
            queued = []
            return
        }
        let now = configuration.now()
        let existing = store.keys(withPrefix: CompanionSyncKeys.requestPrefix)
        for key in existing {
            guard case .value(let request) = CompanionSyncCodec.decodeRequest(store.data(forKey: key)) else { continue }
            if now.timeIntervalSince(request.requestedAt.date) > CheckNowTiming.requestRetention {
                store.removeValue(forKey: key)
            }
        }
        let keys = Array(Set(existing + queued)).sorted()
        queued = []
        intake(keys: keys, fromLaunch: true)
    }

    /// A typed `didChangeExternallyNotification`. Only request keys matter here.
    public func receive(_ change: iCloudKeyValueChange) {
        let keys = change.changedKeys.filter { $0.hasPrefix(CompanionSyncKeys.requestPrefix) }
        guard !keys.isEmpty else { return }
        guard started else {
            queued.append(contentsOf: keys)
            return
        }
        // The first sync after launch (or a new iCloud account) delivers what sat in iCloud
        // while this Mac was away: the same age backstop as the launch scan (AE2).
        let fromLaunch = change.reason == .initialSyncChange || change.reason == .accountChange
        intake(keys: keys, fromLaunch: fromLaunch)
    }

    /// Whether a run or an answer is still in flight (tests settle on it without waiting
    /// on a refresh that may never end).
    var hasPendingWork: Bool { !work.isEmpty || spacedReceipt != nil }

    // MARK: Intake (KTD14.2, KTD14.3)

    private func intake(keys: [String], fromLaunch: Bool) {
        guard let host, host.checkNowSyncEnabled else { return }
        let now = configuration.now()
        var admitted: [Intake] = []
        for key in keys {
            guard let device = CompanionSyncKeys.deviceUUID(fromRequestKey: key),
                case .value(let request) = CompanionSyncCodec.decodeRequest(store.data(forKey: key)),
                request.sourceID == configuration.sourceID
            else { continue }
            let id = request.requestID
            guard ledger.lastHandled(device: device) != id,
                !history.contains(where: { $0.requestID == id }),
                run?.members[id] == nil,
                !deferred.contains(where: { $0.request.requestID == id }),
                !admitted.contains(where: { $0.request.requestID == id })
            else { continue }
            // KTD14.3: the age limit is a backstop for what a launch finds, never a clock
            // comparison for a live request.
            if fromLaunch,
                now.timeIntervalSince(request.requestedAt.date)
                    > CheckNowTiming.requestAgeLimit + CheckNowTiming.clockSkewAllowance
            {
                continue
            }
            admitted.append(Intake(device: device, request: request))
            CheckNowLog.logger.info(
                "mac request \(CheckNowLog.tag(id), privacy: .public) admitted (\(fromLaunch ? "launch" : "live", privacy: .public))")
        }
        admit(admitted)
    }

    private func admit(_ intakes: [Intake]) {
        guard !intakes.isEmpty, let host else { return }
        if answering {
            deferred.append(contentsOf: intakes)
            return
        }
        if var current = run {
            for intake in intakes { current.members[intake.request.requestID] = intake.device }
            run = current
            writeActiveReceipt(spaced: true)
            return
        }
        let now = configuration.now()
        if host.checkNowFullRefreshStartedAt == nil, let last = host.checkNowLastFullRefreshCompletedAt,
            now.timeIntervalSince(last) < CheckNowTiming.cooldown
        {
            answerCooldown(intakes, checkedAt: last)
            return
        }
        startRun(intakes)
    }

    // MARK: Runs (KTD14.4–6)

    private func startRun(_ intakes: [Intake]) {
        guard let host else { return }
        let now = configuration.now()
        run = Run(
            members: Dictionary(intakes.map { ($0.request.requestID, $0.device) }, uniquingKeysWith: { first, _ in first }),
            // A joined Mac-started refresh keeps its own start time.
            startedAt: host.checkNowFullRefreshStartedAt ?? now,
            progress: host.checkNowProgress)
        host.checkNowObserveProgress { [weak self] in self?.progressDidChange() }
        writeActiveReceipt(spaced: true)
        track { [weak self] in
            await host.checkNowRunFullRefresh()
            await self?.finishRun()
        }
    }

    private func progressDidChange() {
        guard var current = run, let progress = host?.checkNowProgress else { return }
        if let landed = progress.lastLanded, progress.completed > (current.progress?.completed ?? 0) {
            // Spike: consecutive landings of one provider give that lane's per-probe time.
            CheckNowLog.logger.info(
                "mac landed \(landed.providerID, privacy: .public) \(progress.completed)/\(progress.total)")
        }
        current.progress = progress
        run = current
        writeActiveReceipt(spaced: true)
    }

    /// KTD14.5: finish is the forced flush after the refresh's last merge, and only then the
    /// finished receipt naming that flush's generation.
    private func finishRun() async {
        guard let host, let finishing = run else { return }
        answering = true
        cancelSpacedReceipt()
        host.checkNowObserveProgress(nil)
        let members = finishing.members
        if host.checkNowSyncEnabled {
            let generation = await publish(members.keys.sorted(), outcome: .finished)
            let progress = finishing.progress
            if let generation {
                write(receipt(
                    state: .finished, requestIDs: Array(members.keys), startedAt: finishing.startedAt,
                    finishedAt: configuration.now(), progress: progress, finishedGeneration: generation))
            } else {
                write(receipt(
                    state: progress == nil ? .accepted : .running, requestIDs: Array(members.keys),
                    startedAt: finishing.startedAt, progress: progress))
            }
            for (id, device) in members { ledger.recordHandled(device: device, requestID: id) }
        }
        run = nil
        answering = false
        drainDeferred()
    }

    /// KTD14.4: inside 60 s of any completed full refresh the Mac answers "checked a moment
    /// ago" instead of refreshing. It republishes first — flushing anything dirty, and
    /// letting the manifest echo the answer — and names that generation, so the phone
    /// completes exactly as it does a finished check.
    private func answerCooldown(_ intakes: [Intake], checkedAt: Date) {
        answering = true
        let ids = intakes.map(\.request.requestID).sorted()
        track { [weak self] in
            guard let self else { return }
            if let generation = await self.publish(ids, outcome: .cooldown) {
                self.write(self.receipt(
                    state: .cooldown, requestIDs: ids, startedAt: nil, checkedAt: checkedAt,
                    finishedGeneration: generation))
            } else {
                // The failed answers ride in the history; the phone ends on "hasn't finished".
                self.write(self.receipt(state: .accepted, requestIDs: ids, startedAt: nil))
            }
            for intake in intakes {
                self.ledger.recordHandled(device: intake.device, requestID: intake.request.requestID)
            }
            self.answering = false
            self.drainDeferred()
        }
    }

    /// Records the answers with the stamped generation before the flush is written, so any
    /// later capture echoes them too; a failed flush turns them into `failed`.
    private func publish(_ ids: [String], outcome: CompanionAnsweredOutcome) async -> Int64? {
        guard let host else { return nil }
        let generation = await host.checkNowPublish { generation in
            let answers = ids.compactMap {
                try? CompanionAnsweredRequest(requestID: $0, outcome: outcome, finishedGeneration: generation)
            }
            self.remember(answers)
            return self.history
        }
        if generation == nil {
            remember(ids.compactMap { try? CompanionAnsweredRequest(requestID: $0, outcome: .failed) })
        }
        return generation
    }

    private func remember(_ answers: [CompanionAnsweredRequest]) {
        history = CompanionAnsweredRequest.terminalHistory(history + answers)
        ledger.answered = history
        host?.checkNowSetAnsweredHistory(history)
    }

    private func drainDeferred() {
        let waiting = deferred
        deferred = []
        // Re-checked against the history this answer just extended.
        admit(waiting.filter { intake in !history.contains { $0.requestID == intake.request.requestID } })
    }

    // MARK: Receipts (KTD14.6, KTD8 spacing)

    private func writeActiveReceipt(spaced: Bool) {
        guard run != nil else { return }
        let now = configuration.now()
        if spaced, let last = lastReceiptWriteAt, now.timeIntervalSince(last) < CheckNowTiming.receiptSpacing {
            guard spacedReceipt == nil else { return }
            let delay = CheckNowTiming.receiptSpacing - now.timeIntervalSince(last)
            let sleep = configuration.sleep
            spacedReceipt = Task { [weak self] in
                await sleep(delay)
                guard !Task.isCancelled, let self else { return }
                self.spacedReceipt = nil
                guard !self.answering else { return }
                self.writeActiveReceipt(spaced: false)
            }
            return
        }
        guard let current = run else { return }
        write(receipt(
            state: current.progress == nil ? .accepted : .running, requestIDs: Array(current.members.keys),
            startedAt: current.startedAt, progress: current.progress))
    }

    private func cancelSpacedReceipt() {
        spacedReceipt?.cancel()
        spacedReceipt = nil
    }

    private func receipt(
        state: CompanionReceiptState, requestIDs: [String], startedAt: Date?, finishedAt: Date? = nil,
        checkedAt: Date? = nil, progress: CheckNowRunProgress? = nil, finishedGeneration: Int64? = nil
    ) -> CompanionReceipt? {
        let total = progress.map { max($0.total, $0.completed) }
        return try? CompanionReceipt(
            sourceID: configuration.sourceID, state: state, requestIDs: requestIDs,
            answeredRequests: history, startedAt: startedAt.flatMap(CompanionWireDate.init(date:)),
            finishedAt: finishedAt.flatMap(CompanionWireDate.init(date:)),
            checkedAt: checkedAt.flatMap(CompanionWireDate.init(date:)), total: total,
            completed: progress?.completed, lastLanded: progress?.lastLanded,
            finishedGeneration: finishedGeneration)
    }

    /// Contract Decision 3: receipt writes are measured against the whole v4 namespace too;
    /// an over-budget receipt is not written rather than displacing account content.
    private func write(_ receipt: CompanionReceipt?) {
        guard let receipt, let bytes = try? CompanionSyncCodec.encode(receipt) else { return }
        var image: [String: Data] = [:]
        for key in store.keys(withPrefix: CompanionSyncKeys.namespace) {
            if let data = store.data(forKey: key) { image[key] = data }
        }
        image[CompanionSyncKeys.receipt] = bytes
        guard CompanionBudgetMeasurement(image).fits else {
            lastFailure = "overBudget"
            return
        }
        store.set(bytes, forKey: CompanionSyncKeys.receipt)
        store.synchronize()
        CheckNowLog.logger.info(
            "mac receipt \(receipt.state.rawValue, privacy: .public) for \(receipt.requestIDs.map(CheckNowLog.tag).joined(separator: ","), privacy: .public)")
        lastReceiptWriteAt = configuration.now()
        lastFailure = nil
    }

    private func track(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        work[id] = Task { [weak self] in
            await operation()
            self?.work[id] = nil
        }
    }
}

// MARK: - UsageStore as the host

extension UsageStore: CheckNowHost {
    public var checkNowSyncEnabled: Bool { syncToIPhoneEnabled }
    public var checkNowFullRefreshStartedAt: Date? { fullRefreshStartedAt }
    public var checkNowLastFullRefreshCompletedAt: Date? { lastFullRefreshCompletedAt }

    public func checkNowRunFullRefresh() async {
        await refreshAll()
    }

    public var checkNowProgress: CheckNowRunProgress? {
        guard let progress = refreshProgress else { return nil }
        let landed = progress.lastLanded.flatMap { key in
            try? CompanionLastLanded(
                providerID: key.providerID.raw, accountID: key.accountID.raw,
                live: snapshot(for: key).freshness == .live)
        }
        return CheckNowRunProgress(total: progress.total, completed: progress.completed, lastLanded: landed)
    }

    public func checkNowObserveProgress(_ observer: (@MainActor () -> Void)?) {
        checkNowProgressObserver = observer
    }

    public func checkNowPublish(answering: (Int64) -> [CompanionAnsweredRequest]) async -> Int64? {
        guard let phoneSyncExporter else { return nil }
        return await phoneSyncExporter.submitForced(companionCapture(), answering: answering)
    }

    public func checkNowSetAnsweredHistory(_ answers: [CompanionAnsweredRequest]) {
        checkNowAnsweredRequests = answers
    }
}
