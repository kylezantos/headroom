import Foundation
import Testing
@testable import HeadroomCore

/// U12: what the phone's Settings sheet derives from the resolved snapshot — the rows that
/// read manifest fields (rule 7), the iPhone sync status and the what-syncs list (KTD22).
struct PhoneSettingsPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC")!
    private let locale = Locale(identifier: "en_US")

    // MARK: Rows that read manifest fields

    @Test func aV4MacShowsItsWidgetProvidersAndReminderSummary() {
        let rows = PhoneSettingsManifestRows(snapshot: CompanionDemoData.snapshot(.multiAccount, now: now))
        guard case .available(let widgetProviders, let reminders) = rows else {
            Issue.record("expected the manifest rows, got \(rows)")
            return
        }
        #expect(widgetProviders == ["Claude", "Codex"])
        #expect(reminders?.macUseItUpEnabled == true)
    }

    @Test func aV3OnlyMacAsksForAMacUpdate() {
        let rows = PhoneSettingsManifestRows(snapshot: CompanionDemoData.snapshot(.oldMac, now: now))
        #expect(rows == .updateMac)
        #expect(PhoneSettingsCopy.updateMac == "Update Headroom on your Mac")
    }

    /// A current Mac's v3 mirror, read while the v4 manifest isn't (or before it arrives),
    /// must not ask an up-to-date Mac to update.
    @Test func aCurrentMacsV3MirrorHidesTheRowsInsteadOfAskingForAnUpdate() throws {
        // A 1.5 Mac's v3 key names its lineage; read alone it resolves as a mirror.
        let oldMacV3 = try #require(try CompanionDemoData.publication(.oldMac, now: now).v3)
        let legacy = try #require(SyncedWidgetSnapshotCodec.decode(oldMacV3).envelope)
        let mirrorEnvelope = SyncedWidgetSnapshotEnvelope(
            schemaVersion: legacy.schemaVersion, publishedAt: legacy.publishedAt,
            sourceID: legacy.sourceID, sourcePlatform: legacy.sourcePlatform,
            snapshot: legacy.snapshot,
            companionSourceID: CompanionDemoData.sourceID, companionGeneration: 7)
        let mirror = CompanionSnapshotResolver.resolve(CompanionResolverInput(
            manifest: nil, providerKeys: [:], v3: try SyncedWidgetSnapshotCodec.encode(mirrorEnvelope),
            cache: .empty, now: now)).snapshot
        let mirrored = try #require(mirror.content)
        #expect(mirrored.origin == .v3 && mirrored.notice == nil)
        #expect(PhoneSettingsManifestRows(snapshot: mirror) == .hidden)
    }

    @Test func pausedAndWaitingHideTheRows() {
        #expect(PhoneSettingsManifestRows(snapshot: CompanionDemoData.snapshot(.paused, now: now)) == .hidden)
        #expect(PhoneSettingsManifestRows(snapshot: CompanionDemoData.snapshot(.waiting, now: now)) == .hidden)
        #expect(PhoneSettingsManifestRows(snapshot: CompanionResolvedSnapshot(state: .accountScopeUnavailable)) == .hidden)
        #expect(PhoneSettingsManifestRows(snapshot: CompanionResolvedSnapshot(state: .unreadable)) == .hidden)
        #expect(PhoneSettingsManifestRows(snapshot: nil) == .hidden)
    }

    // MARK: iPhone sync status

    @Test func liveDataReadsOnWithTheManifestAge() throws {
        let snapshot = CompanionDemoData.snapshot(.multiAccount, now: now)
        let status = PhoneSyncStatus(snapshot: snapshot, now: now, timeZone: utc, locale: locale)
        #expect(status.state == "On")
        // The demo Mac published a minute before `now`.
        #expect(status.lastUpdate == "1 min ago")
        #expect(status.dimmedLine == nil)
    }

    @Test func aQuietMacReadsTheDimmedSentence() throws {
        let snapshot = CompanionDemoData.snapshot(.dimmed, now: now)
        let status = PhoneSyncStatus(snapshot: snapshot, now: now, timeZone: utc, locale: locale)
        #expect(status.state == "On")
        let line = try #require(status.dimmedLine)
        #expect(line.hasPrefix("No update from your Mac since "))
    }

    @Test func nonContentStatesNameThemselves() {
        #expect(PhoneSyncStatus(snapshot: CompanionDemoData.snapshot(.paused, now: now), now: now).state
            == "Paused on your Mac")
        #expect(PhoneSyncStatus(snapshot: CompanionDemoData.snapshot(.waiting, now: now), now: now).state
            == "Waiting for your Mac")
        #expect(PhoneSyncStatus(snapshot: CompanionResolvedSnapshot(state: .accountScopeUnavailable), now: now).state
            == "iCloud not available")
        #expect(PhoneSyncStatus(snapshot: CompanionResolvedSnapshot(state: .unreadable), now: now).state
            == "Couldn’t read your Mac’s last update")
        #expect(PhoneSyncStatus(snapshot: nil, now: now).state == "Checking…")
        #expect(PhoneSyncStatus(snapshot: CompanionDemoData.snapshot(.paused, now: now), now: now).lastUpdate == nil)
    }

    // MARK: Check-now round trip

    @Test func theRoundTripRowShowsDurationAndAge() {
        let trip = PhoneCheckNowRoundTrip(requestedAt: now.addingTimeInterval(-200), finishedAt: now.addingTimeInterval(-188))
        #expect(trip.text(now: now) == "12 s · 3 min ago")
        let long = PhoneCheckNowRoundTrip(requestedAt: now.addingTimeInterval(-150), finishedAt: now.addingTimeInterval(-30))
        #expect(long.text(now: now) == "2 min · just now")
    }

    // MARK: What syncs (KTD22)

    @Test func whatSyncsNamesExactlyTheKTD22ListAndNoEncryptionClaim() {
        let list = PhoneSettingsCopy.whatSyncs
        #expect(list == [
            "Account names you chose",
            "Plan names",
            "Usage and reset times",
            "API spend",
            "Display choices",
            "Check-now requests",
            "A random ID for your Mac and for each iPhone or iPad",
            "A random ID that tells this app which iCloud account its saved data belongs to",
        ])
        #expect(PhoneSettingsCopy.whatSyncsFooter.contains("isn’t end-to-end encrypted"))
        #expect(!PhoneSettingsCopy.whatSyncsFooter.localizedCaseInsensitiveContains("source ID"))
    }

    @Test func noRenewalDatesCopyAndR2C6Rules() {
        for line in PhoneSettingsCopy.all {
            #expect(!line.localizedCaseInsensitiveContains("renewal"), "renewal dates were cut: \(line)")
            #expect(!line.contains("'"), "straight apostrophe in: \(line)")
            #expect(!line.localizedCaseInsensitiveContains("connect"), "retired verb in: \(line)")
        }
    }
}
