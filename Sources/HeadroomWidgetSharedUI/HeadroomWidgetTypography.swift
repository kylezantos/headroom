#if canImport(HeadroomCore)
import HeadroomCore
#endif
import CoreText
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// WCL6: the widget half of the popover's `OpticalLeading` / `OpticalCentering` pair.
///
/// The popover's version is built on `NSFont` and `NSLayoutManager`, neither of which
/// compiles in the iOS widget extension, so the metrics here come from CoreText —
/// `CTFontGetCapHeight` for the vertical guide and `CTFontGetBoundingRectsForGlyphs` for
/// the left side bearing. Only the *construction* of a weighted system font still goes
/// through the platform font class: CoreText has no reliable constructor for the system
/// face at an arbitrary weight (descriptor matching on the hidden system family silently
/// falls back to Helvetica), and `UIFont`/`NSFont` are both available in their respective
/// widget extensions. Everything that AppKit was blocking — the layout manager — is gone.
///
/// Naming is deliberately `widget`-prefixed rather than shadowing the popover's
/// `capHeightCentered` / `opticalLeading`: the macOS app target compiles
/// `Sources/HeadroomWidgetSharedUI` *into the app module* alongside `Sources/HeadroomApp`
/// (see `project.yml`), so identical member names here would be a redeclaration, not an
/// override.
public enum HeadroomWidgetType {
    /// WCF1: one ladder face for every widget string — a point size, a weight, and
    /// (for numerals, countdowns and amounts) tabular figures. No semantic `Font` styles.
    public static func font(size: Double, weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        let base = Font.system(size: CGFloat(size), weight: weight)
        return mono ? base.monospacedDigit() : base
    }
}


/// WCL4: the medium centre rule starts at the first meter label's *cap* top, not its line-box
/// top. The inset is the font's ascent minus its cap height — what sits above the capitals in
/// a SwiftUI line box.
public enum HeadroomWidgetTypography {
    public static func capTopInset(size: Double, weight: Font.Weight, mono: Bool = false) -> CGFloat {
        HeadroomWidgetFontMetrics.capTopInset(size: CGFloat(size), weight: weight, mono: mono)
    }
}

/// WCL6: the measured metrics behind the two modifiers below.
public enum HeadroomWidgetFontMetrics {
    public static func capTopInset(size: CGFloat, weight: Font.Weight, mono: Bool = false) -> CGFloat {
        let font = ctFont(size: size, weight: weight, mono: mono)
        return max(0, CTFontGetAscent(font) - CTFontGetCapHeight(font))
    }

    /// Distance from the baseline up to the middle of the capitals — the half-height the
    /// eye reads as the type's middle, and what a mixed-size row should centre on.
    public static func capHeightCenter(size: CGFloat, weight: Font.Weight, mono: Bool = false) -> CGFloat {
        capCache.value(for: MetricKey(size: size, weight: weightValue(weight), mono: mono, character: nil)) {
            CTFontGetCapHeight(ctFont(size: size, weight: weight, mono: mono)) / 2
        }
    }

    /// The leading correction to *subtract* from the layout edge so a string's perceived
    /// ink edge — not its glyph box — lands on the content axis. Bearing plus the print
    /// overhang for diagonals and rounds, quantised to the 0.25pt grid a Retina raster can
    /// resolve. Same table and same reasoning as the popover's `OpticalLeading`.
    public static func leadingCorrection(
        for text: String,
        size: CGFloat,
        weight: Font.Weight,
        mono: Bool = false
    ) -> CGFloat {
        guard let first = text.first else { return 0 }
        return bearingCache.value(
            for: MetricKey(size: size, weight: weightValue(weight), mono: mono, character: first)
        ) {
            let font = ctFont(size: size, weight: weight, mono: mono)
            let raw = bearing(of: first, font: font) + overhang(for: first) * size
            return (raw / quantum).rounded() * quantum
        }
    }

    // MARK: - CoreText

    private static let quantum: CGFloat = 0.25

    /// A V W X Y and their lowercase — apex/vertex touches the axis at one point.
    private static let diagonals: Set<Character> = ["A", "V", "W", "X", "Y", "v", "w", "x", "y"]
    /// Curves are tangent to the axis at one point, so they read indented when box-aligned.
    private static let rounds: Set<Character> = [
        "C", "G", "O", "Q", "S",
        "a", "c", "d", "e", "g", "o", "q", "s",
        "0", "3", "6", "8", "9", "(",
    ]

    private static func overhang(for character: Character) -> CGFloat {
        if diagonals.contains(character) { return 0.06 }
        if rounds.contains(character) { return 0.035 }
        return 0
    }

    /// Anything CoreText cannot resolve to exactly one glyph from one UTF-16 unit corrects
    /// by 0 rather than guessing — an unaligned label is a smaller defect than a shifted one.
    private static func bearing(of character: Character, font: CTFont) -> CGFloat {
        var units = Array(String(character).utf16)
        guard units.count == 1 else { return 0 }
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, 1) else { return 0 }
        var rects = [CGRect](repeating: .zero, count: 1)
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, &rects, 1)
        return rects[0].origin.x
    }

    private static func ctFont(size: CGFloat, weight: Font.Weight, mono: Bool) -> CTFont {
        let value = weightValue(weight)
        #if canImport(UIKit)
        let platform = mono
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: UIFont.Weight(value))
            : UIFont.systemFont(ofSize: size, weight: UIFont.Weight(value))
        return platform as CTFont
        #elseif canImport(AppKit)
        let platform = mono
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: NSFont.Weight(value))
            : NSFont.systemFont(ofSize: size, weight: NSFont.Weight(value))
        return platform as CTFont
        #else
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        #endif
    }

    /// `Font.Weight` is opaque, so the bridge to the platform weight is a lookup rather
    /// than a cast. The raw values are the documented `UIFont.Weight`/`NSFont.Weight`
    /// constants, which are identical on both platforms.
    private static func weightValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: -0.8
        case .thin: -0.6
        case .light: -0.4
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        case .black: 0.62
        default: 0
        }
    }

    // MARK: - Cache

    private struct MetricKey: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let mono: Bool
        let character: Character?
    }

    /// WCL6: a lock-guarded dictionary rather than `@MainActor` state. WidgetKit evaluates
    /// these bodies off the main actor while it renders a timeline entry, so main-actor
    /// isolation would force every call site to hop (or, worse, tempt an `assumeIsolated`);
    /// and the process is short-lived, so the cap exists only to bound a pathological key
    /// space, not to manage memory over time.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [MetricKey: CGFloat] = [:]

        func value(for key: MetricKey, compute: () -> CGFloat) -> CGFloat {
            lock.lock()
            defer { lock.unlock() }
            if let hit = storage[key] { return hit }
            let value = compute()
            if storage.count >= 256 { storage.removeAll(keepingCapacity: true) }
            storage[key] = value
            return value
        }
    }

    private static let capCache = Cache()
    private static let bearingCache = Cache()
}

public extension View {
    /// WCL6: hang this text's cap-height centre on the enclosing `.center` row. A widget
    /// row mixes three line-box heights (an 18pt numeral over a 12pt label), and SwiftUI's
    /// `.center` centres *line boxes*, which are asymmetric about their ink by a different
    /// amount at every size.
    func widgetCapHeightCentered(size: Double, weight: Font.Weight, mono: Bool = false) -> some View {
        alignmentGuide(VerticalAlignment.center) { dimensions in
            dimensions[.firstTextBaseline]
                - HeadroomWidgetFontMetrics.capHeightCenter(size: CGFloat(size), weight: weight, mono: mono)
        }
    }

    /// WCL6: pull this text back onto the content axis. The negative leading padding shrinks
    /// the padded view by the correction, so the glyph's perceived edge lands on the layout
    /// edge and the rest of the row travels with it.
    func widgetOpticalLeading(_ text: String, size: Double, weight: Font.Weight) -> some View {
        padding(
            .leading,
            -HeadroomWidgetFontMetrics.leadingCorrection(for: text, size: CGFloat(size), weight: weight)
        )
    }
}
