import SwiftUI
import AppKit
import HeadroomCore

/// The Liquid Glass popover (U7). Composes one card per provider on a Tahoe glass
/// surface, a gear that opens Settings, and a Quit control (required — the app has no
/// Dock presence, KTD9). A `TimelineView` drives a per-minute `now` so countdowns and
/// "updated N min ago" tick without a data poll.
struct PopoverView: View {
    var store: UsageStore
    var onOpenSettings: () -> Void

    @State private var popoverWindow: NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Drives the one-shot content fade. The popover is recreated on each menu-bar click, so
    // this resets to false and the quiet settle replays on every open.
    @State private var appeared = false

    /// One fast, custom ease-out settle for the whole popover content on open (Emil flags
    /// built-in `ease`/`easeOut` as lacking strength; this curve is a strong ease-out).
    private static let entrance = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 20) {
                header(now: context.date)
                    // Header sits 14pt above the first card (vs the 20pt tile gap) — the
                    // title belongs to the content below it more than cards belong to
                    // each other.
                    .padding(.bottom, -6)
                ForEach(Array(store.providerOrder.enumerated()), id: \.element) { _, id in
                    ProviderCardView(
                        providerID: id,
                        displayName: store.displayNames[id] ?? id.raw,
                        snapshot: store.appDisplaySnapshot(for: id),
                        now: context.date,
                        onRetrySetup: { store.refreshNow() }
                    )
                }
                APISpendSectionView(store: store, now: context.date, onOpenSettings: openSettingsDismissingPopover)
                footer
            }
            // One quiet content fade on open — no per-row stagger. Emil's frequency rule:
            // this popover is opened often, so a cascading entrance that replays every time
            // fights the "don't make me wait" expectation. Content-only, so the glass stays
            // put; snaps in instantly under Reduce Motion.
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 4)
            .animation(reduceMotion ? nil : Self.entrance, value: appeared)
            // 19pt inset / 20pt tile gap / 384pt overall — tuned in the onboarding HTML
            // mockup (Jul 2026); roomier than the original concentric 12pt scheme.
            .padding(19)
            .frame(width: 384)
            // One clean glass layer: the `.glassEffect` already supplies the material, so the
            // redundant `.ultraThinMaterial` stacked underneath is gone — more native, less muddy.
            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            // Capture the popover's hosting window so opening Settings can dismiss it.
            .background(WindowAccessor { popoverWindow = $0 })
            .onAppear { appeared = true }
        }
    }

    /// Native pattern: navigating out of the transient menu-bar popover into the persistent
    /// Settings window dismisses the popover (mirrors Control Center → System Settings). The
    /// popover is recreated on next menu-bar click, so closing its window is safe.
    private func openSettingsDismissingPopover() {
        popoverWindow?.close()
        onOpenSettings()
    }

    /// The page title now outweighs the 16pt card titles so hierarchy reads top-down,
    /// and the right slot carries one contextual status: the consolidated "Updated"
    /// stamp, or the Claude first-run stage ("Set up Claude to begin" / "Watching for
    /// approval…"). The gear's visible glyph stays small but its hit area is padded out
    /// to the 40×40 floor.
    private func header(now: Date) -> some View {
        // All three elements align on one *ink-center* axis (measured against real
        // renders): pure `.center` leaves the title ~2pt low (descender + line box),
        // pure baseline leaves the 11pt status visibly low. So: baseline row, with the
        // status raised 2pt (its ink center then matches the title's) and the gear
        // centered 5pt above the baseline (the title's ink center).
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Usage")
                .font(.system(size: 20, weight: .bold))
                .kerning(-0.2)
            Spacer(minLength: 8)
            if let status = headerStatus(now: now) {
                Text(status)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] + 2 }
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
            // Circle center on the title's ink center: ≈5pt above the baseline for
            // 20pt SF bold (cap 14pt up, descender ~4pt down → mass center −5).
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
        }
    }

    /// Single status for the whole popover. During Claude's first-run setup it narrates
    /// the stage; otherwise it's "Updated N min ago" from the *oldest* live snapshot so
    /// it never claims data is fresher than the least-fresh provider. Stale providers
    /// are excluded (their own stale pill carries that story); nil on first run when
    /// nothing is live yet, so the header simply omits it.
    private func headerStatus(now: Date) -> String? {
        if claudeNeedsTrustSetup {
            return ClaudeSetupSession.openedSetupAt != nil ? "Watching for approval…" : "Set up Claude to begin"
        }
        let liveCaptures = store.providerOrder.compactMap { id -> Date? in
            guard case .live = store.snapshot(for: id).freshness else { return nil }
            return store.snapshot(for: id).capturedAt
        }
        guard let oldest = liveCaptures.min() else { return nil }
        return Countdown.updatedLabel(capturedAt: oldest, now: now).map { "Updated \($0)" }
    }

    private var claudeNeedsTrustSetup: Bool {
        guard store.providerOrder.contains(.claude),
              case .stale(let reason) = store.appDisplaySnapshot(for: .claude).freshness else { return false }
        return reason.isPermanent && reason.message == ClaudeUsageWorkspace.trustRequiredMessage
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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isRefreshing)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
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
