import AppKit
import SwiftUI
import Accessibility
import HeadroomCore

/// Settings window root. Presented in its own window so dismissing settings never
/// closes the menu bar popover behind it.
///
/// Sidebar rebuild (Sep 2026): the single scrolling column of nine tiles became a
/// System-Settings-style `NavigationSplitView` with six named destinations (R1), so a
/// preference is found by picking a room instead of scrolling past everything else.
/// Pane content keeps the popover's card language — `RaisedTile` at 13pt pad / 10pt
/// radius, 15pt semibold titles, one row grammar (label leading, control trailing).
///
/// KTD3: this view owns *all* root state. The panes are stateless and read it through
/// bindings and closures, so switching panes preserves API key drafts, the Replace flow,
/// result messages, and the pending removal dialog (R13).
struct SettingsView: View {
    let store: UsageStore
    @Binding var appearancePreference: AppearancePreference
    var softwareUpdates: SoftwareUpdateControlling = DisabledSoftwareUpdateController()
    var preferences = Preferences()
    var credentialStore = CredentialStore()
    var launchControl: LaunchAtLoginControlling = LaunchAtLogin()
    /// Injection seam (unused in production wiring); the default reads each account's
    /// `.claude.json`.
    var duplicateDetector = ClaudeDuplicateLoginDetector()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarSelection: SettingsPane? = .general
    @State private var hasVisitedAccounts = false
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var showMenuBarPercentage = false
    @State private var usagePercentageMode: UsagePercentageMode = .remaining
    @State private var meterStyle: MeterStyle = .default
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
    /// KTD3: hoisted off `AccountsSettingsTile` so leaving and re-entering Accounts
    /// neither blanks the "Same login as X" badges nor re-reads every `.claude.json`.
    @State private var duplicateLoginLabels: [AccountKey: String] = [:]

    /// Fast, no-bounce settle shared by the credential-row reveals and result messages.
    /// The interaction is occasional settings work, so it gets just enough motion to
    /// confirm the state change.
    private static let settleAnimation = HeadroomMotion.settle

    /// KTD2, revised Sep 2026: the width is fixed for every pane, but the height is now
    /// per-destination (`SettingsPane.preferredContentHeight`). One Appearance-sized frame
    /// everywhere left General showing two rows above ~600pt of empty window. Every pane
    /// body is still a `ScrollView`, so a pane that outgrows its budget scrolls instead of
    /// clipping, and AppKit can still constrain the window to a short screen.
    ///
    /// Appearance is the tallest pane (specimen + Theme + Meter style + In-app display):
    /// about 805pt of content at default text size once the Fill swatches sit on one row.
    /// The hidden title bar adds 32pt (measured live), so 812pt of content is an 844pt
    /// window, which still clears a 13-inch MacBook Air's 931pt of usable height. It stays
    /// the window's declared default size.
    /// 740, not 720: the sidebar column had to grow 36pt to stop clipping "Widgets &
    /// iPhone", and the detail column cannot absorb that. Appearance's Fill row needs
    /// 392pt of grid (5 × 72pt swatches + 4 × 8pt gaps) beside its 46pt row label, and
    /// the detail column only offers `width − sidebar − 124`. At 720/216 that is 379pt
    /// and the five fills wrap to two rows; 740/216 restores the 523pt detail column —
    /// the exact width `MeterStyleTile`'s 72pt minimum was chosen against.
    static let windowWidth: CGFloat = 740
    static let windowHeight: CGFloat = SettingsPane.appearance.preferredContentHeight
    static let minimumWindowHeight: CGFloat = 600
    /// Diagnostic seam: the render harness raises the frame for its multi-account capture
    /// so the whole account list is in the picture. The live window never sets this.
    var frameHeightOverride: CGFloat? = nil
    private var frameHeight: CGFloat {
        frameHeightOverride ?? selectedPane.preferredContentHeight
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: sidebarBinding)
                // 216pt as the *floor*, not just the ideal: with the split view pinned to
                // a fixed overall width the sidebar can settle on its minimum, and 180pt
                // clipped the longest destination to "Widgets & i…". 108pt of text at
                // 13pt plus the icon column and the sidebar's row insets needs ~216pt.
                .navigationSplitViewColumnWidth(min: 216, ideal: 216, max: 250)
                // KTD1: the removal must sit on the sidebar column's content — applied to
                // the split view itself it is ignored and the toggle still renders.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        // KTD8: no `.navigationTitle` anywhere in the split view — the window title
        // string set in `HeadroomApp` is what `placeSettingsWindowOnActiveScreen()`
        // matches on, and a navigation title would replace it.
        .frame(
            minWidth: Self.windowWidth, idealWidth: Self.windowWidth, maxWidth: Self.windowWidth,
            minHeight: min(Self.minimumWindowHeight, frameHeight),
            idealHeight: frameHeight,
            maxHeight: frameHeight
        )
        // The scene is `.windowResizability(.contentSize)`, so AppKit follows the hosting
        // view's fitting size every layout pass: interpolating the frame height is what
        // makes the window grow or shrink over the settle duration instead of snapping.
        // Scoped to `frameHeight` so ordinary preference changes inside a pane are not
        // swept into it. A pane switch changes both the height and the detail content, so
        // the room cross-fades as the frame travels.
        .animation(reduceMotion ? nil : Self.settleAnimation, value: frameHeight)
        .onAppear { loadPreferences() }
        .task { await refreshSavedKeyPresence() }
        // KTD3: the scan lives on the root so revisiting Accounts keeps its badges, but it
        // only starts once Accounts has been shown — a visit to General should not read
        // every Claude account's `.claude.json`.
        .task(id: hasVisitedAccounts ? claudeDuplicateFingerprint : nil) {
            guard hasVisitedAccounts else { return }
            // Off-main: `.claude.json` can be large (the CLI writes project history
            // into it), so the identity reads never block the settings surface.
            let detector = duplicateDetector
            let accounts = store.accounts(for: .claude)
            let labels = await Task.detached {
                detector.duplicateLabels(for: accounts)
            }.value
            // The detached scan outlives this .task's cancellation, so a slow stale
            // scan can finish after a newer one — never let it overwrite the fresh
            // badge state (code-review finding).
            guard !Task.isCancelled else { return }
            duplicateLoginLabels = labels
        }
        .onChange(of: selectedPane) { _, newValue in
            preferences.settingsPane = newValue
            if newValue == .accounts { hasVisitedAccounts = true }
        }
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

    /// The pane on screen. `sidebarSelection` is optional only because `List(selection:)`
    /// demands it; the binding below never stores nil, so the fallback is unreachable.
    private var selectedPane: SettingsPane { sidebarSelection ?? .general }

    /// macOS can hand a sidebar `List` a nil selection (⌘-click deselect, or a rebuild
    /// mid-transition). Dropping to no pane would blank the detail column, so a nil is
    /// ignored and the last real destination stays selected.
    private var sidebarBinding: Binding<SettingsPane?> {
        Binding(
            get: { sidebarSelection },
            set: { newValue in
                guard let newValue else { return }
                sidebarSelection = newValue
            }
        )
    }

    @ViewBuilder private var detail: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsPane(
                intervalMinutes: $intervalMinutes,
                launchAtLogin: $launchAtLogin,
                softwareUpdates: softwareUpdates,
                onIntervalChange: { newValue in
                    preferences.pollIntervalMinutes = newValue
                    store.reschedulePolling()
                },
                onLaunchAtLoginChange: { newValue in
                    try? launchControl.setEnabled(newValue)
                }
            )
        case .appearance:
            AppearanceSettingsPane(
                store: store,
                appearancePreference: $appearancePreference,
                meterStyle: $meterStyle,
                usagePercentageMode: $usagePercentageMode,
                showCodexSparkCountersInApp: $showCodexSparkCountersInApp,
                onAppearanceChange: { newValue in
                    preferences.appearancePreference = newValue
                    // Repaint the AppKit windows (this Settings window + the popover panel);
                    // `preferredColorScheme` alone doesn't reach their chrome, and switching
                    // to System doesn't release the per-window appearance pin. (See HeadroomApp.)
                    newValue.applyToProcess()
                },
                onMeterStyleChange: { newStyle in
                    store.setMeterStyle(newStyle)
                }
            )
        case .menuBar:
            MenuBarSettingsPane(
                store: store,
                showMenuBarPercentage: $showMenuBarPercentage,
                menuBarFillSource: $menuBarFillSource,
                menuBarWindowSources: $menuBarWindowSources
            )
        case .widgets:
            WidgetsSettingsPane(
                store: store,
                widgetsEnabled: $widgetsEnabled,
                showCodexSparkCountersInWidgets: $showCodexSparkCountersInWidgets,
                syncToIPhoneEnabled: $syncToIPhoneEnabled
            )
        case .accounts:
            AccountsSettingsPane(
                store: store,
                duplicateLoginLabels: duplicateLoginLabels,
                surfaceBinding: surfaceBinding
            )
        case .apiSpend:
            APISpendSettingsPane(
                store: store,
                apiSpendPeriod: $apiSpendPeriod,
                apiKeyDrafts: $apiKeyDrafts,
                replacingKeyProviders: $replacingKeyProviders,
                credentialMessages: $credentialMessages,
                savedKeyProviders: savedKeyProviders,
                surfaceBinding: surfaceBinding,
                onSaveKey: { key, provider in saveKey(key, for: provider) },
                onRequestRemoval: { removalCandidate = $0 },
                cancelMessageDismissal: { messageDismissals[$0]?.cancel() }
            )
        }
    }

    /// Recompute duplicate badges when the Claude account list changes, a row is
    /// renamed (badges quote account labels), a row's signed-in identity changes, or
    /// a fresh capture lands (a re-login to a different accountUuid under the same
    /// email only surfaces as a new `capturedAt` — the scan is cheap off-main and
    /// only runs while the settings window is open).
    private var claudeDuplicateFingerprint: String {
        store.accounts(for: .claude)
            .map { account in
                let snapshot = store.snapshot(for: account.key)
                let captured = snapshot.capturedAt?.timeIntervalSinceReferenceDate ?? 0
                return "\(account.id.raw):\(account.label):\(snapshot.accountEmail ?? ""):\(captured)"
            }
            .joined(separator: "|")
    }

    // MARK: - Shared bindings

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

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: { if !$0 { removalCandidate = nil } }
        )
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
        // R4: reopen on the last-visited destination; an unknown stored value already
        // decodes to General in `Preferences`.
        let storedPane = preferences.settingsPane
        sidebarSelection = storedPane
        if storedPane == .accounts { hasVisitedAccounts = true }
        appearancePreference = preferences.appearancePreference
        showMenuBarPercentage = store.showMenuBarPercentage
        usagePercentageMode = store.usagePercentageMode
        meterStyle = store.meterStyle
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

// (RenewalDateField removed — plan-renewal dates were cut from all UI in the
// Jul 2026 density audit; `Preferences.renewalDate` remains for stored data.)
