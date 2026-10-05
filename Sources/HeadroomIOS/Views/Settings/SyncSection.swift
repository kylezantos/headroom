import SwiftUI

/// KTD22: the iPhone sync section — status, the manifest's age, the last check-now round trip
/// and exactly what syncs. No row ever shows the Mac's source ID.
struct SyncSection: View {
    let snapshot: CompanionResolvedSnapshot?
    let isDemoMode: Bool
    /// U9 hands this over once a check-now request finishes; until then the row is absent.
    let lastCheckNow: PhoneCheckNowRoundTrip?
    let now: Date

    var body: some View {
        let status = PhoneSyncStatus(snapshot: snapshot, now: now)
        Section {
            LabeledContent("Status", value: status.state)
                .accessibilityIdentifier("headroom.settings.sync.status")
            if isDemoMode {
                LabeledContent("Source", value: "Sample data")
            }
            if let lastUpdate = status.lastUpdate {
                LabeledContent("Last update", value: lastUpdate)
                    .accessibilityIdentifier("headroom.settings.sync.lastUpdate")
            }
            if let dimmedLine = status.dimmedLine {
                // KTD15: the same sentence the Usage screen and widgets show once the Mac goes
                // quiet. Neutral ink (R4).
                Text(dimmedLine)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("headroom.settings.sync.dimmed")
            }
            if let lastCheckNow {
                LabeledContent("Last check", value: lastCheckNow.text(now: now))
            }
        } header: {
            Text("iPhone sync")
        } footer: {
            Text(PhoneSettingsCopy.managedOnMac)
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(PhoneSettingsCopy.whatSyncs, id: \.self) { item in
                    Text(item)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("headroom.settings.whatSyncs")
        } header: {
            Text("What syncs through your iCloud")
        } footer: {
            Text(PhoneSettingsCopy.whatSyncsFooter)
        }
    }
}
