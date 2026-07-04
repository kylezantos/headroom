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
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var showMenuBarPercentage = false
    @State private var menuBarFillSource: MenuBarFillSource = .none
    @State private var widgetsEnabled = true
    @State private var syncToIPhoneEnabled = false
    @State private var launchAtLogin = false
    @State private var renewalDates: [ProviderID: Date] = [:]
    @State private var apiSpendPeriod: APISpendPeriod = .currentMonth
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var credentialMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Custom header (the window uses a hidden title bar): the vessel logo anchors
            // the title, drawn just below the floating traffic lights.
            HStack(spacing: 10) {
                VesselMark()
                    .frame(width: 17, height: 30)
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

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Widgets")
                WidgetSettingsSection(
                    widgetsEnabled: $widgetsEnabled,
                    syncToIPhoneEnabled: $syncToIPhoneEnabled
                )
                .onChange(of: widgetsEnabled) { _, newValue in
                    store.setWidgetsEnabled(newValue)
                }
                .onChange(of: syncToIPhoneEnabled) { _, newValue in
                    store.setSyncToIPhoneEnabled(newValue)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Subscription Usage")
                surfaceToggle(.claudeSubscription)
                surfaceToggle(.codexSubscription)
            }

            Divider()

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
                    store.refreshNow()
                }

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

                if let credentialMessage {
                    Text(credentialMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Divider()

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

            Divider()

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
            syncToIPhoneEnabled = store.syncToIPhoneEnabled
            apiSpendPeriod = store.apiSpendPeriod
            launchAtLogin = launchControl.isEnabled
            for id in [ProviderID.claude, .codex] {
                if let date = preferences.renewalDate(for: id) { renewalDates[id] = date }
            }
        }
    }

    private func surfaceToggle(_ surface: UsageSurface) -> some View {
        Toggle(surface.displayName, isOn: Binding(
            get: { store.isSurfaceEnabled(surface) },
            set: { newValue in
                store.setSurfaceEnabled(newValue, for: surface)
                store.refreshNow()
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
                store.refreshNow()
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
                store.refreshNow()
            case .failure(let reason):
                credentialMessage = reason.message
            }
        }
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

/// The Headroom identity mark drawn as a crisp vector — a miniature of the app icon: a
/// capsule vessel filled from the bottom (the empty space on top *is* the headroom), with a
/// green liquid gradient, a bright meniscus surface line, and a metallic rim. Rendered as a
/// vector so it stays sharp at header size (the full app-icon PNG turns to mud that small).
/// The `0.557` frame aspect ratio matches the app-icon capsule (330×592); anything squatter
/// reads as a blob rather than the vessel.
private struct VesselMark: View {
    /// Static fill matching the app icon (`0.46`); the mark is decorative here, not live.
    var fillFraction: CGFloat = 0.46

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let rim = max(1.3, w * 0.12)
            ZStack(alignment: .bottom) {
                // Full-size base so the ZStack fills the frame; without it the ZStack shrinks
                // to the liquid's height and `.frame` centers it — the "floating pill" bug.
                Color.clear
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.58, green: 1.00, blue: 0.78),
                                 Color(red: 0.29, green: 0.87, blue: 0.59),
                                 Color(red: 0.12, green: 0.67, blue: 0.44)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(height: h * fillFraction)
                    .overlay(alignment: .top) {
                        // Bright meniscus line at the liquid surface, like the icon's glow.
                        Rectangle()
                            .fill(Color(red: 0.92, green: 1.00, blue: 0.96))
                            .frame(height: max(1, h * 0.035))
                            .opacity(0.6)
                    }
            }
            .frame(width: w, height: h)
            .clipShape(Capsule())
            // Adaptive rim so it defines the capsule in both light and dark settings windows.
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [Color.primary.opacity(0.72), Color.primary.opacity(0.42)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: rim)
            )
        }
    }
}
