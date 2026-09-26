import Foundation

/// A notification request, free of UserNotifications types so Core can build and test
/// it (KTD1). Payloads carry display names only (KTD12).
public struct NotificationContent: Sendable, Equatable {
    /// KTD12: deterministic, so a repost replaces its banner instead of stacking.
    public let identifier: String
    /// KTD12: `<provider>.<account>`, so Notification Center groups per account.
    public let threadIdentifier: String
    public let title: String
    public let body: String

    public init(identifier: String, threadIdentifier: String, title: String, body: String) {
        self.identifier = identifier
        self.threadIdentifier = threadIdentifier
        self.title = title
        self.body = body
    }

    public static func threadIdentifier(for account: AccountKey) -> String {
        "\(account.providerID.raw).\(account.accountID.raw)"
    }

    /// R13: "{N}% of {limit} is still unused" / "Resets in {time left}, {clock}."
    /// `accountLabel` is nil unless the provider shows more than one account; the caller
    /// decides, because only the store knows the visible account count.
    public static func useItUp(
        _ proposal: UseItUpProposal,
        providerName: String,
        accountLabel: String?,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> NotificationContent {
        let limit = UseItUpEvaluator.limitName(for: proposal.kind, providerName: providerName)
        let subject = accountLabel.map { "\(limit) (\($0))" } ?? limit
        let clock = ResetClockFormatter.phrase(
            for: proposal.deadline,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar
        )
        let account = proposal.account
        let epochMinutes = Int(proposal.deadline.timeIntervalSince1970 / 60)
        return NotificationContent(
            identifier: "use-it-up.\(account.providerID.raw).\(account.accountID.raw).\(proposal.windowID).\(epochMinutes)",
            threadIdentifier: threadIdentifier(for: account),
            title: "\(proposal.percentLeft)% of \(subject) is still unused",
            body: "Resets in \(Countdown.string(to: proposal.deadline, now: now)), \(clock)."
        )
    }

    /// R16: "Codex banked a reset" / "{Account} now has N banked resets." With one Codex
    /// account (`accountLabel` nil) the body reads "You now have N banked resets."
    public static func bankedReset(_ proposal: BankedResetProposal, accountLabel: String?) -> NotificationContent {
        let noun = proposal.count == 1 ? "banked reset" : "banked resets"
        let body = accountLabel.map { "\($0) now has \(proposal.count) \(noun)." }
            ?? "You now have \(proposal.count) \(noun)."
        return NotificationContent(
            identifier: "codex-banked.\(proposal.account.accountID.raw).\(proposal.count)",
            threadIdentifier: threadIdentifier(for: proposal.account),
            title: "Codex banked a reset",
            body: body
        )
    }
}
