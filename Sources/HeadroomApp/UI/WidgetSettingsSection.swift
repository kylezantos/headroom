import SwiftUI

struct WidgetSettingsSection: View {
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Share data with widgets", isOn: $widgetsEnabled)
            Text("Add or remove widgets from macOS. This controls whether Headroom supplies usage data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show Codex Spark counters in widgets", isOn: $showCodexSparkCountersInWidgets)

            Toggle("Sync snapshot to iPhone", isOn: $syncToIPhoneEnabled)
            Text("Sends only the widget-safe usage snapshot through your iCloud account. No provider credentials are synced.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
