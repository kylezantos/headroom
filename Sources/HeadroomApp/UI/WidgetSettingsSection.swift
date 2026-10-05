import SwiftUI
import HeadroomCore

/// Widgets tile content: master enables as switch rows, the dependent Spark-counter
/// option as a checkbox, and help text on the shared 11pt style (this section
/// previously ran 10pt `.caption`, splitting one role across two sizes).
struct WidgetSettingsSection: View {
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool
    let store: UsageStore

    /// System Settings' sub-option indent: dependent controls sit one step in from the
    /// switch that governs them.
    private static let subOptionIndent: CGFloat = 20

    /// "at 2:41 PM" today, "on Oct 3 at 2:41 PM" otherwise.
    private static func publishTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDateInToday(date) else { return "at \(time)" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
    }

    var body: some View {
        // PB4: two groups, not three peers. The Spark-counter checkbox is a sub-option of
        // widget export, so it nests inside that group; floating between the two switches at
        // the same gap, it read as belonging to neither. S6B (2026-09-22 spacing audit): the
        // provider picker is a widget sub-option too, so both indent under the switch they
        // depend on instead of the picker splitting the switch from its checkbox.
        VStack(alignment: .leading, spacing: SettingsMetrics.groupToGroup) {
            VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                    SettingsSwitchRow(title: "Share data with widgets", isOn: $widgetsEnabled)
                    SettingsHelpText(text: "Controls whether Headroom supplies usage data to macOS widgets.")
                }

                VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                        ResponsiveControlRow(label: "Widget providers") {
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
                            .fixedSize()
                        }
                        SettingsHelpText(text: "Widgets show up to two selected providers in app order. Menu bar pills are configured\u{00A0}separately.")
                    }
                    Toggle("Show Codex Spark counters in widgets", isOn: $showCodexSparkCountersInWidgets)
                }
                .padding(.leading, Self.subOptionIndent)
            }

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
                // G9: the Mac had no way to reach the iPhone app.
                Link(AboutLinks.iPhoneApp.title, destination: AboutLinks.iPhoneApp.url)
                    .font(SettingsType.help)
            }
        }
    }

}
