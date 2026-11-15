import AppKit
import CryptoKit
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
        ("opencode-light", "opencode-dark")])
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
    ])
    func coreInkAspectMatchesTheShippedArtwork(_ pair: (String, String)) throws {
        let measured = try Self.inkBox(of: pair.1).aspect
        let declared = HeadroomBrandMark.inkAspect(for: pair.0)
        #expect(abs(measured - declared) / declared < 0.01, "\(pair.0): art \(measured), table \(declared)")
    }
}

/// CA-MB1/CA-MB2 (KTD7): the provider marks drawn into the menu-bar label image.
@MainActor
@Suite(.sharedAppState)
struct MenuBarMarkRenderTests {
    static let providers: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot, .opencode]

    static func meter(_ provider: ProviderID?, text: String = "72%", fill: Double = 0.72,
                      severity: UsageSeverity = .healthy, attention: Bool = false,
                      pending: Bool = false, automatic: Bool = false) -> MenuBarMeter {
        MenuBarMeter(
            summary: MenuBarSummary(text: text, providerID: provider, detail: provider.map { "\($0.raw) weekly" },
                                    isNeutral: pending, severity: severity, needsAttention: attention),
            fill: pending ? nil : fill, awaitingFirstReading: pending, isLiveReading: !pending,
            sourceAccountKey: provider.map { AccountKey(providerID: $0, accountID: .primary) },
            isAutomaticSummary: automatic)
    }

    /// The approved MB1 strip: Claude 72% healthy, Codex 38% low, Cursor 9% critical.
    static func strip(attention: Bool = false) -> [MenuBarMeter] {
        [
            meter(.claude, text: "72%", fill: 0.72),
            meter(.codex, text: "38%", fill: 0.38, severity: .low),
            meter(.cursor, text: "9%", fill: 0.09, severity: .critical, attention: attention),
        ]
    }

    /// Rasterises the label at `scale` pixels per point. Rows run top-down.
    static func bitmap(_ image: NSImage, scale: CGFloat) throws -> NSBitmapImageRep {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale),
            pixelsHigh: Int(image.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func digest(_ rep: NSBitmapImageRep) -> String {
        let data = Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// RGBA (premultiplied) of every pixel in the columns `[minX, maxX)` points.
    static func columns(_ rep: NSBitmapImageRep, from minX: Double, to maxX: Double, scale: CGFloat) -> [[UInt8]] {
        let data = rep.bitmapData!
        var out: [[UInt8]] = []
        for y in 0..<rep.pixelsHigh {
            for x in Int(minX * Double(scale))..<min(rep.pixelsWide, Int(maxX * Double(scale))) {
                let i = y * rep.bytesPerRow + x * 4
                out.append([data[i], data[i + 1], data[i + 2], data[i + 3]])
            }
        }
        return out
    }

    /// Marks off must leave today's image untouched. Pinned from the renderer at 6dbe09c3,
    /// before any mark was drawn, at 2× for icon-only and percentage strips on both bars.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func marksOffIsByteIdenticalToTheUnmarkedLabel(_ input: (dark: Bool, percentage: Bool)) throws {
        let result = MenuBarLabelRenderer.render(meters: Self.strip(attention: true), showsPercentage: input.percentage,
                                                 palette: MenuBarPalette(isDarkMenuBar: input.dark), showsMarks: false)
        let digest = Self.digest(try Self.bitmap(result.image, scale: 2))
        // A macOS update that changes text antialiasing moves the two percentage digests;
        // re-pin those from a marks-off render on the base commit, never from new code.
        let pinned = [
            "true-false": "99416408dd03df159474ead91635a93dd88956595b7b88543c2033558c931417",
            "true-true": "5342fe0e5b70e445f7b33d778cb799266ea80f25dcd5ba97ee808169e5171340",
            "false-false": "b597010eee796da1cdaab1f49d5612b25f8c4cd2a900d1bab269bf7f7035f34f",
            "false-true": "c7ee18d33893f40c16280e03c42695cddecf32ddf7af127d247adf4f33e73dbb",
        ]
        #expect(digest == pinned["\(input.dark)-\(input.percentage)"], "dark \(input.dark) pct \(input.percentage): \(digest)")
    }

    /// The approved panel's readouts, measured with the real numeral font: 222pt and 101pt
    /// marked, today's 170pt and 49pt unmarked.
    @Test func theStripMeasuresThePanelsWidths() {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        func width(_ percentage: Bool, _ marks: Bool) -> CGFloat {
            MenuBarLabelRenderer.render(meters: Self.strip(), showsPercentage: percentage, palette: palette,
                                        showsMarks: marks).image.size.width
        }
        #expect(width(true, true) == 222)
        #expect(width(false, true) == 101)
        #expect(width(true, false) == 170)
        #expect(width(false, false) == 49)
    }

    /// Single ink at 0.90 of the bar's ink for every provider: no brand colour survives
    /// (Claude's orange beside an amber fill was the MB-B collision), and the solid parts
    /// reach exactly white × 0.90 on a dark bar and black × 0.85 × 0.90 on a light one.
    @Test(arguments: [true, false])
    func everyMarkIsOneInkAtNinetyPercentOfTheBar(_ dark: Bool) throws {
        let palette = MenuBarPalette(isDarkMenuBar: dark)
        for provider in Self.providers {
            let image = MenuBarLabelRenderer.render(meters: [Self.meter(provider)], showsPercentage: false,
                                                    palette: palette, showsMarks: true).image
            #expect(image.size.width == CGFloat(MenuBarLabelGeometry.markBoxSize
                + MenuBarLabelGeometry.markVesselGap + MenuBarLabelGeometry.vesselWidth), "\(provider.raw)")
            let pixels = Self.columns(try Self.bitmap(image, scale: 4), from: 0,
                                      to: MenuBarLabelGeometry.markBoxSize, scale: 4).filter { $0[3] > 0 }
            #expect(!pixels.isEmpty, "\(provider.raw) drew no mark")
            for pixel in pixels {
                // Premultiplied: white ink stores r = g = b = alpha, black ink stores zeros.
                let expected = dark ? pixel[3] : 0
                #expect(pixel[0] == expected && pixel[1] == expected && pixel[2] == expected,
                        "\(provider.raw) pixel \(pixel) is not single-ink")
                if pixel[0] != expected { break }
            }
            let peak = Double(pixels.map { $0[3] }.max() ?? 0)
            #expect(abs(peak - palette.markInk.opacity * 255) <= 2, "\(provider.raw) peak alpha \(peak)")
        }
    }

    /// CA-MB2: the automatic summary is marked even with the preference off, and the mark
    /// follows the provider in the same render as the numeral. Only the mark's columns
    /// differ between Claude and Codex here, since the reading is the same.
    @Test func theAutomaticSummarySwapsItsMarkWithTheProviderItFollows() throws {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        func render(_ provider: ProviderID) throws -> (NSImage, NSBitmapImageRep) {
            let image = MenuBarLabelRenderer.render(meters: [Self.meter(provider, automatic: true)], showsPercentage: true,
                                                    palette: palette, automatic: true, showsMarks: false).image
            return (image, try Self.bitmap(image, scale: 2))
        }
        let (claudeImage, claude) = try render(.claude)
        let (codexImage, codex) = try render(.codex)
        let unmarked = MenuBarLabelRenderer.render(meters: [Self.meter(.claude)], showsPercentage: true,
                                                   palette: palette, showsMarks: false).image
        #expect(claudeImage.size.width - unmarked.size.width
            == CGFloat(MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap))
        #expect(codexImage.size.width == claudeImage.size.width)
        let markEnd = MenuBarLabelGeometry.markBoxSize
        #expect(Self.columns(claude, from: 0, to: markEnd, scale: 2) != Self.columns(codex, from: 0, to: markEnd, scale: 2))
        let width = Double(claudeImage.size.width)
        #expect(Self.columns(claude, from: markEnd, to: width, scale: 2) == Self.columns(codex, from: markEnd, to: width, scale: 2))

        let empty = MenuBarLabelRenderer.render(meters: [Self.meter(nil, pending: true, automatic: true)],
                                                showsPercentage: false, palette: palette, automatic: true).image
        #expect(empty.size.width == CGFloat(MenuBarLabelGeometry.vesselWidth), "nobody to follow, no mark")
    }

    /// On a 1× bar Codex's `>_` cut-out is reopened, so the underscore's pixels stay close to
    /// clear instead of closing into the blob.
    @Test func codexKeepsItsPromptOpenOnAOneXBar() throws {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        let image = MenuBarLabelRenderer.render(meters: [Self.meter(.codex)], showsPercentage: false,
                                                palette: palette, showsMarks: true).image
        func underscoreAlpha(scale: CGFloat) throws -> (min: Double, peak: Double) {
            let rep = try Self.bitmap(image, scale: scale)
            let data = rep.bitmapData!
            let peak = Double(Self.columns(rep, from: 0, to: MenuBarLabelGeometry.markBoxSize, scale: scale).map { $0[3] }.max() ?? 0)
            // The underscore sits about 10.5pt down and 6.8 to 8.9pt across the image.
            var lowest = 255.0
            for y in Int(9.5 * scale)..<Int(11.5 * scale) {
                for x in Int(7 * scale)..<Int(8.8 * scale) {
                    lowest = min(lowest, Double(data[y * rep.bytesPerRow + x * 4 + 3]))
                }
            }
            return (lowest, peak)
        }
        let oneX = try underscoreAlpha(scale: 1)
        #expect(oneX.min < 0.25 * oneX.peak, "1× underscore alpha \(oneX.min) of \(oneX.peak)")
    }

    /// One mark's ink in a single-pill render: the box of pixels at or above half the peak
    /// alpha, the alpha-weighted pixel count (alpha / peak), and how far the box's centre sits
    /// above the vessel's (the image's) centre, in points. Also whether anything at all was
    /// drawn in the gap between the mark's box and its vessel.
    static func markInk(_ provider: ProviderID, dark: Bool, scale: CGFloat) throws
        -> (height: Double, mass: Double, lift: Double, spillsIntoGap: Bool) {
        let image = MenuBarLabelRenderer.render(meters: [meter(provider)], showsPercentage: false,
                                                palette: MenuBarPalette(isDarkMenuBar: dark), showsMarks: true).image
        let rep = try bitmap(image, scale: scale)
        let data = rep.bitmapData!
        let box = Int(MenuBarLabelGeometry.markBoxSize * Double(scale))
        let vessel = Int((MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap) * Double(scale))
        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[y * rep.bytesPerRow + x * 4 + 3]) }
        var peak = 0, spills = false
        for y in 0..<rep.pixelsHigh {
            for x in 0..<box { peak = max(peak, alpha(x, y)) }
            for x in box..<vessel where alpha(x, y) > 0 { spills = true }
        }
        var top = Int.max, bottom = -1, mass = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<box {
                mass += Double(alpha(x, y)) / Double(peak)
                if alpha(x, y) * 2 >= peak { top = min(top, y); bottom = max(bottom, y) }
            }
        }
        let s = Double(scale)
        let lift = (Double(rep.pixelsHigh) / 2 - Double(top + bottom + 1) / 2) / s
        return (Double(bottom - top + 1) / s, mass, lift, spills)
    }

    /// CA-MB1: pins the menu bar's optical balance of the six marks. With the popover's sizing
    /// they measured 2pt apart in height and 1.85× apart in weight at 2×; the menu bar's own
    /// table measures 2.0pt (by design: the solid Codex and OpenCode take the least extent)
    /// and 1.30×, every centre within 0.25pt of the vessel's, nothing in the gap.
    @Test(arguments: [true, false])
    func theSixMarksStayOpticallyBalancedAtTwoX(_ dark: Bool) throws {
        var heights: [Double] = [], masses: [Double] = []
        for provider in Self.providers {
            let ink = try Self.markInk(provider, dark: dark, scale: 2)
            heights.append(ink.height); masses.append(ink.mass)
            #expect(abs(ink.lift) <= 0.3, "\(provider.raw) sits \(ink.lift)pt off the vessel's centre")
            #expect(!ink.spillsIntoGap, "\(provider.raw) drew into its gap")
        }
        let summary = zip(Self.providers, zip(heights, masses)).map { "\($0.raw) \($1.0)pt \(Int($1.1))" }.joined(separator: ", ")
        #expect(heights.max()! - heights.min()! <= 2.25, "heights: \(summary)")
        #expect(masses.max()! / masses.min()! < 1.36, "weights: \(summary)")
    }

    /// At 1× the marks stay inside their boxes and on the vessel's centre to the half pixel.
    @Test(arguments: [true, false])
    func everyMarkStaysInItsBoxAndCentredAtOneX(_ dark: Bool) throws {
        for provider in Self.providers {
            let ink = try Self.markInk(provider, dark: dark, scale: 1)
            #expect(abs(ink.lift) <= 0.5, "\(provider.raw) sits \(ink.lift)pt off the vessel's centre")
            #expect(!ink.spillsIntoGap, "\(provider.raw) drew into its gap")
        }
    }

    /// One explicit pill with marks resolved off draws exactly as before.
    @Test func explicitPillsFollowTheResolvedPreference() {
        let palette = MenuBarPalette(isDarkMenuBar: true)
        let off = MenuBarLabelRenderer.render(meters: [Self.meter(.claude)], showsPercentage: false,
                                              palette: palette, showsMarks: false).image
        let on = MenuBarLabelRenderer.render(meters: [Self.meter(.claude)], showsPercentage: false,
                                             palette: palette, showsMarks: true).image
        #expect(off.size.width == CGFloat(MenuBarLabelGeometry.vesselWidth))
        #expect(on.size.width == CGFloat(MenuBarLabelGeometry.markBoxSize + MenuBarLabelGeometry.markVesselGap
            + MenuBarLabelGeometry.vesselWidth))
    }
}
