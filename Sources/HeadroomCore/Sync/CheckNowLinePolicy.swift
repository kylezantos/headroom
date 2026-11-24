import Foundation

// iPhone parity U9 (R18, KTD14, KTD16): what the one slot under the phone's "Usage" title
// shows while a check-now request runs, and when it hands the slot back to the freshness
// line. Pure, so the hold and resume rules are tested without a SwiftUI host.

/// The slot's two occupants.
public enum CheckNowSlot: Equatable, Sendable {
    /// The request's line. `isInFlight` is the only time the loading row may show (KTD16).
    case checkNow(CheckNowLine, isInFlight: Bool)
    /// "Updated 2 min ago", or the dimmed "No update from your Mac since <time>".
    case freshness
}

public enum CheckNowLinePolicy {
    /// U9: "Just now" — and the other two ways a check completes, "Checked a moment ago" and
    /// "Checked · N accounts didn’t update" — hold this long, then the stamp returns.
    public static let completionHold: TimeInterval = 3

    /// A finished or cooldown answer: the request is done and the numbers are current.
    public static func isCompletion(_ phase: CheckNowPhase) -> Bool {
        switch phase {
        case .finished, .cooldown: true
        case .asking, .checking, .noAnswer, .notFinished: false
        }
    }

    /// `completedAt` is when this host first saw the status complete. The timeout lines stay
    /// until something changes them — a late answer resumes the request (AE2) and a new pull
    /// replaces it — because "Your Mac hasn’t answered" is still true until then.
    public static func slot(status: CheckNowStatus?, completedAt: Date?, now: Date) -> CheckNowSlot {
        guard let status else { return .freshness }
        if isCompletion(status.phase) {
            guard let completedAt, now < completedAt.addingTimeInterval(completionHold) else { return .freshness }
        }
        return .checkNow(status.line, isInFlight: status.isInFlight)
    }

    /// When the slot hands back to the freshness line on its own.
    public static func revertsAt(status: CheckNowStatus?, completedAt: Date?) -> Date? {
        guard let status, isCompletion(status.phase), let completedAt else { return nil }
        return completedAt.addingTimeInterval(completionHold)
    }

    /// When the host should next re-evaluate on its own: the earlier of the request's own
    /// timeout and the completion hold's end, counting only dates after `now`. Nil once nothing
    /// future remains. Review 2 #1: the hold's end stays fixed after it passes, so a host that
    /// re-armed on it would wake with no delay forever on the main actor.
    public static func nextWake(status: CheckNowStatus?, completedAt: Date?, now: Date) -> Date? {
        [status?.nextDeadline, revertsAt(status: status, completedAt: completedAt)]
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }

    /// CA-I2 (revisits "Approved F"'s 190pt slot): once the app dims, the header slot keeps
    /// only this short stamp, the widgets' own words (CA-W4), and the full "No update from
    /// your Mac since …" sentence gets its own line under the header, where it never clips.
    public static func dimmedStamp(since time: String) -> String {
        "Last update \(time)"
    }

    /// A launch (or the first update of a session) adopts a stored request only while it is
    /// still open, so yesterday's "Just now" or timeout never greets a fresh launch.
    public static func resumesAtLaunch(_ status: CheckNowStatus) -> Bool {
        switch status.phase {
        case .asking, .checking: true
        // Still answerable until the age limit; `nextDeadline` is nil once it has passed.
        case .noAnswer: status.nextDeadline != nil
        case .notFinished, .finished, .cooldown: false
        }
    }
}

/// Review #10: the phone starts a load from launch, foreground, URL opens, every KVS change,
/// demo switches and pulls, with no ordering between them. Only the latest-started load may
/// publish, so an older read that finishes last can never put stale numbers back on screen
/// or reload widgets with them. A direct adoption (a check's finished snapshot) supersedes
/// every load already in flight.
@MainActor
public final class CompanionLatestLoad<Value> {
    private var latest: UInt64 = 0

    public init() {}

    /// Runs `work` and returns its value only if no newer load or adoption started meanwhile.
    public func run(_ work: () async -> Value) async -> Value? {
        latest &+= 1
        let token = latest
        let value = await work()
        return token == latest ? value : nil
    }

    /// The caller is about to publish something newer than any load in flight.
    public func supersede() {
        latest &+= 1
    }
}
