import Foundation

/// Folds the built-in row into the extra row that holds the same login, for the popover.
///
/// The built-in row reads whatever login the CLI's default config home holds. An account
/// switcher (ccswap and similar tools) rotates that login between accounts the user also
/// tracks as extra rows, each pinned to its own config home. Without this, every switch
/// leaves two cards reading one login, and the label on the built-in card names an account
/// it is no longer reading.
///
/// When the built-in row's captured email matches exactly one extra row of the same
/// provider, the built-in row is dropped from the drawn list and that extra row is marked
/// as the active login. Each tracked account then keeps exactly one card, and the marker
/// follows the switcher. Display only: the registry, Settings (with its "Same login as X"
/// badge), the menu bar, widgets and the phone are untouched, and nothing is removed.
///
/// Folds only when at least two rows remain, so the card keeps its multi-account layout and
/// the single-account card's setup and recovery paths (which assume the built-in row) are
/// never handed an extra account.
///
/// Fails safe to "no collapse" whenever the match is not certain: no built-in row, no
/// captured email on either side, more than one extra row with that email, or plan labels
/// that disagree (one email can belong to two subscriptions, for example a personal and a
/// team organization).
public struct ActiveLoginCollapse: Equatable, Sendable {
    /// The rows to draw, in their original order, minus a folded built-in row.
    public let accounts: [ProviderAccount]
    /// The extra row the CLI's default login is signed in to, when one was folded into it.
    public let activeKey: AccountKey?
    /// The built-in row that was folded away, if any.
    public let hiddenKey: AccountKey?

    public static func resolve(
        accounts: [ProviderAccount],
        emailsByKey: [AccountKey: String],
        planLabelsByKey: [AccountKey: String] = [:]
    ) -> ActiveLoginCollapse {
        let unchanged = ActiveLoginCollapse(accounts: accounts, activeKey: nil, hiddenKey: nil)
        guard accounts.count > 2,
              let builtIn = accounts.first(where: \.isBuiltIn),
              let email = AccountEmail.normalized(emailsByKey[builtIn.key])
        else { return unchanged }

        let matches = accounts.filter { candidate in
            !candidate.isBuiltIn
                && candidate.providerID == builtIn.providerID
                && AccountEmail.normalized(emailsByKey[candidate.key]) == email
        }
        guard matches.count == 1, let target = matches.first else { return unchanged }

        if let builtInPlan = normalizedPlan(planLabelsByKey[builtIn.key]),
           let targetPlan = normalizedPlan(planLabelsByKey[target.key]),
           builtInPlan != targetPlan {
            return unchanged
        }

        return ActiveLoginCollapse(
            accounts: accounts.filter { $0.key != builtIn.key },
            activeKey: target.key,
            hiddenKey: builtIn.key
        )
    }

    private static func normalizedPlan(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}
