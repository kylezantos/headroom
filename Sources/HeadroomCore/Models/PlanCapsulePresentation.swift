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
        PlanCapsulePresentation.hasLiveCriticalResettableWindow(
            snapshotIsLive: freshness == .live,
            readings: windows.map(UsageMeterReading.init(window:))
        )
    }
}

extension PlanCapsulePresentation {
    /// U3/KTD6.2: the capsule's auto-open decision reads the same normalized severity the
    /// meter row paints, so a Mac capsule and a phone row cannot disagree about Critical at a
    /// rounding boundary. Only the severity source changed; the live snapshot, live window and
    /// resettable-kind gates are the ones the capsule always had. The phone passes readings
    /// built from synced summaries (`UsageMeterReading(widgetSummary:)`).
    public static func hasLiveCriticalResettableWindow(
        snapshotIsLive: Bool,
        readings: [UsageMeterReading]
    ) -> Bool {
        guard snapshotIsLive else { return false }
        return readings.contains { reading in
            switch reading.window.kind {
            case .fiveHour, .weekly:
                return reading.window.freshness == .live && reading.severity == .critical
            case .billingPeriod, .other:
                return false
            }
        }
    }
}

/// 1C (Kyle, 2026-11-24): where the chips after the plan capsule sit (the stale or "Last
/// read" chip, Connected, the menu-bar source glyph). Before this, a hover-opened
/// "Business · 3 resets" pushed them right, and because every capsule is fixed width the
/// account name was the only thing left to give: "Work" became "…". Now a hover-opened
/// capsule opens *over* the run, which stays where the closed capsule put it and fades out
/// underneath. The row reserves only what the open capsule needs past the run's end, so the
/// name gives way only when the open capsule is wider than the capsule and the run together.
///
/// Hover only. A capsule opened by attention (Critical, the first-show reveal, the phone's
/// tap) can stay open, so it still pushes the run and keeps it readable.
public enum PlanCapsuleRunGeometry {
    /// Where the run starts, measured from the capsule's leading edge.
    public static func runOffset(
        closedWidth: Double,
        liveWidth: Double,
        spacing: Double,
        overlaysRun: Bool
    ) -> Double {
        (overlaysRun ? closedWidth : liveWidth) + spacing
    }

    /// The width the capsule and its run take in the row. An empty run takes no spacing.
    public static func width(
        closedWidth: Double,
        liveWidth: Double,
        runWidth: Double,
        spacing: Double,
        overlaysRun: Bool
    ) -> Double {
        guard runWidth > 0 else { return liveWidth }
        let runEnd = runOffset(
            closedWidth: closedWidth, liveWidth: liveWidth, spacing: spacing, overlaysRun: overlaysRun
        ) + runWidth
        return max(runEnd, liveWidth)
    }
}
