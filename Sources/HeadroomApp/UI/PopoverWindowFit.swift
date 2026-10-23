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

/// SQ1: fits the popover window's height to the content on macOS 15, top edge kept under the
/// status item, the way `PopoverView.fitPopoverWindow(columns:)` fits a narrower width. macOS 26
/// sizes the `MenuBarExtra` window correctly on its own, so it is left alone there. Owned by
/// `PopoverView` like its plan model; the ideal height reaches it from layout, outside
/// observation, so a report never re-runs a body.
@MainActor
final class PopoverWindowHeightFitter {
    weak var window: NSWindow?
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
        let bottomLimit = window.screen?.visibleFrame.minY
        guard let frame = Self.fittedFrame(current: window.frame, targetHeight: idealHeight, bottomLimit: bottomLimit)
        else { return }
        window.setFrame(frame, display: window.isVisible)
        window.invalidateShadow()
    }

    nonisolated static let tolerance: CGFloat = 0.5

    /// `current` with its height changed to `targetHeight` and its top edge where it was, or nil
    /// when it is already within half a point. `bottomLimit` (the screen's visible bottom)
    /// keeps a tall popover above the Dock; the top-pinned layout scrolls what doesn't fit.
    nonisolated static func fittedFrame(current: NSRect, targetHeight: CGFloat, bottomLimit: CGFloat? = nil) -> NSRect? {
        var height = targetHeight
        if let bottomLimit, current.maxY - bottomLimit > 0 { height = min(height, current.maxY - bottomLimit) }
        guard height > 0, abs(current.height - height) > tolerance else { return nil }
        return NSRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
    }

    /// On macOS 26 the `MenuBarExtra` window's height already follows the content. The macOS 15.0
    /// report points to a window left shorter than the content there (unconfirmed on a device).
    static var isEnabled: Bool {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        if #unavailable(macOS 26.0) { return true }
        return false
    }

    #if DEBUG
    /// Exercises the macOS 15 path on 26: tests set it, and `HEADROOM_FORCE_POPOVER_HEIGHT_FIT=1`
    /// (or `0`) sets it for a debug `swift run`. Nil leaves it to the OS.
    static var debugOverride: Bool? = ProcessInfo.processInfo.environment["HEADROOM_FORCE_POPOVER_HEIGHT_FIT"]
        .map { $0 == "1" }
    #endif
}

/// SQ1: the header title's bounds. Only the hosting test reads it; nothing in the app does.
struct PopoverHeaderTitleAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
