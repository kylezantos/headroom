import SwiftUI
import HeadroomCore

/// The "In-app display" tile, rebuilt as visual swatches (Sep 2026) so its two choices
/// preview themselves the way Theme and Meter style do, instead of naming themselves in a
/// segmented control. Each swatch is a small, honest fragment of the surface the choice
/// changes:
/// - **Percentages** shows a live `MeterGauge` at the mode's fraction beside the reading it
///   produces ("62% left" vs "38% used") — the numbers, words, and meter direction the help
///   line describes, all three visible at once.
/// - **Account names** shows two provider names inked the way the popover would ink them —
///   the recessive grey for Neutral, each provider's brand tint for Brand.
///
/// Chrome, captions, and the selection ring match `MeterStyleTile` / `ThemeThumbnailPicker`
/// so the Appearance pane reads as one family of choices (PB13 gives all three the one
/// `selectionChrome` modifier).
struct InAppDisplayTile: View {
    let store: UsageStore
    /// PA5: the Percentages swatch draws the meter the user actually has, not a chip/solid
    /// stand-in — the axis under test here is the reading, not the meter.
    let meterStyle: MeterStyle
    @Binding var usagePercentageMode: UsagePercentageMode
    @Binding var accountTitleInk: AccountTitleInk
    @Binding var showCodexSparkCountersInApp: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Two fixed columns on the same centers for both rows, so Percentages and Account
    /// names line up the way Format / Shape / Fill do in the meter tile.
    private let swatchWidth: CGFloat = 150
    private let swatchSpacing: CGFloat = 8

    /// R2C19/R2B1: `SettingsTile` owns the container, the title case ("In-App Display"), and
    /// the group rhythm, so this tile can no longer drift from the two beside it.
    var body: some View {
        SettingsTile("In-App Display") {
            swatchRow(
                "Percentages",
                selection: usagePercentageMode,
                help: "Changes the numbers, words, and meter direction in the app and menu bar."
            ) {
                ForEach(UsagePercentageMode.allCases) { mode in
                    percentageSwatch(mode)
                }
            }
            // G1A: the popover's account names read as a recessive grey by default; Brand
            // puts them back in each provider's color for people who want it.
            .accessibilityRepresentation {
                Picker("Percentages", selection: $usagePercentageMode) {
                    ForEach(UsagePercentageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            swatchRow(
                "Account names",
                selection: accountTitleInk,
                help: "Brand colors each account name in its provider’s color."
            ) {
                ForEach(AccountTitleInk.allCases) { ink in
                    accountNameSwatch(ink)
                }
            }
            .accessibilityRepresentation {
                Picker("Account names", selection: $accountTitleInk) {
                    ForEach(AccountTitleInk.allCases) { ink in
                        Text(ink.label).tag(ink)
                    }
                }
            }

            Toggle("Show Codex Spark counters in app", isOn: $showCodexSparkCountersInApp)
                .onChange(of: showCodexSparkCountersInApp) { _, newValue in
                    store.setShowCodexSparkCountersInApp(newValue)
                }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(swatchWidth), spacing: swatchSpacing, alignment: .leading),
            count: 2
        )
    }

    private func swatchRow<Selection: Equatable, Swatches: View>(
        _ caption: String,
        selection: Selection,
        help: String,
        @ViewBuilder swatches: () -> Swatches
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
            SettingsGroupLabel(caption)

            LazyVGrid(columns: columns, alignment: .leading, spacing: swatchSpacing) {
                swatches()
            }
            // SM1: the row's selection plate slides between its swatches.
            .settingsSelectionGroup(value: selection)

            SettingsHelpText(text: help)
        }
    }

    // MARK: - Percentages

    /// A `MeterGauge` at the mode's fraction beside the reading it produces. A weekly window
    /// sitting at 62% remaining fills to 0.62 and reads "62% left"; the same window in Used
    /// fills to 0.38 and reads "38% used" — the flip the popover and menu bar perform.
    private func percentageSwatch(_ mode: UsagePercentageMode) -> some View {
        let isSelected = usagePercentageMode == mode
        let fraction = mode == .remaining ? 0.62 : 0.38
        let pct = Int((fraction * 100).rounded())

        return swatch(
            label: mode.label,
            isSelected: isSelected,
            accessibilityLabel: "\(mode.label) percentages",
            action: {
                usagePercentageMode = mode
                store.setUsagePercentageMode(mode)
            }
        ) {
            HStack(spacing: 8) {
                // PA5: shape and fill come from the live selection; the fraction is the axis
                // under test and stays literal. Drawn at Micro because this is a 150 × 36pt
                // swatch, and resolved against the live format so Tube-under-Full previews
                // the Chip the popover would actually draw.
                MeterGauge(
                    style: MeterStyle(
                        format: .micro,
                        shape: meterStyle.shape.resolved(for: meterStyle.format),
                        fill: meterStyle.fill
                    ),
                    fraction: fraction,
                    severity: .healthy,
                    freshness: .live
                )
                .frame(width: 46)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(pct)%")
                        .font(.system(size: 13, weight: .semibold))
                    Text(mode.term)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Account names

    private func accountNameSwatch(_ ink: AccountTitleInk) -> some View {
        let isSelected = accountTitleInk == ink

        return swatch(
            label: ink.label,
            isSelected: isSelected,
            accessibilityLabel: "\(ink.label) account names",
            action: {
                accountTitleInk = ink
                store.setAccountTitleInk(ink)
            }
        ) {
            VStack(alignment: .leading, spacing: 3) {
                accountNameLine(.claude, ink: ink)
                accountNameLine(.codex, ink: ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
        }
    }

    private func accountNameLine(_ id: ProviderID, ink: AccountTitleInk) -> some View {
        Text(id.displayName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ProviderStyle.accountTitleInk(for: id, ink: ink, scheme: colorScheme))
    }

    // MARK: - Shared swatch shell

    /// The swatch shell shared by both rows: a 36pt well over a swatch label, matching the
    /// meter-tile swatches' rhythm.
    private func swatch<Content: View>(
        label: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                content()
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        ProviderStyle.recessedWell(dark: colorScheme == .dark),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text(label)
                    .font(SettingsType.swatchLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(5)
            .selectionChrome(isSelected: isSelected)
        }
        .buttonStyle(SettingsSwatchButtonStyle())
        .help(label)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
