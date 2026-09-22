import Foundation

// Decoders are lenient (KTD6): unknown keys are ignored by `Decodable`, unknown
// enum-ish values pass through as strings, and one unrecognized field never blanks
// the whole snapshot. Exact field names must be verified against a live Codex
// `wham/usage` capture.

// MARK: - Codex (chatgpt.com/backend-api/wham/usage)

struct CodexUsageDTO: Decodable {
    let rate_limit: CodexRateLimitDTO?
    let plan_type: String?
    let additional_rate_limits: [CodexNamedWindowDTO]?
    /// Key-absent, JSON `null`, a usable count, or a present-but-unusable value.
    /// A hand-written init keeps a bad credits shape from failing the body (KTD3)
    /// while still telling `null` from a missing key (R2).
    let resetCreditsField: CodexResetCreditsField

    enum CodingKeys: String, CodingKey {
        case rate_limit, plan_type, additional_rate_limits, rate_limit_reset_credits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rate_limit = try c.decodeIfPresent(CodexRateLimitDTO.self, forKey: .rate_limit)
        plan_type = try c.decodeIfPresent(String.self, forKey: .plan_type)
        additional_rate_limits = try c.decodeIfPresent([CodexNamedWindowDTO].self, forKey: .additional_rate_limits)
        resetCreditsField = Self.readResetCredits(c)
    }

    private static func readResetCredits(_ c: KeyedDecodingContainer<CodingKeys>) -> CodexResetCreditsField {
        let key = CodingKeys.rate_limit_reset_credits
        guard c.contains(key) else { return .absent }
        if (try? c.decodeNil(forKey: key)) == true { return .nullObject }
        guard let dto = try? c.decode(CodexResetCreditsDTO.self, forKey: key),
              let count = dto.reportedCount else { return .notReported }
        return .count(count)
    }
}

struct CodexResetCreditsDTO: Decodable {
    let availableCount: Double?

    enum CodingKeys: String, CodingKey { case available_count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        availableCount = c.flexibleDouble(.available_count)
    }

    /// Non-negative integral counts only. Fractional, negative, and overflowing
    /// values are not reported (R2).
    var reportedCount: Int? {
        guard let availableCount, availableCount >= 0,
              let count = Int(exactly: availableCount) else { return nil }
        return count
    }
}

struct CodexRateLimitDTO: Decodable {
    let primary_window: CodexWindowDTO?
    let secondary_window: CodexWindowDTO?
}

struct CodexWindowDTO: Decodable {
    // Accept several plausible field names for percent-used; whichever is present wins.
    let used_percent: Double?
    let usage_percent: Double?
    let utilization: Double?
    let reset_at: String?
    let resetAtEpoch: Double?
    let resets_at: String?
    let reset_after_seconds: Double?
    let resets_in_seconds: Double?
    // Codex tags each window with its true duration; this — not the primary/secondary slot —
    // is what identifies a window as 5-hour vs weekly (#codex-window-kind).
    let limit_window_seconds: Double?

    var utilizationValue: Double? { used_percent ?? usage_percent ?? utilization }
    var resetAtValue: String? { resets_at ?? reset_at }
    var resetEpochValue: Double? { resetAtEpoch }
    var resetSecondsValue: Double? { resets_in_seconds ?? reset_after_seconds }
    var windowSecondsValue: Double? { limit_window_seconds }

    enum CodingKeys: String, CodingKey {
        case used_percent, usage_percent, utilization
        case reset_at, resets_at, reset_after_seconds, resets_in_seconds
        case limit_window_seconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        used_percent = c.flexibleDouble(.used_percent)
        usage_percent = c.flexibleDouble(.usage_percent)
        utilization = c.flexibleDouble(.utilization)
        resets_at = c.flexibleString(.resets_at)
        reset_at = c.flexibleString(.reset_at)
        resetAtEpoch = c.flexibleDouble(.reset_at)
        reset_after_seconds = c.flexibleDouble(.reset_after_seconds)
        resets_in_seconds = c.flexibleDouble(.resets_in_seconds)
        limit_window_seconds = c.flexibleDouble(.limit_window_seconds)
    }
}

struct CodexNamedWindowDTO: Decodable {
    let name: String?
    let label: String?
    let limit_name: String?
    let metered_feature: String?
    let used_percent: Double?
    let usage_percent: Double?
    let utilization: Double?
    let reset_at: String?
    let resetAtEpoch: Double?
    let resets_at: String?
    let reset_after_seconds: Double?
    let resets_in_seconds: Double?
    let limit_window_seconds: Double?
    let rate_limit: CodexRateLimitDTO?

    var displayLabel: String { name ?? label ?? limit_name ?? metered_feature ?? "other" }
    var utilizationValue: Double? { used_percent ?? usage_percent ?? utilization }
    var resetAtValue: String? { resets_at ?? reset_at }
    var resetEpochValue: Double? { resetAtEpoch }
    var resetSecondsValue: Double? { resets_in_seconds ?? reset_after_seconds }
    var windowSecondsValue: Double? { limit_window_seconds }

    enum CodingKeys: String, CodingKey {
        case name, label, limit_name, metered_feature
        case used_percent, usage_percent, utilization
        case reset_at, resets_at, reset_after_seconds, resets_in_seconds
        case limit_window_seconds
        case rate_limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexibleString(.name)
        label = c.flexibleString(.label)
        limit_name = c.flexibleString(.limit_name)
        metered_feature = c.flexibleString(.metered_feature)
        used_percent = c.flexibleDouble(.used_percent)
        usage_percent = c.flexibleDouble(.usage_percent)
        utilization = c.flexibleDouble(.utilization)
        resets_at = c.flexibleString(.resets_at)
        reset_at = c.flexibleString(.reset_at)
        resetAtEpoch = c.flexibleDouble(.reset_at)
        reset_after_seconds = c.flexibleDouble(.reset_after_seconds)
        resets_in_seconds = c.flexibleDouble(.resets_in_seconds)
        limit_window_seconds = c.flexibleDouble(.limit_window_seconds)
        rate_limit = try? c.decode(CodexRateLimitDTO.self, forKey: .rate_limit)
    }
}

// MARK: - API spend reports

struct OpenAICostsDTO: Decodable {
    let data: [CostBucketDTO]
}

struct AnthropicCostReportDTO: Decodable {
    let data: [AnthropicCostBucketDTO]
    let hasMore: Bool
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct AnthropicCostBucketDTO: Decodable {
    let results: [CostResultDTO]
}

struct CostBucketDTO: Decodable {
    let results: [CostResultDTO]

    enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decode([CostResultDTO].self, forKey: .results)) ?? []
    }
}

struct CostResultDTO: Decodable {
    let amount: FlexibleAmountDTO?
    let currency: String?

    init(amount: FlexibleAmountDTO?, currency: String?) {
        self.amount = amount
        self.currency = currency
    }

    enum CodingKeys: String, CodingKey {
        case amount, cost, currency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = (try? c.decode(FlexibleAmountDTO.self, forKey: .amount))
              ?? (try? c.decode(FlexibleAmountDTO.self, forKey: .cost))
        currency = c.flexibleString(.currency)
    }
}

struct FlexibleAmountDTO: Decodable {
    let value: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey { case value, amount, total, currency }

    init(value: Double?, currency: String?) {
        self.value = value
        self.currency = currency
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(Double.self) {
            self.value = value
            self.currency = nil
            return
        }
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self.value = Double(value)
            self.currency = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = c.flexibleDouble(.value) ?? c.flexibleDouble(.amount) ?? c.flexibleDouble(.total)
        currency = c.flexibleString(.currency)
    }
}

enum CostAccumulator {
    static func total(from results: [CostResultDTO], emptyIsZero: Bool = false) -> (amount: Double, currency: String)? {
        if results.isEmpty, emptyIsZero { return (0, "usd") }
        var total = 0.0
        var currency: String?
        var sawAmount = false
        for result in results {
            guard let value = result.amount?.value else { continue }
            let resultCurrency = result.amount?.currency ?? result.currency ?? "usd"
            if let currency, currency != resultCurrency { return nil }
            currency = resultCurrency
            total += value
            sawAmount = true
        }
        guard sawAmount else { return nil }
        return (total, currency ?? "usd")
    }
}

// MARK: - Shared window construction

/// Builds a `UsageWindow` from decoded parts, tolerating either an ISO reset time or
/// a relative `resets_in_seconds`. Shared by both providers so window assembly and the
/// generic HTTP-status failure mapping live in one place.
enum UsageWindowBuilder {
    static func make(
        _ kind: WindowKind,
        utilization: Double?,
        resetsAt: String?,
        resetEpochSeconds: Double? = nil,
        resetsInSeconds: Double?,
        now: () -> Date
    ) -> UsageWindow? {
        guard let utilization else { return nil }
        let reset: Date
        if let d = DateParsing.iso8601(resetsAt) {
            reset = d
        } else if let epoch = resetEpochSeconds {
            reset = Date(timeIntervalSince1970: epoch)
        } else if let seconds = resetsInSeconds {
            reset = now().addingTimeInterval(seconds)
        } else {
            return nil
        }
        return UsageWindow(kind: kind, utilization: utilization, resetsAt: reset)
    }

    /// Failure reason for HTTP statuses both providers handle identically.
    static func genericFailure(for status: Int) -> FailureReason {
        status == 429 ? .transient("Rate limited — will retry")
                      : .transient("Service error (\(status))")
    }
}

/// Classifies a Codex usage window by its true duration rather than by which slot
/// (`primary_window`/`secondary_window`) it arrived in.
///
/// #codex-window-kind — slot position is NOT reliable: the "prolite" plan returns its
/// weekly window in `primary_window` with `secondary_window: null`, so the old
/// primary→5-hour / secondary→weekly assumption mislabeled the weekly window as 5-hour
/// (and dropped the weekly row entirely). Codex tags each window with `limit_window_seconds`
/// (18000 = 5h, 604800 = 7d); we key off those verified values exactly and fall back to
/// `positionalDefault` only when the duration is absent (older/other response variants and
/// pre-`limit_window_seconds` fixtures). Any other declared duration keeps its own label.
enum CodexWindowClassifier {
    static func kind(limitWindowSeconds seconds: Double?, positionalDefault: WindowKind) -> WindowKind {
        guard let seconds, seconds > 0 else { return positionalDefault }
        switch seconds {
        case 18_000:  return .fiveHour
        case 604_800: return .weekly
        default:      return .other(durationLabel(seconds: seconds))
        }
    }

    /// Human label for an unrecognized window duration, so a new Codex window (e.g. a daily
    /// or monthly limit) still renders honestly instead of being forced into 5h/weekly.
    static func durationLabel(seconds: Double) -> String {
        let hours = (seconds / 3600).rounded()
        if hours < 48 { return "\(Int(hours))h" }
        return "\(Int((seconds / 86_400).rounded()))d"
    }
}

private extension KeyedDecodingContainer {
    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func flexibleString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        return nil
    }
}
