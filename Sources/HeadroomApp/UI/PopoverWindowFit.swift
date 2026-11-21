import AppKit
import SwiftUI

/// SQ1 (macOS 15.0 report, 2026-10-11: "The header 'Usage' is clipped"): the popover's root.
/// A hosting view centres content that is taller than it, so a `MenuBarExtra` window shorter
/// than the popover cut the header and the footer by the same amount.
///
/// The root still answers the content's ideal size for every proposal, so the host sizes and
/// grows its window exactly as before. (A hosting view grows its window from the size its root
/// answers at the current bounds; answering the window's own height there stopped it growing, and
/// the column sizing tests caught it.) What changes is placement. In a window shorter than the
/// content (the proposal), the content is laid out at the window's height in a box centred on
/// this root's centre. The host centres this root in the window, so that box is the window: the
/// header sits at its top, and the card list (the one flexible piece) gives up the difference, so
/// the footer stays too. At or above the ideal height nothing moves.
struct PopoverTopPinnedLayout: Layout {
    /// The content's ideal height, reported from inside layout as it is placed. Only the
    /// window fitter reads it, and it acts on the next main turn, never during the pass.
    var reportIdealHeight: (@Sendable (CGFloat) -> Void)?

    /// The content's ideal height at the proposed width: what the fixed-height popover answered
    /// for every proposal before its card list could give up height.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        return content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let visible = Self.visibleHeight(proposed: proposal.height, ideal: bounds.height)
        content.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY - visible / 2),
            anchor: .top,
            proposal: ProposedViewSize(width: bounds.width, height: visible)
        )
        reportIdealHeight?(bounds.height)
    }

    /// The window's height when it is a real one shorter than the content, else the content's.
    /// Zero (a minimum-size probe) and infinity mean no window, so they keep the content's height.
    static func visibleHeight(proposed: CGFloat?, ideal: CGFloat) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 0, proposed < ideal else { return ideal }
        return proposed
    }
}

/// SQ1: fits the popover window's height to the content, top edge kept under the status item,
/// the way `PopoverView.fitPopoverWindow(columns:)` fits a narrower width. On macOS 15 it fits
/// both ways. On macOS 26 the `MenuBarExtra` window grows with the content on its own but never
/// shrinks, so the fitter only shrinks it there (GF1). Owned by `PopoverView` like its plan model;
/// the ideal height reaches it from layout, outside observation, so a report never re-runs a body.
@MainActor
final class PopoverWindowHeightFitter {
    weak var window: NSWindow?
    /// A view inside the popover's hosting view (the window accessor), so the fit can count
    /// whatever the window wraps around that hosting view.
    weak var anchor: NSView?
    private var idealHeight: CGFloat?
    private var fitScheduled = false

    /// Heights reported during layout are acted on after the pass.
    func report(_ height: CGFloat) {
        guard Self.isEnabled else { return }
        if let idealHeight, abs(idealHeight - height) <= Self.tolerance { return }
        idealHeight = height
        scheduleFit()
    }

    /// The window just resolved or the popover opened: fit it to the last height reported.
    func scheduleFit() {
        guard Self.isEnabled, !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fitScheduled = false
            fit()
        }
    }

    private func fit() {
        guard let window, let idealHeight else { return }
        let host = anchor.flatMap(Self.outermostHostingView(containing:)) ?? window.contentView
        let target = Self.windowHeight(
            forContent: idealHeight,
            windowHeight: window.frame.height,
            hostHeight: host?.bounds.height ?? window.frame.height,
            hostSafeArea: host.map { $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } ?? 0
        )
        let bottomLimit = Self.visibleBottom(
            under: window.frame,
            screens: NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) },
            fallback: window.screen?.visibleFrame
        )
        guard let frame = Self.fittedFrame(
            current: window.frame, targetHeight: target, bottomLimit: bottomLimit,
            allowsGrowth: Self.mode.allowsGrowth
        ) else { return }
        window.setFrame(frame, display: window.isVisible)
        window.invalidateShadow()
    }

    nonisolated static let tolerance: CGFloat = 0.5

    /// The window height that gives the popover `content` points: the content plus whatever the
    /// window keeps outside the hosting view (a title bar or top inset, the brief's H2) and any
    /// safe area the hosting view keeps the content out of. A host taller than its window adds
    /// nothing.
    nonisolated static func windowHeight(
        forContent content: CGFloat, windowHeight: CGFloat, hostHeight: CGFloat, hostSafeArea: CGFloat = 0
    ) -> CGFloat {
        content + max(windowHeight - hostHeight, 0) + max(hostSafeArea, 0)
    }

    nonisolated static func visibleBottom(
        under frame: NSRect, screens: [(frame: NSRect, visible: NSRect)], fallback: NSRect?
    ) -> CGFloat? {
        visibleFrame(under: frame, screens: screens, fallback: fallback)?.minY
    }

    /// The visible frame of the screen the popover hangs from: the one holding the window's
    /// top-centre point (just inside it), not `NSWindow.screen`, which picks the screen with the
    /// largest overlap and so, with a display stacked below the menu-bar display, can be the
    /// lower one. `fallback` (the window's own screen) covers a top edge on no screen.
    nonisolated static func visibleFrame(
        under frame: NSRect, screens: [(frame: NSRect, visible: NSRect)], fallback: NSRect?
    ) -> NSRect? {
        let topCentre = NSPoint(x: frame.midX, y: frame.maxY - 1)
        return screens.first { $0.frame.contains(topCentre) }?.visible ?? fallback
    }

    /// The outermost hosting view above `anchor`: the one the host sized for the popover.
    static func outermostHostingView(containing anchor: NSView) -> NSView? {
        var found: NSView?
        var view: NSView? = anchor.superview
        while let current = view {
            if String(describing: type(of: current)).contains("HostingView") { found = current }
            view = current.superview
        }
        return found
    }

    /// `current` with its height changed to `targetHeight` and its top edge where it was, or nil
    /// when it is already within half a point. `bottomLimit` (the screen's visible bottom)
    /// keeps a tall popover above the Dock; the top-pinned layout scrolls what doesn't fit.
    /// Without `allowsGrowth` (macOS 26, GF1) a window shorter than the target is left to the
    /// host, which grows it on its own.
    nonisolated static func fittedFrame(
        current: NSRect, targetHeight: CGFloat, bottomLimit: CGFloat? = nil, allowsGrowth: Bool = true
    ) -> NSRect? {
        var height = targetHeight
        if let bottomLimit, current.maxY - bottomLimit > 0 { height = min(height, current.maxY - bottomLimit) }
        guard height > 0, abs(current.height - height) > tolerance else { return nil }
        guard allowsGrowth || height < current.height else { return nil }
        return NSRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
    }

    enum Mode: Sendable, Equatable {
        case off
        /// macOS 15: the 15.0 report points to a window left shorter than the content
        /// (unconfirmed on a device), so the fitter grows as well as shrinks.
        case fit
        /// macOS 26 (GF1, 2026-11-21): the window grows with the content on its own but never
        /// shrinks. The first open after launch lays out one tall column before the plan turns to
        /// two, so the window kept the tall height and the shorter two-column popover sat ~70pt
        /// below the menu bar, centred in it, on every open.
        case shrinkOnly

        var allowsGrowth: Bool { self == .fit }
    }

    static var mode: Mode {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        if #unavailable(macOS 26.0) { return .fit }
        return .shrinkOnly
    }

    static var isEnabled: Bool { mode != .off }

    #if DEBUG
    /// Tests set it; `HEADROOM_FORCE_POPOVER_HEIGHT_FIT=1` exercises the macOS 15 path on 26 for a
    /// debug `swift run`, and `0` turns the fitter off. Nil leaves it to the OS.
    static var debugOverride: Mode? = ProcessInfo.processInfo.environment["HEADROOM_FORCE_POPOVER_HEIGHT_FIT"]
        .map { $0 == "1" ? .fit : .off }
    #endif
}

/// SQ1: the header title's bounds. Only the hosting test reads it; nothing in the app does.
struct PopoverHeaderTitleAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
