import Foundation

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
    let visibleAccounts = providerAccounts.filter { $0.providerID == account.providerID }
    guard visibleAccounts.count == 1, isDefaultAccountLabel(account.label) else {
        return account.label
    }
    return providerDisplayName
}

/// Label-only eligibility for a persistent email. The view remains responsible for
/// suppressing both email and tooltip when its snapshot carries no address (KTD11).
public func showsPersistentEmail(
    for account: ProviderAccount,
    in providerAccounts: [ProviderAccount]
) -> Bool {
    let visibleAccounts = providerAccounts.filter { $0.providerID == account.providerID }
    if visibleAccounts.count > 1, isDefaultAccountLabel(account.label) {
        return true
    }
    return visibleAccounts.contains { candidate in
        candidate.key != account.key
            && candidate.label.compare(account.label, options: .caseInsensitive) == .orderedSame
    }
}

private func isDefaultAccountLabel(_ label: String) -> Bool {
    if label == "Main" { return true }

    let prefix = "Account "
    guard label.hasPrefix(prefix) else { return false }
    let suffix = label.dropFirst(prefix.count).utf8
    guard let first = suffix.first, (49...57).contains(first) else { return false }
    return suffix.allSatisfy { (48...57).contains($0) }
}
