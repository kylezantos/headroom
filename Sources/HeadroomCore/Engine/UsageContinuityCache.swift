import Foundation

/// Redaction-safe persistence for last-known subscription windows. This cache stores
/// only display-ready values keyed by provider/account — usage numbers plus the plan
/// label and account email the UI already shows; credentials, raw provider responses,
/// CLI output, paths, and failure details never cross this boundary.
public protocol UsageContinuityCaching: Sendable {
    func load() -> [AccountKey: UsageSnapshot]
    func save(_ snapshot: UsageSnapshot, for key: AccountKey)
    func remove(for key: AccountKey)
}

/// UserDefaults-backed continuity across app launches. `UsageStore` still owns freshness
/// and expiry decisions; this type only round-trips bounded, non-secret snapshot data.
public struct UsageContinuityCache: UsageContinuityCaching, @unchecked Sendable {
    private static let storageKey = "usageContinuitySnapshots.v2"
    private static let legacyStorageKey = "usageContinuitySnapshots.v1"
    private static let maximumRecords = 64

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [AccountKey: UsageSnapshot] {
        let stored: [StoredSnapshot]
        switch recordState() {
        case .records(let records):
            stored = records
        case .legacy(let records):
            stored = records.map(StoredSnapshot.init)
            write(stored)
        case .missing, .blocked:
            stored = []
        }
        return Dictionary(
            stored.compactMap { record in
                guard let snapshot = record.snapshot else { return nil }
                return (record.key, snapshot)
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    public func save(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard snapshot.providerID == key.providerID else { return }
        guard var stored = writableRecords() else { return }
        stored.removeAll { $0.key == key }
        if !snapshot.windows.isEmpty {
            stored.append(StoredSnapshot(key: key, snapshot: snapshot))
        }
        write(Array(stored.suffix(Self.maximumRecords)))
    }

    public func remove(for key: AccountKey) {
        guard let stored = writableRecords() else { return }
        write(stored.filter { $0.key != key })
    }

    private func writableRecords() -> [StoredSnapshot]? {
        switch recordState() {
        case .records(let records):
            return records
        case .legacy(let records):
            return records.map(StoredSnapshot.init)
        case .missing:
            return []
        case .blocked:
            return nil
        }
    }

    private func recordState() -> StoredRecordState {
        if let data = defaults.data(forKey: Self.storageKey) {
            guard let header = try? JSONDecoder().decode(StoredEnvelopeHeader.self, from: data),
                  header.schemaVersion == StoredEnvelope.currentSchemaVersion,
                  let envelope = try? JSONDecoder().decode(StoredEnvelope.self, from: data)
            else { return .blocked }
            return .records(envelope.records)
        }
        guard let data = defaults.data(forKey: Self.legacyStorageKey),
              let records = try? JSONDecoder().decode([LegacyStoredSnapshot].self, from: data)
        else {
            return defaults.data(forKey: Self.legacyStorageKey) == nil ? .missing : .blocked
        }
        return .legacy(records)
    }

    private func write(_ records: [StoredSnapshot]) {
        guard let data = try? JSONEncoder().encode(StoredEnvelope(records: records)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

private enum StoredRecordState {
    case missing
    case blocked
    case records([StoredSnapshot])
    case legacy([LegacyStoredSnapshot])
}

private struct StoredEnvelopeHeader: Decodable {
    let schemaVersion: Int
}

private struct StoredEnvelope: Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let records: [StoredSnapshot]

    init(records: [StoredSnapshot]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.records = records
    }
}

private struct StoredSnapshot: Codable {
    let key: AccountKey
    let windows: [StoredWindow]
    let planLabel: String?
    /// Persisted alongside the plan label so a relaunch still names the account before
    /// the first poll lands. Optional, so records written by earlier builds still decode.
    let accountEmail: String?
    /// Same continuity as `planLabel`. Optional, and the envelope stays at schema 2:
    /// a missing key is nil, and a later build's unknown keys are ignored on rollback (KTD2).
    let bankedResets: Int?
    let capturedAt: Date?

    init(key: AccountKey, snapshot: UsageSnapshot) {
        self.key = key
        self.windows = snapshot.windows.map(StoredWindow.init)
        self.planLabel = snapshot.planLabel
        self.accountEmail = snapshot.accountEmail
        self.bankedResets = snapshot.bankedResets
        self.capturedAt = snapshot.capturedAt
    }

    init(_ legacy: LegacyStoredSnapshot) {
        self.key = legacy.key
        self.windows = legacy.windows.map {
            StoredWindow($0, providerID: legacy.key.providerID, capturedAt: legacy.capturedAt)
        }
        self.planLabel = legacy.planLabel
        self.accountEmail = legacy.accountEmail
        self.bankedResets = nil
        self.capturedAt = legacy.capturedAt
    }

    var snapshot: UsageSnapshot? {
        let restoredWindows = windows.compactMap(\.usageWindow)
        guard !restoredWindows.isEmpty, restoredWindows.count == windows.count else { return nil }
        return UsageSnapshot(
            providerID: key.providerID,
            windows: restoredWindows,
            planLabel: planLabel,
            accountEmail: accountEmail,
            bankedResets: bankedResets,
            capturedAt: capturedAt,
            freshness: .stale(.transient("Last known usage — refreshing"))
        )
    }
}

private enum StoredWindowKind: String, Codable {
    case fiveHour
    case weekly
    case billingPeriod
    case other
}

private struct StoredWindow: Codable {
    private let kind: StoredWindowKind
    let otherLabel: String?
    let billingPeriodDuration: TimeInterval?
    let utilization: Double
    let reset: StoredResetEvidence
    let resetLabel: String?
    let resetTimeZoneIdentifier: String?
    let observedAt: Date?
    let staleObservedAt: Date?
    let unavailableSince: Date?

    init(_ window: UsageWindow) {
        switch window.kind {
        case .fiveHour:
            self.kind = .fiveHour
            self.otherLabel = nil
            self.billingPeriodDuration = nil
        case .weekly:
            self.kind = .weekly
            self.otherLabel = nil
            self.billingPeriodDuration = nil
        case .billingPeriod(let label, let duration):
            self.kind = .billingPeriod
            self.otherLabel = label
            self.billingPeriodDuration = duration
        case .other(let label):
            self.kind = .other
            self.otherLabel = label
            self.billingPeriodDuration = nil
        }
        self.utilization = window.utilization
        self.reset = StoredResetEvidence(window.resetSchedule)
        self.resetLabel = window.resetLabel
        self.resetTimeZoneIdentifier = window.resetTimeZoneIdentifier
        self.observedAt = window.observedAt ?? window.freshness.observedAt
        switch window.freshness {
        case .live:
            self.staleObservedAt = nil
            self.unavailableSince = nil
        case .stale(let observedAt):
            self.staleObservedAt = observedAt
            self.unavailableSince = nil
        case .unavailable(let since):
            self.staleObservedAt = nil
            self.unavailableSince = since
        }
    }

    init(_ legacy: LegacyStoredWindow, providerID: ProviderID, capturedAt: Date?) {
        self.kind = legacy.kind
        self.otherLabel = legacy.otherLabel
        self.billingPeriodDuration = legacy.billingPeriodDuration
        self.utilization = legacy.utilization
        self.reset = StoredResetEvidence(
            LegacyResetClassifier.schedule(
                providerID: providerID,
                resetsAt: legacy.resetsAt,
                capturedAt: capturedAt
            )
        )
        self.resetLabel = legacy.resetLabel
        self.resetTimeZoneIdentifier = nil
        self.observedAt = legacy.staleObservedAt
        self.staleObservedAt = legacy.unavailableSince == nil
            ? (legacy.staleObservedAt ?? capturedAt)
            : nil
        self.unavailableSince = legacy.unavailableSince
    }

    var usageWindow: UsageWindow? {
        guard utilization.isFinite else { return nil }
        let restoredKind: WindowKind
        switch kind {
        case .fiveHour:
            restoredKind = .fiveHour
        case .weekly:
            restoredKind = .weekly
        case .billingPeriod:
            guard let otherLabel, !otherLabel.isEmpty,
                  let billingPeriodDuration,
                  billingPeriodDuration.isFinite,
                  billingPeriodDuration > 0
            else { return nil }
            restoredKind = .billingPeriod(label: otherLabel, duration: billingPeriodDuration)
        case .other:
            guard let otherLabel, !otherLabel.isEmpty else { return nil }
            restoredKind = .other(otherLabel)
        }
        guard let resetSchedule = reset.schedule else { return nil }
        return UsageWindow(
            kind: restoredKind,
            utilization: utilization,
            resetSchedule: resetSchedule,
            resetLabel: resetLabel,
            resetTimeZoneIdentifier: resetTimeZoneIdentifier,
            freshness: unavailableSince.map(UsageWindowFreshness.unavailable(since:))
                ?? staleObservedAt.map(UsageWindowFreshness.stale(observedAt:))
                ?? .live,
            observedAt: observedAt
        )
    }
}

private struct StoredResetEvidence: Codable {
    private enum Kind: String, Codable {
        case scheduled
        case unresolved
    }

    private let kind: Kind
    private let deadline: Date?
    private let reason: String?

    init(_ schedule: ResetSchedule) {
        switch schedule {
        case .scheduled(let deadline):
            self.kind = .scheduled
            self.deadline = deadline
            self.reason = nil
        case .unresolved(let reason):
            self.kind = .unresolved
            self.deadline = nil
            self.reason = reason.rawValue
        }
    }

    var schedule: ResetSchedule? {
        switch kind {
        case .scheduled:
            guard let deadline, reason == nil else { return nil }
            return .scheduled(deadline)
        case .unresolved:
            guard deadline == nil,
                  let reason,
                  let decodedReason = ResetUnresolvedReason(rawValue: reason)
            else { return nil }
            return .unresolved(decodedReason)
        }
    }
}

private struct LegacyStoredSnapshot: Codable {
    let key: AccountKey
    let windows: [LegacyStoredWindow]
    let planLabel: String?
    let accountEmail: String?
    let capturedAt: Date?
}

private struct LegacyStoredWindow: Codable {
    let kind: StoredWindowKind
    let otherLabel: String?
    let billingPeriodDuration: TimeInterval?
    let utilization: Double
    let resetsAt: Date
    let resetLabel: String?
    let staleObservedAt: Date?
    let unavailableSince: Date?
}

/// Pure freshness and expiry policy shared by launch restoration and live merges.
/// Keeping the state machine here prevents provider-specific continuity rules from
/// spreading through the observable store.
enum UsageContinuityPolicy {
    static func restoredSnapshot(
        _ cached: UsageSnapshot?,
        for providerID: ProviderID,
        at restorationDate: Date
    ) -> UsageSnapshot {
        guard let cached, cached.providerID == providerID else {
            return .pending(for: providerID)
        }
        let windows = cached.windows.compactMap {
            restoredWindow(
                $0,
                providerID: providerID,
                capturedAt: cached.capturedAt,
                at: restorationDate
            )
        }
        guard !windows.isEmpty else { return .pending(for: providerID) }
        return UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: cached.planLabel,
            accountEmail: cached.accountEmail,
            bankedResets: cached.bankedResets,
            capturedAt: cached.capturedAt,
            freshness: .stale(.transient("Last known usage — refreshing"))
        )
    }

    static func mergedSnapshot(
        _ fresh: UsageSnapshot,
        with prior: UsageSnapshot?,
        at mergeDate: Date
    ) -> UsageSnapshot {
        if case .stale(let reason) = fresh.freshness,
           fresh.windows.isEmpty,
           let prior,
           !prior.windows.isEmpty {
            return snapshotByRetainingValidWindows(prior, reason: reason, at: mergeDate)
        }
        guard fresh.providerID == .claude,
              fresh.freshness == .live,
              let prior
        else {
            return fresh
        }
        return preservingClaudeWeeklySubLimits(in: fresh, from: prior)
    }

    private static func snapshotByRetainingValidWindows(
        _ prior: UsageSnapshot,
        reason: FailureReason,
        at mergeDate: Date
    ) -> UsageSnapshot {
        let windows = prior.windows.compactMap { window in
            restoredWindow(
                window,
                providerID: prior.providerID,
                capturedAt: prior.capturedAt,
                at: mergeDate
            )
        }
        return UsageSnapshot(
            providerID: prior.providerID,
            windows: windows,
            planLabel: prior.planLabel,
            accountEmail: prior.accountEmail,
            bankedResets: prior.bankedResets,
            capturedAt: prior.capturedAt,
            freshness: .stale(reason)
        )
    }

    private static func continuityExpiryDate(
        for window: UsageWindow,
        providerID: ProviderID,
        capturedAt: Date
    ) -> Date {
        switch window.resetSchedule {
        case .scheduled(let deadline):
            return deadline
        case .unresolved:
            // Copilot's allowance resets at the start of each UTC month even when no reading
            // said so. The generic 30-day lifetime would keep last month's number on screen
            // for most of this one after a failed poll.
            if providerID == .copilot {
                return CopilotLedgerCalculator.utcMonth(containing: capturedAt).upperBound
            }
            return capturedAt.addingTimeInterval(ResetSchedulePolicy.fallbackLifetime(for: window.kind))
        }
    }

    private static func restoredWindow(
        _ window: UsageWindow,
        providerID: ProviderID,
        capturedAt: Date?,
        at restorationDate: Date
    ) -> UsageWindow? {
        if case .unavailable(let since) = window.freshness {
            return restorationDate.timeIntervalSince(since) < ResetSchedulePolicy.fallbackLifetime(for: window.kind)
                ? window
                : nil
        }

        guard let observedAt = window.observedAt ?? window.freshness.observedAt ?? capturedAt else {
            return nil
        }
        let expiredAt = continuityExpiryDate(
            for: window,
            providerID: providerID,
            capturedAt: observedAt
        )
        if expiredAt > restorationDate {
            return window.withFreshness(.stale(observedAt: observedAt))
        }
        guard (isClaudeWeeklySubLimit(window, providerID: providerID) || window.kind.isBillingPeriod),
              restorationDate.timeIntervalSince(expiredAt) < ResetSchedulePolicy.fallbackLifetime(for: window.kind)
        else {
            return nil
        }
        return window.withFreshness(.unavailable(since: expiredAt))
    }

    /// Claude's primary limits remain fresh while a separately rate-limited model
    /// breakdown is retained as last-known. Once invalid, the old percentage is hidden
    /// behind an unavailable row for one bounded lifetime before the row disappears.
    private static func preservingClaudeWeeklySubLimits(
        in fresh: UsageSnapshot,
        from prior: UsageSnapshot
    ) -> UsageSnapshot {
        guard fresh.windows.contains(where: { $0.kind == .weekly }),
              let capturedAt = fresh.capturedAt
        else {
            return fresh
        }
        let freshKinds = Set(fresh.windows.map(\.kind))
        let retained = prior.windows.compactMap { window -> UsageWindow? in
            guard isClaudeWeeklySubLimit(window, providerID: fresh.providerID),
                  !freshKinds.contains(window.kind)
            else {
                return nil
            }
            if case .unavailable(let since) = window.freshness {
                return capturedAt.timeIntervalSince(since) < ResetSchedulePolicy.fallbackLifetime(for: window.kind)
                    ? window
                    : nil
            }
            guard let observedAt = window.observedAt ?? window.freshness.observedAt ?? prior.capturedAt else {
                return nil
            }
            let expiredAt = continuityExpiryDate(
                for: window,
                providerID: fresh.providerID,
                capturedAt: observedAt
            )
            if expiredAt > capturedAt {
                return window.withFreshness(.stale(observedAt: observedAt))
            }
            return capturedAt.timeIntervalSince(expiredAt) < ResetSchedulePolicy.fallbackLifetime(for: window.kind)
                ? window.withFreshness(.unavailable(since: expiredAt))
                : nil
        }
        guard !retained.isEmpty else { return fresh }
        return UsageSnapshot(
            providerID: fresh.providerID,
            windows: fresh.windows + retained,
            planLabel: fresh.planLabel,
            accountEmail: fresh.accountEmail,
            bankedResets: fresh.bankedResets,
            capturedAt: fresh.capturedAt,
            freshness: .live
        )
    }

    private static func isClaudeWeeklySubLimit(
        _ window: UsageWindow,
        providerID: ProviderID
    ) -> Bool {
        guard providerID == .claude,
              case .other(let label) = window.kind
        else {
            return false
        }
        return label.localizedCaseInsensitiveContains("weekly")
    }

}

private extension WindowKind {
    var isBillingPeriod: Bool {
        if case .billingPeriod = self { return true }
        return false
    }
}
