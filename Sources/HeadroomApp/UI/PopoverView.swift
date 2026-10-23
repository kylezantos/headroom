#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import os
import HeadroomCore
#if canImport(HeadroomWidgetSharedUI)
import HeadroomWidgetSharedUI
#endif

/// The native popover (U7). Composes one card per provider on a system surface, a gear
/// that opens Settings, and a Quit control (required — the app has no Dock presence,
/// KTD9). Tahoe uses Liquid Glass; Sequoia falls back to native material. A
/// `TimelineView` drives a per-minute `now` so countdowns and "updated N min ago" tick
/// without a data poll.
struct PopoverView: View {
    @ObservedObject private var tuning = PopoverTuningModel.shared
    var store: UsageStore
    var onOpenSettings: () -> Void
    /// Render-harness only: `ImageRenderer` can't rasterize the Liquid Glass shell, so the
    /// marketing export forces the solid surface branch (a flat dark shell that also
    /// matches the design artboard). The live app leaves this off and keeps its glass.
    var forceSolidSurface: Bool = false
    /// Render-harness only: `ImageRenderer` does not run the geometry callback that
    /// normally measures the scroll stack. A fixed proposal keeps the marketing render
    /// from collapsing the cards to zero height.
    var forcedCardsHeight: CGFloat? = nil
    /// DialKit only: the pinned tuning copy has no MenuBarExtra host, so it keeps the shell.
    var isPinnedTuningCopy: Bool = false
    /// SQ1: set by the `MenuBarExtra` scene only, so harness windows (which pad and size the
    /// popover themselves) are never refitted. Acts only where `PopoverWindowHeightFitter` is
    /// enabled: before macOS 26.
    var fitsMenuBarWindowHeight: Bool = false

    @State private var popoverWindow: NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate
    /// L2A: live scroll geometry for the bottom feather and the bespoke gutter indicator.
    /// SC1 (2026-10-03 perf bench): held in a model that only those two child views read.
    /// As `@State` here, every scroll frame re-ran this whole body and rebuilt every card —
    /// ~40ms and 230 view bodies per scroll step at 20 accounts.
    @State private var scroll = PopoverScrollModel()
    /// Measured height of the card stack. `MenuBarExtra(.window)` sizes its window to the
    /// content's ideal height, and a `ScrollView` has no ideal height of its own — left to
    /// self-size it collapsed to zero and the popover opened at 127pt with no cards
    /// (`maxHeight` only sets a ceiling, never a floor). Measuring the stack and pinning an
    /// explicit height is what keeps the window honest; the cap still applies above it.
    @State private var cardsHeight: CGFloat = 0
    /// KTD3 / KTD10: the one- or two-column plan. Heights reach it outside observation; the
    /// body reads only the resolved plan.
    @State private var columns = PopoverPlanModel(cap: Double(PopoverCardMetrics.cardsHeightCap))
    /// R2M12: second-resolution "now" for the waiting clock, driven only while a handoff is
    /// open. The popover's own `TimelineView` ticks per minute, which is right for "Updated
    /// N min ago" and useless for "Waiting 45s".
    @State private var waitingClockNow: Date = .now
    /// SQ1: fits the window's height on macOS 15; inert on 26.
    @State private var heightFitter = PopoverWindowHeightFitter()

    private static let titleFont = NSFont.systemFont(ofSize: 20, weight: .bold)
    private static let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    var body: some View {
        let _ = BenchCounters.hit("PopoverView")
        // SQ1: a window shorter than the popover clips the card list, never the header.
        PopoverTopPinnedLayout(reportIdealHeight: idealHeightReport) { timeline }
    }

    /// SQ1: the fitter hears the content's ideal height only where it acts. Nil elsewhere keeps
    /// the root layout free of a closure, so it compares equal across body passes.
    private var idealHeightReport: (@Sendable (CGFloat) -> Void)? {
        guard fitsMenuBarWindowHeight, PopoverWindowHeightFitter.isEnabled else { return nil }
        return { [heightFitter] height in
            // `Layout.placeSubviews` is nonisolated but SwiftUI runs layout on the main thread.
            MainActor.assumeIsolated { heightFitter.report(height) }
        }
    }

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = pinnedDate ?? context.date
            let _ = BenchCounters.hit("PopoverView.timeline")
            let accountsByVisibleProvider = store.providerOrder.reduce(
                into: [ProviderID: [ProviderAccount]]()
            ) { accounts, providerID in
                accounts[providerID] = store.accounts(for: providerID)
            }
            let anyProviderMultiAccount = surfaceUsesAccountRows(
                accountsByProvider: accountsByVisibleProvider
            )
            // M7A: the card stack's identity is provider order *and* each provider's
            // account order, flattened. Make Main promotes a row inside one provider and
            // leaves `providerOrder` untouched, so keying on the provider list alone would
            // miss the only reorder this surface can actually show.
            let cardListIdentity = store.providerOrder.flatMap { id in
                (accountsByVisibleProvider[id] ?? []).map(\.key)
            }
            let entriesByProvider = store.providerOrder.reduce(
                into: [ProviderID: [ProviderAccountEntry]]()
            ) { entries, id in
                entries[id] = (accountsByVisibleProvider[id] ?? []).map { account in
                    ProviderAccountEntry(account: account, snapshot: store.appDisplaySnapshot(for: account.key))
                }
            }
            // R5: accounts in provider order, then Make Main order, then the spend card.
            let columnSlots = store.providerOrder.flatMap { id in
                ProviderCardView.columnSlots(
                    providerID: id,
                    entries: entriesByProvider[id] ?? [],
                    capabilityStatus: store.providerCapabilities[id],
                    accountLayout: store.accountLayout,
                    showsCodexSparkCounters: store.showCodexSparkCountersInApp
                )
            } + (store.apiSpendProviderOrder.isEmpty ? [] : [PopoverColumnSlot.spend])
            let columnPlan = columns.drawnPlan(
                for: columnSlots, allowsHorizontalExpansion: store.expandAccountsHorizontally
            )
            let fragments = PopoverCardFragment.fragments(slots: columnSlots, plan: columnPlan)
            // NB1 (2026-09-25 motion audit): what can change a card's height — each account's
            // freshness, its setup session, and its meter rows, the values the card's own
            // scopes key on. Those scopes reach only the card, so it grew on `valueSpring`
            // while the cards below it jumped to their final places and overlapped it or left
            // a gap.
            let cardLayoutSignature = PopoverCardLayoutSignature(
                freshness: store.providerOrder.flatMap { id in
                    (entriesByProvider[id] ?? []).map(\.snapshot.freshness)
                },
                sessions: store.providerOrder.flatMap { id in
                    (accountsByVisibleProvider[id] ?? []).map { providerCardSessionKey(SetupSessions.state(for: $0)) }
                },
                // A live poll can add or age out a meter row with freshness unchanged.
                rows: store.providerOrder.flatMap { id in
                    (entriesByProvider[id] ?? []).map { $0.snapshot.windows.map(\.kind) }
                }
            )
            VStack(spacing: tuning.values.cardGap) {
                header(now: now)
                    // Header sits 11pt above the first card (vs the 20pt tile gap) — the
                    // title belongs to the content below it more than cards belong to
                    // each other.
                    .padding(.bottom, tuning.values.headerGap - tuning.values.cardGap)
                // Cards scroll once many accounts push past a comfortable popover
                // height; below the cap the height tracks the measured stack, so the
                // common case is untouched. Header and footer stay pinned.
                ScrollView(.vertical) {
                    PopoverColumnsLayout(columnCount: columnPlan.columnCount, metrics: columnMetrics) {
                        ForEach(Array(fragments.enumerated()), id: \.element.id) { index, fragment in
                            Group {
                                if let id = fragment.providerID {
                                    cardFragment(
                                        fragment,
                                        providerID: id,
                                        entries: entriesByProvider[id] ?? [],
                                        anyProviderMultiAccount: anyProviderMultiAccount,
                                        now: now
                                    )
                                } else {
                                    APISpendSectionView(store: store, now: now, onOpenSettings: openSettingsDismissingPopover)
                                        // The planner counts content inside the card's 13pt padding.
                                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [columns] in
                                            columns.record(max($0 - 2 * tuning.values.cardPadding, 0), for: PopoverColumnSlot.spendID)
                                        }
                                        // S5A: the spend tile is a sibling card, so it arrives and
                                        // leaves the same way the provider cards above it do.
                                        .transition(.settingsReveal)
                                }
                            }
                            .layoutValue(key: PopoverColumn.self, value: fragment.column)
                            // VoiceOver reads down the first column, then the second (R5).
                            .accessibilitySortPriority(Double(fragments.count - index))
                        }
                    }
                    .accessibilityElement(children: .contain)
                    // M7A: the popover had no reorder animation at all, so a Make Main
                    // promotion teleported its card to the top. The stack's own layout change
                    // rides this scope. The measured `cardsHeight` below reports the final
                    // layout, not frame by frame, so the scroll frame and the window take
                    // their new height at once; only the cards inside move.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion),
                        value: cardListIdentity
                    )
                    // NB1: the neighbours ride the same spring as the card that resized.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                        value: cardLayoutSignature
                    )
                    // Scroll content is laid out at its ideal height regardless of the
                    // ScrollView's own frame, so this reports the true stack height even
                    // on the first pass while the frame below is still zero.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        BenchCounters.mark("cardsHeight=\($0)")
                        cardsHeight = $0
                    }
                }
                // L2A: the stock overlay scroller sat on the card border and painted a
                // near-black well over the card interior when it expanded. We hide it and
                // draw our own in the 19pt shell gutter instead (see `PopoverScrollIndicator`),
                // which also retires main's borrowed 10pt scroller gutter — the viewport
                // and the cards are the same width again.
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                // A soft fade while content continues past the bottom of the cap — the flat
                // clip alone read as a card with missing data (impeccable audit P2). Gated so
                // the common non-scrolling popover keeps its crisp last card edge.
                // TF2 (Kyle, 2026-09-24): the top has no fade. L3A's 14pt top feather was
                // shorter than a line of text, so a card passing under the header looked sliced
                // mid-glyph against the title rather than softened; Tahoe's soft scroll-edge
                // effect was tried in its place and dropped, because the header bar broke the
                // scroll range inside the MenuBarExtra window. Cards now pass cleanly under the
                // solid header.
                .onScrollGeometryChange(for: PopoverScrollMetrics.self) { geometry in
                    PopoverScrollMetrics(
                        offset: geometry.contentOffset.y,
                        viewport: geometry.containerSize.height,
                        content: geometry.contentSize.height
                    )
                } action: { _, metrics in
                    BenchCounters.mark("scrollMetrics(viewport=\(metrics.viewport),content=\(metrics.content))")
                    scroll.update(metrics)
                }
                // FA1: the feather animates its own opacity only (see `PopoverScrollFeather`).
                .mask { PopoverScrollFeather(model: scroll) }
                // Applied outside the mask so the indicator never feathers at the ends,
                // and outside the feather animations so its position tracks the scroll 1:1.
                .overlay(alignment: .topTrailing) { PopoverScrollIndicator(model: scroll) }
                // SQ1: the measured height is both ideal and ceiling, but the list may give up
                // height when the window is shorter than the popover (`PopoverTopPinnedLayout`), so
                // the header and footer stay whole. At its ideal height nothing changes.
                .frame(
                    minHeight: forcedCardsHeight ?? 0,
                    idealHeight: forcedCardsHeight ?? min(cardsHeight, PopoverCardMetrics.cardsHeightCap),
                    maxHeight: forcedCardsHeight ?? min(cardsHeight, PopoverCardMetrics.cardsHeightCap)
                )
                footer(now: now)
            }
            // M9C (Sep 2026): no entrance motion at all, not even on the first open. Kyle
            // reviewed the once-per-session fade in the live build and called for instant —
            // the popover is opened dozens of times a day and any fade reads as latency.
            // 19pt inset / 20pt tile gap / 384pt overall — tuned in the onboarding HTML
            // mockup (Jul 2026); roomier than the original concentric 12pt scheme.
            .padding(tuning.values.shellMargin)
            // KTD4 / KTD5: pinned from the stored plan, never animated (R7).
            .frame(width: shellWidth(columns: columnPlan.columnCount))
            .onChange(of: columnSlots, initial: true) { columns.update(slots: columnSlots) }
            // KTD2: a layout change replans from the new layout's heights. It is made in
            // Settings, so the popover is closed and nothing animates (KTD5).
            .onChange(of: store.accountLayout, initial: true) { columns.setLayout(store.accountLayout) }
            .onChange(of: store.expandAccountsHorizontally, initial: true) {
                columns.setAllowsHorizontalExpansion(store.expandAccountsHorizontally)
            }
            // U1 spike: `MenuBarExtra` grows its window with the content but never shrinks it.
            .onChange(of: columnPlan.columnCount) { fitPopoverWindow(columns: columnPlan.columnCount) }
            // U1 spike: the popover's view state outlives a close, and a width chosen on open
            // shows the old one for a pass. So the next open's plan is made here, from the
            // heights just drawn, and the hidden window takes its width before it reappears.
            .onDisappear {
                columns.popoverDidClose()
                fitPopoverWindow(columns: columns.drawnPlan(for: columnSlots).columnCount)
            }
            // SQ1: each open refits the reused window to the last ideal height (macOS 15 only).
            .onAppear { if fitsMenuBarWindowHeight { heightFitter.scheduleFit() } }
            // One clean system surface: Liquid Glass on Tahoe, native material on Sequoia.
            // Both paths own their full background so no redundant material muddies the host.
            .modifier(PopoverSurfaceModifier(
                cornerRadius: tuning.values.shellCornerRadius,
                settings: surface,
                forceSolid: forceSolidSurface
            ))
            // Capture the popover's hosting window so opening Settings can dismiss it.
            .background(WindowAccessor(surface: surface, cornerRadius: tuning.values.shellCornerRadius) {
                configurePopoverWindow($0, from: $1)
            })
            // G1A: the popover is the only surface with a title-ink choice, so this is the
            // one place it enters the view tree (the Settings specimen sets its own).
            .environment(\.accountTitleInk, store.accountTitleInk)
            .environment(\.headroomTuning, tuning.values)
        }
    }

    /// One provider card, or one piece of it, in its column (KTD6).
    private func cardFragment(
        _ fragment: PopoverCardFragment,
        providerID id: ProviderID,
        entries: [ProviderAccountEntry],
        anyProviderMultiAccount: Bool,
        now: Date
    ) -> some View {
        // M5A follow-up: the popover dissolves old recipe → new recipe instead of
        // hard-cutting. The `.id` sits on the card and the ZStack around it is what makes
        // that safe here: an id swap keeps both copies alive for the fade, and stacked they
        // would briefly double the card's height — which the measured `cardsHeight` samples.
        // A ZStack overlaps them instead, so the list only ever holds the taller of the two.
        // The specimen's hidden-twin variant is deliberately not copied: a second live
        // `ProviderCardView` here would announce, claim arrivals, and read the store twice
        // per provider.
        ZStack(alignment: .topLeading) {
            ProviderCardView(
                providerID: id,
                displayName: store.displayNames[id] ?? id.raw,
                entries: entries,
                capabilityStatus: store.providerCapabilities[id],
                percentageMode: store.usagePercentageMode,
                meterStyle: store.meterStyle,
                anyProviderMultiAccount: anyProviderMultiAccount,
                now: now,
                onRetrySetup: {
                    if let account = store.primaryAccount(for: id) { store.refreshAccountNow(account.key) }
                },
                onRetryProvider: { store.refreshProviderNow(id) },
                onRetryAccount: { store.refreshAccountNow($0.key) },
                claimBankedResetReveal: { store.claimBankedResetReveal(for: $0, currentCount: $1) },
                loadingForAccount: { key in
                    // R6/R10: evaluated by glyph children, not this large body.
                    AccountLoadingState.resolve(key: key, checking: store.accountActionCheckingKeys,
                        probing: store.probingAccounts, ends: store.lastProbeEndTimes,
                        fullRefresh: store.fullRefreshInFlight)
                },
                fragment: fragment.accountRange,
                // `Layout.placeSubviews` is nonisolated but SwiftUI runs layout on the main thread.
                onMeasureColumnItem: { [columns] id, height in
                    MainActor.assumeIsolated { columns.record(height, for: id) }
                },
                accountLayout: store.accountLayout,
                useEmailAsAccountName: store.useEmailAsAccountName,
                showsCodexSparkCounters: store.showCodexSparkCountersInApp
            )
            .id(meterRecipeKey)
            .transition(.opacity)
        }
        // S2A: the swap is opacity only, so Reduce Motion keeps the
        // 200ms dissolve rather than hard-cutting the meter.
        .animation(
            HeadroomMotion.resolved(
                HeadroomMotion.settle,
                .crossfade,
                reduceMotion: reduceMotion
            ),
            value: meterRecipeKey
        )
        // M7A: a card that arrives rises 4pt out of a slight blur, one
        // that leaves only fades — the Settings list's vocabulary, so
        // both surfaces describe the same account change the same way.
        .transition(.settingsReveal)
    }

    /// KTD4 / R7: one card width, or exactly two plus the gap (384 / 750 at the shipped
    /// values). Read from `tuning` so the DialKit shell dials still drive it; the plan's own
    /// height model stays on `AccountColumnsMetrics.popover`.
    private func shellWidth(columns: Int) -> CGFloat {
        let values = tuning.values
        let card = values.shellWidth - 2 * values.shellMargin
        return values.shellWidth + CGFloat(max(columns, 1) - 1) * (card + values.cardGap)
    }

    /// The column layout's card width and gap, from the same tuning values as the shell.
    private var columnMetrics: AccountColumnsMetrics {
        let values = tuning.values
        var metrics = AccountColumnsMetrics.popover
        metrics.columnWidth = values.shellWidth - 2 * values.shellMargin
        metrics.cardGap = values.cardGap
        return metrics
    }

    /// U1 spike: a wider plan grows the `MenuBarExtra` window on its own; a narrower one has
    /// to be fitted, or the content sits centred in the old width with stray shadow edges.
    /// The left edge stays on the status item.
    private func fitPopoverWindow(columns count: Int) {
        let width = shellWidth(columns: count)
        DispatchQueue.main.async {
            guard let window = popoverWindow, window.frame.width > width + 0.5 else { return }
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: window.isVisible)
            window.invalidateShadow()
        }
    }

    /// M5A follow-up: one key for the whole card list, read once per body pass.
    private var meterRecipeKey: String { MeterRecipeKey.key(for: store.meterStyle) }

    /// Native pattern: navigating out of the transient menu-bar popover into the persistent
    /// Settings window dismisses the popover (mirrors Control Center → System Settings). The
    /// popover is recreated on next menu-bar click, so closing its window is safe.
    ///
    /// SW1: the popover fades out while Settings fades in, so the handoff is one crossfade
    /// instead of a cut. The close rides the fade's own completion, so the two share one
    /// clock, and the alpha is restored after it because `MenuBarExtra` may reuse the window
    /// for the next open. KB1: from ⌘, both halves are instant.
    private func openSettingsDismissingPopover() {
        if let window = popoverWindow {
            if HeadroomMotion.isKeyboardInitiated {
                window.close()
            } else {
                let fading = window
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = HeadroomMotion.windowOutDuration
                    context.timingFunction = HeadroomMotion.windowCurve
                    fading.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        fading.close()
                        fading.alphaValue = 1
                    }
                }
            }
        }
        onOpenSettings()
    }

    private func configurePopoverWindow(_ window: NSWindow?, from anchor: NSView) {
        popoverWindow = window
        guard let window else { return }
        if fitsMenuBarWindowHeight, heightFitter.window !== window {
            heightFitter.window = window
            heightFitter.scheduleFit()
        }
        let radius = tuning.values.shellCornerRadius
        // HR-33: keep the custom content radius, but clear the MenuBarExtra host backing
        // so the popover has exactly one system material layer at the rounded edge.
        // Idempotent: this runs on every view update, and re-assigning window properties
        // that already hold the value still invalidates the window.
        if window.isOpaque { window.isOpaque = false }
        if window.backgroundColor != .clear { window.backgroundColor = .clear }
        // PC1 (Kyle, 2026-09-23): an unbundled `swift run` (the `--demo` QA path) gets a host
        // background that `.containerBackground(.clear, for: .window)` does not remove: flat
        // leaf views spanning the window (a backdrop, a grey fill, a vibrancy layer), clipped
        // only by the window's smaller corner, so a filled second corner showed outside the
        // r22 shell. Those leaves are rounded to the shell's radius. Not the host view itself:
        // masking a parent that holds the live glass made the popover flicker. The bundled
        // app has no such leaves, so this loop finds nothing there.
        var reshaped = false
        for leaf in window.contentView?.subviews ?? [] where leaf.subviews.isEmpty {
            guard let layer = leaf.layer,
                  layer.cornerRadius != radius || !layer.masksToBounds else { continue }
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            reshaped = true
        }
        // PC3 (2026-10-13): the window server draws the window shadow, and its hairline rim, at
        // the window's own tighter corner, which no view or layer here can reshape. That rim was
        // the second corner outside the shell (the faint outline on 26, likely the filled corner
        // reported on 27). Turning the shadow off removed it; the glass edge carries the outline.
        if window.hasShadow != surface.windowShadow { window.hasShadow = surface.windowShadow }
        PopoverShadowWindow.sync(with: window, settings: surface, cornerRadius: radius)
        if surface.reshapeHostChrome {
            if PopoverHostChrome.reshape(in: window, sparing: anchor, cornerRadius: radius) { reshaped = true }
        } else if PopoverHostChrome.restoreChrome() {
            reshaped = true
        }
        if reshaped { window.invalidateShadow() }
    }

    /// PC2: the surface the popover draws; the pinned DialKit copy always keeps the shell.
    private var surface: PopoverSurfaceSettings {
        var settings = tuning.surface
        if isPinnedTuningCopy { settings.surface = .headroom }
        return settings
    }

    /// The page title now outweighs the 15pt card titles so hierarchy reads top-down, and
    /// the right slot carries one contextual status: the consolidated "Updated" stamp, or
    /// the setup stage a provider card is showing below it (PA10 —
    /// `PopoverHeaderStatusText`). The gear's visible glyph stays small but its hit area is
    /// padded out to the 40×40 floor.
    private func header(now: Date) -> some View {
        let statusBaselineOffset = Self.baselineOffsetMatchingTitle(for: Self.statusFont)
        let gearBaselineOffset = Self.inkCenterAboveBaseline(Self.titleFont)
        // All three elements align on one *cap-centre* axis (measured against real
        // renders): pure `.center` leaves the title ~2pt low (descender + line box),
        // pure baseline leaves the 11pt status visibly low. So: baseline row, with the
        // status raised so its cap centre matches the title's, and the gear centred at
        // the title's cap centre above the baseline.
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Usage")
                .font(.system(size: 20, weight: .bold))
                .kerning(-0.2)
                // SQ1: the hosting test reads where the title landed. SwiftUI builds no
                // accessibility tree without an assistive client, so an identifier can't be found.
                .anchorPreference(key: PopoverHeaderTitleAnchorKey.self, value: .bounds) { $0 }
            Spacer(minLength: 8)
            headerStatusSlot(now: now, baselineOffset: statusBaselineOffset)
            // Native glass control. Its circular boundary sits flush at the content margin —
            // matching "Usage" on the left edge — which fixes the old alignment (a bare glyph
            // whose hit-area padding floated it ~9pt inside the edge).
            Button(action: openSettingsDismissingPopover) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    // 32pt glyph frame so the glass control reaches the ~40pt hit floor
                    // while the visible gearshape stays small.
                    .frame(width: 32, height: 32)
            }
            // PA11b: the gear stays bare. Text-labelled buttons all took a resting container
            // in this pass, but a borderless glyph in a title bar is the macOS HIG's own
            // toolbar convention — the hover pill, the pointer cursor and the press state
            // are the affordance, exactly as they are for `+`, `…`, copy, trash and reset.
            .buttonStyle(HoverButtonStyle(horizontalPadding: 0, verticalPadding: 0))
            // R2M8: ⌘, is universal on macOS, and Settings is a `Window(id:)` rather than a
            // `Settings` scene, so the system gives the app nothing for free. Bound to the
            // gear itself so the shortcut and the click run one action. Emil's rule that a
            // keyboard-initiated action must not animate is kept by KB1: since SW1 the click
            // path crossfades, and both halves check `isKeyboardInitiated` to stay instant.
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Settings")
            .alignmentGuide(.firstTextBaseline) { d in
                d[VerticalAlignment.center] + gearBaselineOffset
            }
        }
        // R2M12: the elapsed wait is read in seconds, and the popover's own `TimelineView`
        // only ticks per minute. This runs *only* while a handoff clock is on screen and is
        // cancelled the moment it isn't — a clock bound to real work, not a decorative loop.
        .task(id: headerWaitingAccount?.key) {
            guard pinnedDate == nil, headerWaitingAccount != nil else { return }
            while !Task.isCancelled {
                waitingClockNow = .now
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The header now speaks only when a setup card needs the user; the freshness stamp lives
    /// in the footer beside Refresh (Sep 2026). A setup phrase and a waiting clock are
    /// different lines, so `.id(status.kind)` replaces the view and the outer `.crossfade`
    /// scope dissolves it. The ZStack keeps both copies in one slot mid-crossfade so the
    /// header doesn't relayout under them.
    private func headerStatusSlot(now: Date, baselineOffset: CGFloat) -> some View {
        let status = PopoverHeaderStatusResolver.setup(statusInput(now: now))
        return ZStack(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
            if let status {
                statusLine(status)
            }
        }
        // R2M5/S2A: the replacement is pure opacity, so Reduce Motion keeps its 200ms rather
        // than blinking one sentence into another.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: status?.kind
        )
        .alignmentGuide(.firstTextBaseline) { d in
            d[.firstTextBaseline] + baselineOffset
        }
    }

    /// One status line, shared by the header's setup slot and the footer's freshness stamp.
    private func statusLine(_ status: PopoverHeaderStatus) -> some View {
        Text(status.text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            // M2A: the minute tick was a hard cut. The stamp's value only grows, so
            // `numericText(value:)` rolls the digits upward — time's own direction.
            .contentTransition(headerStatusTransition(status))
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion),
                value: status
            )
            .id(status.kind)
            .transition(.opacity)
    }

    private static func inkCenterAboveBaseline(_ font: NSFont) -> CGFloat {
        // Cap centre, not the cap-to-descender midpoint: the header is Title Case, so its
        // optical centre is half the cap height. The old midpoint folded the descender in and
        // sat the gear and the status ~2pt below the title (measured on a live 2× capture).
        OpticalCentering.capHeightCenter(of: font)
    }

    /// Measured residual on a live 2× capture: with the pure cap-centre difference the 11pt
    /// stamp's cap centre still sat 0.75pt below the title's (the raised baseline snaps to
    /// the pixel grid). Re-measure if either font changes.
    private static let statusBaselineResidual: CGFloat = 0.75

    private static func baselineOffsetMatchingTitle(for font: NSFont) -> CGFloat {
        inkCenterAboveBaseline(titleFont) - inkCenterAboveBaseline(font) + statusBaselineResidual
    }

    private func headerStatusTransition(_ status: PopoverHeaderStatus) -> ContentTransition {
        guard let rollValue = status.rollValue else { return .identity }
        return HeadroomMotion.numericText(value: rollValue, reduceMotion: reduceMotion)
    }

    /// R2M5: the popover's status inputs, gathered from live captures, retained ones and the
    /// setup card below the header. The decisions are `PopoverHeaderStatusResolver`, so the
    /// states are pinned by tests without standing up a store, a snapshot and a popover;
    /// this only gathers the inputs.
    private func statusInput(now: Date) -> PopoverHeaderStatusResolver.Input {
        var setupText: String?
        var waitingElapsed: TimeInterval?
        if let outcome = claudeGuidedSetupOutcome {
            let account = ProviderAccount.builtIn(for: .claude)
            setupText = PopoverHeaderStatusText.claude(
                outcome: outcome,
                isWaiting: SetupSessions.isWaiting(for: account)
            )
            waitingElapsed = handoffElapsed(for: account, now: now)
        } else if let action = codexConnectionAction {
            let account = ProviderAccount.builtIn(for: .codex)
            setupText = PopoverHeaderStatusText.codex(
                action: action,
                isWaiting: SetupSessions.isWaiting(for: account)
            )
            waitingElapsed = handoffElapsed(for: account, now: now)
        }
        // U3: the aggregation is Core's `FreshnessStamp.Anchors`, shared with the phone. A
        // retained row keeps its own *source* observation anchor across stale and unavailable
        // transitions — the honest answer to "when was this last checked" (R2M5).
        let anchors = FreshnessStamp.Anchors(snapshots: store.providerOrder.lazy.flatMap { id in
            store.accounts(for: id).map { store.snapshot(for: $0.key) }
        })
        return PopoverHeaderStatusResolver.Input(
            setupText: setupText,
            waitingElapsed: waitingElapsed,
            oldestLiveCapture: anchors.oldestLive,
            newestCheck: anchors.newestCheck,
            now: now
        )
    }

    /// R2M12: `waitingClockNow` is refreshed once a second by the header's own task while a
    /// handoff is open; `now` is the popover's per-minute tick and stands in until the first
    /// tick lands.
    private func handoffElapsed(for account: ProviderAccount, now: Date) -> TimeInterval? {
        guard let start = SetupSessions.waitingStart(for: account) else { return nil }
        return max(0, (pinnedDate ?? max(now, waitingClockNow)).timeIntervalSince(start))
    }

    /// R2M12: the account whose open handoff the header is clocking, if any. Nil covers a
    /// handoff whose start was never trustworthy — a marker staged before the start was
    /// persisted, or one whose recorded start is in the future — and that wait keeps the
    /// card-derived line rather than showing an invented duration. A handoff restored from a
    /// durable marker now arrives with its real start (`SetupSessions.restoreWaitingStart`),
    /// so an hour-old Terminal window reads as an hour, not as three seconds.
    private var headerWaitingAccount: ProviderAccount? {
        if claudeGuidedSetupOutcome != nil {
            let account = ProviderAccount.builtIn(for: .claude)
            return SetupSessions.waitingStart(for: account) != nil ? account : nil
        }
        if codexConnectionAction != nil {
            let account = ProviderAccount.builtIn(for: .codex)
            return SetupSessions.waitingStart(for: account) != nil ? account : nil
        }
        return nil
    }

    private var claudeGuidedSetupOutcome: ProviderSetupOutcome? {
        guard store.providerOrder.contains(.claude),
              case .stale(let reason) = store.appDisplaySnapshot(for: .claude).freshness else { return nil }
        switch reason.providerSetupOutcome {
        case .claudeLoginRequired, .claudeTrustRequired:
            return reason.providerSetupOutcome
        default:
            return nil
        }
    }

    /// PA10: the header reads the *same* action enum the Codex card below it reads, instead
    /// of collapsing four states into "does Codex need connecting".
    private var codexConnectionAction: CodexConnectionAction? {
        guard store.providerOrder.contains(.codex) else { return nil }
        return store.appDisplaySnapshot(for: .codex).codexConnectionAction
    }

    private func footer(now: Date) -> some View {
        let freshness = PopoverHeaderStatusResolver.freshness(statusInput(now: now))
        return RefreshFooter(store: store, freshness: freshness)
    }
}

/// KTD17/KTD18: only the small footer observes fast work signals and redraws its clock.
/// The card stack and PopoverView's minute timeline never receive per-frame state writes.
private struct RefreshFooter: View {
    let store: UsageStore
    let freshness: PopoverHeaderStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate

    var body: some View {
        let meters = store.menuBarMeters
        let mains = Dictionary(uniqueKeysWithValues: store.providerOrder.compactMap { id in
            store.primaryAccount(for: id).map { (id, $0.key) }
        })
        let sourceIdentity = ReprintSourceIdentity(meters: meters,
            automatic: store.menuBarFillSource.providerIDs == nil, currentMains: mains)
        let run = store.userRefreshRun
        let work = store.visibleRefreshWork
        let probing = store.probingAccounts
        let ends = store.lastProbeEndTimes
        let spend = store.apiSpendInFlightProviders
        let now = pinnedDate ?? Date()
        let makeRecipe: (Date) -> ReprintRecipe = { date in
            ReprintRecipe(meters: meters, automatic: store.menuBarFillSource.providerIDs == nil,
                currentMains: mains, run: run, probingAccounts: probing, probeEndTimes: ends,
                spendInFlightProviders: spend, visibleWork: work, now: date, reduceMotion: reduceMotion)
        }
        let current = makeRecipe(now)
        // The one-shot expiry pauses this timeline after the hold, last print or wave.
        let deadlines = [work.clearedAt?.addingTimeInterval(LoadingMotionConstants.endHoldDuration)]
            + (run?.entries.values.filter { $0.origin != .setupCheck }.map {
                ($0.landedAt ?? $0.requestedAt).addingTimeInterval(
                    $0.landedAt == nil ? LoadingMotionConstants.ghostWipeDuration : LoadingMotionConstants.printDuration)
            } ?? []).map(Optional.some)
            + ends.values.map { Optional(Date(timeIntervalSince1970: floor($0.timeIntervalSince1970) + 1)) }
        let ongoingMotion = !reduceMotion && (current.phase == .spinner || current.phase == .spendTail)
            && (!probing.isEmpty || current.phase == .spendTail)
        let printing = current.pills.contains { pill in
            switch pill.ink {
            case .printing, .crossfade: true
            default: false
            }
        }
        LoadingTimeline(active: ongoingMotion,
                        until: current.needsTimeline ? deadlines.compactMap { $0 }.max() : nil,
                        interval: printing ? 1 / 30 : LoadingMotionConstants.sloshFrameInterval) { date in
            let recipe = makeRecipe(date)
            let receipt = RefreshReceiptPresentation.line(run: run, isResting: recipe.phase == .rest, now: date,
                                                          title: { store.refreshReceiptTitle(for: $0) })
            HStack(spacing: 10) {
                // PA11b: native bezel owns its appearance-safe chrome and cached label.
                Button { store.refreshNow() } label: {
                    Text("Refresh").opacity(recipe.isEnabled ? 1 : 0)
                }
                .disabled(!recipe.isEnabled)
                .overlay {
                    if !recipe.isEnabled {
                        ZStack {
                            HalftonePillRow(pills: recipe.pills)
                                // KTD19: changing to an unrequested main crossfades uniformly;
                                // the Core recipe never invents a fresh print for that account.
                                .id(sourceIdentity)
                                .transition(.opacity)
                        }
                        .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade,
                                    reduceMotion: reduceMotion), value: sourceIdentity)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade,
                            reduceMotion: reduceMotion), value: recipe.isEnabled)
                // R2M8: ⌘R follows the work, never a click-specific animation. R5 keeps
                // it enabled during setup-only checks; KTD9 disables through spend and hold.
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel(recipe.isEnabled ? "Refresh" : "Refreshing usage")
                ZStack(alignment: .leading) {
                    if let receipt {
                        receiptLine(receipt).id(receipt).transition(receiptTransition)
                    } else {
                        Text(freshness.text)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .contentTransition(freshness.rollValue.map {
                                HeadroomMotion.numericText(value: $0, reduceMotion: reduceMotion)
                            } ?? .identity)
                            .id(freshness.kind)
                            .transition(receiptTransition)
                    }
                }
                .clipped()
                .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade,
                            reduceMotion: reduceMotion), value: freshness.kind)
                .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade,
                            reduceMotion: reduceMotion), value: receipt)
                Spacer(minLength: 0)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .buttonBorderShape(.roundedRectangle(radius: 7))
            .font(.system(size: 12.5, weight: .semibold))
        }
    }

    private var receiptTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                              removal: .move(edge: .top).combined(with: .opacity))
    }

    private func receiptLine(_ line: RefreshReceiptPresentation.Line) -> some View {
        HStack(spacing: 5) {
            if line.checked {
                Image(systemName: "checkmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.tertiary)
            }
            Text(line.text).foregroundStyle(.secondary)
            if let count = line.count { Text(count).foregroundStyle(.tertiary).padding(.leading, 2) }
        }
        .font(.system(size: 11).monospacedDigit())
        .lineLimit(1)
    }
}

/// PA10: the popover has one status slot, and it was writing its own copy for a card it
/// only labels. Codex's expired session, denied file access and misplaced sign-in all read
/// "Connect Codex to begin" over a card saying "Reconnect Codex" — or saying, in the last
/// two, that signing in again will not help at all. The slot now derives from the same
/// `CodexConnectionAction` the card switches on, so header and card cannot disagree.
///
/// The waiting strings changed with it: the header said "Watching for …" where every card
/// and account row says "Waiting for …". One verb.
///
/// Lifted out of `PopoverView` on purpose: pure string mapping, so the table is testable
/// without standing up a store, a snapshot and a popover.
enum PopoverHeaderStatusText {
    static func claude(outcome: ProviderSetupOutcome, isWaiting: Bool) -> String {
        if isWaiting {
            return outcome == .claudeLoginRequired
                ? "Waiting for Claude sign-in…"
                : "Waiting for approval…"
        }
        // R2C6: one verb for one act — the untyped preset no longer says "Set up".
        return ProviderSignInCopy.header(for: .claude)
    }

    static func codex(action: CodexConnectionAction, isWaiting: Bool) -> String {
        guard !isWaiting else { return "Waiting for Codex sign-in…" }
        switch action {
        // R2C6: the header shares the card's vocabulary instead of "Connect"/"Reconnect".
        case .connect: return ProviderSignInCopy.header(for: .codex)
        case .reconnect: return ProviderSignInCopy.header(for: .codex, again: true)
        case .showPrivacyGuidance: return "Codex needs file access"
        case .resolveStorage: return "Codex sign-in needs relocating"
        }
    }

    /// R2M12: the waiting card already says *what* Headroom is waiting for, so the header
    /// repeating it verbatim ("Waiting for approval…" twice) spends the app's one status slot
    /// on nothing. It carries the thing the card cannot: a clock. Seconds are zero-padded
    /// past the first minute so the digits roll in place instead of jittering the column.
    static func waiting(elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        if seconds < 60 { return "Waiting \(seconds)s" }
        if seconds < 3600 {
            return "Waiting \(seconds / 60)m \(padded(seconds % 60))s"
        }
        return "Waiting \(seconds / 3600)h \(padded((seconds % 3600) / 60))m"
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// R2M5: one resolved header line. `kind` is the slot's *identity* — a phrase and a stamp are
/// different lines, not one value that changed — and `rollValue` is what the digit roll
/// follows (M2A), nil wherever there are no digits to roll.
struct PopoverHeaderStatus: Equatable {
    enum Kind: Hashable {
        case waiting
        case setup
        case updated
        case lastChecked
        case never
    }

    let kind: Kind
    let text: String
    let rollValue: Double?
}

/// R2M5: the header slot used to collect `.live` captures and return nil for everything else,
/// so first run, an all-stale popover and a capability failure showed a card full of retained
/// numbers with no visible age anywhere. A number you cannot date is a number you cannot
/// trust — Weather and Stocks carry a timestamp even when the fetch failed. Pure and lifted
/// out of the view for the same reason `PopoverHeaderStatusText` is: the table is the
/// decision, and it should be testable without a store.
enum PopoverHeaderStatusResolver {
    struct Input {
        /// The setup line the card below is showing, when a setup card is the header's source.
        var setupText: String?
        /// R2M12: set only while that account's handoff is open *and* its start is known.
        var waitingElapsed: TimeInterval?
        /// Oldest live capture across every account, so the header never claims data is
        /// fresher than the least-fresh provider.
        var oldestLiveCapture: Date?
        /// Newest observation of any kind, live or retained — the answer to "when was this
        /// last checked" once nothing is live.
        var newestCheck: Date?
        var now: Date
    }

    /// The header's line: only a setup stage the card below is showing. Nil otherwise — the
    /// freshness stamp moved to the footer beside Refresh (Sep 2026), so the header is just
    /// the title and the gear whenever nothing needs the user.
    static func setup(_ input: Input) -> PopoverHeaderStatus? {
        if let elapsed = input.waitingElapsed {
            return PopoverHeaderStatus(
                kind: .waiting,
                text: PopoverHeaderStatusText.waiting(elapsed: elapsed),
                // WC1 (2026-09-25 motion audit): the seconds swap plainly. A roll once a second
                // for as long as the handoff lasts is periodic motion in the corner of the
                // eye; the digits are already tabular, so the swap never shifts the line.
                rollValue: nil
            )
        }
        if let setupText = input.setupText {
            return PopoverHeaderStatus(kind: .setup, text: setupText, rollValue: nil)
        }
        return nil
    }

    /// The footer stamp beside Refresh. U3: the wording and the roll value are Core's
    /// `FreshnessStamp`, shared with the phone; this maps its kind into the slot's identity.
    static func freshness(_ input: Input) -> PopoverHeaderStatus {
        let stamp = FreshnessStamp.resolve(
            FreshnessStamp.Anchors(oldestLive: input.oldestLiveCapture, newestCheck: input.newestCheck),
            now: input.now
        )
        let kind: PopoverHeaderStatus.Kind = switch stamp.kind {
        case .updated: .updated
        case .lastChecked: .lastChecked
        case .never: .never
        }
        return PopoverHeaderStatus(kind: kind, text: stamp.text, rollValue: stamp.rollValue)
    }
}

/// The popover shell: 19pt inset / 384pt overall, tuned in the onboarding HTML mockup
/// (Jul 2026). R2C20: the Appearance specimen derives its card width from these so a
/// preview can never draw a card the popover doesn't.
enum PopoverCardMetrics {
    static let shellWidth: CGFloat = 384
    static let shellMargin: CGFloat = 19
    /// One source with the column planner, so the cards it measures and the widths it plans
    /// can't drift apart.
    static let cardWidth = CGFloat(AccountColumnsMetrics.popover.columnWidth)
    static let cardPadding = CGFloat(AccountColumnsMetrics.popover.cardPadding)
    static let accountGap = CGFloat(AccountColumnsMetrics.popover.accountGap)
    /// The card stack scrolls past this height; with two columns it caps the taller one (R8).
    static let cardsHeightCap: CGFloat = 640

    /// KTD4 / R7: one card width (384 overall) or exactly two plus the 20pt gap (750).
    static func shellWidth(columns: Int) -> CGFloat {
        CGFloat(AccountColumnsMetrics.popover.gridWidth(columns: columns)) + 2 * shellMargin
    }
}

/// L2A geometry. The gutter offset is measured from the scroll viewport's trailing edge,
/// which coincides with the cards' right edge 19pt inside the shell: pushing the 3pt
/// capsule out by 12.5pt lands its centre 8pt from the shell edge.
private enum PopoverScrollIndicatorMetrics {
    static let width: CGFloat = 3
    static let minimumLength: CGFloat = 24
    static let endInset: CGFloat = 6
    static let shellMargin: CGFloat = PopoverCardMetrics.shellMargin
    static let centreFromShellEdge: CGFloat = 8
    static let gutterOffset: CGFloat = shellMargin - centreFromShellEdge + width / 2
}

/// One read of the scroll viewport, shared by the feather and the indicator so the two
/// stay in step and the popover installs a single `onScrollGeometryChange`.
private struct PopoverScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var viewport: CGFloat = 0
    var content: CGFloat = 0

    var overflows: Bool { viewport > 0 && content > viewport + 1 }
    var continuesBelow: Bool { offset + viewport < content - 4 }
}

/// SC1: the scroll chrome's state, out of `PopoverView`'s body. Each property is written
/// only when it changes, so a scroll frame re-renders the indicator alone and the feather
/// only when the list stops or starts continuing below the cap.
@MainActor
@Observable
private final class PopoverScrollModel {
    private(set) var metrics = PopoverScrollMetrics()
    /// Content extends past the scroll cap and isn't scrolled to the bottom — gates the
    /// bottom fade so it never softens a fully visible last card.
    private(set) var continuesBelow = false
    private(set) var indicatorVisible = false
    @ObservationIgnored private var indicatorHideTask: Task<Void, Never>?

    /// Called only when the metrics changed (`onScrollGeometryChange` compares them).
    func update(_ metrics: PopoverScrollMetrics) {
        self.metrics = metrics
        if continuesBelow != metrics.continuesBelow { continuesBelow = metrics.continuesBelow }
        flashIndicator(overflows: metrics.overflows)
    }

    /// Appears on scroll, holds 900ms, then fades. Each geometry change restarts the hold,
    /// so a continuous drag keeps it lit and it settles once the list stops moving.
    private func flashIndicator(overflows: Bool) {
        indicatorHideTask?.cancel()
        guard overflows else {
            if indicatorVisible { indicatorVisible = false }
            return
        }
        if !indicatorVisible { indicatorVisible = true }
        indicatorHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.indicatorVisible = false
        }
    }
}

/// The scroll viewport's mask (R2C23): crisp everywhere except a back-loaded bottom fade while
/// content continues below the cap.
///
/// FA1 (2026-10-03 perf bench): the fade's animation is scoped to the band's opacity. It used
/// to wrap the whole ScrollView, and the feather flips in the same transaction as the open's
/// 0 → measured height change, so the card list grew open over ~12 frames on every open —
/// the entrance M9C removed — re-rendering the popover on each frame.
private struct PopoverScrollFeather: View {
    let model: PopoverScrollModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// R2C23: 14pt, down from 26 — the old band was taller than a whole Micro meter row, so
    /// the last chip in the list rendered as a half-dissolved ghost and the card's bottom rim
    /// never drew at all. Notification Centre, Raycast and Linear all fade ~12–16pt.
    private static let featherHeight: CGFloat = 14

    /// R2C23: non-linear, so the fade is back-loaded and the top two-thirds of the band stays
    /// crisp — a soft edge rather than missing data. A straight `LinearGradient` between two
    /// colours could not express it; these are its three stops.
    private static let featherStops: [Gradient.Stop] = [
        Gradient.Stop(color: .black, location: 0),
        Gradient.Stop(color: .black.opacity(0.55), location: 0.5),
        Gradient.Stop(color: .black.opacity(0), location: 1),
    ]

    var body: some View {
        let _ = BenchCounters.hit("PopoverScrollFeather")
        let fadesOut = model.continuesBelow
        VStack(spacing: 0) {
            Rectangle().fill(.black)
            ZStack {
                LinearGradient(stops: Self.featherStops, startPoint: .top, endPoint: .bottom)
                // The gated case: an opaque band over the fade, so a popover that doesn't
                // scroll keeps its crisp last card edge. FA1: the body-scoped animation
                // reaches this opacity only — never the band's place in a growing viewport.
                // S2A: pure mask opacity, so Reduce Motion keeps the 200ms softening.
                Rectangle().fill(.black)
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)
                    ) { $0.opacity(fadesOut ? 0 : 1) }
            }
            .frame(height: Self.featherHeight)
        }
    }
}

/// L2A: a 3pt capsule whose centre sits 8pt from the shell's right edge, so it lives wholly
/// inside the 19pt gutter and never touches a card (the cards' right edge is 19pt in).
/// No track, no well, no hover growth — the three things the stock scroller was faulted
/// for. Drawn only while the content overflows the 640pt cap.
private struct PopoverScrollIndicator: View {
    let model: PopoverScrollModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = BenchCounters.hit("PopoverScrollIndicator")
        if model.metrics.overflows {
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.30))
                .opacity(model.indicatorVisible ? 1 : 0)
                // Fade-out is the specified 200ms on `settle`'s curve; the appearance is
                // the shorter `quickSettle` so the cue is already there when the finger
                // lands. S2A: the capsule only ever changes opacity, so Reduce Motion keeps
                // both timings — the geometry below is what stays untweened.
                .animation(visibilityAnimation, value: model.indicatorVisible)
                // Geometry sits outside the animation scope so the capsule slides with the
                // scroll rather than easing behind it.
                .frame(width: PopoverScrollIndicatorMetrics.width, height: length)
                .offset(x: PopoverScrollIndicatorMetrics.gutterOffset, y: offsetY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var visibilityAnimation: Animation? {
        HeadroomMotion.resolved(
            model.indicatorVisible ? HeadroomMotion.quickSettle : HeadroomMotion.settle,
            .crossfade,
            reduceMotion: reduceMotion
        )
    }

    /// Proportional length — viewport × (viewport / content) — floored at 24pt so a very
    /// long list still leaves something to see, and capped by the inset track.
    private var length: CGFloat {
        let viewport = model.metrics.viewport
        let content = model.metrics.content
        guard viewport > 0, content > viewport else { return 0 }
        let track = max(viewport - 2 * PopoverScrollIndicatorMetrics.endInset, 0)
        return min(track, max(PopoverScrollIndicatorMetrics.minimumLength, viewport * (viewport / content)))
    }

    private var offsetY: CGFloat {
        let metrics = model.metrics
        let track = max(metrics.viewport - 2 * PopoverScrollIndicatorMetrics.endInset, 0)
        let travel = max(track - length, 0)
        let scrollable = max(metrics.content - metrics.viewport, 1)
        let progress = min(max(metrics.offset / scrollable, 0), 1)
        return PopoverScrollIndicatorMetrics.endInset + travel * progress
    }
}

private struct PopoverSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    var settings: PopoverSurfaceSettings = .shipping
    /// Render-harness only: force the solid shell (ImageRenderer can't rasterize glass).
    var forceSolid: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !settings.usesHeadroomShell && !forceSolid {
            // PC2 tuning: the host's own glass (rounded to the shell in `configurePopoverWindow`),
            // made more opaque by a flat wash in the same shape. Nothing of ours is glass.
            let (wash, opacity) = colorScheme == .light
                ? (settings.lightTint, settings.lightTintOpacity)
                : (settings.darkTint, settings.darkTintOpacity)
            content.background(wash.opacity(opacity), in: shape)
        } else if reduceTransparency || forceSolid || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            // Light glass over a dark desktop lenses the wallpaper into the edge band and
            // muddies the shell (diagnosed Jul 2026, hierarchy log ruled out a second shell);
            // the tint pins the light shell to a light identity while dark mode keeps pure
            // glass. Mirrors how system menu-bar dropdowns read as a light surface.
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = settings.glass == .clear ? .clear : .regular
        let (tint, opacity) = colorScheme == .light
            ? (settings.lightTint, settings.lightTintOpacity)
            : (settings.darkTint, settings.darkTintOpacity)
        return opacity > 0 ? base.tint(tint.opacity(opacity)) : base
    }
}

/// Resolves the `NSWindow` hosting a SwiftUI view. Used to get a direct handle on the
/// `MenuBarExtra(.window)` popover window — SwiftUI exposes no first-class dismissal for
/// it, and matching by private class name is brittle, so we read `view.window` instead.
private struct WindowAccessor: NSViewRepresentable {
    /// Unused in the body; a changed surface or radius makes SwiftUI call `updateNSView` again.
    var surface: PopoverSurfaceSettings = .shipping
    var cornerRadius: CGFloat = 0
    /// The window, and the accessor's own view so callers can tell their content apart from
    /// the host's chrome.
    let onResolve: (NSWindow?, NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window, view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window, nsView) }
    }
}

/// PC2 (macOS 27): the MenuBarExtra host draws its own system glass behind the popover again,
/// at the system's tighter corner radius, and `.containerBackground(.clear, for: .window)` no
/// longer removes it, so a filled second corner showed outside the r22 shell. The host's
/// glass and vibrancy views (everything outside the hosting view that renders `PopoverView`)
/// are reshaped to the shell through their own public corner APIs. No layer is masked, which
/// made the live glass flicker (BUGS.md), and our own SwiftUI glass is never touched.
@MainActor
private enum PopoverHostChrome {
    private static let log = Logger(subsystem: "com.kylezantos.headroom", category: "popover-window")
    private static var loggedWindows: Set<ObjectIdentifier> = []
    /// Host corner state as first seen, so the tuning toggle can hand it back.
    private static var glassOriginals: [ObjectIdentifier: (view: NSView, radius: CGFloat)] = [:]
    private static var maskOriginals: [ObjectIdentifier: (view: NSVisualEffectView, mask: NSImage?)] = [:]

    static func restoreChrome() -> Bool {
        var changed = false
        if #available(macOS 26.0, *) {
            for (_, original) in glassOriginals {
                (original.view as? NSGlassEffectView)?.cornerRadius = original.radius
                changed = true
            }
        }
        glassOriginals.removeAll()
        for (_, original) in maskOriginals {
            original.view.maskImage = original.mask
            changed = true
        }
        maskOriginals.removeAll()
        return changed
    }

    /// Returns true when a view changed shape, so the caller can refresh the window shadow.
    static func reshape(in window: NSWindow, sparing anchor: NSView, cornerRadius: CGFloat) -> Bool {
        guard let root = window.contentView?.superview ?? window.contentView else { return false }
        let content = hostingView(containing: anchor)
        logHierarchyOnce(window, root: root, content: content)
        return reshape(root, sparing: content, cornerRadius: cornerRadius)
    }

    private static func reshape(_ view: NSView, sparing content: NSView?, cornerRadius: CGFloat) -> Bool {
        if view === content { return false }
        var changed = false
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            if glass.cornerRadius != cornerRadius {
                let key = ObjectIdentifier(glass)
                if glassOriginals[key] == nil { glassOriginals[key] = (glass, glass.cornerRadius) }
                glass.cornerRadius = cornerRadius
                changed = true
            }
        } else if let effect = view as? NSVisualEffectView, effect.maskImage?.size.width != cornerRadius * 2 + 1 {
            let key = ObjectIdentifier(effect)
            if maskOriginals[key] == nil { maskOriginals[key] = (effect, effect.maskImage) }
            effect.maskImage = roundedMask(cornerRadius: cornerRadius)
            changed = true
        }
        for child in view.subviews where reshape(child, sparing: content, cornerRadius: cornerRadius) {
            changed = true
        }
        return changed
    }

    /// The outermost hosting view above the accessor: SwiftUI's own glass lives inside it.
    private static func hostingView(containing anchor: NSView) -> NSView? {
        var found: NSView?
        var view: NSView? = anchor.superview
        while let current = view {
            if String(describing: type(of: current)).contains("HostingView") { found = current }
            view = current.superview
        }
        return found
    }

    /// A resizable rounded-rect mask, the documented way to shape an `NSVisualEffectView`.
    private static func roundedMask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }

    /// One structural dump per popover window once it has a size (class names, frames, corner
    /// state; no content), so a future OS's host layout can be read with
    /// `/usr/bin/log show --predicate 'category == "popover-window"'`. Views inside our hosting
    /// view are listed a few levels deep, because the host's backdrop can sit there too (PC1).
    private static func logHierarchyOnce(_ window: NSWindow, root: NSView, content: NSView?) {
        guard window.frame.width > 10, loggedWindows.insert(ObjectIdentifier(window)).inserted else { return }
        var lines = ["\(type(of: window)) \(NSStringFromRect(window.frame)) style=\(window.styleMask.rawValue)"
            + " shadow=\(window.hasShadow) opaque=\(window.isOpaque) level=\(window.level.rawValue)"]
        func visit(_ view: NSView, depth: Int, insideContent: Int?) {
            let layer = view.layer
            let marker = view === content ? " [content]" : ""
            lines.append(String(repeating: "  ", count: depth)
                + "\(type(of: view)) \(NSStringFromRect(view.frame)) r=\(layer?.cornerRadius ?? -1)"
                + " mask=\(layer?.masksToBounds ?? false) hidden=\(view.isHidden)"
                + " bg=\(layer?.backgroundColor != nil) filters=\(layer?.filters?.count ?? 0)\(marker)")
            let nested = view === content ? 0 : insideContent.map { $0 + 1 }
            if let nested, nested >= 4 { return }
            view.subviews.forEach { visit($0, depth: depth + 1, insideContent: nested) }
        }
        visit(root, depth: 0, insideContent: nil)
        // Layers with no view of their own (a backdrop sublayer can draw the host's edge).
        func visitLayer(_ layer: CALayer, depth: Int) {
            guard depth < 5 else { return }
            for sub in layer.sublayers ?? [] where !(sub.delegate is NSView) {
                lines.append("L" + String(repeating: "  ", count: depth) + "\(type(of: sub)) \(NSStringFromRect(sub.frame))"
                    + " r=\(sub.cornerRadius) mask=\(sub.masksToBounds) bg=\(sub.backgroundColor != nil)"
                    + " border=\(sub.borderWidth) filters=\(sub.filters?.count ?? 0) shadow=\(sub.shadowOpacity)")
                visitLayer(sub, depth: depth + 1)
            }
        }
        if let rootLayer = root.layer { visitLayer(rootLayer, depth: 0) }
        if let contentLayer = content?.layer { visitLayer(contentLayer, depth: 0) }
        log.notice("Popover window hierarchy:\n\(lines.joined(separator: "\n"), privacy: .public)")
    }
}

/// PS1 (2026-10-13): the popover's own shadow is off (PC3) because the window server draws it at
/// the window's tighter corner. This draws a replacement at the shell's corner from a second,
/// click-through borderless window ordered just below the popover as a child window. The shadow
/// is cut out under the shell so it never darkens the glass. It mirrors the popover's frame,
/// visibility and alpha (the Settings handoff fades the popover), and goes when the popover closes.
@MainActor
final class PopoverShadowWindow {
    private static var byParent: [ObjectIdentifier: PopoverShadowWindow] = [:]

    static func sync(with parent: NSWindow, settings: PopoverSurfaceSettings, cornerRadius: CGFloat) {
        let key = ObjectIdentifier(parent)
        guard settings.customShadow else {
            byParent.removeValue(forKey: key)?.tearDown()
            return
        }
        let style = Style(
            cornerRadius: cornerRadius,
            opacity: settings.customShadowOpacity,
            blur: settings.customShadowRadius,
            y: settings.customShadowY
        )
        if let existing = byParent[key] {
            existing.update(style)
        } else {
            byParent[key] = PopoverShadowWindow(parent: parent, style: style)
        }
    }

    struct Style: Equatable {
        var cornerRadius: CGFloat
        var opacity: Double
        var blur: Double
        var y: Double
        /// Room around the shell for the blur and offset to fall off before the window edge.
        var pad: CGFloat { CGFloat(blur * 2.5 + abs(y)) + 2 }
    }

    private weak var parent: NSWindow?
    private let window: NSWindow
    private let host: NSHostingView<PopoverShadowView>
    private var style: Style
    private var observers: [NSObjectProtocol] = []
    private var kvo: [NSKeyValueObservation] = []

    private init(parent: NSWindow, style: Style) {
        self.parent = parent
        self.style = style
        host = NSHostingView(rootView: PopoverShadowView(style: style))
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = host
        window.level = parent.level
        window.collectionBehavior = parent.collectionBehavior.union([.transient, .ignoresCycle])
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                     NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { _ in
            MainActor.assumeIsolated { PopoverShadowWindow.byParent.removeValue(forKey: ObjectIdentifier(parent))?.tearDown() }
        })
        kvo.append(parent.observe(\.isVisible) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.follow() }
        })
        kvo.append(parent.observe(\.alphaValue) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.follow() }
        })
        follow()
    }

    private func update(_ style: Style) {
        guard style != self.style else { return }
        self.style = style
        host.rootView = PopoverShadowView(style: style)
        follow()
    }

    private func follow() {
        guard let parent else { return tearDown() }
        guard parent.isVisible else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        let frame = parent.frame.insetBy(dx: -style.pad, dy: -style.pad)
        if window.frame != frame { window.setFrame(frame, display: true) }
        if window.alphaValue != parent.alphaValue { window.alphaValue = parent.alphaValue }
        if window.parent !== parent {
            parent.addChildWindow(window, ordered: .below)
        } else if !window.isVisible {
            window.order(.below, relativeTo: parent.windowNumber)
        }
    }

    private func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        kvo.removeAll()
        parent?.removeChildWindow(window)
        window.orderOut(nil)
    }
}

struct PopoverShadowView: View {
    let style: PopoverShadowWindow.Style

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(style.opacity), radius: style.blur, y: style.y)
            .padding(style.pad)
            // Keep only what falls outside the shell: the glass above stays untouched.
            .mask {
                Rectangle()
                    .overlay(shape.padding(style.pad).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// NB1: the per-account values that change a card's height, flattened in card order.
struct PopoverCardLayoutSignature: Equatable {
    var freshness: [Freshness]
    var sessions: [SetupSessionState]
    var rows: [[WindowKind]]
}
