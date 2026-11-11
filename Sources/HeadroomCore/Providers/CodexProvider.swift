import Foundation

/// Codex/ChatGPT usage provider (U5). Reads `~/.codex/auth.json` via `CredentialStore`
/// and calls the `wham/usage` endpoint. On 401, rereads a session the official client
/// may have renewed while the request was in flight (session-reliability KTD4).
/// Never rotates credentials itself. Never throws (KTD7 isolation).
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
        await fetchResult().snapshot
    }

    /// KTD2 (default-login plan): the token and `account_id` come from one file read, so
    /// the session a request used names its own account. A live reading is kept only when
    /// the session the fetch started with, the session whose token was accepted (they
    /// differ after a 401 reload) and a re-read after the request all name one account.
    public func fetchResult() async -> UsageProviderFetchResult {
        switch await credentials.codexSession() {
        case .failure(let reason):
            return UsageProviderFetchResult(snapshot: stale(reason))
        case .success(let session):
            let (snapshot, used) = await fetch(session: session, mayReload: true)
            guard snapshot.freshness == .live else { return UsageProviderFetchResult(snapshot: snapshot) }
            let after: AccountIdentityRead
            switch await credentials.codexSession() {
            case .success(let current): after = current.identityRead
            case .failure: after = .unreadable
            }
            let outcome = used.identity == session.identity
                ? AccountIdentityOutcome.bracketing(before: used.identityRead, after: after)
                : .unreadable
            guard outcome != .unreadable else { return .identityUnreadable(for: id) }
            return UsageProviderFetchResult(snapshot: snapshot.withIdentity(outcome))
        }
    }

    /// Returns the snapshot and the session whose token produced it.
    private func fetch(session: CodexSession, mayReload: Bool) async -> (UsageSnapshot, CodexSession) {
        switch await http.get(url: Self.endpoint, headers: ["Authorization": "Bearer \(session.accessToken)"]) {
        case .failure(let reason):
            return (stale(reason), session)
        case .success(let result):
            switch result.status {
            case 200:
                return (decode(result.body, accountEmail: session.accountEmail), session)
            case 401:
                if mayReload {
                    switch await credentials.codexSession() {
                    case .success(let current) where current.accessToken != session.accessToken:
                        return await fetch(session: current, mayReload: false)
                    case .failure(let reason):
                        return (stale(reason), session)
                    default:
                        // KTD6: an unchanged expired session is not evidence that
                        // the login was revoked. Keep retry and manual recovery.
                        return (stale(.providerSetup(.codexSessionUnverified)), session)
                    }
                }
                return (stale(.providerSetup(.codexRejectedAuth)), session)
            default:
                return (stale(UsageWindowBuilder.genericFailure(for: result.status)), session)
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
