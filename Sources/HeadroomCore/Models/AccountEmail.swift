import Foundation

/// The one normalization every account email passes through before it becomes
/// `UsageSnapshot.accountEmail`.
///
/// The sources disagree on case: `.claude.json` keeps whatever the user typed at login
/// ("Kylezantos@gmail.com"), while Codex's `id_token` `email` claim arrives already
/// lowercased — so one address rendered as two different strings across the Accounts
/// pane's provider rows. The local part of an address is formally case-sensitive, but no
/// provider here treats it that way, and this value is display context only: it is never
/// a lookup key (Claude's duplicate-login detection matches `oauthAccount.accountUuid`,
/// not the email). Normalizing at each reader boundary means every surface — Accounts
/// pane, popover tooltip, widget projection — receives the same string without each view
/// re-normalizing on its own.
public enum AccountEmail {
    /// Whitespace-trimmed and lowercased, or nil when nothing displayable is left.
    public static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed.lowercased()
    }
}
