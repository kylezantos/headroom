import SwiftUI
import HeadroomCore

/// CA-S7: the "Mac widgets" tile's content. Master enable as a switch row, the dependent
/// provider menu and Spark-counter option indented under it, help on the shared 11pt style.
/// The iPhone switch used to share this untitled tile; two features now get two titled tiles.
struct MacWidgetSettingsSection: View {
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    let store: UsageStore

    /// System Settings' sub-option indent: dependent controls sit one step in from the
    /// switch that governs them.
    private static let subOptionIndent: CGFloat = 20

    var body: some View {
        // PB4: the Spark-counter checkbox is a sub-option of widget export, so it nests inside
        // that group. S6B (2026-09-22 spacing audit): the provider picker is a widget
        // sub-option too, so both indent under the switch they depend on.
        VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsSwitchRow(title: "Share data with widgets", isOn: $widgetsEnabled)
                // CA-S9: the consequence, in the widget's own words (`WidgetStatusCopy`),
                // instead of the label said again.
                SettingsHelpText(text: "When off, your widgets show “\(WidgetStatusState.macDisabled.title)”.")
            }

            VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                    ResponsiveControlRow(label: "Widget providers") {
                        providerMenu
                    }
                    SettingsHelpText(text: "Widgets show up to two providers, in the order of your accounts.")
                }
                Toggle("Show Codex Spark counters in widgets", isOn: $showCodexSparkCountersInWidgets)
            }
            .padding(.leading, Self.subOptionIndent)
        }
    }

    private var providerMenu: some View {
        Menu {
            Button { store.setWidgetPrioritySource(.auto) } label: {
                if store.widgetPrioritySource == .auto {
                    Label("Automatic (first two enabled)", systemImage: "checkmark")
                } else {
                    Text("Automatic (first two enabled)")
                }
            }
            Divider()
            ForEach(store.registeredProviderOrder, id: \.self) { id in
                Button {
                    var selected = store.widgetPrioritySource.providerIDs ?? []
                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                    store.setWidgetPrioritySource(selected.isEmpty ? .auto : .providers(selected))
                } label: {
                    if store.widgetPrioritySource.providerIDs?.contains(id) == true {
                        Label(store.displayNames[id] ?? id.raw, systemImage: "checkmark")
                    } else {
                        Text(store.displayNames[id] ?? id.raw)
                    }
                }
                .disabled(!store.providerOrder.contains(id))
            }
        } label: {
            Text(MenuBarPrioritySelection.label(
                source: store.widgetPrioritySource,
                fetchedOrder: store.providerOrder,
                displayName: { store.displayNames[$0] ?? $0.raw }
            ))
        }
        // CA-S10: small, the switches' height, so the trailing column shares one size.
        .controlSize(.small)
        .fixedSize()
    }
}

/// CA-S7: the "iPhone and iPad" tile's content.
struct IPhoneSyncSettingsSection: View {
    @Binding var syncToIPhoneEnabled: Bool
    let store: UsageStore

    /// "at 2:41 PM" today, "on Oct 3 at 2:41 PM" otherwise.
    private static func publishTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDateInToday(date) else { return "at \(time)" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
            // PB9: "usage", not "snapshot" — the user has no snapshot in their vocabulary,
            // and the next line already says what travels.
            SettingsSwitchRow(title: "Sync usage to iPhone", isOn: $syncToIPhoneEnabled)
            // KTD22 / R35: the exact what-syncs list, shared with the phone's Settings.
            SettingsHelpText(text: CompanionPrivacyCopy.whatSyncs)
            if syncToIPhoneEnabled, let status = store.phoneSyncStatus {
                SettingsHelpText(text: CompanionPrivacyCopy.macStatus(
                    lastPublishAt: status.lastPublishAt,
                    formattedTime: status.lastPublishAt.map(Self.publishTime),
                    ladderLevel: status.ladderLevel,
                    lastFailure: status.lastFailure))
            }
            // G9: the Mac had no way to reach the iPhone app. CA-S2: neutral ink.
            SettingsInlineLink(AboutLinks.iPhoneApp.title, destination: AboutLinks.iPhoneApp.url)
                .padding(.top, SettingsMetrics.labelToControl)
        }
    }
}
