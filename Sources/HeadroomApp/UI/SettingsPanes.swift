#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import AppKit
import SwiftUI
import HeadroomCore

/// The seven Settings destinations (R1). KTD3: every pane here is stateless — root state
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
        let _ = BenchCounters.hit("SettingsPaneScaffold")
        ScrollView(.vertical) {
            // R2C19: the pane's two levels no longer share one 14. The title sits close to
            // the tile it heads and the tiles stand well apart, so which level a gap
            // separates is legible from the gap alone.
            VStack(alignment: .leading, spacing: SettingsMetrics.headerToContent) {
                // PB2/T5: the top of the pane's hierarchy, a clear step above the 15pt tile
                // headers under it (17 read as their twin).
                Text(title)
                    .font(SettingsType.paneTitle)
                    .kerning(SettingsType.paneTitleKerning)
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
    let softwareUpdates: SoftwareUpdateControlling
    /// KTD12: names each provider whose effective interval exceeds the chosen one; nil
    /// while every promise is kept (R10).
    let cadenceSentence: String?
    let onIntervalChange: (Int) -> Void
    let onLaunchAtLoginChange: (Bool) -> Void
    let onSendFeedback: () async -> FeedbackMail.Outcome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = BenchCounters.hit("GeneralSettingsPane")
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
                SoftwareUpdatesTile(softwareUpdates: softwareUpdates)
            }

            AboutSettingsTile(onSendFeedback: onSendFeedback)
        }
    }
}

/// The Updates tile, carried by both General and About over the same bindings: the two
/// Sparkle preferences, then "Check for Updates…" beside when Sparkle last looked. The
/// version lives in the sidebar stamp and About's header, so this row doesn't repeat it.
struct SoftwareUpdatesTile: View {
    let softwareUpdates: SoftwareUpdateControlling
    private var automaticChecks: Binding<Bool> {
        Binding(
            get: { softwareUpdates.automaticallyChecksForUpdates },
            set: { softwareUpdates.automaticallyChecksForUpdates = $0 }
        )
    }

    private var automaticDownloads: Binding<Bool> {
        Binding(
            get: { softwareUpdates.automaticallyDownloadsUpdates },
            set: { softwareUpdates.automaticallyDownloadsUpdates = $0 }
        )
    }

    var body: some View {
        SettingsTile("Updates") {
            SettingsSwitchRow(title: "Automatically check for updates", isOn: automaticChecks)
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsSwitchRow(title: "Download and install updates automatically", isOn: automaticDownloads)
                SettingsHelpText(text: "Installs when you quit Headroom.")
            }
            // Sparkle only downloads on its own background checks, so with those off this
            // switch could never act. Dimmed rather than hidden, so the dependency is visible.
            .disabled(!softwareUpdates.automaticallyChecksForUpdates || !softwareUpdates.allowsAutomaticUpdates)

            checkRow
        }
    }

    private var checkRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button("Check for Updates…") {
                softwareUpdates.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!softwareUpdates.presentation.canCheckForUpdates)
            Spacer(minLength: 12)
            // Sparkle's date isn't observable, so the line re-reads it on a slow tick and
            // picks up a check made while the pane is open.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                if let lastChecked = softwareUpdates.lastUpdateCheckDate {
                    Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                        .font(SettingsType.help)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
    @Binding var accountTitleInk: AccountTitleInk
    @Binding var accountLayout: AccountLayout
    @Binding var showCodexSparkCountersInApp: Bool
    let onAppearanceChange: (AppearancePreference) -> Void
    let onMeterStyleChange: (MeterStyle) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = BenchCounters.hit("AppearanceSettingsPane")
        SettingsPaneScaffold(SettingsPane.appearance.label) {
            // R6: sits on the pane background above the tiles, not inside one — it is
            // the subject of the pane, not another setting.
            AppearanceSpecimen(
                meterStyle: meterStyle,
                percentageMode: usagePercentageMode,
                accountTitleInk: accountTitleInk,
                accountLayout: accountLayout
            )

            SettingsTile("Theme") {
                ThemeThumbnailPicker(selection: $appearancePreference)
                    .onChange(of: appearancePreference) { _, newValue in
                        onAppearanceChange(newValue)
                    }
            }

            // L12B: every row is a swatch grid now, so the tile takes its full width.
            MeterStyleTile(meterStyle: meterStyle) { newStyle in
                // MS1 (2026-09-25 motion audit): one transaction for the whole pane. The
                // specimen's height scope reached only its hidden twin, so the visible well,
                // the Tube note, and every tile below it snapped while the card crossfaded.
                // The card's crossfade and the swatch plate keep their own inner scopes.
                withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion)) {
                    meterStyle = newStyle
                }
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
                accountLayout: $accountLayout,
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
    /// PS3: a switched-off provider's card links to Settings → Accounts, where its switch
    /// lives. `SettingsView` owns the sidebar selection, so it hands the switch down.
    var onOpenAccounts: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// PC2: the card under the pointer, which shows its move carets and lifts its × to
    /// secondary ink.
    @State private var hoveredCard: ProviderID?
    /// PC2: the caret holding keyboard focus. A focused caret shows without the pointer, so
    /// Full Keyboard Access never tabs onto an invisible control.
    @FocusState private var focusedCaret: CaretSlot?

    private struct CaretSlot: Hashable {
        let id: ProviderID
        let offset: Int
    }

    private var isAuto: Bool { store.menuBarFillSource == .auto }
    private var selected: [ProviderID] { store.selectedMenuBarProviders }
    /// Every other registered provider, switched-off ones included (PS3: dimmed, not hidden).
    private var notShown: [ProviderID] {
        store.registeredProviderOrder.filter { !selected.contains($0) }
    }

    var body: some View {
        let _ = BenchCounters.hit("MenuBarSettingsPane")
        // The specimen stays in view while the editor scrolls at the window's resize floor.
        VStack(alignment: .leading, spacing: SettingsMetrics.headerToContent) {
            Text(SettingsPane.menuBar.label)
                .font(SettingsType.paneTitle)
                .kerning(SettingsType.paneTitleKerning)
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
                        SettingsHelpText(text: "Uses each provider’s main account. Removing a pill keeps its account connected.")
                        if !isAuto {
                            Button("Use one automatic summary pill instead…") {
                                animatingPills { store.setMenuBarFillSource(.auto) }
                            }
                            .buttonStyle(.link)
                            .font(SettingsType.help)
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
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
            HStack(alignment: .firstTextBaseline) {
                SettingsGroupLabel("Menu bar preview")
                Spacer(minLength: 8)
                Text(store.menuBarFillSource == .auto ? "Automatic summary" : selected.count == 1 ? "1 pill" : "\(selected.count) pills")
                    .font(SettingsType.help)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack {
                    Spacer(minLength: 0)
                    // No invisible percentage-on twin: seeing the width shrink is the
                    // point of the compact choice. Always use the production renderer.
                    // MS2 (2026-09-25 motion audit): the old and new pill crossfade in place,
                    // trailing-aligned, so a pill edit no longer hard-swaps the strip while
                    // the cards below it glide.
                    ZStack(alignment: .trailing) {
                        MenuBarPreviewPill(meters: store.menuBarMeters, showsPercentage: store.showMenuBarPercentage)
                            .id(MenuBarPreviewKey(meters: store.menuBarMeters, showsPercentage: store.showMenuBarPercentage))
                            .transition(.opacity)
                    }
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                        value: MenuBarPreviewKey(meters: store.menuBarMeters, showsPercentage: store.showMenuBarPercentage)
                    )
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
        VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
            SettingsGroupLabel("Display")
            // The Appearance swatch grid: fixed 150pt columns, not the tile's full width.
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(150), spacing: 8, alignment: .leading), count: 2),
                alignment: .leading,
                spacing: 8
            ) {
                displayChoice(showsPercentage: true, title: "Pills + percentages", detail: "Exact usage at a glance")
                displayChoice(showsPercentage: false, title: "Pills only", detail: "Save menu bar space")
            }
            // SM1: the selection plate slides between the two treatments.
            .settingsSelectionGroup(value: store.showMenuBarPercentage)
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
            // well, 5pt, a centered swatch label, 5pt padding so the r11 ring stays concentric.
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
                    .font(SettingsType.swatchLabel)
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

    private var arranger: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsGroupLabel("In your menu bar")
                if isAuto {
                    SettingsHelpText(text: "Drag a provider up to give it its own pill.")
                } else {
                    SettingsHelpText(text: "Drag to arrange. Click a card’s value to change what its pill shows.")
                }
            }
            MenuBarPillArranger(
                shown: selected,
                notShown: notShown,
                canonicalOrder: store.registeredProviderOrder,
                canDrag: { store.providerOrder.contains($0) },
                menuBarMessage: menuBarMessage,
                notShownCaption: "Not shown",
                notShownHelp: isAuto
                    ? "Each value sets what the summary follows for that provider."
                    : "Drag one up, or press +.",
                onCommit: commit,
                card: { id, presentation in providerCard(id, presentation: presentation) }
            )
            // The arranger lifts a picked-up card past its own bounds, so nothing clips it.
            .padding(1)
        }
    }

    /// The menu bar well's own text when it holds no cards.
    private var menuBarMessage: (title: String?, detail: String)? {
        if isAuto {
            return ("One automatic summary pill", "Follows whichever provider is closest to its limit.")
        }
        if selected.isEmpty {
            return (nil, "Your pills’ providers are switched off. Drag one up from below, or turn one on in Accounts.")
        }
        return nil
    }

    private func commit(_ commit: PillShelfCommit) {
        switch commit {
        case .none: break
        case .move(let id, let target): store.moveMenuBarProvider(id, before: target)
        case .add(let id, let target): store.addMenuBarProvider(id, before: target)
        case .remove(let id): store.removeMenuBarProvider(id)
        }
    }

    /// SM3: every pill edit — arrows, remove, add — runs on the account list's reorder
    /// spring, so the cards slide into their new slots instead of re-laying out in one frame.
    private func animatingPills(_ change: () -> Void) {
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion), change)
    }

    /// `presentation` is the row whose form this card takes. It is the provider's row, except
    /// that a dropped card takes its drop row's form as soon as it is let go (PS8).
    @ViewBuilder private func providerCard(_ id: ProviderID, presentation: PillShelf) -> some View {
        if store.providerOrder.contains(id) {
            pillCard(id, inMenuBar: presentation == .menuBar)
        } else {
            offCard(id)
        }
    }

    // MARK: Cards

    /// PS6 (Kyle, 2026-09-24): one card for both rows, not a shelf card swapped for a pill
    /// card. Swapping built a new view on every row change, so the card replaced itself
    /// instead of changing. The pill and the name stay put and only the row's action trades
    /// places: × in the menu bar, + on the shelf.
    ///
    /// PC2 (Kyle, 2026-09-25): three bands, one job each — who (mark and name, leading), the
    /// pill alone in the middle, and what it follows (the value pull-down across the foot).
    /// The old five centred rows hung the mark off the name's left and the chevrons off the
    /// value's right, a zig-zag down a 100pt card. The value shows on the shelf too, as a
    /// working menu, so a card reads the same in both rows and a pill's value can be chosen
    /// before it is added. The grip went (the whole card drags) and the move arrows became
    /// carets in the pill's empty flanks, shown on hover.
    private func pillCard(_ id: ProviderID, inMenuBar: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let hovered = hoveredCard == id
        return VStack(spacing: 0) {
            cardHeader(id, dimmed: !inMenuBar)
            cardBody {
                cardPill(id)
                    .opacity(inMenuBar ? 1 : 0.75)
            }
            .overlay {
                if inMenuBar {
                    HStack(spacing: 0) {
                        caret(id, offset: -1, visible: hovered)
                        Spacer(minLength: 0)
                        caret(id, offset: 1, visible: hovered)
                    }
                    // Out through the card's 9pt padding to 1pt from its edge.
                    .padding(.horizontal, -(Self.cardInset - 1))
                    .offset(y: Self.pillDrop / 2)
                }
            }
            PillValueMenu(store: store, id: id, name: name(id), dimmed: !inMenuBar)
                .padding(.horizontal, -(Self.cardInset - Self.trayInset))
        }
        .padding([.top, .horizontal], Self.cardInset)
        .padding(.bottom, Self.trayInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            Group {
                if inMenuBar {
                    Button {
                        hoveredCard = nil
                        animatingPills { store.removeMenuBarProvider(id) }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(selected.count == 1)
                    .help(selected.count == 1 ? "Keep one pill, or choose the automatic summary below" : "Remove \(name(id)) pill")
                    .accessibilityLabel("Remove \(name(id)) pill")
                    .transition(cardPartTransition)
                } else {
                    Button {
                        animatingPills { store.addMenuBarProvider(id) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add \(name(id)) pill")
                    .accessibilityLabel("Add \(name(id)) pill")
                    .transition(cardPartTransition)
                }
            }
            .buttonStyle(PillCardChipStyle(quiet: !hovered))
            .padding(.top, Self.cardInset - 1)
            .padding(.trailing, Self.actionTrailingInset)
        }
        .background {
            // Both surfaces are always there and trade opacity, so the card's material
            // crossfades with the morph instead of being replaced.
            ZStack {
                // PS7: one opaque base under both, never faded. Two translucent layers
                // crossing at 50% each let the well show through mid-morph — a flash.
                shape.fill(Color(nsColor: .windowBackgroundColor))
                // SM3: a raised card rather than a hairline outline — something you can pick
                // up reads as an object, and a lifted card must hide what it passes over.
                Color.clear
                    .raisedTile(cornerRadius: 11, surface: .opaque)
                    .opacity(inMenuBar ? 1 : 0)
                // PS1: the shelf's flatter card.
                Color.clear
                    .shelfCardSurface(dark: colorScheme == .dark)
                    .opacity(inMenuBar ? 0 : 1)
            }
        }
        .contentShape(shape)
        .onHover { inside in
            withAnimation(HeadroomMotion.resolved(
                inside ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut, .crossfade, reduceMotion: reduceMotion
            )) {
                hoveredCard = inside ? id : (hoveredCard == id ? nil : hoveredCard)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(inMenuBar ? "\(name(id)) menu bar pill" : "\(name(id)), not in the menu bar")
        // PC2: the carets only appear under the pointer, so VoiceOver moves through actions.
        .accessibilityActions {
            if inMenuBar {
                if selected.first != id {
                    Button("Move \(name(id)) left") { animatingPills { store.moveMenuBarProvider(id, by: -1) } }
                }
                if selected.last != id {
                    Button("Move \(name(id)) right") { animatingPills { store.moveMenuBarProvider(id, by: 1) } }
                }
            }
        }
    }

    /// PS6: a card part arriving comes in a beat behind the card's growth, out of a 97% scale
    /// and a slight blur so it resolves rather than pops; one leaving fades out quickly. MB1:
    /// both on their own short tokens and a 1.5pt blur, so the switch never lingers soft.
    /// Under Reduce Motion both are plain crossfades (S2A).
    private var cardPartTransition: AnyTransition {
        let arriving: AnyTransition = reduceMotion
            ? .opacity
            : .opacity
                .combined(with: .scale(scale: 0.97))
                .combined(with: .modifier(active: PartBlur(radius: 1.5), identity: PartBlur(radius: 0)))
        return .asymmetric(
            insertion: arriving.animation(HeadroomMotion.partIn),
            removal: .opacity.animation(HeadroomMotion.partOut)
        )
    }

    /// A provider that is switched off. It cannot be picked up; the whole card opens
    /// Accounts, where its switch lives. PC2: the same three bands as `pillCard`, with
    /// "Off ›" in the value's place, so it sits at its neighbours' height.
    private func offCard(_ id: ProviderID) -> some View {
        Button(action: onOpenAccounts) {
            VStack(spacing: 0) {
                cardHeader(id, dimmed: true)
                cardBody {
                    cardPill(id)
                        .opacity(0.35)
                }
                HStack(spacing: 3) {
                    Text("Off")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                }
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: PillValueTrayStyle.height)
            }
            .padding([.top, .horizontal], Self.cardInset)
            .padding(.bottom, Self.trayInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .shelfCardSurface(dark: colorScheme == .dark)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(SettingsCopy.providerOffNotice). Turn it on in Accounts.")
        .accessibilityLabel("\(name(id)) is off")
        .accessibilityHint("Opens Accounts, where you can turn it on.")
    }

    // MARK: Card metrics (PC2)

    /// The card's padding on its top and sides; the mark's ink starts here.
    private static let cardInset: CGFloat = 9
    /// The footer tray's inset from the card edge. With the card's 11pt radius it gives the
    /// tray's 8 (`PillValueTrayStyle.cornerRadius`), so the two corners nest.
    private static let trayInset: CGFloat = 3
    /// The ×/+ chip is 18pt with ~8pt of ink; pulled out so its ink ends on `cardInset`.
    private static let actionTrailingInset: CGFloat = 4
    /// The header's trailing room for that floating chip's ink plus a 2pt gap.
    private static let actionReserve: CGFloat = 10
    /// The pill band: 10 above the pill, the 25pt pill, 8 below.
    private static let bodyHeight: CGFloat = 43
    /// The pill sits this far below the band's centre, evening the space above it against
    /// the header's own descender room, so it reads centred between header and footer.
    private static let pillDrop: CGFloat = 2

    private func cardHeader(_ id: ProviderID, dimmed: Bool) -> some View {
        // The mark hugs its ink, so this 4 is the whole gap for every provider.
        HStack(spacing: 4) {
            ProviderLogoView(providerID: id, size: 12, hugsInk: true)
            Text(name(id))
                .font(SettingsType.help.weight(.semibold))
                .foregroundStyle(dimmed ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .padding(.trailing, Self.actionReserve)
        .help(name(id))
    }

    private func cardBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.top, Self.pillDrop)
            .frame(maxWidth: .infinity)
            .frame(height: Self.bodyHeight)
    }

    private func cardPill(_ id: ProviderID) -> some View {
        MenuBarPreviewPill(meters: [store.providerMenuBarMeter(for: id)], showsPercentage: store.showMenuBarPercentage)
            .frame(height: 25)
    }

    /// PC2: a move caret in the pill's flank. Always laid out so the pill never shifts; shown
    /// while the card is hovered or the caret has keyboard focus, and disabled — out of the
    /// focus chain as well as out of sight — where the card has nowhere to go.
    @ViewBuilder private func caret(_ id: ProviderID, offset: Int, visible: Bool) -> some View {
        let direction = offset < 0 ? "left" : "right"
        let canMove = offset < 0 ? selected.first != id : selected.last != id
        let slot = CaretSlot(id: id, offset: offset)
        let shown = canMove && (visible || focusedCaret == slot)
        Button {
            // The card slides out from under a still pointer, and onHover only fires on the
            // next pointer move, so drop the hover rather than leave carets on a card that left.
            hoveredCard = nil
            animatingPills { store.moveMenuBarProvider(id, by: offset) }
        } label: {
            Image(systemName: "chevron.\(direction)")
        }
        .buttonStyle(PillCaretStyle())
        .disabled(!canMove)
        .focused($focusedCaret, equals: slot)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .help("Move \(name(id)) \(direction)")
        .accessibilityHidden(true)
    }

    private func name(_ id: ProviderID) -> String {
        store.displayNames[id] ?? id.raw.capitalized
    }
}

/// PS6: the blur half of `cardPartTransition`. Animatable, so the radius eases with the
/// fade instead of popping to its end state.
private struct PartBlur: ViewModifier, @preconcurrency Animatable {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

// MARK: - Widgets & iPhone

struct WidgetsSettingsPane: View {
    let store: UsageStore
    /// R16: which style the specimen previews. Held by `SettingsView` (panes are stateless).
    @Binding var previewStyle: WidgetLayoutStyle
    @Binding var widgetsEnabled: Bool
    @Binding var showCodexSparkCountersInWidgets: Bool
    @Binding var syncToIPhoneEnabled: Bool
    var body: some View {
        let _ = BenchCounters.hit("WidgetsSettingsPane")
        SettingsPaneScaffold(SettingsPane.widgets.label) {
            // L9P: sits on the pane background above the tile, like the Appearance
            // specimen — it is the subject of the pane, not another setting.
            WidgetPreviewStrip(widgetsEnabled: widgetsEnabled, style: previewStyle)

            // R16/KTD13: the styles a widget can take, previewed above. Choosing one here
            // changes the preview only; each widget picks its style in Edit Widget.
            SettingsTile("Widget style") {
                WidgetStyleGalleryPicker(selection: $previewStyle)
            }

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
        let _ = BenchCounters.hit("AccountsSettingsPane")
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
        let _ = BenchCounters.hit("APISpendSettingsPane")
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

        VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: surface.providerID, size: 15)
                    SettingsGroupLabel(surface.displayName)
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
            VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                if store.isSurfaceEnabled(surface) {
                    // SL1: the editor and the configured row overlap for their swap instead of
                    // stacking, so saving a key no longer grows the tile by both for 200ms.
                    ZStack(alignment: .topLeading) {
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
                    .transition(.settingsReveal(reduceMotion: reduceMotion))
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
        // R2M7/S2A → RM1: the scopes are `.movement`, so under Reduce Motion the tile's height
        // snaps; the editor⇄configured swap keeps its fade because
        // `settingsReveal(reduceMotion:)` carries its own `settle` there. Outside Reduce
        // Motion the reveal's rise and blur ride these scopes as before.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
            value: savedKeyProviders
        )
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
            value: replacingKeyProviders
        )
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
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
                .font(SettingsType.help)
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
            Text(title).font(SettingsType.help).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsHelpText(text: guidance.text)
                Link(guidance.linkLabel, destination: guidance.url)
                    .font(SettingsType.help)
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

/// MS2: what the Menu Bar pane's preview strip shows, so a change to it crossfades.
/// `MenuBarMeter` is Equatable but not Hashable, and `.id` needs Hashable, so the meters are
/// keyed by their value description, which changes exactly when what they draw does.
private struct MenuBarPreviewKey: Hashable {
    let meters: String
    let showsPercentage: Bool

    init(meters: [MenuBarMeter], showsPercentage: Bool) {
        self.meters = String(describing: meters)
        self.showsPercentage = showsPercentage
    }
}

// MARK: - About

/// The combined General pane preserves About's copy and destinations without repeating
/// the sidebar's large app mark. Uses the same tile and link rows as the other settings.
private struct AboutSettingsTile: View {
    let onSendFeedback: () async -> FeedbackMail.Outcome

    /// The feedback row's trailing text while its email is being prepared or was copied.
    @State private var feedbackStatus: String?

    var body: some View {
        SettingsTile("About Headroom", titleAccessory: {
            Spacer(minLength: 12)
            if let version = AppVersionLabel.plain {
                Text("Version \(version)")
                    .font(SettingsType.help.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }) {
            SettingsHelpText(text: AboutLinks.tagline)

            VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                SettingsGroupLabel("Support")
                VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Feedback plan R1: reading CLI versions takes a second or two, so the
                        // row says so; a webmail user gets the email on the clipboard instead.
                        SettingsOutboundRow(
                            title: "Send Feedback",
                            destination: feedbackStatus ?? "Email",
                            help: FeedbackEmail.address,
                            accessibilityHint: "Opens an email in your mail app"
                        ) {
                            guard feedbackStatus == nil else { return }
                            feedbackStatus = "Opening…"
                            Task {
                                let outcome = await onSendFeedback()
                                feedbackStatus = outcome == .copied ? "Email copied" : nil
                                guard outcome == .copied else { return }
                                try? await Task.sleep(for: .seconds(4))
                                feedbackStatus = nil
                            }
                        }
                        // Webmail users have no mail app to open; the address is selectable so
                        // they can copy it.
                        SettingsHelpText(text: "Opens your default email app. Or email \(FeedbackEmail.address).")
                            .textSelection(.enabled)
                            .padding(.bottom, 8)
                        Divider()
                        SettingsLinkRow(link: AboutLinks.tipJar)
                    }
                    SettingsHelpText(text: AboutLinks.tipJarNote)
                }
            }

            VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                SettingsGroupLabel("Made by \(AboutLinks.makerName)")
                SettingsLinkList(links: AboutLinks.maker)
            }
        }
    }
}

/// Outbound link rows separated by hairlines: title on the leading edge, destination and an
/// arrow on the trailing edge, the same label-left/control-right grammar as every other row.
struct SettingsLinkList: View {
    let links: [AboutLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(links) { link in
                if link.id != links.first?.id {
                    Divider()
                }
                SettingsLinkRow(link: link)
            }
        }
    }
}

private struct SettingsLinkRow: View {
    let link: AboutLink

    var body: some View {
        SettingsOutboundRow(
            title: link.title,
            destination: link.destination,
            help: link.url.absoluteString,
            accessibilityHint: "Opens in your browser"
        ) {
            NSWorkspace.shared.open(link.url)
        }
    }
}

/// The About rows' one look: title on the leading edge, destination and an outbound arrow on
/// the trailing edge, brightening on hover. Every row leaves Headroom, for the browser or the
/// user's mail app.
private struct SettingsOutboundRow: View {
    let title: String
    let destination: String
    let help: String
    let accessibilityHint: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(destination)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(isHovered ? .primary : .secondary)
                .lineLimit(1)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(destination)")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isLink)
    }
}
