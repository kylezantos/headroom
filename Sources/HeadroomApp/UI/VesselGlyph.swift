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
/// fill level and severity so live updates don't re-rasterize on every redraw. Static —
/// no motion (user's standing rule).
enum VesselGlyph {
    /// Point size tuned to sit level with system menu-bar glyphs (~16–18pt tall).
    static let menuBarSize = NSSize(width: 11, height: 18)
    /// Fill used when no provider drives the level (automatic mode, or no data yet).
    static let staticFill = 0.46

    @MainActor private static var cache: [ImageKey: NSImage] = [:]

    /// Cached vessel at the given fill (0…1); `nil` → the static decorative fill.
    @MainActor static func menuBarImage(fill: Double?, severity: UsageSeverity, isNeutral: Bool) -> NSImage {
        let clamped = min(1, max(0, fill ?? staticFill))
        let bucket = Int((clamped * 100).rounded())
        let key = ImageKey(fillBucket: bucket, severity: severity, isNeutral: isNeutral)
        if let cached = cache[key] { return cached }
        let image = render(
            size: menuBarSize,
            lineWidth: 1.6,
            fill: CGFloat(bucket) / 100,
            severity: severity,
            isNeutral: isNeutral
        )
        cache[key] = image
        return image
    }

    private static func render(
        size: NSSize,
        lineWidth: CGFloat,
        fill: CGFloat,
        severity: UsageSeverity,
        isNeutral: Bool
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            // Capsule wall (stroke stays inside the bounds).
            let wallRect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let wall = NSBezierPath(roundedRect: wallRect,
                                    xRadius: wallRect.width / 2,
                                    yRadius: wallRect.width / 2)
            wall.lineWidth = lineWidth
            strokeColor(for: severity, isNeutral: isNeutral).setStroke()
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
            fillColor(for: severity, isNeutral: isNeutral).setFill()
            NSBezierPath(rect: liquid).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = false
        return image
    }

    // Menu bar palette pinned dark (Jul 2026). `VesselGlyph` renders ONLY the menu-bar
    // status item (the widget uses a separate `VesselMark`), and SwiftUI rasterizes the
    // resulting `Image(nsImage:)` against the *system* appearance — so a dynamic `NSColor`
    // bakes to its light value in light mode while a sibling `.labelColor` stays dynamic and
    // resolves white on the dark menu bar, giving a mixed palette. The Tahoe menu bar always
    // paints status items on a dark translucent backplate, so both the stroke and the fills
    // pin to their dark-scheme values regardless of system appearance. See MenuBarLabel.
    private static func strokeColor(for severity: UsageSeverity, isNeutral: Bool) -> NSColor {
        if !isNeutral, severity == .critical { return fillColor(for: severity, isNeutral: false) }
        return .white
    }

    private static func fillColor(for severity: UsageSeverity, isNeutral: Bool) -> NSColor {
        guard !isNeutral else { return NSColor.white.withAlphaComponent(0.62) }
        // The liquid is a meter fill, so it reads from the fill tier — but pinned dark, where
        // the fill and text tiers are the same values and Increase Contrast is a no-op. The
        // menu bar has no SwiftUI environment to read, and its backplate is always dark.
        let rgb = HeadroomSeverityColorValues.fill(for: severity, dark: true, increasedContrast: false)
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }

    private struct ImageKey: Hashable {
        let fillBucket: Int
        let severity: String
        let isNeutral: Bool

        init(fillBucket: Int, severity: UsageSeverity, isNeutral: Bool) {
            self.fillBucket = fillBucket
            self.severity = String(describing: severity)
            self.isNeutral = isNeutral
        }
    }
}
