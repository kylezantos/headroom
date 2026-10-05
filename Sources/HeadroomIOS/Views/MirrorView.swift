import SwiftUI

/// The usage screen (U8): one card per provider from the resolved companion snapshot (KTD6),
/// every account stacked inside, at the popover's proportions one Dynamic Type step up (KTD3).
struct MirrorView: View {
    let content: CompanionResolvedContent
    let isDemoMode: Bool
    /// KTD21: Explore Demo keeps a neutral banner; a `--demo` screenshot launch hides it.
    let showsDemoBanner: Bool
    let canExitDemo: Bool
    let demoWidgetUnavailable: Bool
    let onExitDemo: () -> Void
    var onRefresh: () async -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// KTD3: the phone's one Dynamic Type unit over the popover ramp. Every shared row, gap
    /// and reservation on this screen multiplies by it.
    @ScaledMetric(relativeTo: .body) private var phoneScale: CGFloat = PhoneScale.defaultFactor
    private var scale: CGFloat { PhoneScale.clamped(phoneScale) }
    /// KTD16: shown from the first frame when the launch's entrance has already played.
    @State private var cardsShown = PhoneLaunchEntrance.shared.hasPlayed
    @State private var disclosedTitle: DisclosedTitle?

    /// The approved mock's screen rhythm (U1-B): 20pt side margins and 20pt between tiles.
    private static let sideMargin: CGFloat = 20
    private static let tileGap: CGFloat = 20

    var body: some View {
        // KTD11: U12's one store ("Match my Mac" or the phone's override). It is observable,
        // so a Settings change re-renders the cards.
        let display = PhoneDemoMeterStyle.applied(to: PhoneDisplayPreferencesStore.app.resolve(mac: content.display))
        // A per-minute `now` so "Updated N min ago" and the reset countdowns tick without a
        // data poll — same pattern the Mac popover uses.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView {
                VStack(spacing: Self.tileGap) {
                    if showsDemoBanner {
                        DemoModeBanner(
                            canExitDemo: canExitDemo,
                            widgetUnavailable: demoWidgetUnavailable,
                            onExitDemo: onExitDemo
                        )
                    }
                    if content.providers.isEmpty && content.apiSpend.isEmpty {
                        emptyLine
                    }
                    cards(context(display: display, now: timeline.date))
                    if !content.apiSpend.isEmpty {
                        APISpendMirrorView(summaries: content.apiSpend, now: timeline.date)
                            .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
                            .phoneCardEntrance(isShown: cardsShown, accountsBefore: accountCount)
                    }
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Self.sideMargin)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .refreshable { await onRefresh() }
            // Native large title + subtitle (iOS 26): "Usage" is the screen title and
            // collapses into the bar on scroll; the freshness stamp rides along as the
            // subtitle instead of a hand-built header.
            .navigationTitle("Usage")
            .navigationSubtitle(updatedText(now: timeline.date))
            .navigationBarTitleDisplayMode(.large)
        }
        .environment(\.accountTitleInk, display.accountTitleInk)
        .sheet(item: $disclosedTitle) { disclosed in
            PhoneTitleDisclosureSheet(disclosed: disclosed)
        }
        .onAppear(perform: startEntranceIfNeeded)
        #if DEBUG
        .overlay(alignment: .topLeading) { PhoneEntranceMarker() }
        #endif
    }

    private func context(display: ResolvedPhoneDisplay, now: Date) -> PhoneCardContext {
        PhoneCardContext(
            display: display,
            usesAccountRows: CompanionCardPresentation.usesAccountRows(content.providers),
            widgetProviderIDs: CompanionCardPresentation.widgetProviderIDs(content),
            ladder: content.ladder,
            surfaceDimmed: CompanionFreshnessRule.isDimmed(content.freshness, surface: .app, at: now),
            now: now,
            scale: scale,
            onTruncatedTitle: { disclosedTitle = $0 }
        )
    }

    @ViewBuilder
    private func cards(_ context: PhoneCardContext) -> some View {
        let offsets = accountOffsets
        if horizontalSizeClass == .regular && content.providers.count > 1 {
            LazyVGrid(columns: providerColumns, alignment: .center, spacing: Self.tileGap) {
                ForEach(Array(content.providers.enumerated()), id: \.element.id) { index, provider in
                    PhoneProviderCard(provider: provider, context: context)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .phoneCardEntrance(isShown: cardsShown, accountsBefore: offsets[index])
                }
            }
        } else {
            ForEach(Array(content.providers.enumerated()), id: \.element.id) { index, provider in
                PhoneProviderCard(provider: provider, context: context)
                    .phoneCardEntrance(isShown: cardsShown, accountsBefore: offsets[index])
            }
        }
    }

    /// KTD16: each card's stagger counts the accounts above it, capped after the eighth.
    private var accountOffsets: [Int] {
        var running = 0
        return content.providers.map { provider in
            defer { running += max(1, provider.accounts.count) }
            return running
        }
    }

    private var accountCount: Int {
        content.providers.reduce(0) { $0 + max(1, $1.accounts.count) }
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
            .accessibilityIdentifier("headroom.empty")
    }

    private var providerColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 280), spacing: Self.tileGap, alignment: .top),
            GridItem(.flexible(minimum: 280), spacing: Self.tileGap, alignment: .top),
        ]
    }

    private func updatedText(now: Date) -> String {
        if isDemoMode && showsDemoBanner { return "Sample data · No account connected" }
        if let updated = MirrorPresentation.updatedLabel(generatedAt: content.generatedAt, now: now) {
            return "Updated \(updated)"
        }
        return "Latest Mac snapshot"
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IdentityCapsuleStyle.metadataFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(widgetUnavailable
            ? "Demo Mode. Sample data. Widgets could not join Demo Mode on this install."
            : "Demo Mode. Sample data. No accounts are connected.")
        .accessibilityIdentifier("headroom.demo.banner")
    }
}

#if DEBUG
/// KTD16 UI-test marker: how many times the card entrance has started this launch. Invisible,
/// DEBUG-only; the test reads it to prove a data refresh never replays the entrance.
private struct PhoneEntranceMarker: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("Card entrance")
            .accessibilityValue("\(PhoneLaunchEntrance.shared.playCount)")
            .accessibilityIdentifier("headroom.entrance")
    }
}
#endif
