import Foundation

/// Why the plan capsule is open, so the view can pick the matching motion pair (KTD8).
public enum PlanCapsuleMotionCause: Sendable, Equatable {
    case hover
    case attention
}

public enum PlanCapsuleState: Sendable, Equatable {
    case plain
    case bead
    case open
}

/// Pure plan-capsule decision. SwiftUI only renders the result (KTD4).
public struct PlanCapsulePresentation: Sendable, Equatable {
    public let state: PlanCapsuleState
    public let visibleLabel: String
    public let planText: String
    public let detail: String?
    public let showsBead: Bool
    public let motionCause: PlanCapsuleMotionCause?
    public let helpLine: String?
    public let accessibilityPhrase: String?

    public static func resolve(
        planDisplayName: String?,
        bankedResets: Int?,
        isHovering: Bool,
        isCritical: Bool,
        isRevealing: Bool
    ) -> PlanCapsulePresentation {
        let plan = planDisplayName ?? ""
        let count = bankedResets ?? 0
        let hasSpare = count > 0
        let open = hasSpare && (isHovering || isCritical || isRevealing)
        let state: PlanCapsuleState = hasSpare ? (open ? .open : .bead) : .plain
        let detail = open ? "\(count) \(count == 1 ? "reset" : "resets")" : nil
        let visibleLabel: String
        if let detail, !plan.isEmpty {
            visibleLabel = "\(plan) · \(detail)"
        } else if let detail {
            visibleLabel = detail
        } else {
            visibleLabel = plan
        }
        let cause: PlanCapsuleMotionCause? = open ? ((isCritical || isRevealing) ? .attention : .hover) : nil
        return PlanCapsulePresentation(
            state: state,
            visibleLabel: visibleLabel,
            planText: plan,
            detail: detail,
            showsBead: state == .bead,
            motionCause: cause,
            helpLine: Self.helpLine(count: bankedResets),
            accessibilityPhrase: Self.accessibilityPhrase(count: bankedResets)
        )
    }

    /// Tooltip line. Nil at zero and when the count was not reported.
    public static func helpLine(count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        let noun = count == 1 ? "reset" : "resets"
        return "\(count) banked \(noun) — a full reset refreshes the 5-hour and weekly windows"
    }

    /// VoiceOver phrase. States the count and the same full-reset explanation (R12).
    public static func accessibilityPhrase(count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        let noun = count == 1 ? "reset" : "resets"
        return "\(count) banked \(noun) available — a full reset refreshes the 5-hour and weekly windows"
    }
}

extension UsageSnapshot {
    /// A live 5-hour or weekly window at Critical. Spark and other extra windows
    /// do not qualify: a banked reset does not refresh them (KTD5).
    public var hasLiveCriticalResettableWindow: Bool {
        guard freshness == .live else { return false }
        return windows.contains { window in
            switch window.kind {
            case .fiveHour, .weekly:
                return window.freshness == .live && window.severity == .critical
            case .billingPeriod, .other:
                return false
            }
        }
    }
}
