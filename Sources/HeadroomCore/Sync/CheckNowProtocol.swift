import Foundation
import os

// iPhone parity U6 (KTD14, R18, R19): the phone side of check-now. Pure state machine plus
// a thin client that owns the KVS request key and the App Group state. Compiled into both
// iOS targets (whole-folder Sync membership, KTD4), so it names only Models/Sync/Widgets
// types. The Mac side is `Engine/CheckNowCoordinator.swift`.

// MARK: - Timing

/// KTD14 timing. The acknowledgement and age numbers are the plan's; the per-probe estimate
/// is a documented provisional constant until the two-device spike
/// (`docs/qa/2026-10-check-now-latency-spike.md`) replaces it with a measurement.
public enum CheckNowTiming {
    /// KTD14.7: no acknowledgement this long after asking reads "hasn't answered".
    public static let acknowledgementTimeout: TimeInterval = 60
    /// AE2 / KTD14.3: how long a request stays answerable. A late acknowledgement inside it
    /// resumes the request; the Mac's launch scan ignores anything older.
    public static let requestAgeLimit: TimeInterval = 10 * 60
    /// KTD14.3: clock skew the Mac allows on top of the age limit at its launch scan.
    public static let clockSkewAllowance: TimeInterval = 2 * 60
    /// KTD14.7: the floor of the finish window, measured from the acknowledgement.
    public static let minimumFinishWindow: TimeInterval = 3 * 60
    /// PROVISIONAL pending the U6 spike: one probe's worst case. A Claude probe is ~3–5 s on
    /// the print path and ~20–30 s on the PTY fallback (AGENTS.md), so the fallback's upper
    /// bound keeps a 20-account lane from timing out early.
    public static let provisionalPerProbeSeconds: TimeInterval = 30
    /// KTD14.4: a full refresh of any origin answers "checked a moment ago" for this long.
    public static let cooldown: TimeInterval = 60
    /// KTD8: receipts are written at most this often while a check runs.
    public static let receiptSpacing: TimeInterval = 15
    /// KTD14.8: request keys older than this are pruned; newer ones are never deleted
    /// outside sync-off.
    public static let requestRetention: TimeInterval = 30 * 24 * 60 * 60

    /// KTD14.7: ack time + max(3 minutes, largest lane's account count × per-probe time).
    public static func finishWindow(largestLaneAccountCount: Int) -> TimeInterval {
        max(minimumFinishWindow, Double(max(0, largestLaneAccountCount)) * provisionalPerProbeSeconds)
    }
}

// MARK: - Copy

/// Phone check-now copy, pinned under the R2C6 copy rules (one sign-in verb, no "connect",
/// curly apostrophes, non-breaking space around em dashes). Progress lines reuse the Mac
/// footer's `RefreshReceiptPresentation`.
public enum CheckNowCopy {
    public static let asking = "Asking your Mac…"
    public static let noAnswer = "Your Mac hasn’t answered. It may be asleep, or Headroom isn’t open."
    public static let notFinished = "Your Mac started checking but hasn’t finished. Pull again later."
    public static let justNow = "Just now"
    public static let checkedMomentAgo = "Checked a moment ago"

    /// "Checked · 1 account didn’t update".
    public static func notUpdated(_ count: Int) -> String {
        "Checked · \(count) \(count == 1 ? "account" : "accounts") didn’t update"
    }
}

// MARK: - Device identity

/// KTD14.1: one random UUID per install, shared through the App Group by the app, the
/// widget extension and controls. Never a device name.
public enum CheckNowDeviceIdentity {
    public static let defaultsKey = "companionSync.deviceUUID.v1"

    public static func deviceUUID(in defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: defaultsKey), let uuid = UUID(uuidString: stored) {
            return uuid.uuidString.lowercased()
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: defaultsKey)
        defaults.synchronize()
        return created
    }
}

// MARK: - State

/// One outstanding request per phone install (contract Decision 2). Counts, maxima and the
/// acknowledgement time are phone-local; nothing here compares the Mac's clock.
public struct CheckNowRequestState: Codable, Equatable, Sendable {
    public let requestID: String
    /// The Mac the request was addressed to (the manifest's lineage at pull time).
    public let sourceID: String
    /// Phone clock. Only phone-local durations are measured from it.
    public let askedAt: Date
    /// KTD14.7: sizes the finish window.
    public let largestLaneAccountCount: Int
    /// Phone clock when this request's ID first appeared in a receipt or answer.
    public internal(set) var acknowledgedAt: Date?
    public internal(set) var total: Int?
    public internal(set) var completed: Int = 0
    public internal(set) var lastLanded: CompanionLastLanded?
    /// Terminal evidence for this request ID only: finished, cooldown or failed.
    public internal(set) var outcome: CompanionAnsweredOutcome?
    public internal(set) var finishedGeneration: Int64?
    /// The highest generation of this Mac the phone has fully assembled.
    public internal(set) var assembledGeneration: Int64?
    /// Accounts in that assembled snapshot that did not come back live.
    public internal(set) var notUpdatedCount: Int = 0

    public init(
        requestID: String, sourceID: String, askedAt: Date, largestLaneAccountCount: Int,
        assembledGeneration: Int64? = nil
    ) {
        self.requestID = requestID
        self.sourceID = sourceID
        self.askedAt = askedAt
        self.largestLaneAccountCount = largestLaneAccountCount
        self.assembledGeneration = assembledGeneration
    }
}

public enum CheckNowPhase: Equatable, Sendable {
    /// Written; no acknowledgement yet.
    case asking
    /// Acknowledged; `completed` only moves forward. Also covers a finished receipt whose
    /// generation the phone has not assembled yet.
    case checking(total: Int?, completed: Int, lastLanded: CompanionLastLanded?)
    /// No acknowledgement within 60 s. A later acknowledgement inside the age limit resumes.
    case noAnswer
    /// The finish window passed, or the Mac answered that it could not finish.
    case notFinished
    /// Finished and assembled at `finishedGeneration` or later.
    case finished(notUpdated: Int)
    /// The Mac had just refreshed: "Checked a moment ago", completed the same way.
    case cooldown
}

// MARK: - Machine

public enum CheckNowBegin: Equatable, Sendable {
    /// A new request to write under this install's request key.
    case requested(CheckNowRequestState, CompanionRequest)
    /// The install's outstanding request; pulls coalesce onto it (Decision 2, AE3).
    case pending(CheckNowRequestState)
    /// KTD14.1: an old, downgraded or paused Mac, or nothing readable — re-read only.
    case rereadOnly
}

/// KTD14.7 as pure functions of the state, the latest receipt, the latest resolved snapshot
/// and the phone clock.
public enum CheckNowMachine {
    /// Requests go out only when the resolver's winner is v4 (KTD14.1).
    public static func begin(
        snapshot: CompanionResolvedSnapshot, current: CheckNowRequestState?, requestID: String,
        now: Date
    ) -> CheckNowBegin {
        guard let content = snapshot.content, content.origin == .v4, let sourceID = content.sourceID,
            let wireNow = CompanionWireDate(date: now)
        else { return .rereadOnly }
        if let current, current.sourceID == sourceID, !isSettled(current, now: now) {
            return .pending(current)
        }
        guard let request = try? CompanionRequest(requestID: requestID, requestedAt: wireNow, sourceID: sourceID)
        else { return .rereadOnly }
        var state = CheckNowRequestState(
            requestID: request.requestID, sourceID: sourceID, askedAt: now,
            largestLaneAccountCount: largestLaneAccountCount(content))
        state = receive(snapshot, into: state, now: now)
        return .requested(state, request)
    }

    /// Own-ID evidence only (Decision 2): a foreign Mac's receipt, another phone's run and a
    /// receipt that does not name this request change nothing.
    public static func receive(
        _ receipt: CompanionReceipt, into state: CheckNowRequestState, now: Date
    ) -> CheckNowRequestState {
        guard receipt.sourceID == state.sourceID else { return state }
        var next = state
        if let answer = receipt.answeredRequests.first(where: { $0.requestID == state.requestID }) {
            apply(answer, to: &next, now: now)
        }
        guard receipt.requestIDs.contains(state.requestID) else { return next }
        // AE2: a late acknowledgement resumes the request only inside the age limit.
        guard next.acknowledgedAt != nil || now.timeIntervalSince(state.askedAt) < CheckNowTiming.requestAgeLimit
        else { return next }
        if next.acknowledgedAt == nil { next.acknowledgedAt = now }
        if let total = receipt.total, let completed = receipt.completed {
            next.total = max(next.total ?? 0, total)
            if completed > next.completed {
                next.completed = completed
                next.lastLanded = receipt.lastLanded ?? next.lastLanded
            } else if next.lastLanded == nil {
                next.lastLanded = receipt.lastLanded
            }
        }
        switch receipt.state {
        case .finished, .cooldown:
            // A finished run names its answer's generation; an answer already applied for
            // this ID agrees with it (the Mac writes both from one decision).
            if next.outcome == nil || next.outcome == .finished || next.outcome == .cooldown {
                next.outcome = receipt.state == .cooldown ? .cooldown : .finished
                next.finishedGeneration = receipt.finishedGeneration ?? next.finishedGeneration
            }
        case .accepted, .running, .unknown:
            break
        }
        return next
    }

    /// The snapshot supplies assembly (`assembledGeneration`) and, through the manifest's
    /// answered list, snapshot-first completion (Decision 2). A newer heartbeat without this
    /// request's answer completes nothing.
    public static func receive(
        _ snapshot: CompanionResolvedSnapshot, into state: CheckNowRequestState, now: Date
    ) -> CheckNowRequestState {
        guard let content = snapshot.content, content.origin == .v4, content.sourceID == state.sourceID
        else { return state }
        var next = state
        if let assembled = content.assembledGeneration, assembled >= (next.assembledGeneration ?? .min) {
            next.assembledGeneration = assembled
            // Default-login R12: a check never reads a remembered row, so it is not one the
            // check failed to update.
            next.notUpdatedCount = content.providers.flatMap(\.accounts)
                .filter { $0.freshness != .live && !$0.isRemembered }.count
        }
        if let answer = content.answeredRequests.first(where: { $0.requestID == state.requestID }) {
            apply(answer, to: &next, now: now)
        }
        return next
    }

    public static func phase(of state: CheckNowRequestState, now: Date) -> CheckNowPhase {
        switch state.outcome {
        case .failed:
            return .notFinished
        case .finished, .cooldown:
            // "Just now" only once the phone has assembled finishedGeneration or later.
            if let finished = state.finishedGeneration, let assembled = state.assembledGeneration,
                assembled >= finished
            {
                return state.outcome == .cooldown ? .cooldown : .finished(notUpdated: state.notUpdatedCount)
            }
        case .unknown, nil:
            break
        }
        guard let acknowledgedAt = state.acknowledgedAt else {
            return now.timeIntervalSince(state.askedAt) >= CheckNowTiming.acknowledgementTimeout
                ? .noAnswer : .asking
        }
        if !(now < finishDeadline(acknowledgedAt: acknowledgedAt, state: state)) { return .notFinished }
        return .checking(total: state.total, completed: state.completed, lastLanded: state.lastLanded)
    }

    /// A settled request no longer coalesces pulls: the next pull asks again.
    public static func isSettled(_ state: CheckNowRequestState, now: Date) -> Bool {
        switch phase(of: state, now: now) {
        case .finished, .cooldown, .notFinished: true
        case .noAnswer: now.timeIntervalSince(state.askedAt) >= CheckNowTiming.requestAgeLimit
        case .asking, .checking: false
        }
    }

    /// When the phase can next change on its own (a timeout), so a host can re-evaluate.
    public static func nextDeadline(of state: CheckNowRequestState, now: Date) -> Date? {
        switch phase(of: state, now: now) {
        case .asking:
            return state.askedAt.addingTimeInterval(CheckNowTiming.acknowledgementTimeout)
        case .noAnswer:
            let expiry = state.askedAt.addingTimeInterval(CheckNowTiming.requestAgeLimit)
            return expiry > now ? expiry : nil
        case .checking:
            return state.acknowledgedAt.map { finishDeadline(acknowledgedAt: $0, state: state) }
        case .notFinished, .finished, .cooldown:
            return nil
        }
    }

    /// KTD14.7: the largest lane's account count, from what the phone sees. Every account
    /// of one provider shares that provider's lane.
    public static func largestLaneAccountCount(_ content: CompanionResolvedContent) -> Int {
        content.providers.map { $0.accounts.count + $0.omittedAccountCount }.max() ?? 0
    }

    private static func finishDeadline(acknowledgedAt: Date, state: CheckNowRequestState) -> Date {
        acknowledgedAt.addingTimeInterval(
            CheckNowTiming.finishWindow(largestLaneAccountCount: state.largestLaneAccountCount))
    }

    private static func apply(_ answer: CompanionAnsweredRequest, to state: inout CheckNowRequestState, now: Date) {
        switch answer.outcome {
        case .finished, .cooldown:
            state.outcome = answer.outcome
            state.finishedGeneration = answer.finishedGeneration
        case .failed:
            state.outcome = .failed
        case .unknown:
            return
        }
        if state.acknowledgedAt == nil { state.acknowledgedAt = now }
    }
}

// MARK: - Presentation

/// What the phone's status line shows (U9 draws it): a receipt line while the Mac reports
/// progress, otherwise one sentence.
public enum CheckNowLine: Equatable, Sendable {
    case receipt(RefreshReceiptPresentation.Line)
    case message(String)
}

public struct CheckNowStatus: Equatable, Sendable {
    public let phase: CheckNowPhase
    public let line: CheckNowLine
    /// KTD16: the dot-matrix spinner shows only while a real check is in flight.
    public let isInFlight: Bool
    /// When the host should re-evaluate without new data (a timeout).
    public let nextDeadline: Date?
    /// The request ID this status describes.
    public let requestID: String
    /// Phone clock when the request was written: the start of Settings' round trip (U9).
    public let askedAt: Date

    public static func make(
        state: CheckNowRequestState, snapshot: CompanionResolvedSnapshot?, now: Date
    ) -> CheckNowStatus {
        let phase = CheckNowMachine.phase(of: state, now: now)
        let line: CheckNowLine
        switch phase {
        case .asking: line = .message(CheckNowCopy.asking)
        case .noAnswer: line = .message(CheckNowCopy.noAnswer)
        case .notFinished: line = .message(CheckNowCopy.notFinished)
        case .cooldown: line = .message(CheckNowCopy.checkedMomentAgo)
        case .finished(let notUpdated):
            line = .message(notUpdated > 0 ? CheckNowCopy.notUpdated(notUpdated) : CheckNowCopy.justNow)
        case .checking(let total, let completed, let landed):
            let content = snapshot?.content
            let accounts = total ?? content?.providers.reduce(0) { $0 + $1.accounts.count } ?? 0
            if let landed, completed > 0, let title = title(of: landed, in: content) {
                line = .receipt(
                    RefreshReceiptPresentation.landed(
                        title: title, live: landed.live, completed: completed, total: max(accounts, completed)))
            } else {
                line = .receipt(RefreshReceiptPresentation.checking(accounts))
            }
        }
        let inFlight: Bool
        switch phase {
        case .asking, .checking: inFlight = true
        case .noAnswer, .notFinished, .finished, .cooldown: inFlight = false
        }
        return CheckNowStatus(
            phase: phase, line: line, isInFlight: inFlight,
            nextDeadline: CheckNowMachine.nextDeadline(of: state, now: now), requestID: state.requestID,
            askedAt: state.askedAt)
    }

    /// KTD14.6: the phone looks the title up by account ID; an unknown provider or account
    /// omits the landed row rather than fabricate one.
    static func title(of landed: CompanionLastLanded, in content: CompanionResolvedContent?) -> String? {
        guard let provider = content?.providers.first(where: { $0.id == landed.providerID }),
            let account = provider.accounts.first(where: { $0.accountID == landed.accountID })
        else { return nil }
        return RefreshReceiptPresentation.title(
            providerName: provider.displayName, accountTitle: account.title,
            providerAccountCount: provider.accounts.count + provider.omittedAccountCount)
    }
}

// MARK: - Client

/// U6 spike instrumentation (`docs/qa/2026-10-check-now-latency-spike.md`): one line per
/// state change, the request ID's first eight characters only, static wording otherwise.
public enum CheckNowLog {
    public static let logger = Logger(subsystem: "com.kylezantos.headroom", category: "checknow")

    public static func tag(_ requestID: String) -> String { String(requestID.prefix(8)) }

    static func name(_ phase: CheckNowPhase) -> String {
        switch phase {
        case .asking: "asking"
        case .checking: "checking"
        case .noAnswer: "noAnswer"
        case .notFinished: "notFinished"
        case .finished: "finished"
        case .cooldown: "cooldown"
        }
    }
}

/// Where the install's one request state lives: the App Group, so the app, the widget
/// extension and controls coalesce onto one outstanding request (Decision 2).
public protocol CheckNowStateStoring: Sendable {
    func load() -> CheckNowRequestState?
    func save(_ state: CheckNowRequestState?)
}

public struct CheckNowDefaultsStateStore: CheckNowStateStoring, @unchecked Sendable { // UserDefaults is thread-safe
    public static let defaultsKey = "companionSync.checkNow.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> CheckNowRequestState? {
        defaults.data(forKey: Self.defaultsKey).flatMap {
            try? JSONDecoder().decode(CheckNowRequestState.self, from: $0)
        }
    }

    public func save(_ state: CheckNowRequestState?) {
        if let state, let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }
}

public enum CheckNowPullResult: Equatable, Sendable {
    case requested(CheckNowStatus)
    case pending(CheckNowStatus)
    /// KTD14.1: re-read the last sync; nothing was written.
    case rereadOnly
}

/// The phone's check-now entry point (U9 calls it). Demo never constructs one: Explore Demo
/// replays `CompanionDemoModeStore.replayCheckNow` through `CheckNowMachine` and writes
/// nothing (KTD21, AE8).
public final class CheckNowClient: @unchecked Sendable {
    private let store: any iCloudKeyValueSyncing
    private let stateStore: any CheckNowStateStoring
    private let deviceUUID: String
    private let now: @Sendable () -> Date
    private let makeRequestID: @Sendable () -> String
    private let lock = NSLock()

    public init(
        store: any iCloudKeyValueSyncing, stateStore: any CheckNowStateStoring, deviceUUID: String,
        now: @escaping @Sendable () -> Date = Date.init,
        makeRequestID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.store = store
        self.stateStore = stateStore
        self.deviceUUID = deviceUUID
        self.now = now
        self.makeRequestID = makeRequestID
    }

    /// Production composition: the real KVS store and the App Group's state and device ID.
    public static func appGroup(
        suiteName: String = WidgetSnapshotCache.appGroupSuiteName
    ) -> CheckNowClient? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        return CheckNowClient(
            store: UbiquitousKeyValueSyncStore(), stateStore: CheckNowDefaultsStateStore(defaults: defaults),
            deviceUUID: CheckNowDeviceIdentity.deviceUUID(in: defaults))
    }

    /// Pull to refresh. Writes this install's request key and synchronizes only when the
    /// resolver's winner is v4; otherwise the host re-reads (KTD14.1, AE1).
    public func pull(snapshot: CompanionResolvedSnapshot) -> CheckNowPullResult {
        lock.withLock {
            let at = now()
            switch CheckNowMachine.begin(
                snapshot: snapshot, current: stateStore.load(), requestID: makeRequestID(), now: at)
            {
            case .rereadOnly:
                return .rereadOnly
            case .pending(let state):
                // Nudge delivery of the one outstanding request; the Mac dedupes by ID.
                store.synchronize()
                return .pending(CheckNowStatus.make(state: state, snapshot: snapshot, now: at))
            case .requested(let state, let request):
                guard let key = CompanionSyncKeys.request(deviceUUID: deviceUUID),
                    let bytes = try? CompanionSyncCodec.encode(request), store.set(bytes, forKey: key)
                else { return .rereadOnly }
                store.synchronize()
                stateStore.save(state)
                CheckNowLog.logger.info("phone request \(CheckNowLog.tag(state.requestID), privacy: .public) written")
                return .requested(CheckNowStatus.make(state: state, snapshot: snapshot, now: at))
            }
        }
    }

    /// Folds the current receipt key and the latest resolved snapshot into the shared state.
    /// Call it on every KVS change, snapshot reload and `nextDeadline`. Nil with no request.
    public func update(snapshot: CompanionResolvedSnapshot) -> CheckNowStatus? {
        lock.withLock {
            guard var state = stateStore.load() else { return nil }
            let at = now()
            let before = CheckNowMachine.phase(of: state, now: at)
            if case .value(let receipt) = CompanionSyncCodec.decodeReceipt(store.data(forKey: CompanionSyncKeys.receipt)) {
                state = CheckNowMachine.receive(receipt, into: state, now: at)
            }
            state = CheckNowMachine.receive(snapshot, into: state, now: at)
            stateStore.save(state)
            let status = CheckNowStatus.make(state: state, snapshot: snapshot, now: at)
            if CheckNowLog.name(before) != CheckNowLog.name(status.phase) {
                CheckNowLog.logger.info(
                    "phone request \(CheckNowLog.tag(state.requestID), privacy: .public) \(CheckNowLog.name(status.phase), privacy: .public) after \(at.timeIntervalSince(state.askedAt), format: .fixed(precision: 1), privacy: .public)s")
            }
            return status
        }
    }
}
