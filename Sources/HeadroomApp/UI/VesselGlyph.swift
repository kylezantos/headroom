import SwiftUI
import AppKit

/// Headroom's identity glyph: a vessel filled from the bottom — the empty space on top
/// *is* the headroom the app tracks. The menu-bar fill is dynamic: it drains with the
/// weekly usage of the provider chosen in Settings (`UsageStore.menuBarFill`).
///
/// `MenuBarExtra` labels only reliably rasterize `Text`/`Image` primitives; a custom
/// `Shape`/`GeometryReader` view renders blank in the menu bar (that's why the item was
/// invisible). So the glyph is drawn into a **template `NSImage`** and shown via
/// `Image(nsImage:)`. Being a template, it inherits the severity tint from the
/// surrounding `foregroundStyle` (healthy → amber → red) exactly like an SF Symbol.
/// Images are cached per whole-percent fill level so live updates don't re-rasterize on
/// every redraw. Static — no motion (user's standing rule).
enum VesselGlyph {
    /// Point size tuned to sit level with system menu-bar glyphs (~16–18pt tall).
    static let menuBarSize = NSSize(width: 11, height: 18)
    /// Fill used when no provider drives the level (`.none`, or no weekly data yet).
    static let staticFill = 0.46

    @MainActor private static var cache: [Int: NSImage] = [:]

    /// Cached vessel template at the given fill (0…1); `nil` → the static decorative fill.
    @MainActor static func menuBarImage(fill: Double?) -> NSImage {
        let clamped = min(1, max(0, fill ?? staticFill))
        let bucket = Int((clamped * 100).rounded())
        if let cached = cache[bucket] { return cached }
        let image = render(size: menuBarSize, lineWidth: 1.6, fill: CGFloat(bucket) / 100)
        cache[bucket] = image
        return image
    }

    private static func render(size: NSSize, lineWidth: CGFloat, fill: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            NSColor.black.set()

            // Capsule wall (stroke stays inside the bounds).
            let wallRect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let wall = NSBezierPath(roundedRect: wallRect,
                                    xRadius: wallRect.width / 2,
                                    yRadius: wallRect.width / 2)
            wall.lineWidth = lineWidth
            wall.stroke()

            // Liquid: clip to an inset capsule, then fill the lower `fill` fraction. The
            // clip supplies the rounded base; the fill rectangle supplies the flat top.
            let inner = bounds.insetBy(dx: lineWidth + 0.6, dy: lineWidth + 0.6)
            let clip = NSBezierPath(roundedRect: inner,
                                    xRadius: inner.width / 2,
                                    yRadius: inner.width / 2)
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            // flipped: false → origin is bottom-left, so the liquid sits at the base.
            let liquid = NSRect(x: inner.minX, y: inner.minY,
                                width: inner.width, height: inner.height * fill)
            NSBezierPath(rect: liquid).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
