import Foundation

public struct MeterResetLine: Sendable, Equatable {
    public let countdown: String
    public let tooltip: String

    public init(countdown: String, tooltip: String) {
        self.countdown = countdown
        self.tooltip = tooltip
    }
}

/// Pure reset-countdown formatting. Kept out of views so every surface uses the same
/// approved precision and reset-evidence semantics.
public enum Countdown {
    /// Compact countdown from `now` to a scheduled deadline, e.g. "4h 59m" or "2m".
    public static func string(to resetsAt: Date, now: Date) -> String {
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "resets now" }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Complete provider-independent reset sentence for subscription presentation.
    /// Deliberately derives from scheduled evidence instead of `resetLabel`, so Claude and Codex
    /// use the same compact relative grammar while source labels remain available to
    /// diagnostics and snapshot consumers.
    public static func resetText(resetsAt: Date, now: Date) -> String {
        resetLine(resetsAt: resetsAt, now: now)?.tooltip ?? "Reset info unavailable"
    }

    public static func resetLine(resetsAt: Date, now: Date) -> MeterResetLine? {
        let interval = resetsAt.timeIntervalSince(now)
        if (-60...60).contains(interval) {
            return MeterResetLine(countdown: "now", tooltip: "Resets now")
        }
        guard interval > 60 else { return nil }
        let countdown = string(to: resetsAt, now: now)
        return MeterResetLine(countdown: countdown, tooltip: "Resets in \(countdown)")
    }

    public static func resetText(for window: UsageWindow, now: Date) -> String {
        resetText(
            schedule: window.resetSchedule,
            utilization: window.utilization,
            isLive: window.freshness.isLive,
            now: now
        )
    }

    public static func resetText(
        schedule: ResetSchedule,
        utilization: Double?,
        isLive: Bool,
        now: Date
    ) -> String {
        switch schedule {
        case .scheduled(let deadline):
            return resetText(resetsAt: deadline, now: now)
        case .unresolved(let reason):
            if isLive,
               utilization == 0,
               reason == .absent || reason == .elapsed {
                return "Available"
            }
            return "Reset info unavailable"
        }
    }

    /// Relative "updated" label for a captured snapshot, e.g. "just now",
    /// "3 min ago". Returns nil when there is no capture time (`.pending`).
    public static func updatedLabel(capturedAt: Date?, now: Date) -> String? {
        guard let capturedAt else { return nil }
        let seconds = max(0, now.timeIntervalSince(capturedAt))
        let minutes = Int(seconds / 60)
        if minutes <= 0 { return "just now" }
        if minutes == 1 { return "1 min ago" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return hours == 1 ? "1 hr ago" : "\(hours) hr ago"
    }
}
