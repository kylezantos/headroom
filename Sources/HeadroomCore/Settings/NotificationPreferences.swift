import Foundation

/// Whether a reminder's lead time counts hours or days (R4).
public enum ReminderLeadUnit: String, Codable, CaseIterable, Sendable {
    case hours
    case days

    /// R4: 1–48 hours or 1–30 days.
    public var amountRange: ClosedRange<Int> {
        switch self {
        case .hours: return 1...48
        case .days: return 1...30
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .hours: return 60 * 60
        case .days: return 24 * 60 * 60
        }
    }
}

/// One use-it-up reminder: "when a limit is within `amount` `unit` of its reset and
/// `threshold`% or more is left". KTD5: `id` names the row and never changes, so an edit
/// animates in place; `firingKey` carries the values, so an edit re-arms the rule.
public struct ReminderRule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public static let thresholdRange: ClosedRange<Int> = 1...100

    public let id: UUID
    public var amount: Int
    public var unit: ReminderLeadUnit
    public var threshold: Int

    public init(id: UUID = UUID(), amount: Int, unit: ReminderLeadUnit, threshold: Int) {
        self.id = id
        self.amount = amount
        self.unit = unit
        self.threshold = threshold
    }

    public var leadInterval: TimeInterval { TimeInterval(amount) * unit.seconds }

    public var leadMinutes: Int { Int(leadInterval / 60) }

    /// KTD5: `<uuid>:<lead minutes>:<threshold>`. Minutes, not amount+unit, so 24 hours
    /// and 1 day are the same rule to the ledger.
    public var firingKey: String { "\(id.uuidString):\(leadMinutes):\(threshold)" }

    public func clamped() -> ReminderRule {
        ReminderRule(
            id: id,
            amount: Self.clampedAmount(amount, unit: unit),
            unit: unit,
            threshold: Self.clampedThreshold(threshold)
        )
    }

    /// R4: changing the unit keeps the number and clamps it (48 hours → 30 days).
    public func withUnit(_ newUnit: ReminderLeadUnit) -> ReminderRule {
        ReminderRule(id: id, amount: amount, unit: newUnit, threshold: threshold).clamped()
    }

    /// R4: blank input (nil) commits as the range's floor.
    public static func clampedAmount(_ raw: Int?, unit: ReminderLeadUnit) -> Int {
        guard let raw else { return unit.amountRange.lowerBound }
        return min(unit.amountRange.upperBound, max(unit.amountRange.lowerBound, raw))
    }

    public static func clampedThreshold(_ raw: Int?) -> Int {
        guard let raw else { return thresholdRange.lowerBound }
        return min(thresholdRange.upperBound, max(thresholdRange.lowerBound, raw))
    }
}

/// Which limit families the reminders cover (R7, KTD3).
public enum ReminderScope: String, Codable, CaseIterable, Sendable {
    case weekly
    case billingPeriod
    case fiveHour

    /// R7: weekly limits and billing periods on; 5-hour windows off.
    public static let defaults: Set<ReminderScope> = [.weekly, .billingPeriod]
}

/// Rule-list helpers shared by the store and the pane (R5, R6, R8).
public enum ReminderRules {
    /// R6: 1 day at 50% and 6 hours at 25%. Fixed IDs, because the defaults are never
    /// written until the user edits: fresh UUIDs per read would change every firing key
    /// on relaunch and re-fire rules already spent this cycle (R12, KTD5).
    public static let defaults: [ReminderRule] = [
        ReminderRule(
            id: UUID(uuidString: "6C1B7B0E-2D1F-4E0B-9A51-0D5E7F1A0001")!,
            amount: 1,
            unit: .days,
            threshold: 50
        ),
        ReminderRule(
            id: UUID(uuidString: "6C1B7B0E-2D1F-4E0B-9A51-0D5E7F1A0002")!,
            amount: 6,
            unit: .hours,
            threshold: 25
        ),
    ]

    /// R5: half the shortest rule's lead in hours and half its threshold, both rounded
    /// down with a floor of 1. An empty list seeds 1 day at 50%.
    public static func seed(from rules: [ReminderRule]) -> ReminderRule {
        guard let shortest = rules.min(by: { ($0.leadMinutes, $0.threshold) < ($1.leadMinutes, $1.threshold) }) else {
            return ReminderRule(amount: 1, unit: .days, threshold: 50)
        }
        let leadHours = shortest.leadMinutes / 60
        return ReminderRule(
            amount: ReminderRule.clampedAmount(max(1, leadHours / 2), unit: .hours),
            unit: .hours,
            threshold: max(1, shortest.threshold / 2)
        )
    }

    /// R6: longest lead first, then highest threshold. Stable, so equal rules keep their
    /// relative order and a resort never shuffles rows that did not change.
    public static func sorted(_ rules: [ReminderRule]) -> [ReminderRule] {
        rules.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element, r = rhs.element
                if l.leadMinutes != r.leadMinutes { return l.leadMinutes > r.leadMinutes }
                if l.threshold != r.threshold { return l.threshold > r.threshold }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// R8: compares values, not row IDs, so rebuilding the default pair by hand still
    /// hides "Reset to defaults".
    public static func isDefault(rules: [ReminderRule], scope: Set<ReminderScope>) -> Bool {
        guard scope == ReminderScope.defaults, rules.count == defaults.count else { return false }
        return zip(rules, defaults).allSatisfy { rule, preset in
            rule.amount == preset.amount && rule.unit == preset.unit && rule.threshold == preset.threshold
        }
    }
}
