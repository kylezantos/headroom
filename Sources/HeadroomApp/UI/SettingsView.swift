import AppKit
import SwiftUI
import Accessibility
import HeadroomCore

/// Settings window root. Presented in its own window so dismissing settings never
/// closes the menu bar popover behind it.
///
/// Sidebar rebuild (Sep 2026): the single scrolling column of nine tiles became a
/// System-Settings-style `NavigationSplitView` with six named destinations (R1; seven
/// since Notifications, 2026-09-26), so a preference is found by picking a room instead
/// of scrolling past everything else.
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
    // The launch domain, not `.standard`: production passes this in, but a fallback on
    // `.standard` would put a `--demo` Settings session back in the user's real defaults.
    var preferences = AppComposition.launchPreferences
    var credentialStore = CredentialStore()
    var launchControl: LaunchAtLoginControlling = LaunchAtLogin()
    /// Injection seam (unused in production wiring); the default reads each account's
    /// `.claude.json`.
    var duplicateDetector = ClaudeDuplicateLoginDetector()
    /// U6: permission reads and requests for the Notifications pane. Required, so every
    /// caller chooses — production passes `AppComposition.notificationClient`, the render
    /// harness a scripted fake — and none can reach the real center by default (KTD9).
    let notificationClient: any NotificationAuthorizing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// LP1 (2026-10-03 perf bench): nil until `loadPreferences` picks the room. Seeded with
    /// `.general`, every open built General — twice — before switching to the stored pane,
    /// and that switch played the pane transition inside the window's own fade-in.
    @State private var sidebarSelection: SettingsPane?
    /// KB1: whether the latest pane switch came from the keyboard.
    @State private var paneSwitchIsInstant = false
    @State private var hasVisitedAccounts = false
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var usagePercentageMode: UsagePercentageMode = .remaining
    @State private var accountTitleInk: AccountTitleInk = .neutral
    @State private var meterStyle: MeterStyle = .default
    /// R16: the widget style Settings › Widgets & iPhone previews. View state only — widgets
    /// choose their own style in Edit Widget. `--widget-style` seeds it for the harness.
    @State private var widgetPreviewStyle: WidgetLayoutStyle = AppComposition.demoWidgetStyle()
    @State private var widgetsEnabled = true
    @State private var showCodexSparkCountersInApp = true
    @State private var showCodexSparkCountersInWidgets = false
    @State private var syncToIPhoneEnabled = false
    @State private var launchAtLogin = false
    /// L13: mirrors Sparkle's stored preference so the Updates switch repaints on
    /// toggle; the updater stays the source of truth and is written on change.
    @State private var automaticUpdateChecks = false
    @State private var automaticUpdateDownloads = false
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
    /// KTD11: the last permission read. Nil until the first check lands, so the pane never
    /// flashes the denied notice on open.
    @State private var notificationAuthorization: NotificationAuthorization?

    /// Fast, no-bounce settle shared by the credential-row reveals and result messages.
    /// The interaction is occasional settings work, so it gets just enough motion to
    /// confirm the state change.
    private static let settleAnimation = HeadroomMotion.settle

    /// L9A: one window for every destination, resizable on both axes, and the size the
    /// user leaves it at is the size it keeps. Per-pane window heights are retired —
    /// resizing the frame on every pane switch is what read as unfinished, and the real
    /// squeeze in the review was horizontal (help text wrapping in a ~340pt content
    /// column), not vertical. Every pane body is a `ScrollView`, so Appearance — the
    /// tallest room at roughly 812pt of content — simply scrolls at the 700pt default
    /// instead of dictating the window.
    ///
    /// 800 × 700 default, 720 × 600 floor, no ceiling. 800 keeps the Appearance Fill row
    /// on one line: the row needs 392pt of grid (5 × 72pt swatches + 4 × 8pt gaps) beside
    /// its 46pt label, and the detail column offers `width − sidebar − 124` — 460pt at
    /// 800/216, against 380pt at the old 720. 600 tall is the floor because the sidebar's
    /// identity block and six destinations need roughly 340pt before the list itself
    /// scrolls; the seventh (Notifications, 2026-09-26) adds one ~28pt row, still well
    /// inside the floor. The scene declares these via `.windowResizability(.contentSize)`,
    /// which reads the min and max off this frame; leaving max unset is what makes the
    /// window resizable at all.
    static let windowWidth: CGFloat = 800
    /// R2B2: 770, up from 700. The opening height of a resizable window matters only for
    /// where it *cuts*, and 700 cut through the middle of the Fill swatch row — a half-drawn
    /// control is the one thing an opening frame must not show. Measured off the harness
    /// render of Appearance (the tallest pane) after R2C19's spacing: the Fill grid's last
    /// swatch ends at ≈766pt and its help line starts 6pt later, so 770 puts the fold in that
    /// gap. Every control in the pane is whole; only prose waits below it. 760 was two points
    /// short and clipped the second line of the wrapped swatch labels. Re-measure if the
    /// pane's spacing or content changes again.
    static let windowHeight: CGFloat = 770
    static let minimumWindowWidth: CGFloat = 720
    static let minimumWindowHeight: CGFloat = 600
    /// L9A: leading-aligned cap on a pane's content so a window dragged to 1200pt does
    /// not run a help line to full measure. Sits inside the detail column, outside the
    /// pane's own 20pt padding, and never bites at the default width (the detail column
    /// is ~584pt there).
    static let detailContentMaxWidth: CGFloat = 640
    /// Diagnostic seam: the render harness raises the frame for its multi-account capture
    /// so the whole account list is in the picture. The live window never sets this.
    var frameHeightOverride: CGFloat? = nil

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: sidebarBinding)
                // KTD1: the removal must sit on the sidebar column's content — applied to
                // the split view itself it is ignored and the toggle still renders.
                //
                // **Order is load-bearing on Tahoe (macOS 26).** This must come *before*
                // `.navigationSplitViewColumnWidth`, not after it. `.toolbar(removing:)`
                // wraps the content in a view whose column-width preference
                // `NavigationSplitView` no longer reads, so a width declared underneath it
                // is silently dropped and the column falls back to a 140pt intrinsic
                // width — which clipped the longest destination to "Widgets &…".
                // Measured on macOS 26.5 against the live window: with the removal applied
                // last the column is 140pt at every window width and for *any* declared
                // value (216, 250, even a fixed 400); applied first it is 216pt at 720,
                // 800, and 1100 wide. Independent of the outer frame — the pre-L9A
                // width-pinned frame reproduces 140pt just the same — and independent of
                // the split-view style. If this ever has to move again, prove it by
                // reading the sidebar column's accessibility frame, not by eye.
                .toolbar(removing: .sidebarToggle)
                // L9A: 216pt as the *floor* as well as the ideal — the sidebar can
                // settle on its minimum, and 180pt clipped the longest destination to
                // "Widgets & i…". 108pt of text at 13pt plus the icon column and the
                // sidebar's row insets needs ~216pt. 250 caps how much of a widened
                // window the navigation can claim; the extra width belongs to the panes.
                .navigationSplitViewColumnWidth(min: 216, ideal: 216, max: 250)
        } detail: {
            detailColumn
        }
        // KTD8: no `.navigationTitle` anywhere in the split view — the window title
        // string set in `HeadroomApp` is what `placeSettingsWindowOnActiveScreen()`
        // matches on, and a navigation title would replace it.
        // L9A: no max on either axis — `.windowResizability(.contentSize)` derives the
        // window's resize limits from this frame, so an unset max is what lets the user
        // drag the window as large as they like. The ideal is only the opening size.
        .frame(
            minWidth: Self.minimumWindowWidth,
            idealWidth: Self.windowWidth,
            minHeight: Self.minimumWindowHeight,
            idealHeight: frameHeightOverride ?? Self.windowHeight
        )
        .onAppear { loadPreferences() }
        // R18: re-check permission every time Settings opens, and again whenever Headroom
        // comes back to the front — the way back from "Open System Settings…".
        .task { await refreshNotificationAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotificationAuthorization() }
        }
        .task { await refreshSavedKeyPresence() }
        // KTD3: the scan's result lives on the root so revisiting Accounts keeps its badges,
        // but it only starts once Accounts has been shown — a visit to General should not
        // read every Claude account's `.claude.json`.
        .background {
            if hasVisitedAccounts {
                ClaudeDuplicateLoginScan(
                    store: store,
                    detector: duplicateDetector,
                    labels: $duplicateLoginLabels
                )
            }
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

    /// The pane on screen. `sidebarSelection` is optional because `List(selection:)` demands
    /// it, and it is nil only before `loadPreferences` runs (LP1); the binding below never
    /// stores nil after that.
    private var selectedPane: SettingsPane { sidebarSelection ?? .general }

    /// macOS can hand a sidebar `List` a nil selection (⌘-click deselect, or a rebuild
    /// mid-transition). Dropping to no pane would blank the detail column, so a nil is
    /// ignored and the last real destination stays selected.
    private var sidebarBinding: Binding<SettingsPane?> {
        Binding(
            get: { sidebarSelection },
            set: { newValue in
                guard let newValue else { return }
                // KB1: arrowing through the sidebar swaps panes instantly. Set in the same
                // update as the selection, because the transition is read for both panes then.
                paneSwitchIsInstant = HeadroomMotion.isKeyboardInitiated
                sidebarSelection = newValue
            }
        )
    }

    /// M6B: 120ms opacity-only dissolve between destinations. Nothing travels — a pane is a
    /// different room, not the same content moving — and the sidebar's native selection
    /// highlight is left alone. The `ZStack` is what makes the `.id` swap a transition
    /// rather than a hard cut: it is the stable container the outgoing and incoming panes
    /// overlap inside, the same shape as the Menu Bar pane's `preview` strip (MS2).
    /// Panes stay stateless (KTD3), so nothing is lost when one is rebuilt.
    ///
    /// SM2 (2026-09-22): the symmetric 120ms dissolve overlapped two dense rooms at half
    /// opacity each, which read as a double exposure rather than a room change. The exit is
    /// now 80ms and the entrance 200ms out of a 3pt blur (Emil's blur-bridge), so the eye
    /// sees one pane resolve instead of two crossing. Still nothing travels (M6B).
    private var detailColumn: some View {
        ZStack(alignment: .topLeading) {
            // LP1: no pane until the stored one is known, so the first one built is the one
            // shown. `loadPreferences` runs in the first layout pass, before the window is
            // revealed, so this empty column never reaches the screen.
            if sidebarSelection != nil {
                detail
                    .id(selectedPane)
                    // KB1: `.identity`, not a nil-animation transaction — measured, a transition's
                    // attached animation plays even inside `disablesAnimations`.
                    .transition(paneSwitchIsInstant ? .identity : .settingsPane(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            paneSwitchIsInstant
                ? nil
                : HeadroomMotion.resolved(HeadroomMotion.paneIn, .crossfade, reduceMotion: reduceMotion),
            value: selectedPane
        )
    }

    @ViewBuilder private var detail: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsPane(
                intervalMinutes: $intervalMinutes,
                launchAtLogin: $launchAtLogin,
                automaticUpdateChecks: $automaticUpdateChecks,
                automaticUpdateDownloads: $automaticUpdateDownloads,
                softwareUpdates: softwareUpdates,
                cadenceSentence: cadenceSentence,
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
                accountTitleInk: $accountTitleInk,
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
            MenuBarSettingsPane(store: store, onOpenAccounts: {
                paneSwitchIsInstant = false
                sidebarSelection = .accounts
            })
        case .widgets:
            WidgetsSettingsPane(
                store: store,
                previewStyle: $widgetPreviewStyle,
                widgetsEnabled: $widgetsEnabled,
                showCodexSparkCountersInWidgets: $showCodexSparkCountersInWidgets,
                syncToIPhoneEnabled: $syncToIPhoneEnabled
            )
        case .notifications:
            NotificationsSettingsPane(
                store: store,
                authorization: notificationAuthorization,
                latenessMinutes: reminderLatenessMinutes,
                onSetSwitch: { which, isOn in
                    Task {
                        let status = await NotificationsSettingsInteractions.setSwitch(
                            which,
                            isOn: isOn,
                            store: store,
                            client: notificationClient,
                            known: notificationAuthorization
                        )
                        setNotificationAuthorization(status)
                    }
                },
                onOpenSystemSettings: { notificationClient.openSystemSettings() }
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
        case .about:
            AboutSettingsPane(
                softwareUpdates: softwareUpdates,
                automaticUpdateChecks: $automaticUpdateChecks,
                automaticUpdateDownloads: $automaticUpdateDownloads
            )
        }
    }

    /// KTD12: read from the store's observable cadences so the sentence updates as lanes drain.
    private var cadenceSentence: String? {
        PollCadencePresentation.sentence(for: store.registeredProviderOrder.compactMap { providerID in
            guard let cadence = store.pollCadences[providerID] else { return nil }
            return (store.displayNames[providerID] ?? providerID.displayName, cadence)
        })
    }

    /// R9: the reminder help line's lateness figure — the slowest effective interval across
    /// the same lanes `cadenceSentence` reads, so General and Notifications quote one number.
    private var reminderLatenessMinutes: Int {
        PollCadencePresentation.slowestEffectiveMinutes(
            store.registeredProviderOrder.compactMap { store.pollCadences[$0] },
            chosenInterval: LaneSchedule.chosenInterval(minutes: intervalMinutes)
        )
    }

    // MARK: - Notifications permission

    private func refreshNotificationAuthorization() async {
        let status = await NotificationsSettingsInteractions.refreshAuthorization(
            store: store,
            client: notificationClient
        )
        setNotificationAuthorization(status)
    }

    /// The notice tile's reveal rides the pane's own `.animation` scope; this only avoids
    /// republishing an unchanged state.
    private func setNotificationAuthorization(_ status: NotificationAuthorization?) {
        guard notificationAuthorization != status else { return }
        notificationAuthorization = status
    }

    // MARK: - Shared bindings

    private func surfaceBinding(_ surface: UsageSurface) -> Binding<Bool> {
        Binding(
            get: { store.isSurfaceEnabled(surface) },
            set: { newValue in
                // Animated so the key-entry reveal below an API row settles instead of
                // hard-cutting. RM1: `.movement`, so under Reduce Motion the tile's height
                // snaps; the reveal's fade survives on its own via
                // `settingsReveal(reduceMotion:)`.
                withAnimation(
                    HeadroomMotion.resolved(Self.settleAnimation, .movement, reduceMotion: reduceMotion)
                ) {
                    store.setSurfaceEnabled(newValue, for: surface)
                }
                if surface.isSubscription {
                    // KTD11 (2026-09-19 polling plan): wake only this provider's now-due
                    // accounts. A full `refreshNow()` here marked every other provider's
                    // accounts due too, which at the account envelope is the very sweep the
                    // per-account scheduler removes.
                    store.dispatchDueNow(for: surface.providerID)
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

    /// R2B1: "signed in" for the first-open default means at least one configured account has
    /// produced a reading. A never-signed-in stale reason — or nothing fetched at all — is the
    /// case Accounts exists to answer, so that is the room the window opens in.
    private var hasSignedInAccount: Bool {
        store.registeredProviderOrder.contains { providerID in
            store.accounts(for: providerID).contains { account in
                let snapshot = store.snapshot(for: account.key)
                if case .stale(let reason) = snapshot.freshness,
                   reason.providerSetupOutcome?.isNeverSignedIn == true {
                    return false
                }
                return snapshot.freshness == .live || !snapshot.windows.isEmpty
            }
        }
    }

    private func loadPreferences() {
        // Clamp any legacy sub-2-minute interval up to the new floor.
        let saved = max(2, preferences.pollIntervalMinutes)
        if saved != preferences.pollIntervalMinutes {
            preferences.pollIntervalMinutes = saved
            store.reschedulePolling()
        }
        intervalMinutes = saved
        // R4: reopen on the last-visited destination; an unknown stored value already
        // decodes to General in `Preferences`. R2B1: on the *first* open — nothing stored —
        // a Mac with no account signed in opens on Accounts instead, where all of its work is.
        let storedPane = preferences.initialSettingsPane(hasSignedInAccount: hasSignedInAccount)
        // LP1: the opening pane arrives with the window, not as a pane switch.
        paneSwitchIsInstant = true
        sidebarSelection = storedPane
        if storedPane == .accounts { hasVisitedAccounts = true }
        appearancePreference = preferences.appearancePreference
        usagePercentageMode = store.usagePercentageMode
        accountTitleInk = store.accountTitleInk
        meterStyle = store.meterStyle
        widgetsEnabled = store.widgetsEnabled
        showCodexSparkCountersInApp = store.showCodexSparkCountersInApp
        showCodexSparkCountersInWidgets = store.showCodexSparkCountersInWidgets
        syncToIPhoneEnabled = store.syncToIPhoneEnabled
        apiSpendPeriod = store.apiSpendPeriod
        launchAtLogin = launchControl.isEnabled
        automaticUpdateChecks = softwareUpdates.automaticallyChecksForUpdates
        automaticUpdateDownloads = softwareUpdates.automaticallyDownloadsUpdates
    }

    /// Presence only (never the key material): selects the configured summary or the
    /// first-save editor, so the UI can show whether a credential exists at rest.
    /// One write for the whole sweep (2026-10-03 perf bench): each per-key insert landed after
    /// its own Keychain hop and re-rendered the root and the open pane during the fade-in.
    private func refreshSavedKeyPresence() async {
        var present: Set<APIKeyProvider> = []
        for provider in APIKeyProvider.allCases {
            if case .success = await credentialStore.apiKey(for: provider) {
                present.insert(provider)
            }
        }
        if savedKeyProviders != present { savedKeyProviders = present }
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

/// KTD3's duplicate-login scan, in a view of its own (DL1, 2026-10-03 perf bench). Its
/// fingerprint reads every Claude snapshot; computed in `SettingsView.body`, it made each
/// Claude refresh re-render the whole window and its open pane once Accounts had been
/// visited. Here a refresh re-runs only this empty view, and the root re-renders only when
/// the badges themselves change.
private struct ClaudeDuplicateLoginScan: View {
    let store: UsageStore
    let detector: ClaudeDuplicateLoginDetector
    @Binding var labels: [AccountKey: String]

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .task(id: fingerprint) {
                // Off-main: `.claude.json` can be large (the CLI writes project history
                // into it), so the identity reads never block the settings surface.
                let detector = detector
                let accounts = store.accounts(for: .claude)
                let scanned = await Task.detached {
                    detector.duplicateLabels(for: accounts)
                }.value
                // The detached scan outlives this .task's cancellation, so a slow stale
                // scan can finish after a newer one — never let it overwrite the fresh
                // badge state (code-review finding).
                guard !Task.isCancelled else { return }
                if labels != scanned { labels = scanned }
            }
    }

    /// Recompute duplicate badges when the Claude account list changes, a row is
    /// renamed (badges quote account labels), a row's signed-in identity changes, or
    /// a fresh capture lands (a re-login to a different accountUuid under the same
    /// email only surfaces as a new `capturedAt` — the scan is cheap off-main and
    /// only runs while the settings window is open).
    private var fingerprint: String {
        store.accounts(for: .claude)
            .map { account in
                let snapshot = store.snapshot(for: account.key)
                let captured = snapshot.capturedAt?.timeIntervalSinceReferenceDate ?? 0
                return "\(account.id.raw):\(account.label):\(snapshot.accountEmail ?? ""):\(captured)"
            }
            .joined(separator: "|")
    }
}

// (RenewalDateField removed — plan-renewal dates were cut from all UI in the
// Jul 2026 density audit; `Preferences.renewalDate` remains for stored data.)
