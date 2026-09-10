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
        VStack(alignment: .leading, spacing: SettingsMetrics.groupToGroup) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                    SettingsSwitchRow(title: "Share data with widgets", isOn: $widgetsEnabled)
                    helpText
                }

                Toggle("Show Codex Spark counters in widgets", isOn: $showCodexSparkCountersInWidgets)
            }

            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                // PB9: "usage", not "snapshot" — the user has no snapshot in their vocabulary,
                // and the next line already says what travels.
                SettingsSwitchRow(title: "Sync usage to iPhone", isOn: $syncToIPhoneEnabled)
                SettingsHelpText(text: "Sends only your usage numbers through iCloud. Sign-ins are never synced.")
            }
        }
    }

    /// R2B2: one help block under the switch, not two. Two `SettingsHelpText` views 4pt
    /// apart with 2pt of internal leading rendered as two paragraphs of one thought at
    /// almost the same gap as the lines inside them; as one string the sentences wrap into
    /// a single block on the shared measure.
    ///
    /// PB8: the widget-provider rule is stated once, in the Menu Bar pane that owns it; the
    /// second sentence points there instead of paraphrasing it into a second,
    /// differently-worded rule.
    private var helpText: some View {
        SettingsHelpText(attributed: helpString)
            .environment(\.openURL, OpenURLAction { url in
                guard url == Self.menuBarPaneURL else { return .systemAction }
                onShowMenuBarPane()
                return .handled
            })
    }

    private var helpString: AttributedString {
        // Leads with what the switch does; the old copy opened with an instruction ("Add or
        // remove widgets from macOS") this window can't perform.
        var sentence = AttributedString(
            "Controls whether Headroom supplies usage data to macOS widgets. "
                + "Widgets follow the priority providers you choose in "
        )
        var link = AttributedString("Menu Bar")
        link.link = Self.menuBarPaneURL
        sentence.append(link)
        sentence.append(AttributedString("."))
        return sentence
    }
}
