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
                    // Non-breaking spaces keep "2 min." from orphaning onto its own line.
                    SettingsHelpText(text: "Each Claude refresh runs a CLI session (~20–30s). Minimum\u{00A0}2\u{00A0}min.")
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

struct MenuBarSettingsPane: View {
    let store: UsageStore
    @Binding var showMenuBarPercentage: Bool
    @Binding var menuBarFillSource: MenuBarFillSource
    @Binding var menuBarWindowSources: [ProviderID: MenuBarWindowSource]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsPaneScaffold(SettingsPane.menuBar.label) {
            SettingsTile {
                // Live specimen of the real menu-bar label (same renderer, same store
                // meters), re-rendering as the choices below change — the user sees what
                // "fill" and "limit window" mean instead of decoding prose.
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        // Invisible percentage-on twin reserves the slot at its widest
                        // state, so toggling the percentage never reflows the caption or
                        // changes the strip height — the swap happens inside a fixed box.
                        MenuBarLabel(
                            meters: store.menuBarMeters,
                            showsPercentage: true,
                            appearance: .menuBar
                        )
                        .hidden()
                        // `.id` swap: the outgoing and incoming pills overlap leading-
                        // aligned and dissolve, instead of the NSImage hard-cutting.
                        MenuBarLabel(
                            meters: store.menuBarMeters,
                            showsPercentage: store.showMenuBarPercentage,
                            appearance: .menuBar
                        )
                        .id(menuBarPreviewKey)
                        .transition(.opacity)
                    }
                    // R2M7/S2A: the swap is a pure `.transition(.opacity)` between two
                    // overlapping pills, so it keeps its timing under Reduce Motion —
                    // `reduceMotion ? nil :` hard-cut the one thing S2A says must not.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                        value: menuBarPreviewKey
                    )
                    .menuBarPreviewPlate(darkMenuBar: MenuBarAppearanceMonitor.shared.isDarkMenuBar)
                    Text("Live preview — follows the choices below")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                // R2C9: r14 around the r6 menu-bar plate at 9/6pt of padding.
                .settingsPreviewWell(dark: colorScheme == .dark, verticalPadding: 6, cornerRadius: 14)

                SettingsSwitchRow(title: "Show percentage", isOn: $showMenuBarPercentage)
                    .onChange(of: showMenuBarPercentage) { _, newValue in
                        store.setShowMenuBarPercentage(newValue)
                    }

                VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                    ResponsiveControlRow(label: "Priority providers") {
                        menuBarProviderSelectionMenu
                    }
                    // PB8: this pane owns the widget rule; the Widgets pane points back here
                    // instead of restating it in different words ("first two enabled
                    // providers" vs "up to 2 of your priority providers" was one rule
                    // described twice, and the two descriptions disagreed).
                    SettingsHelpText(text: "Sets the menu-bar number and the first two widget tiles. Auto picks whichever provider is closest to its limit.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    // R2B2: a sub-group header that is smaller *and* lighter than the 13pt
                    // rows beneath it reads as a caption belonging to the row above, not as
                    // the head of what follows. Uppercase + tracking is the sidebar's own
                    // section idiom, so the level is carried by treatment instead of size.
                    Text("Preferred window")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.3)
                        .foregroundStyle(.secondary)

                    ForEach(store.registeredProviderOrder, id: \.self) { providerID in
                        if store.hasSelectableMenuBarWindows(for: providerID) {
                            menuBarWindowRow(
                                providerID: providerID,
                                selection: menuBarWindowBinding(for: providerID)
                            )
                        }
                    }

                    // PB7: "level", not "fill" — Fill is the Appearance pane's meter recipe,
                    // and this sentence means how full the vessel is drawn.
                    SettingsHelpText(text: "Each provider’s percentage, level, and color follow its preferred window.")
                }
            }
        }
    }

    /// Keys the preview pill's cross-fade to the preference changes that re-render it
    /// (live data ticks don't need choreography). PB13: the palette follows the live menu
    /// bar rather than `colorScheme` or a pinned dark, so an appearance flip repaints
    /// through observation instead of this key — it is not a choice the user just made.
    private var menuBarPreviewKey: String {
        let windows = store.registeredProviderOrder.map { id in
            "\(id.raw)=\(menuBarWindowSources[id, default: .weekly].rawValue)"
        }.joined(separator: ",")
        return "\(store.showMenuBarPercentage)-\(store.usagePercentageMode.rawValue)-\(store.menuBarFillSource.sortedIdentifier)-\(windows)"
    }

    private var menuBarProviderSelectionMenu: some View {
        Menu {
            Button {
                applyMenuBarFillSource(.auto)
            } label: {
                HStack {
                    Text("Auto")
                    if menuBarFillSource == .auto { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(store.registeredProviderOrder, id: \.self) { providerID in
                let selected = menuBarFillSource.providerIDs?.contains(providerID) == true
                Button {
                    toggleMenuBarProvider(providerID)
                } label: {
                    HStack {
                        Text(store.displayNames[providerID] ?? providerID.raw.capitalized)
                        if selected { Image(systemName: "checkmark") }
                    }
                }
                // A provider whose subscription switch is off is never fetched, so it can
                // never supply the menu-bar number. Listed but greyed (not removed) so the
                // menu keeps registry order and the absence reads as a state, not a bug.
                .disabled(!isProviderFetched(providerID))
            }
        } label: {
            Text(menuBarSelectionLabel)
        }
        .fixedSize()
    }

    private var menuBarSelectionLabel: String {
        guard let selected = menuBarFillSource.providerIDs else { return "Auto" }
        let names = store.registeredProviderOrder.filter { selected.contains($0) }.map {
            store.displayNames[$0] ?? $0.raw.capitalized
        }
        return names.isEmpty ? "Auto" : names.joined(separator: " + ")
    }

    private func toggleMenuBarProvider(_ providerID: ProviderID) {
        var selected = menuBarFillSource.providerIDs ?? []
        if selected.contains(providerID) {
            selected.remove(providerID)
        } else {
            selected.insert(providerID)
        }
        applyMenuBarFillSource(selected.isEmpty ? .auto : .providers(selected))
    }

    private func applyMenuBarFillSource(_ source: MenuBarFillSource) {
        menuBarFillSource = source
        store.setMenuBarFillSource(source)
    }

    /// Whether Headroom actually polls this provider. `providerOrder` is
    /// `registeredProviderOrder` filtered by the user's subscription switches, so this
    /// reads the same `enabledSurfaces` truth the rest of the app does — no second
    /// on/off source lives in the Menu Bar pane.
    private func isProviderFetched(_ providerID: ProviderID) -> Bool {
        store.providerOrder.contains(providerID)
    }

    private func menuBarWindowBinding(for providerID: ProviderID) -> Binding<MenuBarWindowSource> {
        Binding(
            get: { menuBarWindowSources[providerID] ?? store.menuBarWindowSource(for: providerID) },
            set: { menuBarWindowSources[providerID] = $0 }
        )
    }

    /// Provider identity is the row label, so the two choices scan as one compact
    /// matrix without introducing nested provider cards inside the Menu Bar tile.
    private func menuBarWindowRow(
        providerID: ProviderID,
        selection: Binding<MenuBarWindowSource>
    ) -> some View {
        // R11's rule, applied here: "off" means "not fetched". The row stays in registry
        // order and keeps its stored choice — dimmed with an Off tag, control disabled —
        // so turning the provider back on restores the row in place instead of
        // reflowing the list.
        let isFetched = isProviderFetched(providerID)

        return VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    providerWindowLabel(providerID, isFetched: isFetched)
                    Spacer(minLength: 12)
                    menuBarWindowPicker(providerID: providerID, selection: selection)
                        .disabled(!isFetched)
                }

                VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
                    providerWindowLabel(providerID, isFetched: isFetched)
                    menuBarWindowPicker(providerID: providerID, selection: selection)
                        .disabled(!isFetched)
                }
            }

            // The fallback line describes live data ("using 5-hour while weekly is
            // unavailable"), which says nothing about a provider that isn't polled.
            if isFetched, let fallback = menuBarWindowFallbackText(for: providerID) {
                SettingsHelpText(text: fallback)
            }
        }
    }

    private func providerWindowLabel(_ providerID: ProviderID, isFetched: Bool) -> some View {
        // The Off tag sits outside the width-reservation stack: reserving it would widen
        // every row's label slot the moment one provider is switched off. The picker is
        // pinned to `segmentedMaxWidth` by the trailing spacer, so the tag can't push it.
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                ForEach(store.registeredProviderOrder, id: \.self) { id in
                    providerWindowLabelContent(id).hidden()
                }
                providerWindowLabelContent(providerID)
            }
            if !isFetched {
                SettingsPillBadge(text: "Off")
                    // R2B1/PB9: one constant, shared with the Accounts help line, so the two
                    // statements of this rule cannot drift (they disagreed on the full stop).
                    .help(SettingsCopy.providerOffNotice)
                    .accessibilityLabel(SettingsCopy.providerOffAccessibilityLabel)
            }
        }
        // Matches the dimmed-row step Accounts uses for the same "off" state.
        .opacity(isFetched ? 1 : 0.45)
    }

    /// Every row reserves the widest registered provider label so flexible picker slots
    /// receive identical proposals at compact window widths.
    private func providerWindowLabelContent(_ providerID: ProviderID) -> some View {
        HStack(spacing: 7) {
            ProviderLogoView(providerID: providerID, size: 15)
            Text(store.displayNames[providerID] ?? providerID.raw.capitalized)
        }
    }

    private func menuBarWindowPicker(
        providerID: ProviderID,
        selection: Binding<MenuBarWindowSource>
    ) -> some View {
        let name = store.displayNames[providerID] ?? providerID.raw.capitalized
        return Picker("\(name) preferred window", selection: selection) {
            ForEach(MenuBarWindowSource.allCases, id: \.self) { source in
                Text(source.label).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // PB3: `width`, not `maxWidth`, so the slot is one declared size instead of whatever
        // the labels happen to need. The trailing alignment is the other half of the fix and
        // is load-bearing: an AppKit segmented control does *not* stretch to a proposal wider
        // than its intrinsic width, so "Weekly | 5-hour" (127pt) sat centred in the 220pt box
        // and still ended ~45pt short of the rail every other control in the tile lands on.
        // Measured in the harness render at 800 × 700. A longer set of labels (the API Spend
        // Period picker, 217pt) fills the box and is unaffected.
        .frame(width: SettingsMetrics.segmentedMaxWidth, alignment: .trailing)
        .onChange(of: selection.wrappedValue) { _, newValue in
            store.setMenuBarWindowSource(newValue, for: providerID)
        }
    }

    private func menuBarWindowFallbackText(for providerID: ProviderID) -> String? {
        let preferred = store.menuBarWindowSource(for: providerID)
        guard let resolved = store.resolvedMenuBarWindowSource(for: providerID),
              resolved != preferred
        else { return nil }
        return "Using \(resolved.label.lowercased()) while \(preferred.label.lowercased()) data is unavailable."
    }
}

// MARK: - Widgets & iPhone

struct WidgetsSettingsPane: View {
    let store: UsageStore
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool
    /// PB8: the widget rule lives in Menu Bar, so the help line there links to it. The root
    /// owns the sidebar selection (KTD3) and persists it through `settingsPane`, so this
    /// pane asks rather than navigating itself.
    let onShowMenuBarPane: () -> Void

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
                    onShowMenuBarPane: onShowMenuBarPane
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
