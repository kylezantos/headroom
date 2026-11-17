import Foundation

/// The one Antigravity account signed in to the official `agy` CLI, read through its
/// no-turn `/usage` and `/credits` answers (`AntigravityUsageSource`). The provider only turns
/// a capture into a snapshot: it never spawns, reads a credential or calls Google itself.
public struct AntigravityProvider: UsageProvider {
    public let id = ProviderID.antigravity
    public let displayName = ProviderID.antigravity.displayName
    public let pollingLane: ProviderPollingLane = .serial("antigravity-cli")
    /// `agy` keeps its sign-in in its own home and the Keychain, and isolating a second
    /// account is unproven, so Antigravity stays single-account.
    public let accountCapacity = 1

    private let source: any AntigravityUsageSource
    private let locale: Locale
    private let now: @Sendable () -> Date

    public init(
        source: any AntigravityUsageSource,
        locale: Locale = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.locale = locale
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await source.capture() {
        case .usage(let usage):
            return UsageSnapshot(
                providerID: id,
                windows: Self.windows(for: usage.buckets),
                planLabel: creditsLabel(usage.credits),
                capturedAt: now(),
                freshness: .live
            )
        case .failed(let failure):
            // Providers never throw: the store's continuity keeps the last windows, dimmed.
            return .stale(for: id, reason: failure.failureReason)
        }
    }

    /// The row a bucket becomes. These labels are stored window IDs and must never change.
    /// Both pools use `.other` so their IDs cannot collide, and the ` 5h`/` weekly` suffixes
    /// give them their display names and reminders.
    public static func windowKind(_ pool: AntigravityPool, _ window: AntigravityWindow) -> WindowKind {
        let poolName = switch pool {
        case .gemini: "Gemini"
        case .claudeAndGPT: "Claude & GPT"
        }
        let windowName = switch window {
        case .fiveHour: "5h"
        case .weekly: "weekly"
        }
        return .other("\(poolName) \(windowName)")
    }

    /// Pools in the order the source first reports them, and within each pool the row with
    /// less left first, so a surface that shows one row per pool shows its tighter one. A tie
    /// keeps the source's order. A bucket the source omits has no row.
    static func windows(for buckets: [AntigravityBucket]) -> [UsageWindow] {
        var pools: [AntigravityPool] = []
        for bucket in buckets where !pools.contains(bucket.pool) { pools.append(bucket.pool) }
        return pools.flatMap { pool in
            buckets.enumerated()
                .filter { $0.element.pool == pool }
                .sorted { ($0.element.remainingFraction, $0.offset) < ($1.element.remainingFraction, $1.offset) }
                .map { window(for: $0.element) }
        }
    }

    private static func window(for bucket: AntigravityBucket) -> UsageWindow {
        UsageWindow(
            kind: windowKind(bucket.pool, bucket.window),
            utilization: min(100, max(0, (1 - bucket.remainingFraction) * 100)),
            resetSchedule: bucket.resetsAt.map(ResetSchedule.scheduled) ?? .unresolved(.absent)
        )
    }

    /// The AI-credits balance as a badge, only when above zero: zero or unavailable credits
    /// draw no badge.
    func creditsLabel(_ credits: Double?) -> String? {
        guard let credits, credits > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        guard let number = formatter.string(from: NSNumber(value: credits)) else { return nil }
        return credits == 1 ? "\(number) credit" : "\(number) credits"
    }
}
