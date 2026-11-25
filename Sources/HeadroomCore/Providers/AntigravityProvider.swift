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
    /// A timer probe can answer from the source's sticky signed-out or stopped state, so a
    /// Check Now that lands during one gets its own fresh read, as Copilot does.
    public let reusesCachedStatusOnTimerProbes = true

    private let source: any AntigravityUsageSource
    private let gpuCreditsSource: (any AntigravityGPUCreditsSource)?
    private let gpuCreditsMode: @Sendable () -> AntigravityGPUCreditsMode
    private let colabTier: @Sendable () -> ColabComputeTier
    private let gpuCreditsRefillDay: @Sendable () -> Int?
    private let locale: Locale
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        source: any AntigravityUsageSource,
        gpuCreditsSource: (any AntigravityGPUCreditsSource)? = nil,
        gpuCreditsMode: @escaping @Sendable () -> AntigravityGPUCreditsMode = { .off },
        colabTier: @escaping @Sendable () -> ColabComputeTier = { .aiUltra },
        gpuCreditsRefillDay: @escaping @Sendable () -> Int? = { nil },
        locale: Locale = .current,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.gpuCreditsSource = gpuCreditsSource
        self.gpuCreditsMode = gpuCreditsMode
        self.colabTier = colabTier
        self.gpuCreditsRefillDay = gpuCreditsRefillDay
        self.locale = locale
        self.calendar = calendar
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await source.capture() {
        case .usage(let usage):
            let capturedAt = now()
            var resultWindows = Self.windows(for: usage.buckets)
            if gpuCreditsMode() != .off,
               let gpuCreditsSource,
               case .balance(let credits) = await gpuCreditsSource.capture()
            {
                resultWindows.append(
                    Self.gpuCreditsWindow(
                        credits: credits,
                        tier: colabTier(),
                        refillDay: gpuCreditsRefillDay(),
                        now: capturedAt,
                        calendar: calendar
                    )
                )
            }
            return UsageSnapshot(
                providerID: id,
                windows: resultWindows,
                planLabel: creditsLabel(usage.credits),
                capturedAt: capturedAt,
                freshness: .live
            )
        case .failed(let failure):
            return .stale(for: id, reason: failure.failureReason)
        }
    }

    static func gpuCreditsWindow(
        credits: AntigravityGPUCredits,
        tier: ColabComputeTier,
        refillDay: Int?,
        now: Date,
        calendar: Calendar = .current
    ) -> UsageWindow {
        let capacity = max(1, tier.threeMonthCapacity)
        let remainingFraction = min(1, max(0, credits.balanceUnits / capacity))
        let utilization = min(100, max(0, (1 - remainingFraction) * 100))
        let nextRefill = refillDay.flatMap {
            AntigravityGPUCreditsWindow.nextMonthlyRefillDate(day: $0, after: now, calendar: calendar)
        }
        return UsageWindow(
            kind: AntigravityGPUCreditsWindow.windowKind,
            utilization: utilization,
            resetSchedule: nextRefill.map(ResetSchedule.scheduled) ?? .unresolved(.absent)
        )
    }

    /// The row a bucket becomes. These labels are stored window IDs and must never change.
    /// Both pools use `.other` so their IDs cannot collide, and the ` 5h`/` weekly` suffixes
    /// give them their display names and reminders. The Claude and GPT pool is "Other", as
    /// Cursor names its second pool, so the Standard card's "Other · Weekly" fits untruncated.
    public static func windowKind(_ pool: AntigravityPool, _ window: AntigravityWindow) -> WindowKind {
        let labelPool: AntigravityRowLabels.Pool = switch pool {
        case .gemini: .gemini
        case .claudeAndGPT: .other
        }
        let labelWindow: AntigravityRowLabels.Window = switch window {
        case .fiveHour: .fiveHour
        case .weekly: .weekly
        }
        return .other(AntigravityRowLabels.stored(labelPool, labelWindow))
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
