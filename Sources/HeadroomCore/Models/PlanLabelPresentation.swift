import Foundation

/// Display names for the raw plan identifiers providers report.
///
/// `planLabel` stays deliberately lenient at the source — Codex passes `plan_type`
/// through verbatim so a new tier never breaks decoding (#709), Grok reports
/// `subscriptionTier`, Cursor the plan text off its `/usage` header — so ids arrive in
/// whatever shape the provider used (`prolite`, `SuperGrok`, `Pro+`, `Max 20x`).
/// `.capitalized` is wrong in both directions: it renders `prolite` as one word and
/// flattens `SuperGrok` to "Supergrok". Every surface that shows a plan routes its text
/// through here instead, so the lenient model keeps its raw value and only the badge is
/// humanized. Invariant: the result never contains `_`, so a raw id such as
/// `self_serve_business_prolite` can never reach a pill.
public enum PlanLabelPresentation {
    /// Keyed by normalized id (lowercased, separators dropped) so `prolite`,
    /// `pro_lite` and `PRO-LITE` all resolve to the same display name.
    private static let displayNames: [String: String] = [
        "free": "Free",
        "plus": "Plus",
        "pro": "Pro",
        "prolite": "Pro Lite",
        "max": "Max",
        "team": "Team",
        "enterprise": "Enterprise",
        "supergrok": "SuperGrok",
        "supergrokheavy": "SuperGrok Heavy",
    ]

    /// Every Codex `plan_type` OpenAI's own client knows (codex-rs `PlanType`, read
    /// 2026-10-18), checked before the generic table. Normalized keys, like `displayNames`.
    private static let codexDisplayNames: [String: String] = [
        "free": "Free",
        "freeworkspace": "Free",
        "go": "Go",
        "plus": "Plus",
        // DECISION D1: keep Headroom's Pro / Pro Lite / Pro Max rather than the Codex TUI's
        // "Pro 200 / Pro 100 / Pro 500".
        "pro": "Pro",
        "prolite": "Pro Lite",
        "promax": "Pro Max",
        // DECISION D2: OpenAI renamed ChatGPT Team to Business, so Codex `team` and
        // `business` both read "Business". Codex only: Claude's Team plan stays "Team".
        "team": "Business",
        "business": "Business",
        // DECISION D3: the self-serve Business tiers read "Business", unprefixed like every
        // other pill (users reported the raw `Self_serve_business_prolite`).
        "selfservebusinessprolite": "Business",
        "selfservebusinessusagebased": "Business",
        "enterprise": "Enterprise",
        "hc": "Enterprise",
        "ent26": "Enterprise",
        "enterprisecbpusagebased": "Enterprise",
        "enterprisecbpautomation": "Enterprise",
        "edu": "Edu",
        "education": "Edu",
        "eduplus": "Edu Plus",
        "edupro": "Edu Pro",
        "guest": "Guest",
        "k12": "K-12",
    ]

    /// Codex ids with no plan worth naming: the badge collapses instead.
    private static let codexHidden: Set<String> = ["unknown", "quorum"]

    /// Id fragments that describe billing mechanics, not the plan, so the identifier rule
    /// drops them (`self_serve_business_x` → "Business X").
    private static let noiseTokens: Set<String> = ["self", "serve", "usage", "based", "cbp", "plan", "tier"]

    private static let tokenNames: [String: String] = [
        "prolite": "Pro Lite",
        "promax": "Pro Max",
        "edu": "Edu",
        "k12": "K-12",
        "supergrok": "SuperGrok",
    ]

    /// Nil for a missing or blank label so callers keep collapsing the badge entirely.
    /// `provider` adds that provider's own id table (Codex); nil keeps the generic path.
    public static func displayName(_ raw: String?, provider: ProviderID? = nil) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = normalizedKey(trimmed)
        if provider == .codex {
            if codexHidden.contains(key) { return nil }
            if let known = codexDisplayNames[key] { return known }
        }
        if let known = displayNames[key] { return known }
        if isIdentifier(trimmed) { return humanizedIdentifier(trimmed) }
        return fallback(trimmed)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
    }

    /// An id rather than display text: snake_case, or one token in a single case
    /// (`business`, `ULTRA`). Mixed-case or spaced text without `_` is the provider's own.
    private static func isIdentifier(_ value: String) -> Bool {
        if value.contains("_") { return true }
        guard !value.contains(where: \.isWhitespace) else { return false }
        return !value.contains(where: \.isUppercase) || !value.contains(where: \.isLowercase)
    }

    /// Unknown ids stay lenient (#709) but read as words: split on separators, drop the
    /// billing noise, title-case the rest. Nil when only noise remains.
    private static func humanizedIdentifier(_ value: String) -> String? {
        let words = value
            .split(whereSeparator: { $0 == "_" || $0 == "-" || $0.isWhitespace })
            .map(String.init)
            .filter { !noiseTokens.contains($0.lowercased()) }
            .map { token -> String in
                if let named = tokenNames[token.lowercased()] { return named }
                guard let first = token.first else { return token }
                // An all-caps token is shouted, not cased: `PREMIUM` → "Premium".
                let rest = token.dropFirst()
                return first.uppercased() + (token == token.uppercased() ? rest.lowercased() : String(rest))
            }
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    /// Display text without `_`. A value that already carries an uppercase letter is the
    /// provider's own display text (`Max 20x`, `Pro+`) and is left untouched — title-casing
    /// it would corrupt the very casing the provider chose. Lowercase words (`ultra pro`)
    /// only get each first letter raised, never their remainder lowercased.
    private static func fallback(_ value: String) -> String {
        guard !value.contains(where: \.isUppercase) else { return value }
        return value
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
