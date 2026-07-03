import SwiftUI
import HeadroomCore

/// Settings pane (U8): poll interval, per-provider renewal dates (R4), and
/// launch-at-login (R15). Presented in its own window so dismissing settings never
/// closes the menu bar popover behind it.
struct SettingsView: View {
    let store: UsageStore
    var preferences = Preferences()
    var credentialStore = CredentialStore()
    var launchControl: LaunchAtLoginControlling = LaunchAtLogin()

    @Environment(\.dismiss) private var dismiss
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var showMenuBarPercentage = false
    @State private var menuBarFillSource: MenuBarFillSource = .none
    @State private var widgetsEnabled = true
    @State private var launchAtLogin = false
    @State private var renewalDates: [ProviderID: Date] = [:]
    @State private var apiSpendPeriod: APISpendPeriod = .currentMonth
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var credentialMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Stepper("Refresh every \(intervalMinutes) min", value: $intervalMinutes, in: 2...60)
                    .onChange(of: intervalMinutes) { _, newValue in
                        preferences.pollIntervalMinutes = newValue
                        store.reschedulePolling()
                    }
                Text("Each Claude refresh runs a CLI session (~20–30s). Minimum 2 min.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Toggle("Show percentage in menu bar", isOn: $showMenuBarPercentage)
                .onChange(of: showMenuBarPercentage) { _, newValue in
                    store.setShowMenuBarPercentage(newValue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Picker("Menu bar fill tracks", selection: $menuBarFillSource) {
                    ForEach(MenuBarFillSource.allCases, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }
                .onChange(of: menuBarFillSource) { _, newValue in
                    store.setMenuBarFillSource(newValue)
                }
                Text("Drains with the chosen provider's weekly usage; None keeps it static.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WidgetSettingsSection(widgetsEnabled: $widgetsEnabled)
                .onChange(of: widgetsEnabled) { _, newValue in
                    store.setWidgetsEnabled(newValue)
                }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Subscription Usage").font(.subheadline.weight(.semibold))
                surfaceToggle(.claudeSubscription)
                surfaceToggle(.codexSubscription)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("API Spend").font(.subheadline.weight(.semibold))
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
                    provider: .anthropic
                )

                surfaceToggle(.openAIAPI)
                apiKeyRow(
                    title: "OpenAI admin key",
                    placeholder: "sk-…",
                    text: $openAIKey,
                    provider: .openAI
                )

                if let credentialMessage {
                    Text(credentialMessage)
                        .font(.caption2)
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
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { renewalDates[id] ?? Date() },
                                set: { renewalDates[id] = $0; preferences.setRenewalDate($0, for: id) }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    try? launchControl.setEnabled(newValue)
                }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        // Center the window title. macOS 26 leading-aligns the default window title, so
        // remove it and supply a centered principal item instead.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Headroom Settings").font(.headline)
            }
        }
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

    private func apiKeyRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        provider: APIKeyProvider
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
