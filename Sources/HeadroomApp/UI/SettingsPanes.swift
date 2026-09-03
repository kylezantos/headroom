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
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 20)
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
    let softwareUpdates: SoftwareUpdateControlling
    let onIntervalChange: (Int) -> Void
    let onLaunchAtLoginChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneScaffold(SettingsPane.general.label) {
            SettingsTile {
                VStack(alignment: .leading, spacing: 4) {
                    ResponsiveControlRow(label: "Refresh every") {
                        Stepper(value: $intervalMinutes, in: 2...60) {
                            Text("\(intervalMinutes) min")
                                // Tabular digits so 5 → 10 doesn't reflow the row.
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(intervalMinutes)))
                        }
                        .animation(reduceMotion ? nil : HeadroomMotion.press, value: intervalMinutes)
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
                // Hidden — not permanently dimmed — when no updater is configured
                // (debug/CLI builds lack the Sparkle Info.plist keys). A button that can
                // never be pressed reads as broken. (R3: the removed footer's action.)
                if softwareUpdates.canCheckForUpdates {
                    ResponsiveControlRow(label: "Software updates") {
                        Button("Check for Updates…") {
                            softwareUpdates.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
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
    @Binding var showCodexSparkCountersInApp: Bool
    let onAppearanceChange: (AppearancePreference) -> Void
    let onMeterStyleChange: (MeterStyle) -> Void

    var body: some View {
        SettingsPaneScaffold(SettingsPane.appearance.label) {
            // R6: sits on the pane background above the tiles, not inside one — it is
            // the subject of the pane, not another setting.
            AppearanceSpecimen(
                meterStyle: meterStyle,
                percentageMode: usagePercentageMode
            )

            SettingsTile("Theme") {
                ThemeThumbnailPicker(selection: $appearancePreference)
                    .onChange(of: appearancePreference) { _, newValue in
                        onAppearanceChange(newValue)
                    }
            }

            // KTD13: the real-meter swatches need the tile's full width so they can
            // wrap. Only Format keeps the shared picker cap.
            MeterStyleTile(
                meterStyle: meterStyle,
                formatPickerMaxWidth: SettingsMetrics.segmentedMaxWidth
            ) { newStyle in
                meterStyle = newStyle
                onMeterStyleChange(newStyle)
            }

            // R8: the two display preferences that used to hide inside "Subscription
            // Usage", beside the switches that decide whether a provider is polled at
            // all. They change how numbers read, not what is fetched.
            SettingsTile("In-app display") {
                VStack(alignment: .leading, spacing: 4) {
                    ResponsiveControlRow(label: "Percentages") {
                        Picker("Percentages", selection: $usagePercentageMode) {
                            ForEach(UsagePercentageMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: SettingsMetrics.segmentedMaxWidth)
                        .onChange(of: usagePercentageMode) { _, newValue in
                            store.setUsagePercentageMode(newValue)
                        }
                    }
                    SettingsHelpText(text: "Changes the numbers, words, and meter direction in the app and menu bar.")
                }
                Toggle("Show Codex Spark counters in app", isOn: $showCodexSparkCountersInApp)
                    .onChange(of: showCodexSparkCountersInApp) { _, newValue in
                        store.setShowCodexSparkCountersInApp(newValue)
                    }
            }
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
                        MenuBarLabel(meters: store.menuBarMeters, showsPercentage: true)
                            .hidden()
                        // `.id` swap: the outgoing and incoming pills overlap leading-
                        // aligned and dissolve, instead of the NSImage hard-cutting.
                        MenuBarLabel(meters: store.menuBarMeters, showsPercentage: store.showMenuBarPercentage)
                            .id(menuBarPreviewKey)
                            .transition(.opacity)
                    }
                    .animation(reduceMotion ? nil : HeadroomMotion.settle, value: menuBarPreviewKey)
                    // The label is pinned to its dark palette (white ink + dark severity
                    // colors), representative of the Tahoe menu bar's dark translucent backplate.
                    // A light preview well would render that white ink invisibly, so the specimen
                    // sits on its own dark plate — a faithful preview of what the menu bar shows.
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Color(white: 0.15),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    Text("Live preview — follows the choices below")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    ClaudeSetupStyle.wellBackground(dark: colorScheme == .dark),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

                SettingsSwitchRow(title: "Show percentage", isOn: $showMenuBarPercentage)
                    .onChange(of: showMenuBarPercentage) { _, newValue in
                        store.setShowMenuBarPercentage(newValue)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    ResponsiveControlRow(label: "Priority providers") {
                        menuBarProviderSelectionMenu
                    }
                    SettingsHelpText(text: "Controls the menu-bar number and widget tiles. Auto uses the tightest menu-bar limit; widgets use the first 2 enabled providers.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferred window")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(store.registeredProviderOrder, id: \.self) { providerID in
                        if store.hasSelectableMenuBarWindows(for: providerID) {
                            menuBarWindowRow(
                                providerID: providerID,
                                selection: menuBarWindowBinding(for: providerID)
                            )
                        }
                    }

                    SettingsHelpText(text: "Each provider's percentage, fill, and color follow its preferred window.")
                }
            }
        }
    }

    /// Keys the preview pill's cross-fade to the preference changes that re-render it
    /// (live data ticks don't need choreography). The specimen's palette is pinned dark to
    /// match the real menu bar, so it no longer depends on `colorScheme`.
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
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    providerWindowLabel(providerID)
                    Spacer(minLength: 12)
                    menuBarWindowPicker(providerID: providerID, selection: selection)
                }

                VStack(alignment: .leading, spacing: 6) {
                    providerWindowLabel(providerID)
                    menuBarWindowPicker(providerID: providerID, selection: selection)
                }
            }

            if let fallback = menuBarWindowFallbackText(for: providerID) {
                SettingsHelpText(text: fallback)
            }
        }
    }

    private func providerWindowLabel(_ providerID: ProviderID) -> some View {
        ZStack(alignment: .leading) {
            ForEach(store.registeredProviderOrder, id: \.self) { id in
                providerWindowLabelContent(id).hidden()
            }
            providerWindowLabelContent(providerID)
        }
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
        .frame(maxWidth: SettingsMetrics.segmentedMaxWidth)
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

    var body: some View {
        SettingsPaneScaffold(SettingsPane.widgets.label) {
            SettingsTile {
                WidgetSettingsSection(
                    widgetsEnabled: $widgetsEnabled,
                    showCodexSparkCountersInWidgets: $showCodexSparkCountersInWidgets,
                    syncToIPhoneEnabled: $syncToIPhoneEnabled
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
                surfaceBinding: surfaceBinding,
                showsTitle: false
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
                // Period trails the provider rows it modifies (it used to lead them).
                ResponsiveControlRow(label: "Period") {
                    Picker("Period", selection: $apiSpendPeriod) {
                        ForEach(APISpendPeriod.allCases, id: \.self) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: SettingsMetrics.segmentedMaxWidth)
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
            if store.isSurfaceEnabled(surface) {
                if saved && !replacing {
                    configuredAPIKeyRow(provider: provider, title: title)
                        .transition(.settingsReveal)
                } else {
                    apiKeyEditor(
                        provider: provider,
                        title: title,
                        placeholder: placeholder,
                        text: text,
                        replacing: replacing
                    )
                    .transition(.settingsReveal)
                }
            }
            if let message = credentialMessages[provider] {
                // Result feedback lives on the acted-on row (the old shared line
                // rendered far away, under the other provider's rows).
                SettingsHelpText(text: message)
                    .transition(.settingsReveal)
            }
        }
        .animation(reduceMotion ? nil : HeadroomMotion.settle, value: savedKeyProviders)
        .animation(reduceMotion ? nil : HeadroomMotion.settle, value: replacingKeyProviders)
        .animation(reduceMotion ? nil : HeadroomMotion.settle, value: credentialMessages)
    }

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
                Button("Replace key…") {
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
        let guidance: (text: String, linkLabel: String, url: URL) = switch provider {
        case .anthropic:
            (
                "A regular API key cannot read organization spend. Use a dedicated admin key so you can revoke it independently. Spend retrieval currently has a known request-format issue.",
                "Open Anthropic Console",
                URL(string: "https://platform.claude.com/settings/admin-keys")!
            )
        case .openAI:
            (
                "A regular API key cannot read organization spend. Use a dedicated admin key with the narrowest access available so you can revoke it independently. Spend retrieval has not been live-verified.",
                "Open OpenAI Platform",
                URL(string: "https://platform.openai.com/settings/organization/admin-keys")!
            )
        case .xAI:
            (
                "A regular API key cannot read team spend. Use a dedicated management key with only the required ACLs so you can revoke it independently.",
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
                let trimmed = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSaveKey(text.wrappedValue, provider)
            }
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
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
