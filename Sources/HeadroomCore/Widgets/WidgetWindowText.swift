import Foundation

/// R15 / WCW1 / WCW8 (2026-10-02 widget-styles plan): the strings every widget style prints
/// or speaks for a window. Pure, so the wording is tested here rather than only on a device;
/// the shared UI reads it through the `HeadroomWidgetWindowText` alias.
public enum WidgetWindowText {
    /// WCW1: the bare countdown ("4d 6h", "now"); nothing when unresolved or unavailable.
    public static func countdown(_ window: WidgetWindowSummary?, now: Date) -> String? {
        guard let window, !window.freshness.isUnavailable else { return nil }
        return window.resetSchedule.meterResetLine(now: now)?.countdown
    }

    /// WCW8: an em dash, never "--".
    public static func percent(_ window: WidgetWindowSummary?) -> String {
        guard let value = window?.displayPercentRemaining else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    /// R15: the spoken value for one window — shared by every style so the wording cannot
    /// drift between them.
    public static func accessibilityValue(_ window: WidgetWindowSummary?, providerIsLive: Bool, now: Date) -> String {
        guard let window else { return "no reading yet" }
        var parts: [String] = []
        if let value = window.displayPercentRemaining {
            parts.append("\(Int(value.rounded())) percent left")
        }
        if window.freshness.isStale { parts.append("last known") }
        if window.freshness.isUnavailable { parts.append("unavailable") }
        if !providerIsLive { parts.append(providerNeedsAttention) }
        if window.severity == .critical, providerIsLive, window.freshness.isLive { parts.append("low") }
        if !window.freshness.isUnavailable {
            parts.append(Countdown.resetText(
                schedule: window.resetSchedule,
                utilization: window.utilization,
                isLive: window.freshness.isLive,
                now: now
            ))
        }
        return parts.joined(separator: ", ")
    }

    /// R15: one element per provider — its name, then each window in visual order. With no
    /// `windows`, the hero-first order the styles draw: primary, then the rest in popover order.
    /// WCM5-v: a provider with nothing to read speaks its stale reason, never an empty value.
    public static func providerAccessibility(
        _ provider: WidgetStyleProviderRecipe,
        windows: [WidgetWindowSummary]? = nil,
        now: Date
    ) -> String {
        guard !provider.isWaiting else { return WidgetStyleCopy.waiting }
        let spoken = windows ?? ([provider.primary].compactMap { $0 } + provider.secondary)
        guard !spoken.isEmpty else {
            if let message = provider.staleMessage { return message }
            return provider.summary.freshness == .live ? "no reading yet" : providerNeedsAttention
        }
        let isLive = provider.summary.freshness == .live
        return spoken.map { "\($0.widgetDisplayLabel): \(accessibilityValue($0, providerIsLive: isLive, now: now))" }
            .joined(separator: "; ")
    }

    static let providerNeedsAttention = "provider needs attention"
}
