import Foundation

// Mac-only by folder: this file reads coordinator and session types that live in Engine,
// which the iOS targets never compile (KTD4). Only the safe `CompanionAttention` result
// crosses into the wire projection (contract Decision 5).

/// The typed setup-session facts AppComposition hands the projector for one account.
/// No title, ID, path or associated source string is part of it.
public struct CompanionSessionInput: Equatable, Sendable {
    public let state: SetupSessionState
    public let purpose: SetupHandoffPurpose?
    public let interactiveReason: ClaudeInteractiveLaunchReason?

    public init(
        state: SetupSessionState, purpose: SetupHandoffPurpose? = nil,
        interactiveReason: ClaudeInteractiveLaunchReason? = nil
    ) {
        self.state = state
        self.purpose = purpose
        self.interactiveReason = interactiveReason
    }
}

/// KTD10 / Decision 5: the complete many-to-one table from every source case to a wire
/// attention value. Every switch is exhaustive with no default, so a new source case
/// fails to compile until it is mapped.
public enum CompanionAttentionMapping {
    public static func attention(for outcome: ProviderSetupOutcome) -> CompanionAttention {
        switch outcome {
        case .claudeCLIMissing, .codexCLIMissing, .grokCLIMissing, .cursorCLIMissing:
            .cliMissing
        case .claudeLoginRequired, .codexAuthAbsent, .grokAuthAbsent, .cursorAuthAbsent:
            .signInRequired
        case .claudeTrustRequired, .cursorTrustRequired:
            .workspaceApproval
        case .claudeUnknownUI, .cursorUnknownUI:
            .setupScreenUnknown
        // Credential IO is retryable, never proof the credentials were rejected.
        case .claudeTransientCapture, .codexCredentialIO, .grokCredentialIO,
            .grokTransientCapture, .cursorTransientCapture:
            .retrying
        case .codexPermissionDenied, .grokPermissionDenied:
            .allowSignInFile
        // Unsafe permissions recover by signing in again; no permission bits or path export.
        case .codexUnsafePermissions, .grokUnsafePermissions, .codexRejectedAuth,
            .grokRejectedAuth:
            .signInAgain
        case .codexMalformedAuth, .grokMalformedAuth:
            .signInFileUnreadable
        case .codexStorageMismatch:
            .signInStorageMismatch
        // Not "finishing sign-in": without an active typed session that would be a claim.
        case .codexCallbackIncomplete:
            .setupFailed
        case .cursorMCPApprovalRequired:
            .externalToolsApproval
        }
    }

    /// Associated strings are ignored: copy comes only from the typed category.
    public static func attention(for reason: FailureReason) -> CompanionAttention {
        switch reason {
        case .transient, .decode: .retrying
        case .needsReauth: .signInAgain
        case .scopeDenied: .accessDenied
        case .notLoggedIn: .signInRequired
        case .providerSetup(let outcome): attention(for: outcome)
        }
    }

    /// Provider scope only: capability failures never enter account snapshots.
    public static func capabilityAttention(for state: ProviderCapabilityState) -> CompanionAttention? {
        switch state {
        // Pending stays pending, and a running search never claims absence.
        case .unknown, .discovering, .available: nil
        case .inconclusive(let issue): attention(for: issue)
        case .confirmedAbsent: .cliMissing
        }
    }

    /// Every discovery issue is one inconclusive category; no detail or path crosses.
    public static func attention(for issue: CLIExecutableDiscoveryIssue) -> CompanionAttention {
        switch issue {
        case .shellTimeout, .shellSpawnFailure, .invalidShellOutput, .inaccessibleCandidate,
            .invalidatedHint, .launchRace, .npmPrefixUnresolved:
            .cliDiscoveryRetrying
        }
    }

    /// Account-scope attention for a failed session. Capability failures belong to the
    /// provider (`providerAttention(for:)`) and leave the account's base state alone.
    public static func attention(for failure: SetupSessionFailure) -> CompanionAttention? {
        switch failure {
        case .executableMissing: .cliMissing
        // Sourced from the typed staging refusal, never from matching "update" in text.
        case .updateRequired: .cliUpdateRequired
        case .stagingFailed, .terminalRejected, .pasteboardFailed, .retryExhausted: .setupFailed
        // The bounded wait expired: never claim success or an active check.
        case .waitingTimedOut: .setupFailed
        case .closedBeforeSignIn: .signInRequired
        case .provider(let outcome): attention(for: outcome)
        case .providerCapability: nil
        }
    }

    public static func providerAttention(for failure: SetupSessionFailure) -> CompanionAttention? {
        guard case .providerCapability(let state) = failure else { return nil }
        return capabilityAttention(for: state)
    }

    /// The overlay a live typed session puts over an account's snapshot attention.
    public static func sessionOverlay(_ input: CompanionSessionInput) -> CompanionAttention? {
        switch input.state {
        case .idle, .connected, .cancelled, .removing, .removalFailed, .removed:
            return nil
        case .preparing:
            // Before a real session begins, a staged never-onboarded launch says so.
            return input.interactiveReason == .neverOnboardedExtraAccount
                ? .neverOnboarded : .setupInProgress
        case .waiting, .verifying:
            switch input.purpose {
            case .trust: return .workspaceApproval
            case .approval: return .externalToolsApproval
            // An unreadable version is not an update requirement; the prompt decides.
            case .setup, .reset, nil: return .finishingSignIn
            }
        case .blockedByOpenHandoff, .blockedByProviderLogin:
            // Never serialize the blocking account's title or ID.
            return .setupBlocked
        case .failed(let failure):
            return attention(for: failure)
        }
    }

    /// The snapshot's own attention, with the never-onboarded extra specialization. Uses
    /// the existing semantic classifier plus the registry's built-in flag, never the main
    /// account, `AccountID.primary`, a nil capture or an email/auth-file read.
    public static func baseAttention(freshness: Freshness, isBuiltIn: Bool) -> CompanionAttention? {
        switch freshness {
        case .pending, .live:
            return nil
        case .stale(let reason):
            if !isBuiltIn, reason.providerSetupOutcome?.isNeverSignedIn == true {
                return .neverOnboarded
            }
            return attention(for: reason)
        }
    }

    /// Precedence: a current typed session overlay wins over older snapshot text; with
    /// no overlay, the base snapshot attention.
    public static func accountAttention(
        freshness: Freshness, isBuiltIn: Bool, session: CompanionSessionInput?
    ) -> CompanionAttention? {
        session.flatMap(sessionOverlay) ?? baseAttention(freshness: freshness, isBuiltIn: isBuiltIn)
    }

    /// Provider-level line. A known capability state is authoritative (available clears
    /// it); only an unknown capability falls back to a session's typed capability failure.
    public static func providerAttention(
        capability: ProviderCapabilityState?, sessions: [CompanionSessionInput]
    ) -> CompanionAttention? {
        switch capability {
        case .available?, .discovering?: return nil
        case .inconclusive(let issue)?: return attention(for: issue)
        case .confirmedAbsent?: return .cliMissing
        case .unknown?, nil:
            for session in sessions {
                if case .failed(let failure) = session.state, let attention = providerAttention(for: failure) {
                    return attention
                }
            }
            return nil
        }
    }

    /// Source permanence for the stale `h` flag, independent of any session overlay.
    public static func needsAttention(_ freshness: Freshness) -> Bool? {
        guard case .stale(let reason) = freshness else { return nil }
        return reason.isPermanent
    }
}

/// The composition seam: AppComposition injects the per-account session lookup as a
/// closure, so the projector never reaches into the coordinator (Decision 5).
public struct CompanionAttentionMapper: Sendable {
    private let session: @MainActor @Sendable (AccountKey) -> CompanionSessionInput?

    public init(session: @escaping @MainActor @Sendable (AccountKey) -> CompanionSessionInput?) {
        self.session = session
    }

    @MainActor
    public func accountAttention(for key: AccountKey, freshness: Freshness, isBuiltIn: Bool)
        -> CompanionAttention?
    {
        CompanionAttentionMapping.accountAttention(
            freshness: freshness, isBuiltIn: isBuiltIn, session: session(key))
    }

    @MainActor
    public func providerAttention(accounts: [AccountKey], capability: ProviderCapabilityState?)
        -> CompanionAttention?
    {
        CompanionAttentionMapping.providerAttention(
            capability: capability, sessions: accounts.compactMap(session))
    }
}
