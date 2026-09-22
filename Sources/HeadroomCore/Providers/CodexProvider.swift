import Foundation

/// Codex/ChatGPT usage provider (U5). Reads `~/.codex/auth.json` via `CredentialStore`
/// and calls the `wham/usage` endpoint. Does not attempt OpenAI's refresh — on 401 it
/// degrades to the official CLI login handoff (KTD3). Never throws (KTD7 isolation).
public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex
    public let accountID: AccountID
    public let displayName = "Codex"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public init(
        credentials: CredentialStore,
        accountID: AccountID = .primary,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.accountID = accountID
        self.http = http
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await credentials.codexSession() {
        case .failure(let reason):
            return stale(reason)
        case .success(let session):
            switch await http.get(url: Self.endpoint, headers: ["Authorization": "Bearer \(session.accessToken)"]) {
            case .failure(let reason):
                return stale(reason)
            case .success(let result):
                switch result.status {
                case 200:
                    return decode(result.body, accountEmail: session.accountEmail)
                case 401:
                    return stale(.providerSetup(.codexRejectedAuth))
                default:
                    return stale(UsageWindowBuilder.genericFailure(for: result.status))
                }
            }
        }
    }

    private func decode(_ body: Data, accountEmail: String?) -> UsageSnapshot {
        guard let dto = try? JSONDecoder().decode(CodexUsageDTO.self, from: body) else {
            return stale(.decode("Couldn’t read Codex usage response"))
        }
        var windows: [UsageWindow] = []
        // Kind comes from each window's own `limit_window_seconds`, not its slot — see
        // #codex-window-kind. The primary/secondary args are only the fallback used when a
        // response omits the duration.
        if let w = dto.rate_limit?.primary_window,
           let win = codexWindow(w, positionalDefault: .fiveHour) {
            windows.append(win)
        }
        if let w = dto.rate_limit?.secondary_window,
           let win = codexWindow(w, positionalDefault: .weekly) {
            windows.append(win)
        }
        for extra in dto.additional_rate_limits ?? [] {
            let label = extra.displayLabel
            if let w = extra.rate_limit?.primary_window,
               let win = codexNamedWindow(w, label: label, positionalDefault: .fiveHour) {
                windows.append(win)
            }
            if let w = extra.rate_limit?.secondary_window,
               let win = codexNamedWindow(w, label: label, positionalDefault: .weekly) {
                windows.append(win)
            }
            if extra.rate_limit == nil,
               let win = UsageWindowBuilder.make(.other(label), utilization: extra.utilizationValue, resetsAt: extra.resetAtValue, resetEpochSeconds: extra.resetEpochValue, resetsInSeconds: extra.resetSecondsValue, now: now) {
                windows.append(win)
            }
        }
        guard !windows.isEmpty else {
            return stale(.decode("No usage windows in Codex response"))
        }
        return UsageSnapshot(
            providerID: id,
            windows: windows,
            planLabel: dto.plan_type,        // lenient: any string, incl. new tiers (#709)
            accountEmail: accountEmail,
            bankedResets: dto.resetCreditsField.bankedResets,
            codexResetCreditsField: dto.resetCreditsField,
            capturedAt: now(),
            freshness: .live
        )
    }

    /// A main rate-limit window, kinded by its true duration (#codex-window-kind).
    private func codexWindow(_ w: CodexWindowDTO, positionalDefault: WindowKind) -> UsageWindow? {
        let kind = CodexWindowClassifier.kind(limitWindowSeconds: w.windowSecondsValue, positionalDefault: positionalDefault)
        return UsageWindowBuilder.make(kind, utilization: w.utilizationValue, resetsAt: w.resetAtValue, resetEpochSeconds: w.resetEpochValue, resetsInSeconds: w.resetSecondsValue, now: now)
    }

    /// An additional (model-specific) allowance window, suffixed with its true duration
    /// rather than a hardcoded "5h"/"weekly" (#codex-window-kind).
    private func codexNamedWindow(_ w: CodexWindowDTO, label: String, positionalDefault: WindowKind) -> UsageWindow? {
        let kind = CodexWindowClassifier.kind(limitWindowSeconds: w.windowSecondsValue, positionalDefault: positionalDefault)
        return UsageWindowBuilder.make(.other("\(label) \(kind.shortLabel)"), utilization: w.utilizationValue, resetsAt: w.resetAtValue, resetEpochSeconds: w.resetEpochValue, resetsInSeconds: w.resetSecondsValue, now: now)
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}
