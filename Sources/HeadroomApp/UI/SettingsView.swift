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
    @State private var menuBarFillSource: MenuBarFillSource = .none
    @State private var menuBarWindowSource: MenuBarWindowSource = .weekly
    @State private var widgetsEnabled = true
    @State private var showCodexSparkCountersInApp = true
    @State private var showCodexSparkCountersInWidgets = false
    @State private var syncToIPhoneEnabled = false
    @State private var launchAtLogin = false
    @State private var apiSpendPeriod: APISpendPeriod = .currentMonth
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var savedKeyProviders: Set<APIKeyProvider> = []
    @State private var credentialMessages: [APIKeyProvider: String] = [:]
    @State private var messageDismissals: [APIKeyProvider: Task<Void, Never>] = [:]
    @State private var removalCandidate: APIKeyProvider?

    /// Fast, no-bounce settle shared by the credential-row reveals and result messages.
    /// The interaction is occasional settings work, so it gets just enough motion to
    /// confirm the state change.
    private static let settleAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)

    /// One trailing-control width for every segmented picker (Theme / Limit window /
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
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: intervalMinutes)
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
                }
            }
        }
    }

    /// Keys the preview pill's cross-fade to the preference changes that re-render it
    /// (live data ticks don't need choreography).
    private var menuBarPreviewKey: String {
        "\(store.showMenuBarPercentage)-\(store.menuBarFillSource.rawValue)-\(store.menuBarWindowSource.rawValue)"
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
                Text("Live preview — follows the choices below")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                ClaudeSetupStyle.codeBackground(dark: colorScheme == .dark),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )

            SettingsSwitchRow(title: "Show percentage", isOn: $showMenuBarPercentage)
                .onChange(of: showMenuBarPercentage) { _, newValue in
                    store.setShowMenuBarPercentage(newValue)
                }

            VStack(alignment: .leading, spacing: 4) {
                responsiveControlRow(label: "Limit window") {
                    Picker("Limit window", selection: $menuBarWindowSource) {
                        ForEach(MenuBarWindowSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: Self.segmentedMaxWidth)
                    .onChange(of: menuBarWindowSource) { _, newValue in
                        store.setMenuBarWindowSource(newValue)
                    }
                }
                SettingsHelpText(text: "Percentage, fill, and color follow this window.")
            }

            VStack(alignment: .leading, spacing: 4) {
                responsiveControlRow(label: "Fill tracks") {
                    Picker("Fill tracks", selection: $menuBarFillSource) {
                        ForEach(MenuBarFillSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: menuBarFillSource) { _, newValue in
                        store.setMenuBarFillSource(newValue)
                    }
                }
                SettingsHelpText(text: "The vessel empties as this window is used. Both shows Claude and Codex side by side.")
            }
        }
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
            surfaceSwitchRow(.claudeSubscription)
            surfaceSwitchRow(.codexSubscription)
            Toggle("Show Codex Spark counters in app", isOn: $showCodexSparkCountersInApp)
                .onChange(of: showCodexSparkCountersInApp) { _, newValue in
                    store.setShowCodexSparkCountersInApp(newValue)
                }
        }
    }

    private var apiSpendTile: some View {
        settingsTile("API Spend") {
            apiProviderRows(
                surface: .anthropicAPI,
                provider: .anthropic,
                title: "Anthropic admin key",
                placeholder: "sk-ant-admin…",
                text: $anthropicKey
            )
            apiProviderRows(
                surface: .openAIAPI,
                provider: .openAI,
                title: "OpenAI admin key",
                placeholder: "sk-…",
                text: $openAIKey
            )
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

    /// Master row (mark + name + saved-state chip + switch), then — only while the
    /// surface is on — the key entry. Off means absent, not dimmed: the old treatment
    /// kept sub-floor-contrast text and a dead credential field on screen at 0.4
    /// opacity for a feature that was off.
    @ViewBuilder private func apiProviderRows(
        surface: UsageSurface,
        provider: APIKeyProvider,
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: surface.providerID, size: 15)
                    Text(surface.displayName)
                }
                Spacer(minLength: 12)
                if savedKeyProviders.contains(provider) {
                    KeySavedChip()
                        .transition(.opacity)
                }
                Toggle(surface.displayName, isOn: surfaceBinding(surface))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            if store.isSurfaceEnabled(surface) {
                apiKeyRow(provider: provider, title: title, placeholder: placeholder, text: text)
                    .transition(.settingsReveal)
            }
            if let message = credentialMessages[provider] {
                // Result feedback lives on the acted-on row (the old shared line
                // rendered far away, under the other provider's rows).
                SettingsHelpText(text: message)
                    .transition(.settingsReveal)
            }
        }
        .animation(reduceMotion ? nil : Self.settleAnimation, value: savedKeyProviders)
        .animation(reduceMotion ? nil : Self.settleAnimation, value: credentialMessages)
    }

    private func apiKeyRow(
        provider: APIKeyProvider,
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        let saved = savedKeyProviders.contains(provider)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    apiKeyField(placeholder: placeholder, text: text)
                    apiKeyButtons(provider: provider, saved: saved, text: text)
                }

                VStack(alignment: .leading, spacing: 8) {
                    apiKeyField(placeholder: placeholder, text: text)
                    apiKeyButtons(provider: provider, saved: saved, text: text)
                }
            }
        }
    }

    private func apiKeyField(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 160)
    }

    /// Native bordered commit action — one button vocabulary with the footer,
    /// replacing the hover-only bare-text chips (whose extended hit areas also
    /// overlapped at the old 8pt spacing). Save is disabled on an empty field;
    /// Remove exists only when there is a key to remove, behind a confirmation.
    private func apiKeyButtons(provider: APIKeyProvider, saved: Bool, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Button(saved ? "Update" : "Save") {
                saveKey(text.wrappedValue, for: provider)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if saved {
                Button("Remove") { removalCandidate = provider }
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
        menuBarFillSource = store.menuBarFillSource
        menuBarWindowSource = store.menuBarWindowSource
        widgetsEnabled = store.widgetsEnabled
        showCodexSparkCountersInApp = store.showCodexSparkCountersInApp
        showCodexSparkCountersInWidgets = store.showCodexSparkCountersInWidgets
        syncToIPhoneEnabled = store.syncToIPhoneEnabled
        apiSpendPeriod = store.apiSpendPeriod
        launchAtLogin = launchControl.isEnabled
    }

    /// Presence only (never the key material): drives the "Key saved" chip and the
    /// Save/Update/Remove states, so a credentials UI can finally show whether a
    /// credential exists.
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
                showCredentialMessage("\(provider.displayName) API key saved", for: provider)
                store.refreshAPISpendNow()
            case .failure(let reason):
                showCredentialMessage(reason.message, for: provider)
            }
        }
    }

    private func deleteKey(for provider: APIKeyProvider) {
        Task {
            switch await credentialStore.deleteAPIKey(for: provider) {
            case .success:
                clearField(for: provider)
                savedKeyProviders.remove(provider)
                showCredentialMessage("\(provider.displayName) API key removed", for: provider)
                store.refreshAPISpendNow()
            case .failure(let reason):
                showCredentialMessage(reason.message, for: provider)
            }
        }
    }

    private func clearField(for provider: APIKeyProvider) {
        switch provider {
        case .anthropic: anthropicKey = ""
        case .openAI: openAIKey = ""
        }
    }

    /// Result feedback auto-dismisses on the popover's Connected-chip cadence (4s)
    /// and is spoken to VoiceOver — the old shared message line never cleared and
    /// was silent to assistive tech.
    private func showCredentialMessage(_ message: String, for provider: APIKeyProvider) {
        credentialMessages[provider] = message
        AccessibilityNotification.Announcement(message).post()
        messageDismissals[provider]?.cancel()
        messageDismissals[provider] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            credentialMessages[provider] = nil
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
