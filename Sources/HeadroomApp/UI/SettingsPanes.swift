import AppKit
import SwiftUI
import HeadroomCore

/// The six Settings destinations (R1). KTD3: every pane here is stateless — root state
/// lives on `SettingsView` and reaches these views as bindings, closures, or the store,
/// so switching panes never resets a draft, a result message, or a pending dialog (R13).

/// Shared detail-column chrome: the pane title, then its tiles, inside a scroll view that
/// fills the fixed window frame. KTD2 — the outer frame is fixed, so the scroll view is
/// pinned to `.infinity` rather than relying on ideal sizes (see
/// `docs/solutions/popover-scrollview-zero-height.md`).
struct SettingsPaneScaffold<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            // R2C19: the pane's two levels no longer share one 14. The title sits close to
            // the tile it heads and the tiles stand well apart, so which level a gap
            // separates is legible from the gap alone.
            VStack(alignment: .leading, spacing: SettingsMetrics.headerToContent) {
                // PB2: 17, one step above the 15pt tile headers under it. At 15 the two were
                // byte-identical, so "Appearance" and "Theme" differed only by indent and the
                // pane had no top of its hierarchy.
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.2)
                VStack(alignment: .leading, spacing: SettingsMetrics.tileToTile) {
                    content
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
            // L9A: the window is resizable now, so the pane's measure is capped and
            // left-aligned rather than tracking the column. Without this a 1200pt-wide
            // window runs a help line the whole way across.
            .frame(maxWidth: SettingsView.detailContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    @Binding var intervalMinutes: Int
    @Binding var launchAtLogin: Bool
    @Binding var automaticUpdateChecks: Bool
    let softwareUpdates: SoftwareUpdateControlling
    /// KTD12: names each provider whose effective interval exceeds the chosen one; nil
    /// while every promise is kept (R10).
    let cadenceSentence: String?
    let onIntervalChange: (Int) -> Void
    let onLaunchAtLoginChange: (Bool) -> Void
    let onAutomaticUpdateChecksChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneScaffold(SettingsPane.general.label) {
            SettingsTile {
                VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                    ResponsiveControlRow(label: "Refresh every") {
                        Stepper(value: $intervalMinutes, in: 2...60) {
                            Text("\(intervalMinutes) min")
                                // Tabular digits so 5 → 10 doesn't reflow the row.
                                .monospacedDigit()
                                // R2M7/S2A: the roll is movement, so Reduce Motion swaps the
                                // text outright — via the helper, not a hand-rolled literal.
                                .contentTransition(
                                    HeadroomMotion.numericText(
                                        value: Double(intervalMinutes),
                                        reduceMotion: reduceMotion
                                    )
                                )
                        }
                        // R2M7: `pressDown`, not the `press` compat alias, and resolved as
                        // `.movement` to match the digit roll it drives.
                        .animation(
                            HeadroomMotion.resolved(
                                HeadroomMotion.pressDown,
                                .movement,
                                reduceMotion: reduceMotion
                            ),
                            value: intervalMinutes
                        )
                        .onChange(of: intervalMinutes) { _, newValue in
                            onIntervalChange(newValue)
                        }
                    }
                    // One help block (R2B2): the cadence sentence folds in rather than stacking
                    // a paragraph per provider. Non-breaking spaces keep "2 min." from
                    // orphaning onto its own line.
                    SettingsHelpText(text: ["Each account refreshes on its own schedule.", cadenceSentence, "Minimum\u{00A0}2\u{00A0}min."]
                        .compactMap { $0 }
                        .joined(separator: " "))
                }
                SettingsSwitchRow(title: "Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        onLaunchAtLoginChange(newValue)
                    }
            }

            // L13: software update gets its own group at the foot of the pane, the way
            // System Settings separates it from the general preferences above, instead
            // of riding under "Launch at login".
            //
            // Hidden — not permanently dimmed — when no updater is configured
            // (debug/CLI builds lack the Sparkle Info.plist keys). A button that can
            // never be pressed reads as broken. (R3: the removed footer's action.)
            if softwareUpdates.canCheckForUpdates {
                SettingsTile("Updates") {
                    ResponsiveControlRow(label: versionRowLabel) {
                        Button("Check for Updates…") {
                            softwareUpdates.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                        SettingsSwitchRow(
                            title: "Automatically check for updates",
                            isOn: $automaticUpdateChecks
                        )
                        .onChange(of: automaticUpdateChecks) { _, newValue in
                            onAutomaticUpdateChecksChange(newValue)
                        }
                        SettingsHelpText(text: "Headroom checks in the background and tells you when a new version is ready.")
                    }
                }
            }
        }
    }

    /// The bundle's version beside the check button, in the About-panel form
    /// ("Version 1.4.0 (32)"). The tile only renders in a configured release bundle, so
    /// the number is present in practice; the bare label is the safe fallback.
    private var versionRowLabel: String {
        guard let version = AppVersionLabel.plain else { return "Version" }
        return "Version \(version)"
    }
}

// MARK: - Appearance

/// Every visual choice in one room (KD7): the live specimen on top, then Theme, meter
/// style, and the in-app display switches under it — the three tiles the specimen
/// responds to, in the order it responds to them.
struct AppearanceSettingsPane: View {
    let store: UsageStore
    @Binding var appearancePreference: AppearancePreference
    @Binding var meterStyle: MeterStyle
    @Binding var usagePercentageMode: UsagePercentageMode
    @Binding var accountTitleInk: AccountTitleInk
    @Binding var showCodexSparkCountersInApp: Bool
    let onAppearanceChange: (AppearancePreference) -> Void
    let onMeterStyleChange: (MeterStyle) -> Void

    var body: some View {
        SettingsPaneScaffold(SettingsPane.appearance.label) {
            // R6: sits on the pane background above the tiles, not inside one — it is
            // the subject of the pane, not another setting.
            AppearanceSpecimen(
                meterStyle: meterStyle,
                percentageMode: usagePercentageMode,
                accountTitleInk: accountTitleInk
            )

            SettingsTile("Theme") {
                ThemeThumbnailPicker(selection: $appearancePreference)
                    .onChange(of: appearancePreference) { _, newValue in
                        onAppearanceChange(newValue)
                    }
            }

            // L12B: every row is a swatch grid now, so the tile takes its full width.
            MeterStyleTile(meterStyle: meterStyle) { newStyle in
                meterStyle = newStyle
                onMeterStyleChange(newStyle)
            }

            // R8: the two display preferences that used to hide inside "Subscription
            // Usage", beside the switches that decide whether a provider is polled at
            // all. They change how numbers read, not what is fetched — and each previews
            // itself as a swatch, matching Theme and Meter style above.
            InAppDisplayTile(
                store: store,
                meterStyle: meterStyle,
                usagePercentageMode: $usagePercentageMode,
                accountTitleInk: $accountTitleInk,
                showCodexSparkCountersInApp: $showCodexSparkCountersInApp
            )
        }
    }
}

// MARK: - Menu Bar

/// Shared priority-label formatting now used by Widgets. Disabled providers stay
/// stored but do not claim to supply a visible tile.
enum MenuBarPrioritySelection {
    static func label(
        source: MenuBarFillSource,
        fetchedOrder: [ProviderID],
        displayName: (ProviderID) -> String
    ) -> String {
        guard let selected = source.providerIDs else { return "Auto" }
        let names = fetchedOrder.filter(selected.contains).map(displayName)
        // Every stored pick is switched off. The pill is neutral, so neither "Auto" (a
        // different, live behavior) nor the provider's name is true.
        return names.isEmpty ? "None" : names.joined(separator: " + ")
    }
}

struct MenuBarSettingsPane: View {
    let store: UsageStore

    @Environment(\.colorScheme) private var colorScheme

    private static let cardWidth: CGFloat = 100
    /// The two provider lists share one pitch whether a row carries a picker, a button, or
    /// read-only text, so the same provider sits at the same rhythm in both.
    private static let rowHeight: CGFloat = 24
    private static let rowSpacing: CGFloat = 4

    private var selected: [ProviderID] { store.selectedMenuBarProviders }
    private var available: [ProviderID] {
        store.registeredProviderOrder.filter { !selected.contains($0) }
    }

    var body: some View {
        // The specimen stays in view while the editor scrolls at the window's resize floor.
        VStack(alignment: .leading, spacing: SettingsMetrics.headerToContent) {
            Text(SettingsPane.menuBar.label)
                .font(.system(size: 17, weight: .semibold))
                .kerning(-0.2)
            // The scaffold's second level, retyped because this pane pins its first tile:
            // the two tiles stand `tileToTile` apart like every other pane's.
            VStack(alignment: .leading, spacing: SettingsMetrics.tileToTile) {
                SettingsTile {
                    preview
                    displayChoices
                }
                ScrollView(.vertical) {
                    SettingsTile("Your Pills") {
                        arranger
                        availablePills
                        windowChoices
                        SettingsHelpText(text: "Uses each provider’s main account. Removing a pill keeps its account connected.")
                        if store.menuBarFillSource != .auto {
                            Button("Use one automatic summary pill instead…") {
                                store.setMenuBarFillSource(.auto)
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: SettingsView.detailContentMaxWidth, alignment: .leading)
        // The explicit zero minimum is load-bearing. AppKit pins the detail column's
        // minimum height to this view's size at a zero-width proposal, where the pinned
        // tile's text wraps a word per line to ~1,000pt. The split view then outgrew the
        // window, which centred it and clipped both columns' tops under the title bar.
        // Panes built on `SettingsPaneScaffold` never hit this: their outer ScrollView
        // has no minimum height.
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                groupCaption("Menu bar preview")
                Spacer(minLength: 8)
                Text(store.menuBarFillSource == .auto ? "Automatic summary" : "\(selected.count) pills")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack {
                    Spacer(minLength: 0)
                    // No invisible percentage-on twin: seeing the width shrink is the
                    // point of the compact choice. Always use the production renderer.
                    MenuBarPreviewPill(meters: store.menuBarMeters, showsPercentage: store.showMenuBarPercentage)
                }
                .frame(minHeight: 30)
            }
            .frame(height: 30)
            .scrollIndicators(.automatic)
            .settingsPreviewWell(dark: colorScheme == .dark, verticalPadding: 6, cornerRadius: 14)
        }
    }

    private var percentageBinding: Binding<Bool> {
        Binding(get: { store.showMenuBarPercentage }, set: { store.setShowMenuBarPercentage($0) })
    }

    private var displayChoices: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
            groupCaption("Display")
            // The Appearance swatch grid: fixed 150pt columns, not the tile's full width.
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(150), spacing: 8, alignment: .leading), count: 2),
                alignment: .leading,
                spacing: 8
            ) {
                displayChoice(showsPercentage: true, title: "Pills + percentages", detail: "Exact usage at a glance")
                displayChoice(showsPercentage: false, title: "Pills only", detail: "Save menu bar space")
            }
            .accessibilityRepresentation {
                Picker("Menu bar display", selection: percentageBinding) {
                    Text("Pills + percentages").tag(true)
                    Text("Pills only").tag(false)
                }
            }
            SettingsHelpText(text: "Short on space? Pills only is useful on laptops with a notch.")
        }
    }

    private func displayChoice(showsPercentage: Bool, title: String, detail: String) -> some View {
        Button {
            store.setShowMenuBarPercentage(showsPercentage)
        } label: {
            // The Settings swatch shell (`InAppDisplayTile.swatch`): specimen in a 36pt r6
            // well, 5pt, a centered 10.5pt label, 5pt padding so the r11 ring stays concentric.
            // The detail line moved to the tooltip; the help line under the grid says it too.
            VStack(spacing: 5) {
                MenuBarPreviewPill(meters: Self.displaySamples, showsPercentage: showsPercentage)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        ProviderStyle.recessedWell(dark: colorScheme == .dark),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(5)
            .selectionChrome(isSelected: store.showMenuBarPercentage == showsPercentage)
        }
        .buttonStyle(SettingsSwatchButtonStyle())
        .help(detail)
    }

    /// Inert examples teach the two treatments even before usage is available. Only
    /// these swatches use fixtures; the main specimen and provider cards use the store.
    private static let displaySamples: [MenuBarMeter] = [72, 38].map { value in
        MenuBarMeter(summary: MenuBarSummary(text: "\(value)%", providerID: nil, detail: nil, isNeutral: false),
                     fill: Double(value) / 100)
    }

    @ViewBuilder private var arranger: some View {
        if store.menuBarFillSource == .auto {
            VStack(alignment: .leading, spacing: 8) {
                Text("One automatic summary pill")
                    .font(.system(size: 13, weight: .medium))
                SettingsHelpText(text: "Follows the provider closest to its limit. Add providers below to give each its own pill.")
            }
        } else if selected.isEmpty {
            SettingsHelpText(text: "Your selected providers are switched off. Turn on tracking in Accounts, or add another provider below.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SettingsHelpText(text: "Drag to arrange, or use the arrows. Order runs left to right.")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(selected, id: \.self) { id in
                            providerCard(id)
                        }
                    }
                    .padding(1)
                }
                // Horizontal scrollers have no useful ideal height in an AppKit host
                // (#popover-scroll-height). Reserve the card's full editing surface.
                .frame(height: 116)
                .scrollIndicators(.automatic)
                .settingsPreviewWell(dark: colorScheme == .dark, verticalPadding: 9, cornerRadius: 20)
            }
        }
    }

    private func providerCard(_ id: ProviderID) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
                    .help("Drag to arrange \(name(id))")
                    .accessibilityLabel("Drag \(name(id))")
                Spacer(minLength: 4)
                Button {
                    store.removeMenuBarProvider(id)
                } label: {
                    Image(systemName: "xmark")
                }
                .disabled(selected.count == 1)
                .help(selected.count == 1 ? "Keep one pill, or choose the automatic summary below" : "Remove \(name(id)) pill")
                .accessibilityLabel("Remove \(name(id)) pill")
            }
            .font(.system(size: 10))
            MenuBarPreviewPill(meters: [store.providerMenuBarMeter(for: id)], showsPercentage: store.showMenuBarPercentage)
                .frame(height: 25)
            Text(name(id))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .help(name(id))
            HStack(spacing: 12) {
                moveButton(id, offset: -1)
                moveButton(id, offset: 1)
            }
        }
        .buttonStyle(.borderless)
        .padding(8)
        .frame(width: Self.cardWidth)
        .selectionChrome(isSelected: false)
        .draggable(id.raw)
        .dropDestination(for: String.self) { values, location in
            guard values.count == 1, let raw = values.first else { return false }
            let source = ProviderID(raw)
            guard source != id, selected.contains(source), let index = selected.firstIndex(of: id) else { return false }
            let targetIndex = location.x < Self.cardWidth / 2 ? index : index + 1
            let target = selected.indices.contains(targetIndex) ? selected[targetIndex] : nil
            store.moveMenuBarProvider(source, before: target)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name(id)) menu bar pill")
    }

    private func moveButton(_ id: ProviderID, offset: Int) -> some View {
        let direction = offset < 0 ? "left" : "right"
        return Button {
            store.moveMenuBarProvider(id, by: offset)
        } label: {
            Image(systemName: "arrow.\(direction)")
                .font(.system(size: 11))
        }
        .disabled(offset < 0 ? selected.first == id : selected.last == id)
        .help("Move \(name(id)) \(direction)")
        .accessibilityLabel("Move \(name(id)) \(direction)")
    }

    @ViewBuilder private var availablePills: some View {
        if available.isEmpty {
            SettingsHelpText(text: "All \(selected.count) providers shown.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                groupCaption("Available pills")
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(available, id: \.self) { id in
                        HStack(spacing: 8) {
                            ProviderLogoView(providerID: id, size: 15)
                            Text(name(id))
                            Spacer(minLength: 8)
                            if store.providerOrder.contains(id) {
                                Button("Add pill", systemImage: "plus") { store.addMenuBarProvider(id) }
                                    .controlSize(.small)
                                    .accessibilityLabel("Add \(name(id)) pill")
                            } else {
                                SettingsPillBadge(text: "Off")
                                    .help(SettingsCopy.providerOffNotice)
                            }
                        }
                        .frame(minHeight: Self.rowHeight)
                    }
                }
                if available.contains(where: { !store.providerOrder.contains($0) }) {
                    SettingsHelpText(text: "Turn on provider tracking in Accounts to add its pill.")
                }
            }
        }
    }

    @ViewBuilder private var windowChoices: some View {
        let ids = store.menuBarFillSource == .auto ? store.providerOrder : selected
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                groupCaption("Usage shown in each pill")
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(ids, id: \.self) { id in
                        HStack(spacing: 8) {
                            ProviderLogoView(providerID: id, size: 15)
                            Text(name(id))
                            Spacer(minLength: 8)
                            if store.hasSelectableMenuBarWindows(for: id) {
                                Picker("\(name(id)) usage window", selection: Binding(
                                    get: { store.menuBarWindowSource(for: id) },
                                    set: { store.setMenuBarWindowSource($0, for: id) }
                                )) {
                                    ForEach(MenuBarWindowSource.allCases, id: \.self) { source in
                                        Text(source.label).tag(source)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .fixedSize()
                            } else {
                                Text(store.resolvedMenuBarWindowKind(for: id)?.shortLabel ?? "Waiting for usage")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: Self.rowHeight)
                        if let resolved = store.resolvedMenuBarWindowSource(for: id),
                           resolved != store.menuBarWindowSource(for: id) {
                            SettingsHelpText(text: "Using \(resolved.label.lowercased()) while \(store.menuBarWindowSource(for: id).label.lowercased()) data is unavailable.")
                        }
                    }
                }
            }
        }
    }

    private func name(_ id: ProviderID) -> String {
        store.displayNames[id] ?? id.raw.capitalized
    }

    /// The Settings group caption (Format / Shape / Fill, Percentages / Account names):
    /// 11pt semibold secondary, sentence case. Tile titles are the only larger heading.
    private func groupCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Widgets & iPhone

struct WidgetsSettingsPane: View {
    let store: UsageStore
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool
    var body: some View {
        SettingsPaneScaffold(SettingsPane.widgets.label) {
            // L9P: sits on the pane background above the tile, like the Appearance
            // specimen — it is the subject of the pane, not another setting.
            WidgetPreviewStrip(widgetsEnabled: widgetsEnabled)

            SettingsTile {
                WidgetSettingsSection(
                    widgetsEnabled: $widgetsEnabled,
                    showCodexSparkCountersInWidgets: $showCodexSparkCountersInWidgets,
                    syncToIPhoneEnabled: $syncToIPhoneEnabled,
                    store: store
                )
                .onChange(of: widgetsEnabled) { _, newValue in
                    store.setWidgetsEnabled(newValue)
                }
                .onChange(of: showCodexSparkCountersInWidgets) { _, newValue in
                    store.setShowCodexSparkCountersInWidgets(newValue)
                }
                .onChange(of: syncToIPhoneEnabled) { _, newValue in
                    store.setSyncToIPhoneEnabled(newValue)
                }
            }
        }
    }
}

// MARK: - Accounts

/// R9/KD7: one room per provider. The old "Subscription Usage" tile is gone — each
/// provider's on/off switch now rides its own group header in `AccountsSettingsTile`,
/// next to the accounts it governs, and its two display preferences moved to Appearance
/// in U3.
struct AccountsSettingsPane: View {
    let store: UsageStore
    let duplicateLoginLabels: [AccountKey: String]
    let surfaceBinding: (UsageSurface) -> Binding<Bool>

    var body: some View {
        SettingsPaneScaffold(SettingsPane.accounts.label) {
            AccountsSettingsTile(
                store: store,
                duplicateLoginLabels: duplicateLoginLabels,
                surfaceBinding: surfaceBinding
            )
        }
    }
}

// MARK: - API Spend

struct APISpendSettingsPane: View {
    let store: UsageStore
    @Binding var apiSpendPeriod: APISpendPeriod
    @Binding var apiKeyDrafts: [APIKeyProvider: String]
    @Binding var replacingKeyProviders: Set<APIKeyProvider>
    @Binding var credentialMessages: [APIKeyProvider: String]
    let savedKeyProviders: Set<APIKeyProvider>
    let surfaceBinding: (UsageSurface) -> Binding<Bool>
    let onSaveKey: (String, APIKeyProvider) -> Void
    let onRequestRemoval: (APIKeyProvider) -> Void
    /// Cancels the root's pending auto-dismiss task for a provider's result message; the
    /// task itself stays on the root (KTD3) so a pane switch can't strand it.
    let cancelMessageDismissal: (APIKeyProvider) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneScaffold(SettingsPane.apiSpend.label) {
            SettingsTile {
                ForEach(store.registeredAPISpendProviderOrder, id: \.self) { providerID in
                    if let provider = APIKeyProvider.allCases.first(where: { $0.providerID == providerID }),
                       let surface = UsageSurface.api(for: providerID) {
                        apiProviderRows(
                            surface: surface,
                            provider: provider,
                            title: provider.adminKeyTitle,
                            placeholder: provider.keyPlaceholder,
                            text: apiKeyDraftBinding(for: provider)
                        )
                    }
                }
                // Period trails the provider rows it modifies (it used to lead them). PB4:
                // it is a sibling of those rows, not part of the last one — the tile's 18pt
                // between-group gap against their 8pt internal gap is what says so.
                ResponsiveControlRow(label: "Period") {
                    Picker("Period", selection: $apiSpendPeriod) {
                        ForEach(APISpendPeriod.allCases, id: \.self) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // PB3: pinned, not capped — see `menuBarWindowPicker`.
                    .frame(width: SettingsMetrics.segmentedMaxWidth, alignment: .trailing)
                    .onChange(of: apiSpendPeriod) { _, newValue in
                        store.setAPISpendPeriod(newValue)
                        store.refreshAPISpendNow()
                    }
                }
            }
        }
    }

    /// Master row (mark + name + switch), then — only while the surface is on — either
    /// a calm configured summary or the key editor. Credential state belongs beside
    /// the credential controls; putting it in the master row crowded the provider name
    /// enough to wrap at ordinary settings widths.
    @ViewBuilder private func apiProviderRows(
        surface: UsageSurface,
        provider: APIKeyProvider,
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        let saved = savedKeyProviders.contains(provider)
        let replacing = replacingKeyProviders.contains(provider)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: surface.providerID, size: 15)
                    Text(surface.displayName)
                }
                Spacer(minLength: 12)
                Toggle(surface.displayName, isOn: apiSurfaceBinding(surface, provider: provider))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            // R2B2: the group's children sit on the header's *text* axis with the mark
            // hanging in the margin — the Accounts convention. Left flush with the mark, the
            // provider name floated 22.5pt right of everything it heads.
            VStack(alignment: .leading, spacing: 8) {
                if store.isSurfaceEnabled(surface) {
                    if saved && !replacing {
                        configuredAPIKeyRow(provider: provider, title: title)
                            .transition(.settingsReveal(reduceMotion: reduceMotion))
                    } else {
                        apiKeyEditor(
                            provider: provider,
                            title: title,
                            placeholder: placeholder,
                            text: text,
                            replacing: replacing
                        )
                        .transition(.settingsReveal(reduceMotion: reduceMotion))
                    }
                }
                if let message = credentialMessages[provider] {
                    // Result feedback lives on the acted-on row (the old shared line
                    // rendered far away, under the other provider's rows).
                    SettingsHelpText(text: message)
                        .transition(.settingsReveal(reduceMotion: reduceMotion))
                }
            }
            .padding(.leading, Self.groupTextAxisInset)
        }
        // R2M7/S2A: through the resolver as `.crossfade`, so the editor⇄configured swap keeps
        // its fade under Reduce Motion; `reduceMotion ? nil :` killed the transition outright.
        // The reveal's own rise and blur are the movement half and drop inside the transition
        // (`settingsReveal(reduceMotion:)`) — an `.animation` scope cannot split a transition
        // from the height change beside it.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: savedKeyProviders
        )
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: replacingKeyProviders
        )
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: credentialMessages
        )
    }

    /// R2B2: the provider mark (15pt) plus the 7pt gap to its name — the inset that lands a
    /// group's children on the header's text axis.
    private static let groupTextAxisInset: CGFloat = 22

    private func apiSurfaceBinding(_ surface: UsageSurface, provider: APIKeyProvider) -> Binding<Bool> {
        let binding = surfaceBinding(surface)
        return Binding(
            get: { binding.wrappedValue },
            set: { isEnabled in
                binding.wrappedValue = isEnabled
                if !isEnabled {
                    replacingKeyProviders.remove(provider)
                    clearField(for: provider)
                }
            }
        )
    }

    private func apiKeyDraftBinding(for provider: APIKeyProvider) -> Binding<String> {
        Binding(
            get: { apiKeyDrafts[provider, default: ""] },
            set: { apiKeyDrafts[provider] = $0 }
        )
    }

    private func clearField(for provider: APIKeyProvider) {
        apiKeyDrafts[provider] = ""
    }

    private func configuredAPIKeyRow(provider: APIKeyProvider, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SavedCredentialStatus()
                Spacer(minLength: 12)
                Button("Replace Key") {
                    credentialMessages[provider] = nil
                    cancelMessageDismissal(provider)
                    replacingKeyProviders.insert(provider)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Remove") { onRequestRemoval(provider) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func apiKeyEditor(
        provider: APIKeyProvider,
        title: String,
        placeholder: String,
        text: Binding<String>,
        replacing: Bool
    ) -> some View {
        // PA2: no engineering status in this copy. Two of these sentences reported the state
        // of our own implementation ("known request-format issue", "isn't live-verified yet")
        // at the exact moment the user is pasting an org-wide admin key — one of them already
        // false — and neither named an action. Real failures are reported on the row that
        // fails ("Anthropic didn't accept the saved admin key"), where they can be acted on.
        let guidance: (text: String, linkLabel: String, url: URL) = switch provider {
        case .anthropic:
            (
                "A regular API key can’t read organization spend. Use a dedicated admin key you can revoke on its own.",
                "Open Anthropic Console",
                URL(string: "https://platform.claude.com/settings/admin-keys")!
            )
        case .openAI:
            (
                "A regular API key can’t read organization spend. Use a dedicated admin key with the narrowest access, so you can revoke it by itself.",
                "Open OpenAI Platform",
                URL(string: "https://platform.openai.com/settings/organization/admin-keys")!
            )
        case .xAI:
            (
                "A regular API key can’t read team spend. Use a dedicated management key with only the ACLs it needs, so you can revoke it on its own.",
                "Open xAI Console",
                URL(string: "https://console.x.ai/team/default/settings/management-keys")!
            )
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    apiKeyField(provider: provider, placeholder: placeholder, text: text)
                    apiKeyEditorButtons(provider: provider, replacing: replacing, text: text)
                }

                VStack(alignment: .leading, spacing: 8) {
                    apiKeyField(provider: provider, placeholder: placeholder, text: text)
                    apiKeyEditorButtons(provider: provider, replacing: replacing, text: text)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                SettingsHelpText(text: guidance.text)
                Link(guidance.linkLabel, destination: guidance.url)
                    .font(.system(size: 11))
            }
        }
    }

    private func apiKeyField(provider: APIKeyProvider, placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 160)
            .onChange(of: text.wrappedValue) {
                credentialMessages[provider] = nil
                cancelMessageDismissal(provider)
            }
            // R13: Return commits the key, matching the Save button's own guard, so a
            // pasted key doesn't need a mouse trip.
            .onSubmit {
                guard Self.hasSavableKey(text.wrappedValue) else { return }
                onSaveKey(text.wrappedValue, provider)
            }
    }

    /// One rule for "there is a key to save", shared by Return and the Save button.
    private static func hasSavableKey(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The editor is used for both first save and intentional replacement. Removal
    /// stays in the configured summary so a replacement never presents three competing
    /// actions beside a secure field.
    private func apiKeyEditorButtons(
        provider: APIKeyProvider,
        replacing: Bool,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 8) {
            Button(replacing ? "Update" : "Save") {
                onSaveKey(text.wrappedValue, provider)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!Self.hasSavableKey(text.wrappedValue))

            if replacing {
                Button("Cancel") {
                    clearField(for: provider)
                    credentialMessages[provider] = nil
                    cancelMessageDismissal(provider)
                    replacingKeyProviders.remove(provider)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
    }
}

extension APIKeyProvider {
    var adminKeyTitle: String {
        switch self {
        case .anthropic: return "Anthropic admin key"
        case .openAI: return "OpenAI admin key"
        case .xAI: return "xAI management key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-admin…"
        case .openAI: return "sk-…"
        case .xAI: return "xai-…"
        }
    }
}
