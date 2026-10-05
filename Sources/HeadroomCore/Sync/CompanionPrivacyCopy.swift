import Foundation

/// KTD22 / R35: the one description of what syncs, shared by the Mac's Widgets & iPhone
/// footnote and the phone's iPhone sync section, so the two can never drift. It names
/// only what the shipped build sends; reminder text joins when U16's CloudKit reminders
/// ship (KTD19), and not before.
public enum CompanionPrivacyCopy {
    /// "Account names you chose" because labels are free text and may look like emails
    /// (KTD9). No copy implies end-to-end encryption.
    public static let whatSyncs =
        "Sends account names you chose, plan names, usage, reset times, API spend, display "
        + "choices and check-now requests through your iCloud, with random IDs for this Mac, "
        + "each iPhone or iPad and your iCloud account’s sync. Sign-ins, emails and API keys "
        + "never sync. iCloud "
        + "key-value data isn’t end-to-end encrypted."

    /// The Mac's sync status line (KTD22 diagnostics), from times and counts only.
    /// `formattedTime` is the caller's localized rendering of `lastPublishAt`.
    public static func macStatus(
        lastPublishAt: Date?, formattedTime: String?, ladderLevel: Int, lastFailure: String?
    ) -> String {
        var parts: [String] = []
        if let formattedTime, lastPublishAt != nil {
            parts.append("Last sent to iCloud \(formattedTime).")
        } else {
            parts.append("Nothing sent to iCloud yet.")
        }
        if lastFailure == "overBudget" {
            parts.append("The latest update didn’t fit in iCloud, so your iPhone keeps the one before.")
        } else if ladderLevel == 1 {
            parts.append("Model rows for extra accounts stay on this Mac so everything fits in iCloud.")
        } else if ladderLevel >= 2 {
            parts.append("Some accounts stay on this Mac so everything fits in iCloud.")
        }
        return parts.joined(separator: " ")
    }
}
