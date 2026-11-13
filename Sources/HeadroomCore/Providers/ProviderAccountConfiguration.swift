import Foundation

/// Inspectable production routing for one provider/account pair. The composition root
/// consumes this value to build concrete providers; tests can verify identity and exact
/// paths without spawning a CLI, touching Keychain, or making a network request.
public struct ProviderAccountConfiguration: Sendable, Equatable {
    public let accountKey: AccountKey
    public let claudeConfigDirectory: URL?
    public let claudeWorkspaceDirectory: URL?
    public let codexHomeDirectory: URL?
    public let codexAuthFile: URL?
    public let grokHomeDirectory: URL?
    public let grokAuthFile: URL?
    /// KTD10: `.builtIn` for the built-in OpenCode account (its four XDG variables are unset,
    /// so it reads the default home a plain Terminal `opencode` uses), `.isolated` for an
    /// extra, nil for every other provider.
    public private(set) var opencodeHome: OpenCodeAccountHome? = nil

    /// The four XDG folders an extra OpenCode account exports; nil for the built-in account.
    public var opencodeDataHome: URL? { opencodeXDGDirectory("XDG_DATA_HOME") }
    public var opencodeConfigHome: URL? { opencodeXDGDirectory("XDG_CONFIG_HOME") }
    public var opencodeCacheHome: URL? { opencodeXDGDirectory("XDG_CACHE_HOME") }
    public var opencodeStateHome: URL? { opencodeXDGDirectory("XDG_STATE_HOME") }

    private func opencodeXDGDirectory(_ variable: String) -> URL? {
        opencodeHome?.xdgValues[variable].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public static func make(
        for account: ProviderAccount,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        accountsBase: URL = AccountStorage.baseDirectoryURL,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) -> ProviderAccountConfiguration {
        switch account.providerID {
        case .claude:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: builtInClaudeWorkspace,
                    codexHomeDirectory: nil,
                    codexAuthFile: nil,
                    grokHomeDirectory: nil,
                    grokAuthFile: nil
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: root.appendingPathComponent("config", isDirectory: true),
                claudeWorkspaceDirectory: root.appendingPathComponent("workspace", isDirectory: true),
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: nil,
                grokAuthFile: nil
            )
        case .codex:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: nil,
                    codexHomeDirectory: nil,
                    codexAuthFile: userHome.appendingPathComponent(".codex/auth.json"),
                    grokHomeDirectory: nil,
                    grokAuthFile: nil
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: root,
                codexAuthFile: root.appendingPathComponent("auth.json"),
                grokHomeDirectory: nil,
                grokAuthFile: nil
            )
        case .grok:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: nil,
                    codexHomeDirectory: nil,
                    codexAuthFile: nil,
                    grokHomeDirectory: nil,
                    grokAuthFile: userHome.appendingPathComponent(".grok/auth.json")
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: root,
                grokAuthFile: root.appendingPathComponent("auth.json")
            )
        case .opencode:
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: nil,
                grokAuthFile: nil,
                opencodeHome: AccountStorage.opencodeAccountHome(for: account, baseDirectoryURL: accountsBase)
            )
        default:
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: nil,
                grokAuthFile: nil
            )
        }
    }
}
