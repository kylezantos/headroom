/// R2C6 — one verb for the whole flow: **sign in**. The app used to name one act four ways
/// ("sign in" / "connect" / "set up" / "needs sign-in"), so a status sentence, a card title,
/// the popover header and a Settings row could each call it something different and the
/// reader had to work out whether the buttons did different things. All four CLIs call it
/// `login`; "connect" describes nothing the user actually does.
///
/// The wording lives in Core rather than in a view because four surfaces render it — the
/// popover card, the popover header, the guided setup card and the Settings account row —
/// and a rename that reaches three of them is how the four names happened the first time.
public enum ProviderSignInCopy {
    /// B3T: every label here is a button on some surface, so both are Title Case.
    public static let button = "Sign In"
    public static let buttonAgain = "Sign In Again"

    /// The official CLI a provider's sign-in runs in, named the way its own docs name it.
    public static func cliName(for providerID: ProviderID) -> String {
        switch providerID {
        case .claude: "Claude CLI"
        case .codex: "Codex CLI"
        case .grok: "Grok Build CLI"
        case .cursor: "Cursor Agent CLI"
        default: "\(providerID.displayName) CLI"
        }
    }

    /// The name install and discovery copy uses. Claude's command ships inside the Claude
    /// Code product, so "not installed" has to name the product a user would go and get;
    /// the sign-in sentence names the command they run.
    public static func cliProductName(for providerID: ProviderID) -> String {
        providerID == .claude ? "Claude Code CLI" : cliName(for: providerID)
    }

    /// The account-state sentence shared by the popover card and the Settings account row.
    public static func status(for providerID: ProviderID, again: Bool = false) -> String {
        "\(again ? "Sign in again" : "Sign in") with the official \(cliName(for: providerID))"
    }

    /// PA10's one-line popover header, derived from the same state the card switches on.
    public static func header(for providerID: ProviderID, again: Bool = false) -> String {
        again
            ? "Sign in to \(providerID.displayName) again"
            : "Sign in to \(providerID.displayName) to begin"
    }

    /// The guided setup card's title.
    public static func cardTitle(for providerID: ProviderID, again: Bool = false) -> String {
        again
            ? "Sign in to \(providerID.displayName) again"
            : "Sign in to \(providerID.displayName)"
    }

    /// R2C7: the sentence states the cause; the button beside it names the act. "Install
    /// Claude Code to show usage" sat directly above **Install Claude Code**, spending the
    /// card's one explanatory line restating its own button.
    ///
    /// Claude's reads as a failed *search* because Headroom's locator can also come back
    /// inconclusive (`ProviderCapabilityState`) and neither state may claim more than it
    /// knows; the other three read a file their CLI either wrote or didn't.
    ///
    /// `hasRetainedReading` is true when the card is still showing numbers from an earlier
    /// capture. A "can't find the CLI" sentence above three live-looking percentages leaves
    /// the reader to decide which one to believe, so the sentence reconciles them itself.
    public static func cliMissing(for providerID: ProviderID, hasRetainedReading: Bool = false) -> String {
        let name = cliProductName(for: providerID)
        if hasRetainedReading {
            return "Headroom can’t find the \(name)\u{00A0}—\u{00A0}showing the last reading"
        }
        return providerID == .claude
            ? "Headroom can’t find the \(name) on this Mac"
            : "\(name) isn’t installed on this Mac"
    }
}

/// KTD1/R6 (2026-09-19 sign-in plan): why staging chose the interactive launch over the
/// sign-in script. The two reasons need different waiting copy — an unreadable version
/// leaves the user at the CLI's own screen with `/login` to type, while a never-onboarded
/// extra config shows the CLI's login selector by itself (AE7) — and neither can be
/// re-derived at render time, because the installed CLI can change while the original
/// Terminal is still open.
public enum ClaudeInteractiveLaunchReason: String, Sendable, Equatable, CaseIterable {
    case versionUnreadable
    case neverOnboardedExtraAccount
}

/// KTD11: what an open handoff is asking the user for. It is the one dimension the waiting
/// and confirming copy both turn on, so a workspace approval never borrows a sign-in
/// sentence and vice versa.
public enum SetupWaitingPrompt: Sendable, Equatable, CaseIterable {
    case signIn
    /// R6: the interactive launch chosen because the CLI's version could not be read. The
    /// CLI shows its own screen and the user has to type `/login` there.
    case signInNeedsLoginCommand
    case workspaceApproval
    case deviceCode
}

/// KTD11: the literal the user has to pick or type, set apart from the prose in the card's
/// quiet bordered box rather than bolded inside a sentence.
public struct SetupWaitingToken: Sendable, Equatable {
    public let text: String
    /// True when the token is something the user types, so a card sets it in the same
    /// monospaced face the manual-command disclosure uses and drops the "choose this"
    /// checkmark that belongs to an option.
    public let isCommand: Bool

    public init(text: String, isCommand: Bool) {
        self.text = text
        self.isCommand = isCommand
    }
}

public struct SetupWaitingCopy: Sendable, Equatable {
    public let title: String
    public let body: String
    public let token: SetupWaitingToken?

    public init(title: String, body: String, token: SetupWaitingToken? = nil) {
        self.title = title
        self.body = body
        self.token = token
    }
}

/// A provider/setup condition that changes which recovery action Headroom may offer.
/// These values deliberately carry no provider output, paths, account identity, or
/// caught errors. Presentation copy is derived separately so behavior never depends
/// on matching a user-facing string.
public enum ProviderSetupOutcome: Sendable, Equatable, Hashable {
    case claudeCLIMissing
    case claudeLoginRequired
    case claudeTrustRequired
    case claudeUnknownUI
    case claudeTransientCapture
    case codexCLIMissing
    case codexAuthAbsent
    case codexPermissionDenied
    case codexUnsafePermissions
    case codexMalformedAuth
    case codexCredentialIO
    case codexRejectedAuth
    case codexSessionUnverified
    case codexStorageMismatch
    case codexCallbackIncomplete
    case grokCLIMissing
    case grokAuthAbsent
    case grokPermissionDenied
    case grokUnsafePermissions
    case grokMalformedAuth
    case grokCredentialIO
    case grokRejectedAuth
    case grokTransientCapture
    case cursorCLIMissing
    case cursorAuthAbsent
    case cursorTrustRequired
    case cursorMCPApprovalRequired
    case cursorUnknownUI
    case cursorTransientCapture

    // W2A: these render in the popover's 295pt recovery line and again, wrapping freely
    // since S2B, in a ≈197pt account state row. The `\u{00A0}` runs glue tails that would otherwise
    // wrap to a bare orphan at 295 ("CLI" at 7%, "read it" at 13%) and keep an em dash
    // off the start of a line; they are inert at the narrower measure.
    //
    // R2B1: the nbsp-around-em-dash rule now covers the whole set rather than a sample of
    // it — five of the nine dashes were bare, so the same construction wrapped two ways
    // depending on which case produced it.
    //
    // R2C6: the sign-in sentences come from `ProviderSignInCopy`. The "— reconnect" tails
    // became "— sign in again" for the same reason: they are the prose half of a button
    // that now reads "Sign In Again".
    public var message: String {
        switch self {
        case .claudeCLIMissing: ProviderSignInCopy.cliMissing(for: .claude)
        case .claudeLoginRequired: ProviderSignInCopy.status(for: .claude)
        case .claudeTrustRequired: "Approve Headroom’s workspace in\u{00A0}the\u{00A0}Claude\u{00A0}CLI"
        case .claudeUnknownUI: "Claude opened an unrecognized setup screen"
        case .claudeTransientCapture: "Couldn’t read Claude usage\u{00A0}—\u{00A0}will retry"
        case .codexCLIMissing: ProviderSignInCopy.cliMissing(for: .codex)
        case .codexAuthAbsent: ProviderSignInCopy.status(for: .codex)
        case .codexPermissionDenied: "Allow Headroom to read the Codex sign-in file"
        case .codexUnsafePermissions: "Codex sign-in isn’t stored privately\u{00A0}—\u{00A0}sign in again"
        case .codexMalformedAuth: "Codex sign-in data is unreadable\u{00A0}—\u{00A0}sign in again"
        case .codexCredentialIO: "Couldn’t read Codex sign-in data"
        // R2C6: the canonical re-auth state, so it carries the re-auth sentence verbatim;
        // the two diagnostic siblings above keep their cause and take only the new tail.
        case .codexRejectedAuth: ProviderSignInCopy.status(for: .codex, again: true)
        case .codexSessionUnverified: "Couldn’t verify the Codex session"
        case .codexStorageMismatch: "Codex saved this login where Headroom can’t\u{00A0}read\u{00A0}it"
        case .codexCallbackIncomplete: "Codex sign-in did not finish"
        case .grokCLIMissing: ProviderSignInCopy.cliMissing(for: .grok)
        case .grokAuthAbsent: ProviderSignInCopy.status(for: .grok)
        case .grokPermissionDenied: "Allow Headroom to read the Grok sign-in file"
        case .grokUnsafePermissions: "Grok sign-in isn’t stored privately\u{00A0}—\u{00A0}sign in again"
        case .grokMalformedAuth: "Grok sign-in data is unreadable\u{00A0}—\u{00A0}sign in again"
        case .grokCredentialIO: "Couldn’t read Grok sign-in data"
        case .grokRejectedAuth: ProviderSignInCopy.status(for: .grok, again: true)
        case .grokTransientCapture: "Couldn’t read Grok usage\u{00A0}—\u{00A0}will retry"
        case .cursorCLIMissing: ProviderSignInCopy.cliMissing(for: .cursor)
        case .cursorAuthAbsent: ProviderSignInCopy.status(for: .cursor)
        case .cursorTrustRequired: "Approve Headroom’s workspace in the Cursor Agent CLI"
        case .cursorMCPApprovalRequired: "Review Cursor Agent’s external tools"
        case .cursorUnknownUI: "Cursor Agent opened an unrecognized screen"
        case .cursorTransientCapture: "Couldn’t read Cursor usage\u{00A0}—\u{00A0}will retry"
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .claudeUnknownUI, .claudeTransientCapture, .codexCredentialIO, .codexSessionUnverified,
             .grokCredentialIO, .grokTransientCapture, .cursorUnknownUI,
             .cursorTransientCapture:
            false
        default:
            true
        }
    }

    /// True only when the account has never completed its first official CLI login.
    /// Timer backoff keys off this typed state rather than enumerating providers.
    public var isNeverSignedIn: Bool {
        switch self {
        case .claudeLoginRequired, .codexAuthAbsent, .grokAuthAbsent, .cursorAuthAbsent:
            true
        default:
            false
        }
    }

    /// B3T (Kyle, Sep 2026): every label here is a button on some surface, so all of them
    /// are Title Case — round 3's sentence case made them read as prose beside the sentences
    /// they answer, which is exactly what a chip must not do once B3H removes its resting box.
    ///
    /// PA11: one label per action — `.checkNow` is always "Check Now". The old split ("Check
    /// Again" in a primary slot, "Check Now" in a secondary one) named the same forced poll two
    /// ways on adjacent cards. "Refresh" stays reserved for the footer's whole-app poll.
    ///
    /// R2C6 extends PA11 one level up, on the most consequential action: signing in is
    /// **Sign In** the first time and **Sign In Again** on a re-auth, on every provider and
    /// every surface. "Connect Codex", "Connect Grok", "Connect Cursor", "Reconnect …" and
    /// "Open Claude Setup" were five names for those two acts.
    public var recoveryPresentation: ProviderRecoveryPresentation {
        switch self {
        case .claudeCLIMissing:
            // R7: mirrors the capability presentation — install guidance plus a fresh
            // discovery check, never a copied bare-name command.
            .init(status: message, primaryLabel: "Install Claude Code", primaryAction: .installClaudeCLI,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .claudeLoginRequired:
            .init(status: message, primaryLabel: ProviderSignInCopy.button, primaryAction: .openClaudeSetup,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeTrustRequired:
            // KTD5 (2026-09-19 sign-in plan): approval is its own handoff purpose. Sharing
            // Sign In's action staged the sign-in script, which exits on an already
            // signed-in account before the approval prompt can appear (AE3).
            .init(status: message, primaryLabel: "Open Claude Workspace", primaryAction: .openClaudeWorkspace,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeUnknownUI, .claudeTransientCapture:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow,
                  secondaryLabel: "Open Guided Setup", secondaryAction: .openClaudeSetup)
        case .codexCLIMissing:
            .init(status: message, primaryLabel: "Install Codex CLI", primaryAction: .installCodexCLI)
        case .codexAuthAbsent:
            .init(status: message, primaryLabel: ProviderSignInCopy.button, primaryAction: .connectCodex,
                  secondaryLabel: "Use Device Code", secondaryAction: .connectCodexDeviceCode,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .codexPermissionDenied:
            .init(status: message, primaryLabel: "Privacy & Security Help", primaryAction: .showPrivacyGuidance,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .codexUnsafePermissions, .codexMalformedAuth, .codexRejectedAuth:
            .init(status: message, primaryLabel: ProviderSignInCopy.buttonAgain, primaryAction: .reconnectCodex,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .codexCredentialIO:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow)
        case .codexSessionUnverified:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow,
                  secondaryLabel: ProviderSignInCopy.buttonAgain, secondaryAction: .reconnectCodex)
        case .codexStorageMismatch:
            .init(status: message, primaryLabel: "Resolve Storage", primaryAction: .resolveCodexStorage,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .codexCallbackIncomplete:
            .init(status: message, primaryLabel: "Reopen Codex Login", primaryAction: .reconnectCodex,
                  secondaryLabel: "Use Device Code", secondaryAction: .connectCodexDeviceCode)
        case .grokCLIMissing:
            .init(status: message, primaryLabel: "Install Grok Build", primaryAction: .installGrokCLI)
        case .grokAuthAbsent:
            .init(status: message, primaryLabel: ProviderSignInCopy.button, primaryAction: .connectGrok,
                  secondaryLabel: "Use Device Code", secondaryAction: .connectGrokDeviceCode,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .grokPermissionDenied:
            .init(status: message, primaryLabel: "Privacy & Security Help", primaryAction: .showPrivacyGuidance,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .grokUnsafePermissions, .grokMalformedAuth, .grokRejectedAuth:
            .init(status: message, primaryLabel: ProviderSignInCopy.buttonAgain, primaryAction: .reconnectGrok,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .grokCredentialIO, .grokTransientCapture:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow)
        case .cursorCLIMissing:
            .init(status: message, primaryLabel: "Install Cursor Agent", primaryAction: .installCursorAgent)
        case .cursorAuthAbsent:
            .init(status: message, primaryLabel: ProviderSignInCopy.button, primaryAction: .connectCursor,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .cursorTrustRequired:
            .init(status: message, primaryLabel: "Open Cursor Workspace", primaryAction: .openCursorWorkspace,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .cursorMCPApprovalRequired:
            .init(status: message, primaryLabel: "Review Cursor Tools", primaryAction: .reviewCursorTools,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .cursorUnknownUI, .cursorTransientCapture:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow,
                  secondaryLabel: ProviderSignInCopy.buttonAgain, secondaryAction: .connectCursor)
        }
    }
}

public enum SetupRecoveryAction: Sendable, Equatable, Hashable {
    case installClaudeCLI
    case openClaudeSetup
    case installCodexCLI
    case connectCodex
    case connectCodexDeviceCode
    case reconnectCodex
    case installGrokCLI
    case connectGrok
    case connectGrokDeviceCode
    case reconnectGrok
    case installCursorAgent
    case connectCursor
    case openClaudeWorkspace
    case openCursorWorkspace
    case reviewCursorTools
    case showPrivacyGuidance
    case resolveCodexStorage
    case checkNow
}

public enum SetupAutomaticPolicy: Sendable, Equatable, Hashable {
    case none
    case boundedChecksAfterHandoff
}

public struct ProviderRecoveryPresentation: Sendable, Equatable {
    public let status: String
    public let primaryLabel: String
    public let primaryAction: SetupRecoveryAction
    public let secondaryLabel: String?
    public let secondaryAction: SetupRecoveryAction?
    public let automaticPolicy: SetupAutomaticPolicy

    public init(
        status: String,
        primaryLabel: String,
        primaryAction: SetupRecoveryAction,
        secondaryLabel: String? = nil,
        secondaryAction: SetupRecoveryAction? = nil,
        automaticPolicy: SetupAutomaticPolicy = .none
    ) {
        self.status = status
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
        self.automaticPolicy = automaticPolicy
    }
}

/// Redaction-safe filesystem handshake around an external Terminal setup process.
/// The wrapper writes only its redaction-safe handoff mode/PID and exit status; it
/// never writes provider output, credentials, callback data, paths, or account identity.
public struct SetupCompletionMarker: Sendable, Equatable {
    public let pendingPath: String
    public let completedPath: String

    public init(pendingPath: String, completedPath: String) {
        self.pendingPath = pendingPath
        self.completedPath = completedPath
    }
}
