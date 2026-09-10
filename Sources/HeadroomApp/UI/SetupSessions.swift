import SwiftUI
import Observation
import AppKit
import HeadroomCore

/// Observable mirror of per-account Terminal-handoff state. The session enums'
/// static dictionaries are invisible to SwiftUI observation, so a row couldn't
/// repaint to "Waiting for sign-in…" until the first auto-retry mutated the store
/// (~8–12s of a dead-looking button — code-review finding). Views read this object
/// in `body`, so the flip is immediate.
@MainActor
@Observable
final class SetupSessionActivity {
    static let shared = SetupSessionActivity()

    private var openedAt: [AccountKey: Date] = [:]

    func openedAt(for key: AccountKey) -> Date? { openedAt[key] }

    func set(_ date: Date?, for key: AccountKey) { openedAt[key] = date }

    /// R2M12: when the account's current Terminal handoff was opened, so the popover
    /// header can carry a clock instead of echoing the card's own title. The coordinator's
    /// `.waiting(attempt:)` carries a retry counter, not a start instant, so the stamp is
    /// taken at the app boundary where the handoff is actually kicked off.
    private var waitingSince: [AccountKey: Date] = [:]

    func waitingSince(for key: AccountKey) -> Date? { waitingSince[key] }

    func beginWaiting(for key: AccountKey, at date: Date) { waitingSince[key] = date }

    func endWaiting(for key: AccountKey) { waitingSince.removeValue(forKey: key) }

    /// The Connected payoff (chip + four-second settle) fires once per connection, per
    /// account — not once per card identity. The card used to guard it with its own
    /// `@State`, which the M5A meter-style crossfade resets when it rebuilds the card, so a
    /// style change inside the four-second window replayed the chip and queued a second
    /// settle (cross-model review finding, 2026-09-10). `settle(for:)` releases the claim.
    private var connectedPayoffClaimed: Set<AccountKey> = []

    /// True when this call took the claim; false when the payoff already ran for this
    /// connection.
    func claimConnectedPayoff(for key: AccountKey) -> Bool {
        connectedPayoffClaimed.insert(key).inserted
    }

    func releaseConnectedPayoff(for key: AccountKey) {
        connectedPayoffClaimed.remove(key)
    }
}

/// The single provider→session routing switch. Views call these instead of
/// switching on `providerID` themselves — four parallel copies of that switch is
/// how a future provider ends up with a Sign In button that silently no-ops
/// (code-review finding).
@MainActor
enum SetupSessions {
    enum RecoveryRoute: Equatable {
        case documentation(URL)
        case setup(SetupHandoffMode)
        case privacyGuidance(URL)
        case checkNow
    }

    /// R6/KTD5: `manualCommand` exists only because preparation already captured a
    /// validated absolute executable, so the Terminal-rejected clipboard fallback can
    /// never hand back an unresolved bare-name command.
    struct PreparedScript: Sendable {
        let scriptURL: URL
        let completionMarker: SetupCompletionMarker
        let manualCommand: String
    }

    private static var coordinator: SetupSessionCoordinator?
    private static weak var store: UsageStore?
    private static var preparedScripts: [AccountKey: PreparedScript] = [:]
    private static var activeScripts: [AccountKey: PreparedScript] = [:]
    private static var completionTasks: [AccountKey: Task<Void, Never>] = [:]
    private static var checkNowTasks: [AccountKey: Task<Void, Never>] = [:]
    private static var announcedFailures: [AccountKey: SetupSessionFailure] = [:]
    private static var capabilityAnnouncementDedupe = CapabilityAnnouncementDedupe()
    private static var claudeExecutableLocator: any CLIExecutableLocating = CLIExecutableLocator.claude()
    private static var builtInClaudeWorkspace = ClaudeUsageWorkspace.defaultDirectoryURL

    /// The one shared Claude locator, so manual-command surfaces resolve the same
    /// validated absolute executable the probe and setup handoff use (R6).
    static var claudeLocator: any CLIExecutableLocating { claudeExecutableLocator }

    /// Test seam: production reads a staged handoff only through `openPreparedHandoff`.
    static func stagedHandoff(for key: AccountKey) -> PreparedScript? {
        preparedScripts[key]
    }

    static func configure(
        store: UsageStore,
        claudeExecutableLocator: any CLIExecutableLocating,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) {
        self.store = store
        self.claudeExecutableLocator = claudeExecutableLocator
        self.builtInClaudeWorkspace = builtInClaudeWorkspace
        let coordinator = SetupSessionCoordinator(
            prepare: { account, mode, purpose in
                await prepareHandoff(
                    for: account,
                    mode: mode,
                    purpose: purpose,
                    builtInClaudeWorkspace: builtInClaudeWorkspace,
                    claudeExecutableLocator: claudeExecutableLocator
                )
            },
            open: { handoff in openPreparedHandoff(handoff) },
            discard: { handoff in await discardPreparedHandoff(handoff) },
            accountExists: { key in
                store.accounts(for: key.providerID).contains(where: { $0.key == key })
            },
            requestRefresh: { key in store.refreshAccountNow(key) },
            resetBoundary: { key in store.invalidateUsageForAccountReset(key) }
        )
        self.coordinator = coordinator
        store.attachSetupCoordinator(coordinator)
        for providerID in store.providerOrder {
            for account in store.accounts(for: providerID) {
                let marker = completionMarker(
                    for: account,
                    builtInClaudeWorkspace: builtInClaudeWorkspace
                )
                if AccountStorage.setupHandoffIsActive(marker: marker) {
                    coordinator.restoreActiveHandoff(
                        account.key,
                        mode: AccountStorage.setupHandoffMode(marker: marker) ?? .standard,
                        purpose: AccountStorage.setupHandoffPurpose(marker: marker) ?? .setup
                    )
                    restoreWaitingStart(for: account.key, marker: marker)
                    monitorCompletion(marker, for: account.key)
                } else {
                    let completion = AccountStorage.setupHandoffCompletion(marker: marker)
                    if completion != .unknown {
                        coordinator.handoffDidEnd(
                            account.key,
                            completion: completion,
                            purpose: AccountStorage.setupHandoffPurpose(marker: marker) ?? .setup
                        )
                    }
                    AccountStorage.clearFinishedSetupCompletionMarkers(marker)
                }
            }
        }
    }

    static func openSetup(for account: ProviderAccount, onRetry: @escaping () -> Void) {
        noteHandoffBegan(for: account)
        if let coordinator {
            coordinator.begin(for: account)
            return
        }
        // Render harnesses do not construct the app composition root. Preserve their
        // deterministic preview state and the legacy fallback outside production.
        switch account.providerID {
        case .claude: ClaudeSetupSession.openSetup(for: account, onRetry: onRetry)
        case .codex: CodexSetupSession.openSetup(for: account, onRetry: onRetry)
        case .grok: assertionFailure("Grok setup requires the configured coordinator")
        case .cursor: assertionFailure("Cursor setup requires the configured coordinator")
        default: assertionFailure("No setup session registered for \(account.providerID)")
        }
    }

    static func resetSetup(for account: ProviderAccount) {
        noteHandoffBegan(for: account)
        coordinator?.beginReset(for: account)
    }

    /// R2M12: stamp the start of a handoff. Idempotent while a wait is already running, so
    /// "Reopen" and "Continue Setup" keep the clock the user has been reading rather than
    /// restarting it — and so a restored start seeded by `restoreWaitingStart` survives the
    /// next call rather than being rewritten to now.
    static func noteHandoffBegan(for account: ProviderAccount, at date: Date = .now) {
        guard !isWaiting(for: account) else { return }
        SetupSessionActivity.shared.beginWaiting(for: account.key, at: date)
    }

    /// R2M12: seed the clock of a handoff restored from its durable marker. `configure`
    /// runs before the coordinator knows the session is waiting, so this writes the stamp
    /// directly instead of going through `noteHandoffBegan`'s already-waiting guard. The
    /// start is only ever the one Headroom persisted beside the marker's generation; when
    /// that is missing, cancelled, or in the future the account keeps today's behaviour and
    /// the header falls back to the card-derived line rather than inventing "Waiting 3s".
    static func restoreWaitingStart(
        for key: AccountKey,
        marker: SetupCompletionMarker,
        now: Date = .now
    ) {
        guard let startedAt = AccountStorage.setupHandoffStartedAt(marker: marker, now: now)
        else { return }
        SetupSessionActivity.shared.beginWaiting(for: key, at: startedAt)
    }

    /// R2M12: how long the account's current handoff has been open, or nil when it is not
    /// waiting — or when no trustworthy start was recorded for it.
    static func waitingStart(for account: ProviderAccount) -> Date? {
        guard isWaiting(for: account) else { return nil }
        return SetupSessionActivity.shared.waitingSince(for: account.key)
    }

    /// Execute the action selected by the core recovery table. Keeping this switch at
    /// the app boundary means Settings and the popover cannot accidentally turn a
    /// permission problem into another login attempt or drift on provider behavior.
    static func performRecovery(
        _ action: SetupRecoveryAction,
        for account: ProviderAccount,
        onRetry: @escaping () -> Void
    ) {
        switch recoveryRoute(for: action) {
        case .documentation(let url), .privacyGuidance(let url):
            NSWorkspace.shared.open(url)
        case .setup(.standard):
            openSetup(for: account, onRetry: onRetry)
        case .setup(.deviceCode):
            noteHandoffBegan(for: account)
            if let coordinator {
                coordinator.begin(for: account, mode: .deviceCode)
            } else {
                CodexSetupSession.openSetup(for: account, onRetry: onRetry)
            }
        case .checkNow:
            guard checkNowTasks[account.key] == nil else { return }
            checkNowTasks[account.key] = Task {
                defer { checkNowTasks[account.key] = nil }
                await CLIExecutableRefreshContext.$generation.withValue(UUID()) {
                    if account.providerID == .claude {
                        _ = await claudeExecutableLocator.locate(forceRefresh: true)
                    }
                    onRetry()
                }
            }
        }
    }

    /// App-boundary routing for the complete typed recovery table. Keeping this pure makes the
    /// UI contract testable without opening Terminal, System Settings, or a browser.
    static func recoveryRoute(for action: SetupRecoveryAction) -> RecoveryRoute {
        switch action {
        case .installClaudeCLI:
            // R8: Anthropic's current official installation guide.
            .documentation(URL(string: "https://code.claude.com/docs/en/installation")!)
        case .openClaudeSetup, .connectCodex, .reconnectCodex, .resolveCodexStorage,
             .connectGrok, .reconnectGrok, .connectCursor:
            .setup(.standard)
        case .installCodexCLI:
            .documentation(URL(string: "https://developers.openai.com/codex/cli/")!)
        case .connectCodexDeviceCode, .connectGrokDeviceCode:
            .setup(.deviceCode)
        case .installGrokCLI:
            .documentation(URL(string: "https://x.ai/news/grok-build")!)
        case .installCursorAgent:
            .documentation(URL(string: "https://docs.cursor.com/en/cli/installation")!)
        case .showPrivacyGuidance:
            .privacyGuidance(URL(string: "https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac")!)
        case .checkNow:
            .checkNow
        }
    }

    static func continueSetup(for account: ProviderAccount) {
        coordinator?.continueSetup(for: account)
    }

    static func isWaiting(for account: ProviderAccount) -> Bool {
        if let coordinator {
            switch coordinator.state(for: account.key) {
            case .preparing, .waiting, .verifying: return true
            default: return false
            }
        }
        return SetupSessionActivity.shared.openedAt(for: account.key) != nil
    }

    static func hasActiveHandoff(for account: ProviderAccount) -> Bool {
        coordinator?.hasActiveHandoff(for: account.key)
            ?? (SetupSessionActivity.shared.openedAt(for: account.key) != nil)
    }

    static func state(for account: ProviderAccount) -> SetupSessionState {
        coordinator?.state(for: account.key)
            ?? (isWaiting(for: account) ? .waiting(attempt: 0) : .idle)
    }

    static func mode(for account: ProviderAccount) -> SetupHandoffMode {
        coordinator?.sessionMode(for: account.key) ?? .standard
    }

    /// Redaction-safe, actionable copy for coordinator failures. Views use the typed
    /// state so preparation/open/retry failures do not collapse back into a dead-looking
    /// Connect button or expose caught filesystem/AppKit errors.
    static func failureMessage(for account: ProviderAccount) -> String? {
        guard case .failed(let failure) = state(for: account) else { return nil }
        switch failure {
        case .executableMissing:
            let name = switch account.providerID {
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .grok: "Grok Build"
            case .cursor: "Cursor Agent"
            default: account.providerID.raw.capitalized
            }
            return "\(name) CLI wasn’t found. Install or update it, then try again."
        case .stagingFailed:
            return "Headroom couldn’t prepare the Terminal handoff. Try again."
        case .terminalRejected:
            return "Terminal didn’t open. The official CLI command was copied for you."
        case .pasteboardFailed:
            return "Terminal didn’t open, and the recovery command couldn’t be copied. Try again."
        case .retryExhausted:
            // R2B1: prose names the button it points at, so "Check Now" is capitalised the
            // way the chip beside this sentence is.
            return "Sign-in wasn’t confirmed. Check Now, or reopen the official CLI."
        case .provider(let outcome):
            return outcome.message
        case .providerCapability(let capability):
            return capability.recoveryPresentation?.status
                ?? "Claude Code availability couldn’t be confirmed. Try again."
        }
    }

    /// Multiple surfaces can observe the same account simultaneously. Deduplicate the
    /// VoiceOver announcement at the session boundary so a single transition is spoken
    /// once even when both Settings and the popover are mounted.
    static func announceFailureIfNeeded(for account: ProviderAccount) {
        guard case .failed(let failure) = state(for: account) else {
            announcedFailures.removeValue(forKey: account.key)
            return
        }
        guard announcedFailures[account.key] != failure,
              let message = failureMessage(for: account)
        else { return }
        announcedFailures[account.key] = failure
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Setup failed. \(message)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    static func announceCapabilityIfNeeded(
        _ state: ProviderCapabilityState?,
        for providerID: ProviderID
    ) {
        guard let message = capabilityAnnouncementDedupe.announcement(
            for: providerID,
            state: state
        ) else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    static func isConnected(_ account: ProviderAccount) -> Bool {
        if coordinator != nil { return state(for: account) == .connected }
        return SetupSessionActivity.shared.openedAt(for: account.key) != nil
    }

    /// End an account's handoff session: cancel pending retries and clear the waiting
    /// flag. Called when the account goes live — and when it's removed, so orphaned
    /// retry tasks can't keep spawning poll cycles for a deleted account.
    static func settle(for account: ProviderAccount) {
        SetupSessionActivity.shared.endWaiting(for: account.key)
        SetupSessionActivity.shared.releaseConnectedPayoff(for: account.key)
        if let coordinator {
            coordinator.settleConnected(account.key)
            return
        }
        switch account.providerID {
        case .claude: ClaudeSetupSession.cancelRetries(for: account.id)
        case .codex: CodexSetupSession.cancelRetries(for: account.id)
        default: break
        }
        SetupSessionActivity.shared.set(nil, for: account.key)
    }

    static func cancel(for account: ProviderAccount) {
        coordinator?.cancel(account.key)
        SetupSessionActivity.shared.set(nil, for: account.key)
        SetupSessionActivity.shared.endWaiting(for: account.key)
    }

    /// Stop waiting for an external CLI handoff without attempting to terminate its
    /// user-visible Terminal process. Cancellation is tombstoned synchronously before
    /// the generation's files are removed, so a late wrapper stays ignored on relaunch.
    static func forceCancel(for account: ProviderAccount) {
        completionTasks.removeValue(forKey: account.key)?.cancel()
        let prepared = preparedScripts.removeValue(forKey: account.key)
            ?? activeScripts.removeValue(forKey: account.key)
        let marker = prepared?.completionMarker ?? completionMarker(
            for: account,
            builtInClaudeWorkspace: builtInClaudeWorkspace
        )
        AccountStorage.clearSetupCompletionMarkers(marker)
        if let prepared {
            try? FileManager.default.removeItem(at: prepared.scriptURL)
        }
        coordinator?.forceCancel(account.key)
        store?.cancelAccountRemoval(account.key)
        SetupSessionActivity.shared.set(nil, for: account.key)
        SetupSessionActivity.shared.endWaiting(for: account.key)
    }

    static func prepareHandoff(
        for account: ProviderAccount,
        mode: SetupHandoffMode,
        purpose: SetupHandoffPurpose = .setup,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL,
        claudeExecutableLocator: any CLIExecutableLocating = CLIExecutableLocator.claude()
    ) async -> SetupPreparationResult {
        let accountCompletionMarker = completionMarker(
            for: account,
            builtInClaudeWorkspace: builtInClaudeWorkspace
        )
        let preparation = await Task.detached(priority: .userInitiated) { () -> Result<PreparedScript, SetupSessionFailure> in
            do {
                if !account.isBuiltIn {
                    _ = try AccountStorage.ensureDirectories(for: account)
                }
                let supportDirectory = builtInClaudeWorkspace
                    .deletingLastPathComponent()
                    .appendingPathComponent("Setup", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: supportDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: supportDirectory.path
                )
                let scriptURL = supportDirectory
                    .appendingPathComponent("\(UUID().uuidString).command")
                let completionMarker = accountCompletionMarker
                let script: String
                let manualCommand: String
                switch account.providerID {
                case .claude:
                    let location = await claudeExecutableLocator.locate(forceRefresh: true)
                    guard let executable = location.path else {
                        switch location {
                        case .confirmedAbsent:
                            return .failure(.providerCapability(.confirmedAbsent))
                        case .inconclusive(let issue):
                            return .failure(.providerCapability(.inconclusive(issue)))
                        case .available:
                            return .failure(.stagingFailed)
                        }
                    }
                    let configuration = ProviderAccountConfiguration.make(
                        for: account,
                        builtInClaudeWorkspace: builtInClaudeWorkspace
                    )
                    guard let workspace = configuration.claudeWorkspaceDirectory else {
                        return .failure(.stagingFailed)
                    }
                    try ClaudeUsageWorkspace.ensureDirectory(at: workspace)
                    let fallback = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    let descriptor = ClaudeSetupDescriptor(
                        accountKey: account.key,
                        executablePath: executable,
                        loginPath: CLIExecutableResolver.resolveLoginPath(fallback: fallback),
                        workspaceDirectory: workspace.path,
                        configDirectory: configuration.claudeConfigDirectory?.path,
                        purpose: purpose,
                        completionMarker: completionMarker
                    )
                    script = ClaudeSetupCommand.script(for: descriptor)
                    // KTD5: the descriptor carries the validated executable resolved
                    // above, so a nil command here would mean staging is inconsistent.
                    guard let resolved = ClaudeSetupCommand.manualCommand(for: descriptor) else {
                        return .failure(.stagingFailed)
                    }
                    manualCommand = resolved
                case .codex:
                    let executable = CodexCLI.resolveExecutable()
                    guard executable != nil else { return .failure(.executableMissing) }
                    let configuration = ProviderAccountConfiguration.make(for: account)
                    script = CodexCLI.loginScript(
                        executablePath: executable,
                        codexHome: configuration.codexHomeDirectory?.path,
                        mode: mode,
                        completionMarker: completionMarker
                    )
                    manualCommand = CodexCLI.accountLoginCommand(
                        codexHome: configuration.codexHomeDirectory?.path,
                        mode: mode
                    )
                case .grok:
                    let executable = GrokCLI.resolveExecutable()
                    guard executable != nil else { return .failure(.executableMissing) }
                    let configuration = ProviderAccountConfiguration.make(for: account)
                    script = GrokCLI.loginScript(
                        executablePath: executable,
                        grokHome: configuration.grokHomeDirectory?.path,
                        mode: mode,
                        completionMarker: completionMarker
                    )
                    manualCommand = GrokCLI.accountLoginCommand(
                        grokHome: configuration.grokHomeDirectory?.path,
                        mode: mode
                    )
                case .cursor:
                    let executable = CursorCLI.resolveExecutable()
                    guard executable != nil else { return .failure(.executableMissing) }
                    script = CursorCLI.loginScript(
                        executablePath: executable,
                        completionMarker: completionMarker
                    )
                    manualCommand = CursorCLI.loginCommand
                default:
                    return .failure(.stagingFailed)
                }
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
                return .success(PreparedScript(
                    scriptURL: scriptURL,
                    completionMarker: completionMarker,
                    manualCommand: manualCommand
                ))
            } catch {
                return .failure(.stagingFailed)
            }
        }.value

        switch preparation {
        case .success(let preparedScript):
            preparedScripts[account.key] = preparedScript
            return .success(PreparedSetupHandoff(
                accountKey: account.key,
                mode: mode,
                purpose: purpose
            ))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private static func openPreparedHandoff(_ handoff: PreparedSetupHandoff) -> SetupOpenResult {
        guard let prepared = preparedScripts.removeValue(forKey: handoff.accountKey) else {
            return .failure(.stagingFailed)
        }
        do {
            try AccountStorage.prepareSetupCompletionMarker(
                prepared.completionMarker,
                mode: handoff.mode,
                purpose: handoff.purpose
            )
        } catch {
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return .failure(.stagingFailed)
        }
        guard NSWorkspace.shared.open(prepared.scriptURL) else {
            AccountStorage.clearPreparedSetupCompletionMarker(prepared.completionMarker)
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return copyCommand(prepared.manualCommand)
                ? .failure(.terminalRejected)
                : .failure(.pasteboardFailed)
        }
        activeScripts[handoff.accountKey] = prepared
        monitorCompletion(prepared.completionMarker, for: handoff.accountKey)
        return .success(())
    }

    static func discardPreparedHandoff(_ handoff: PreparedSetupHandoff) async {
        guard let prepared = preparedScripts.removeValue(forKey: handoff.accountKey) else { return }
        await Task.detached(priority: .utility) {
            AccountStorage.clearPreparedSetupCompletionMarker(prepared.completionMarker)
            try? FileManager.default.removeItem(at: prepared.scriptURL)
        }.value
    }

    /// Delegates to the shared account-aware resolver in HeadroomCore so the marker
    /// path staged here can never diverge from the one `UsageStore`'s removal gate
    /// checks via `AccountStorage.setupHandoffIsActive(for:)` (code-review finding:
    /// a divergent built-in path let stop-tracking detach a row mid-handoff).
    private static func completionMarker(
        for account: ProviderAccount,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) -> SetupCompletionMarker {
        AccountStorage.setupCompletionMarker(
            for: account,
            builtInClaudeWorkspace: builtInClaudeWorkspace
        )
    }

    private static func monitorCompletion(_ marker: SetupCompletionMarker, for key: AccountKey) {
        completionTasks.removeValue(forKey: key)?.cancel()
        completionTasks[key] = Task { @MainActor in
            while !Task.isCancelled, AccountStorage.setupHandoffIsActive(marker: marker) {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            coordinator?.handoffDidEnd(
                key,
                completion: AccountStorage.setupHandoffCompletion(marker: marker),
                purpose: AccountStorage.setupHandoffPurpose(marker: marker)
            )
            AccountStorage.clearFinishedSetupCompletionMarkers(marker)
            activeScripts.removeValue(forKey: key)
            completionTasks[key] = nil
        }
    }

    static func copyCommand(_ command: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(command, forType: .string)
    }
}
