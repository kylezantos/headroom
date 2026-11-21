import Foundation

/// KTD7: a bounded, local baseline. Rejected credentials are counted separately from
/// confirmed sign-outs; neither event attributes a cause to Headroom or the provider.
@MainActor
public final class SessionReliabilityRecord {
    public static let retentionDays = 14

    public struct Day: Codable, Equatable, Sendable {
        public let startedAt: Date
        public let provider: ProviderID
        public let builtIn: Bool
        public fileprivate(set) var observations = 0
        public fileprivate(set) var liveReadings = 0
        public fileprivate(set) var signOutTransitions = 0
        public fileprivate(set) var rejectedAuthTransitions = 0
        public fileprivate(set) var sampledAccountSeconds: TimeInterval = 0
        public fileprivate(set) var peakTrackedAccounts = 0
        fileprivate var accounts: Set<AccountID> = []

        public var observedAccounts: Int { accounts.count }
    }

    private struct Observation: Codable {
        let account: AccountKey
        var at: Date
        var lastKnownLive: Bool
    }

    private struct Stored: Codable {
        var days: [Day] = []
        var observations: [Observation] = []
    }

    private enum Outcome {
        case live, signedOut, rejected, inconclusive
    }

    private static let storageKey = "sessionReliability.v1"
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(defaults: UserDefaults, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    public var days: [Day] {
        pruned(load(), at: now()).days.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            if $0.provider != $1.provider { return $0.provider.raw < $1.provider.raw }
            return $0.builtIn && !$1.builtIn
        }
    }

    public func note(
        _ snapshot: UsageSnapshot,
        for account: AccountKey,
        expectedInterval: TimeInterval,
        trackedAccounts: [AccountKey] = []
    ) {
        let date = now()
        var stored = pruned(load(), at: date)
        let prior = stored.observations.first { $0.account == account }
        let index = bucket(for: account, at: date, in: &stored)
        stored.days[index].observations += 1
        stored.days[index].accounts.insert(account.accountID)
        let tracked = Set(trackedAccounts.filter {
            $0.providerID == account.providerID && ($0.accountID == .primary) == (account.accountID == .primary)
        }).count
        stored.days[index].peakTrackedAccounts = max(stored.days[index].peakTrackedAccounts, tracked, 1)

        var knownLive = prior?.lastKnownLive ?? false
        switch outcome(snapshot) {
        case .live:
            stored.days[index].liveReadings += 1
            knownLive = true
        case .signedOut:
            if knownLive { stored.days[index].signOutTransitions += 1 }
            knownLive = false
        case .rejected:
            if knownLive { stored.days[index].rejectedAuthTransitions += 1 }
            knownLive = false
        case .inconclusive:
            break
        }

        // Only adjacent on-cadence samples contribute coverage. Sleep, app downtime,
        // clock reversal and a first observation cannot fabricate account-days.
        if let prior, expectedInterval.isFinite, expectedInterval > 0 {
            let gap = date.timeIntervalSince(prior.at)
            if gap > 0, gap <= 2 * expectedInterval {
                var cursor = prior.at
                while cursor < date {
                    let start = calendar.startOfDay(for: cursor)
                    let end = min(start.addingTimeInterval(86_400), date)
                    let coverageIndex = bucket(for: account, at: cursor, in: &stored)
                    stored.days[coverageIndex].sampledAccountSeconds += end.timeIntervalSince(cursor)
                    stored.days[coverageIndex].accounts.insert(account.accountID)
                    cursor = end
                }
            }
        }
        stored.observations.removeAll { $0.account == account }
        stored.observations.append(Observation(account: account, at: date, lastKnownLive: knownLive))
        save(stored)
    }

    /// Deliberate reset/removal must not become a spontaneous sign-out event, and
    /// reattaching the same local key must not bridge observation coverage.
    public func endObservation(for account: AccountKey) {
        var stored = load()
        stored.observations.removeAll { $0.account == account }
        save(stored)
    }

    public func diagnosticLines() -> [String] {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "Session reliability: sampled observations, not cause attribution",
            "UTC daily buckets; retained 14 days; gaps beyond twice the chosen interval excluded",
            "No comparable before/after coverage means improvement is unproven.",
        ]
        for day in days {
            lines.append([
                formatter.string(from: day.startedAt),
                "provider=\(day.provider.raw)", "account=\(day.builtIn ? "built-in" : "extra")",
                "observed_accounts=\(day.observedAccounts)", "peak_tracked_accounts=\(day.peakTrackedAccounts)",
                "observations=\(day.observations)",
                "live=\(day.liveReadings)", "sign_out_transitions=\(day.signOutTransitions)",
                "auth_rejection_transitions=\(day.rejectedAuthTransitions)",
                "sampled_account_seconds=\(Int(day.sampledAccountSeconds))",
            ].joined(separator: " "))
        }
        return lines
    }

    private func outcome(_ snapshot: UsageSnapshot) -> Outcome {
        switch snapshot.freshness {
        case .live: return .live
        case .stale(let reason):
            switch reason.providerSetupOutcome {
            case .claudeLoginRequired, .codexAuthAbsent, .grokAuthAbsent, .cursorAuthAbsent, .copilotSignedOut,
                 .opencodeSignedOut, .opencodeConsoleSignInRequired, .antigravitySignedOut:
                return .signedOut
            case .codexRejectedAuth, .codexSessionUnverified, .grokRejectedAuth, .opencodeSignInExpired:
                return .rejected
            default: return .inconclusive
            }
        default: return .inconclusive
        }
    }

    private func bucket(for account: AccountKey, at date: Date, in stored: inout Stored) -> Int {
        let start = calendar.startOfDay(for: date)
        let builtIn = account.accountID == .primary
        if let index = stored.days.firstIndex(where: {
            $0.startedAt == start && $0.provider == account.providerID && $0.builtIn == builtIn
        }) { return index }
        stored.days.append(Day(startedAt: start, provider: account.providerID, builtIn: builtIn))
        return stored.days.count - 1
    }

    private func pruned(_ stored: Stored, at date: Date) -> Stored {
        let start = calendar.startOfDay(for: date)
        let cutoff = start.addingTimeInterval(-Double(Self.retentionDays - 1) * 86_400)
        return Stored(
            days: stored.days.filter { !($0.startedAt < cutoff) && !($0.startedAt > start) },
            observations: stored.observations.filter { !($0.at < cutoff) && !($0.at > date) }
        )
    }

    private func load() -> Stored {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return Stored() }
        return stored
    }

    private func save(_ stored: Stored) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
