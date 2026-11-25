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

/// How Antigravity displays Google Colab GPU compute-unit credits (`colab usage`).
/// Default `.off` leaves existing Antigravity cards unchanged and never spawns `colab`.
public enum AntigravityGPUCreditsMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case replaceOtherWeekly
    case add

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "Off"
        case .replaceOtherWeekly: "Replace Other · Weekly"
        case .add: "Add"
        }
    }
}

/// User-selected Google Colab monthly allotment, used to compute the 90-day (3-month)
/// steady-state tank capacity (`3 × monthlyUnits`) because unused Colab compute units
/// expire strictly after 90 days.
public enum ColabComputeTier: String, CaseIterable, Identifiable, Sendable {
    case aiUltra
    case proPlus
    case pro

    public var id: String { rawValue }

    public var monthlyUnits: Double {
        switch self {
        case .aiUltra: 2_000
        case .proPlus: 600
        case .pro: 100
        }
    }

    /// Steady-state tank size under Google Colab's 90-day compute-unit expiration rule.
    public var threeMonthCapacity: Double { monthlyUnits * 3 }

    public var label: String {
        switch self {
        case .aiUltra: "AI Ultra (2,000/mo · 6,000 max)"
        case .proPlus: "Pro+ (600/mo · 1,800 max)"
        case .pro: "Pro (100/mo · 300 max)"
        }
    }
}

/// Shared identity, refill-date math, and visibility filtering for Antigravity's optional
/// Colab GPU Credits row. Lives in `Models` so Mac, widgets, and iOS share one contract.
public enum AntigravityGPUCreditsWindow {
    public static let storedLabel = "GPU Credits"
    public static let shortLabel = "GPU"
    public static let windowKind = WindowKind.other(storedLabel)

    public static func isGPUCreditsRow(_ kind: WindowKind, providerID: ProviderID) -> Bool {
        guard providerID == .antigravity, case .other(let label) = kind else { return false }
        return label == storedLabel
    }

    public static func isOtherWeeklyRow(_ kind: WindowKind, providerID: ProviderID) -> Bool {
        guard providerID == .antigravity, case .other(let label) = kind else { return false }
        guard let parsed = AntigravityRowLabels.parse(label) else { return false }
        return parsed.pool == .other && parsed.window == .weekly
    }

    /// Computes the next occurrence of a monthly refill day (`1...31`) strictly after `now`,
    /// clamping days like 31 to shorter months (e.g., Feb 28/29). Returns `nil` for invalid days.
    public static func nextMonthlyRefillDate(
        day: Int,
        after now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let startOfMonthComps = calendar.dateComponents([.year, .month], from: now)
        guard let currentMonthStart = calendar.date(from: startOfMonthComps) else { return nil }

        func clampedDate(forMonthStart monthStart: Date) -> Date? {
            guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return nil }
            let clampedDay = min(day, range.count)
            var comps = calendar.dateComponents([.year, .month], from: monthStart)
            comps.day = clampedDay
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            return calendar.date(from: comps)
        }

        if let candidate = clampedDate(forMonthStart: currentMonthStart), candidate > now {
            return candidate
        }
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) else {
            return nil
        }
        return clampedDate(forMonthStart: nextMonthStart)
    }

    /// Filters Antigravity windows for `mode`:
    /// - `.off`: removes any GPU Credits row.
    /// - `.add`: keeps all windows.
    /// - `.replaceOtherWeekly`: hides `Other weekly` ONLY while a usable GPU Credits row is
    ///   present, falling back honestly to `Other weekly` if GPU credits are unavailable.
    public static func visibleWindows(
        _ windows: [UsageWindow],
        providerID: ProviderID,
        mode: AntigravityGPUCreditsMode
    ) -> [UsageWindow] {
        guard providerID == .antigravity else { return windows }
        switch mode {
        case .off:
            return windows.filter { !isGPUCreditsRow($0.kind, providerID: providerID) }
        case .add:
            return windows
        case .replaceOtherWeekly:
            let hasUsableGPU = windows.contains {
                isGPUCreditsRow($0.kind, providerID: providerID) && AntigravityFiveHourWindows.hasUsableNumber($0)
            }
            guard hasUsableGPU else {
                return windows.filter { !isGPUCreditsRow($0.kind, providerID: providerID) }
            }
            return windows.filter { !isOtherWeeklyRow($0.kind, providerID: providerID) }
        }
    }
}

/// The "Show 5-hour windows" switch for Antigravity (`UsageStore.showsAntigravityFiveHourWindows`),
/// composed with `AntigravityGPUCreditsMode`.
/// A row is a 5-hour Antigravity row only when the snapshot is Antigravity's and its stored
/// label parses as a 5-hour pool row, so no other provider's row can be hidden by a label
/// that happens to match. Every surface filters through `visibleWindows`, so the popover,
/// Compact rows, the menu bar, widgets, the phone and reminders agree on what is hidden.
public enum AntigravityFiveHourWindows {
    public static func isFiveHourRow(_ kind: WindowKind, providerID: ProviderID) -> Bool {
        guard providerID == .antigravity, case .other(let label) = kind else { return false }
        return AntigravityRowLabels.parse(label)?.window == .fiveHour
    }

    /// `windows` without Antigravity's 5-hour rows while the switch is off, plus GPU credits
    /// visibility filtering (`mode`). The 5-hour rows are hidden only while some remaining row
    /// has a usable number: when every other row is unavailable or has no finite percentage
    /// (or there is none), every row stays.
    public static func visibleWindows(
        _ windows: [UsageWindow],
        providerID: ProviderID,
        showsFiveHourWindows: Bool,
        gpuCreditsMode: AntigravityGPUCreditsMode = .off
    ) -> [UsageWindow] {
        guard providerID == .antigravity else { return windows }
        let afterGPU = AntigravityGPUCreditsWindow.visibleWindows(
            windows, providerID: providerID, mode: gpuCreditsMode
        )
        guard !showsFiveHourWindows else { return afterGPU }
        let kept = afterGPU.filter { !isFiveHourRow($0.kind, providerID: providerID) }
        return kept.contains(where: hasUsableNumber) ? kept : afterGPU
    }

    static func hasUsableNumber(_ window: UsageWindow) -> Bool {
        !window.freshness.isUnavailable && window.utilization.isFinite
    }

    public static func visibleSnapshot(
        _ snapshot: UsageSnapshot,
        showsFiveHourWindows: Bool,
        gpuCreditsMode: AntigravityGPUCreditsMode = .off
    ) -> UsageSnapshot {
        guard snapshot.providerID == .antigravity else { return snapshot }
        let windows = visibleWindows(
            snapshot.windows,
            providerID: snapshot.providerID,
            showsFiveHourWindows: showsFiveHourWindows,
            gpuCreditsMode: gpuCreditsMode
        )
        return windows == snapshot.windows ? snapshot : snapshot.replacingWindows(windows)
    }
}
