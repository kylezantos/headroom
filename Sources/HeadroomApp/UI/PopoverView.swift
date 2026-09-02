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
    /// Render-harness only: `ImageRenderer` does not fire `onAppear`, so the entrance
    /// fade would leave the snapshot fully transparent. Forces the content visible for
    /// the offscreen marketing export; the live app leaves this off.
    var forceVisible: Bool = false
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
    // Drives the first-session open fade. Subsequent menu-bar opens are instant because
    // SwiftUI recreates this view per open; replaying motion there reads as latency.
    @State private var appeared = false
    @State private var animatesEntrance = false
    /// Content extends past the scroll cap and isn't scrolled to the bottom — gates
    /// the bottom fade so it never softens a fully visible last card.
    @State private var scrollContinuesBelow = false
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
            let anyProviderMultiAccount = store.providerOrder.contains {
                store.accounts(for: $0).count > 1
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
                        }
                        APISpendSectionView(store: store, now: context.date, onOpenSettings: openSettingsDismissingPopover)
                    }
                    // Scroll content is laid out at its ideal height regardless of the
                    // ScrollView's own frame, so this reports the true stack height even
                    // on the first pass while the frame below is still zero.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                // Soft bottom fade while content continues below the cap — the flat
                // clip alone read as a card with missing data (impeccable audit P2).
                // Overflow-gated so the common non-scrolling popover keeps its crisp
                // final card edge.
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 4
                } action: { _, overflows in
                    scrollContinuesBelow = overflows
                }
                .mask {
                    VStack(spacing: 0) {
                        Rectangle().fill(.black)
                        LinearGradient(
                            colors: [.black, scrollContinuesBelow ? .black.opacity(0) : .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 26)
                    }
                }
                .animation(reduceMotion ? nil : HeadroomMotion.settle, value: scrollContinuesBelow)
                .frame(height: forcedCardsHeight ?? min(cardsHeight, 640))
                footer
            }
            // One quick content fade on open — no per-row stagger or vertical travel.
            .opacity((appeared || forceVisible) ? 1 : 0)
            .animation(reduceMotion || !animatesEntrance ? nil : HeadroomMotion.quickSettle, value: appeared)
            // 19pt inset / 20pt tile gap / 384pt overall — tuned in the onboarding HTML
            // mockup (Jul 2026); roomier than the original concentric 12pt scheme.
            .padding(19)
            .frame(width: 384)
            // One clean system surface: Liquid Glass on Tahoe, native material on Sequoia.
            // Both paths own their full background so no redundant material muddies the host.
            .modifier(PopoverSurfaceModifier(cornerRadius: 22, forceSolid: forceSolidSurface))
            // Capture the popover's hosting window so opening Settings can dismiss it.
            .background(WindowAccessor { configurePopoverWindow($0) })
            .onAppear {
                guard !PopoverEntranceAnimation.hasAnimatedThisSession else {
                    appeared = true
                    return
                }
                animatesEntrance = true
                appeared = true
                PopoverEntranceAnimation.hasAnimatedThisSession = true
            }
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
                Text(status)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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

    /// Single status for the whole popover. During a guided provider setup it narrates
    /// the stage; otherwise it's "Updated N min ago" from the *oldest* live snapshot so
    /// it never claims data is fresher than the least-fresh provider. Stale providers
    /// are excluded (their own stale pill carries that story); nil on first run when
    /// nothing is live yet, so the header simply omits it.
    private func headerStatus(now: Date) -> String? {
        if let outcome = claudeGuidedSetupOutcome {
            let account = ProviderAccount.builtIn(for: .claude)
            if SetupSessions.isWaiting(for: account) {
                return outcome == .claudeLoginRequired ? "Watching for Claude sign-in…" : "Watching for approval…"
            }
            return outcome == .claudeLoginRequired ? "Sign in to Claude to begin" : "Set up Claude to begin"
        }
        if codexNeedsConnection {
            let account = ProviderAccount.builtIn(for: .codex)
            return SetupSessions.isWaiting(for: account) ? "Watching for Codex sign-in…" : "Connect Codex to begin"
        }
        let liveCaptures = store.providerOrder.flatMap { id -> [Date] in
            store.accounts(for: id).compactMap { account in
                let snapshot = store.snapshot(for: account.key)
                guard case .live = snapshot.freshness else { return nil }
                return snapshot.capturedAt
            }
        }
        guard let oldest = liveCaptures.min() else { return nil }
        return Countdown.updatedLabel(capturedAt: oldest, now: now).map { "Updated \($0)" }
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
            .animation(reduceMotion ? nil : HeadroomMotion.settle, value: store.isRefreshing)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private enum PopoverEntranceAnimation {
    static var hasAnimatedThisSession = false
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
