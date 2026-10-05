import Foundation

/// Participants that keep their own phone-bound state in step with "Sync usage to
/// iPhone" (KTD22). The CloudKit reminder poster (U16, KTD19) implements this and plugs
/// into AppComposition's slot; the KVS publisher drives it and never knows the type.
///
/// Calls arrive from the serial publisher in the order the Mac decides them. Each call
/// is idempotent: the sync-off purge repeats on every launch while sync stays off, so a
/// lost deletion, or one a downgraded Mac could not perform, is repaired later.
public protocol CompanionSyncLifecycle: Sendable {
    /// Sync is on for this launch, or was just turned back on.
    func companionSyncDidEnable() async
    /// KTD22 sync-off order: runs after the disabled v3 envelope, the disabled manifest
    /// tombstone and the removal of every provider, receipt and request key.
    func companionSyncDidPurge() async
    /// KTD22: the Mac's iCloud account changed. The publisher republishes every key to
    /// the new store; a participant resets anything tied to the old account.
    func companionSyncAccountDidChange() async
}
