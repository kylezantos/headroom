import SwiftUI
import AppKit
import HeadroomCore

/// Headroom's identity glyph: a vessel filled from the bottom — the empty space on top
/// *is* the headroom the app tracks. The menu-bar fill is dynamic: it drains with the
/// weekly usage of the provider chosen in Settings (`UsageStore.menuBarFill`).
///
/// Status bar labels are most reliable when the final meter is an `NSImage`. Earlier
/// SwiftUI shape-based attempts rendered blank in the menu bar, so the glyph is drawn
/// into an `NSImage` and shown directly.
/// It is not a template image: the fill is always severity-colored, while the vessel
/// stroke stays neutral except in the critical band. Images are cached per whole-percent
/// fill level, severity, and menu-bar appearance so live updates don't re-rasterize on every
/// redraw. Static — no motion (user's standing rule).
enum VesselGlyph {
    /// Point size tuned to sit level with system menu-bar glyphs (~16–18pt tall).
    static let menuBarSize = NSSize(width: 11, height: 18)
    /// Fill used when no provider drives the level (automatic mode, or no data yet).
    static let staticFill = 0.46

    @MainActor private static var cache: [ImageKey: NSImage] = [:]

    /// Cached vessel at the given fill (0…1); `nil` → the static decorative fill. The
    /// palette is part of the cache key (L1A): the same level renders differently on a light
    /// menu bar than on a dark one.
    @MainActor static func menuBarImage(
        fill: Double?,
        severity: UsageSeverity,
        isNeutral: Bool,
        palette: MenuBarPalette
    ) -> NSImage {
        let clamped = min(1, max(0, fill ?? staticFill))
        let bucket = Int((clamped * 100).rounded())
        let key = ImageKey(
            fillBucket: bucket,
            severity: severity,
            isNeutral: isNeutral,
            isDarkMenuBar: palette.isDarkMenuBar
        )
        if let cached = cache[key] { return cached }
        let image = render(
            size: menuBarSize,
            lineWidth: 1.6,
            fill: CGFloat(bucket) / 100,
            severity: severity,
            isNeutral: isNeutral,
            palette: palette
        )
        cache[key] = image
        return image
    }

    private static func render(
        size: NSSize,
        lineWidth: CGFloat,
        fill: CGFloat,
        severity: UsageSeverity,
        isNeutral: Bool,
        palette: MenuBarPalette
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            // Capsule wall (stroke stays inside the bounds).
            let wallRect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let wall = NSBezierPath(roundedRect: wallRect,
                                    xRadius: wallRect.width / 2,
                                    yRadius: wallRect.width / 2)
            wall.lineWidth = lineWidth
            strokeColor(for: severity, isNeutral: isNeutral, palette: palette).setStroke()
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
            fillColor(for: severity, isNeutral: isNeutral, palette: palette).setFill()
            NSBezierPath(rect: liquid).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

    // L1A (Sep 2026): the palette follows the *menu bar's* effective appearance instead of
    // being pinned dark. `VesselGlyph` renders ONLY the menu-bar status item (the widget uses
    // a separate `VesselMark`), and SwiftUI rasterizes the resulting `Image(nsImage:)`
    // against the *system* appearance — so every color here is resolved to an explicit value
    // by `MenuBarPalette` rather than left as a dynamic `NSColor`, and nothing depends on
    // which appearance the rasterizer is in. See MenuBarLabel / MenuBarAppearanceMonitor.
    private static func strokeColor(
        for severity: UsageSeverity,
        isNeutral: Bool,
        palette: MenuBarPalette
    ) -> NSColor {
        // The critical band is the one case where the wall itself carries severity.
        if !isNeutral, severity == .critical {
            return fillColor(for: severity, isNeutral: false, palette: palette)
        }
        return palette.ink.menuBarColor
    }

    private static func fillColor(
        for severity: UsageSeverity,
        isNeutral: Bool,
        palette: MenuBarPalette
    ) -> NSColor {
        guard !isNeutral else { return palette.neutralLiquid.menuBarColor }
        return palette.liquid(for: severity).menuBarColor
    }

    private struct ImageKey: Hashable {
        let fillBucket: Int
        let severity: String
        let isNeutral: Bool
        let isDarkMenuBar: Bool

        init(fillBucket: Int, severity: UsageSeverity, isNeutral: Bool, isDarkMenuBar: Bool) {
            self.fillBucket = fillBucket
            self.severity = String(describing: severity)
            self.isNeutral = isNeutral
            self.isDarkMenuBar = isDarkMenuBar
        }
    }
}
