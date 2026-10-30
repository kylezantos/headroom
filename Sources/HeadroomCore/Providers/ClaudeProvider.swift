import Foundation

/// Claude usage provider (U4). Reads the real 5-hour and weekly windows from Claude
/// Code's own `/usage` panel via `ClaudeUsageSource` — the compliant path, since the
/// official CLI makes the request and this only reads what it prints. Never throws:
/// a missing CLI or unreadable panel degrades to a typed stale state (KTD7).
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude
    public let accountID: AccountID
    public let displayName = "Claude"
    public let pollingLane: ProviderPollingLane = .serial("claude-cli")
    public let reportsProviderCapability = true

    private let source: ClaudeUsageSource
    private let emailSource: ClaudeAccountEmailReading
    private let now: @Sendable () -> Date

    public init(
        source: ClaudeUsageSource = ClaudeUsageCLIProbe(),
        accountID: AccountID = .primary,
        emailSource: ClaudeAccountEmailReading? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.accountID = accountID
        // Defaults to this account's own `.claude.json`, resolved the same way the probe
        // resolves `CLAUDE_CONFIG_DIR`, so an extra account never reports the built-in
        // account's email.
        self.emailSource = emailSource ?? ClaudeAccountEmailFileReader.forAccount(accountID)
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        await fetchResult().snapshot
    }

    public func fetchResult() async -> UsageProviderFetchResult {
        switch await source.capturePanel() {
        case .cliNotFound:
            return capabilityFailure(.confirmedAbsent)
        case .cliInconclusive(let issue):
            return capabilityFailure(.inconclusive(issue))
        case .loginRequired:
            return accountResult(stale(.providerSetup(.claudeLoginRequired)))
        case .workspaceTrustRequired:
            return accountResult(stale(.providerSetup(.claudeTrustRequired)))
        case .startupQuestion:
            return accountResult(stale(.providerSetup(.claudeStartupQuestion)))
        case .unknownUI:
            return accountResult(stale(.providerSetup(.claudeUnknownUI)))
        case .transientCapture:
            return accountResult(stale(.providerSetup(.claudeTransientCapture)))
        case .panel(let text, let planHint):
            let parsed = ClaudeUsageParser.parse(text)
            guard !parsed.isEmpty else {
                return accountResult(stale(.providerSetup(.claudeTransientCapture)))
            }
            let capturedAt = now()
            let windows = parsed.map { window in
                let resetSchedule = ClaudeResetNormalizer.schedule(
                    label: window.resetLabel,
                    timeZoneIdentifier: window.resetTimeZoneIdentifier,
                    kind: window.kind,
                    now: capturedAt
                )
                let labelOnlySchedule = ClaudeResetNormalizer.schedule(
                    label: window.resetLabel,
                    timeZoneIdentifier: nil,
                    kind: window.kind,
                    now: capturedAt
                )
                let resetLabel: String? = switch labelOnlySchedule {
                case .unresolved(.absent), .unresolved(.unparseable): nil
                default: window.resetLabel
                }
                let resetTimeZoneIdentifier = resetLabel.flatMap { _ in
                    window.resetTimeZoneIdentifier.flatMap { TimeZone(identifier: $0)?.identifier }
                }
                return UsageWindow(
                    kind: window.kind,
                    utilization: window.percentUsed,
                    resetSchedule: resetSchedule,
                    resetLabel: resetLabel,
                    resetTimeZoneIdentifier: resetTimeZoneIdentifier
                )
            }
            return accountResult(UsageSnapshot(
                providerID: id,
                windows: windows,
                // Panel-text tier first ("Max 20x" fidelity); the auth-status hint
                // covers the print-mode report, which omits the tier header.
                planLabel: ClaudeUsageParser.plan(in: text) ?? planHint,
                accountEmail: emailSource.readAccountEmail(),
                capturedAt: capturedAt,
                freshness: .live
            ))
        }
    }

    private func capabilityFailure(_ capability: ProviderCapabilityState) -> UsageProviderFetchResult {
        UsageProviderFetchResult(
            snapshot: stale(.transient("Claude CLI capability unavailable — will retry")),
            capability: capability
        )
    }

    private func accountResult(_ snapshot: UsageSnapshot) -> UsageProviderFetchResult {
        UsageProviderFetchResult(snapshot: snapshot, capability: .available)
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}
