import Foundation

/// Desktop display override: saved labels remain intact, and an email used as the
/// title is omitted from secondary text and tooltips so it never appears twice.
public struct DesktopAccountIdentity: Equatable, Sendable {
    public let title: String
    public let email: String?
    public let showsPersistentEmail: Bool
    public let isEmailTitle: Bool

    public init(title: String, email: String?, showsPersistentEmail: Bool, usesEmailAsName: Bool) {
        let address = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesAddress = usesEmailAsName && address?.isEmpty == false
        self.title = usesAddress ? (address ?? title) : title
        self.email = usesAddress ? nil : email
        self.showsPersistentEmail = !usesAddress && showsPersistentEmail
        self.isEmailTitle = usesAddress
    }
}

/// Whether every provider card should use account identity rows. The decision is
/// surface-wide: one provider with multiple visible accounts flips every card (KTD9).
public func surfaceUsesAccountRows(
    accountsByProvider: [ProviderID: [ProviderAccount]]
) -> Bool {
    accountsByProvider.values.contains { $0.count > 1 }
}

/// The title for one account identity row. A lone default label is implementation
/// detail, so it reads as the provider name; multi-account rows keep their labels
/// because those labels identify distinct CLI config homes (KTD10).
public func rowTitle(
    for account: ProviderAccount,
    in providerAccounts: [ProviderAccount],
    providerDisplayName: String
) -> String {
    let visibleAccounts = providerAccounts.lazy.filter { $0.providerID == account.providerID }
    guard visibleAccounts.prefix(2).count == 1,
          ProviderAccount.isDefaultLabel(account.label)
    else {
        return account.label
    }
    return providerDisplayName
}

/// Eligibility for a persistent email. The view remains responsible for suppressing
/// both email and tooltip when its snapshot carries no address (KTD11).
///
/// `emailsByKey` carries each visible account's captured address. When two rows of one
/// provider report the same address, both show it: a custom label names a config home,
/// not a login, so an external switcher (or a re-login) can move the built-in row onto
/// the same account as another row while its label still reads as the old one. Showing
/// the address is the only on-screen tell in the popover; the Settings duplicate badge
/// is not visible there.
public func showsPersistentEmail(
    for account: ProviderAccount,
    in providerAccounts: [ProviderAccount],
    emailsByKey: [AccountKey: String] = [:]
) -> Bool {
    let visibleAccounts = providerAccounts.lazy.filter { $0.providerID == account.providerID }
    if visibleAccounts.prefix(2).count > 1,
       ProviderAccount.isDefaultLabel(account.label) {
        return true
    }
    if let email = AccountEmail.normalized(emailsByKey[account.key]),
       visibleAccounts.contains(where: { candidate in
           candidate.key != account.key
               && AccountEmail.normalized(emailsByKey[candidate.key]) == email
       }) {
        return true
    }
    return visibleAccounts.contains { candidate in
        candidate.key != account.key
            && candidate.label.compare(account.label, options: .caseInsensitive) == .orderedSame
    }
}
