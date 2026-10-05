import Foundation

/// U13 (iOS parity plan): the KTD15 freshness rules as one input to `WidgetStyleRecipe`, so
/// every style and family takes the dimmed and past-reset states from the recipe instead of
/// deciding them in a view (R10, R11).
///
/// - Past reset: ten minutes after a window's reset with no newer reading, the window goes
///   through the existing unavailable path — no numeral, no wash or fill, ranked last — and
///   its provider gets a "Reset at <time>" note.
/// - Dimmed: every window takes the stale treatment, which demotes numeral ink and fill
///   saturation. It is the per-row stale treatment applied once at the recipe, so the two
///   never stack, and nothing multiplies opacity.
public struct WidgetFreshnessTreatment: Sendable, Equatable {
    /// Which host draws the widget; it only changes copy.
    public enum Host: Sendable, Equatable {
        /// The Mac reads its own app's file: no "waiting for your Mac".
        case mac
        /// The phone reads what the Mac synced.
        case phone
    }

    /// The moment the past-reset rule is evaluated at; nil turns it off.
    public let now: Date?
    /// Set while the whole surface is dimmed: the time "No update … since" names.
    public let dimmedSince: Date?
    public let host: Host
    public let timeZone: TimeZone
    public let locale: Locale

    public init(
        now: Date?, dimmedSince: Date? = nil, host: Host = .mac,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) {
        self.now = now
        self.dimmedSince = dimmedSince
        self.host = host
        self.timeZone = timeZone
        self.locale = locale
    }

    /// No freshness rules: the recipe as the widget-styles round shipped it.
    public static let none = WidgetFreshnessTreatment(now: nil)

    /// A widget host's treatment at one timeline entry: the past-reset rule at `now`, and the
    /// widget floor of `CompanionFreshnessRule` for dimming (KTD15). Nil inputs (demo, or a
    /// payload with no Mac clock) never dim.
    public static func widget(
        inputs: CompanionFreshnessInputs?, now: Date, host: Host,
        surface: CompanionFreshnessSurface = .widget,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) -> WidgetFreshnessTreatment {
        let dimmedSince = inputs.flatMap {
            CompanionFreshnessRule.isDimmed($0, surface: surface, at: now) ? CompanionFreshnessRule.lastHeardFromMac($0) : nil
        }
        return WidgetFreshnessTreatment(now: now, dimmedSince: dimmedSince, host: host, timeZone: timeZone, locale: locale)
    }

    public var isDimmed: Bool { dimmedSince != nil }

    /// R10: the dimmed sentence, longest first; the caption tries each whole (WCF7).
    public var dimmedCaptions: [String] {
        guard let dimmedSince, let now else { return [] }
        let time = WidgetClockText.text(for: dimmedSince, now: now, timeZone: timeZone, locale: locale)
        let sentence = host == .phone
            ? CompanionFreshnessCopy.noUpdate(since: time)
            : "No update from Headroom since \(time)"
        return [sentence, "No update since \(time)", "Since \(time)"]
    }

    // MARK: Applying the rules

    /// The envelope every style lays out: past-reset windows made unavailable, then — while
    /// dimmed — every live window demoted to stale. Ranking, wash and fills follow from these
    /// window states, so no style decides them itself.
    func applied(to envelope: WidgetSnapshotEnvelope) -> WidgetSnapshotEnvelope {
        guard now != nil || isDimmed else { return envelope }
        let providers = envelope.providers.map { provider in
            var copy = provider
            copy.windows = provider.windows.map(applied(to:))
            return copy
        }
        return WidgetSnapshotEnvelope(
            schemaVersion: envelope.schemaVersion, generatedAt: envelope.generatedAt, status: envelope.status,
            providers: providers, apiSpendProviders: envelope.apiSpendProviders,
            widgetProviderSelection: envelope.widgetProviderSelection)
    }

    func applied(to window: WidgetWindowSummary) -> WidgetWindowSummary {
        if let resetAt = pastResetTime(window) {
            return window.madeUnavailable(since: resetAt)
        }
        return isDimmed ? window.demotedToStale() : window
    }

    /// R11: the reset time while the window's number is hidden.
    func pastResetTime(_ window: WidgetWindowSummary) -> Date? {
        guard let now, window.hasDisplayValue else { return nil }
        return CompanionFreshnessRule.pastResetTime(window, at: now)
    }

    /// The note for one shown provider: its most recent past reset, if any.
    func pastResetNote(for provider: WidgetProviderSummary, namesProvider: Bool) -> WidgetPastResetNote? {
        let crossed = provider.windows.compactMap { window in pastResetTime(window).map { (window, $0) } }
        guard let now, let (window, resetAt) = crossed.max(by: { $0.1 < $1.1 }) else { return nil }
        let time = WidgetClockText.text(for: resetAt, now: now, timeZone: timeZone, locale: locale)
        let named = namesProvider
            ? "\(provider.displayName) \(window.widgetDisplayLabel) reset at \(time)"
            : "\(window.widgetDisplayLabel) reset at \(time)"
        var captions = host == .phone ? ["\(named) · waiting for your Mac"] : []
        captions += [named, "Reset at \(time)"]
        return WidgetPastResetNote(providerID: provider.id, windowID: window.id, resetAt: resetAt, captions: captions)
    }
}

/// R11: one provider's "Reset at <time>" line, longest wording first.
public struct WidgetPastResetNote: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let windowID: String
    public let resetAt: Date
    public let captions: [String]
    public var id: String { providerID }
}

/// The clock time freshness copy names: "2:00 PM" today, "Fri 2:00 PM" within the week,
/// "Oct 2" before that. In the user's zone and locale, both injected for tests; a source's
/// own zone is provenance only (AGENTS.md).
public enum WidgetClockText {
    public static func text(for date: Date, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let template = switch days {
        case ...0: "jmm"
        case 1...6: "EEEjmm"
        default: "MMMd"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

extension WidgetWindowSummary {
    /// R11: a past-reset window takes the unavailable path; every other field is kept.
    func madeUnavailable(since date: Date) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: kind, label: label, percentRemaining: percentRemaining, utilization: utilization,
            resetSchedule: resetSchedule, resetLabel: resetLabel, resetTimeZoneIdentifier: resetTimeZoneIdentifier,
            observedAt: observedAt, severity: severity, freshness: .unavailable(since: date),
            billingPeriodDuration: billingPeriodDuration
        )
    }
}

public extension WidgetStyleRecipe {
    /// R10: the whole surface is dimmed; every window already carries the stale treatment.
    var isDimmed: Bool { freshness.isDimmed }
    /// R10: the dimmed sentence, longest first. Empty while not dimmed.
    var dimmedCaptions: [String] { freshness.dimmedCaptions }
    /// U13/KTD10: the "Reset at <time>" notes, fullest first — every note, then the first
    /// provider's alone. They are the first thing a widget drops, before any rail or row
    /// sheds; the window itself already reads "—" (R11), so the note only explains it.
    var pastResetNoteRungs: [[WidgetPastResetNote]] {
        guard let first = pastResetNotes.first else { return [] }
        return pastResetNotes.count > 1 ? [pastResetNotes, [first]] : [[first]]
    }
}
