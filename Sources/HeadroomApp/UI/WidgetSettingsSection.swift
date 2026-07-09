import SwiftUI

/// Widgets tile content: master enables as switch rows, the dependent Spark-counter
/// option as a checkbox, and help text on the shared 11pt style (this section
/// previously ran 10pt `.caption`, splitting one role across two sizes).
struct WidgetSettingsSection: View {
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SettingsSwitchRow(title: "Share data with widgets", isOn: $widgetsEnabled)
                // Leads with what the switch does; the old copy opened with an
                // instruction ("Add or remove widgets from macOS") this window
                // can't perform.
                SettingsHelpText(text: "Controls whether Headroom supplies usage data to macOS widgets.")
            }

            Toggle("Show Codex Spark counters in widgets", isOn: $showCodexSparkCountersInWidgets)

            VStack(alignment: .leading, spacing: 4) {
                SettingsSwitchRow(title: "Sync snapshot to iPhone", isOn: $syncToIPhoneEnabled)
                SettingsHelpText(text: "Sends only the widget-safe usage snapshot through your iCloud account. No provider credentials are synced.")
            }
        }
    }
}
