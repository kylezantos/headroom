import Foundation

/// One widget timeline: when its entries render and when it asks WidgetKit to reload.
public struct CompanionTimeline: Equatable, Sendable {
    public let entryDates: [Date]
    public let reloadDate: Date
    /// The future moment this surface dims (KTD15); nil when it is already dimmed or the
    /// content has no Mac clock (demo, status states).
    public let dimsAt: Date?
}

/// U13 (iOS parity plan): widget timelines that cross into the dimmed and past-reset states
/// without an app launch (KTD15, R10, R11). WidgetKit only sees new data when it reloads, so
/// the schedule adds an entry at the surface's dim moment and at each shown window's reset
/// deadline plus the past-reset grace, on top of the minute-cadence countdown entries.
///
/// The reload is requested at the earlier of the regular refresh and the dim moment. A healthy
/// Mac's next reload therefore lands before anything could dim; the dim entry only renders
/// when the reload is late or the Mac really has gone quiet. The regular refresh stays, because
/// on the phone a reload is the only way a widget picks up new iCloud data.
public enum CompanionTimelineSchedule {
    public static func timeline(
        for envelope: WidgetSnapshotEnvelope?,
        freshness: CompanionFreshnessInputs?,
        surface: CompanionFreshnessSurface = .widget,
        now: Date
    ) -> CompanionTimeline {
        var dates = Set(WidgetTimelineSchedule.entryDates(for: envelope, now: now))
        for crossing in pastResetCrossings(envelope) where crossing >= now {
            dates.insert(crossing)
        }

        var reload = WidgetTimelineSchedule.refreshDate(after: now)
        var dimsAt: Date?
        if let freshness {
            let moment = CompanionFreshnessRule.dimsAt(freshness, surface: surface)
            if moment > now {
                dimsAt = moment
                dates.insert(moment)
                reload = min(reload, moment)
            }
        }
        return CompanionTimeline(entryDates: dates.sorted(), reloadDate: reload, dimsAt: dimsAt)
    }

    /// The moments a shown window's number hides (R11): its scheduled reset plus the grace,
    /// for windows that still show a number from a reading taken before that reset.
    static func pastResetCrossings(_ envelope: WidgetSnapshotEnvelope?) -> [Date] {
        guard let envelope else { return [] }
        return envelope.widgetProviders.flatMap(\.windows).compactMap { window in
            guard window.hasDisplayValue, let deadline = window.resetSchedule.deadline else { return nil }
            if let observed = window.observedAt ?? window.freshness.observedAt, observed >= deadline { return nil }
            return deadline.addingTimeInterval(CompanionFreshnessRule.pastResetGrace)
        }
    }
}
