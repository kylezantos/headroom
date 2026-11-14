import AppKit
import Testing
@testable import Headroom

/// SQ2 (macOS 15.7.7 VM, 2026-10-30): PC1 rounded every leaf of the popover's content view to
/// the shell's 22pt corner. On macOS 15 those leaves include the header's own drawing, so
/// "Usage" drew as "Jsage", the status line lost both ends and the gear became a diamond.
/// Only a leaf spanning the content is a host backdrop worth rounding.
@Suite(.sharedAppState)
struct PopoverHostBackdropTests {
    private let bounds = NSRect(x: 0, y: 0, width: 384, height: 440)
    private let radius: CGFloat = 22

    @Test func aLeafSpanningTheContentQualifies() {
        #expect(PopoverHostBackdrop.spansContent(bounds, bounds: bounds, cornerRadius: radius))
        // Within a point on every edge (fractional scales, a resize pass in flight).
        #expect(PopoverHostBackdrop.spansContent(
            NSRect(x: -0.5, y: 0.5, width: 384.5, height: 439.5), bounds: bounds, cornerRadius: radius
        ))
    }

    /// The leaves the macOS 15.7.7 VM logged inside a 384×440 popover, all rounded before SQ2.
    @Test func theHeaderLeavesFromTheMacOS15LogDoNotQualify() {
        let headerLeaves = [
            NSRect(x: 19, y: 26, width: 60, height: 21),      // "Usage" (CGDrawingView)
            NSRect(x: 192, y: 28, width: 133, height: 14),    // header status line (CGDrawingView)
            NSRect(x: 341, y: 27, width: 16, height: 16),     // gear (_NSShapeHitTestingView)
            NSRect(x: 333, y: 19, width: 32, height: 32),     // gear focus ring (_FocusRingView)
            NSRect(x: 141, y: -41.5, width: 32, height: 32),  // KeyViewProxy
        ]
        for leaf in headerLeaves {
            #expect(!PopoverHostBackdrop.spansContent(leaf, bounds: bounds, cornerRadius: radius))
        }
    }

    @Test func aLeafShortOfAnyEdgeDoesNotQualify() {
        #expect(!PopoverHostBackdrop.spansContent(
            NSRect(x: 0, y: 0, width: 384, height: 420), bounds: bounds, cornerRadius: radius
        ))
        #expect(!PopoverHostBackdrop.spansContent(
            NSRect(x: 19, y: 0, width: 365, height: 440), bounds: bounds, cornerRadius: radius
        ))
        // A leaf wider than the content is not a backdrop of this window either.
        #expect(!PopoverHostBackdrop.spansContent(
            NSRect(x: -20, y: 0, width: 424, height: 440), bounds: bounds, cornerRadius: radius
        ))
    }

    /// A first pass before the window has a size: a small leaf matching zero or tiny bounds
    /// must not be rounded on the way through.
    @Test func contentTooSmallForTheCornerQualifiesNothing() {
        #expect(!PopoverHostBackdrop.spansContent(.zero, bounds: .zero, cornerRadius: radius))
        let tiny = NSRect(x: 0, y: 0, width: 60, height: 21)
        #expect(!PopoverHostBackdrop.spansContent(tiny, bounds: tiny, cornerRadius: radius))
    }
}
