import Foundation

/// Every color the menu bar label paints, resolved for one *menu bar* appearance (L1A).
///
/// Until Sep 2026 the label pinned all of these to their dark-scheme values, on the belief
/// that Tahoe always draws status items on a dark translucent backplate. It doesn't: over a
/// light wallpaper the menu bar itself goes light, and the pinned white vessel and white
/// numerals disappeared into it.
///
/// The pin was really a workaround for a *rendering* bug, not an appearance decision: SwiftUI
/// rasterizes `Image(nsImage:)` against the **system** appearance, so a dynamic severity
/// `NSColor` baked to its light value while a sibling `.labelColor` stayed dynamic and
/// resolved white against the dark menu bar — one label, two palettes. This type removes the
/// ambiguity instead of pinning around it: every value is an explicit constant selected by a
/// single flag, so the render never depends on whichever appearance the rasterizer happens to
/// be in.
///
/// The flag is the **menu bar's** appearance, not the system's. Those differ in a case that a
/// system-appearance check gets wrong: a light system appearance over a dark wallpaper still
/// gets a dark menu bar. `MenuBarAppearanceMonitor` (app target) supplies it from the status
/// item's own window.
public struct MenuBarPalette: Sendable, Equatable {
    public let isDarkMenuBar: Bool

    public init(isDarkMenuBar: Bool) {
        self.isDarkMenuBar = isDarkMenuBar
    }

    /// The menu bar's label color — what every other status item's ink matches. White on a
    /// dark bar, black at 0.85 on a light one (AppKit's own `labelColor` pair), resolved to
    /// explicit values rather than left dynamic.
    public var ink: HeadroomTint {
        isDarkMenuBar
            ? HeadroomTint(color: .white, opacity: 1.0)
            : HeadroomTint(color: .black, opacity: 0.85)
    }

    /// CA-MB1 (KTD7): a provider mark, the ink at 0.90, one step under the numeral so the
    /// number still leads. Monochrome on purpose: severity stays the only colour in the bar
    /// (DESIGN rule 4).
    public var markInk: HeadroomTint {
        HeadroomTint(color: ink.color, opacity: ink.opacity * 0.90)
    }

    /// Liquid for a vessel with no severity to report (automatic fill, or no data yet): the
    /// ink knocked back to 0.62 so the level reads as decoration rather than as status.
    public var neutralLiquid: HeadroomTint {
        HeadroomTint(color: ink.color, opacity: ink.opacity * 0.62)
    }

    /// What the vessel's liquid — and the needs-sign-in dot — paint: the severity **fill**
    /// tier for this appearance.
    ///
    /// The menu bar has no SwiftUI environment, so Increase Contrast is not consulted here;
    /// the vivid light fills are the L1A design, and the numeral beside each vessel carries
    /// the accessible reading.
    public func liquid(for severity: UsageSeverity) -> HeadroomRGBColor {
        HeadroomSeverityColorValues.fill(for: severity, dark: isDarkMenuBar, increasedContrast: false)
    }

    /// A severity rendered as *ink* — the percentage numeral when the window is low or
    /// critical, and the numeral beside a provider that needs sign-in. This is the text tier,
    /// which parts from the fill tier at critical because the fill red fails at numeral size.
    public func severityInk(for severity: UsageSeverity) -> HeadroomRGBColor {
        switch severity {
        case .critical: HeadroomSeverityColorValues.criticalText(dark: isDarkMenuBar)
        case .low, .healthy: HeadroomSeverityColorValues.color(for: severity, dark: isDarkMenuBar)
        }
    }
}
