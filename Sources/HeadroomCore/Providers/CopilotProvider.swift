import CryptoKit
import Foundation

/// One monthly AI credit meter for the account signed in to the official Copilot CLI's
/// default home. Credit use comes from the CLI's session logs (`CopilotUsageLedger`) and
/// the allowance from its local server (`CopilotStatusSource`).
public struct CopilotProvider: UsageProvider {
    public let id = ProviderID.copilot
    public let displayName = ProviderID.copilot.displayName
    public let pollingLane: ProviderPollingLane = .serial("copilot-cli")
    /// A Headroom-owned `COPILOT_HOME` never receives the session logs this meter reads,
    /// so an extra account would stay unavailable forever.
    public let accountCapacity = 1
    /// `CopilotStatusSource` serves timer probes from its hour-long cache.
    public let reusesCachedStatusOnTimerProbes = true

    static let window = BillingPeriodWindowClassifier.kind(periodType: "monthly", durationSeconds: nil)

    private let statusSource: any CopilotStatusSourcing
    private let ledger: CopilotUsageLedger
    private let loginMemory: any CopilotLoginMemory
    private let now: @Sendable () -> Date

    /// Pass the same `ledger` for every poll: its memo is what keeps a poll from rereading
    /// unchanged session files.
    public init(
        statusSource: any CopilotStatusSourcing,
        ledger: CopilotUsageLedger,
        loginMemory: any CopilotLoginMemory,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.statusSource = statusSource
        self.ledger = ledger
        self.loginMemory = loginMemory
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await statusSource.status() {
        case .cliMissing: return stale(.providerSetup(.copilotCLIMissing))
        case .signedOut: return stale(.providerSetup(.copilotSignedOut))
        case .failure(let reason): return stale(reason)
        case .signedIn(let status):
            // KTD13: the login comes from the status call that served the reading, up to
            // an hour old, so it labels the reading but cannot bracket it.
            let identity = AccountIdentity.copilot(login: status.login).map(AccountIdentityOutcome.known) ?? .absent
            let snapshot = await snapshot(for: status)
            return snapshot.freshness == .live ? snapshot.withIdentity(identity) : snapshot
        }
    }

    /// The used figure the provider shows. The logs alone miss use from other clients, and
    /// the server's count alone is coarse, so the server can only raise the logs' figure, by
    /// the least use its reading proves. Public so `--probe-copilot` prints exactly this value.
    public static func reading(
        from ledger: CopilotUsageLedger,
        for status: CopilotAccountStatus,
        loginChangedAt: Date?,
        now: Date
    ) async -> CopilotLedgerOutcome {
        let month = CopilotLedgerCalculator.utcMonth(containing: now)
        // Logs carry no login, so after a change nothing older is known to be this
        // account's. A change in an earlier month is behind this month's reset already.
        let notBefore = loginChangedAt.flatMap { month.contains($0) ? $0 : nil }
        func input(anchor: CopilotUsageAnchor?) -> CopilotLedgerInput {
            CopilotLedgerInput(tokenBasedBilling: status.tokenBasedBilling, anchor: anchor, evidenceNotBefore: notBefore)
        }

        let fromLogs = await ledger.read(input(anchor: nil))
        guard case .reading(let logs) = fromLogs,
              let anchor = serverAnchor(for: status, now: now, month: month),
              case .reading(let withServer) = await ledger.read(input(anchor: anchor)),
              let raised = withServer.usedCredits,
              raised > (logs.usedCredits ?? 0)
        else { return fromLogs }
        return .reading(CopilotLedgerReading(
            usedCredits: raised,
            resetsAt: logs.resetsAt ?? withServer.resetsAt,
            newestEvidenceAt: withServer.newestEvidenceAt
        ))
    }

    /// GitHub rounds the server's count to the nearest 0.5% of the allowance and caches it,
    /// and CLI 1.0.105 puts the time of that reading in `resetDate`, so a past `resetDate`
    /// dates a coarse but genuine count. Half a rounding step below it is the least use it
    /// proves: 300 of 20,000 was reported while true use was 285. That bound also keeps a
    /// cached 0, returned for over an hour while true use was 104 to 284, from counting. A
    /// future `resetDate` means the CLI now reports a real reset, so the reading's time is
    /// unknown.
    private static func serverAnchor(
        for status: CopilotAccountStatus,
        now: Date,
        month: Range<Date>
    ) -> CopilotUsageAnchor? {
        guard let reported = status.reportedUsed, let entitlement = status.entitlement,
              let observedAt = status.reportedResetDate,
              !(observedAt > now), month.contains(observedAt)
        else { return nil }
        let leastUse = reported - entitlement * 0.0025
        guard leastUse > 0 else { return nil }
        return CopilotUsageAnchor(used: leastUse, observedAt: observedAt)
    }

    private func snapshot(for status: CopilotAccountStatus) async -> UsageSnapshot {
        let now = now()
        let month = CopilotLedgerCalculator.utcMonth(containing: now)
        let loginChangedAt = loginMemory.loginChangedAt(noting: status.login, at: now)

        guard !status.isUnlimited, let entitlement = status.entitlement, entitlement > 0 else {
            return unavailable(now: now, month: month)
        }
        guard case .reading(let reading) = await Self.reading(
            from: ledger, for: status, loginChangedAt: loginChangedAt, now: now
        ) else {
            return stale(.providerSetup(.copilotLogsUnreadable))
        }
        guard let used = reading.usedCredits, let evidenceAt = reading.newestEvidenceAt else {
            return unavailable(now: now, month: month)
        }

        // A live window's `observedAt` stays nil: `FreshnessStamp.Anchors` prefers it over
        // the capture time, so log time would drag the shared footer back. `capturedAt`
        // stays the poll time for the same reason in the scheduler and the phone stamp.
        let isCurrent = now.timeIntervalSince(evidenceAt) <= CompanionFreshnessRule.minimumThreshold
        let reset = reading.resetsAt ?? status.reportedResetDate.flatMap { $0 > now ? $0 : nil }
        let window = UsageWindow(
            kind: Self.window,
            utilization: used / entitlement * 100,
            resetSchedule: reset.map(ResetSchedule.scheduled) ?? .unresolved(.absent),
            freshness: isCurrent ? .live : .stale(observedAt: evidenceAt)
        )
        return UsageSnapshot(providerID: id, windows: [window], planLabel: nil, capturedAt: now, freshness: .live)
    }

    /// Live so a fresh sign-in completes setup, with a row rather than no windows because
    /// the Lock Screen reads an empty snapshot as still loading. `since` is the month start
    /// so the row is identical between polls and the phone's key is not rewritten.
    private func unavailable(now: Date, month: Range<Date>) -> UsageSnapshot {
        let window = UsageWindow(
            kind: Self.window,
            utilization: 0,
            resetSchedule: .unresolved(.absent),
            freshness: .unavailable(since: month.lowerBound)
        )
        return UsageSnapshot(providerID: id, windows: [window], planLabel: nil, capturedAt: now, freshness: .live)
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}

/// When the Copilot CLI's signed-in login last changed. Only a digest of the login is
/// kept, never the login itself.
public protocol CopilotLoginMemory: Sendable {
    /// Records `login` as the one seen at `now` and returns when the login last changed,
    /// or nil if it never has. The first login ever seen is not a change.
    func loginChangedAt(noting login: String, at now: Date) -> Date?
}

public struct UserDefaultsCopilotLoginMemory: CopilotLoginMemory, @unchecked Sendable {
    private static let digestKey = "copilotLogin.v1.digest"
    private static let changedAtKey = "copilotLogin.v1.changedAt"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loginChangedAt(noting login: String, at now: Date) -> Date? {
        let digest = SHA256.hash(data: Data(login.utf8)).map { String(format: "%02x", $0) }.joined()
        let previous = defaults.string(forKey: Self.digestKey)
        if previous != digest {
            defaults.set(digest, forKey: Self.digestKey)
            if previous != nil { defaults.set(now, forKey: Self.changedAtKey) }
        }
        return defaults.object(forKey: Self.changedAtKey) as? Date
    }
}
