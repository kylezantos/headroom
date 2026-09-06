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
                            colors: [scrollContinuesAbove ? .black.opacity(0) : .black, .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 26)
                        Rectangle().fill(.black)
                        LinearGradient(
                            colors: [.black, scrollContinuesBelow ? .black.opacity(0) : .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 26)
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

    /// The page title now outweighs the 16pt card titles so hierarchy reads top-down,
    /// and the right slot carries one contextual status: the consolidated "Updated"
    /// stamp, or the Claude first-run stage ("Set up Claude to begin" / "Watching for
    /// approval…"). The gear's visible glyph stays small but its hit area is padded out
    /// to the 40×40 floor.
    private func header(now: Date) -> some View {
        let statusBaselineOffset = Self.baselineOffsetMatchingTitle(for: Self.statusFont)
        let gearBaselineOffset = Self.inkCenterAboveBaseline(Self.titleFont)
        // All three elements align on one *ink-center* axis (measured against real
        // renders): pure `.center` leaves the title ~2pt low (descender + line box),
        // pure baseline leaves the 11pt status visibly low. So: baseline row, with the
        // status raised 2pt (its ink center then matches the title's) and the gear
        // centered 5pt above the baseline (the title's ink center).
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Usage")
                .font(.system(size: 20, weight: .bold))
                .kerning(-0.2)
            Spacer(minLength: 8)
            if let status = headerStatus(now: now) {
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
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[.firstTextBaseline] + statusBaselineOffset
                    }
            }
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
            // Bare glyph, no container: resting containers are the *cards'* language
            // (non-clickable). Clickability announces itself on approach — hover pill,
            // pointer cursor, press state — via HoverButtonStyle.
            .buttonStyle(HoverButtonStyle(horizontalPadding: 0, verticalPadding: 0))
            .accessibilityLabel("Settings")
            .alignmentGuide(.firstTextBaseline) { d in
                d[VerticalAlignment.center] + gearBaselineOffset
            }
        }
    }

    private static func inkCenterAboveBaseline(_ font: NSFont) -> CGFloat {
        (font.capHeight + font.descender) / 2
    }

    private static func baselineOffsetMatchingTitle(for font: NSFont) -> CGFloat {
        inkCenterAboveBaseline(titleFont) - inkCenterAboveBaseline(font)
    }

    /// M2A: the header's one status slot carries either the numeric "Updated N …" stamp or
    /// non-numeric setup copy. `elapsedMinutes` is nil for the latter, which is what keeps a
    /// phrase like "Watching for approval…" from trying to roll its letters.
    private struct HeaderStatus: Equatable {
        let text: String
        let elapsedMinutes: Double?
    }

    private func headerStatusTransition(_ status: HeaderStatus) -> ContentTransition {
        guard let minutes = status.elapsedMinutes else { return .identity }
        return HeadroomMotion.numericText(value: minutes, reduceMotion: reduceMotion)
    }

    /// Single status for the whole popover. During a guided provider setup it narrates
    /// the stage; otherwise it's "Updated N min ago" from the *oldest* live snapshot so
    /// it never claims data is fresher than the least-fresh provider. Stale providers
    /// are excluded (their own stale pill carries that story); nil on first run when
    /// nothing is live yet, so the header simply omits it.
    private func headerStatus(now: Date) -> HeaderStatus? {
        if let outcome = claudeGuidedSetupOutcome {
            let account = ProviderAccount.builtIn(for: .claude)
            if SetupSessions.isWaiting(for: account) {
                return HeaderStatus(
                    text: outcome == .claudeLoginRequired
                        ? "Watching for Claude sign-in…"
                        : "Watching for approval…",
                    elapsedMinutes: nil
                )
            }
            return HeaderStatus(
                text: outcome == .claudeLoginRequired
                    ? "Sign in to Claude to begin"
                    : "Set up Claude to begin",
                elapsedMinutes: nil
            )
        }
        if codexNeedsConnection {
            let account = ProviderAccount.builtIn(for: .codex)
            return HeaderStatus(
                text: SetupSessions.isWaiting(for: account)
                    ? "Watching for Codex sign-in…"
                    : "Connect Codex to begin",
                elapsedMinutes: nil
            )
        }
        let liveCaptures = store.providerOrder.flatMap { id -> [Date] in
            store.accounts(for: id).compactMap { account in
                let snapshot = store.snapshot(for: account.key)
                guard case .live = snapshot.freshness else { return nil }
                return snapshot.capturedAt
            }
        }
        guard let oldest = liveCaptures.min(),
              let label = Countdown.updatedLabel(capturedAt: oldest, now: now) else { return nil }
        // M2A: the label's own granularity is whole minutes since capture, so that is the
        // value the roll follows. Between polls it only increases, which is what makes the
        // digits climb; a landing capture resets it and they roll back down.
        return HeaderStatus(
            text: "Updated \(label)",
            elapsedMinutes: (max(0, now.timeIntervalSince(oldest)) / 60).rounded(.down)
        )
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

    private var codexNeedsConnection: Bool {
        guard store.providerOrder.contains(.codex) else { return false }
        return store.appDisplaySnapshot(for: .codex).codexConnectionAction != nil
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
                    // Quiet bare-text controls (no chip): resting containers belong to
                    // the cards; hover/press/cursor carry the affordance.
                    Button("Refresh") { store.refreshNow() }
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
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
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
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
