import AppKit
import Foundation
import HeadroomCore
import Testing
@testable import Headroom

/// OA2: the brand SVGs are trimmed so the path's tight bounding box *is* the viewBox. That
/// is the fact `HeadroomBrandMark`'s sizing rule stands on — with untrimmed art, "13/15 of
/// the slot" would size each mark's *margins* differently instead of its ink. These tests
/// rasterise the shipped artwork exactly the way `ProviderLogoView` draws it and fail if a
/// mark is ever re-cut with padding, or if a light/dark pair drifts apart so the mark would
/// shift when the appearance changes.
@Suite(.sharedAppState)
struct BrandMarkInkTests {
    private static let brandIconsDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HeadroomAppTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/HeadroomApp/Resources/BrandIcons")

    private static let markFiles = [
        "claude-color", "codex-color", "cursor-dark", "cursor-light", "grok-dark", "grok-light",
        "copilot-dark", "copilot-light", "opencode-dark", "opencode-light",
        "antigravity-dark", "antigravity-light",
    ]

    /// The ink box as a fraction of the drawn image, plus the image's own aspect. Drawn into
    /// a square: `NSImage.draw(in:)` stretches rather than letterboxes, so a trimmed mark
    /// reports ink at all four edges whatever its aspect.
    private struct InkBox {
        var left: Double
        var right: Double
        var top: Double
        var bottom: Double
        var aspect: Double
    }

    private static func inkBox(of name: String) throws -> InkBox {
        let url = brandIconsDirectory.appendingPathComponent("\(name).svg")
        let svg = try #require(NSImage(contentsOf: url), "missing brand SVG \(name)")
        let side = 512
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        svg.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        let data = try #require(rep.bitmapData)
        let stride = rep.bytesPerRow
        var minX = side, maxX = -1, minY = side, maxY = -1
        for y in 0..<side {
            for x in 0..<side where data[y * stride + x * 4 + 3] > 25 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        try #require(maxX >= 0, "no ink rasterised for \(name)")
        let f = Double(side)
        return InkBox(
            left: Double(minX) / f,
            right: (f - Double(maxX + 1)) / f,
            top: Double(minY) / f,
            bottom: (f - Double(maxY + 1)) / f,
            aspect: svg.size.height > 0 ? svg.size.width / svg.size.height : .nan
        )
    }

    @Test(arguments: markFiles)
    func everyMarkIsTrimmedToItsInk(_ name: String) throws {
        let box = try Self.inkBox(of: name)
        #expect(box.left < 0.01, "\(name) leading margin \(box.left)")
        #expect(box.right < 0.01, "\(name) trailing margin \(box.right)")
        #expect(box.top < 0.01, "\(name) top margin \(box.top)")
        #expect(box.bottom < 0.01, "\(name) bottom margin \(box.bottom)")
    }

    /// Grok and Cursor ship a light/dark pair. Both are the same path with a different fill,
    /// so their trimmed boxes must be identical — otherwise the mark would jump sideways
    /// when the appearance changes.
    @Test(arguments: [("grok-light", "grok-dark"), ("cursor-light", "cursor-dark"), ("copilot-light", "copilot-dark"),
        ("opencode-light", "opencode-dark"), ("antigravity-light", "antigravity-dark")])
    func lightAndDarkPairsTrimToTheSameBox(_ pair: (String, String)) throws {
        let light = try Self.inkBox(of: pair.0)
        let dark = try Self.inkBox(of: pair.1)
        #expect(abs(light.aspect - dark.aspect) < 0.001, "\(pair.0) vs \(pair.1) aspect")
        #expect(abs(light.left - dark.left) < 0.01)
        #expect(abs(light.right - dark.right) < 0.01)
        #expect(abs(light.top - dark.top) < 0.01)
        #expect(abs(light.bottom - dark.bottom) < 0.01)
    }

    /// The Core `inkAspect` table is what the asset-catalog surfaces (iOS, both widget
    /// families) size their marks by — they only ever see an `Image(name)` and cannot
    /// measure the artwork. This is the link that keeps the table honest.
    @Test(arguments: [
        (ProviderID.claude.raw, "claude-color"),
        (ProviderID.codex.raw, "codex-color"),
        (ProviderID.grok.raw, "grok-light"),
        (ProviderID.cursor.raw, "cursor-light"),
        (ProviderID.copilot.raw, "copilot-light"),
        (ProviderID.opencode.raw, "opencode-light"),
        (ProviderID.opencode.raw, "opencode-dark"),
        (ProviderID.antigravity.raw, "antigravity-light"),
        (ProviderID.antigravity.raw, "antigravity-dark"),
    ])
    func coreInkAspectMatchesTheShippedArtwork(_ pair: (String, String)) throws {
        let measured = try Self.inkBox(of: pair.1).aspect
        let declared = HeadroomBrandMark.inkAspect(for: pair.0)
        #expect(abs(measured - declared) / declared < 0.01, "\(pair.0): art \(measured), table \(declared)")
    }
}
