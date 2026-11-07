import Foundation

/// Claude accounts that live in ccswap (the claude-swap account switcher), read without a
/// second sign-in.
///
/// ccswap keeps each saved account's login and manages its token generations itself; a
/// process that refreshes those tokens behind its back can spend a grant ccswap still
/// holds. So Headroom never reads ccswap's credentials or points `CLAUDE_CONFIG_DIR` at its
/// profiles. Each row runs `ccswap run <email> -- -p /usage …`: ccswap prepares that
/// account's isolated profile and execs the **official** `claude` CLI, which makes the
/// usage request; Headroom only reads its output, like every other Claude account.
///
/// Discovery reads `ccswap list --json` for identity only (slot email). The usage numbers
/// ccswap prints there come from the OAuth usage endpoint and are deliberately not decoded.
public enum CCSwapAccounts {
    /// Account ids for ccswap-backed rows: a stable prefix plus the lowercased email, so a
    /// row survives slot renumbering and is recognisable without extra registry fields.
    public static let accountIDPrefix = "ccswap-"

    public static func accountID(email: String) -> AccountID? {
        guard let normalized = AccountEmail.normalized(email) else { return nil }
        return AccountID(accountIDPrefix + normalized)
    }

    /// The ccswap account a row reads, or nil for every other account.
    public static func email(for accountID: AccountID) -> String? {
        guard accountID.raw.hasPrefix(accountIDPrefix) else { return nil }
        return AccountEmail.normalized(String(accountID.raw.dropFirst(accountIDPrefix.count)))
    }

    /// Arguments placed before the CLI's own: `ccswap run <email> -- <claude args>`.
    public static func launchPrefix(email: String) -> [String] {
        ["run", email, "--"]
    }

    public static func locator() -> CLIExecutableLocator {
        CLIExecutableLocator(
            executableName: "ccswap",
            fallbackPaths: [
                "\(NSHomeDirectory())/.local/bin/ccswap",
                "/opt/homebrew/bin/ccswap",
                "/usr/local/bin/ccswap",
            ]
        )
    }

    /// The Claude accounts ccswap manages, by email, in slot order. Identity only.
    public static func emails(inListJSON data: Data) -> [String] {
        struct Listing: Decodable {
            struct Account: Decodable {
                let number: Int?
                let email: String?
            }
            let schemaVersion: Int?
            let accounts: [Account]?
        }
        guard let listing = try? JSONDecoder().decode(Listing.self, from: data),
              listing.schemaVersion == 1
        else { return [] }
        var seen = Set<String>()
        return (listing.accounts ?? [])
            .sorted { ($0.number ?? .max) < ($1.number ?? .max) }
            .compactMap { AccountEmail.normalized($0.email) }
            .filter { email in
                // ccswap's placeholder emails for setup tokens and API keys carry no login.
                !email.hasSuffix("@token.local") && seen.insert(email).inserted
            }
    }

    /// Runs `ccswap list --json --provider claude` (a local read of ccswap's own store; no
    /// network) and returns its account emails. Empty when ccswap is absent or fails.
    public static func discoverEmails(
        locator: any CLIExecutableLocating = locator(),
        deadline: TimeInterval = 10
    ) async -> [String] {
        guard case .available(let path, _) = await locator.locate() else { return [] }
        return await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["list", "--json", "--provider", "claude"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let end = Date().addingTimeInterval(deadline)
            while process.isRunning, Date() < end { usleep(20_000) }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return []
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return emails(inListJSON: output.fileHandleForReading.readDataToEndOfFile())
        }.value
    }
}

/// A ccswap row's identity is its slot email; there is no Headroom-owned `.claude.json`.
public struct FixedClaudeAccountEmail: ClaudeAccountEmailReading {
    private let email: String

    public init(_ email: String) { self.email = email }

    public func readAccountEmail() -> String? { email }
}

/// Emails of ccswap rows the user removed, so discovery doesn't add them back.
public struct CCSwapDismissedAccounts {
    public static let defaultsKey = "ccswapDismissedEmails.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func contains(_ email: String) -> Bool {
        guard let email = AccountEmail.normalized(email) else { return false }
        return Set(defaults.stringArray(forKey: Self.defaultsKey) ?? []).contains(email)
    }

    public func dismiss(_ email: String) {
        guard let email = AccountEmail.normalized(email) else { return }
        var all = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        all.insert(email)
        defaults.set(all.sorted(), forKey: Self.defaultsKey)
    }
}
