import AppKit
import CoreText
import SwiftUI

/// OA1: optical margin alignment for the card's content column — InDesign's hanging glyphs,
/// in SwiftUI.
///
/// Every text in a provider card starts at the same 34pt layout edge, but SF's glyphs carry
/// different left side bearings, so the *ink* staggers: at 15pt semibold "P" begins 1.30pt
/// inside its layout box while "W" begins 0.64pt inside it. The result is a column that
/// jitters row to row — "Weekly" reads left of "Personal", and a diagonal reads further right
/// than its topmost pixel suggests. Pulling each string back by its own first-glyph bearing
/// (plus a small overhang for diagonals and rounds) lands the *perceived* edge on the axis
/// instead of the layout edge.
///
/// Applies to running text that starts a line — titles, meter labels, status sentences. It is
/// deliberately **not** applied to chips (their label sits inside a button with its own
/// padding, so the container edge, not the glyph, is what aligns) or to the popover header.
enum OpticalLeading {
    /// OA1: overhang as a fraction of the point size, on top of the measured bearing.
    ///
    /// These are the standard hanging-glyph compensations from print typography — **derived
    /// convention, not measured from SF**. A bearing alone aligns the glyph's bounding box,
    /// but the eye aligns on perceived mass: a diagonal's apex and a round's tangent each
    /// touch the axis at a single point, so a box-aligned "W" or "O" reads as if it were
    /// indented. Overhanging them a little past the axis reads flush. Stems and flats
    /// (`E F H M P 5 1` …) already meet the axis along their whole height and get nothing.
    /// Tune these two numbers, not the call sites.
    enum Overhang {
        /// A V W X Y and their lowercase — apex/vertex touches the axis at one point.
        static let diagonal: CGFloat = 0.06
        /// C G O Q S 0 3 6 8 9 and `(` — curve is tangent to the axis at one point.
        static let round: CGFloat = 0.035
    }

    private static let diagonals: Set<Character> = ["A", "V", "W", "X", "Y", "v", "w", "x", "y"]
    private static let rounds: Set<Character> = [
        "C", "G", "O", "Q", "S", "c", "e", "o", "s", "0", "3", "6", "8", "9", "(",
    ]

    /// OA1: half a point at 2× is a visible seam, so corrections land on the 0.25pt grid the
    /// Retina raster can actually resolve. Sub-quarter-point precision would only smear.
    private static let quantum: CGFloat = 0.25

    /// The leading correction to *subtract* from the layout edge, quantised to 0.25pt.
    /// Cached — this runs once per text per render pass.
    static func correction(for text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        guard let first = text.first else { return 0 }
        return cache.value(for: Key(character: first, size: size, weight: weight.rawValue)) {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            return quantised(unroundedCorrection(for: first, font: font))
        }
    }

    /// Uncached font-driven form, for call sites holding a concrete `NSFont`.
    static func correction(for text: String, font: NSFont) -> CGFloat {
        guard let first = text.first else { return 0 }
        return quantised(unroundedCorrection(for: first, font: font))
    }

    /// The raw `bearing + overhang × size` before quantisation. Exposed so tests can pin the
    /// measurement itself rather than the 0.25pt grid it lands on.
    static func unroundedCorrection(for text: String, font: NSFont) -> CGFloat {
        guard let first = text.first else { return 0 }
        return unroundedCorrection(for: first, font: font)
    }

    private static func unroundedCorrection(for character: Character, font: NSFont) -> CGFloat {
        bearing(of: character, font: font) + overhang(for: character) * font.pointSize
    }

    private static func overhang(for character: Character) -> CGFloat {
        if diagonals.contains(character) { return Overhang.diagonal }
        if rounds.contains(character) { return Overhang.round }
        return 0
    }

    /// The glyph's left side bearing at this font's size, straight from CoreText.
    ///
    /// Anything CoreText can't resolve to exactly one glyph from exactly one UTF-16 unit —
    /// an emoji, a surrogate pair, a character with no glyph in this font — corrects by 0
    /// rather than guessing; an unaligned title is a far smaller defect than a shifted one.
    private static func bearing(of character: Character, font: NSFont) -> CGFloat {
        var units = Array(String(character).utf16)
        guard units.count == 1 else { return 0 }
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        guard CTFontGetGlyphsForCharacters(font as CTFont, &units, &glyphs, 1) else { return 0 }
        var rects = [CGRect](repeating: .zero, count: 1)
        CTFontGetBoundingRectsForGlyphs(font as CTFont, .horizontal, &glyphs, &rects, 1)
        return rects[0].origin.x
    }

    private static func quantised(_ value: CGFloat) -> CGFloat {
        (value / quantum).rounded() * quantum
    }

    // MARK: - Cache

    private struct Key: Hashable {
        let character: Character
        let size: CGFloat
        let weight: CGFloat
    }

    /// OA1: CoreText's per-glyph metrics are cheap but not free, and this is on the render
    /// path of every row. The key space is bounded by (first characters actually seen) ×
    /// (the handful of sizes and weights the popover uses), so a plain dictionary behind a
    /// lock is the whole story; the cap only guards against pathological account names.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Key: CGFloat] = [:]

        func value(for key: Key, compute: () -> CGFloat) -> CGFloat {
            lock.lock()
            defer { lock.unlock() }
            if let hit = storage[key] { return hit }
            let value = compute()
            if storage.count >= 512 { storage.removeAll(keepingCapacity: true) }
            storage[key] = value
            return value
        }
    }

    private static let cache = Cache()
}

extension View {
    /// OA1: pull this text back onto the optical axis. The negative leading padding shrinks
    /// the padded view by the correction, so the glyph's perceived edge lands on the layout
    /// edge and everything after it in the row travels with it — the whole cluster stays
    /// spaced as authored, it just starts where the eye expects.
    func opticalLeading(_ text: String, size: CGFloat, weight: Font.Weight) -> some View {
        padding(.leading, -OpticalLeading.correction(for: text, size: size, weight: .from(weight)))
    }
}

extension NSFont.Weight {
    /// SwiftUI's `Font.Weight` is an opaque struct, so the bridge to the AppKit weight the
    /// metrics need is a lookup rather than a cast. Unknown values read as `.regular`.
    static func from(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
