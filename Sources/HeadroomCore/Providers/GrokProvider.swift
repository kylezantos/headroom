import Foundation

public struct GrokProvider: UsageProvider {
    public let id = ProviderID.grok
    public let accountID: AccountID
    public let displayName = "Grok"
    public let pollingLane: ProviderPollingLane = .serial("grok-cli")

    private let source: any GrokUsageSource
    private let emailSource: (any GrokAccountEmailReading)?
    private let now: @Sendable () -> Date

    public init(
        source: any GrokUsageSource,
        accountID: AccountID = .primary,
        emailSource: (any GrokAccountEmailReading)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.accountID = accountID
        // Nil by default for every account: a default initializer must never read a real
        // credential file unasked (tests and diagnostics construct providers directly,
        // and a `.primary` fallback here silently read the wrong home when --probe-grok
        // targeted an isolated account). `AppComposition` — the one place providers are
        // wired — supplies the account-scoped reader.
        self.emailSource = emailSource
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await source.fetchUsage() {
        case .payload(let data, _): return decode(data)
        case .methodUnavailable: return stale(.providerSetup(.grokTransientCapture))
        case .cliNotFound: return stale(.providerSetup(.grokCLIMissing))
        case .authAbsent: return stale(.providerSetup(.grokAuthAbsent))
        case .authPermissionDenied: return stale(.providerSetup(.grokPermissionDenied))
        case .authUnsafePermissions: return stale(.providerSetup(.grokUnsafePermissions))
        case .authMalformed: return stale(.providerSetup(.grokMalformedAuth))
        case .authIOFailure: return stale(.providerSetup(.grokCredentialIO))
        case .rejectedAuth: return stale(.providerSetup(.grokRejectedAuth))
        case .failure(let reason): return stale(reason)
        }
    }

    private func decode(_ body: Data) -> UsageSnapshot {
        guard let normalized = Self.normalizedPayload(body),
              let dto = try? JSONDecoder().decode(GrokBillingResponseDTO.self, from: normalized),
              let config = dto.config,
              let window = usageWindow(config)
        else { return stale(.decode("Couldn’t read Grok usage response")) }

        return UsageSnapshot(
            providerID: id,
            windows: [window],
            planLabel: dto.subscriptionTier,
            accountEmail: emailSource?.readAccountEmail(),
            capturedAt: now(),
            freshness: .live
        )
    }

    private func usageWindow(_ config: GrokBillingConfigDTO) -> UsageWindow? {
        let period = config.currentPeriod
        let start = DateParsing.iso8601(period?.start ?? config.billingPeriodStart)
        guard let end = DateParsing.iso8601(period?.end ?? config.billingPeriodEnd) else {
            // Scheduled reset evidence requires a genuine date. Do not manufacture a
            // sentinel when the source stops providing a real period bound.
            return nil
        }
        let duration = start.map { end.timeIntervalSince($0) }
        guard duration == nil || (duration!.isFinite && duration! > 0) else { return nil }

        let utilization: Double?
        if let preferred = config.creditUsagePercent {
            utilization = preferred
        } else if let limit = config.monthlyLimit?.val, limit > 0,
                  let used = config.used?.val {
            utilization = used / limit * 100
        } else if period != nil {
            // Live capture 2026-08-01: proto3 omitted the zero-valued percentage while
            // retaining a complete typed period. In this verified new-shape response,
            // absence means the scalar's protobuf default (0), not unknown usage.
            utilization = 0
        } else {
            utilization = nil
        }
        guard let utilization, utilization.isFinite else { return nil }

        return UsageWindow(
            kind: BillingPeriodWindowClassifier.kind(
                periodType: GrokPeriodType.normalized(period?.type),
                durationSeconds: duration
            ),
            utilization: utilization,
            resetsAt: end
        )
    }

    /// ACP extension responses have shipped both the direct billing object and a
    /// `{ "result": ... }` extension wrapper. HTTP is direct. Normalize once so the
    /// provider remains transport-agnostic.
    private static func normalizedPayload(_ body: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: body) else { return nil }
        if let wrapper = object as? [String: Any],
           let nested = wrapper["result"], JSONSerialization.isValidJSONObject(nested) {
            return try? JSONSerialization.data(withJSONObject: nested)
        }
        return body
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}
