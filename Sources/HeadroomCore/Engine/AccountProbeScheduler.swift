import Foundation

/// Whether the running probe answers a user action. `UsageProvider.fetchResult()` takes no
/// arguments, so a provider that rate-limits an expensive read learns here when it must read
/// anyway: a timer can wait, but someone who pressed Check Now or finished a sign-in cannot.
public enum UserRequestedProbeContext {
    @TaskLocal public static var isUserRequested = false
    /// Every reason the running probe was requested since the last probe of its account
    /// started. Empty for a timer probe. A provider that must tell a full refresh (launch,
    /// Refresh, a phone Check Now) apart from an account's own Try Again or a finished sign-in
    /// reads this; most only need `isUserRequested`.
    @TaskLocal public static var origins: Set<UserRefreshOrigin> = []
}

/// What the scheduler needs from the store. Kept as a protocol so the scheduler holds no
/// snapshot, provider, or export logic of its own (2026-09-19 polling plan, KTD1).
@MainActor
protocol AccountProbeSchedulerHost: AnyObject {
    var schedulerNow: Date { get }
    var schedulerChosenInterval: TimeInterval { get }
    func schedulerStartsNewUserRun(origin: UserRefreshOrigin) -> Bool
    func schedulerUserRunDidChange(_ run: UserRefreshRun)
    func schedulerProvider(for key: AccountKey) -> (any UsageProvider)?
    /// Attached, not being removed, and its subscription surface is on.
    func schedulerIsEligible(_ key: AccountKey) -> Bool
    func schedulerIsPrimary(_ key: AccountKey) -> Bool
    func schedulerFreshness(for key: AccountKey) -> Freshness?
    /// The account's earliest tracked reset deadline later than `after`.
    func schedulerResetDeadline(for key: AccountKey, after: Date) -> Date?
    func schedulerAttachmentGeneration(for key: AccountKey) -> UInt64
    func schedulerBeginCapabilityRefresh(for providers: [any UsageProvider]) -> [ProviderID: UInt64]
    func schedulerApplyCapability(_ state: ProviderCapabilityState, for providerID: ProviderID, generation: UInt64?)
    /// Merges the result with continuity and exports compact surfaces when the key is a
    /// primary (KTD9). Returns whether the result was accepted.
    func schedulerMerge(key: AccountKey, result: UsageProviderFetchResult, attachmentGeneration: UInt64) -> Bool
    /// A lane pass ended, or a concurrent lane's last in-flight fetch finished (KTD6, KTD9).
    func schedulerLaneDidGoIdle(_ lane: ProviderPollingLane)
    /// User-initiated work started or drained (KTD2).
    func schedulerUserWorkDidChange(hasPending: Bool)
    /// An account's probe started or ended, timer and user work alike. The menu-bar pill of
    /// a provider's main account sloshes in between (Oct 2026, round-3 S2).
    func schedulerProbeDidStart(_ key: AccountKey)
    func schedulerProbeDidEnd(_ key: AccountKey)
    /// User-requested work moved on: `completed` of the `total` accounts requested since it
    /// began, and the account that just finished, if any (Oct 2026, round-4 W4 receipt).
    func schedulerUserProgressDidChange(total: Int, completed: Int, landed: AccountKey?)
}

/// Per-lane due-queue engine (2026-09-19 polling plan, KTD1, KTD2, KTD6–KTD9, KTD11).
///
/// Each CLI lane drains one probe at a time, most overdue first, behind a measured
/// duty-cycle gate; the HTTP lane fetches its due accounts concurrently. The scheduler owns
/// the attempt clock (KTD3), the per-lane probe log (KTD4), and the priority requests that
/// let user actions jump the queue (KTD7). Everything that touches snapshots goes back
/// through the host.
@MainActor
final class AccountProbeScheduler {
    private struct LaneState {
        var draining = false
        /// KTD7: a pass a user request started serves user work only; timer-due siblings
        /// wait for the timer, so Check Now, Make Main and a setup check never fan out.
        var userOnly = false
        var inFlight: Set<AccountKey> = []
        /// Ordered, unique: a repeated request for an account already waiting is coalesced (KTD7).
        var priority: [AccountKey] = []
        var log: [LaneSchedule.ProbeSpan] = []
        var passCapability: [ProviderID: UInt64] = [:]
        var newestCapability: [ProviderID: ProviderCapabilityState] = [:]
    }

    /// The scheduler is created inside the store's initializer, before `self` can be
    /// captured, so the host attaches right after.
    weak var host: (any AccountProbeSchedulerHost)?

    private var records: [AccountKey: LaneSchedule.AccountRecord] = [:]
    private var laneOf: [AccountKey: ProviderPollingLane] = [:]
    /// Registration order (registry display order, primary first): the tie-break among
    /// equally overdue accounts, so a launch pass fills rows in the order the user sees.
    private var order: [AccountKey] = []
    /// The attachment generation each in-flight probe started under. A request that
    /// arrives after a reset or handoff boundary cannot be answered by that probe.
    private var inFlightAttachment: [AccountKey: UInt64] = [:]
    /// In-flight probes that started under `UserRequestedProbeContext`.
    private var inFlightUserRequested: Set<AccountKey> = []
    private var lanes: [ProviderPollingLane: LaneState] = [:]
    /// Accounts a user action marked due and that have not merged yet (KTD2).
    private var userPending: Set<AccountKey> = []
    private var userRun: UserRefreshRun?
    /// KTD2/R5: a ladder check after a user landing is current setup work, not a new
    /// request to fade/print the retained user entry during its spend tail.
    private var setupPendingPreservingLanding: Set<AccountKey> = []
    /// Every origin that asked for an account since its last probe started, so a setup check
    /// coalesced with a full refresh is still seen as a setup check by the probe that serves it.
    private var pendingOrigins: [AccountKey: Set<UserRefreshOrigin>] = [:]
    /// W4: how many accounts the current run of user work asked for and has finished. Both
    /// restart when user work begins from nothing pending.
    private var userTotal = 0
    private var userCompleted = 0
    /// A user action may perform provider-wide setup before queueing its account probe.
    /// Preserve that task-local discovery generation across the scheduler's own task hop so
    /// the probe can reuse the setup result instead of starting a second CLI search.
    private var priorityLocatorGeneration: [AccountKey: UUID] = [:]
    /// KTD2 (default-login plan): consecutive readings refused because the account's
    /// identity could not be read on both sides of the usage read. At the bound the next
    /// one is merged as an ordinary transient failure, so a permanently unreadable
    /// identity file ends in a stale row with normal backoff, not an endless retry.
    private var identityRefusals: [AccountKey: Int] = [:]
    static let identityRefusalBound = 2
    /// Accounts whose refused reading was already re-queued inside the current user work.
    private var identityRequeued: Set<AccountKey> = []
    /// Refusals since launch, per account. Diagnostics only: how often the after-read
    /// meets a file the CLI is rewriting is unmeasured.
    private(set) var identityRefusalTotals: [AccountKey: Int] = [:]
    private var userWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionWaiters: [AccountKey: [CheckedContinuation<Void, Never>]] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: Membership

    func register(_ provider: any UsageProvider) {
        let key = provider.accountKey
        guard records[key] == nil else { return }
        records[key] = LaneSchedule.AccountRecord(key: key)
        laneOf[key] = provider.pollingLane
        order.append(key)
        if lanes[provider.pollingLane] == nil { lanes[provider.pollingLane] = LaneState() }
    }

    func unregister(_ key: AccountKey) {
        records.removeValue(forKey: key)
        order.removeAll { $0 == key }
        if let lane = laneOf.removeValue(forKey: key) {
            lanes[lane]?.priority.removeAll { $0 == key }
        }
        priorityLocatorGeneration.removeValue(forKey: key)
        identityRefusals.removeValue(forKey: key)
        finish(key, outcome: .dropped)
    }

    /// KTD11: a re-enabled or newly attached account is due now once, with no history, so
    /// its first gap can neither stretch the displayed interval nor read as overdue.
    func markDueNow(_ keys: [AccountKey]) {
        for key in keys where !isInFlight(key) {
            guard var record = records[key] else { continue }
            record.lastAttempt = nil
            record.previousAttempt = nil
            record.forcedDue = true
            records[key] = record
        }
    }

    // MARK: Requests

    /// KTD2: a user asked for everything. Every eligible account is due now and bypasses
    /// the duty-cycle gate; `waitUntilUserWorkDrains()` returns when all of them merged.
    func markAllDue(origin: UserRefreshOrigin = .fullRefresh) {
        guard let host else { return }
        for key in order where host.schedulerIsEligible(key) {
            insertUserPending(key, origin: origin)
            // KTD7 parity with `requestPriority`: a probe already running answers the
            // request unless it started before a reset or handoff boundary.
            if isInFlight(key) {
                if !inFlightAnswers(key) { enqueuePriority(key) }
                continue
            }
            records[key]?.forcedDue = true
        }
    }

    /// KTD7: front of the account's lane; served after the in-flight probe.
    func requestPriority(_ key: AccountKey, origin: UserRefreshOrigin = .accountAction) {
        guard let host, records[key] != nil, host.schedulerIsEligible(key) else { return }
        insertUserPending(key, origin: origin)
        if isInFlight(key) {
            // The running probe answers the request; one that predates a reset or handoff
            // boundary cannot (its result will be rejected), so a follow-up is queued.
            if !inFlightAnswers(key) {
                enqueuePriority(key, locatorGeneration: CLIExecutableRefreshContext.generation)
            }
            return
        }
        enqueuePriority(key, locatorGeneration: CLIExecutableRefreshContext.generation)
        if let lane = laneOf[key] { dispatchUserWork(in: lane) }
    }

    /// KTD11: a surface went off. Queued user requests for its accounts can no longer be
    /// served, so their waiters are released instead of pinning `isRefreshing` and a full
    /// refresh open; an in-flight probe still finishes on its own.
    func withdraw(_ keys: [AccountKey]) {
        for key in keys {
            if let lane = laneOf[key] { lanes[lane]?.priority.removeAll { $0 == key } }
            priorityLocatorGeneration.removeValue(forKey: key)
            if !isInFlight(key) { finish(key, outcome: .dropped) }
        }
    }

    /// Timer tick, popover open, or a surface change: start every idle lane that has due
    /// work the gate allows. Draining lanes serve their own queue and are left alone.
    func dispatchDue() {
        guard host != nil else { return }
        for lane in lanes.keys {
            switch lane {
            case .serial:
                startSerialPassIfNeeded(lane)
            case .concurrent:
                dispatchConcurrent(lane)
            }
        }
    }

    func dispatchDue(for providerID: ProviderID) {
        guard host != nil else { return }
        let involved = Set(laneOf.filter { $0.key.providerID == providerID }.values)
        for lane in involved {
            switch lane {
            case .serial:
                startSerialPassIfNeeded(lane)
            case .concurrent:
                dispatchConcurrent(lane, providerID: providerID)
            }
        }
    }

    /// KTD7: start the request's own lane for user work only. A lane already draining
    /// serves the request next from its loop.
    private func dispatchUserWork(in lane: ProviderPollingLane) {
        switch lane {
        case .serial:
            startSerialPassIfNeeded(lane, userOnly: true)
        case .concurrent:
            dispatchConcurrent(lane, userOnly: true)
        }
    }

    func waitUntilUserWorkDrains() async {
        guard !userPending.isEmpty else { return }
        await withCheckedContinuation { continuation in
            userWaiters.append(continuation)
        }
    }

    func waitForCompletion(of key: AccountKey) async {
        guard userPending.contains(key) else { return }
        await withCheckedContinuation { continuation in
            completionWaiters[key, default: []].append(continuation)
        }
    }

    var allLanesIdle: Bool {
        lanes.values.allSatisfy { !$0.draining && $0.inFlight.isEmpty }
    }

    /// A full refresh returns only once every lane pass it started has ended, so pass-end
    /// capability verdicts and exports have landed (the contract the store tests rely on).
    func waitUntilLanesIdle() async {
        guard !allLanesIdle else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    // MARK: Cadence readouts (KTD4, KTD12)

    private func effectiveInterval(
        in lane: ProviderPollingLane, records: [LaneSchedule.AccountRecord], chosen: TimeInterval
    ) -> TimeInterval {
        guard case .serial = lane else { return chosen }
        let gaps = records.filter(\.isOnCadence).compactMap(\.attemptGap)
        return LaneSchedule.effectiveInterval(chosen: chosen, attemptGaps: gaps)
    }

    func effectiveInterval(forProvider providerID: ProviderID, chosen: TimeInterval) -> TimeInterval {
        guard let lane = laneOf.first(where: { $0.key.providerID == providerID })?.value else { return chosen }
        return effectiveInterval(in: lane, records: liveRecords(in: lane), chosen: chosen)
    }

    func accountCount(for providerID: ProviderID) -> Int {
        guard let host else { return 0 }
        return records.keys.filter { $0.providerID == providerID && host.schedulerIsEligible($0) }.count
    }

    /// KTD6: seconds until the earliest due account in an idle lane, or until a closed
    /// lane's budget reopens, clamped by `LaneSchedule.wakeDelay`.
    func wakeDelay() -> TimeInterval {
        guard let host else { return LaneSchedule.chosenInterval(minutes: Preferences.defaultIntervalMinutes) }
        let now = host.schedulerNow
        let chosen = host.schedulerChosenInterval
        var candidates: [Date] = []
        for (lane, state) in lanes where !state.draining && state.inFlight.isEmpty {
            let records = liveRecords(in: lane)
            let effective = effectiveInterval(in: lane, records: records, chosen: chosen)
            let dueDates = records.map { LaneSchedule.nextDue(for: $0, chosen: chosen, effective: effective) }
            guard var earliest = dueDates.min() else { continue }
            if case .serial = lane,
               let reopens = LaneSchedule.budgetReopens(log: state.log, now: now, chosen: chosen) {
                earliest = max(earliest, reopens)
            }
            candidates.append(earliest)
        }
        return LaneSchedule.wakeDelay(candidates: candidates, now: now, chosen: chosen)
    }

    // MARK: Lane passes

    private func startSerialPassIfNeeded(_ lane: ProviderPollingLane, userOnly: Bool = false) {
        guard let state = lanes[lane], !state.draining else { return }
        lanes[lane]?.userOnly = userOnly
        guard nextSerialKey(in: lane) != nil else { lanes[lane]?.userOnly = false; return }
        lanes[lane]?.draining = true
        Task { @MainActor [weak self] in
            await self?.runSerialPass(lane)
        }
    }

    private func runSerialPass(_ lane: ProviderPollingLane) async {
        guard let host else { return }
        // KTD8: one locator generation and one capability generation per pass.
        let passGeneration = UUID()
        let providers = laneOf.filter { $0.value == lane }.keys.compactMap { host.schedulerProvider(for: $0) }
        lanes[lane]?.passCapability = host.schedulerBeginCapabilityRefresh(for: providers)
        lanes[lane]?.newestCapability = [:]

        while let key = nextSerialKey(in: lane) {
            let isPriority = lanes[lane]?.priority.contains(key) == true
            lanes[lane]?.priority.removeAll { $0 == key }
            let requestedLocatorGeneration = priorityLocatorGeneration.removeValue(forKey: key)
            await probe(
                key,
                lane: lane,
                // KTD8: a user action's epoch advance must still force a fresh search.
                locatorGeneration: isPriority ? (requestedLocatorGeneration ?? UUID()) : passGeneration,
                capabilityGeneration: lanes[lane]?.passCapability[key.providerID],
                appliesCapabilityImmediately: isPriority
            )
        }

        if let state = lanes[lane] {
            for (providerID, capability) in state.newestCapability {
                host.schedulerApplyCapability(capability, for: providerID, generation: state.passCapability[providerID])
            }
        }
        lanes[lane]?.newestCapability = [:]
        lanes[lane]?.passCapability = [:]
        lanes[lane]?.userOnly = false
        lanes[lane]?.draining = false
        host.schedulerLaneDidGoIdle(lane)
        notifyIdleWaitersIfNeeded()
        // Work may have become due while the pass ran (a priority request arriving as the
        // loop exited, or the gate reopening); let the next wake or request restart it.
    }

    private func dispatchConcurrent(_ lane: ProviderPollingLane, providerID: ProviderID? = nil, userOnly: Bool = false) {
        guard let host, let state = lanes[lane] else { return }
        let now = host.schedulerNow
        let chosen = host.schedulerChosenInterval
        var records = liveRecords(in: lane)
        if let providerID { records = records.filter { $0.key.providerID == providerID } }
        if userOnly { records = records.filter { userPending.contains($0.key) } }
        let due = LaneSchedule.dueAccounts(
            records: records, priority: state.priority, now: now, chosen: chosen, effective: chosen
        ).filter { !state.inFlight.contains($0) }
        guard !due.isEmpty else { return }
        // One capability generation per batch, as the serial pass does: a per-account cycle
        // would leave only the last-dispatched probe's verdict matching its generation.
        let cycle = host.schedulerBeginCapabilityRefresh(for: due.compactMap { host.schedulerProvider(for: $0) })
        for key in due {
            lanes[lane]?.priority.removeAll { $0 == key }
            let requestedLocatorGeneration = priorityLocatorGeneration.removeValue(forKey: key)
            // A record without a provider would stay due forever; drop it rather than wake
            // every second for it.
            guard host.schedulerProvider(for: key) != nil else { unregister(key); continue }
            let attachment = host.schedulerAttachmentGeneration(for: key)
            lanes[lane]?.inFlight.insert(key)
            inFlightAttachment[key] = attachment
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.probe(
                    key,
                    lane: lane,
                    locatorGeneration: requestedLocatorGeneration ?? UUID(),
                    capabilityGeneration: cycle[key.providerID],
                    appliesCapabilityImmediately: true,
                    preReservedAttachmentGeneration: attachment
                )
                if self.lanes[lane]?.inFlight.isEmpty == true {
                    self.host?.schedulerLaneDidGoIdle(lane)
                    self.notifyIdleWaitersIfNeeded()
                }
            }
        }
    }

    private func probe(
        _ key: AccountKey,
        lane: ProviderPollingLane,
        locatorGeneration: UUID,
        capabilityGeneration: UInt64?,
        appliesCapabilityImmediately: Bool,
        preReservedAttachmentGeneration: UInt64? = nil
    ) async {
        guard let host, let provider = host.schedulerProvider(for: key), host.schedulerIsEligible(key) else {
            if preReservedAttachmentGeneration != nil {
                lanes[lane]?.inFlight.remove(key)
                inFlightAttachment.removeValue(forKey: key)
            }
            // A record without a provider would be selected again at once (serial lane) or
            // keep the wake at one second (concurrent lane).
            if host?.schedulerProvider(for: key) == nil { unregister(key) } else { finish(key, outcome: .dropped) }
            return
        }
        let start = host.schedulerNow
        if var record = records[key] {
            record.isPrimary = host.schedulerIsPrimary(key)
            record.isNeverSignedIn = LaneSchedule.isNeverSignedIn(host.schedulerFreshness(for: key))
            record.lastGapOnCadence = record.scheduledOnCadence
            record.previousAttempt = record.lastAttempt
            record.lastAttempt = start
            record.forcedDue = false
            records[key] = record
        }
        if preReservedAttachmentGeneration == nil { lanes[lane]?.inFlight.insert(key) }
        let attachment = preReservedAttachmentGeneration ?? host.schedulerAttachmentGeneration(for: key)
        inFlightAttachment[key] = attachment
        host.schedulerProbeDidStart(key)

        // User-pending, not `isPriority`: a full refresh marks accounts due without queueing
        // them, while a timer pass or popover open reaching a user-pending key still serves it.
        let isUserRequested = userPending.contains(key)
        if isUserRequested { inFlightUserRequested.insert(key) }
        let origins = isUserRequested ? (pendingOrigins.removeValue(forKey: key) ?? []) : []
        let fetched = await CLIExecutableRefreshContext.$generation.withValue(locatorGeneration) {
            await UserRequestedProbeContext.$isUserRequested.withValue(isUserRequested) {
                await UserRequestedProbeContext.$origins.withValue(origins) {
                    await provider.fetchResult()
                }
            }
        }

        inFlightAttachment.removeValue(forKey: key)
        inFlightUserRequested.remove(key)
        // The store may have gone away while the probe ran; nothing left to merge into.
        guard let liveHost = self.host else { return }
        let end = liveHost.schedulerNow
        lanes[lane]?.inFlight.remove(key)
        appendToLog(LaneSchedule.ProbeSpan(start: start, end: end), lane: lane, now: end, chosen: liveHost.schedulerChosenInterval)
        let result = boundingIdentityRefusal(fetched, for: key)
        if result.discard != nil {
            // The store refuses it, so `accepted` is false below: no backoff, no dimmed
            // row. The account is due again at the lane's next turn (R3).
            requeueAfterIdentityRefusal(key)
        }
        let accepted = liveHost.schedulerMerge(key: key, result: result, attachmentGeneration: attachment)
        // After the merge, so a pill calms on the number it just fetched.
        liveHost.schedulerProbeDidEnd(key)
        // A result the store refused (reset, handoff boundary, detached row) says nothing
        // about the row that now holds this key, so it must not move its backoff either.
        if accepted, var record = records[key] {
            let outcome = LaneSchedule.outcome(of: result)
            record.consecutiveFailures = LaneSchedule.consecutiveFailures(after: outcome, previous: record.consecutiveFailures)
            records[key] = record
        }
        if accepted, let capability = result.capability {
            if appliesCapabilityImmediately {
                liveHost.schedulerApplyCapability(capability, for: key.providerID, generation: capabilityGeneration)
            }
            // Serial lanes keep the newest verdict for pass end so a recovered later account
            // clears an earlier path miss from the same pass.
            lanes[lane]?.newestCapability[key.providerID] = capability
        }
        finish(key, outcome: accepted ? (result.snapshot.freshness == .live ? .live : .stale) : .dropped)
        // A follow-up queued behind this probe: the serial loop picks it up itself, but a
        // concurrent lane has no loop, so its batch is started here.
        if case .concurrent = lane, lanes[lane]?.priority.contains(key) == true { dispatchUserWork(in: lane) }
    }

    // MARK: Identity refusals (KTD2)

    private func boundingIdentityRefusal(_ result: UsageProviderFetchResult, for key: AccountKey) -> UsageProviderFetchResult {
        guard result.discard == .identityUnreadable else {
            identityRefusals.removeValue(forKey: key)
            return result
        }
        identityRefusalTotals[key, default: 0] += 1
        let refusals = identityRefusals[key, default: 0]
        guard refusals < Self.identityRefusalBound else { return result.withoutDiscard }
        identityRefusals[key] = refusals + 1
        return result
    }

    private func requeueAfterIdentityRefusal(_ key: AccountKey) {
        records[key]?.forcedDue = true
        // A user who asked for this account gets one more read inside the same refresh;
        // `finish` leaves the request open while the follow-up is queued.
        guard userPending.contains(key), identityRequeued.insert(key).inserted else { return }
        enqueuePriority(key)
    }

    // MARK: Helpers

    /// Records the host can currently schedule, with the fields that live on the store
    /// (primary selection, never-signed-in state, reset deadline) filled in at read time.
    private func liveRecords(in lane: ProviderPollingLane) -> [LaneSchedule.AccountRecord] {
        guard let host else { return [] }
        let now = host.schedulerNow
        return order.compactMap { key -> LaneSchedule.AccountRecord? in
            guard laneOf[key] == lane, var record = records[key], host.schedulerIsEligible(key) else { return nil }
            record.isPrimary = host.schedulerIsPrimary(key)
            record.isNeverSignedIn = LaneSchedule.isNeverSignedIn(host.schedulerFreshness(for: key))
            // R2M3: a deadline is phased relative to the attempt it must post-date, not to
            // now — by the time the engine wakes at deadline + grace, the deadline has passed.
            record.resetDeadline = host.schedulerResetDeadline(for: key, after: record.lastAttempt ?? now)
            return record
        }
    }

    private func isInFlight(_ key: AccountKey) -> Bool {
        guard let lane = laneOf[key] else { return false }
        return lanes[lane]?.inFlight.contains(key) == true
    }

    /// Whether the probe running for `key` started under the store's current attachment
    /// generation, so its result will be accepted and can answer a user request. A timer
    /// probe for a provider that serves cached status to timer probes cannot: the user asked
    /// for a fresh read, which only a probe started as user-requested makes.
    private func inFlightAnswers(_ key: AccountKey) -> Bool {
        guard let host, let started = inFlightAttachment[key],
              started == host.schedulerAttachmentGeneration(for: key)
        else { return false }
        if inFlightUserRequested.contains(key) { return true }
        return host.schedulerProvider(for: key)?.reusesCachedStatusOnTimerProbes != true
    }

    private func enqueuePriority(_ key: AccountKey, locatorGeneration: UUID? = nil) {
        guard let lane = laneOf[key] else { return }
        if let locatorGeneration {
            priorityLocatorGeneration[key] = locatorGeneration
        }
        guard lanes[lane]?.priority.contains(key) == false else { return }
        lanes[lane]?.priority.append(key)
    }

    /// The account a serial lane probes next, or nil when nothing may start. One live read
    /// of the lane feeds both the effective-interval readout and the gated candidates.
    /// R8: timer work waits for the budget; user work never does, so a closed gate narrows
    /// the candidates to user requests instead of ending the pass. A user-started pass
    /// (KTD7) is narrowed the same way whatever the gate says.
    private func nextSerialKey(in lane: ProviderPollingLane) -> AccountKey? {
        guard let host, let state = lanes[lane] else { return nil }
        let now = host.schedulerNow
        let chosen = host.schedulerChosenInterval
        let records = liveRecords(in: lane)
        let timerMayStart = !state.userOnly && LaneSchedule.mayStartTimerProbe(log: state.log, now: now, chosen: chosen)
        let candidates = timerMayStart ? records : records.filter { userPending.contains($0.key) }
        return LaneSchedule.nextAccount(
            records: candidates,
            priority: state.priority,
            now: now,
            chosen: chosen,
            effective: effectiveInterval(in: lane, records: records, chosen: chosen)
        )
    }

    private func notifyIdleWaitersIfNeeded() {
        guard allLanesIdle, !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func appendToLog(_ span: LaneSchedule.ProbeSpan, lane: ProviderPollingLane, now: Date, chosen: TimeInterval) {
        guard case .serial = lane else { return }
        var log = lanes[lane]?.log ?? []
        log.append(span)
        let horizon = now.addingTimeInterval(-2 * LaneSchedule.window(chosen: chosen))
        log.removeAll { $0.end < horizon }
        lanes[lane]?.log = log
    }

    private func insertUserPending(_ key: AccountKey, origin: UserRefreshOrigin) {
        let wasEmpty = userPending.isEmpty
        pendingOrigins[key, default: []].insert(origin)
        // R5: setup verification must not replace a user's retained landing during its end hold.
        if userRun == nil || (wasEmpty && host?.schedulerStartsNewUserRun(origin: origin) == true) {
            userRun = UserRefreshRun(startedAt: host?.schedulerNow ?? Date())
        }
        if origin == .setupCheck,
           let entry = userRun?.entries[key], entry.origin != .setupCheck, entry.outcome != nil {
            setupPendingPreservingLanding.insert(key)
        } else {
            // An explicit user request can upgrade the setup-only probe already in flight
            // and reopen the historical entry; ordinary pending precedence stays unchanged.
            setupPendingPreservingLanding.remove(key)
            if var entry = userRun?.entries[key] {
                let becomesUserRequest = entry.origin == .setupCheck && origin != .setupCheck
                if origin != .setupCheck || entry.origin == .setupCheck { entry.origin = origin }
                // Coalesced user requests keep their first wipe time. Upgrading a setup check
                // starts its first wipe now; re-reading a landed key starts a new one (KTD2).
                if entry.outcome != nil || becomesUserRequest {
                    entry.requestedAt = host?.schedulerNow ?? Date()
                    entry.outcome = nil
                    entry.landedAt = nil
                }
                userRun?.entries[key] = entry
            } else {
                userRun?.entries[key] = UserRefreshEntry(origin: origin, requestedAt: host?.schedulerNow ?? Date())
            }
            if let userRun { host?.schedulerUserRunDidChange(userRun) }
        }
        guard userPending.insert(key).inserted else { return }
        if wasEmpty { userTotal = 0; userCompleted = 0 }
        userTotal += 1
        if wasEmpty { host?.schedulerUserWorkDidChange(hasPending: true) }
        host?.schedulerUserProgressDidChange(total: userTotal, completed: userCompleted, landed: nil)
    }

    private func finish(_ key: AccountKey, outcome: UserRefreshOutcome) {
        // A follow-up probe is still queued for this key; it answers the waiters instead.
        if let lane = laneOf[key], lanes[lane]?.priority.contains(key) == true { return }
        if let waiters = completionWaiters.removeValue(forKey: key) {
            for waiter in waiters { waiter.resume() }
        }
        identityRequeued.remove(key)
        guard userPending.remove(key) != nil else { return }
        pendingOrigins.removeValue(forKey: key)
        if setupPendingPreservingLanding.remove(key) == nil {
            userRun?.entries[key]?.outcome = outcome
            userRun?.entries[key]?.landedAt = host?.schedulerNow
            if let userRun { host?.schedulerUserRunDidChange(userRun) }
        }
        userCompleted += 1
        host?.schedulerUserProgressDidChange(total: userTotal, completed: userCompleted, landed: key)
        guard userPending.isEmpty else { return }
        host?.schedulerUserWorkDidChange(hasPending: false)
        let waiters = userWaiters
        userWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
