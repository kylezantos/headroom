#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
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
    @Binding var accountLayout: AccountLayout
    @Binding var showCodexSparkCountersInApp: Bool
    @Binding var showsAntigravityFiveHourWindows: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Two fixed columns on the same centers for every row, so they line up the way Format /
    /// Shape / Fill do in the meter tile. CA-S11: the window's wide swatch (150 → 160), which
    /// spans two of the meter tile's columns exactly.
    private let swatchWidth: CGFloat = SettingsSwatchWidth.wide
    private let swatchSpacing: CGFloat = SettingsSwatchWidth.gap

    /// R2C19/R2B1: `SettingsTile` owns the container, the title and the group rhythm, so this
    /// tile can no longer drift from the two beside it. CA-S8: sentence case, like every tile
    /// title in the window.
    var body: some View {
        SettingsTile("In-app display") {
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
            // The swatches and VoiceOver's picker both write the binding; this one write reaches the store.
            .onChange(of: usagePercentageMode) { _, newValue in store.setUsagePercentageMode(newValue) }

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
            // The swatches and VoiceOver's picker both write the binding; this one write reaches the store.
            .onChange(of: accountTitleInk) { _, newValue in store.setAccountTitleInk(newValue) }

            // Popover account layout plan (R1, HD-2): a third swatch row beside the other two
            // reading choices. Long account lists choose their overflow direction below.
            swatchRow(
                "Account layout",
                selection: accountLayout,
                help: "Compact shows each account on one line. Recommended for 5+ accounts."
            ) {
                ForEach(AccountLayout.allCases) { layout in
                    accountLayoutSwatch(layout)
                }
            }
            .accessibilityRepresentation {
                Picker("Account layout", selection: $accountLayout) {
                    ForEach(AccountLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
            }
            // The VoiceOver picker writes only the binding; the swatch's action is what
            // reaches the store, so persist from the binding too (equal values are ignored).
            .onChange(of: accountLayout) { _, newValue in
                store.setAccountLayout(newValue)
            }

            swatchRow(
                "Long account lists",
                selection: store.expandAccountsHorizontally,
                // CA-S9: what the choice is about, not the two options said again.
                help: "What the popover does when your accounts no longer fit its height."
            ) {
                expansionSwatch(horizontal: true)
                expansionSwatch(horizontal: false)
            }
            .accessibilityRepresentation {
                Picker("Long account lists", selection: Binding(
                    get: { store.expandAccountsHorizontally },
                    set: { store.setExpandAccountsHorizontally($0) }
                )) {
                    Text("Expand horizontally").tag(true)
                    Text("Scroll vertically").tag(false)
                }
            }

            Toggle("Show Codex Spark counters in app", isOn: $showCodexSparkCountersInApp)
                .onChange(of: showCodexSparkCountersInApp) { _, newValue in
                    store.setShowCodexSparkCountersInApp(newValue)
                }

            // Beside the Spark switch, offered while Antigravity is tracked (it is opt-in, so a
            // switch about rows nobody sees would only be noise). One value for every surface:
            // the popover, the menu bar, widgets, the phone and reminders. The weekly rows
            // always stay.
            if store.providerOrder.contains(.antigravity) {
                Toggle(isOn: $showsAntigravityFiveHourWindows) {
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                        Text(Self.antigravityFiveHourTitle)
                        SettingsHelpText(text: Self.antigravityFiveHourHelp)
                    }
                }
                .onChange(of: showsAntigravityFiveHourWindows) { _, newValue in
                    store.setShowsAntigravityFiveHourWindows(newValue)
                }
            }
        }
    }

    static let antigravityFiveHourTitle = "Show 5-hour windows"
    static let antigravityFiveHourHelp =
        "Antigravity’s Gemini and Other 5-hour limits, everywhere they appear: the popover, menu bar, widgets, iPhone and reminders. When off, they still show if no weekly limit has a number."

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

    // MARK: - Account layout

    /// Standard previews an account section — a name over two meter lines; Compact previews
    /// three accounts on a line each. Both draw the user's own meter as its Micro twin, the
    /// way the Percentages swatch does.
    private func accountLayoutSwatch(_ layout: AccountLayout) -> some View {
        swatch(
            label: layout.label,
            isSelected: accountLayout == layout,
            accessibilityLabel: "\(layout.label) account layout",
            action: {
                accountLayout = layout
                store.setAccountLayout(layout)
            }
        ) {
            Group {
                switch layout {
                case .standard:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ProviderStyle.accountTitleInk(for: .claude, ink: accountTitleInk, scheme: colorScheme))
                        layoutMeterLine(label: "5-hour", fraction: 0.72)
                        layoutMeterLine(label: "Weekly", fraction: 0.38)
                    }
                case .compact:
                    VStack(alignment: .leading, spacing: 2) {
                        layoutCompactLine("Personal", 0.72, 0.38)
                        layoutCompactLine("Work", 0.29, 0.61)
                        layoutCompactLine("Studio", 0.88, 0.59)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var swatchMicroStyle: MeterStyle {
        CompactAccountRowRecipe.microTwin(of: meterStyle)
    }

    private func expansionSwatch(horizontal: Bool) -> some View {
        let label = horizontal ? "Expand horizontally" : "Scroll vertically"
        return swatch(
            label: label,
            isSelected: store.expandAccountsHorizontally == horizontal,
            accessibilityLabel: label,
            action: { store.setExpandAccountsHorizontally(horizontal) }
        ) {
            // A 28pt miniature leaves 4pt above and below inside the shared 36pt well.
            // Two 32pt panels and a 6pt gutter show widening; one panel and a scroller
            // show the fixed-width alternative. The rows are schematic, not real meters.
            let panelWidth: CGFloat = 32
            let panelHeight: CGFloat = 28
            let gutter: CGFloat = 6
            let ink = ProviderStyle.secondaryText(scheme: colorScheme)
            HStack(spacing: gutter) {
                Canvas { context, _ in
                    for column in 0..<(horizontal ? 2 : 1) {
                        let x = CGFloat(column) * (panelWidth + gutter)
                        let panel = Path(roundedRect: CGRect(x: x, y: 0, width: panelWidth, height: panelHeight), cornerRadius: 3)
                        context.fill(panel, with: .color(ink.opacity(0.08)))
                        context.stroke(panel, with: .color(ink.opacity(0.45)), lineWidth: 1)
                        for row in 0..<3 {
                            let line = Path(roundedRect: CGRect(x: x + 5, y: 6 + CGFloat(row) * 7, width: 17, height: 2), cornerRadius: 1)
                            context.fill(line, with: .color(ink))
                        }
                    }
                    if !horizontal {
                        let track = CGRect(x: panelWidth - 6, y: 4, width: 2, height: panelHeight - 8)
                        context.fill(Path(roundedRect: track, cornerRadius: 1), with: .color(ink.opacity(0.2)))
                        let thumb = CGRect(x: track.minX, y: track.minY + 2, width: track.width, height: 7)
                        context.fill(Path(roundedRect: thumb, cornerRadius: 1), with: .color(ink))
                    }
                }
                .frame(width: horizontal ? panelWidth * 2 + gutter : panelWidth, height: panelHeight)

                Image(systemName: horizontal ? "arrow.left.and.right" : "arrow.up.and.down")
                    .font(SettingsType.swatchLabel)
                    .foregroundStyle(ink)
            }
            .accessibilityHidden(true)
        }
    }

    private func layoutMeterLine(label: String, fraction: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            MeterGauge(style: swatchMicroStyle, fraction: fraction, severity: .healthy, freshness: .live, scale: 0.6)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
        }
    }

    private func layoutCompactLine(_ name: String, _ first: Double, _ second: Double) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(ProviderStyle.accountTitleInk(for: .claude, ink: accountTitleInk, scheme: colorScheme))
            Spacer(minLength: 4)
            ForEach([first, second], id: \.self) { fraction in
                MeterGauge(style: swatchMicroStyle, fraction: fraction, severity: .healthy, freshness: .live, scale: 0.5)
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: 7.5, weight: .semibold).monospacedDigit())
            }
        }
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
