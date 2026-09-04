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
/// humanized.
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

    /// Nil for a missing or blank label so callers keep collapsing the badge entirely.
    public static func displayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let known = displayNames[normalizedKey(trimmed)] { return known }
        return fallback(trimmed)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
    }

    /// Unknown ids stay lenient (#709). A value that already carries an uppercase letter
    /// is the provider's own display text (`Max 20x`, `Pro+`) and is left untouched —
    /// title-casing it would corrupt the very casing the provider chose. An all-lowercase
    /// id only gets each word's first letter raised, never its remainder lowercased.
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
