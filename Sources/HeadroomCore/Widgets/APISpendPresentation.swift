import Foundation

/// Why an API-spend row has no live amount, as typed evidence instead of a failure
/// string. Badge, message and call-to-action are all decided from this one value, so the
/// card can no longer say "Needs setup" next to "admin key rejected" — those two lines
/// were computed independently (badge from `isPermanent`, CTA from "amount is nil").
public enum APISpendAttention: String, Codable, Sendable, Equatable, CaseIterable {
    /// No key is stored yet.
    case missingKey
    /// A key is stored and the provider refused it (401).
    case keyRejected
    /// A key is stored and accepted, but it cannot read the cost surface (403).
    case keyLacksAccess
    /// Permanent, but none of the key conditions above — keep the source's own copy.
    case setupRequired
    /// Retryable; the next poll may clear it on its own.
    case retryable

    public init(reason: FailureReason) {
        switch reason {
        case .notLoggedIn: self = .missingKey
        case .needsReauth: self = .keyRejected
        case .scopeDenied: self = .keyLacksAccess
        case .transient, .decode: self = .retryable
        case .providerSetup(let outcome): self = outcome.isPermanent ? .setupRequired : .retryable
        }
    }
}

/// Everything a spend row renders for one state: badge, tone, sub-line and the action
/// title. Pure, so the macOS popover row and the companion/widget mirror read the same
/// decisions instead of each re-deriving copy from a `FailureReason` message.
public struct APISpendRowStatus: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        /// First run, before any fetch — quieter than a failure.
        case quiet
        /// Retryable staleness; informational, not actionable.
        case neutral
        case warning
        case critical
    }

    public let badge: String?
    public let tone: Tone
    public let message: String?
    /// Title for the button that opens Settings → API Spend; nil renders no button.
    public let callToAction: String?
    /// Companion/widget wording for the same action, which can only be taken on the Mac.
    public let remoteHint: String?

    public init(
        badge: String?,
        tone: Tone,
        message: String?,
        callToAction: String?,
        remoteHint: String?
    ) {
        self.badge = badge
        self.tone = tone
        self.message = message
        self.callToAction = callToAction
        self.remoteHint = remoteHint
    }
}

public enum APISpendPresentation {
    public static func amountText(amount: Double?, currency: String?) -> String? {
        guard let amount, let currency, !currency.isEmpty else { return nil }
        let code = currency.uppercased()
        if code == "USD" {
            return String(format: "$%.2f", amount)
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(code) \(String(format: "%.2f", amount))"
    }

    // MARK: - Row status

    /// The vendor inside a spend provider's display name ("Anthropic API" → "Anthropic"),
    /// so copy names the brand rather than the row title. Derived rather than kept in a
    /// per-provider copy table, so a new spend provider needs no new strings.
    public static func vendorName(from displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(" API") else { return trimmed }
        let vendor = String(trimmed.dropLast(4)).trimmingCharacters(in: .whitespaces)
        return vendor.isEmpty ? trimmed : vendor
    }

    /// macOS popover row: the full `Freshness` still carries the typed `FailureReason`.
    public static func rowStatus(freshness: Freshness, displayName: String) -> APISpendRowStatus {
        switch freshness {
        case .pending:
            pendingStatus
        case .live:
            liveStatus
        case .stale(let reason):
            attentionStatus(
                APISpendAttention(reason: reason),
                sourceMessage: reason.message,
                vendor: vendorName(from: displayName)
            )
        }
    }

    /// Companion/widget row: the wire format keeps only the message plus a permanence
    /// flag, so the typed attention rides alongside as an additive field. A payload from
    /// an older writer carries none and falls back to exactly the previous two-way split.
    public static func rowStatus(
        freshness: WidgetProviderFreshness,
        attention: APISpendAttention? = nil,
        displayName: String = ""
    ) -> APISpendRowStatus {
        switch freshness {
        case .pending:
            pendingStatus
        case .live:
            liveStatus
        case .stale(let message, let needsAttention):
            attentionStatus(
                attention ?? (needsAttention ? .setupRequired : .retryable),
                sourceMessage: message,
                vendor: vendorName(from: displayName)
            )
        }
    }

    private static let pendingStatus = APISpendRowStatus(
        badge: nil,
        tone: .quiet,
        message: "Waiting for cost data",
        callToAction: "Add key…",
        remoteHint: nil
    )

    private static let liveStatus = APISpendRowStatus(
        badge: nil,
        tone: .neutral,
        message: nil,
        callToAction: nil,
        remoteHint: nil
    )

    private static func attentionStatus(
        _ attention: APISpendAttention,
        sourceMessage: String,
        vendor: String
    ) -> APISpendRowStatus {
        switch attention {
        case .missingKey:
            APISpendRowStatus(
                badge: "Needs setup",
                tone: .warning,
                message: "Add an admin key to see \(vendor) spend",
                callToAction: "Add key…",
                remoteHint: "Set up on Mac"
            )
        case .keyRejected:
            APISpendRowStatus(
                badge: "Key rejected",
                tone: .critical,
                message: "\(vendor) didn't accept the saved admin key",
                callToAction: "Replace key…",
                remoteHint: "Replace key on Mac"
            )
        case .keyLacksAccess:
            APISpendRowStatus(
                badge: "Key lacks access",
                tone: .warning,
                message: "Key can't read the cost report",
                callToAction: "Fix key…",
                remoteHint: "Fix key on Mac"
            )
        case .setupRequired:
            APISpendRowStatus(
                badge: "Needs setup",
                tone: .warning,
                message: sourceMessage,
                callToAction: "Add key…",
                remoteHint: "Set up on Mac"
            )
        case .retryable:
            APISpendRowStatus(
                badge: "Stale",
                tone: .neutral,
                message: sourceMessage,
                callToAction: "Add key…",
                remoteHint: nil
            )
        }
    }

    public static func statusText(
        freshness: WidgetProviderFreshness,
        attention: APISpendAttention? = nil,
        capturedAt: Date?,
        now: Date
    ) -> String? {
        switch freshness {
        case .pending:
            "Waiting for cost data"
        case .live:
            Countdown.updatedLabel(capturedAt: capturedAt, now: now).map { "Updated \($0)" }
        case .stale:
            rowStatus(freshness: freshness, attention: attention).remoteHint
                ?? (Countdown.updatedLabel(capturedAt: capturedAt, now: now).map { "Updated \($0)" } ?? "Not updated")
        }
    }

    /// Companion rows follow the current macOS popover: the screen header owns the live
    /// freshness stamp, while only pending/stale rows carry a secondary status line.
    public static func companionStatusText(
        freshness: WidgetProviderFreshness,
        attention: APISpendAttention? = nil
    ) -> String? {
        switch freshness {
        case .pending:
            "Waiting for cost data"
        case .live:
            nil
        case .stale:
            rowStatus(freshness: freshness, attention: attention).badge
        }
    }

    public static func amountText(_ summary: WidgetAPISpendSummary) -> String? {
        guard let amount = amountText(amount: summary.amount, currency: summary.currency) else { return nil }
        return summary.semanticKind == .balance ? "\(amount) left" : amount
    }

    public static func contextLabel(kind: APISpendKind, periodLabel: String) -> String {
        kind == .balance ? "Remaining balance" : periodLabel
    }

    public static func qualifier(kind: APISpendKind) -> String? {
        kind == .balance ? "remaining" : nil
    }

    /// The exact page where a user tops up prepaid API credits — the billing screen that
    /// hosts Anthropic's "Buy credits" / OpenAI's "Add to credit balance" control, not a
    /// docs or marketing page. Anthropic's console moved to platform.claude.com (late
    /// 2025), so we link there directly instead of riding the console.anthropic.com
    /// redirect. Kept in Core so the mapping is unit-tested.
    public static func addCreditsURL(for providerID: ProviderID) -> URL? {
        switch providerID {
        case .claude:
            URL(string: "https://platform.claude.com/settings/billing")
        case .codex:
            URL(string: "https://platform.openai.com/settings/organization/billing/overview")
        case .grok:
            URL(string: "https://console.x.ai")
        default:
            nil
        }
    }
}
