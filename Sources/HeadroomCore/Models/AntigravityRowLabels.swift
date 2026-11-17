import Foundation

/// The stored labels of Antigravity's four rows ("Gemini 5h", "Gemini weekly", "Other 5h",
/// "Other weekly") and their compact short forms, in one platform-neutral place. The provider
/// builds the stored labels, and the compact recipe reads the pool and short form back off them,
/// so each spelling lives only here.
enum AntigravityRowLabels {
    enum Pool: String, CaseIterable {
        case gemini = "Gemini"
        case other = "Other"
    }

    enum Window: String, CaseIterable {
        case fiveHour = "5h"
        case weekly = "weekly"

        var shortName: String {
            switch self {
            case .fiveHour: "5h"
            case .weekly: "wk"
            }
        }
    }

    static func stored(_ pool: Pool, _ window: Window) -> String {
        "\(pool.rawValue) \(window.rawValue)"
    }

    static func short(_ pool: Pool, _ window: Window) -> String {
        "\(pool.rawValue) \(window.shortName)"
    }

    /// The pool and window a stored label names, or nil for any other label.
    static func parse(_ label: String) -> (pool: Pool, window: Window)? {
        for pool in Pool.allCases {
            for window in Window.allCases where label == stored(pool, window) {
                return (pool, window)
            }
        }
        return nil
    }
}

/// The "Show 5-hour windows" switch for Antigravity (`UsageStore.showsAntigravityFiveHourWindows`).
/// A row is a 5-hour Antigravity row only when the snapshot is Antigravity's and its stored
/// label parses as a 5-hour pool row, so no other provider's row can be hidden by a label
/// that happens to match. Every surface filters through `visibleWindows`, so the popover,
/// Compact rows, the menu bar, widgets, the phone and reminders agree on what is hidden.
public enum AntigravityFiveHourWindows {
    public static func isFiveHourRow(_ kind: WindowKind, providerID: ProviderID) -> Bool {
        guard providerID == .antigravity, case .other(let label) = kind else { return false }
        return AntigravityRowLabels.parse(label)?.window == .fiveHour
    }

    /// `windows` without Antigravity's 5-hour rows while the switch is off. Hiding never
    /// empties the list: when nothing else would remain, every row stays.
    public static func visibleWindows(
        _ windows: [UsageWindow], providerID: ProviderID, showsFiveHourWindows: Bool
    ) -> [UsageWindow] {
        guard providerID == .antigravity, !showsFiveHourWindows else { return windows }
        let kept = windows.filter { !isFiveHourRow($0.kind, providerID: providerID) }
        return kept.isEmpty ? windows : kept
    }

    public static func visibleSnapshot(_ snapshot: UsageSnapshot, showsFiveHourWindows: Bool) -> UsageSnapshot {
        guard snapshot.providerID == .antigravity, !showsFiveHourWindows else { return snapshot }
        let windows = visibleWindows(
            snapshot.windows, providerID: snapshot.providerID, showsFiveHourWindows: false)
        return windows.count == snapshot.windows.count ? snapshot : snapshot.replacingWindows(windows)
    }
}
