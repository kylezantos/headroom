import Foundation

/// R5/KTD9: visible user work excludes setup verification, even when the scheduler still
/// retains that work alongside a completed account action. Its hold has its own clock.
public struct VisibleRefreshWork: Sendable, Equatable {
    public let isInFlight: Bool
    public let clearedAt: Date?

    public init(isInFlight: Bool = false, clearedAt: Date? = nil) {
        self.isInFlight = isInFlight
        self.clearedAt = clearedAt
    }
}

/// The reason a key joined user work (loading-language KTD1–KTD3). Timer probes have no
/// entry unless they satisfy a request that arrived while they were already running.
public enum UserRefreshOrigin: Sendable, Hashable {
    case fullRefresh
    case accountAction
    case setupCheck
}

public enum UserRefreshOutcome: Sendable, Equatable {
    case live
    case stale
    case dropped
}

public struct UserRefreshEntry: Sendable, Equatable {
    public var origin: UserRefreshOrigin
    public var requestedAt: Date
    public var outcome: UserRefreshOutcome?
    public var landedAt: Date?

    public init(origin: UserRefreshOrigin, requestedAt: Date, outcome: UserRefreshOutcome? = nil, landedAt: Date? = nil) {
        self.origin = origin
        self.requestedAt = requestedAt
        self.outcome = outcome
        self.landedAt = landedAt
    }
}

public struct UserRefreshRun: Sendable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public var entries: [AccountKey: UserRefreshEntry]
    /// The hold starts after all user work, including spend, drains (KTD1, KTD9).
    public var refreshingClearedAt: Date?

    public init(id: UUID = UUID(), startedAt: Date, entries: [AccountKey: UserRefreshEntry] = [:], refreshingClearedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.entries = entries
        self.refreshingClearedAt = refreshingClearedAt
    }
}
