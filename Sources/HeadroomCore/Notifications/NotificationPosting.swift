import Foundation

/// KTD1: the one seam between Core's notification decisions and the system. Core never
/// imports UserNotifications; the app supplies the adapter, tests a recording fake.
public protocol NotificationPosting: Sendable {
    /// Hands one request to the system. True only when it was accepted: a denied,
    /// unavailable, or failed post returns false, so nothing is marked fired (KTD6).
    func post(_ content: NotificationContent) async -> Bool
}

/// KTD9: the poster for every process that must never touch the notification center —
/// `swift run`, `--demo`, `--render-popover`, and hosted tests. It accepts nothing, so
/// the ledgers stay untouched and a later bundled run can still fire.
public struct InertNotificationPoster: NotificationPosting {
    public init() {}

    public func post(_ content: NotificationContent) async -> Bool { false }
}
