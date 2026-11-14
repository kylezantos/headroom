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
    ///
    /// CA-P9 (COPY-05): Claude's is "Claude Code", the product the user installed. "Claude CLI"
    /// and "Claude Code CLI" named one program two ways on neighbouring rows.
    public static func cliName(for providerID: ProviderID) -> String {
        switch providerID {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .grok: "Grok Build CLI"
        case .cursor: "Cursor Agent CLI"
        case .copilot: "GitHub Copilot CLI"
        default: "\(providerID.displayName) CLI"
        }
    }

    /// The name install and discovery copy uses. CA-P9: Claude's sign-in and install copy now
    /// both say "Claude Code", so the two names agree; the accessor stays so install rows keep
    /// one place to name the product a user would go and get.
    public static func cliProductName(for providerID: ProviderID) -> String {
        cliName(for: providerID)
    }

    /// The account-state sentence shared by the popover card and the Settings account row.
    public static func status(for providerID: ProviderID, again: Bool = false) -> String {
        "\(again ? "Sign in again" : "Sign in") with the official \(cliName(for: providerID))"
    }

    /// CA-P5: the one-line recovery row's form of `status`, without "the official", which
    /// wrapped "Sign in with the official Claude Code" onto two lines at 295pt. It still
    /// contains the verb, so the row accents it and appends nothing.
    public static func shortStatus(for providerID: ProviderID, again: Bool = false) -> String {
        "\(again ? "Sign in again" : "Sign in") with \(cliName(for: providerID))"
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
    ///
    /// CA-P9: two sentences instead of an em dash, and "Claude Code" without "the".
    public static func cliMissing(for providerID: ProviderID, hasRetainedReading: Bool = false) -> String {
        let name = cliProductName(for: providerID)
        if hasRetainedReading {
            return "Headroom can’t find \(name). Showing the last reading."
        }
        return providerID == .claude
            ? "Headroom can’t find \(name) on this Mac"
            : "\(name) isn’t installed on this Mac"
    }

    /// CA-P5: the one-line recovery row's form of `cliMissing` ("Claude Code not found ·
    /// Install"). The full sentence stays in the row's tooltip.
    public static func cliMissingShort(for providerID: ProviderID) -> String {
        "\(cliProductName(for: providerID)) not found"
    }

    // MARK: CA-P9 setup card copy (COPY-03, COPY-04)
    //
    // R2C6 retired "connect", but the cards still said "reconnects"; "signing in in" read as a
    // typo; the em-dash steps were the one AI tell in plain copy. Each line now says what the
    // user will see. They live beside the sign-in sentences so the cards and Settings cannot
    // word the same promise three ways again.

    /// The last step of the Claude and Codex sign-in cards.
    public static let comeBackStep = "Come back. Your usage shows up here."
    /// The Codex waiting card when the login is the device code.
    public static let codexDeviceCodeWaitingBody =
        "Follow the device-code steps in Terminal. Your usage shows up here when Codex confirms."
    /// The Codex waiting card when the login is in the browser.
    public static let codexBrowserWaitingBody =
        "Finish the ChatGPT sign-in in your browser. Your usage shows up here when Codex confirms."
    /// The Codex re-auth card's body. "Quick" over-promised a device-code or SSO sign-in.
    public static let codexSignedOutBody = "Codex signed you out. Sign in again to keep your usage current."

    /// CA-P9 (COPY-04): one shape for the privacy promise. The claims stay different on
    /// purpose: Codex reads a token file, Claude does not. Nil for a provider whose card
    /// prints no note.
    public static func privacyNote(for providerID: ProviderID) -> String? {
        switch providerID {
        case .claude:
            "Headroom reads the usage report from Claude Code. It never sees your password or tokens, "
                + "and checking doesn’t count against your limits."
        case .codex:
            "You sign in with the official Codex CLI in your browser. Headroom never sees your password."
        default:
            nil
        }
    }

    /// CA-S4 (COPY-04): Settings › Accounts' one trust sentence, in the cards' shape.
    public static let accountsTrustFooter =
        "Each account signs in with its provider’s own CLI in Terminal. Headroom never sees your password."

    /// CA-S5 (COPY-11): the built-in row's "Default" badge tooltip.
    public static func defaultLoginHelp(for providerID: ProviderID) -> String {
        "The account \(cliProductName(for: providerID)) in Terminal is signed in to"
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
    /// Claude Code stopped on a one-time startup question before its prompt (CLI 2.1.312's
    /// Chrome onboarding). The launch is the ordinary `.trust` interactive one; only the
    /// waiting, confirming, timeout and phone copy change, so this reason is what tells
    /// them apart from a workspace approval.
    case startupQuestion
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
    /// The interactive launch opened so the user can answer a startup question Claude Code
    /// asks before its prompt. Headroom never answers it, so the copy names no option.
    case startupQuestion
    case deviceCode
    /// KTD11 (OpenCode plan): Sign Out & Set Up Again. OpenCode's logout opens an account
    /// picker in Terminal before the device-code login, so the copy names that step first.
    case deviceCodeAfterSignOut
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
    /// Claude Code is stopped on a recognized one-time question before its prompt (the Chrome
    /// onboarding). Answering it changes the user's Claude settings, so only the user can.
    case claudeStartupQuestion
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
    case copilotCLIMissing
    case copilotSignedOut
    /// A session log under `~/.copilot` exists but could not be read. A partial sum would
    /// look like a real, lower number, so nothing is shown until every log reads.
    case copilotLogsUnreadable
    // OpenCode plan, KTD3/KTD4/KTD20. KTD22's `opencodeUpdateHeld` is added only if the
    // migration measurement shows the hold is needed.
    case opencodeCLIMissing
    /// The installed `opencode` is older than 2.2.0, so Headroom never runs its usage read.
    case opencodeUpdateRequired
    case opencodeSignedOut
    /// Connected with a stored API key rather than a Console sign-in, which has no Go usage.
    case opencodeConsoleSignInRequired
    /// The usage read says the Console sign-in can no longer be refreshed.
    case opencodeSignInExpired
    /// The usage read's output no longer matches the contract; only a Headroom update fixes it.
    case opencodeFormatChanged
    case opencodeTransientCapture

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
    //
    // CA-P9: no em dashes. A cause and its consequence are two sentences now ("Couldn’t read
    // Claude usage. Headroom tries again on its next check."), the retry sentence in the words
    // the stale chip's tooltip uses (CA-P3), and "workspace" is the folder the CLI asks about.
    public var message: String {
        switch self {
        case .claudeCLIMissing: ProviderSignInCopy.cliMissing(for: .claude)
        case .claudeLoginRequired: ProviderSignInCopy.status(for: .claude)
        case .claudeTrustRequired: "Approve Headroom’s folder in\u{00A0}Claude\u{00A0}Code"
        case .claudeUnknownUI: "Claude opened an unrecognized setup screen"
        case .claudeStartupQuestion: "Claude Code is waiting on a one-time question"
        case .claudeTransientCapture: Self.retrying("Couldn’t read Claude usage")
        case .codexCLIMissing: ProviderSignInCopy.cliMissing(for: .codex)
        case .codexAuthAbsent: ProviderSignInCopy.status(for: .codex)
        case .codexPermissionDenied: "Allow Headroom to read the Codex sign-in file"
        case .codexUnsafePermissions: "Codex sign-in isn’t stored privately. Sign in again to fix it."
        case .codexMalformedAuth: "Codex sign-in data is unreadable. Sign in again to fix it."
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
        case .grokUnsafePermissions: "Grok sign-in isn’t stored privately. Sign in again to fix it."
        case .grokMalformedAuth: "Grok sign-in data is unreadable. Sign in again to fix it."
        case .grokCredentialIO: "Couldn’t read Grok sign-in data"
        case .grokRejectedAuth: ProviderSignInCopy.status(for: .grok, again: true)
        case .grokTransientCapture: Self.retrying("Couldn’t read Grok usage")
        case .cursorCLIMissing: ProviderSignInCopy.cliMissing(for: .cursor)
        case .cursorAuthAbsent: ProviderSignInCopy.status(for: .cursor)
        case .cursorTrustRequired: "Approve Headroom’s folder in\u{00A0}Cursor\u{00A0}Agent"
        case .cursorMCPApprovalRequired: "Review Cursor Agent’s external tools"
        case .cursorUnknownUI: "Cursor Agent opened an unrecognized screen"
        case .cursorTransientCapture: Self.retrying("Couldn’t read Cursor usage")
        case .copilotCLIMissing: ProviderSignInCopy.cliMissing(for: .copilot)
        case .copilotSignedOut: ProviderSignInCopy.status(for: .copilot)
        case .copilotLogsUnreadable: Self.retrying("Couldn’t read Copilot session logs")
        // KTD21's copy table.
        case .opencodeCLIMissing: ProviderSignInCopy.cliMissing(for: .opencode)
        case .opencodeUpdateRequired: "Go usage needs OpenCode 2.2 or newer"
        case .opencodeSignedOut: ProviderSignInCopy.status(for: .opencode)
        case .opencodeConsoleSignInRequired: "Sign in to OpenCode Console to see Go usage"
        case .opencodeSignInExpired: ProviderSignInCopy.status(for: .opencode, again: true)
        case .opencodeFormatChanged: "Headroom can’t read OpenCode usage after an OpenCode change. Contact support"
        case .opencodeTransientCapture: Self.retrying("Couldn’t read OpenCode usage")
        }
    }

    /// CA-P9/CA-P3: a transient failure's two sentences, the second the stale chip's own.
    private static func retrying(_ cause: String) -> String {
        "\(cause). Headroom tries again on its next check."
    }

    /// CA-P5: the one-line recovery row's sentence, short enough that the row's appended
    /// action fits beside it ("Claude Code not found · Install"). `message` stays the full
    /// sentence for Settings and the row's tooltip. Nil keeps `message` (it is already short,
    /// or already names its action).
    var shortMessage: String? {
        switch self {
        case .claudeLoginRequired: ProviderSignInCopy.shortStatus(for: .claude)
        case .codexAuthAbsent: ProviderSignInCopy.shortStatus(for: .codex)
        case .grokAuthAbsent: ProviderSignInCopy.shortStatus(for: .grok)
        case .cursorAuthAbsent: ProviderSignInCopy.shortStatus(for: .cursor)
        case .copilotSignedOut: ProviderSignInCopy.shortStatus(for: .copilot)
        case .opencodeSignedOut: ProviderSignInCopy.shortStatus(for: .opencode)
        case .codexRejectedAuth: ProviderSignInCopy.shortStatus(for: .codex, again: true)
        case .grokRejectedAuth: ProviderSignInCopy.shortStatus(for: .grok, again: true)
        case .opencodeSignInExpired: ProviderSignInCopy.shortStatus(for: .opencode, again: true)
        case .claudeCLIMissing: ProviderSignInCopy.cliMissingShort(for: .claude)
        case .claudeTrustRequired, .cursorTrustRequired: "Approve Headroom’s folder"
        case .claudeUnknownUI: "Claude showed an unknown screen"
        case .claudeStartupQuestion: "Claude Code has a question"
        case .claudeTransientCapture: "Couldn’t read Claude usage"
        case .codexCLIMissing: ProviderSignInCopy.cliMissingShort(for: .codex)
        case .codexPermissionDenied: "Codex sign-in is blocked"
        case .codexUnsafePermissions: "Codex sign-in isn’t private"
        case .codexMalformedAuth: "Codex sign-in is unreadable"
        case .codexCredentialIO: "Can’t read Codex sign-in"
        case .codexSessionUnverified: "Can’t verify Codex session"
        case .codexStorageMismatch: "Codex login saved elsewhere"
        case .grokCLIMissing: ProviderSignInCopy.cliMissingShort(for: .grok)
        case .grokPermissionDenied: "Grok sign-in is blocked"
        case .grokUnsafePermissions: "Grok sign-in isn’t private"
        case .grokMalformedAuth: "Grok sign-in is unreadable"
        case .grokCredentialIO: "Can’t read Grok sign-in"
        case .grokTransientCapture: "Couldn’t read Grok usage"
        case .cursorCLIMissing: ProviderSignInCopy.cliMissingShort(for: .cursor)
        case .cursorUnknownUI: "Cursor showed an unknown screen"
        case .cursorTransientCapture: "Couldn’t read Cursor usage"
        case .copilotCLIMissing: ProviderSignInCopy.cliMissingShort(for: .copilot)
        case .copilotLogsUnreadable: "Couldn’t read Copilot logs"
        case .opencodeCLIMissing: ProviderSignInCopy.cliMissingShort(for: .opencode)
        case .opencodeUpdateRequired: "Go usage needs OpenCode 2.2"
        case .opencodeFormatChanged: "Can’t read OpenCode usage"
        case .opencodeTransientCapture: "Couldn’t read OpenCode usage"
        default: nil
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .claudeUnknownUI, .claudeTransientCapture, .codexCredentialIO, .codexSessionUnverified,
             .grokCredentialIO, .grokTransientCapture, .cursorUnknownUI,
             .cursorTransientCapture, .copilotLogsUnreadable,
             .opencodeFormatChanged, .opencodeTransientCapture:
            false
        default:
            true
        }
    }

    /// True only when the account has never completed its first official CLI login.
    /// Timer backoff keys off this typed state rather than enumerating providers.
    public var isNeverSignedIn: Bool {
        switch self {
        // KTD12 (OpenCode plan): an API-key connection has never signed in to the Console.
        case .claudeLoginRequired, .codexAuthAbsent, .grokAuthAbsent, .cursorAuthAbsent, .copilotSignedOut,
             .opencodeSignedOut, .opencodeConsoleSignInRequired:
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
        fullRecoveryPresentation.withShortStatus(shortMessage)
    }

    private var fullRecoveryPresentation: ProviderRecoveryPresentation {
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
            // CA-P9: a label change only. The button still stages the `.trust` interactive
            // launch, a different script from Sign In's (AGENTS.md); "workspace" was
            // Headroom's word, and the CLI asks about a folder.
            .init(status: message, primaryLabel: "Open Claude in Terminal", primaryAction: .openClaudeWorkspace,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeStartupQuestion:
            // The question sits in front of the prompt only in an interactive launch, so the
            // recovery opens one for the user to answer. Guided Setup runs the sign-in
            // script, which exits on a signed-in account before the question can appear.
            .init(status: message, primaryLabel: "Open Claude Code", primaryAction: .answerClaudeQuestion,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeUnknownUI:
            // An unrecognized screen is almost always another startup question. The old
            // "Open Guided Setup" secondary ran the sign-in script, which can never show it,
            // so it was a dead end; the interactive launch lets the user see the screen.
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow,
                  secondaryLabel: "Open Claude Code", secondaryAction: .answerClaudeQuestion)
        case .claudeTransientCapture:
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
            // CA-P9: label only; the trust launch is unchanged.
            .init(status: message, primaryLabel: "Open Cursor in Terminal", primaryAction: .openCursorWorkspace,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .cursorMCPApprovalRequired:
            .init(status: message, primaryLabel: "Review Cursor Tools", primaryAction: .reviewCursorTools,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .cursorUnknownUI, .cursorTransientCapture:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow,
                  secondaryLabel: ProviderSignInCopy.buttonAgain, secondaryAction: .connectCursor)
        case .copilotCLIMissing:
            .init(status: message, primaryLabel: "Install Copilot CLI", primaryAction: .installCopilotCLI)
        case .copilotSignedOut:
            .init(status: message, primaryLabel: ProviderSignInCopy.button, primaryAction: .connectCopilot,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        // An unreadable log is never a sign-in problem, so it gets a fresh read and no
        // Terminal sign-in.
        case .copilotLogsUnreadable:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow)
        case .opencodeCLIMissing:
            .init(status: message, primaryLabel: "Install OpenCode CLI", primaryAction: .installOpenCodeCLI,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        // KTD3: a 1.x install needs a major upgrade, which only the user can run. U12 found
        // the default curl and npm installs still give 1.x, so the action explains OpenCode 2
        // rather than promising a one-step update.
        case .opencodeUpdateRequired:
            .init(status: message, primaryLabel: "About OpenCode 2", primaryAction: .updateOpenCode,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .opencodeSignedOut, .opencodeConsoleSignInRequired:
            .init(status: message, primaryLabel: ProviderSignInCopy.button, primaryAction: .connectOpenCode,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .opencodeSignInExpired:
            .init(status: message, primaryLabel: ProviderSignInCopy.buttonAgain, primaryAction: .connectOpenCode,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        // KTD21: the usage route is experimental, and only a Headroom update can follow a
        // change to it, so the action is the feedback email rather than a sign-in.
        case .opencodeFormatChanged:
            .init(status: message, primaryLabel: "Contact Support", primaryAction: .contactSupport,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .opencodeTransientCapture:
            .init(status: message, primaryLabel: "Check Now", primaryAction: .checkNow)
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
    case installCopilotCLI
    case connectCopilot
    case installOpenCodeCLI
    /// Opens the maintainers' OpenCode 2 upgrade guide (KTD21).
    case updateOpenCode
    /// Sign In and Sign In Again both run `opencode auth` in Terminal (R6).
    case connectOpenCode
    /// KTD7: the no-Go row's link to OpenCode's Go plans.
    case seeOpenCodeGoPlans
    /// Opens the same pre-filled feedback email as Settings › About › Send Feedback
    /// (KTD21), so Headroom still sends nothing itself.
    case contactSupport
    case openClaudeWorkspace
    /// Opens interactive Claude Code in the account's workspace so the user can answer a
    /// startup question (or see an unrecognized screen). Same launch as
    /// `.openClaudeWorkspace`, recorded with `ClaudeInteractiveLaunchReason.startupQuestion`.
    case answerClaudeQuestion
    case openCursorWorkspace
    case reviewCursorTools
    case showPrivacyGuidance
    case resolveCodexStorage
    case checkNow
}

public extension UsageSnapshot.PlanStatus {
    /// KTD7/D2 (OpenCode plan): a live reading with no plan draws one sentence and one
    /// button where the meter would be. Nil for a provider that never reports the status.
    func recoveryPresentation(for providerID: ProviderID) -> ProviderRecoveryPresentation? {
        switch (self, providerID) {
        case (.noActivePlan, .opencode):
            .init(status: "No Go plan on this workspace", primaryLabel: "See Go Plans",
                  primaryAction: .seeOpenCodeGoPlans,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        default:
            nil
        }
    }
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
    /// CA-P5: an explicit one-line form of `status`; nil derives one (`shortStatus`).
    private let shortStatusOverride: String?

    public init(
        status: String,
        primaryLabel: String,
        primaryAction: SetupRecoveryAction,
        secondaryLabel: String? = nil,
        secondaryAction: SetupRecoveryAction? = nil,
        automaticPolicy: SetupAutomaticPolicy = .none,
        shortStatus: String? = nil
    ) {
        self.status = status
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
        self.automaticPolicy = automaticPolicy
        self.shortStatusOverride = shortStatus
    }

    func withShortStatus(_ shortStatus: String?) -> ProviderRecoveryPresentation {
        .init(status: status, primaryLabel: primaryLabel, primaryAction: primaryAction,
              secondaryLabel: secondaryLabel, secondaryAction: secondaryAction,
              automaticPolicy: automaticPolicy, shortStatus: shortStatus ?? shortStatusOverride)
    }

    /// CA-P5 (option A): the action a one-line recovery row appends after its sentence, as in
    /// "Claude Code not found · Install". Keyed on the action, so presentations built outside
    /// `ProviderSetupOutcome` (the capability card's) shorten the same way. Sign In, Sign In
    /// Again and Check Now are already short and keep R2C6's one verb.
    public var primaryShortLabel: String {
        switch primaryAction {
        case .installClaudeCLI, .installCodexCLI, .installGrokCLI, .installCursorAgent,
             .installCopilotCLI, .installOpenCodeCLI:
            "Install"
        case .showPrivacyGuidance: "Get Help"
        case .openClaudeWorkspace, .openCursorWorkspace: "Open Terminal"
        case .answerClaudeQuestion: "Answer"
        case .resolveCodexStorage: "Resolve"
        case .reviewCursorTools: "Review"
        case .updateOpenCode: "Learn More"
        case .reconnectCodex where primaryLabel != ProviderSignInCopy.buttonAgain: "Reopen"
        default: primaryLabel
        }
    }

    /// CA-P5 (option A): the sentence a one-line recovery row prints before " · " and its
    /// short action. An install action reads "<product> not found"; otherwise the explicit
    /// short form, or the status's first sentence.
    public var shortStatus: String {
        if let shortStatusOverride { return shortStatusOverride }
        if let provider = primaryAction.installsCLI {
            return ProviderSignInCopy.cliMissingShort(for: provider)
        }
        return Self.firstSentence(of: status)
    }

    /// CA-P5: true when the row has to append `primaryShortLabel`, because its sentence does
    /// not already contain the action ("Sign in with the official Codex CLI" does).
    public var appendsShortAction: Bool {
        shortStatus.range(of: primaryShortLabel, options: [.caseInsensitive, .diacriticInsensitive]) == nil
    }

    /// CA-P5: the one-line row's tooltip, the full sentence and the full label it shortens:
    /// "Headroom can’t find Claude Code on this Mac. Install Claude Code."
    public var rowHelp: String {
        let sentence = status.hasSuffix(".") ? status : status + "."
        return "\(sentence) \(primaryLabel)."
    }

    /// The text up to the first sentence break. A legacy "cause\u{00A0}—\u{00A0}consequence"
    /// counts as one, so a status not yet rewritten still shortens to its cause.
    static func firstSentence(of text: String) -> String {
        let breaks = [". ", "\u{00A0}—\u{00A0}", " — "]
        let end = breaks.compactMap { text.range(of: $0)?.lowerBound }.min() ?? text.endIndex
        let first = String(text[..<end])
        return first.hasSuffix(".") ? String(first.dropLast()) : first
    }
}

extension SetupRecoveryAction {
    /// The provider whose CLI an install action fetches, or nil for every other action.
    var installsCLI: ProviderID? {
        switch self {
        case .installClaudeCLI: .claude
        case .installCodexCLI: .codex
        case .installGrokCLI: .grok
        case .installCursorAgent: .cursor
        case .installCopilotCLI: .copilot
        case .installOpenCodeCLI: .opencode
        default: nil
        }
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
