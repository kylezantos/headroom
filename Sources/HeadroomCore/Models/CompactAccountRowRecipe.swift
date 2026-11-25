import Foundation

/// Default-login plan U8 (R7, R8, KTD10): how a remembered account's row reads, decided once
/// for Standard, Compact and Settings. The treatment is keyed on the row's kind, never on
/// freshness: an engine row that is stale keeps its "Stale" capsule and its gauges.
///
/// - The identity row carries `lastReadLabel` ("Last read 2 min ago") where an engine row
///   would carry "Stale". A remembered row never says "Stale".
/// - A window whose scheduled reset has passed draws as one line, its label and
///   `Countdown.resetNotReadLine` ("Reset today at 1:10 PM · not read since"), with no gauge
///   and no number (R8). Every other window keeps its dimmed meter. The reset is read off the
///   window's own schedule rather than its freshness, so a reading the aging pass has not
///   reached yet still never states a value past its reset.
public struct RememberedRowRecipe: Sendable, Equatable {
    /// `Countdown.lastReadLabel`; nil only when nothing records when the account was read.
    public let lastReadLabel: String?
    /// One per window, in the order given — what `UsageBarsStack` lays out: the reset line
    /// that replaces the window's meter, or nil for its (dimmed) meter.
    public let resetNotReadLines: [String?]
    /// The same lines in `Countdown`'s compact form, which is what the row draws.
    public let compactResetNotReadLines: [String?]

    public init(
        windows: [UsageWindow],
        lastReadAt: Date?,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        lastReadLabel = Countdown.lastReadLabel(capturedAt: lastReadAt, now: now)
        resetNotReadLines = windows.map { window in
            Self.resetNotReadLine(for: window, now: now, timeZone: timeZone, locale: locale)
        }
        compactResetNotReadLines = windows.map { window in
            Self.resetNotReadLine(for: window, now: now, timeZone: timeZone, locale: locale, compact: true)
        }
    }

    /// The reset line for one window of a remembered row, or nil while its reset is ahead
    /// (or it has none: a window with no scheduled reset keeps the ordinary unavailable
    /// meter, since "Reset …" would name a reset nobody reported).
    public static func resetNotReadLine(
        for window: UsageWindow,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        compact: Bool = false
    ) -> String? {
        guard let deadline = window.resetSchedule.deadline, !(deadline > now) else { return nil }
        return Countdown.resetNotReadLine(
            resetAt: deadline, now: now, timeZone: timeZone, locale: locale, compact: compact)
    }
}

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
    /// Default-login plan U8 (R7): set only on a remembered account's row, where it takes the
    /// place of "Stale" in the tooltip and VoiceOver label. Nil on every engine row.
    public let lastReadLabel: String?
    /// U8: true for a remembered account's row, whatever its freshness.
    public let isRemembered: Bool
    /// CA-P3: a dimmed engine row's "Last read 14 min ago" (or "Not refreshed"), from the
    /// snapshot's capture time, the same words its Standard chip prints.
    public let staleReadLabel: String

    public var fallsBackToStandard: Bool { content == .standardFallback }

    /// The row's one state phrase for its tooltip and VoiceOver label: "Last read …" on a
    /// remembered row (U8, R7) and, since CA-P3, on a dimmed engine row too, where it was a
    /// bare "Stale" with no age. Nil otherwise.
    public var rowStateLabel: String? {
        guard content == .meters else { return nil }
        if isRemembered { return lastReadLabel }
        return isDimmed ? staleReadLabel : nil
    }

    /// CA-P3: the tooltip line that says why the row is old, under `rowStateLabel`.
    public var rowStateHelp: String? {
        guard content == .meters, !isRemembered, isDimmed else { return nil }
        return Countdown.staleReadHelp
    }

    /// - Parameters:
    ///   - snapshot: the account's snapshot. Order does not matter; Spark filtering is
    ///     re-applied here so an unfiltered snapshot cannot leak a row Standard hides.
    ///   - showsCodexSparkCounters: `UsageStore.showCodexSparkCountersInApp`, the flag
    ///     `appDisplaySnapshot(for:)` filters the Standard bars with.
    ///   - showsAntigravityFiveHourWindows: `UsageStore.showsAntigravityFiveHourWindows`, the
    ///     other switch `appDisplaySnapshot(for:)` filters with.
    ///   - isRemembered: U8, the row is an account the default login left. Its tooltip
    ///     names when it was last read and, per window, its reset (`RememberedRowRecipe`).
    ///   - lastReadAt: U8, when a remembered account was last read; the snapshot's capture
    ///     time stands in when absent.
    public init(
        snapshot: UsageSnapshot,
        meterStyle: MeterStyle,
        percentageMode: UsagePercentageMode,
        now: Date,
        requiresStandardSection: Bool,
        showsCodexSparkCounters: Bool,
        showsAntigravityFiveHourWindows: Bool = true,
        antigravityGPUCreditsMode: AntigravityGPUCreditsMode = .off,
        isRemembered: Bool = false,
        lastReadAt: Date? = nil,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        self.meterStyle = Self.microTwin(of: meterStyle)
        self.isDimmed = snapshot.freshness != .live
        self.isRemembered = isRemembered
        self.staleReadLabel = Countdown.staleReadLabel(capturedAt: snapshot.capturedAt, now: now)
        self.lastReadLabel = isRemembered
            ? Countdown.lastReadLabel(capturedAt: lastReadAt ?? snapshot.capturedAt, now: now)
            : nil

        var windows = Self.visibleWindows(
            in: snapshot,
            showsCodexSparkCounters: showsCodexSparkCounters,
            showsAntigravityFiveHourWindows: showsAntigravityFiveHourWindows,
            antigravityGPUCreditsMode: antigravityGPUCreditsMode
        )
        if isRemembered {
            // U8 (R8): a cell past its reset prints no number, even before the aging pass
            // has turned its window unavailable.
            windows = windows.map { window in
                guard !window.freshness.isUnavailable,
                      let deadline = window.resetSchedule.deadline, !(deadline > now)
                else { return window }
                // CA-P4: it held a number, so it keeps an anchor ("No current reading").
                return window.withFreshness(.unavailable(since: deadline), observedAt: snapshot.capturedAt)
            }
        }

        let content = Self.content(
            freshness: snapshot.freshness,
            hasWindows: !windows.isEmpty,
            // KTD7 (OpenCode plan): the no-plan row's See Go Plans is an action Compact
            // cannot draw, so it keeps the Standard section like any other recovery row.
            requiresStandardSection: requiresStandardSection || snapshot.planStatusRecovery != nil
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
        let shown = snapshot.providerID == .antigravity
            ? Self.onePerAntigravityPool(from: windows)
            : Self.shownWindows(from: windows)
        self.shownWindows = shown.map { window in
            CompactAccountRowWindow(
                window: window,
                shortLabel: Self.shortLabel(for: window.kind),
                displayedPercentage: UsageMeterReading(window: window).roundedPercentage(for: percentageMode)
            )
        }
        self.overflowCount = windows.count - shown.count

        let dimmed = isDimmed
        let lines = windows.map { window -> (tooltip: String, spoken: String) in
            // U8 (R8): a remembered window past its reset says when it reset, never a value.
            if isRemembered,
               let line = RememberedRowRecipe.resetNotReadLine(
                   for: window, now: now, timeZone: timeZone, locale: locale) {
                let name = window.kind.spokenName
                return (tooltip: "\(name): \(line)", spoken: "\(name): \(line)")
            }
            return Self.windowDescription(
                window, percentageMode: percentageMode, dimmed: dimmed,
                showsWindowState: !isRemembered, now: now
            )
        }
        self.tooltip = lines.map(\.tooltip).joined(separator: "\n")
        self.accessibilityValue = lines.map(\.spoken).joined(separator: "; ")
    }

    /// One Compact cell under a header column. `ownLabel` is set when the window sits under a
    /// column that names another kind (a neighbour's row chose the header), so the cell names
    /// itself instead of reading as the column's window (KTD15: a limit can move a window
    /// into a slot its neighbours don't show).
    public struct PlacedCell: Sendable, Equatable {
        public let window: CompactAccountRowWindow
        public let ownLabel: String?
    }

    /// The shown windows under the card header's columns: each under its own kind, then any
    /// left over in the first empty column, so nothing the recipe shows is dropped. With no
    /// columns, the shown windows in order with no labels of their own.
    public func placedWindows(columns: [WindowKind]) -> [PlacedCell?] {
        guard !columns.isEmpty else { return shownWindows.map { PlacedCell(window: $0, ownLabel: nil) } }
        var placed: [PlacedCell?] = columns.map { kind in
            shownWindows.first { $0.window.kind.persistentID == kind.persistentID }
                .map { PlacedCell(window: $0, ownLabel: nil) }
        }
        let used = Set(placed.compactMap { $0?.window.window.kind.persistentID })
        for leftover in shownWindows where !used.contains(leftover.window.kind.persistentID) {
            if let gap = placed.firstIndex(where: { $0 == nil }) {
                placed[gap] = PlacedCell(window: leftover, ownLabel: leftover.shortLabel)
            }
        }
        return placed
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

    /// KTD15: two windows in source order, except that a live or stale window at 100% used
    /// (a limited one included) takes a shown slot from the shown window with the most room.
    /// With nothing at its limit this is exactly the first two, so labels never move until a
    /// limit is hit. Unavailable windows never take a slot, and a window at its limit is never
    /// displaced. The chosen pair keeps source order. The row stays one line either way: a
    /// usage state never sends it to the Standard section.
    static func shownWindows(from windows: [UsageWindow]) -> [UsageWindow] {
        var shown = Array(windows.indices.prefix(maximumShownWindows))
        for candidate in windows.indices.dropFirst(maximumShownWindows) where isAtLimit(windows[candidate]) {
            let replaceable = shown.indices.filter { !isAtLimit(windows[shown[$0]]) }
            // An unavailable shown window has no number to keep, so it counts as all room.
            guard let roomiest = replaceable.max(by: { room(windows[shown[$0]]) < room(windows[shown[$1]]) })
            else { break }
            shown[roomiest] = candidate
        }
        return shown.sorted().map { windows[$0] }
    }

    /// Antigravity's two pools each report a 5-hour and a weekly row, and the provider emits
    /// each pool's tighter row first. Compact shows that first row of each pool, so the two
    /// meters are the two pools rather than one pool's pair. The rows in one pool share a
    /// limit, so its tighter row is also the one at its limit first: no swap is needed.
    static func onePerAntigravityPool(from windows: [UsageWindow]) -> [UsageWindow] {
        var pools: Set<String> = []
        let shown = windows.filter { window in
            guard let pool = antigravityPool(of: window.kind) else { return false }
            return pools.insert(pool).inserted
        }
        return Array(shown.prefix(maximumShownWindows))
    }

    /// The pool an Antigravity row belongs to, read off its stored label (the provider's
    /// `windowKind`), so this compiles where the provider itself does not (iOS).
    private static func antigravityPool(of kind: WindowKind) -> String? {
        guard case .other(let label) = kind else { return nil }
        if label == AntigravityGPUCreditsWindow.storedLabel { return AntigravityGPUCreditsWindow.shortLabel }
        return AntigravityRowLabels.parse(label)?.pool.rawValue
    }

    static func isAtLimit(_ window: UsageWindow) -> Bool {
        !window.freshness.isUnavailable && window.utilization.isFinite && window.utilization >= 100
    }

    private static func room(_ window: UsageWindow) -> Double {
        window.freshness.isUnavailable || !window.utilization.isFinite ? .infinity : window.percentRemaining
    }

    /// The Standard stack's windows in the popover's order: `appDisplaySnapshot(for:)` drops
    /// Codex Spark counters unless the in-app switch is on, and Antigravity's 5-hour rows while
    /// "Show 5-hour windows" is off, then `fiveHourFirst()` leads with
    /// 5-hour, then weekly or the billing periods, then model rows — each group in slot
    /// order. Taking the first two of this list is KTD7's choice: 5-hour then weekly for
    /// Claude and Codex, both pools for Cursor, the period for Grok, slot order otherwise.
    static func visibleWindows(
        in snapshot: UsageSnapshot,
        showsCodexSparkCounters: Bool,
        showsAntigravityFiveHourWindows: Bool = true,
        antigravityGPUCreditsMode: AntigravityGPUCreditsMode = .off
    ) -> [UsageWindow] {
        let ordered = AntigravityFiveHourWindows.visibleWindows(
            snapshot.fiveHourFirst().windows,
            providerID: snapshot.providerID,
            showsFiveHourWindows: showsAntigravityFiveHourWindows,
            gpuCreditsMode: antigravityGPUCreditsMode
        )
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
        case .other(let label):
            return antigravityShortLabel(label) ?? kind.compactName
        }
    }

    /// CA-I10 (IOS-10): the shorter name a long window label takes before a row gives up a
    /// line or truncates. A Codex model row "GPT-5.3-Codex-Spark · Weekly" keeps its period
    /// and the model's last hyphenated part, "Spark · Weekly", the same contraction the
    /// widget header's `compactLabel` makes. Nil when the name has no shorter form.
    public static func shortDisplayName(for kind: WindowKind) -> String? {
        let parts = kind.displayName.components(separatedBy: " · ")
        guard parts.count == 2,
              let model = parts[0].split(separator: "-").last.map(String.init),
              model != parts[0], model.first?.isLetter == true
        else { return nil }
        return "\(model) · \(parts[1])"
    }

    /// Antigravity's pool rows, short enough for the 84pt Compact column and the Lock
    /// Screen rectangle, which the stored labels are not. "Other" is the Claude and GPT pool, as
    /// Cursor's "Other" is its other pool; tooltips and VoiceOver name each row in full.
    /// Nil for any other label.
    public static func antigravityShortLabel(_ label: String) -> String? {
        if label == AntigravityGPUCreditsWindow.storedLabel { return AntigravityGPUCreditsWindow.shortLabel }
        return AntigravityRowLabels.parse(label).map { AntigravityRowLabels.short($0.pool, $0.window) }
    }

    // MARK: - Tooltip and VoiceOver

    /// A stale window's state words, as `UsageBarView` prints them. CA-P3: "Last read", the
    /// chip's phrase, where it was "Last known".
    private static func lastKnownState(_ window: UsageWindow, now: Date) -> String {
        Countdown.windowReadLabel(observedAt: window.freshness.observedAt, now: now)
    }

    /// R13: the same pieces, wording and reset formatter `UsageBarView` puts in a Micro row's
    /// `.help` and accessibility value — the percentage in the chosen mode, the window's own
    /// state ("Last read …", "No reading yet") and `meterResetLine(now:)`'s "Resets in …".
    ///
    /// U8: a remembered row drops the per-window "Last read …" (`showsWindowState: false`);
    /// the row's own last-read line already says it once.
    private static func windowDescription(
        _ window: UsageWindow,
        percentageMode: UsagePercentageMode,
        dimmed: Bool,
        showsWindowState: Bool,
        now: Date
    ) -> (tooltip: String, spoken: String) {
        let reading = UsageMeterReading(window: window)
        let pct = reading.roundedPercentage(for: percentageMode)
        let state: String? = switch window.freshness {
        case .live:
            nil
        case .stale:
            showsWindowState ? lastKnownState(window, now: now) : nil
        case .unavailable:
            // CA-P4: the words a Micro row now prints in its countdown slot.
            Countdown.unavailableLabel(for: window)
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
