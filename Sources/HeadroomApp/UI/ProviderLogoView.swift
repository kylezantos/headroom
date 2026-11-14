#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import HeadroomCore

/// Provider brand mark used at small UI sizes. Bundled SVGs render through AppKit;
/// SF Symbols remain the fallback for unknown providers.
///
/// R2C13: the marks are drawn `.renderingMode(.original)` — the value is a property of the
/// artwork, not of this view — so the ~86% ink ceiling on the two monochrome brands lives in
/// their SVG fills. `HeadroomBrandColorValues.monochromeMarkInk` names those two hexes and
/// `BrandColorValuesTests` re-reads both shipped copies so the token and the files cannot
/// drift. Tinting here instead would have skipped the asset-catalog surfaces (iOS + both
/// widget families), which only ever see an `Image(name)`.
struct ProviderLogoView: View {
    let providerID: ProviderID
    var size: CGFloat = 16
    /// Drop the slot's trailing slack and take the mark's own ink width, for a mark set
    /// *beside* text with no shared axis to hold — the pill cards' centred names, where the
    /// slack read as extra gap, widest on the narrow Cursor and Grok marks.
    var hugsInk = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // OA2: the SVGs are trimmed to their ink, so the mark's rendered size is the shared
        // measured rule (`HeadroomBrandMark`) rather than a per-provider guess — larger ink
        // dimension = 13/15 of the slot, aspect preserved. The mark is centred in its slot
        // (Sep 2026): the marks differ in width by up to 3pt, and a shared left edge put all
        // of that difference into the gap before the title, which is the gap the eye reads.
        // Vertical centring already lines the mark up on the title's cap.
        let mark = HeadroomBrandMark.markSize(for: providerID.raw, slot: Double(size))
        let markWidth = CGFloat(mark.width)
        let markHeight = CGFloat(mark.height)
        if let image = BrandIconImage.image(for: providerID, scheme: scheme) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: markWidth, height: markHeight)
                .frame(width: hugsInk ? markWidth : size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: ProviderStyle.symbol(for: providerID))
                .font(.system(size: markHeight, weight: .semibold))
                .foregroundStyle(ProviderStyle.accent(for: providerID))
                .frame(width: markWidth, height: markHeight)
                .frame(width: hugsInk ? markWidth : size, height: size)
                .accessibilityHidden(true)
        }
    }
}

enum BrandIconImage {
    /// PA15: the bake below is a bundle lookup, an SVG decode, and a 256px offscreen
    /// rasterization, and it ran from `body` — up to ~24 marks every time the popover opens,
    /// on a surface whose entrance animation was deleted because any delay there reads as
    /// latency. Same static cache as `VesselGlyph`, keyed on the two things that change the
    /// bitmap: which provider, and which of the light/dark monochrome pairs is showing.
    @MainActor private static var cache: [Key: NSImage] = [:]

    private struct Key: Hashable {
        let providerID: String
        let isDark: Bool
    }

    @MainActor
    static func image(for providerID: ProviderID, scheme: ColorScheme) -> NSImage? {
        let key = Key(providerID: providerID.raw, isDark: scheme == .dark)
        if let cached = cache[key] { return cached }
        guard let baked = bake(for: providerID, scheme: scheme) else { return nil }
        cache[key] = baked
        return baked
    }

    /// CA-MB1: the decoded vector artwork itself, unbaked, for the menu-bar label, which
    /// draws it into its own image at the bar's backing scale and only reads its coverage.
    @MainActor private static var vectors: [Key: NSImage] = [:]
    @MainActor private static var missing: Set<Key> = []

    @MainActor
    static func vector(for providerID: ProviderID, isDark: Bool) -> NSImage? {
        let key = Key(providerID: providerID.raw, isDark: isDark)
        if let cached = vectors[key] { return cached }
        guard !missing.contains(key) else { return nil }
        guard let name = ProviderStyle.svgResourceName(for: providerID, scheme: isDark ? .dark : .light),
              let url = url(forResource: name),
              let svg = NSImage(contentsOf: url) else {
            missing.insert(key)
            return nil
        }
        vectors[key] = svg
        return svg
    }

    private static func bake(for providerID: ProviderID, scheme: ColorScheme) -> NSImage? {
        guard let name = ProviderStyle.svgResourceName(for: providerID, scheme: scheme),
              let url = url(forResource: name),
              let svg = NSImage(contentsOf: url) else {
            return nil
        }
        // The brand SVGs are small (a 9–24pt viewBox). `ImageRenderer` (the marketing hero
        // export) rasterizes nested images at their intrinsic size and upscales — blurring a
        // 10pt mark ~8×. Bake a high-res bitmap once so the offscreen export stays crisp; the
        // live app draws this `.resizable()` and downsamples cleanly, so it's unaffected.
        //
        // OA2: bake at the SVG's own aspect, not a square. `NSImage.draw(in:)` *stretches*
        // rather than letterboxes, so squaring the bake would distort the trimmed non-square
        // marks (Grok, Cursor) instead of preserving the ink box we just measured.
        let side = 256.0
        let aspect = svg.size.height > 0 ? svg.size.width / svg.size.height : 1
        let pixels = aspect >= 1
            ? NSSize(width: side, height: side / aspect)
            : NSSize(width: side * aspect, height: side)
        let hi = NSImage(size: pixels)
        hi.lockFocus()
        svg.draw(in: NSRect(origin: .zero, size: pixels))
        hi.unlockFocus()
        return hi
    }

    private static func url(forResource name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            return url
        }
        let swiftPMBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Headroom_HeadroomApp.bundle")
        return Bundle(url: swiftPMBundleURL)?
            .url(forResource: name, withExtension: "svg")
    }
}
