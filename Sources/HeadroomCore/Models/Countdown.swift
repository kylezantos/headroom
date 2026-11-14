import Foundation

public struct MeterResetLine: Sendable, Equatable {
    public let countdown: String
    /// The coarsest single-unit form of `countdown` ("22h 54m" → "22h"). A Micro row shows
    /// this instead of the full countdown when the full precision would push the meter off the
    /// row; the full countdown and reset time still live in the tooltip. Defaults to
    /// `countdown` so callers that never shorten stay unchanged.
    public let shortCountdown: String
    public let tooltip: String

    public init(countdown: String, shortCountdown: String? = nil, tooltip: String) {
        self.countdown = countdown
        self.shortCountdown = shortCountdown ?? countdown
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

    /// The coarsest single-unit countdown — "22h 54m" → "22h", "1d 23h" → "1d". A tight Micro
    /// row shows this so the label, meter, and percentage stay on one line; the full precision
    /// remains in the tooltip.
    public static func shortString(to resetsAt: Date, now: Date) -> String {
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "resets now" }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
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
        // R2M3: the countdown never blanks. Once the deadline is behind us the row
        // holds "now" instead of disappearing, because the pre-reset percentage is
        // still on screen until a fresh capture lands — a blank label beside a stale
        // number reads as a bug at the one moment the product exists for. A new
        // capture replaces the deadline (or retires the row as `.unavailable`, which
        // the meter and widget presenters already hide), which is what ends the hold.
        guard interval > 60 else {
            return MeterResetLine(countdown: "now", tooltip: "Resets now")
        }
        let countdown = string(to: resetsAt, now: now)
        return MeterResetLine(
            countdown: countdown,
            shortCountdown: shortString(to: resetsAt, now: now),
            tooltip: "Resets in \(countdown)"
        )
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
        if hours < 24 { return hours == 1 ? "1 hr ago" : "\(hours) hr ago" }
        // A remembered account can go unread for days (default-login plan, R7).
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// The tag a remembered account carries on every surface (R7, R21): "Last read 2 min
    /// ago". One function so the Mac and the phone cannot word it differently.
    public static func lastReadLabel(capturedAt: Date?, now: Date) -> String? {
        updatedLabel(capturedAt: capturedAt, now: now).map { "Last read \($0)" }
    }

    // MARK: - CA-P3/CA-P4: one phrase for an old reading, words for an empty one

    /// CA-P3: what a stale engine row's chip, Settings status and Compact tooltip print,
    /// where "Stale" used to stand with no age. The remembered row's `lastReadLabel` and this
    /// are one phrase on purpose; "Not refreshed" covers a reading nothing dated.
    public static func staleReadLabel(capturedAt: Date?, now: Date) -> String {
        lastReadLabel(capturedAt: capturedAt, now: now) ?? notRefreshedLabel
    }

    public static let notRefreshedLabel = "Not refreshed"

    /// CA-P3: a stale window's state words in a meter's tooltip and Full's state label. It
    /// was "Last known 14 min ago", a third name for the chip's "Last read".
    public static func windowReadLabel(observedAt: Date?, now: Date) -> String {
        lastReadLabel(capturedAt: observedAt, now: now) ?? "Last read"
    }

    /// CA-P3 (UX-01): why a stale engine row's chip carries an age.
    public static let staleReadHelp = "Couldn’t refresh this account. Headroom tries again on its next check."

    /// CA-P3 (UX-01): why a remembered row is not being read, per provider.
    public static func rememberedReadHelp(for providerID: ProviderID) -> String {
        "Not your current \(providerID.displayName) login, so Headroom isn’t reading it. "
            + "Sign in to it again, or add it in Settings › Accounts to keep it live."
    }

    /// CA-P4 (overturns M3A′ for this one state): a window that has never held a number.
    public static let noReadingYet = "No reading yet"
    /// CA-P4: a retained window past its validity window; it held a number once.
    public static let noCurrentReading = "No current reading"

    /// CA-P4: "No reading yet" when nothing was ever observed for the window (Copilot after
    /// sign-in), "No current reading" when a reading aged out. Nil while the window is not
    /// unavailable. Never "No use yet this month": that is wrong for a zero or unlimited
    /// entitlement, which also reads as no number.
    public static func unavailableLabel(for window: UsageWindow) -> String? {
        guard window.freshness.isUnavailable else { return nil }
        return window.observedAt == nil ? noReadingYet : noCurrentReading
    }

    /// CA-P4 (UX-01): the tooltip that says why the row has no number. Without a provider it
    /// names none rather than guessing.
    public static func unavailableHelp(for window: UsageWindow, providerID: ProviderID?) -> String? {
        guard window.freshness.isUnavailable else { return nil }
        let name = providerID?.displayName
        if window.observedAt == nil {
            return name.map { "\($0) hasn’t reported a number for this limit yet." }
                ?? "No number has been reported for this limit yet."
        }
        return name.map { "\($0) didn’t report this limit in its last check." }
            ?? "This limit wasn’t in the last check."
    }

    /// The line a remembered account shows for a window whose reset has passed (R8): when
    /// it reset, and that Headroom has not read it since. It never states a value.
    public static func resetNotReadLine(
        resetAt: Date,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        compact: Bool = false
    ) -> String {
        // `compact` is what a row draws, since the sentence does not fit one:
        // "Reset Wed 10:00 AM · not read since". Tooltips and VoiceOver keep the sentence.
        let when = ResetClockFormatter.pastPhrase(
            for: resetAt, now: now, timeZone: timeZone, locale: locale, compact: compact)
        return "Reset \(when) · not read since"
    }
}
