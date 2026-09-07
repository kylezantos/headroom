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

    /// The key itself is what's wrong — there is nothing to wait for, only a key to add,
    /// replace or re-scope. Rows in these states must offer that action even when they
    /// still show a retained amount (`setupRequired` is deliberately excluded: its copy
    /// comes from the source and may not be about a key at all).
    public var isKeyProblem: Bool {
        switch self {
        case .missingKey, .keyRejected, .keyLacksAccess: true
        case .setupRequired, .retryable: false
        }
    }
}

/// The credential a spend provider actually needs, in the same words the Settings → API
/// Spend pane puts on its field ("Anthropic admin key", "xAI management key"), so the two
/// surfaces can't disagree about what the user is being asked to paste. The article is
/// declared per credential rather than assembled at the call site: copy that picks "a"/"an"
/// from a vendor name produces "a xAI", and only the provider knows whether it wants an
/// admin key or a management key.
public struct APISpendCredentialDescriptor: Sendable, Equatable {
    /// The indefinite article that belongs to `noun`.
    public let article: String
    /// Bare noun for mid-sentence use — "admin key".
    public let noun: String
    /// What that credential has to be able to read, article included — "the cost report".
    /// Each vendor exposes a different surface, so the access failure names the real one.
    public let reportNoun: String

    public init(article: String, noun: String, reportNoun: String) {
        self.article = article
        self.noun = noun
        self.reportNoun = reportNoun
    }

    /// The noun carrying its own article — "an admin key", "a management key".
    public var credentialNoun: String { "\(article) \(noun)" }

    /// `/v1/organizations/cost_report` refuses a regular key; the pane's field is
    /// "Anthropic admin key".
    public static let anthropicAdminKey = APISpendCredentialDescriptor(
        article: "an",
        noun: "admin key",
        reportNoun: "the cost report"
    )

    /// `/v1/organization/costs` refuses a regular key; the pane's field is
    /// "OpenAI admin key".
    public static let openAIAdminKey = APISpendCredentialDescriptor(
        article: "an",
        noun: "admin key",
        reportNoun: "organization costs"
    )

    /// The management API reads team billing and takes a management key, not an admin
    /// key — the pane's field is "xAI management key".
    public static let xAIManagementKey = APISpendCredentialDescriptor(
        article: "a",
        noun: "management key",
        reportNoun: "team billing"
    )

    /// A spend provider that hasn't declared its credential. Vendor-free wording, so a new
    /// provider reads plainly instead of inheriting Anthropic's nouns.
    public static let generic = APISpendCredentialDescriptor(
        article: "an",
        noun: "API key",
        reportNoun: "cost data"
    )

    /// Resolves the credential for surfaces that only carry a `ProviderID` (the widget and
    /// companion payloads never ship a provider instance). Providers declare the same
    /// constants, and `APISpendProviderTests` holds the two in sync.
    public static func forProvider(_ providerID: ProviderID?) -> APISpendCredentialDescriptor {
        switch providerID {
        case .claude: anthropicAdminKey
        case .codex: openAIAdminKey
        case .grok: xAIManagementKey
        default: generic
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
    /// X5 (Kyle): the same state, short enough to stand on the identity line where the
    /// period chip stands. The macOS popover puts the tag beside the title — a billing
    /// period is meaningless once the figure is stale or absent — and the measured 320pt
    /// line cannot hold "Needs setup" or "Key lacks access". Every other surface (widgets,
    /// phone mirror, VoiceOver) keeps the full `badge`.
    public let shortBadge: String?
    public let tone: Tone
    public let message: String?
    /// Title for the button that opens Settings → API Spend; nil renders no button.
    /// B3T: Title Case — it is a button, unlike `remoteHint` below.
    public let callToAction: String?
    /// Companion/widget wording for the same action, which can only be taken on the Mac.
    /// B3T deliberately leaves this in sentence case: it is a hint *line*, not a control.
    public let remoteHint: String?
    /// The stored (or absent) key is itself the problem — see `APISpendAttention.isKeyProblem`.
    public let keyNeedsAttention: Bool

    public init(
        badge: String?,
        shortBadge: String? = nil,
        tone: Tone,
        message: String?,
        callToAction: String?,
        remoteHint: String?,
        keyNeedsAttention: Bool = false
    ) {
        self.badge = badge
        self.shortBadge = shortBadge
        self.tone = tone
        self.message = message
        self.callToAction = callToAction
        self.remoteHint = remoteHint
        self.keyNeedsAttention = keyNeedsAttention
    }

    /// Whether the row renders its button. A row with an amount normally stays a plain
    /// number, but continuity keeps showing the last total after the key stops working —
    /// and a retained amount beside a "Key rejected" badge with no button is a dead end.
    /// Retryable staleness keeps the old rule: the next poll may clear it on its own.
    public func showsCTA(hasAmount: Bool) -> Bool {
        guard callToAction != nil else { return false }
        return keyNeedsAttention || !hasAmount
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
    public static func rowStatus(
        freshness: Freshness,
        providerID: ProviderID? = nil,
        displayName: String
    ) -> APISpendRowStatus {
        switch freshness {
        case .pending:
            pendingStatus
        case .live:
            liveStatus
        case .stale(let reason):
            attentionStatus(
                APISpendAttention(reason: reason),
                sourceMessage: reason.message,
                vendor: vendorName(from: displayName),
                credential: .forProvider(providerID)
            )
        }
    }

    /// Companion/widget row: the wire format keeps only the message plus a permanence
    /// flag, so the typed attention rides alongside as an additive field. A payload from
    /// an older writer carries none and falls back to exactly the previous two-way split.
    public static func rowStatus(
        freshness: WidgetProviderFreshness,
        attention: APISpendAttention? = nil,
        providerID: ProviderID? = nil,
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
                vendor: vendorName(from: displayName),
                credential: .forProvider(providerID)
            )
        }
    }

    private static let pendingStatus = APISpendRowStatus(
        badge: nil,
        tone: .quiet,
        message: "Waiting for cost data",
        callToAction: "Add Key",
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
        vendor: String,
        credential: APISpendCredentialDescriptor
    ) -> APISpendRowStatus {
        switch attention {
        case .missingKey:
            APISpendRowStatus(
                badge: "Needs setup",
                shortBadge: "Setup",
                tone: .warning,
                message: "Add \(credential.credentialNoun) to see \(vendor) spend",
                callToAction: "Add Key",
                remoteHint: "Set up on Mac",
                keyNeedsAttention: true
            )
        case .keyRejected:
            APISpendRowStatus(
                badge: "Key rejected",
                shortBadge: "Rejected",
                tone: .critical,
                message: "\(vendor) didn't accept the saved \(credential.noun)",
                callToAction: "Replace Key",
                remoteHint: "Replace key on Mac",
                keyNeedsAttention: true
            )
        case .keyLacksAccess:
            APISpendRowStatus(
                badge: "Key lacks access",
                shortBadge: "Denied",
                tone: .warning,
                message: "Key can't read \(credential.reportNoun)",
                callToAction: "Fix Key",
                remoteHint: "Fix key on Mac",
                keyNeedsAttention: true
            )
        case .setupRequired:
            APISpendRowStatus(
                badge: "Needs setup",
                shortBadge: "Setup",
                tone: .warning,
                message: sourceMessage,
                callToAction: "Add Key",
                remoteHint: "Set up on Mac"
            )
        case .retryable:
            APISpendRowStatus(
                badge: "Stale",
                shortBadge: "Stale",
                tone: .neutral,
                message: sourceMessage,
                callToAction: "Add Key",
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

    /// The macOS popover's own name/chip split for a spend row's identity line. Core's
    /// `displayName` is the wire name ("Cursor on-demand"), and X5 measured it clipping the
    /// 320pt identity line by 35pt — so the popover renders the vendor as the title and
    /// moves the trailing qualifier into the chip slot the period would occupy. The rule is
    /// derived rather than a per-provider table: a final word that starts lowercase is a
    /// qualifier ("on-demand"), while an initialism stays part of the name ("Anthropic API",
    /// "xAI API"). `displayName` itself is untouched, so widgets and the phone mirror keep
    /// the full string.
    public struct PopoverIdentity: Sendable, Equatable {
        public let title: String
        /// Replaces the period chip's label, or nil when the name carried no qualifier.
        public let chipOverride: String?
    }

    public static func popoverIdentity(displayName: String) -> PopoverIdentity {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.lastIndex(of: " ") else {
            return PopoverIdentity(title: trimmed, chipOverride: nil)
        }
        let qualifier = String(trimmed[trimmed.index(after: separator)...])
        let title = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
        guard let first = qualifier.first, first.isLowercase, !title.isEmpty else {
            return PopoverIdentity(title: trimmed, chipOverride: nil)
        }
        return PopoverIdentity(
            title: title,
            chipOverride: first.uppercased() + String(qualifier.dropFirst())
        )
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
