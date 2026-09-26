import Foundation
import Testing
@testable import HeadroomCore

/// KTD13: the absolute reset phrase in a notification body.
struct ResetClockFormatterTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!
    private let locale = Locale(identifier: "en_US")
    /// Friday 25 Sep 2026, 10:00 AM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_790_355_600)
    private let hour: TimeInterval = 60 * 60

    /// Current ICU puts a narrow no-break space before AM/PM; compare on plain spaces.
    private func phrase(_ date: Date, zone: TimeZone? = nil) -> String {
        ResetClockFormatter.phrase(for: date, now: now, timeZone: zone ?? self.zone, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func sameDayReadsToday() {
        #expect(phrase(now.addingTimeInterval(6 * hour)) == "today at 4:00 PM")
        #expect(phrase(now.addingTimeInterval(13 * hour + 59 * 60)) == "today at 11:59 PM")
    }

    @Test func nextDayReadsTomorrow() {
        #expect(phrase(now.addingTimeInterval(23 * hour)) == "tomorrow at 9:00 AM")
        #expect(phrase(now.addingTimeInterval(14 * hour)) == "tomorrow at 12:00 AM")
    }

    @Test func withinTheWeekReadsTheWeekday() {
        #expect(phrase(now.addingTimeInterval(47 * hour)) == "Sunday at 9:00 AM")
        #expect(phrase(now.addingTimeInterval(6 * 24 * hour)) == "Thursday at 10:00 AM")
    }

    @Test func aWeekOrMoreOutReadsAShortDate() {
        #expect(phrase(now.addingTimeInterval(7 * 24 * hour)) == "Oct 2")
        #expect(phrase(now.addingTimeInterval(12 * 24 * hour)) == "Oct 7")
    }

    /// Source zones are provenance only: the phrase follows the user's zone.
    @Test func formatsInTheInjectedZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // 10:00 AM Friday in LA is 2:00 AM Saturday in Tokyo; +6h is 8:00 AM there.
        #expect(phrase(now.addingTimeInterval(6 * hour), zone: tokyo) == "today at 8:00 AM")
    }

    @Test func honoursTheInjectedLocaleForTheClock() {
        let text = ResetClockFormatter.phrase(
            for: now.addingTimeInterval(6 * hour),
            now: now,
            timeZone: zone,
            locale: Locale(identifier: "en_GB")
        )
        #expect(text == "today at 16:00")
    }
}
