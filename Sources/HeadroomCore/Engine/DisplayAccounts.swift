import Foundation

/// Default-login plan KTD8: which store a display row belongs to. An engine row is a
/// registry account the scheduler probes; a remembered row is an account the default login
/// left (R6), kept in the record store, never probed, never the main account and never a
/// reminder source (R12). Rename and remove follow the kind to the right store.
public enum DisplayAccountKind: Equatable, Hashable, Sendable {
    case engine
    case remembered

    /// R12: whether a row's retry, sign-in and recovery actions reach a provider. Only an
    /// engine row is ever probed, so a remembered row offers none. The popover section, its
    /// card and the Settings row all read this one decision.
    public var offersRetry: Bool { self == .engine }
}

/// One row as every user-visible surface lists it (KTD8). A remembered row carries a
/// `ProviderAccount` built from its record so the existing row views can draw it; that
/// account is never in the registry and never has a provider instance.
public struct DisplayAccount: Identifiable, Equatable, Hashable, Sendable {
    public let account: ProviderAccount
    public let kind: DisplayAccountKind

    public init(account: ProviderAccount, kind: DisplayAccountKind) {
        self.account = account
        self.kind = kind
    }

    public var id: AccountID { account.id }
    public var key: AccountKey { account.key }
    public var label: String { account.label }
    public var isRemembered: Bool { kind == .remembered }
}

/// The display list for one provider, its display primary and the merge map (KTD8).
/// `UsageStore.accounts(for:)` stays the engine list; this is what the popover, Settings,
/// the menu bar, notifications and the phone capture list.
public struct DisplayAccountsProjection: Equatable, Sendable {
    public let providerID: ProviderID
    /// Engine rows in Make Main order, then visible remembered rows in stored order.
    public let rows: [DisplayAccount]
    /// The row compact surfaces follow. Always an engine row: a remembered row is never
    /// the main account (R12). Nil only when the provider has no engine row.
    public let primaryKey: AccountKey?
    /// KTD11: a merged engine key (hidden from `rows`) to the display row that shows its
    /// reading. Decided by `DisplayMergePlanner`; empty for a setup with no merge.
    public let mergeMap: [AccountKey: AccountKey]

    public var accounts: [ProviderAccount] { rows.map(\.account) }

    public func row(for key: AccountKey) -> DisplayAccount? { rows.first { $0.key == key } }

    /// The engine side of "primary, following the merge map": the scheduler's primary
    /// lane priority and the never-signed-in exemption apply to the engine row behind the
    /// display primary, and to any engine row merged into it.
    public func isEnginePrimary(_ key: AccountKey) -> Bool {
        guard let primaryKey else { return false }
        return key == primaryKey || mergeMap[key] == primaryKey
    }
}

/// KTD8's pure decision, consumed by the store and the views like `AccountColumnsPlanner`.
public enum DisplayAccountsResolver {
    /// - Parameters:
    ///   - engine: `UsageStore.accounts(for:)`, already in Make Main order with the
    ///     registry's dangling-pointer fallback applied.
    ///   - remembered: the store's remembered rows for the provider, in stored order.
    ///     Hidden ones are dropped here (R11).
    ///   - mergeMap: engine key hidden by the one-row merge to the row standing for it.
    public static func resolve(
        providerID: ProviderID,
        engine: [ProviderAccount],
        remembered: [RememberedAccountSummary],
        mergeMap: [AccountKey: AccountKey] = [:]
    ) -> DisplayAccountsProjection {
        let engineRows = engine
            .filter { $0.providerID == providerID && mergeMap[$0.key] == nil }
            .map { DisplayAccount(account: $0, kind: .engine) }
        var seen = Set(engine.map(\.key))
        let rememberedRows = remembered.compactMap { summary -> DisplayAccount? in
            guard summary.providerID == providerID, !summary.isHidden,
                  seen.insert(summary.key).inserted
            else { return nil }
            return DisplayAccount(
                account: ProviderAccount(id: summary.id, providerID: providerID, label: summary.label),
                kind: .remembered
            )
        }
        // The engine list's first row is the registry's main choice, or its canonical
        // fallback when the pointer names a row that is not there, which is always the
        // case for a remembered account's local id. A merged main resolves to the row
        // that shows it.
        let primaryKey = engine.first.map { mergeMap[$0.key] ?? $0.key }
        return DisplayAccountsProjection(
            providerID: providerID,
            rows: engineRows + rememberedRows,
            primaryKey: primaryKey,
            mergeMap: mergeMap
        )
    }
}

// MARK: - One account, one row (default-login plan U10, KTD11)

/// What the one-row merge reads about one engine row of a provider.
public struct DisplayMergeInput: Equatable, Sendable {
    public let key: AccountKey
    public let isBuiltIn: Bool
    /// The account the row's slot is bound to while its readings name it. Nil while the
    /// row has no binding, its login lapsed, or its identity is unreadable for now (R4):
    /// none of those is a Known identity.
    public let identity: AccountIdentity?
    /// The row's latest snapshot; nil when it has none.
    public let freshness: Freshness?
    /// A setup or recovery is in progress on the row (`SetupSessionState.holdsDisplayMerge`,
    /// or a removal under way).
    public let isInSetup: Bool

    public init(
        key: AccountKey,
        isBuiltIn: Bool,
        identity: AccountIdentity?,
        freshness: Freshness?,
        isInSetup: Bool
    ) {
        self.key = key
        self.isBuiltIn = isBuiltIn
        self.identity = identity
        self.freshness = freshness
        self.isInSetup = isInSetup
    }
}

/// KTD11's pure decision: whether the built-in row (the default login) shows through an
/// extra row that reads the same account. Display-only; both rows keep being read.
public enum DisplayMergePlanner {
    /// The built-in merges into extra E only when:
    /// - both identities are Known and equal, and the identity is strong (Claude and Codex;
    ///   Grok, Cursor and Copilot are weak and never merge, KTD13);
    /// - exactly one extra matches (R14);
    /// - E's latest snapshot is live or transient-stale;
    /// - neither row is in a setup state.
    /// Any other case returns an empty map and both rows show, as before (R15).
    public static func mergeMap(_ rows: [DisplayMergeInput]) -> [AccountKey: AccountKey] {
        guard let builtIn = rows.first(where: \.isBuiltIn),
              let identity = builtIn.identity, identity.strength == .strong,
              !builtIn.isInSetup
        else { return [:] }
        let matches = rows.filter { !$0.isBuiltIn && $0.identity == identity }
        guard matches.count == 1, let extra = matches.first, !extra.isInSetup,
              isReadable(extra.freshness)
        else { return [:] }
        return [builtIn.key: extra.key]
    }

    /// Live, or a transient failure that keeps the row's numbers. A permanent failure (a
    /// lapsed login, a setup the user must finish) or no reading yet is not readable.
    static func isReadable(_ freshness: Freshness?) -> Bool {
        switch freshness {
        case .live: true
        case .stale(let reason): !reason.isPermanent
        case .pending, nil: false
        }
    }
}

extension SetupSessionState {
    /// KTD11: the states during which a row is being set up or recovered, so the one-row
    /// merge stands aside and both rows show. Settled states (`idle`, `failed`,
    /// `cancelled`, `removalFailed`, `removed`) do not hold it.
    public var holdsDisplayMerge: Bool {
        switch self {
        case .preparing, .waiting, .verifying, .blockedByOpenHandoff, .blockedByProviderLogin,
             .connected, .removing:
            true
        case .idle, .failed, .cancelled, .removalFailed, .removed:
            false
        }
    }
}
