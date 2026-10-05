import SwiftUI

/// U12 stub for R28/R29. Stream F owns this file and fills it in U16 if the CloudKit spike
/// passes; on a spike fail the default line below stays, because reminders then come only
/// from the Mac (R29). Until then the section shows the Mac's own reminder switches read-only
/// from the manifest's reminder summary (KTD19), under the same gating as every manifest row.
struct RemindersSection: View {
    let manifestRows: PhoneSettingsManifestRows

    var body: some View {
        switch manifestRows {
        case .hidden:
            EmptyView()
        case .updateMac:
            Section {
                Text(PhoneSettingsCopy.updateMac)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reminders")
            } footer: {
                Text(PhoneSettingsCopy.remindersFromMac)
            }
        case .available(_, let reminders):
            Section {
                LabeledContent("Before unused usage resets", value: onOff(reminders?.macUseItUpEnabled))
                LabeledContent("When Codex banks a reset", value: onOff(reminders?.macBankedResetEnabled))
            } header: {
                Text("Reminders")
            } footer: {
                Text(PhoneSettingsCopy.remindersFromMac)
            }
            .accessibilityIdentifier("headroom.settings.reminders")
        }
    }

    private func onOff(_ value: Bool?) -> String {
        value == true ? "On" : "Off"
    }
}
