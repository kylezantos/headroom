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
    case cursorUnknownUI
    case cursorTransientCapture

    // W2A: these render in the popover's 295pt recovery line and again, wrapping freely
    // since S2B, in a ≈197pt account state row. The `\u{00A0}` runs glue tails that would otherwise
    // wrap to a bare orphan at 295 ("CLI" at 7%, "read it" at 13%) and keep an em dash
    // off the start of a line; they are inert at the narrower measure.
    public var message: String {
        switch self {
        case .claudeCLIMissing: "Install Claude Code to show usage"
        case .claudeLoginRequired: "Sign in with the official Claude CLI"
        case .claudeTrustRequired: "Approve Headroom's workspace in\u{00A0}the\u{00A0}Claude\u{00A0}CLI"
        case .claudeUnknownUI: "Claude opened an unrecognized setup screen"
        case .claudeTransientCapture: "Couldn't read Claude usage — will retry"
        case .codexCLIMissing: "Install Codex CLI to connect"
        case .codexAuthAbsent: "Connect with the official Codex CLI"
        case .codexPermissionDenied: "Allow Headroom to read the Codex sign-in file"
        case .codexUnsafePermissions: "Codex sign-in isn't stored privately\u{00A0}—\u{00A0}reconnect"
        case .codexMalformedAuth: "Codex sign-in data is unreadable — reconnect"
        case .codexCredentialIO: "Couldn't read Codex sign-in data"
        case .codexRejectedAuth: "Codex sign-in expired — reconnect"
        case .codexStorageMismatch: "Codex saved this login where Headroom can't\u{00A0}read\u{00A0}it"
        case .codexCallbackIncomplete: "Codex sign-in did not finish"
        case .grokCLIMissing: "Install Grok Build to show usage"
        case .grokAuthAbsent: "Connect with the official Grok Build CLI"
        case .grokPermissionDenied: "Allow Headroom to read the Grok sign-in file"
        case .grokUnsafePermissions: "Grok sign-in isn't stored privately\u{00A0}—\u{00A0}reconnect"
        case .grokMalformedAuth: "Grok sign-in data is unreadable — reconnect"
        case .grokCredentialIO: "Couldn't read Grok sign-in data"
        case .grokRejectedAuth: "Grok sign-in expired — reconnect"
        case .grokTransientCapture: "Couldn't read Grok usage — will retry"
        case .cursorCLIMissing: "Install Cursor Agent to show usage"
        case .cursorAuthAbsent: "Connect with the official Cursor Agent CLI"
        case .cursorUnknownUI: "Cursor Agent opened an unrecognized screen"
        case .cursorTransientCapture: "Couldn't read Cursor usage — will retry"
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .claudeUnknownUI, .claudeTransientCapture, .codexCredentialIO,
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

    public var recoveryPresentation: ProviderRecoveryPresentation {
        switch self {
        case .claudeCLIMissing:
            // R7: mirrors the capability presentation — install guidance plus a fresh
            // discovery check, never a copied bare-name command.
            .init(status: message, primaryLabel: "Install Claude Code", primaryAction: .installClaudeCLI,
                  secondaryLabel: "Check again", secondaryAction: .checkNow)
        case .claudeLoginRequired:
            .init(status: message, primaryLabel: "Open Claude setup", primaryAction: .openClaudeSetup,
                  secondaryLabel: "Check now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeTrustRequired:
            .init(status: message, primaryLabel: "Open Claude workspace", primaryAction: .openClaudeSetup,
                  secondaryLabel: "Check now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeUnknownUI, .claudeTransientCapture:
            .init(status: message, primaryLabel: "Check again", primaryAction: .checkNow,
                  secondaryLabel: "Open guided setup", secondaryAction: .openClaudeSetup)
        case .codexCLIMissing:
            .init(status: message, primaryLabel: "Install Codex CLI", primaryAction: .installCodexCLI)
        case .codexAuthAbsent:
            .init(status: message, primaryLabel: "Connect Codex", primaryAction: .connectCodex,
                  secondaryLabel: "Use device code", secondaryAction: .connectCodexDeviceCode,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .codexPermissionDenied:
            .init(status: message, primaryLabel: "Privacy & Security help", primaryAction: .showPrivacyGuidance,
                  secondaryLabel: "Check now", secondaryAction: .checkNow)
        case .codexUnsafePermissions, .codexMalformedAuth, .codexRejectedAuth:
            .init(status: message, primaryLabel: "Reconnect Codex", primaryAction: .reconnectCodex,
                  secondaryLabel: "Check now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .codexCredentialIO:
            .init(status: message, primaryLabel: "Check again", primaryAction: .checkNow)
        case .codexStorageMismatch:
            .init(status: message, primaryLabel: "Resolve storage", primaryAction: .resolveCodexStorage,
                  secondaryLabel: "Check now", secondaryAction: .checkNow)
        case .codexCallbackIncomplete:
            .init(status: message, primaryLabel: "Reopen Codex login", primaryAction: .reconnectCodex,
                  secondaryLabel: "Use device code", secondaryAction: .connectCodexDeviceCode)
        case .grokCLIMissing:
            .init(status: message, primaryLabel: "Install Grok Build", primaryAction: .installGrokCLI)
        case .grokAuthAbsent:
            .init(status: message, primaryLabel: "Connect Grok", primaryAction: .connectGrok,
                  secondaryLabel: "Use device code", secondaryAction: .connectGrokDeviceCode,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .grokPermissionDenied:
            .init(status: message, primaryLabel: "Privacy & Security help", primaryAction: .showPrivacyGuidance,
                  secondaryLabel: "Check now", secondaryAction: .checkNow)
        case .grokUnsafePermissions, .grokMalformedAuth, .grokRejectedAuth:
            .init(status: message, primaryLabel: "Reconnect Grok", primaryAction: .reconnectGrok,
                  secondaryLabel: "Check now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .grokCredentialIO, .grokTransientCapture:
            .init(status: message, primaryLabel: "Check again", primaryAction: .checkNow)
        case .cursorCLIMissing:
            .init(status: message, primaryLabel: "Install Cursor Agent", primaryAction: .installCursorAgent)
        case .cursorAuthAbsent:
            .init(status: message, primaryLabel: "Connect Cursor", primaryAction: .connectCursor,
                  secondaryLabel: "Check now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .cursorUnknownUI, .cursorTransientCapture:
            .init(status: message, primaryLabel: "Check again", primaryAction: .checkNow,
                  secondaryLabel: "Reconnect Cursor", secondaryAction: .connectCursor)
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
