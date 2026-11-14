import Foundation

/// U4's fixed phone categories. No provider error, path or session-associated string
/// enters the wire value; Mac-owned session mapping is a separate integration.
public enum CompanionAttention: String, Codable, Equatable, Sendable, CaseIterable {
    case signInRequired, signInAgain, finishingSignIn, setupInProgress, workspaceApproval
    case cliMissing, cliUpdateRequired, allowSignInFile, signInFileUnreadable, signInStorageMismatch
    case externalToolsApproval, retrying, cliDiscoveryRetrying, setupScreenUnknown, neverOnboarded
    case accessDenied, setupFailed, setupBlocked, unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Transport adds an explicit unknown marker without expanding the source spend enum.
public enum CompanionSpendAttention: String, Codable, Equatable, Sendable, CaseIterable {
    case missingKey, keyRejected, keyLacksAccess, setupRequired, retryable, unknown

    public init(_ attention: APISpendAttention) {
        switch attention {
        case .missingKey: self = .missingKey
        case .keyRejected: self = .keyRejected
        case .keyLacksAccess: self = .keyLacksAccess
        case .setupRequired: self = .setupRequired
        case .retryable: self = .retryable
        }
    }

    public var apiSpendAttention: APISpendAttention? {
        switch self {
        case .missingKey: .missingKey
        case .keyRejected: .keyRejected
        case .keyLacksAccess: .keyLacksAccess
        case .setupRequired: .setupRequired
        case .retryable: .retryable
        case .unknown: nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Canonical phone-sync stale messages. Freshness/permanence stay caller-owned;
/// these functions accept only typed categories, never free-form source text.
public enum CompanionAttentionCopy {
    public static let generic = "Needs attention on your Mac"

    public static func account(_ attention: CompanionAttention?) -> String {
        switch attention {
        case .signInRequired: "Sign in on your Mac"
        case .signInAgain: "Sign in again on your Mac"
        case .finishingSignIn: "Finishing sign-in on your Mac"
        case .setupInProgress: "Finish setup on your Mac"
        // CA-P9: the CLI asks about a folder, so the phone says folder too.
        case .workspaceApproval: "Approve Headroom’s folder on your Mac"
        case .cliMissing: "Install the official CLI on your Mac"
        case .cliUpdateRequired: "Update the official CLI on your Mac"
        case .allowSignInFile: "Allow Headroom to read sign-in data on your Mac"
        case .signInFileUnreadable: "Sign-in data is unreadable on your Mac"
        case .signInStorageMismatch: "Review where sign-in data is stored on your Mac"
        case .externalToolsApproval: "Review the CLI’s external tools on your Mac"
        // CA-P9: two sentences, no em dash, like the Mac's retry lines.
        case .retrying: "Couldn’t read usage. Your Mac will try again."
        case .cliDiscoveryRetrying: "Your Mac couldn’t find the official CLI. It will try again."
        case .setupScreenUnknown: "Review the official CLI’s setup screen on your Mac"
        case .neverOnboarded: "Sign in to this account on your Mac"
        case .accessDenied: "Review this account’s access on your Mac"
        case .setupFailed: "Setup needs attention on your Mac"
        case .setupBlocked: "Another account is being set up on your Mac"
        case .unknown, nil: generic
        }
    }

    /// U8 (V12, spec-flow F3): the phone card names the account it is talking about, so the
    /// sign-in family reads "Sign in to Work on your Mac" where a stack holds several. The
    /// title is the name the Mac shows (KTD9), which is an email only when the user names
    /// accounts by email there; every other category keeps its canonical sentence.
    public static func account(_ attention: CompanionAttention?, title: String?) -> String {
        guard let title, !title.isEmpty else { return account(attention) }
        switch attention {
        case .signInRequired, .neverOnboarded: return "Sign in to \(title) on your Mac"
        case .signInAgain: return "Sign in to \(title) again on your Mac"
        default: return account(attention)
        }
    }

    public static func spend(_ attention: CompanionSpendAttention?) -> String {
        switch attention {
        case .missingKey, .setupRequired: "Set up API spend on your Mac"
        case .keyRejected: "Replace the rejected key on your Mac"
        case .keyLacksAccess: "Review the API key’s access on your Mac"
        case .retryable: "Couldn’t read the amount. Your Mac will try again."
        case .unknown, nil: generic
        }
    }

    public static func spend(apiSpendAttention: APISpendAttention?) -> String {
        spend(apiSpendAttention.map(CompanionSpendAttention.init))
    }
}
