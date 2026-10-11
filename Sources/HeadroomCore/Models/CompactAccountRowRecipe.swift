import Foundation

/// One meter a Compact account row draws. The window keeps its own per-window freshness, so
/// a retained stale row stays stale and an unavailable one keeps its label but no value.
public struct CompactAccountRowWindow: Sendable, Equatable {
    public let window: UsageWindow
    /// R11: the row's visible window name — "5h", "wk", a Cursor pool or a Grok period.
    public let shortLabel: String
    /// KTD6.2: the printed integer in the chosen mode, from the same `UsageMeterReading`
    /// every popover row reads. Nil when the row hides its value (unavailable, non-finite).
    public let displayedPercentage: Int?

    public init(window: UsageWindow, shortLabel: String, displayedPercentage: Int?) {
        self.window = window
        self.shortLabel = shortLabel
        self.displayedPercentage = displayedPercentage
    }
}

/// KTD7: what one account's Compact row shows. Pure and SwiftUI-free; the popover lays it out.
///
/// R15: an account that is not showing live or stale usage keeps its Standard section, so
/// Compact never hides an action. Snapshot states that render an action in Standard are
/// decided here; app-only state the snapshot cannot carry (an active setup session, provider
/// capability recovery) arrives as `requiresStandardSection`.
public struct CompactAccountRowRecipe: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case meters
        /// The first reading has not landed and no session owns the row.
        case skeleton
        case standardFallback
    }

    /// R11: at most two meters per row.
    public static let maximumShownWindows = 2

    public let content: Content
    public let shownWindows: [CompactAccountRowWindow]
    /// R12: the "+N" count — windows the row has no room for.
    public let overflowCount: Int
    /// R14: the Micro twin of the user's meter style.
    public let meterStyle: MeterStyle
    /// A transient-stale snapshot draws its meters dimmed, as Standard's `bars(dimmed:)` does.
    public let isDimmed: Bool
    /// R12/R13: every window, overflowed ones included, one per line with its reset text.
    /// Empty when the row draws no meters.
    public let tooltip: String
    /// R12/R13: every window with its value, state and reset text. Empty when the row draws
    /// no meters.
    public let accessibilityValue: String

    public var fallsBackToStandard: Bool { content == .standardFallback }

    /// - Parameters:
    ///   - snapshot: the account's snapshot. Order does not matter; Spark filtering is
    ///     re-applied here so an unfiltered snapshot cannot leak a row Standard hides.
    ///   - showsCodexSparkCounters: `UsageStore.showCodexSparkCountersInApp`, the flag
    ///     `appDisplaySnapshot(for:)` filters the Standard bars with.
    public init(
        snapshot: UsageSnapshot,
        meterStyle: MeterStyle,
        percentageMode: UsagePercentageMode,
        now: Date,
        requiresStandardSection: Bool,
        showsCodexSparkCounters: Bool
    ) {
        self.meterStyle = Self.microTwin(of: meterStyle)
        self.isDimmed = snapshot.freshness != .live

        let windows = Self.visibleWindows(in: snapshot, showsCodexSparkCounters: showsCodexSparkCounters)

        let content = Self.content(
            freshness: snapshot.freshness,
            hasWindows: !windows.isEmpty,
            requiresStandardSection: requiresStandardSection
        )
        guard content == .meters else {
            self.content = content
            self.shownWindows = []
            self.overflowCount = 0
            self.tooltip = ""
            self.accessibilityValue = ""
            return
        }

        self.content = content
        let shown = windows.prefix(Self.maximumShownWindows)
        self.shownWindows = shown.map { window in
            CompactAccountRowWindow(
                window: window,
                shortLabel: Self.shortLabel(for: window.kind),
                displayedPercentage: UsageMeterReading(window: window).roundedPercentage(for: percentageMode)
            )
        }
        self.overflowCount = windows.count - shown.count

        let dimmed = isDimmed
        let lines = windows.map {
            Self.windowDescription($0, percentageMode: percentageMode, dimmed: dimmed, now: now)
        }
        self.tooltip = lines.map(\.tooltip).joined(separator: "\n")
        self.accessibilityValue = lines.map(\.spoken).joined(separator: "; ")
    }

    // MARK: - Decisions

    /// R14: format Micro, the shape the user currently *sees* — a stored Full + Tube renders
    /// as Chip (`GaugeShape.resolved(for:)`), so its twin is a Micro Chip, matching
    /// `InAppDisplayTile` — and the fill unchanged.
    public static func microTwin(of style: MeterStyle) -> MeterStyle {
        MeterStyle(format: .micro, shape: style.resolvedShape, fill: style.fill)
    }

    private static func content(
        freshness: Freshness,
        hasWindows: Bool,
        requiresStandardSection: Bool
    ) -> Content {
        if requiresStandardSection { return .standardFallback }
        switch freshness {
        case .pending:
            // `AccountSectionView.sessionOwnedRow`: with no session owning it, a pending row
            // is the skeleton. A session-owned pending row arrives with the app flag set.
            return .skeleton
        case .stale(let reason) where reason.isPermanent:
            // `AccountSectionView.stateContent` → `signInContent`: a sign-in sentence and
            // recovery chips (Connect, Sign In Again, Install, Approve…).
            return .standardFallback
        case .stale(.providerSetup):
            // The single-account card's `providerSetupOutcome` branch renders a recovery row
            // for every typed outcome, transient ones included (Check Now, Open Guided Setup).
            return .standardFallback
        case .live, .stale:
            // Standard's "No usage data" line has no Compact equivalent to draw.
            return hasWindows ? .meters : .standardFallback
        }
    }

    /// The Standard stack's windows in the popover's order: `appDisplaySnapshot(for:)` drops
    /// Codex Spark counters unless the in-app switch is on, then `fiveHourFirst()` leads with
    /// 5-hour, then weekly or the billing periods, then model rows — each group in slot
    /// order. Taking the first two of this list is KTD7's choice: 5-hour then weekly for
    /// Claude and Codex, both pools for Cursor, the period for Grok, slot order otherwise.
    static func visibleWindows(in snapshot: UsageSnapshot, showsCodexSparkCounters: Bool) -> [UsageWindow] {
        let ordered = snapshot.fiveHourFirst().windows
        guard snapshot.providerID == .codex, !showsCodexSparkCounters else { return ordered }
        return ordered.filter { !$0.kind.isCodexSparkCounter }
    }

    /// R11: the visible label. 5-hour and weekly read "5h" and "wk". Cursor's pools take the
    /// Lock Screen's approved short names ("Models", "Other", `LockScreenWidgetCopy`), since
    /// the row's identity already says Cursor; "Included" is already short. Grok's billing
    /// periods shorten the same way weekly does ("wk", "mo"). Model rows and unknown windows
    /// keep the name the popover already prints (`compactName`: "Fable", "14d").
    public static func shortLabel(for kind: WindowKind) -> String {
        switch kind {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "wk"
        case .billingPeriod(let label, _):
            switch label {
            case "Weekly": return "wk"
            case "Monthly": return "mo"
            case "Cursor Models": return "Models"
            case "Other Models": return "Other"
            default: return label
            }
        case .other:
            return kind.compactName
        }
    }

    // MARK: - Tooltip and VoiceOver

    /// R13: the same pieces, wording and reset formatter `UsageBarView` puts in a Micro row's
    /// `.help` and accessibility value — the percentage in the chosen mode, the window's own
    /// state ("Last known …", "Unavailable") and `meterResetLine(now:)`'s "Resets in …".
    private static func windowDescription(
        _ window: UsageWindow,
        percentageMode: UsagePercentageMode,
        dimmed: Bool,
        now: Date
    ) -> (tooltip: String, spoken: String) {
        let reading = UsageMeterReading(window: window)
        let pct = reading.roundedPercentage(for: percentageMode)
        let state: String? = switch window.freshness {
        case .live:
            nil
        case .stale(let observedAt):
            Countdown.updatedLabel(capturedAt: observedAt, now: now).map { "Last known \($0)" } ?? "Last known"
        case .unavailable:
            "Unavailable"
        }
        let reset = window.freshness.isUnavailable ? nil : window.resetSchedule.meterResetLine(now: now)?.tooltip

        var shown: [String] = []
        var spoken: [String] = []
        if let pct {
            shown.append("\(pct)% \(percentageMode.term)")
            spoken.append("\(pct) percent \(percentageMode.term)")
        }
        // U8 (R3, AP1): same gate as the red numeral — live and not dimmed.
        if reading.usesCriticalInk(dimmed: dimmed) {
            spoken.append("critical")
        }
        if let state {
            shown.append(state)
            spoken.append(state)
        }
        if let reset {
            shown.append(reset)
            spoken.append(reset)
        }

        let name = window.kind.spokenName
        return (
            tooltip: shown.isEmpty ? name : "\(name): \(shown.joined(separator: " · "))",
            spoken: spoken.isEmpty ? name : "\(name): \(spoken.joined(separator: ", "))"
        )
    }
}
