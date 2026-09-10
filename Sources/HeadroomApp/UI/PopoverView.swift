import SwiftUI
import AppKit
import HeadroomCore

/// The native popover (U7). Composes one card per provider on a system surface, a gear
/// that opens Settings, and a Quit control (required — the app has no Dock presence,
/// KTD9). Tahoe uses Liquid Glass; Sequoia falls back to native material. A
/// `TimelineView` drives a per-minute `now` so countdowns and "updated N min ago" tick
/// without a data poll.
struct PopoverView: View {
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

    @State private var popoverWindow: NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Content extends past the scroll cap and isn't scrolled to the bottom — gates
    /// the bottom fade so it never softens a fully visible last card.
    @State private var scrollContinuesBelow = false
    /// L3A: the list is scrolled off its top — gates the top feather so an unscrolled
    /// popover keeps its crisp first-card edge, exactly like the bottom gate.
    @State private var scrollContinuesAbove = false
    /// L2A: live scroll geometry driving the bespoke gutter indicator. The system
    /// scroller is hidden, so this is the only position and length cue.
    @State private var scrollMetrics = PopoverScrollMetrics()
    @State private var scrollIndicatorVisible = false
    @State private var scrollIndicatorHideTask: Task<Void, Never>?
    /// Measured height of the card stack. `MenuBarExtra(.window)` sizes its window to the
    /// content's ideal height, and a `ScrollView` has no ideal height of its own — left to
    /// self-size it collapsed to zero and the popover opened at 127pt with no cards
    /// (`maxHeight` only sets a ceiling, never a floor). Measuring the stack and pinning an
    /// explicit height is what keeps the window honest; the cap still applies above it.
    @State private var cardsHeight: CGFloat = 0
    /// R2M12: second-resolution "now" for the waiting clock, driven only while a handoff is
    /// open. The popover's own `TimelineView` ticks per minute, which is right for "Updated
    /// N min ago" and useless for "Waiting 45s".
    @State private var waitingClockNow: Date = .now

    private static let titleFont = NSFont.systemFont(ofSize: 20, weight: .bold)
    private static let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
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
            VStack(spacing: 20) {
                header(now: context.date)
                    // Header sits 14pt above the first card (vs the 20pt tile gap) — the
                    // title belongs to the content below it more than cards belong to
                    // each other.
                    .padding(.bottom, -6)
                // Cards scroll once many accounts push past a comfortable popover
                // height; below the cap the height tracks the measured stack, so the
                // common case is untouched. Header and footer stay pinned.
                ScrollView(.vertical) {
                    VStack(spacing: 20) {
                        ForEach(Array(store.providerOrder.enumerated()), id: \.element) { _, id in
                            ProviderCardView(
                                providerID: id,
                                displayName: store.displayNames[id] ?? id.raw,
                                entries: store.accounts(for: id).map { account in
                                    ProviderAccountEntry(
                                        account: account,
                                        snapshot: store.appDisplaySnapshot(for: account.key)
                                    )
                                },
                                capabilityStatus: store.providerCapabilities[id],
                                percentageMode: store.usagePercentageMode,
                                meterStyle: store.meterStyle,
                                anyProviderMultiAccount: anyProviderMultiAccount,
                                now: context.date,
                                onRetrySetup: { store.refreshNow() },
                                onRetryAccount: { store.refreshAccountNow($0.key) }
                            )
                            // M7A: a card that arrives rises 4pt out of a slight blur, one
                            // that leaves only fades — the Settings list's vocabulary, so
                            // both surfaces describe the same account change the same way.
                            .transition(.settingsReveal)
                        }
                        APISpendSectionView(store: store, now: context.date, onOpenSettings: openSettingsDismissingPopover)
                            // S5A: the spend tile is a sibling card, so it arrives and
                            // leaves the same way the provider cards above it do.
                            .transition(.settingsReveal)
                    }
                    // M7A: the popover had no reorder animation at all, so a Make Main
                    // promotion teleported its card to the top. The stack's own layout change
                    // rides this scope, and it is also what the measured `cardsHeight` below
                    // samples frame by frame — so the container contracts *with* a removed
                    // card's fade rather than snapping after it.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion),
                        value: cardListIdentity
                    )
                    // Scroll content is laid out at its ideal height regardless of the
                    // ScrollView's own frame, so this reports the true stack height even
                    // on the first pass while the frame below is still zero.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }
                }
                // L2A: the stock overlay scroller sat on the card border and painted a
                // near-black well over the card interior when it expanded. We hide it and
                // draw our own in the 19pt shell gutter instead (see `scrollIndicator`),
                // which also retires main's borrowed 10pt scroller gutter — the viewport
                // and the cards are the same width again.
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                // Soft fades while content continues past either end of the cap — the flat
                // clip alone read as a card with missing data (impeccable audit P2), and
                // L3A extends the same treatment to the top so a scrolled card is no longer
                // chopped square under the header. Both ends are gated so the common
                // non-scrolling popover keeps its crisp first and last card edges.
                .onScrollGeometryChange(for: PopoverScrollMetrics.self) { geometry in
                    PopoverScrollMetrics(
                        offset: geometry.contentOffset.y,
                        viewport: geometry.containerSize.height,
                        content: geometry.contentSize.height
                    )
                } action: { _, metrics in
                    scrollMetrics = metrics
                    scrollContinuesAbove = metrics.continuesAbove
                    scrollContinuesBelow = metrics.continuesBelow
                    flashScrollIndicator(overflows: metrics.overflows)
                }
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(
                            stops: Self.featherStops(fadesOut: scrollContinuesAbove, mirrored: true),
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: Self.featherHeight)
                        Rectangle().fill(.black)
                        LinearGradient(
                            stops: Self.featherStops(fadesOut: scrollContinuesBelow),
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: Self.featherHeight)
                    }
                }
                // S2A: both feathers are pure mask opacity, so Reduce Motion keeps the
                // 200ms softening rather than hard-cutting the card edge.
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                    value: scrollContinuesBelow
                )
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                    value: scrollContinuesAbove
                )
                // Applied outside the mask so the indicator never feathers at the ends,
                // and outside the feather animations so its position tracks the scroll 1:1.
                .overlay(alignment: .topTrailing) { scrollIndicator }
                .frame(height: forcedCardsHeight ?? min(cardsHeight, 640))
                footer
            }
            // M9C (Sep 2026): no entrance motion at all, not even on the first open. Kyle
            // reviewed the once-per-session fade in the live build and called for instant —
            // the popover is opened dozens of times a day and any fade reads as latency.
            // 19pt inset / 20pt tile gap / 384pt overall — tuned in the onboarding HTML
            // mockup (Jul 2026); roomier than the original concentric 12pt scheme.
            .padding(19)
            .frame(width: 384)
            // One clean system surface: Liquid Glass on Tahoe, native material on Sequoia.
            // Both paths own their full background so no redundant material muddies the host.
            .modifier(PopoverSurfaceModifier(cornerRadius: 22, forceSolid: forceSolidSurface))
            // Capture the popover's hosting window so opening Settings can dismiss it.
            .background(WindowAccessor { configurePopoverWindow($0) })
            // G1A: the popover is the only surface with a title-ink choice, so this is the
            // one place it enters the view tree (the Settings specimen sets its own).
            .environment(\.accountTitleInk, store.accountTitleInk)
        }
    }

    // MARK: - Scroll feather (R2C23)

    /// R2C23: 14pt, down from 26 — the old band was taller than a whole Micro meter row, so
    /// the last chip in the list rendered as a half-dissolved ghost and the card's bottom rim
    /// never drew at all. Notification Centre, Raycast and Linear all fade ~12–16pt.
    private static let featherHeight: CGFloat = 14

    /// R2C23: non-linear, so the fade is back-loaded and the top two-thirds of the band stays
    /// crisp — a soft edge rather than missing data. A straight `LinearGradient` between two
    /// colours could not express it; these are its three stops.
    private static let featherOpacities: [Double] = [1.0, 0.55, 0.0]

    /// L3A: both ends run the same ramp, so the top feather is this one mirrored rather than
    /// a second hand-kept gradient. `fadesOut: false` is the gated case — a popover that
    /// doesn't scroll keeps its crisp first and last card edge.
    private static func featherStops(fadesOut: Bool, mirrored: Bool = false) -> [Gradient.Stop] {
        let opacities = fadesOut
            ? featherOpacities
            : Array(repeating: 1.0, count: featherOpacities.count)
        let lastIndex = Double(opacities.count - 1)
        let stops = opacities.enumerated().map { index, opacity in
            Gradient.Stop(color: .black.opacity(opacity), location: Double(index) / lastIndex)
        }
        guard mirrored else { return stops }
        return stops.reversed().map {
            Gradient.Stop(color: $0.color, location: 1 - $0.location)
        }
    }

    // MARK: - Bespoke scroll indicator (L2A)

    /// A 3pt capsule whose centre sits 8pt from the shell's right edge, so it lives wholly
    /// inside the 19pt gutter and never touches a card (the cards' right edge is 19pt in).
    /// No track, no well, no hover growth — the three things the stock scroller was faulted
    /// for. Drawn only while the content overflows the 640pt cap.
    @ViewBuilder private var scrollIndicator: some View {
        if scrollMetrics.overflows {
            Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.28 : 0.30))
                .opacity(scrollIndicatorVisible ? 1 : 0)
                // Fade-out is the specified 200ms on `settle`'s curve; the appearance is
                // the shorter `quickSettle` so the cue is already there when the finger
                // lands. S2A: the capsule only ever changes opacity, so Reduce Motion keeps
                // both timings — the geometry below is what stays untweened.
                .animation(scrollIndicatorAnimation, value: scrollIndicatorVisible)
                // Geometry sits outside the animation scope so the capsule slides with the
                // scroll rather than easing behind it.
                .frame(
                    width: PopoverScrollIndicatorMetrics.width,
                    height: scrollIndicatorLength
                )
                .offset(x: PopoverScrollIndicatorMetrics.gutterOffset, y: scrollIndicatorOffsetY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var scrollIndicatorAnimation: Animation? {
        HeadroomMotion.resolved(
            scrollIndicatorVisible ? HeadroomMotion.quickSettle : HeadroomMotion.settle,
            .crossfade,
            reduceMotion: reduceMotion
        )
    }

    /// Proportional length — viewport × (viewport / content) — floored at 24pt so a very
    /// long list still leaves something to see, and capped by the inset track.
    private var scrollIndicatorLength: CGFloat {
        let viewport = scrollMetrics.viewport
        let content = scrollMetrics.content
        guard viewport > 0, content > viewport else { return 0 }
        let track = max(viewport - 2 * PopoverScrollIndicatorMetrics.endInset, 0)
        return min(track, max(PopoverScrollIndicatorMetrics.minimumLength, viewport * (viewport / content)))
    }

    private var scrollIndicatorOffsetY: CGFloat {
        let viewport = scrollMetrics.viewport
        let track = max(viewport - 2 * PopoverScrollIndicatorMetrics.endInset, 0)
        let travel = max(track - scrollIndicatorLength, 0)
        let scrollable = max(scrollMetrics.content - viewport, 1)
        let progress = min(max(scrollMetrics.offset / scrollable, 0), 1)
        return PopoverScrollIndicatorMetrics.endInset + travel * progress
    }

    /// Appears on scroll, holds 900ms, then fades. Each geometry change restarts the hold,
    /// so a continuous drag keeps it lit and it settles once the list stops moving.
    private func flashScrollIndicator(overflows: Bool) {
        scrollIndicatorHideTask?.cancel()
        guard overflows else {
            scrollIndicatorVisible = false
            return
        }
        scrollIndicatorVisible = true
        scrollIndicatorHideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            scrollIndicatorVisible = false
        }
    }

    /// Native pattern: navigating out of the transient menu-bar popover into the persistent
    /// Settings window dismisses the popover (mirrors Control Center → System Settings). The
    /// popover is recreated on next menu-bar click, so closing its window is safe.
    private func openSettingsDismissingPopover() {
        popoverWindow?.close()
        onOpenSettings()
    }

    private func configurePopoverWindow(_ window: NSWindow?) {
        popoverWindow = window
        guard let window else { return }
        // HR-33: keep the custom content radius, but clear the MenuBarExtra host backing
        // so the popover has exactly one system material layer at the rounded edge.
        window.isOpaque = false
        window.backgroundColor = .clear
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
            // keyboard-initiated action must not animate needs no work here: dismissing the
            // popover and opening a window are instant by construction.
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
            guard headerWaitingAccount != nil else { return }
            while !Task.isCancelled {
                waitingClockNow = .now
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// R2M5: the slot is never empty. A phrase and a stamp are different lines rather than a
    /// value that changed, so `.id(status.kind)` replaces the view and the outer `.crossfade`
    /// scope dissolves it — which is also what stops "Waiting for approval…" → "Updated 0 min
    /// ago" from running `numericText` on a word→number swap. The ZStack keeps both copies in
    /// one slot mid-crossfade so the header doesn't relayout under them.
    private func headerStatusSlot(now: Date, baselineOffset: CGFloat) -> some View {
        let status = headerStatus(now: now)
        return ZStack(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
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
        // R2M5/S2A: the replacement is pure opacity, so Reduce Motion keeps its 200ms rather
        // than blinking one sentence into another.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: status.kind
        )
        .alignmentGuide(.firstTextBaseline) { d in
            d[.firstTextBaseline] + baselineOffset
        }
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

    /// R2M5: the popover's single status line, resolved from live captures, retained ones and
    /// the setup card below it. The decision itself is `PopoverHeaderStatusResolver`, so the
    /// six states are pinned by tests without standing up a store, a snapshot and a popover;
    /// this only gathers the inputs.
    private func headerStatus(now: Date) -> PopoverHeaderStatus {
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
        var oldestLiveCapture: Date?
        var newestCheck: Date?
        for id in store.providerOrder {
            for account in store.accounts(for: id) {
                let snapshot = store.snapshot(for: account.key)
                if case .live = snapshot.freshness, let capturedAt = snapshot.capturedAt {
                    oldestLiveCapture = oldestLiveCapture.map { min($0, capturedAt) } ?? capturedAt
                    newestCheck = newestCheck.map { max($0, capturedAt) } ?? capturedAt
                    continue
                }
                // R2M5: a retained row's window keeps the *source* observation anchor across
                // stale and unavailable transitions — the honest answer to "when was this
                // last checked", and the only one left once every provider has gone stale.
                if let observed = retainedObservation(in: snapshot) {
                    newestCheck = newestCheck.map { max($0, observed) } ?? observed
                }
            }
        }
        return PopoverHeaderStatusResolver.status(
            PopoverHeaderStatusResolver.Input(
                setupText: setupText,
                waitingElapsed: waitingElapsed,
                oldestLiveCapture: oldestLiveCapture,
                newestCheck: newestCheck,
                isRefreshing: store.isRefreshing,
                now: now
            )
        )
    }

    /// R2M12: `waitingClockNow` is refreshed once a second by the header's own task while a
    /// handoff is open; `now` is the popover's per-minute tick and stands in until the first
    /// tick lands.
    private func handoffElapsed(for account: ProviderAccount, now: Date) -> TimeInterval? {
        guard let start = SetupSessions.waitingStart(for: account) else { return nil }
        return max(0, max(now, waitingClockNow).timeIntervalSince(start))
    }

    private func retainedObservation(in snapshot: UsageSnapshot) -> Date? {
        let observations = snapshot.windows.compactMap(\.observedAt)
        return observations.max() ?? snapshot.capturedAt
    }

    /// R2M12: the account whose open handoff the header is clocking, if any. Nil also covers
    /// a handoff restored from a durable marker, whose start instant is unknown — that wait
    /// keeps the card-derived line rather than showing an invented duration.
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

    /// Left slot shows a live "Refreshing…" state while a cycle is in flight (UI-02) —
    /// a manual refresh spawns a 20–30s Claude session, so without this the button reads
    /// as broken. The spinner is bound to real work, not decorative motion.
    private var footer: some View {
        HStack {
            // Refresh ⇄ spinner share one slot and cross-fade, so kicking off a 20–30s
            // Claude cycle feels like a state change rather than a control vanishing.
            ZStack(alignment: .leading) {
                if store.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                    .accessibilityLabel("Refreshing usage")
                } else {
                    // PA11b (Kyle): "we do need the resting container for all our buttons."
                    // These two were the model B3H pointed the card chips at — bare labels
                    // whose only affordance arrived with the pointer — so they are the ones
                    // that had to move. `.regular` keeps the footer's 12.5pt type; the chip
                    // brings the container, the border and the press step with it.
                    Button("Refresh") { store.refreshNow() }
                        .buttonStyle(SetupChipButtonStyle(size: .regular))
                        // R2M8: ⌘R is the category's own convention (Raycast, Linear, Ice
                        // all ship it) and a utility opened 30× a day should not need the
                        // pointer. The action itself is instant — the footer's swap is
                        // driven by `isRefreshing`, i.e. by the work, not by the click — so
                        // Emil's "keyboard actions don't animate" rule needs nothing here.
                        .keyboardShortcut("r", modifiers: .command)
                        .transition(.opacity)
                }
            }
            // M11A/S2A: the swap is opacity in a fixed slot, so Reduce Motion keeps the
            // crossfade instead of blinking the control out from under the pointer.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                value: store.isRefreshing
            )
            Spacer()
            // PA11b: same chip as Refresh — the app's only two whole-app controls read as
            // one pair.
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(SetupChipButtonStyle(size: .regular))
        }
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
        return outcome == .claudeLoginRequired
            ? "Sign in to Claude to begin"
            : "Set up Claude to begin"
    }

    static func codex(action: CodexConnectionAction, isWaiting: Bool) -> String {
        guard !isWaiting else { return "Waiting for Codex sign-in…" }
        switch action {
        case .connect: return "Connect Codex to begin"
        case .reconnect: return "Reconnect Codex"
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

    static let notChecked = "Not checked yet"
    static let checking = "Checking…"
}

/// R2M5: one resolved header line. `kind` is the slot's *identity* — a phrase and a stamp are
/// different lines, not one value that changed — and `rollValue` is what the digit roll
/// follows (M2A), nil wherever there are no digits to roll.
struct PopoverHeaderStatus: Equatable {
    enum Kind: Hashable {
        case waiting
        case setup
        case updated
        case checking
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
        var isRefreshing: Bool
        var now: Date
    }

    static func status(_ input: Input) -> PopoverHeaderStatus {
        if let elapsed = input.waitingElapsed {
            return PopoverHeaderStatus(
                kind: .waiting,
                text: PopoverHeaderStatusText.waiting(elapsed: elapsed),
                rollValue: (max(0, elapsed)).rounded(.down)
            )
        }
        if let setupText = input.setupText {
            return PopoverHeaderStatus(kind: .setup, text: setupText, rollValue: nil)
        }
        if let oldest = input.oldestLiveCapture,
           let label = Countdown.updatedLabel(capturedAt: oldest, now: input.now) {
            // M2A: the label's own granularity is whole minutes since capture, so that is the
            // value the roll follows. Between polls it only increases, which is what makes the
            // digits climb; a landing capture resets it and they roll back down.
            return PopoverHeaderStatus(
                kind: .updated,
                text: "Updated \(label)",
                rollValue: elapsedMinutes(since: oldest, now: input.now)
            )
        }
        // R2M5: a cycle in flight with nothing live yet is the one case where the slot has a
        // live action to report rather than an age.
        if input.isRefreshing {
            return PopoverHeaderStatus(
                kind: .checking,
                text: PopoverHeaderStatusText.checking,
                rollValue: nil
            )
        }
        if let newest = input.newestCheck,
           let label = Countdown.updatedLabel(capturedAt: newest, now: input.now) {
            return PopoverHeaderStatus(
                kind: .lastChecked,
                text: "Last checked \(label)",
                rollValue: elapsedMinutes(since: newest, now: input.now)
            )
        }
        return PopoverHeaderStatus(
            kind: .never,
            text: PopoverHeaderStatusText.notChecked,
            rollValue: nil
        )
    }

    private static func elapsedMinutes(since date: Date, now: Date) -> Double {
        (max(0, now.timeIntervalSince(date)) / 60).rounded(.down)
    }
}

/// L2A geometry. The gutter offset is measured from the scroll viewport's trailing edge,
/// which coincides with the cards' right edge 19pt inside the shell: pushing the 3pt
/// capsule out by 12.5pt lands its centre 8pt from the shell edge.
private enum PopoverScrollIndicatorMetrics {
    static let width: CGFloat = 3
    static let minimumLength: CGFloat = 24
    static let endInset: CGFloat = 6
    static let shellMargin: CGFloat = 19
    static let centreFromShellEdge: CGFloat = 8
    static let gutterOffset: CGFloat = shellMargin - centreFromShellEdge + width / 2
}

/// One read of the scroll viewport, shared by both feathers and the indicator so the three
/// stay in step and the popover installs a single `onScrollGeometryChange`.
private struct PopoverScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var viewport: CGFloat = 0
    var content: CGFloat = 0

    var overflows: Bool { viewport > 0 && content > viewport + 1 }
    var continuesAbove: Bool { overflows && offset > 0 }
    var continuesBelow: Bool { offset + viewport < content - 4 }
}

private struct PopoverSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    /// Render-harness only: force the solid shell (ImageRenderer can't rasterize glass).
    var forceSolid: Bool = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || forceSolid || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            // Light glass over a dark desktop lenses the wallpaper into the edge band and
            // muddies the shell (diagnosed Jul 2026, hierarchy log ruled out a second shell);
            // the tint pins the light shell to a light identity while dark mode keeps pure
            // glass. Mirrors how system menu-bar dropdowns read as a light surface.
            if colorScheme == .light {
                content.glassEffect(.regular.tint(Color.white.opacity(0.55)), in: shape)
            } else {
                content.glassEffect(in: shape)
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

/// Resolves the `NSWindow` hosting a SwiftUI view. Used to get a direct handle on the
/// `MenuBarExtra(.window)` popover window — SwiftUI exposes no first-class dismissal for
/// it, and matching by private class name is brittle, so we read `view.window` instead.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
