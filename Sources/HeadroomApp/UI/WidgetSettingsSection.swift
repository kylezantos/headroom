import SwiftUI

/// Widgets tile content: master enables as switch rows, the dependent Spark-counter
/// option as a checkbox, and help text on the shared 11pt style (this section
/// previously ran 10pt `.caption`, splitting one role across two sizes).
struct WidgetSettingsSection: View {
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool
    let onShowMenuBarPane: () -> Void

    /// PB8: an in-app destination, not a web address — `openURL` is intercepted below and
    /// never reaches the system. Kept private to this file so nothing else can navigate by
    /// forging a URL.
    private static let menuBarPaneURL = URL(string: "headroom-settings://pane/menu-bar")!

    var body: some View {
        // PB4: two groups, not three peers. The Spark-counter checkbox is a sub-option of
        // widget export, so it nests inside that group; floating between the two switches at
        // the same gap, it read as belonging to neither.
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsSwitchRow(title: "Share data with widgets", isOn: $widgetsEnabled)
                    // Leads with what the switch does; the old copy opened with an
                    // instruction ("Add or remove widgets from macOS") this window
                    // can't perform.
                    SettingsHelpText(text: "Controls whether Headroom supplies usage data to macOS widgets.")
                    providerRule
                }

                Toggle("Show Codex Spark counters in widgets", isOn: $showCodexSparkCountersInWidgets)
            }

            VStack(alignment: .leading, spacing: 4) {
                // PB9: "usage", not "snapshot" — the user has no snapshot in their vocabulary,
                // and the next line already says what travels.
                SettingsSwitchRow(title: "Sync usage to iPhone", isOn: $syncToIPhoneEnabled)
                SettingsHelpText(text: "Sends only your usage numbers through iCloud. Sign-ins are never synced.")
            }
        }
    }

    /// PB8: the widget-provider rule is stated once, in the Menu Bar pane that owns it; this
    /// line points there instead of paraphrasing it into a second, differently-worded rule.
    private var providerRule: some View {
        SettingsHelpText(attributed: ruleText)
            .environment(\.openURL, OpenURLAction { url in
                guard url == Self.menuBarPaneURL else { return .systemAction }
                onShowMenuBarPane()
                return .handled
            })
    }

    private var ruleText: AttributedString {
        var sentence = AttributedString("Widgets follow the priority providers you choose in ")
        var link = AttributedString("Menu Bar")
        link.link = Self.menuBarPaneURL
        sentence.append(link)
        sentence.append(AttributedString("."))
        return sentence
    }
}
