import SwiftUI

/// The usage screen (U8): one card per provider from the resolved companion snapshot (KTD6),
/// every account stacked inside, at the popover's proportions one Dynamic Type step up (KTD3).
/// U21 adds the freshness line, whole-surface dimming, past-reset rows, the old-Mac line and
/// the shared spend rows; U9 the pull-to-check-now line; U11 the flowing columns.
struct MirrorView: View {
    let content: CompanionResolvedContent
    let isDemoMode: Bool
    /// KTD21: Explore Demo keeps a neutral banner; a `--demo` screenshot launch hides it.
    let showsDemoBanner: Bool
    let canExitDemo: Bool
    let demoWidgetUnavailable: Bool
    let checkNow: PhoneCheckNow
    let onExitDemo: () -> Void
    /// U9: pull to refresh and ⌘R. Writes the request (or starts the demo replay) and returns
    /// at once; an older Mac re-reads instead.
    var onCheckNow: () async -> Void
    var onSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// KTD3: the phone's one Dynamic Type unit over the popover ramp. Every shared row, gap
    /// and reservation on this screen multiplies by it.
    @ScaledMetric(relativeTo: .body) private var phoneScale: CGFloat = PhoneScale.defaultFactor
    private var scale: CGFloat { PhoneScale.clamped(phoneScale) }
    /// KTD16 (kept, CA-M5): shown from the first frame when the launch's entrance has played.
    @State private var cardsShown = PhoneLaunchEntrance.shared.hasPlayed
    @State private var disclosedTitle: DisclosedTitle?

    /// The approved mock's screen rhythm (U1-B): 20pt side margins and 20pt between tiles.
    private static let sideMargin: CGFloat = 20
    private static let tileGap: CGFloat = 20
    /// CA-I2 (IOS-02 mock): the dimmed sentence sits 12pt above the first card.
    private static let dimmedLineToCards: CGFloat = 12

    /// KTD17: the phone keeps its 20pt margins; a regular-width window takes the iPad mock's 28.
    private var margin: CGFloat {
        horizontalSizeClass == .regular ? FlowingColumnsMetrics.defaultMargin : Self.sideMargin
    }

    var body: some View {
        // KTD11: U12's one store ("Match my Mac" or the phone's override). It is observable,
        // so a Settings change re-renders the cards.
        let display = PhoneDemoMeterStyle.applied(to: PhoneDisplayPreferencesStore.app.resolve(mac: content.display))
        // A per-minute `now` so "Updated N min ago", the reset countdowns, the dim moment and
        // the past-reset moment tick without a data poll — same pattern the Mac popover uses.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let context = context(display: display, now: timeline.date)
            let freshness = self.freshness(display: display, now: timeline.date)
            ScrollView {
                VStack(spacing: Self.tileGap) {
                    if let sentence = freshness.sentence {
                        // CA-I2: the whole dimmed sentence, time included, on its own line in
                        // `UpdateMacLine`'s form, 12pt above the first card. The header slot
                        // keeps only "Last update <time>".
                        UpdateMacLine(text: sentence, scale: scale, identifier: "headroom.dimmed-line")
                            .padding(.horizontal, margin)
                            .padding(.bottom, Self.dimmedLineToCards - Self.tileGap)
                    }
                    if showsDemoBanner {
                        DemoModeBanner(
                            canExitDemo: canExitDemo,
                            widgetUnavailable: demoWidgetUnavailable,
                            onExitDemo: onExitDemo
                        )
                        .padding(.horizontal, margin)
                    }
                    if let line = CompanionCardPresentation.compatibilityLine(content) {
                        UpdateMacLine(text: line, scale: scale)
                            .padding(.horizontal, margin)
                    }
                    if content.providers.isEmpty && content.apiSpend.isEmpty {
                        emptyLine
                    }
                    cards(context)
                }
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
            .scrollContentBackground(.hidden)
            // U9: returns as soon as the request is written, so the system spinner leaves and
            // the toolbar carries the Mac's progress.
            .refreshable { await onCheckNow() }
            .navigationTitle("Usage")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Native toolbar hosting freezes the loading timeline between receipt
                // updates. A screen-owned header keeps the desktop vessel clock live.
                PhoneScreenHeader(title: "Usage", margin: margin, onSettings: onSettings) {
                    statusLine(freshness: freshness)
                }
            }
            .background { checkNowShortcut }
        }
        .environment(\.accountTitleInk, display.accountTitleInk)
        .sheet(item: $disclosedTitle) { disclosed in
            PhoneTitleDisclosureSheet(disclosed: disclosed)
        }
        .onAppear(perform: startEntranceIfNeeded)
        #if DEBUG
        .overlay(alignment: .topLeading) { PhoneEntranceMarker(checkNow: checkNow) }
        #endif
    }

    private func context(display: ResolvedPhoneDisplay, now: Date) -> PhoneCardContext {
        PhoneCardContext(
            display: display,
            usesAccountRows: CompanionCardPresentation.usesAccountRows(content.providers),
            ladder: content.ladder,
            surfaceDimmed: CompanionFreshnessRule.isDimmed(content.freshness, surface: .app, at: now),
            now: now,
            scale: scale,
            onTruncatedTitle: { disclosedTitle = $0 }
        )
    }

    /// R9/R10: the stamp over the windows on screen (the phone's Spark switch applied), or
    /// the dimmed sentence in its slot.
    private func freshness(display: ResolvedPhoneDisplay, now: Date) -> CompanionScreenFreshness {
        MirrorPresentation.freshness(
            content, shownWindows: { display.appWindows($0.windows).map(\.summary) }, now: now)
    }

    /// U9/U21: one slot. The check-now line while a request shows; otherwise the freshness
    /// line — or, in Explore Demo, the sample-data note that stands in for it.
    private func statusLine(freshness: CompanionScreenFreshness) -> some View {
        let resting = isDemoMode && showsDemoBanner ? "Sample data · No account connected" : freshness.headerText
        return CheckNowStatusLine(
            slot: checkNow.slot(at: Date()),
            restingText: resting,
            inFlightEndedAt: checkNow.inFlightEndedAt,
            requestedAt: checkNow.status?.askedAt,
            didUpdate: checkNow.status?.phase == .finished(notUpdated: 0),
            isDimmed: freshness.isDimmed
        )
    }

    /// U9: iPad's ⌘R runs the same action as the pull. Invisible; it only carries the shortcut.
    private var checkNowShortcut: some View {
        Button("Check Now") { Task { await onCheckNow() } }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// U11 (KTD17): provider cards, then the spend card, flow into columns on iPad and wide
    /// windows; a phone gets one column at its own margins. A card's ID changes with its
    /// account set, so adding an account re-plans while a height change keeps every column.
    /// VoiceOver reads provider order, then spend.
    private func cards(_ context: PhoneCardContext) -> some View {
        FlowingColumns(margin: margin, gap: Self.tileGap) {
            ForEach(Array(content.providers.enumerated()), id: \.element.id) { index, provider in
                PhoneProviderCard(provider: provider, context: context)
                    // CA-M5: one step per card above, capped at the fourth (KTD16 counted
                    // accounts up to the eighth).
                    .phoneCardEntrance(isShown: cardsShown, cardIndex: index)
                    .flowingColumnsCard(id: Self.columnsKey(provider))
            }
            if !content.apiSpend.isEmpty {
                PhoneSpendCard(summaries: content.apiSpend, surfaceDimmed: context.surfaceDimmed, scale: scale)
                    .phoneCardEntrance(isShown: cardsShown, cardIndex: content.providers.count)
                    .flowingColumnsCard(id: "spend")
            }
        }
    }

    static func columnsKey(_ provider: CompanionResolvedProvider) -> String {
        ([provider.id] + provider.accounts.map(\.id).sorted()).joined(separator: "|")
    }

    /// KTD16: the launch's one entrance. A screen built after it played (a demo switch, a
    /// status screen giving way to content) shows its cards at once.
    private func startEntranceIfNeeded() {
        guard !cardsShown else { return }
        _ = PhoneLaunchEntrance.shared.claim()
        cardsShown = true
    }

    /// M3: a Mac that tracks nothing gets a plain line, not a blank screen.
    private var emptyLine: some View {
        Text(CompanionCardCopy.noSubscriptions)
            .font(.system(size: StatusSentence.size * scale, weight: .medium))
            .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 48 * scale)
            .padding(.horizontal, margin)
            .accessibilityIdentifier("headroom.empty")
    }
}

/// The screen-owned header: a large title, the status slot and the 44pt glass gear on one
/// row. CA-I6: the status screens use it too, so a sync coming back never moves the title or
/// the gear (they used the native large title under a separate gear row).
struct PhoneScreenHeader<Status: View>: View {
    let title: String
    let margin: CGFloat
    let onSettings: () -> Void
    @ViewBuilder let status: () -> Status

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            status()
            PhoneSettingsButton(action: onSettings, usesHeaderStyle: true)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, margin)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// R14/AE1: an older Mac sends main accounts only; the line says what updating it adds, in
/// the cards' neutral status voice (P39/P40) with the same Mac glyph. CA-I2: the dimmed
/// "No update from your Mac since …" sentence uses the same line.
private struct UpdateMacLine: View {
    let text: String
    let scale: CGFloat
    var identifier = "headroom.update-mac"

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PhoneCardMetrics.statusGlyphGap * scale) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: PhoneCardMetrics.statusGlyphSize * scale, weight: .regular))
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                .accessibilityHidden(true)
            StatusSentence(text: text, severity: .attention, indented: false, scale: scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// KTD21/G5: Explore Demo's banner in the neutral chip style — no tint, no system blue.
private struct DemoModeBanner: View {
    let canExitDemo: Bool
    let widgetUnavailable: Bool
    let onExitDemo: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo Mode")
                    .font(.subheadline.weight(.semibold))
                Text(widgetUnavailable
                    ? "Sample data — widgets could not join Demo Mode"
                    : "Sample data — no accounts are connected")
                    .font(.caption)
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
            }
            Spacer(minLength: 8)
            if canExitDemo {
                Button("Exit", action: onExitDemo)
                    .accessibilityIdentifier("headroom.demo.exit")
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IdentityCapsuleStyle.metadataFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(widgetUnavailable
            ? "Demo Mode. Sample data. Widgets could not join Demo Mode on this install."
            : "Demo Mode. Sample data. No accounts are connected.")
        .accessibilityIdentifier("headroom.demo.banner")
    }
}

#if DEBUG
/// KTD16 UI-test marker: how many times the card entrance has started this launch. Invisible,
/// DEBUG-only; the test reads it to prove a data refresh never replays the entrance.
/// AE8: a second marker counts the check-now request keys this launch wrote, and AE1's third
/// the pulls that re-read instead.
private struct PhoneEntranceMarker: View {
    let checkNow: PhoneCheckNow

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Card entrance")
                .accessibilityValue("\(PhoneLaunchEntrance.shared.playCount)")
                .accessibilityIdentifier("headroom.entrance")
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Check-now requests written")
                .accessibilityValue("\(checkNow.requestsWritten)")
                .accessibilityIdentifier("headroom.checknow.writes")
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel("Check-now re-read pulls")
                .accessibilityValue("\(checkNow.rereadPulls)")
                .accessibilityIdentifier("headroom.checknow.rereads")
        }
    }
}
#endif
