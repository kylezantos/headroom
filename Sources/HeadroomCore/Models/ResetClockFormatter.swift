import Foundation

/// The absolute half of a reminder body: "today at 4:00 PM", "tomorrow at 9:00 AM",
/// "Sunday at 9:00 AM", or a short date ("Oct 7") a week or more out. KTD13: the
/// relative half stays with `Countdown`; this formats in the user's zone and locale,
/// both injected, because a source's own zone is provenance only.
public enum ResetClockFormatter {
    public static func phrase(
        for date: Date,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar suppliedCalendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var calendar = suppliedCalendar
        calendar.timeZone = timeZone
        calendar.locale = locale

        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? .max

        switch dayOffset {
        case 0:
            return "today at \(format(date, template: "jmm", calendar: calendar))"
        case 1:
            return "tomorrow at \(format(date, template: "jmm", calendar: calendar))"
        case 2...6:
            return "\(format(date, template: "EEEE", calendar: calendar)) at \(format(date, template: "jmm", calendar: calendar))"
        default:
            return format(date, template: "MMMd", calendar: calendar)
        }
    }

    /// The same grammar for a reset already behind us (default-login plan, R8). A weekday
    /// alone is ambiguous once the reset is more than six days past, so the calendar date
    /// takes over there.
    public static func pastPhrase(
        for date: Date,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar suppliedCalendar: Calendar = Calendar(identifier: .gregorian),
        compact: Bool = false
    ) -> String {
        var calendar = suppliedCalendar
        calendar.timeZone = timeZone
        calendar.locale = locale

        let daysAgo = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? .max
        let time = format(date, template: "jmm", calendar: calendar)

        // The short form for a row, which has no room for the sentence: "Wed 10:00 AM",
        // "Sep 18 10:00 AM". A short weekday covers today and yesterday too.
        if compact {
            let day = format(date, template: daysAgo > 6 ? "MMMd" : "EEE", calendar: calendar)
            return "\(day) \(time)"
        }

        switch daysAgo {
        case ...0:
            return "today at \(time)"
        case 1:
            return "yesterday at \(time)"
        case 2...6:
            return "\(format(date, template: "EEEE", calendar: calendar)) at \(time)"
        default:
            return "\(format(date, template: "MMMd", calendar: calendar)) at \(time)"
        }
    }

    private static func format(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
