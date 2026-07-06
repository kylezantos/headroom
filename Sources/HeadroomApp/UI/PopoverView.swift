import SwiftUI
import AppKit
import HeadroomCore

/// The Liquid Glass popover (U7). Composes one card per provider on a Tahoe glass
/// surface, a gear that opens Settings, and a Quit control (required — the app has no
/// Dock presence, KTD9). A `TimelineView` drives a per-minute `now` so countdowns and
/// "updated N min ago" tick without a data poll.
struct PopoverView: View {
    var store: UsageStore
    var preferences = Preferences()
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
            VStack(spacing: 10) {
                header(now: context.date)
                ForEach(Array(store.providerOrder.enumerated()), id: \.element) { _, id in
                    ProviderCardView(
                        providerID: id,
                        displayName: store.displayNames[id] ?? id.raw,
                        snapshot: store.appDisplaySnapshot(for: id),
                        renewalDate: preferences.renewalDate(for: id),
                        now: context.date,
                        onOpenSettings: openSettingsDismissingPopover
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
            // 12pt inset is concentric with the R22 shell → R10 cards (12 + 10 = 22).
            .padding(12)
            .frame(width: 360)
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

    /// The page title now outweighs the card titles (they're `.headline`) so hierarchy
    /// reads top-down, and it carries the single consolidated "Updated" stamp. The gear's
    /// visible glyph stays small but its hit area is padded out to the 40×40 floor.
    private func header(now: Date) -> some View {
        HStack(spacing: 8) {
            Text("Usage")
                .font(.system(size: 15, weight: .bold))
            Spacer(minLength: 8)
            if let updated = headerUpdatedLabel(now: now) {
                Text("Updated \(updated)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            // Native glass control. Its circular boundary sits flush at the content margin —
            // matching "Usage" on the left edge — which fixes the old alignment (a bare glyph
            // whose hit-area padding floated it ~9pt inside the edge).
            Button(action: openSettingsDismissingPopover) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
        }
    }

    /// Single "Updated N min ago" for the whole popover, taken from the *oldest* live
    /// snapshot so it never claims data is fresher than the least-fresh provider. Stale
    /// providers are excluded (their own stale pill carries that story); nil on first run
    /// when nothing is live yet, so the header simply omits it.
    private func headerUpdatedLabel(now: Date) -> String? {
        let liveCaptures = store.providerOrder.compactMap { id -> Date? in
            guard case .live = store.snapshot(for: id).freshness else { return nil }
            return store.snapshot(for: id).capturedAt
        }
        guard let oldest = liveCaptures.min() else { return nil }
        return Countdown.updatedLabel(capturedAt: oldest, now: now)
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
                        Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                    .accessibilityLabel("Refreshing usage")
                } else {
                    Button("Refresh") { store.refreshNow() }
                        .buttonStyle(.glass)
                        .font(.caption)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isRefreshing)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.glass)
                .font(.caption)
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
