import Foundation

/// One OpenCode account's Go allowance, read through the official 2.x client's own usage
/// read (`OpenCodeUsageSource`, KTD1). The provider only turns a capture into a snapshot: it
/// never spawns, reads a credential or calls OpenCode itself (R5).
public struct OpenCodeProvider: UsageProvider {
    public let id = ProviderID.opencode
    public let accountID: AccountID
    public let displayName = ProviderID.opencode.displayName
    /// KTD12: its own serial lane behind the measured duty-cycle gate.
    public let pollingLane: ProviderPollingLane = .serial("opencode-cli")

    /// KTD6: the fixed 30-day duration Copilot's monthly meter uses (Copilot KTD8).
    public static let monthlyKind = WindowKind.billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60)

    private let source: any OpenCodeUsageSource
    private let home: OpenCodeAccountHome
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - source: one shared `OpenCodeUsageCaptureCache` in the app (KTD8), so a user request
    ///     during a timer probe joins the read already running for the same home.
    ///   - home: required, with no default: an extra account must never fall back to the
    ///     built-in home and silently read another workspace (KTD10, AGENTS.md isolation).
    public init(
        source: any OpenCodeUsageSource,
        accountID: AccountID = .primary,
        home: OpenCodeAccountHome,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.accountID = accountID
        self.home = home
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await source.capture(home: home) {
        case .goUsage(let usage):
            return reading(usage)
        case .noGoPlan:
            return noGoPlan(at: now())
        case .failed(let failure):
            // Providers never throw: the store's continuity keeps the last windows, now
            // dimmed, and `planStatus` with them (KTD7).
            return .stale(for: id, reason: failure.failureReason)
        }
    }

    /// KTD6: by name, in the order the card reads them. A limited window already reads 100%
    /// (U2); `isLimited` keeps the source's own word for the limited sentence (D3).
    private func reading(_ usage: OpenCodeGoUsage) -> UsageSnapshot {
        let windows = [
            window(.fiveHour, usage.rolling),
            window(.weekly, usage.weekly),
            window(Self.monthlyKind, usage.monthly),
        ]
        // KTD19: no plan label, workspace name or email. A Go reading clears any earlier
        // no-Go status by carrying none.
        return UsageSnapshot(providerID: id, windows: windows, planLabel: nil, capturedAt: now(), freshness: .live)
    }

    private func window(_ kind: WindowKind, _ go: OpenCodeGoWindow) -> UsageWindow {
        UsageWindow(
            kind: kind,
            utilization: go.percentUsed,
            resetSchedule: .scheduled(go.resetsAt),
            isLimited: go.isLimited
        )
    }

    /// KTD7: live so setup completes, with one Monthly row rather than none because the Lock
    /// Screen reads an empty snapshot as still loading. `since` is the UTC month start, so the
    /// row is identical between polls and the phone's key is not rewritten. The row prints no
    /// number anywhere; the card draws the `planStatus` sentence and button instead (D2).
    private func noGoPlan(at now: Date) -> UsageSnapshot {
        let monthStart = CopilotLedgerCalculator.utcMonth(containing: now).lowerBound
        let window = UsageWindow(
            kind: Self.monthlyKind,
            utilization: 0,
            resetSchedule: .unresolved(.absent),
            freshness: .unavailable(since: monthStart)
        )
        return UsageSnapshot(
            providerID: id,
            windows: [window],
            planLabel: nil,
            capturedAt: now,
            freshness: .live,
            planStatus: .noActivePlan
        )
    }
}
