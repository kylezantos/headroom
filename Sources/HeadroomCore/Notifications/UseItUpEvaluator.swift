import Foundation

/// The notification preferences one evaluation reads, captured as a value so the
/// evaluator stays pure.
public struct UseItUpSettings: Sendable, Equatable {
    public var isEnabled: Bool
    public var rules: [ReminderRule]
    public var scope: Set<ReminderScope>
    /// KTD3: mirrors `UsageStore.showCodexSparkCountersInApp`, so a reminder never names
    /// a row the popover hides.
    public var showCodexSparkCounters: Bool
    /// Mirrors `UsageStore.showsAntigravityFiveHourWindows` the same way.
    public var showsAntigravityFiveHourWindows: Bool

    public init(
        isEnabled: Bool, rules: [ReminderRule], scope: Set<ReminderScope>, showCodexSparkCounters: Bool,
        showsAntigravityFiveHourWindows: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.rules = rules
        self.scope = scope
        self.showCodexSparkCounters = showCodexSparkCounters
        self.showsAntigravityFiveHourWindows = showsAntigravityFiveHourWindows
    }
}

/// One banner's worth of due rules for one limit (R12). `ledgerEntry` is what to record
/// once the post succeeds; nothing is written before then (KTD6).
public struct UseItUpProposal: Sendable, Equatable {
    public let account: AccountKey
    public let kind: WindowKind
    public let deadline: Date
    /// Percent left with the popover's rounding (R13).
    public let percentLeft: Int
    public let dueRules: [ReminderRule]
    public let ledgerEntry: UseItUpLedgerEntry

    public var windowID: String { kind.persistentID }
}

/// Decides which limits in a fresh snapshot are due a use-it-up reminder (R10–R12).
/// Pure: the ledger arrives as entries and updates leave as proposals.
public enum UseItUpEvaluator {
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * 60 * 60

    public static func evaluate(
        snapshot: UsageSnapshot,
        account: AccountKey,
        settings: UseItUpSettings,
        ledger: [UseItUpLedgerEntry],
        now: Date
    ) -> [UseItUpProposal] {
        // KTD2: a failed poll's retained windows and a launch restore never fire.
        guard settings.isEnabled, !settings.rules.isEmpty, snapshot.freshness == .live else { return [] }

        let windows = AntigravityFiveHourWindows.visibleWindows(
            snapshot.windows, providerID: snapshot.providerID,
            showsFiveHourWindows: settings.showsAntigravityFiveHourWindows)
        return windows.compactMap { window in
            // AE4: a live snapshot can still carry a retained stale model row.
            guard window.freshness.isLive,
                  let deadline = window.resetSchedule.deadline,
                  let scope = scope(for: window.kind, providerID: snapshot.providerID),
                  settings.scope.contains(scope)
            else { return nil }
            if snapshot.providerID == .codex, window.kind.isCodexSparkCounter, !settings.showCodexSparkCounters {
                return nil
            }

            let timeLeft = deadline.timeIntervalSince(now)
            guard timeLeft > 0 else { return nil }
            let percentLeft = Int(window.percentRemaining.rounded())
            let limitLength = length(of: window.kind)

            let windowID = window.kind.persistentID
            let stored = ledger.first { $0.account == account && $0.windowID == windowID }
            let spent: [String] = stored.flatMap { $0.isSameCycle(as: deadline) ? $0.firedKeys : nil } ?? []

            let due = settings.rules.filter { rule in
                !spent.contains(rule.firingKey)
                    && (limitLength.map { $0 > rule.leadInterval } ?? true)
                    && timeLeft <= rule.leadInterval
                    && percentLeft >= rule.threshold
            }
            guard !due.isEmpty else { return nil }

            return UseItUpProposal(
                account: account,
                kind: window.kind,
                deadline: deadline,
                percentLeft: percentLeft,
                dueRules: due,
                ledgerEntry: UseItUpLedgerEntry(
                    account: account,
                    windowID: windowID,
                    deadline: deadline,
                    firedKeys: spent + due.map(\.firingKey)
                )
            )
        }
    }

    /// KTD3: which Applies-to family a limit belongs to, or nil when it is excluded.
    /// Model rows classify from their labels; `Nd` and "Billing period" labels count as
    /// billing periods only from Grok or Cursor, because Codex emits `Nd` for rolling
    /// windows. Anything unrecognized is excluded rather than guessed.
    public static func scope(for kind: WindowKind, providerID: ProviderID) -> ReminderScope? {
        switch kind {
        case .fiveHour: return .fiveHour
        case .weekly: return .weekly
        case .billingPeriod: return .billingPeriod
        case .other(let label):
            if isWeeklyModelRow(label) { return .weekly }
            if isFiveHourModelRow(label) { return .fiveHour }
            if providerID == .grok || providerID == .cursor,
               label == "Billing period" || dayCount(in: label) != nil {
                return .billingPeriod
            }
            return nil
        }
    }

    /// KTD3: a limit's full length, used to ignore rules whose lead is not shorter than
    /// the limit itself. Nil when unknown, which skips that check.
    public static func length(of kind: WindowKind) -> TimeInterval? {
        switch kind {
        case .fiveHour: return 5 * hour
        case .weekly: return 7 * day
        case .billingPeriod(_, let duration):
            return duration.isFinite && duration > 0 ? duration : nil
        case .other(let label):
            if isWeeklyModelRow(label) { return 7 * day }
            if isFiveHourModelRow(label) { return 5 * hour }
            return dayCount(in: label).map { TimeInterval($0) * day }
        }
    }

    /// The limit as a banner names it: the popover's spoken name, prefixed with the
    /// provider unless the label already carries it ("Cursor Models").
    public static func limitName(for kind: WindowKind, providerName: String) -> String {
        let name = kind.spokenName
        if name.lowercased().hasPrefix(providerName.lowercased()) { return name }
        return "\(providerName) \(name)"
    }

    private static func isWeeklyModelRow(_ label: String) -> Bool {
        WindowKind.weeklyModelName(in: label) != nil
            || (label.count > " weekly".count && label.lowercased().hasSuffix(" weekly"))
    }

    private static func isFiveHourModelRow(_ label: String) -> Bool {
        label.count > " 5h".count && label.lowercased().hasSuffix(" 5h")
    }

    /// "30d" → 30, the label `BillingPeriodWindowClassifier` gives an unrecognized period.
    private static func dayCount(in label: String) -> Int? {
        guard label.count > 1, label.hasSuffix("d"), let days = Int(label.dropLast()), days > 0 else { return nil }
        return days
    }
}
