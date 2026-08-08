import AppKit
import SwiftUI
import Accessibility
import HeadroomCore

/// Settings pane (U8): poll interval, appearance, surfaces, API keys, and
/// launch-at-login (R15). Presented in its own window so dismissing settings never
/// closes the menu bar popover behind it.
///
/// Rebuilt in the popover's card language (settings-ui audit, Jul 2026): every section
/// is a raised tile at the shared 13pt-pad / 10pt-radius spec, one row grammar
/// (label leading, control trailing), and credential state made visible. The old
/// window mixed flat hairline zones with two elevated panels at two widths —
/// PRODUCT.md principle 5 treats that as an accidental status difference.
struct SettingsView: View {
    let store: UsageStore
    @Binding var appearancePreference: AppearancePreference
    var softwareUpdates: SoftwareUpdateControlling = DisabledSoftwareUpdateController()
    var preferences = Preferences()
    var credentialStore = CredentialStore()
    var launchControl: LaunchAtLoginControlling = LaunchAtLogin()
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var showMenuBarPercentage = false
    @State private var usagePercentageMode: UsagePercentageMode = .remaining
    @State private var menuBarFillSource: MenuBarFillSource = .auto
    @State private var menuBarWindowSources: [ProviderID: MenuBarWindowSource] = [:]
    @State private var widgetsEnabled = true
    @State private var showCodexSparkCountersInApp = true
    @State private var showCodexSparkCountersInWidgets = false
    @State private var syncToIPhoneEnabled = false
    @State private var launchAtLogin = false
    @State private var apiSpendPeriod: APISpendPeriod = .currentMonth
    @State private var apiKeyDrafts: [APIKeyProvider: String] = [:]
    @State private var savedKeyProviders: Set<APIKeyProvider> = []
    @State private var replacingKeyProviders: Set<APIKeyProvider> = []
    @State private var credentialMessages: [APIKeyProvider: String] = [:]
    @State private var messageDismissals: [APIKeyProvider: Task<Void, Never>] = [:]
    @State private var removalCandidate: APIKeyProvider?

    /// Fast, no-bounce settle shared by the credential-row reveals and result messages.
    /// The interaction is occasional settings work, so it gets just enough motion to
    /// confirm the state change.
    private static let settleAnimation = HeadroomMotion.settle

    /// One trailing-control width for every segmented picker (Theme / provider window /
    /// Period). The old window ran three widths (280 / 200 / unconstrained), so the
    /// eye re-learned the layout per row.
    private static let segmentedMaxWidth: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                settingsContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    // Extra top inset clears the traffic lights that float over content when
                    // the window uses a hidden title bar (set on the Window scene).
                    .padding(.top, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)

            // Symmetric at the footer's own 20pt inset — the old inset hairline ran
            // 6/2 asymmetric and landed 4pt off the footer buttons' trailing edge.
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.42))
                .frame(height: 1)
                .padding(.horizontal, 20)

            footer
        }
        .frame(minWidth: 360, idealWidth: 460, maxWidth: 620, minHeight: 420, idealHeight: 700, maxHeight: .infinity)
        .onAppear { loadPreferences() }
        .task { await refreshSavedKeyPresence() }
        .confirmationDialog(
            "Remove this admin key?",
            isPresented: removalDialogPresented,
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { provider in
            Button("Remove \(provider.displayName) Key", role: .destructive) {
                deleteKey(for: provider)
            }
            Button("Cancel", role: .cancel) {}
        } message: { provider in
            Text("Headroom will stop fetching \(provider.displayName) spend until a new key is added.")
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            generalTile
            appearanceTile
            menuBarTile
            widgetsTile
            subscriptionTile
            AccountsSettingsTile(store: store)
            apiSpendTile
        }
    }

    // MARK: - Header

    /// Custom header (the window uses a hidden title bar): the vessel logo anchors
    /// the title, drawn just below the floating traffic lights. Rendered from the
    /// bundled SVG rather than NSApplication.shared.applicationIconImage — the latter
    /// is a single flattened OS-cached snapshot (not the asset catalog's real
    /// multi-resolution art) and rendered pixelated in this header.
    private var header: some View {
        HStack(spacing: 10) {
            if let image = AppIconGlyph.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // Neutral 1pt inset outline defines the icon edge on the window
                    // surface — pure black in light, pure white in dark, never tinted
                    // (UI craft: image outlines). `.strokeBorder` insets so it stays
                    // concentric with the clip and doesn't grow the icon.
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                (colorScheme == .dark ? Color.white : Color.black).opacity(0.10),
                                lineWidth: 1
                            )
                    )
            }
            Text("Headroom Settings")
                // One step above the popover's 20pt "Usage" (user-directed, Jul 2026):
                // a persistent window outranks the transient popover, and the larger
                // step keeps the title unmistakably senior to the 15pt tile headers.
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.2)
            Spacer(minLength: 10)
            if let version = Self.versionLabel {
                // Quiet stamp in the right slot — mirrors the popover header's
                // tertiary "Updated…" status position. Hidden under `swift run`
                // (no bundle Info.plist) rather than showing a placeholder.
                Text(version)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 2)
    }

    private static let versionLabel: String? = {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.isEmpty else { return nil }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return "v\(short) (\(build))"
        }
        return "v\(short)"
    }()

    // MARK: - Tiles

    private var generalTile: some View {
        settingsTile("General") {
            VStack(alignment: .leading, spacing: 4) {
                responsiveControlRow(label: "Refresh every") {
                    Stepper(value: $intervalMinutes, in: 2...60) {
                        Text("\(intervalMinutes) min")
                            // Tabular digits so 5 → 10 doesn't reflow the row.
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(intervalMinutes)))
                    }
                    .animation(reduceMotion ? nil : HeadroomMotion.press, value: intervalMinutes)
                    .onChange(of: intervalMinutes) { _, newValue in
                        preferences.pollIntervalMinutes = newValue
                        store.reschedulePolling()
                    }
                }
                // Non-breaking spaces keep "2 min." from orphaning onto its own line.
                SettingsHelpText(text: "Each Claude refresh runs a CLI session (~20–30s). Minimum\u{00A0}2\u{00A0}min.")
            }
            SettingsSwitchRow(title: "Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    try? launchControl.setEnabled(newValue)
                }
        }
    }

    private var appearanceTile: some View {
        settingsTile("Appearance") {
            responsiveControlRow(label: "Theme") {
                // Declared label matches the visible "Theme" — the old "Appearance"
                // label made VoiceOver announce a different name than the screen shows.
                Picker("Theme", selection: $appearancePreference) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: Self.segmentedMaxWidth)
                .onChange(of: appearancePreference) { _, newValue in
                    preferences.appearancePreference = newValue
                    // Repaint the AppKit windows (this Settings window + the popover panel);
                    // `preferredColorScheme` alone doesn't reach their chrome, and switching
                    // to System doesn't release the per-window appearance pin. (See HeadroomApp.)
                    newValue.applyToProcess()
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

    private var menuBarTile: some View {
        settingsTile("Menu Bar") {
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
                .animation(reduceMotion ? nil : Self.settleAnimation, value: menuBarPreviewKey)
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
                responsiveControlRow(label: "Priority providers") {
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

    private var widgetsTile: some View {
        settingsTile("Widgets") {
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

    private var subscriptionTile: some View {
        settingsTile("Subscription Usage") {
            VStack(alignment: .leading, spacing: 4) {
                responsiveControlRow(label: "Percentages") {
                    Picker("Percentages", selection: $usagePercentageMode) {
                        ForEach(UsagePercentageMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: Self.segmentedMaxWidth)
                    .onChange(of: usagePercentageMode) { _, newValue in
                        store.setUsagePercentageMode(newValue)
                    }
                }
                SettingsHelpText(text: "Changes the numbers, words, and meter direction in the app and menu bar.")
            }
            ForEach(store.registeredProviderOrder, id: \.self) { providerID in
                if let surface = UsageSurface.subscription(for: providerID) {
                    surfaceSwitchRow(surface)
                }
            }
            Toggle("Show Codex Spark counters in app", isOn: $showCodexSparkCountersInApp)
                .onChange(of: showCodexSparkCountersInApp) { _, newValue in
                    store.setShowCodexSparkCountersInApp(newValue)
                }
        }
    }

    private var apiSpendTile: some View {
        settingsTile("API Spend") {
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
            responsiveControlRow(label: "Period") {
                Picker("Period", selection: $apiSpendPeriod) {
                    ForEach(APISpendPeriod.allCases, id: \.self) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: Self.segmentedMaxWidth)
                .onChange(of: apiSpendPeriod) { _, newValue in
                    store.setAPISpendPeriod(newValue)
                    store.refreshAPISpendNow()
                }
            }
        }
    }

    // MARK: - Section building blocks

    /// One material for every section: the popover's card language — `RaisedTile` at
    /// 13pt padding / 10pt radius (matching `ProviderCardView`), full width so sibling
    /// tiles never render at two widths. Tile headers are 15pt semibold, kerned like
    /// the family: one step under the popover's 16pt card titles, two above the 13pt
    /// controls, so size separates the levels instead of weight alone.
    private func settingsTile<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.2)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10, surface: .opaque)
    }

    private func responsiveControlRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                Spacer(minLength: 12)
                content()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                content()
            }
        }
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
        .frame(maxWidth: Self.segmentedMaxWidth)
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

    /// Provider master row: brand mark + name (popover siblings), switch trailing.
    private func surfaceSwitchRow(_ surface: UsageSurface) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ProviderLogoView(providerID: surface.providerID, size: 15)
                Text(surface.displayName)
            }
            Spacer(minLength: 12)
            Toggle(surface.displayName, isOn: surfaceBinding(surface))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func surfaceBinding(_ surface: UsageSurface) -> Binding<Bool> {
        Binding(
            get: { store.isSurfaceEnabled(surface) },
            set: { newValue in
                // Animated so the key-entry reveal below an API row settles instead
                // of hard-cutting; `withAnimation(nil)` is a no-op under Reduce Motion.
                withAnimation(reduceMotion ? nil : Self.settleAnimation) {
                    store.setSurfaceEnabled(newValue, for: surface)
                }
                if surface.isSubscription {
                    store.refreshNow()
                } else {
                    store.refreshAPISpendNow()
                }
            }
        )
    }

    // MARK: - API spend rows

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
        .animation(reduceMotion ? nil : Self.settleAnimation, value: savedKeyProviders)
        .animation(reduceMotion ? nil : Self.settleAnimation, value: replacingKeyProviders)
        .animation(reduceMotion ? nil : Self.settleAnimation, value: credentialMessages)
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
                    messageDismissals[provider]?.cancel()
                    replacingKeyProviders.insert(provider)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Remove") { removalCandidate = provider }
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
                messageDismissals[provider]?.cancel()
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
                saveKey(text.wrappedValue, for: provider)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if replacing {
                Button("Cancel") {
                    clearField(for: provider)
                    credentialMessages[provider] = nil
                    messageDismissals[provider]?.cancel()
                    replacingKeyProviders.remove(provider)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: { if !$0 { removalCandidate = nil } }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            // Hidden — not permanently dimmed — when no updater is configured
            // (debug/CLI builds lack the Sparkle Info.plist keys). A button that can
            // never be pressed reads as broken.
            if softwareUpdates.canCheckForUpdates {
                Button("Check for Updates…") {
                    softwareUpdates.checkForUpdates()
                }
            }

            Spacer()

            Button("Done") { onDone?() ?? dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - State

    private func loadPreferences() {
        // Clamp any legacy sub-2-minute interval up to the new floor.
        let saved = max(2, preferences.pollIntervalMinutes)
        if saved != preferences.pollIntervalMinutes {
            preferences.pollIntervalMinutes = saved
            store.reschedulePolling()
        }
        intervalMinutes = saved
        appearancePreference = preferences.appearancePreference
        showMenuBarPercentage = store.showMenuBarPercentage
        usagePercentageMode = store.usagePercentageMode
        menuBarFillSource = store.menuBarFillSource
        menuBarWindowSources = Dictionary(uniqueKeysWithValues: store.registeredProviderOrder.map {
            ($0, store.menuBarWindowSource(for: $0))
        })
        widgetsEnabled = store.widgetsEnabled
        showCodexSparkCountersInApp = store.showCodexSparkCountersInApp
        showCodexSparkCountersInWidgets = store.showCodexSparkCountersInWidgets
        syncToIPhoneEnabled = store.syncToIPhoneEnabled
        apiSpendPeriod = store.apiSpendPeriod
        launchAtLogin = launchControl.isEnabled
    }

    /// Presence only (never the key material): selects the configured summary or the
    /// first-save editor, so the UI can show whether a credential exists at rest.
    private func refreshSavedKeyPresence() async {
        for provider in APIKeyProvider.allCases {
            if case .success = await credentialStore.apiKey(for: provider) {
                savedKeyProviders.insert(provider)
            } else {
                savedKeyProviders.remove(provider)
            }
        }
    }

    private func saveKey(_ key: String, for provider: APIKeyProvider) {
        Task {
            switch await credentialStore.saveAPIKey(key, for: provider) {
            case .success:
                // Clear only on success — a Keychain failure must not eat a pasted key.
                clearField(for: provider)
                savedKeyProviders.insert(provider)
                replacingKeyProviders.remove(provider)
                credentialMessages[provider] = nil
                messageDismissals[provider]?.cancel()
                AccessibilityNotification.Announcement("\(provider.displayName) API key saved").post()
                store.refreshAPISpendNow()
            case .failure(let reason):
                showCredentialMessage(reason.message, for: provider, autoDismiss: false)
            }
        }
    }

    private func deleteKey(for provider: APIKeyProvider) {
        Task {
            switch await credentialStore.deleteAPIKey(for: provider) {
            case .success:
                clearField(for: provider)
                savedKeyProviders.remove(provider)
                replacingKeyProviders.remove(provider)
                showCredentialMessage("\(provider.displayName) API key removed", for: provider, autoDismiss: true)
                store.refreshAPISpendNow()
            case .failure(let reason):
                showCredentialMessage(reason.message, for: provider, autoDismiss: false)
            }
        }
    }

    private func clearField(for provider: APIKeyProvider) {
        apiKeyDrafts[provider] = ""
    }

    /// Success feedback auto-dismisses on the popover's Connected-chip cadence (4s).
    /// Failures stay until the next edit or retry so a Keychain problem is not hidden.
    private func showCredentialMessage(_ message: String, for provider: APIKeyProvider, autoDismiss: Bool) {
        credentialMessages[provider] = message
        AccessibilityNotification.Announcement(message).post()
        messageDismissals[provider]?.cancel()
        guard autoDismiss else { return }
        messageDismissals[provider] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            credentialMessages[provider] = nil
        }
    }
}

private extension APIKeyProvider {
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

private struct SettingsRevealTransitionModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .offset(y: active ? 4 : 0)
            .blur(radius: active ? 1.5 : 0)
    }
}

private extension AnyTransition {
    /// Enter with the settle vocabulary (opacity + 4pt rise + slight blur), exit
    /// opacity-only — exits softer than enters.
    static var settingsReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettingsRevealTransitionModifier(active: true),
                identity: SettingsRevealTransitionModifier(active: false)
            ),
            removal: .opacity
        )
    }
}

/// Loads the vessel mark straight from its bundled SVG (mirrors `ProviderLogoView`'s
/// `BrandIconImage` lookup) so the Settings header always renders crisp, resolution-
/// independent art instead of depending on the OS's cached app-icon snapshot.
private enum AppIconGlyph {
    static let image: NSImage? = {
        guard let url = url(forResource: "vessel-app-icon") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private static func url(forResource name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            return url
        }
        let swiftPMBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Headroom_HeadroomApp.bundle")
        return Bundle(url: swiftPMBundleURL)?
            .url(forResource: name, withExtension: "svg")
    }
}

// (RenewalDateField removed — plan-renewal dates were cut from all UI in the
// Jul 2026 density audit; `Preferences.renewalDate` remains for stored data.)
