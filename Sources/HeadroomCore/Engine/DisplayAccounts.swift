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
    /// reading. Empty until the one-row merge (U10) lands.
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
