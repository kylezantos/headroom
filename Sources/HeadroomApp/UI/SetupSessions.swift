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
    struct ConnectedPayoffClaim: Sendable, Equatable {
        fileprivate let id: UUID
        fileprivate let coordinatorToken: SetupConnectedPayoffToken?
    }

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
    private var connectedPayoffClaims: [AccountKey: ConnectedPayoffClaim] = [:]

    /// QA1: returns the claim when this call took it; nil when the payoff already runs for this
    /// connection. The coordinator token binds its delayed settle to the matching generation.
    func claimConnectedPayoff(
        for key: AccountKey,
        coordinatorToken: SetupConnectedPayoffToken? = nil
    ) -> ConnectedPayoffClaim? {
        guard connectedPayoffClaims[key] == nil else { return nil }
        let claim = ConnectedPayoffClaim(id: UUID(), coordinatorToken: coordinatorToken)
        connectedPayoffClaims[key] = claim
        return claim
    }

    /// QA1: with a claim, release only that exact payoff. A delayed callback from an earlier
    /// connection must not release the claim belonging to a later connection.
    @discardableResult
    func releaseConnectedPayoff(
        _ claim: ConnectedPayoffClaim? = nil,
        for key: AccountKey
    ) -> Bool {
        if let claim, connectedPayoffClaims[key] != claim { return false }
        return connectedPayoffClaims.removeValue(forKey: key) != nil
    }
}

/// KTD12 (2026-09-19 sign-in plan): one VoiceOver announcement per distinct failure **per
/// handoff**. The dedupe used to clear the moment the state left `.failed`, which a Try Again
/// loop does on every press — so a user holding one Terminal window open heard "Sign-in
/// wasn’t confirmed" at high priority every five minutes. The claim is released when the
/// handoff ends instead, and a genuinely different failure still speaks.
struct SetupFailureAnnouncer {
    private var announced: [AccountKey: SetupSessionFailure] = [:]

    mutating func shouldAnnounce(
        _ failure: SetupSessionFailure?,
        for key: AccountKey,
        hasActiveHandoff: Bool
    ) -> Bool {
        guard let failure else {
            if !hasActiveHandoff { announced.removeValue(forKey: key) }
            return false
        }
        guard announced[key] != failure else { return false }
        announced[key] = failure
        return true
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
        /// KTD5 (2026-09-19 sign-in plan): workspace approval, for Claude as well as Cursor.
        /// It was `cursorWorkspace` while Cursor was the only provider whose approval prompt
        /// needed its own handoff purpose.
        case workspaceTrust
        case cursorTools
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
        /// KTD1 (2026-09-19 sign-in plan): the kind this script was written as, nil for the
        /// providers that stage one kind.
        var claudeScriptKind: ClaudeSetupScriptKind?
        /// KTD11: why that kind is `interactive`, which is what the waiting copy turns on.
        var claudeInteractiveReason: ClaudeInteractiveLaunchReason?
    }

    private static var coordinator: SetupSessionCoordinator?
    private static weak var store: UsageStore?
    private static var preparedScripts: [AccountKey: PreparedScript] = [:]
    private static var activeScripts: [AccountKey: PreparedScript] = [:]
    /// KTD13 live-QA correction: the application that actually owns the account's open
    /// handoff. New handoffs use the
    /// system Terminal deterministically; restored handoffs keep the app recorded when they
    /// opened so Show Terminal still fronts the right process.
    private static var handoffTerminalApps: [AccountKey: String] = [:]
    /// KTD11: why the account's open handoff was staged as the interactive launch, so the
    /// waiting surface can tell the `/login` case (R6) from a never-onboarded extra config
    /// (AE7) without re-reading the CLI version from a view.
    private static var handoffInteractiveReasons: [AccountKey: ClaudeInteractiveLaunchReason] = [:]
    /// Review #1 (2026-09-19 sign-in review): the purpose of a staging that was *refused*
    /// before any handoff opened. `SetupSessionCoordinator.invalidateWork` clears
    /// `sessionPurposes` for a terminal failure with no open handoff — deliberately, so a
    /// settled failure cannot suppress the ordinary polling that would recover the account —
    /// which left a refused `.reset` reading back as `.setup`. Try Again then started a plain
    /// sign-in against a login the reset never signed out, the script's own guard reported it
    /// as already signed in, and Headroom called the old account connected.
    private static var refusedHandoffPurposes: [AccountKey: SetupHandoffPurpose] = [:]
    private static var completionTasks: [AccountKey: Task<Void, Never>] = [:]
    private static var checkNowTasks: [AccountKey: Task<Void, Never>] = [:]
    private static var failureAnnouncer = SetupFailureAnnouncer()
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

    /// KTD13: the application recorded when this account's handoff opened, or nil when none was
    /// resolved — which is what Show Terminal treats as "nothing to front".
    static func handoffTerminalApp(for key: AccountKey) -> String? {
        handoffTerminalApps[key]
    }

    /// KTD13: a handoff that outlived the launch which opened it has no script left to
    /// resolve, so its restored handler is written back through here.
    static func noteHandoffTerminalApp(_ bundleIdentifier: String?, for key: AccountKey) {
        handoffTerminalApps[key] = bundleIdentifier
    }

    /// KTD11: the same write-back for the staged interactive reason, used by `configure`
    /// when it restores a handoff from its durable record.
    static func noteHandoffInteractiveReason(
        _ reason: ClaudeInteractiveLaunchReason?,
        for key: AccountKey
    ) {
        handoffInteractiveReasons[key] = reason
    }

    /// KTD13: the only AppKit call Show Terminal makes, replaceable so tests never front a
    /// real app. Returns whether a running instance was activated.
    static var activateApplication: @MainActor (String) -> Bool = activateRunningApplication(bundleIdentifier:)

    /// R14: app-level activation needs no automation permission, so nothing here enumerates
    /// or raises a window — a minimized window stays minimized.
    static func activateRunningApplication(bundleIdentifier: String) -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .activate() ?? false
    }

    /// R14: bring the app that opened this account's handoff forward. Silent when no handler
    /// was recorded or none of its instances is running: no session state changes, and no
    /// handoff is begun, staged or re-stated.
    @discardableResult
    static func showTerminal(for account: ProviderAccount) -> Bool {
        guard let bundleIdentifier = handoffTerminalApps[account.key] else { return false }
        return activateApplication(bundleIdentifier)
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
            open: { handoff in await openPreparedHandoff(handoff) },
            discard: { handoff in await discardPreparedHandoff(handoff) },
            accountExists: { key in
                store.accounts(for: key.providerID).contains(where: { $0.key == key })
            },
            requestRefresh: { key in store.refreshAccountNow(key, origin: .setupCheck) },
            resetBoundary: { key in store.invalidateUsageForAccountReset(key) },
            // KTD9 (2026-09-19 sign-in plan): a check already in flight when Terminal
            // exits must not settle the verification that follows it.
            handoffBoundary: { key in store.invalidateUsageForHandoffBoundary(key) }
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
                    // KTD8: the policy and the terminal app come from the record this
                    // handoff saved when it opened, never from the CLI version now
                    // installed — that can change while the original window is open.
                    let record = AccountStorage.setupHandoffRecord(marker: marker)
                    let startedAt = AccountStorage.setupHandoffStartedAt(marker: marker)
                    coordinator.restoreActiveHandoff(
                        account.key,
                        mode: AccountStorage.setupHandoffMode(marker: marker) ?? .standard,
                        purpose: AccountStorage.setupHandoffPurpose(marker: marker) ?? .setup,
                        policy: record?.waitingPolicy,
                        startedAt: startedAt
                    )
                    noteHandoffTerminalApp(record?.terminalBundleIdentifier, for: account.key)
                    noteHandoffInteractiveReason(record?.claudeInteractiveReason, for: account.key)
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
        // QA1: the Connected chip's delayed callback belongs to the session reset replaces.
        SetupSessionActivity.shared.releaseConnectedPayoff(for: account.key)
        coordinator?.beginReset(for: account)
    }

    /// R2M12: stamp the start of a handoff. Idempotent while a wait is already running, so
    /// "Reopen" and "Continue Setup" keep the clock the user has been reading rather than
    /// restarting it — and so a restored start seeded by `restoreWaitingStart` survives the
    /// next call rather than being rewritten to now.
    static func noteHandoffBegan(for account: ProviderAccount, at date: Date = .now) {
        // Review #1: a handoff that actually begins supersedes the refusal recorded before
        // it, whether or not this call goes on to stamp the clock.
        refusedHandoffPurposes.removeValue(forKey: account.key)
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
        case .workspaceTrust:
            noteHandoffBegan(for: account)
            coordinator?.beginWorkspaceTrust(for: account)
        case .cursorTools:
            noteHandoffBegan(for: account)
            coordinator?.beginCursorMCPApproval(for: account)
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
        case .openClaudeWorkspace, .openCursorWorkspace:
            .workspaceTrust
        case .reviewCursorTools:
            .cursorTools
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

    static func purpose(for account: ProviderAccount) -> SetupHandoffPurpose? {
        coordinator?.sessionPurpose(for: account.key)
    }

    /// Review #1: the purpose of this account's last refused staging, or nil once a handoff
    /// has begun, the session has been force-cancelled, or it settled connected.
    static func refusedHandoffPurpose(for account: ProviderAccount) -> SetupHandoffPurpose? {
        refusedHandoffPurposes[account.key]
    }

    static func finalVerificationCompletion(for account: ProviderAccount) -> SetupHandoffCompletion? {
        coordinator?.finalVerificationCompletion(for: account.key)
    }

    /// R7/KTD11: the account's waiting phase, assembled once here from the typed session
    /// state and the decisions its handoff recorded. Nil when the session is not waiting —
    /// including the timeout, which is a failure with its own copy and actions (KTD12).
    static func waitingPhase(for account: ProviderAccount) -> SetupWaitingPhase? {
        SetupWaitingPhase.resolve(
            state: state(for: account),
            hasActiveHandoff: hasActiveHandoff(for: account),
            purpose: purpose(for: account),
            mode: mode(for: account),
            interactiveReason: handoffInteractiveReasons[account.key],
            reportedCompletion: finalVerificationCompletion(for: account)
        )
    }

    /// KTD8/R10: return an already-open handoff to waiting without restaging anything.
    static func resumeWaiting(for account: ProviderAccount) {
        coordinator?.resumeWaiting(for: account.key)
    }

    /// KTD12/R10: Try Again is one handler with two branches, kept here so the popover card,
    /// the account row and the Settings row cannot drift apart. With the window still open it
    /// fronts the terminal app and resumes the five-minute wait; with none open it starts a
    /// fresh handoff of the same purpose. It is deliberately not `.checkNow` — PA11 pins that
    /// label to the forced poll.
    static func tryAgain(for account: ProviderAccount, onRetry: @escaping () -> Void) {
        tryAgain(
            for: account,
            route: tryAgainRoute(
                hasActiveHandoff: hasActiveHandoff(for: account),
                purpose: tryAgainPurpose(
                    sessionPurpose: purpose(for: account),
                    refusedPurpose: refusedHandoffPurposes[account.key]
                )
            ),
            onRetry: onRetry
        )
    }

    /// Review #1: which purpose Try Again resumes. The coordinator's live session purpose
    /// wins; the remembered refusal fills only the gap a cleared `sessionPurposes` leaves,
    /// so a reset refused before any window opened resumes as a reset.
    static func tryAgainPurpose(
        sessionPurpose: SetupHandoffPurpose?,
        refusedPurpose: SetupHandoffPurpose?
    ) -> SetupHandoffPurpose? {
        sessionPurpose ?? refusedPurpose
    }

    /// The route is a parameter here so a test can drive each branch without owning the
    /// process-wide coordinator that decides which one applies.
    static func tryAgain(
        for account: ProviderAccount,
        route: TryAgainRoute,
        onRetry: @escaping () -> Void
    ) {
        switch tryAgainAction(for: route) {
        case .showTerminalAndResume:
            showTerminal(for: account)
            resumeWaiting(for: account)
        case .startWorkspaceTrust:
            performRecovery(.openClaudeWorkspace, for: account, onRetry: onRetry)
        case .startReset:
            // Review #1: the sign-out is the point. Starting an ordinary sign-in here would
            // meet an account that is still signed in, so the script's guard would exit
            // reporting success and the old login would be shown as connected.
            resetSetup(for: account)
        case .startSetup:
            openSetup(for: account, onRetry: onRetry)
        }
    }

    /// Review #1: what Try Again does with a route, pure — so the reset branch is provable
    /// without a coordinator, a Terminal window, or a CLI.
    enum TryAgainAction: Equatable {
        case showTerminalAndResume
        case startReset
        case startWorkspaceTrust
        case startSetup
    }

    static func tryAgainAction(for route: TryAgainRoute) -> TryAgainAction {
        switch route {
        case .showTerminalAndResume: .showTerminalAndResume
        case .startNewHandoff(.reset): .startReset
        case .startNewHandoff(.trust): .startWorkspaceTrust
        case .startNewHandoff: .startSetup
        }
    }

    /// KTD12: the two branches, pure, so the choice is provable without opening Terminal.
    enum TryAgainRoute: Equatable {
        case showTerminalAndResume
        /// The purpose survives the failure, so an approval handoff that timed out and was
        /// then closed restarts as an approval rather than as a sign-in (AE3).
        case startNewHandoff(SetupHandoffPurpose)
    }

    static func tryAgainRoute(
        hasActiveHandoff: Bool,
        purpose: SetupHandoffPurpose?
    ) -> TryAgainRoute {
        hasActiveHandoff ? .showTerminalAndResume : .startNewHandoff(purpose ?? .setup)
    }

    /// Redaction-safe, actionable copy for coordinator failures. Views use the typed
    /// state so preparation/open/retry failures do not collapse back into a dead-looking
    /// Connect button or expose caught filesystem/AppKit errors.
    static func failureMessage(for account: ProviderAccount) -> String? {
        guard case .failed(let failure) = state(for: account) else { return nil }
        return failureMessage(
            for: failure,
            account: account,
            purpose: coordinator?.sessionPurpose(for: account.key)
        )
    }

    /// Pure over the typed failure, so the copy for a staging refusal is testable without
    /// an open session. KTD7 (2026-09-19 sign-in plan): the timeout's sentence follows the
    /// handoff purpose, which is why the purpose is a parameter rather than read inside.
    static func failureMessage(
        for failure: SetupSessionFailure,
        account: ProviderAccount,
        purpose: SetupHandoffPurpose? = nil
    ) -> String {
        switch failure {
        case .executableMissing:
            return "\(cliProductName(for: account)) CLI wasn’t found. Install or update it, then try again."
        case .updateRequired:
            // R6: the sentence names the product the user updates, not the command they
            // type — the installed CLI is the thing that is too old, not this account.
            return "Update \(cliProductName(for: account)), then try again."
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
        case .waitingTimedOut:
            // R8/KTD12: this state offers Try Again and Stop Waiting only, so the sentence
            // names no button — unlike `.retryExhausted`, which still points at Check Now.
            return purpose == .trust
                ? "Approval wasn’t confirmed."
                : "Sign-in wasn’t confirmed."
        case .closedBeforeSignIn:
            // R11: the window is gone and the account is still signed out. The status the
            // wrapper recorded is unobservable for an abandoned sign-in, so it says nothing.
            return "Terminal closed before sign-in finished."
        case .provider(let outcome):
            return outcome.message
        case .providerCapability(let capability):
            return capability.recoveryPresentation?.status
                ?? "Claude Code availability couldn’t be confirmed. Try again."
        }
    }

    /// KTD12: the second line the compact waiting shell prints under a failure sentence.
    /// Only the timeout has one: its Terminal window is still open, which is the fact the
    /// one-line sentence cannot carry and the thing that makes Try Again mean something.
    static func failureDetail(for failure: SetupSessionFailure) -> String? {
        switch failure {
        case .waitingTimedOut:
            return "Terminal is still open. Finish there, or try again to keep waiting."
        default:
            return nil
        }
    }

    /// The product a failure sentence points the user at, named the way they would go and
    /// get it rather than the way they invoke it.
    private static func cliProductName(for account: ProviderAccount) -> String {
        switch account.providerID {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .grok: "Grok Build"
        case .cursor: "Cursor Agent"
        default: account.providerID.raw.capitalized
        }
    }

    /// Multiple surfaces can observe the same account simultaneously. Deduplicate the
    /// VoiceOver announcement at the session boundary so a single transition is spoken
    /// once even when both Settings and the popover are mounted.
    static func announceFailureIfNeeded(for account: ProviderAccount) {
        var failure: SetupSessionFailure?
        if case .failed(let typed) = state(for: account) { failure = typed }
        guard failureAnnouncer.shouldAnnounce(
            failure,
            for: account.key,
            hasActiveHandoff: hasActiveHandoff(for: account)
        ), let message = failureMessage(for: account) else { return }
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

    /// QA1: claim the current connection's payoff with the coordinator generation that
    /// its delayed settle is allowed to end. Render harnesses have no coordinator token.
    static func claimConnectedPayoff(
        for account: ProviderAccount
    ) -> SetupSessionActivity.ConnectedPayoffClaim? {
        let coordinatorToken = coordinator?.connectedPayoffToken(for: account.key)
        guard coordinator == nil || coordinatorToken != nil else { return nil }
        guard isConnected(account) else { return nil }
        return SetupSessionActivity.shared.claimConnectedPayoff(
            for: account.key,
            coordinatorToken: coordinatorToken
        )
    }

    /// QA1: settle only the connection that created this delayed payoff. A reset advances the
    /// coordinator generation and releases the old claim before its Terminal handoff starts.
    static func settle(
        for account: ProviderAccount,
        connectedPayoffClaim claim: SetupSessionActivity.ConnectedPayoffClaim
    ) {
        guard SetupSessionActivity.shared.releaseConnectedPayoff(claim, for: account.key) else {
            return
        }
        if let coordinator {
            guard let token = claim.coordinatorToken,
                  coordinator.settleConnected(account.key, token: token) else { return }
            SetupSessionActivity.shared.endWaiting(for: account.key)
            refusedHandoffPurposes.removeValue(forKey: account.key)
            return
        }
        settle(for: account)
    }

    /// End an account's handoff session: cancel pending retries and clear the waiting
    /// flag. Called when the account goes live — and when it's removed, so orphaned
    /// retry tasks can't keep spawning poll cycles for a deleted account.
    static func settle(for account: ProviderAccount) {
        SetupSessionActivity.shared.endWaiting(for: account.key)
        SetupSessionActivity.shared.releaseConnectedPayoff(for: account.key)
        // Review #1: a connected account has nothing left to resume.
        refusedHandoffPurposes.removeValue(forKey: account.key)
        if let coordinator {
            if let token = coordinator.connectedPayoffToken(for: account.key) {
                coordinator.settleConnected(account.key, token: token)
            }
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
        handoffTerminalApps.removeValue(forKey: account.key)
        handoffInteractiveReasons.removeValue(forKey: account.key)
        // Review #1: the user abandoned this attempt, so its refusal describes nothing.
        refusedHandoffPurposes.removeValue(forKey: account.key)
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

    /// KTD1/KTD4 (2026-09-19 sign-in plan): resolved executable plus the account's
    /// environment overrides in, the CLI's raw `--version` output out, or nil when it
    /// cannot be read. Injected so staging tests never spawn the real CLI.
    typealias ClaudeVersionReading = @Sendable (String, [String: String]) async -> String?

    static let readClaudeVersion: ClaudeVersionReading = { executablePath, environmentOverrides in
        await ClaudeUsageCLIProbe.versionOutput(
            executablePath: executablePath,
            environmentOverrides: environmentOverrides
        )
    }

    static func prepareHandoff(
        for account: ProviderAccount,
        mode: SetupHandoffMode,
        purpose: SetupHandoffPurpose = .setup,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL,
        claudeExecutableLocator: any CLIExecutableLocating = CLIExecutableLocator.claude(),
        claudeVersionReader: @escaping ClaudeVersionReading = readClaudeVersion
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
                var stagedScriptKind: ClaudeSetupScriptKind?
                var stagedInteractiveReason: ClaudeInteractiveLaunchReason?
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
                    let kind = await claudeScriptKind(
                        for: account,
                        purpose: purpose,
                        executablePath: executable,
                        configDirectory: configuration.claudeConfigDirectory?.path,
                        readVersion: claudeVersionReader
                    )
                    guard case .stage(let stagedKind, let interactiveReason) = kind else {
                        return .failure(.updateRequired)
                    }
                    stagedScriptKind = stagedKind
                    stagedInteractiveReason = interactiveReason
                    let fallback = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    let descriptor = ClaudeSetupDescriptor(
                        accountKey: account.key,
                        executablePath: executable,
                        loginPath: CLIExecutableResolver.resolveLoginPath(fallback: fallback),
                        workspaceDirectory: workspace.path,
                        configDirectory: configuration.claudeConfigDirectory?.path,
                        purpose: purpose,
                        completionMarker: completionMarker,
                        scriptKind: stagedKind
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
                        mode: mode,
                        executablePath: executable
                    )
                case .cursor:
                    guard let executable = CursorCLI.resolveExecutable() else {
                        return .failure(.executableMissing)
                    }
                    if purpose == .trust || purpose == .approval {
                        let workspace = CursorUsageCLIProbe.defaultWorkspace
                        try FileManager.default.createDirectory(
                            at: workspace,
                            withIntermediateDirectories: true,
                            attributes: [.posixPermissions: 0o700]
                        )
                        try FileManager.default.setAttributes(
                            [.posixPermissions: 0o700],
                            ofItemAtPath: workspace.path
                        )
                        script = purpose == .trust
                            ? CursorCLI.workspaceTrustScript(
                                executablePath: executable,
                                workspaceDirectory: workspace.path,
                                completionMarker: completionMarker
                            )
                            : CursorCLI.mcpApprovalScript(
                                executablePath: executable,
                                workspaceDirectory: workspace.path,
                                completionMarker: completionMarker
                            )
                        manualCommand = CursorCLI.workspaceTrustCommand(
                            executablePath: executable,
                            workspaceDirectory: workspace.path
                        )
                    } else {
                        script = CursorCLI.loginScript(
                            executablePath: executable,
                            completionMarker: completionMarker
                        )
                        manualCommand = CursorCLI.manualLoginCommand(executablePath: executable)
                    }
                default:
                    return .failure(.stagingFailed)
                }
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
                return .success(PreparedScript(
                    scriptURL: scriptURL,
                    completionMarker: completionMarker,
                    manualCommand: manualCommand,
                    claudeScriptKind: stagedScriptKind,
                    claudeInteractiveReason: stagedInteractiveReason
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
                purpose: purpose,
                claudeScriptKind: preparedScript.claudeScriptKind
            ))
        case .failure(let failure):
            // Review #1: the refusal is the one place this purpose still exists — the
            // coordinator drops it the moment the failure settles with no handoff open.
            if failure == .updateRequired {
                refusedHandoffPurposes[account.key] = purpose
            }
            return .failure(failure)
        }
    }

    /// KTD1: staging either writes one of the two Claude scripts or refuses outright.
    /// KTD11: an `interactive` decision also carries *why*, because the waiting copy turns
    /// on it and no view may re-read the CLI version to find out.
    private enum ClaudeStagingDecision {
        case stage(ClaudeSetupScriptKind, ClaudeInteractiveLaunchReason?)
        case refuseUpdateRequired
    }

    /// KTD1 (2026-09-19 sign-in plan): the whole staging rule, read once from one `--version`
    /// capture. Nothing here runs an `auth` subcommand to probe support — an older CLI could
    /// take one as a paid model prompt (`docs/solutions/claude-print-mode-usage-probe.md`).
    private static func claudeScriptKind(
        for account: ProviderAccount,
        purpose: SetupHandoffPurpose,
        executablePath: String,
        configDirectory: String?,
        readVersion: ClaudeVersionReading
    ) async -> ClaudeStagingDecision {
        // The approval prompt appears only in the interactive CLI, and the sign-in script's
        // status guard would exit before it on an account that is already signed in (AE3).
        // No version gates it: refusing would leave an approvable account with nothing to
        // click.
        guard purpose == .setup || purpose == .reset else { return .stage(.interactive, nil) }

        let versionOutput = await readVersion(
            executablePath,
            configDirectory.map { ["CLAUDE_CONFIG_DIR": $0] } ?? [:]
        )
        switch versionOutput.map(ClaudeUsageCLIProbe.signInSupport(versionOutput:)) ?? .unreadable {
        case .tooOld:
            // R6: these CLIs can sign in and still never be confirmed, because every usage
            // check reads `auth status`.
            return .refuseUpdateRequired
        case .unreadable:
            // R6: a change to the CLI's version format must not lock everyone out of sign-in.
            return .stage(.interactive, .versionUnreadable)
        case .supported:
            break
        }
        // AE7: an extra account below the print-mode floor is a never-onboarded config on the
        // PTY path, where the bare launch shows the CLI's own login selector and then the
        // approval prompt in one Terminal trip.
        let belowPrintModeFloor = !(versionOutput.map(
            ClaudeUsageCLIProbe.printUsageSupported(versionOutput:)
        ) ?? false)
        if !account.isBuiltIn, belowPrintModeFloor {
            return .stage(.interactive, .neverOnboardedExtraAccount)
        }
        // KTD1: `.reset` keeps its own `auth logout && auth login` script — the descriptor
        // selects that by purpose — so the kind stamped here only describes the shape the
        // waiting policy sees: a CLI auth command that drives the window and exits.
        return .stage(.signIn, nil)
    }

    static let handoffTerminalBundleIdentifier = "com.apple.Terminal"

    /// KTD13 live-QA correction: `.command` handlers are not execution contracts. An editor
    /// can claim the type, and
    /// Ghostty can accept the LaunchServices request without starting the script. The marker
    /// protocol requires a process to run, so setup uses the system Terminal explicitly.
    static func openHandoffScript(
        _ scriptURL: URL,
        in applicationURL: URL,
        open: (URL, URL) async -> Bool
    ) async -> Bool {
        await open(scriptURL, applicationURL)
    }

    static func handoffTerminalApplicationURL(
        resolveApplication: (String) -> URL?
    ) -> URL? {
        resolveApplication(handoffTerminalBundleIdentifier)
    }

    private static func openHandoffScript(
        _ scriptURL: URL,
        in applicationURL: URL
    ) async -> Bool {
        await openHandoffScript(scriptURL, in: applicationURL) { scriptURL, applicationURL in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.open(
                    [scriptURL],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                )
                return true
            } catch {
                return false
            }
        }
    }

    private static func openPreparedHandoff(_ handoff: PreparedSetupHandoff) async -> SetupOpenResult {
        await openPreparedHandoff(
            handoff,
            resolveTerminalApplication: {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            },
            openScript: { scriptURL, applicationURL in
                await openHandoffScript(scriptURL, in: applicationURL)
            },
            copy: copyCommand
        )
    }

    /// App-boundary seam for the two Terminal failure paths. Tests supply inert closures so
    /// they can prove marker/script cleanup without opening an application or pasteboard.
    static func openPreparedHandoff(
        _ handoff: PreparedSetupHandoff,
        resolveTerminalApplication: (String) -> URL?,
        openScript: (URL, URL) async -> Bool,
        copy: (String) -> Bool
    ) async -> SetupOpenResult {
        guard let prepared = preparedScripts.removeValue(forKey: handoff.accountKey) else {
            return .failure(.stagingFailed)
        }
        let generation: String
        do {
            generation = try AccountStorage.prepareSetupCompletionMarker(
                prepared.completionMarker,
                mode: handoff.mode,
                purpose: handoff.purpose
            )
        } catch {
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return .failure(.stagingFailed)
        }
        guard let terminalApplicationURL = handoffTerminalApplicationURL(
            resolveApplication: resolveTerminalApplication
        ) else {
            AccountStorage.clearPreparedSetupCompletionMarker(prepared.completionMarker)
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return copy(prepared.manualCommand)
                ? .failure(.terminalRejected)
                : .failure(.pasteboardFailed)
        }
        // KTD8: save the decisions a relaunch cannot re-derive, beside the generation and
        // outside the marker lines the wrapper pins. A record that cannot be written is
        // not worth refusing the handoff over — restore falls back by purpose.
        try? AccountStorage.writeSetupHandoffRecord(
            SetupHandoffRecord(
                waitingPolicy: .staged(
                    providerID: handoff.accountKey.providerID,
                    purpose: handoff.purpose,
                    claudeScriptKind: handoff.claudeScriptKind
                ),
                terminalBundleIdentifier: handoffTerminalBundleIdentifier,
                claudeInteractiveReason: prepared.claudeInteractiveReason
            ),
            marker: prepared.completionMarker,
            generation: generation
        )
        // QA2: the opener suspends. Transfer ownership before crossing that boundary so Stop
        // Waiting can always find and remove the script while Terminal is still launching.
        activeScripts[handoff.accountKey] = prepared
        let opened = await openScript(prepared.scriptURL, terminalApplicationURL)
        guard activeScripts[handoff.accountKey]?.scriptURL == prepared.scriptURL else {
            // QA2: cancellation (or a successor handoff) took ownership while the opener was
            // suspended. Its marker state is authoritative; never register this stale launch.
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return .failure(.terminalRejected)
        }
        guard opened else {
            activeScripts.removeValue(forKey: handoff.accountKey)
            AccountStorage.clearPreparedSetupCompletionMarker(prepared.completionMarker)
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return copy(prepared.manualCommand)
                ? .failure(.terminalRejected)
                : .failure(.pasteboardFailed)
        }
        noteHandoffTerminalApp(handoffTerminalBundleIdentifier, for: handoff.accountKey)
        noteHandoffInteractiveReason(prepared.claudeInteractiveReason, for: handoff.accountKey)
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
            handoffTerminalApps.removeValue(forKey: key)
            handoffInteractiveReasons.removeValue(forKey: key)
            completionTasks[key] = nil
        }
    }

    static func copyCommand(_ command: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(command, forType: .string)
    }
}
