import Foundation

/// R2M5 / U3: the popover footer's freshness stamp, lifted out of `PopoverView` so the phone
/// states the age of its numbers with the same aggregation and the same words. Pure: no
/// setup session, store or account traversal — the Mac keeps those and hands in snapshots.
///
/// A number you cannot date is a number you cannot trust, so the stamp always says
/// something: the age of the least-fresh live reading, otherwise when anything was last
/// checked, otherwise that nothing has been.
public struct FreshnessStamp: Sendable, Equatable {
    /// The line's identity. An age and a "Checked" line are different lines, not one value
    /// that changed, so a host can crossfade on `kind` and roll digits on `rollValue`.
    public enum Kind: Sendable, Hashable {
        case updated
        case lastChecked
        case never
    }

    public let kind: Kind
    public let text: String
    /// M2A: whole minutes since the anchor, which only grows between readings so the digits
    /// roll upward. Nil where there are no digits to roll.
    public let rollValue: Double?

    public init(kind: Kind, text: String, rollValue: Double?) {
        self.kind = kind
        self.text = text
        self.rollValue = rollValue
    }

    public static let notCheckedText = "Not checked yet"

    /// The two dates the stamp is decided from, aggregated separately from the wording so
    /// each half is testable on its own.
    public struct Anchors: Sendable, Equatable {
        /// Oldest live reading across every account, so the stamp never claims data is
        /// fresher than the least-fresh one on screen.
        public var oldestLive: Date?
        /// Newest observation of any kind, live or retained — the answer to "when was this
        /// last checked" once nothing is live.
        public var newestCheck: Date?

        public init(oldestLive: Date? = nil, newestCheck: Date? = nil) {
            self.oldestLive = oldestLive
            self.newestCheck = newestCheck
        }

        /// A live snapshot contributes its oldest live window's own observation anchor,
        /// falling back to the snapshot's capture time for a window that carries none (the
        /// Mac's provider rows) — so a synced row keeps the source time it was read at rather
        /// than the time it was published. Retained windows inside a live snapshot are not
        /// live readings and do not drag the age back.
        ///
        /// Anything else contributes only to `newestCheck`, from the newest retained window
        /// anchor (which survives stale and unavailable transitions) or the capture time.
        /// Each retained row keeps its own anchor; none is restamped with a sibling's newer one.
        public init(snapshots: some Sequence<UsageSnapshot>) {
            self.init()
            for snapshot in snapshots {
                if case .live = snapshot.freshness, let live = Self.liveAnchor(of: snapshot) {
                    oldestLive = oldestLive.map { min($0, live) } ?? live
                    let newest = Self.newestLiveAnchor(of: snapshot) ?? live
                    newestCheck = newestCheck.map { max($0, newest) } ?? newest
                    continue
                }
                if let observed = Self.retainedAnchor(of: snapshot) {
                    newestCheck = newestCheck.map { max($0, observed) } ?? observed
                }
            }
        }

        private static func liveWindowAnchors(of snapshot: UsageSnapshot) -> [Date] {
            snapshot.windows
                .filter(\.freshness.isLive)
                .compactMap { $0.observedAt ?? snapshot.capturedAt }
        }

        private static func liveAnchor(of snapshot: UsageSnapshot) -> Date? {
            liveWindowAnchors(of: snapshot).min() ?? snapshot.capturedAt
        }

        private static func newestLiveAnchor(of snapshot: UsageSnapshot) -> Date? {
            liveWindowAnchors(of: snapshot).max() ?? snapshot.capturedAt
        }

        private static func retainedAnchor(of snapshot: UsageSnapshot) -> Date? {
            snapshot.windows.compactMap(\.observedAt).max() ?? snapshot.capturedAt
        }
    }

    /// Beside the control that changes it the age needs no "Updated" verb; "Checked" survives
    /// only to mark retained numbers, where nothing on screen is live.
    public static func resolve(_ anchors: Anchors, now: Date) -> FreshnessStamp {
        if let oldest = anchors.oldestLive,
           let label = Countdown.updatedLabel(capturedAt: oldest, now: now) {
            return FreshnessStamp(
                kind: .updated,
                text: capitalizedFirst(label),
                rollValue: elapsedMinutes(since: oldest, now: now)
            )
        }
        if let newest = anchors.newestCheck,
           let label = Countdown.updatedLabel(capturedAt: newest, now: now) {
            return FreshnessStamp(
                kind: .lastChecked,
                text: "Checked \(label)",
                rollValue: elapsedMinutes(since: newest, now: now)
            )
        }
        return FreshnessStamp(kind: .never, text: notCheckedText, rollValue: nil)
    }

    public static func resolve(snapshots: some Sequence<UsageSnapshot>, now: Date) -> FreshnessStamp {
        resolve(Anchors(snapshots: snapshots), now: now)
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func elapsedMinutes(since date: Date, now: Date) -> Double {
        (max(0, now.timeIntervalSince(date)) / 60).rounded(.down)
    }
}
