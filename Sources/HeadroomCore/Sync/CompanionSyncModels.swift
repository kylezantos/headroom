import Foundation

/// Static validation categories only; transport failures never interpolate source values.
public enum CompanionLeafValidationError: Error, Equatable, Sendable {
    case identity, capture, permanence, number, kind, reset, provenance, rule
}

private func companionFallback<T: RawRepresentable>(
    _ type: T.Type, from decoder: any Decoder, fallback: T
) throws -> T where T.RawValue == String {
    let raw = try decoder.singleValueContainer().decode(String.self)
    return T(rawValue: raw) ?? fallback
}

extension KeyedDecodingContainer {
    /// Only omission authorizes a default; explicit null is corrupt for nonnullable fields.
    fileprivate func companionDecodeIfAbsent<T: Decodable>(_ type: T.Type, forKey key: Key) throws
        -> T?
    {
        guard contains(key) else { return nil }
        return try decode(type, forKey: key)
    }
}

public enum CompanionContentFreshness: String, Codable, Equatable, Sendable {
    case live, pending, stale, unknown
    public init(from decoder: any Decoder) throws {
        self = try companionFallback(Self.self, from: decoder, fallback: .unknown)
    }
}

public enum CompanionWindowFreshness: String, Codable, Equatable, Sendable {
    case live, stale, unavailable, unknown
    public init(from decoder: any Decoder) throws {
        self = try companionFallback(Self.self, from: decoder, fallback: .unknown)
    }
}

public enum CompanionWindowKind: String, Codable, Equatable, Sendable {
    case fiveHour, weekly, other, billingPeriod, unknown
    public init(from decoder: any Decoder) throws {
        self = try companionFallback(Self.self, from: decoder, fallback: .unknown)
    }
}

public enum CompanionResetKind: String, Codable, Equatable, Sendable {
    case scheduled, unresolved, unknown
    public init(from decoder: any Decoder) throws {
        self = try companionFallback(Self.self, from: decoder, fallback: .unknown)
    }
}

/// KTD6.7: hidden numeric metadata survives unavailable windows; only the semantic
/// lift's freshness accessor may authorize showing it. No window identity is encoded.
public struct CompanionSlimWindow: Codable, Equatable, Sendable {
    public let kind: CompanionWindowKind
    public let kindName: String?
    public let billingPeriodDuration: Double?
    public let percentRemaining: Double
    public let utilization: Double?
    public let resetKind: CompanionResetKind
    public let resetDeadline: CompanionWireDate?
    public let resetReason: ResetUnresolvedReason?
    public let freshness: CompanionWindowFreshness
    public let observedAtOverride: CompanionWireDate?
    public let unavailableSince: CompanionWireDate?
    public let isSpark: Bool

    public init(
        kind: CompanionWindowKind, kindName: String? = nil, billingPeriodDuration: Double? = nil,
        percentRemaining: Double, utilization: Double? = nil, resetKind: CompanionResetKind,
        resetDeadline: CompanionWireDate? = nil, resetReason: ResetUnresolvedReason? = nil,
        freshness: CompanionWindowFreshness = .live, observedAtOverride: CompanionWireDate? = nil,
        unavailableSince: CompanionWireDate? = nil, isSpark: Bool = false
    ) throws {
        guard let display = UsageDisplayValue(percentRemaining: percentRemaining),
            utilization?.isFinite != false, billingPeriodDuration?.isFinite != false
        else { throw CompanionLeafValidationError.number }
        switch kind {
        case .fiveHour, .weekly:
            guard kindName == nil, billingPeriodDuration == nil else {
                throw CompanionLeafValidationError.kind
            }
        case .other:
            guard kindName != nil, billingPeriodDuration == nil else {
                throw CompanionLeafValidationError.kind
            }
        case .billingPeriod:
            guard kindName != nil else { throw CompanionLeafValidationError.kind }
        case .unknown: break
        }
        switch resetKind {
        case .scheduled:
            guard resetDeadline != nil, resetReason == nil else {
                throw CompanionLeafValidationError.reset
            }
        case .unresolved:
            guard resetDeadline == nil, resetReason != nil else {
                throw CompanionLeafValidationError.reset
            }
        case .unknown: break
        }
        if freshness == .unavailable, unavailableSince == nil, observedAtOverride == nil {
            throw CompanionLeafValidationError.provenance
        }
        let validBilling = billingPeriodDuration.map { $0 > 0 } ?? false
        self.kind = kind == .billingPeriod && !validBilling ? .unknown : kind
        self.kindName = kindName
        self.billingPeriodDuration =
            kind == .billingPeriod && !validBilling ? nil : billingPeriodDuration
        self.percentRemaining = display.percentRemaining
        self.utilization = utilization
        self.resetKind = resetKind == .unknown ? .unresolved : resetKind
        self.resetDeadline = resetKind == .unknown ? nil : resetDeadline
        self.resetReason = resetKind == .unknown ? .legacyUnknown : resetReason
        self.freshness = freshness
        self.observedAtOverride = observedAtOverride
        self.unavailableSince =
            freshness == .unavailable ? unavailableSince ?? observedAtOverride : unavailableSince
        self.isSpark = isSpark
    }

    private enum CodingKeys: String, CodingKey {
        case kind = "k"
        case kindName = "n"
        case billingPeriodDuration = "d"
        case percentRemaining = "p"
        case utilization = "u"
        case resetKind = "r"
        case resetDeadline = "t"
        case resetReason = "e"
        case freshness = "f"
        case observedAtOverride = "o"
        case unavailableSince = "z"
        case isSpark = "s"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let reason = try c.decodeIfPresent(String.self, forKey: .resetReason).map {
            ResetUnresolvedReason(rawValue: $0) ?? .legacyUnknown
        }
        try self.init(
            kind: c.decode(CompanionWindowKind.self, forKey: .kind),
            kindName: c.decodeIfPresent(String.self, forKey: .kindName),
            billingPeriodDuration: c.decodeIfPresent(Double.self, forKey: .billingPeriodDuration),
            percentRemaining: c.decode(Double.self, forKey: .percentRemaining),
            utilization: c.decodeIfPresent(Double.self, forKey: .utilization),
            resetKind: c.decode(CompanionResetKind.self, forKey: .resetKind),
            resetDeadline: c.decodeIfPresent(CompanionWireDate.self, forKey: .resetDeadline),
            resetReason: reason,
            freshness: c.companionDecodeIfAbsent(CompanionWindowFreshness.self, forKey: .freshness)
                ?? .live,
            observedAtOverride: c.decodeIfPresent(
                CompanionWireDate.self, forKey: .observedAtOverride),
            unavailableSince: c.decodeIfPresent(CompanionWireDate.self, forKey: .unavailableSince),
            isSpark: c.companionDecodeIfAbsent(Bool.self, forKey: .isSpark) ?? false)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(kindName, forKey: .kindName)
        try c.encodeIfPresent(billingPeriodDuration, forKey: .billingPeriodDuration)
        try c.encode(percentRemaining, forKey: .percentRemaining)
        try c.encodeIfPresent(utilization, forKey: .utilization)
        try c.encode(resetKind, forKey: .resetKind)
        try c.encodeIfPresent(resetDeadline, forKey: .resetDeadline)
        try c.encodeIfPresent(resetReason?.rawValue, forKey: .resetReason)
        if freshness != .live { try c.encode(freshness, forKey: .freshness) }
        try c.encodeIfPresent(observedAtOverride, forKey: .observedAtOverride)
        try c.encodeIfPresent(unavailableSince, forKey: .unavailableSince)
        if isSpark { try c.encode(true, forKey: .isSpark) }
    }

    /// Stale/unknown rows without a legitimate original observation/since are omitted;
    /// inheriting today's account capture would fabricate retained provenance (KTD6.2).
    public func widgetSummary(accountCapturedAt: CompanionWireDate?) -> WidgetWindowSummary? {
        let widgetKind: WidgetWindowKind
        let label: String
        switch kind {
        case .fiveHour:
            widgetKind = .fiveHour
            label = WindowKind.fiveHour.shortLabel
        case .weekly:
            widgetKind = .weekly
            label = WindowKind.weekly.shortLabel
        case .other, .billingPeriod:
            guard let kindName else { return nil }
            widgetKind = .other(kindName)
            label = WindowKind.other(kindName).shortLabel
        case .unknown: return nil
        }
        let observed =
            freshness == .live ? observedAtOverride ?? accountCapturedAt : observedAtOverride
        let widgetFreshness: WidgetWindowFreshness
        switch freshness {
        case .live:
            guard observed != nil else { return nil }
            widgetFreshness = .live
        case .stale:
            guard let observed else { return nil }
            widgetFreshness = .stale(observedAt: observed.date)
        case .unavailable, .unknown:
            guard let since = unavailableSince ?? observedAtOverride else { return nil }
            widgetFreshness = .unavailable(since: since.date)
        }
        let reset: ResetSchedule =
            resetKind == .scheduled
            ? .scheduled(resetDeadline!.date) : .unresolved(resetReason!)
        return WidgetWindowSummary(
            kind: widgetKind, label: label, percentRemaining: percentRemaining,
            utilization: utilization,
            resetSchedule: reset, resetLabel: nil, resetTimeZoneIdentifier: nil,
            observedAt: observed?.date,
            severity: WidgetUsageSeverity(UsageSeverity(percentRemaining: percentRemaining)),
            freshness: widgetFreshness,
            billingPeriodDuration: kind == .billingPeriod ? billingPeriodDuration : nil)
    }
}

public struct CompanionAccountSummary: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let planName: String?
    public let freshness: CompanionContentFreshness
    public let capturedAt: CompanionWireDate?
    public let attention: CompanionAttention?
    public let needsAttention: Bool?
    public let bankedResets: Int?
    public let windows: [CompanionSlimWindow]

    public init(
        id: String, title: String, planName: String? = nil,
        freshness: CompanionContentFreshness = .live,
        capturedAt: CompanionWireDate? = nil, attention: CompanionAttention? = nil,
        needsAttention: Bool? = nil,
        bankedResets: Int? = nil, windows: [CompanionSlimWindow]
    ) throws {
        guard !id.isEmpty else { throw CompanionLeafValidationError.identity }
        guard bankedResets.map({ $0 >= 0 }) != false else {
            throw CompanionLeafValidationError.number
        }
        if freshness == .pending {
            guard capturedAt == nil, windows.isEmpty else {
                throw CompanionLeafValidationError.capture
            }
        }
        if freshness != .unknown {
            if freshness == .live || !windows.isEmpty {
                guard capturedAt != nil else { throw CompanionLeafValidationError.capture }
            }
            guard (freshness == .stale) == (needsAttention != nil) else {
                throw CompanionLeafValidationError.permanence
            }
        }
        self.id = id
        self.title = title
        self.planName = planName
        self.freshness = freshness
        self.capturedAt = capturedAt
        self.attention = attention
        self.needsAttention = freshness == .unknown ? nil : needsAttention
        self.bankedResets = bankedResets
        self.windows = windows
    }

    public var displayTitle: String { title.isEmpty ? "Account" : title }
    public var widgetFreshness: WidgetProviderFreshness {
        switch freshness {
        case .live: .live
        case .pending: .pending
        case .stale:
            .stale(
                message: CompanionAttentionCopy.account(attention),
                needsAttention: needsAttention == true)
        case .unknown: .stale(message: CompanionAttentionCopy.generic, needsAttention: false)
        }
    }

    public var widgetWindows: [WidgetWindowSummary] {
        freshness == .unknown
            ? [] : windows.compactMap { $0.widgetSummary(accountCapturedAt: capturedAt) }
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case title = "t"
        case planName = "p"
        case freshness = "f"
        case capturedAt = "c"
        case attention = "a"
        case needsAttention = "h"
        case bankedResets = "b"
        case windows = "w"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id), title: c.decode(String.self, forKey: .title),
            planName: c.decodeIfPresent(String.self, forKey: .planName),
            freshness: c.companionDecodeIfAbsent(CompanionContentFreshness.self, forKey: .freshness)
                ?? .live,
            capturedAt: c.decodeIfPresent(CompanionWireDate.self, forKey: .capturedAt),
            attention: c.decodeIfPresent(CompanionAttention.self, forKey: .attention),
            needsAttention: c.decodeIfPresent(Bool.self, forKey: .needsAttention),
            bankedResets: c.decodeIfPresent(Int.self, forKey: .bankedResets),
            windows: c.decode([CompanionSlimWindow].self, forKey: .windows))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(planName, forKey: .planName)
        if freshness != .live { try c.encode(freshness, forKey: .freshness) }
        try c.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try c.encodeIfPresent(attention, forKey: .attention)
        if freshness == .stale { try c.encode(needsAttention!, forKey: .needsAttention) }
        try c.encodeIfPresent(bankedResets, forKey: .bankedResets)
        try c.encode(windows, forKey: .windows)
    }
}

public enum CompanionSpendKind: String, Codable, Equatable, Sendable {
    case periodSpend, balance, unknown
    public init(from decoder: any Decoder) throws {
        self = try companionFallback(Self.self, from: decoder, fallback: .unknown)
    }
}

public struct CompanionSpendSummary: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let amount: Double?
    public let currency: String?
    public let periodLabel: String
    public let kind: CompanionSpendKind
    public let capturedAt: CompanionWireDate?
    public let freshness: CompanionContentFreshness
    public let attention: CompanionSpendAttention?
    public let needsAttention: Bool?

    public init(
        id: String,
        displayName: String,
        amount: Double? = nil,
        currency: String? = nil,
        periodLabel: String = "Period",
        kind: CompanionSpendKind = .periodSpend,
        capturedAt: CompanionWireDate? = nil,
        freshness: CompanionContentFreshness = .live,
        attention: CompanionSpendAttention? = nil,
        needsAttention: Bool? = nil
    ) throws {
        guard !id.isEmpty else { throw CompanionLeafValidationError.identity }
        guard amount?.isFinite != false else { throw CompanionLeafValidationError.number }
        if freshness == .pending {
            guard capturedAt == nil, amount == nil else {
                throw CompanionLeafValidationError.capture
            }
        }
        if freshness != .unknown {
            if amount != nil, kind != .unknown {
                guard capturedAt != nil else { throw CompanionLeafValidationError.capture }
            }
            guard (freshness == .stale) == (needsAttention != nil) else {
                throw CompanionLeafValidationError.permanence
            }
        }
        self.id = id
        self.displayName = displayName
        self.amount = amount
        self.currency = currency
        self.periodLabel = periodLabel
        self.kind = kind
        self.capturedAt = capturedAt
        self.freshness = freshness
        self.attention = attention
        self.needsAttention = freshness == .unknown ? nil : needsAttention
    }

    /// This lift carries semantic leaves only
    /// It never selects lineage or freshness age.
    public var widgetSummary: WidgetAPISpendSummary {
        let projectedFreshness: WidgetProviderFreshness
        switch (freshness, attention) {
        case (.live, .unknown), (.pending, .unknown):
            projectedFreshness = .stale(
                message: CompanionAttentionCopy.generic, needsAttention: false)
        case (.live, _): projectedFreshness = .live
        case (.pending, _): projectedFreshness = .pending
        case (.stale, _):
            projectedFreshness = .stale(
                message: CompanionAttentionCopy.spend(attention),
                needsAttention: needsAttention == true
            )
        case (.unknown, _):
            projectedFreshness = .stale(
                message: CompanionAttentionCopy.generic, needsAttention: false)
        }
        let projectedKind: APISpendKind?
        switch kind {
        case .periodSpend: projectedKind = .periodSpend
        case .balance: projectedKind = .balance
        case .unknown: projectedKind = nil
        }
        return WidgetAPISpendSummary(
            id: id,
            displayName: displayName.isEmpty ? "API spend" : displayName,
            amount: freshness == .unknown || kind == .unknown ? nil : amount,
            currency: currency,
            periodLabel: periodLabel,
            kind: projectedKind,
            capturedAt: freshness == .unknown ? nil : capturedAt?.date,
            freshness: projectedFreshness,
            attention: attention?.apiSpendAttention
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case displayName = "n"
        case amount = "a"
        case currency = "c"
        case periodLabel = "p"
        case kind = "k"
        case capturedAt = "t"
        case freshness = "f"
        case attention = "e"
        case needsAttention = "h"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            displayName: c.decode(String.self, forKey: .displayName),
            amount: c.decodeIfPresent(Double.self, forKey: .amount),
            currency: c.decodeIfPresent(String.self, forKey: .currency),
            periodLabel: c.companionDecodeIfAbsent(String.self, forKey: .periodLabel) ?? "Period",
            kind: c.companionDecodeIfAbsent(CompanionSpendKind.self, forKey: .kind) ?? .periodSpend,
            capturedAt: c.decodeIfPresent(CompanionWireDate.self, forKey: .capturedAt),
            freshness: c.companionDecodeIfAbsent(CompanionContentFreshness.self, forKey: .freshness)
                ?? .live,
            attention: c.decodeIfPresent(CompanionSpendAttention.self, forKey: .attention),
            needsAttention: c.decodeIfPresent(Bool.self, forKey: .needsAttention)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encode(periodLabel, forKey: .periodLabel)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(capturedAt, forKey: .capturedAt)
        if freshness != .live { try c.encode(freshness, forKey: .freshness) }
        try c.encodeIfPresent(attention, forKey: .attention)
        if freshness == .stale { try c.encode(needsAttention!, forKey: .needsAttention) }
    }
}

public struct CompanionDisplayBlock: Codable, Equatable, Sendable {
    public let meterStyle: MeterStyle
    public let percentageMode: UsagePercentageMode
    public let accountTitleInk: AccountTitleInk
    public let appSparkEnabled: Bool

    public init(
        meterStyle: MeterStyle = .default,
        percentageMode: UsagePercentageMode = .remaining,
        accountTitleInk: AccountTitleInk = .neutral,
        appSparkEnabled: Bool = false
    ) {
        self.meterStyle = meterStyle
        self.percentageMode = percentageMode
        self.accountTitleInk = accountTitleInk
        self.appSparkEnabled = appSparkEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case meterStyle = "m"
        case percentageMode = "p"
        case accountTitleInk = "i"
        case appSparkEnabled = "s"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let style = try c.companionDecodeIfAbsent(String.self, forKey: .meterStyle)
        let mode = try c.companionDecodeIfAbsent(String.self, forKey: .percentageMode)
        let ink = try c.companionDecodeIfAbsent(String.self, forKey: .accountTitleInk)
        self.init(
            meterStyle: style.flatMap(MeterStyle.init(launchToken:)) ?? .default,
            percentageMode: mode.flatMap(UsagePercentageMode.init(rawValue:)) ?? .remaining,
            accountTitleInk: ink.flatMap(AccountTitleInk.init(rawValue:)) ?? .neutral,
            appSparkEnabled: try c.companionDecodeIfAbsent(Bool.self, forKey: .appSparkEnabled)
                ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let token = [
            meterStyle.format.rawValue, meterStyle.shape.rawValue, meterStyle.fill.rawValue,
        ]
        .joined(separator: ".")
        try c.encode(token, forKey: .meterStyle)
        try c.encode(percentageMode.rawValue, forKey: .percentageMode)
        try c.encode(accountTitleInk.rawValue, forKey: .accountTitleInk)
        if appSparkEnabled { try c.encode(true, forKey: .appSparkEnabled) }
    }
}

public enum CompanionReminderUnit: String, Codable, Equatable, Sendable {
    case hours, days
}

public enum CompanionReminderScope: String, Codable, Equatable, Sendable {
    case weekly, billingPeriod, fiveHour
}

public struct CompanionReminderRuleSummary: Codable, Equatable, Sendable {
    public let amount: Int
    public let unit: CompanionReminderUnit
    public let threshold: Int

    public init(amount: Int, unit: CompanionReminderUnit, threshold: Int) throws {
        let bounds = unit == .hours ? 1...48 : 1...30
        guard bounds.contains(amount), (1...100).contains(threshold) else {
            throw CompanionLeafValidationError.rule
        }
        self.amount = amount
        self.unit = unit
        self.threshold = threshold
    }

    private enum CodingKeys: String, CodingKey {
        case amount = "a"
        case unit = "u"
        case threshold = "t"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            amount: c.decode(Int.self, forKey: .amount),
            unit: c.decode(CompanionReminderUnit.self, forKey: .unit),
            threshold: c.decode(Int.self, forKey: .threshold)
        )
    }
}

public struct CompanionReminderSummary: Codable, Equatable, Sendable {
    public let macUseItUpEnabled: Bool
    public let macBankedResetEnabled: Bool
    public let phoneChannelEnabled: Bool
    public let rules: [CompanionReminderRuleSummary]
    public let scope: [CompanionReminderScope]

    public init(
        macUseItUpEnabled: Bool = false,
        macBankedResetEnabled: Bool = false,
        phoneChannelEnabled: Bool = false,
        rules: [CompanionReminderRuleSummary] = [],
        scope: [CompanionReminderScope] = []
    ) {
        self.macUseItUpEnabled = macUseItUpEnabled
        self.macBankedResetEnabled = macBankedResetEnabled
        self.phoneChannelEnabled = phoneChannelEnabled
        self.rules = rules
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case macUseItUpEnabled = "m"
        case macBankedResetEnabled = "b"
        case phoneChannelEnabled = "p"
        case rules = "r"
        case scope = "s"
    }

    /// KTD19: discard an unreadable rule, never substitute a guessed valid rule.
    private struct LossyRule: Decodable {
        let value: CompanionReminderRuleSummary?
        init(from decoder: any Decoder) throws {
            value = try? CompanionReminderRuleSummary(from: decoder)
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            macUseItUpEnabled: try c.companionDecodeIfAbsent(Bool.self, forKey: .macUseItUpEnabled)
                ?? false,
            macBankedResetEnabled: try c.companionDecodeIfAbsent(
                Bool.self, forKey: .macBankedResetEnabled)
                ?? false,
            phoneChannelEnabled: try c.companionDecodeIfAbsent(
                Bool.self, forKey: .phoneChannelEnabled)
                ?? false,
            rules: try c.companionDecodeIfAbsent([LossyRule].self, forKey: .rules)?.compactMap(
                \.value)
                ?? [],
            scope: try c.companionDecodeIfAbsent([String].self, forKey: .scope)?.compactMap(
                CompanionReminderScope.init(rawValue:)) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if macUseItUpEnabled { try c.encode(true, forKey: .macUseItUpEnabled) }
        if macBankedResetEnabled { try c.encode(true, forKey: .macBankedResetEnabled) }
        if phoneChannelEnabled { try c.encode(true, forKey: .phoneChannelEnabled) }
        if !rules.isEmpty { try c.encode(rules, forKey: .rules) }
        if !scope.isEmpty { try c.encode(scope.map(\.rawValue), forKey: .scope) }
    }
}
