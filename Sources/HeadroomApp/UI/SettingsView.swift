import AppKit
import SwiftUI
import HeadroomCore

/// Settings pane (U8): poll interval, per-provider renewal dates (R4), and
/// launch-at-login (R15). Presented in its own window so dismissing settings never
/// closes the menu bar popover behind it.
struct SettingsView: View {
    let store: UsageStore
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
    @State private var widgetsEnabled = true
    @State private var showCodexSparkCountersInApp = true
    @State private var showCodexSparkCountersInWidgets = false
    @State private var syncToIPhoneEnabled = false
    @State private var launchAtLogin = false
    @State private var renewalDates: [ProviderID: Date] = [:]
    @State private var apiSpendPeriod: APISpendPeriod = .currentMonth
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var credentialMessage: String?

    /// Fast, no-bounce settle for the API spend period swap. The interaction is occasional
    /// settings work, so it gets just enough motion to confirm the segment changed.
    private static let apiSpendPeriodAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Custom header (the window uses a hidden title bar): the vessel logo anchors
            // the title, drawn just below the floating traffic lights. Rendered from the
            // bundled SVG rather than NSApplication.shared.applicationIconImage — the latter
            // is a single flattened OS-cached snapshot (not the asset catalog's real
            // multi-resolution art) and rendered pixelated in this header.
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
                    .font(.title2.weight(.semibold))
            }
            .padding(.bottom, 2)

            // The top preferences used to float with no headers while lower sections had
            // them. Every zone now leads with a section header so the whole window follows
            // one pattern (labels shortened where the header already carries the context).
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("General")
                VStack(alignment: .leading, spacing: 2) {
                    Stepper("Refresh every \(intervalMinutes) min", value: $intervalMinutes, in: 2...60)
                        .onChange(of: intervalMinutes) { _, newValue in
                            preferences.pollIntervalMinutes = newValue
                            store.reschedulePolling()
                        }
                    helpText("Each Claude refresh runs a CLI session (~20–30s). Minimum 2 min.")
                }
            }

            insetHairline()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Menu Bar")
                Toggle("Show percentage", isOn: $showMenuBarPercentage)
                    .onChange(of: showMenuBarPercentage) { _, newValue in
                        store.setShowMenuBarPercentage(newValue)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Picker("Fill tracks", selection: $menuBarFillSource) {
                        ForEach(MenuBarFillSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .onChange(of: menuBarFillSource) { _, newValue in
                        store.setMenuBarFillSource(newValue)
                    }
                    helpText("Drains with weekly usage; Both shows Claude and Codex side by side.")
                }
            }

            insetHairline()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Widgets")
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

            insetHairline()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Subscription Usage")
                surfaceToggle(.claudeSubscription)
                surfaceToggle(.codexSubscription)
                Toggle("Show Codex Spark counters in app", isOn: $showCodexSparkCountersInApp)
                    .onChange(of: showCodexSparkCountersInApp) { _, newValue in
                        store.setShowCodexSparkCountersInApp(newValue)
                    }
            }
            .settingsPanel()

            insetHairline()

            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("API Spend")
                Picker("Period", selection: $apiSpendPeriod) {
                    ForEach(APISpendPeriod.allCases, id: \.self) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: apiSpendPeriod) { _, newValue in
                    store.setAPISpendPeriod(newValue)
                    store.refreshAPISpendNow()
                }

                ZStack(alignment: .topLeading) {
                    apiSpendControls
                        .id(apiSpendPeriod)
                        .transition(.apiSpendPeriodSwap)
                }
                .animation(reduceMotion ? nil : Self.apiSpendPeriodAnimation, value: apiSpendPeriod)

                if let credentialMessage {
                    Text(credentialMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .settingsPanel()

            insetHairline()

            // Grid so both date fields share a left edge despite the labels
            // ("Claude renews" / "Codex renews") being different widths.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach([ProviderID.claude, .codex], id: \.self) { id in
                    GridRow {
                        Text("\(store.displayNames[id] ?? id.raw) renews")
                            .gridColumnAlignment(.leading)
                        RenewalDateField(date: Binding(
                            get: { renewalDates[id] ?? Date() },
                            set: { renewalDates[id] = $0; preferences.setRenewalDate($0, for: id) }
                        ))
                    }
                }
            }

            insetHairline()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    try? launchControl.setEnabled(newValue)
                }

            Button("Check for Updates…") {
                softwareUpdates.checkForUpdates()
            }
            .disabled(!softwareUpdates.canCheckForUpdates)

            HStack {
                Spacer()
                Button("Done") { onDone?() ?? dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        // Extra top inset clears the traffic lights that float over content when the window
        // uses a hidden title bar (set on the Window scene in `HeadroomApp`).
        .padding(.top, 30)
        .frame(width: 380)
        .onAppear {
            // Clamp any legacy sub-2-minute interval up to the new floor.
            let saved = max(2, preferences.pollIntervalMinutes)
            if saved != preferences.pollIntervalMinutes {
                preferences.pollIntervalMinutes = saved
                store.reschedulePolling()
            }
            intervalMinutes = saved
            showMenuBarPercentage = store.showMenuBarPercentage
            menuBarFillSource = store.menuBarFillSource
            widgetsEnabled = store.widgetsEnabled
            showCodexSparkCountersInApp = store.showCodexSparkCountersInApp
            showCodexSparkCountersInWidgets = store.showCodexSparkCountersInWidgets
            syncToIPhoneEnabled = store.syncToIPhoneEnabled
            apiSpendPeriod = store.apiSpendPeriod
            launchAtLogin = launchControl.isEnabled
            for id in [ProviderID.claude, .codex] {
                if let date = preferences.renewalDate(for: id) { renewalDates[id] = date }
            }
        }
    }

    @ViewBuilder private var apiSpendControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            surfaceToggle(.anthropicAPI)
            apiKeyRow(
                title: "Anthropic admin key",
                placeholder: "sk-ant-admin…",
                text: $anthropicKey,
                provider: .anthropic,
                enabled: store.isSurfaceEnabled(.anthropicAPI)
            )

            surfaceToggle(.openAIAPI)
            apiKeyRow(
                title: "OpenAI admin key",
                placeholder: "sk-…",
                text: $openAIKey,
                provider: .openAI,
                enabled: store.isSurfaceEnabled(.openAIAPI)
            )
        }
    }

    private func surfaceToggle(_ surface: UsageSurface) -> some View {
        Toggle(surface.displayName, isOn: Binding(
            get: { store.isSurfaceEnabled(surface) },
            set: { newValue in
                store.setSurfaceEnabled(newValue, for: surface)
                if surface.isSubscription {
                    store.refreshNow()
                } else {
                    store.refreshAPISpendNow()
                }
            }
        ))
    }

    /// Uniform section header, matching the "Subscription Usage" / "API Spend" style so
    /// every zone in the window reads the same.
    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold))
    }

    /// Uniform descriptive caption. Consolidates the former mix of `.caption` and
    /// `.caption2` fine print into one size so the helper text reads as one system.
    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func insetHairline() -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.42))
            .frame(height: 1)
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
    }

    /// `enabled` gates the key entry behind its "… API spend" toggle (progressive
    /// disclosure): the field dims and stops taking input until the surface is on, so an
    /// off feature doesn't present a live, focusable credential field.
    private func apiKeyRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        provider: APIKeyProvider,
        enabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    saveKey(text.wrappedValue, for: provider)
                    text.wrappedValue = ""
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                Button("Remove") {
                    deleteKey(for: provider)
                    text.wrappedValue = ""
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                .foregroundStyle(.secondary)
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private func saveKey(_ key: String, for provider: APIKeyProvider) {
        Task {
            switch await credentialStore.saveAPIKey(key, for: provider) {
            case .success:
                credentialMessage = "\(provider.displayName) API key saved"
                store.refreshAPISpendNow()
            case .failure(let reason):
                credentialMessage = reason.message
            }
        }
    }

    private func deleteKey(for provider: APIKeyProvider) {
        Task {
            switch await credentialStore.deleteAPIKey(for: provider) {
            case .success:
                credentialMessage = "\(provider.displayName) API key removed"
                store.refreshAPISpendNow()
            case .failure(let reason):
                credentialMessage = reason.message
            }
        }
    }
}

private struct APISpendPeriodTransitionModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .offset(y: active ? 4 : 0)
            .blur(radius: active ? 1.5 : 0)
    }
}

private extension AnyTransition {
    static var apiSpendPeriodSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: APISpendPeriodTransitionModifier(active: true),
                identity: APISpendPeriodTransitionModifier(active: false)
            ),
            removal: .opacity
        )
    }
}

private extension View {
    func settingsPanel() -> some View {
        self
            .padding(12)
            .raisedTile(cornerRadius: 10, surface: .opaque)
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

/// Renewal date entry: a tidy bordered label showing the formatted date, opening a calendar
/// on click. macOS has no compact tap-to-calendar `DatePicker` (that's iOS-only), and the
/// `.field`/`.stepperField` styles space-pad single digits ("7/ 3/2026"), so we format the
/// label ourselves ("Jul 3, 2026") and pop a `.graphical` picker for editing.
private struct RenewalDateField: View {
    @Binding var date: Date
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing.toggle()
        } label: {
            Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                .monospacedDigit()
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .frame(width: 260)
        }
    }
}
