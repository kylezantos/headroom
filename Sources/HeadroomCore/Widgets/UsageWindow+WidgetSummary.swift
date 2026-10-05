import Foundation

// KTD2 (iOS parity plan): the popover's meter row renders synced rows unchanged, so the
// phone needs a `UsageWindow` built from the wire summary. This file is compiled into both
// iOS targets (Core `Widgets/` is whole-folder, KTD4); `WidgetSnapshotProjector.swift`, the
// forward direction, is not — which is why the inverse cannot live beside it.

public extension UsageWindow {
    /// D12 (inventory): the inverse of the projector's window summary.
    ///
    /// `utilization` is mandatory on `UsageWindow`, so a v1-migrated row with no exact
    /// utilization materializes `100 − percentRemaining`. That value satisfies the model and
    /// nothing else: it is not source evidence, so meter decisions must come from
    /// `UsageMeterReading(widgetSummary:)`, which keeps the stored remaining as the canonical
    /// display and the exact utilization (or its absence) separately.
    init(widgetSummary summary: WidgetWindowSummary) {
        self.init(
            kind: WindowKind(widgetKind: summary.kind, billingPeriodDuration: summary.billingPeriodDuration),
            utilization: summary.utilization ?? (100 - summary.percentRemaining),
            resetSchedule: summary.resetSchedule,
            resetLabel: summary.resetLabel,
            resetTimeZoneIdentifier: summary.resetTimeZoneIdentifier,
            freshness: UsageWindowFreshness(summary.freshness),
            // The source's own observation anchor, never the publication time (R2B2).
            observedAt: summary.observedAt
        )
    }
}

public extension WindowKind {
    /// The projector writes a billing period as `.other(label)` plus an additive
    /// `billingPeriodDuration`; only a positive, finite duration recovers the period.
    /// Anything else stays an honest labeled `.other`, as an older reader would see it.
    init(widgetKind: WidgetWindowKind, billingPeriodDuration: TimeInterval?) {
        switch widgetKind {
        case .fiveHour:
            self = .fiveHour
        case .weekly:
            self = .weekly
        case .other(let label):
            if let duration = billingPeriodDuration, duration.isFinite, duration > 0 {
                self = .billingPeriod(label: label, duration: duration)
            } else {
                self = .other(label)
            }
        }
    }
}

public extension UsageWindowFreshness {
    /// One to one: the wire freshness carries the same dates the source did.
    init(_ freshness: WidgetWindowFreshness) {
        switch freshness {
        case .live: self = .live
        case .stale(let observedAt): self = .stale(observedAt: observedAt)
        case .unavailable(let since): self = .unavailable(since: since)
        }
    }
}

/// KTD6.2 / U3: a meter row's one numeric input. The percentage, the fill and the severity
/// ink all read `display`, so the Mac row, the Mac capsule's Critical decision and the
/// phone cannot round one reading two ways — a binary `100 − 84.95` once made the Mac's
/// capsule turn Critical where the normalized phone value said Low.
public struct UsageMeterReading: Sendable, Equatable {
    /// The window as a row renders it: kind, reset schedule, freshness and provenance.
    public let window: UsageWindow
    /// Canonical normalized remaining. Nil only when the source number is not finite; the
    /// row then shows no figure rather than an invented 0% or 100%.
    public let display: UsageDisplayValue?
    /// Source-precision utilization when the source supplied one. Nil for a remaining-only
    /// row, so live-zero inferences that require exact source metadata cannot qualify on a
    /// value fabricated from rounded remaining.
    public let exactUtilization: Double?

    /// Mac: normalized from the actual provider window (decimal subtraction before rounding).
    public init(window: UsageWindow) {
        self.window = window
        self.display = UsageDisplayValue(window: window)
        self.exactUtilization = window.utilization.isFinite ? window.utilization : nil
    }

    /// Phone: normalized idempotently from the stored remaining. Running the source
    /// initializer on a fabricated `100 − remaining` can round differently (15.049999999999997
    /// remaining reads 15.0, but its fabricated 84.95 utilization reads 15.1).
    public init(widgetSummary summary: WidgetWindowSummary) {
        self.window = UsageWindow(widgetSummary: summary)
        self.display = UsageDisplayValue(percentRemaining: summary.percentRemaining)
        self.exactUtilization = summary.utilization
    }

    /// R2B2: an unavailable row keeps its slot but shows no figure and no fill.
    public var hidesValue: Bool { window.freshness.isUnavailable || display == nil }

    /// Severity from the normalized value. Retained on an unavailable row as hidden metadata;
    /// nil only when there is no finite value to classify.
    public var severity: UsageSeverity? { display?.severity }

    /// The mode's figure from the canonical remaining: Remaining → remaining, Used →
    /// `100 − remaining`. Nil when the row hides its value.
    public func percentage(for mode: UsagePercentageMode) -> Double? {
        guard !hidesValue, let display else { return nil }
        switch mode {
        case .remaining: return display.percentRemaining
        case .used: return 100 - display.percentRemaining
        }
    }

    /// The printed integer — the same `.rounded()` contract `UsagePercentageMode` keeps.
    public func roundedPercentage(for mode: UsagePercentageMode) -> Int? {
        percentage(for: mode).map { Int($0.rounded()) }
    }

    /// The gauge fill, 0 when the row hides its value.
    public func fraction(for mode: UsagePercentageMode) -> Double {
        (percentage(for: mode) ?? 0) / 100
    }

    /// AP1/PA8: critical ink is live-only. A dimmed or retained row keeps its severity as
    /// metadata but never paints it — the reading is no longer one Headroom stands behind.
    public func usesCriticalInk(dimmed: Bool) -> Bool {
        !dimmed && window.freshness.isLive && severity == .critical
    }
}
