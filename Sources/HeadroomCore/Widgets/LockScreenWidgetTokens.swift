import Foundation

/// KTD5 (2026-10-04 Lock Screen plan): opaque gray lightness, not alpha, lets
/// WidgetKit map each ink level into the wallpaper's vibrant material.
public enum LockScreenWidgetTokens {
    public static let fullInk = 1.0 // R13: full white becomes the strongest material ink.
    public static let secondaryInk = 0.72 // KTD5: approved vessel wall and secondary labels.
    public static let halfInk = 0.50 // R8: retained readings use half ink.
    public static let trackInk = 0.24 // KTD5: approved arc and bar tracks.
    public static let washTop = 0.30 // KTD5: approved liquid wash, without a bright edge.
    public static let washBottom = 0.12 // KTD5: approved lower wash level.
    public static let alwaysOnWash = 0.08 // R14: lower luminance while the phone is dimmed.

    public static let tightestNumeral = 17.0 // R3: user-approved gauge size.
    public static let tightestMark = 15.0 // R3: mark sits inside the arc gap.
    public static let liquidNumeral = 18.0 // R3: user-approved dial size.
    public static let liquidMark = 15.0 // R3: dial marks match gauge marks.
    public static let vesselNumeral = 19.0 // R2: Vessel Badge design 01.
    public static let nestedNumeral = 18.0 // R2: Nested Badge design 11A.
    public static let badgeMark = 13.0 // R2: designs 01 and 11A share this mark slot.
    public static let nestedBarWidth = 34.0 // R2: approved compact badge bars.
    public static let nestedParentHeight = 4.0 // R2: parent bar, also each Cursor sibling pool.
    public static let nestedRailHeight = 2.0 // R2: subordinate rolling-window rails.
    public static let nestedRailGap = 1.5 // R2: compact badge bar stack.
    public static let arcRadius = 29.0 // R3: clears the caption inside a 72-point reference circle.
    public static let arcStroke = 4.6 // R2: approved open-arc gauge.
    public static let arcSweep = 0.75 // R2: quarter-circle gap leaves room for the mark.
    public static let captionSize = 9.5 // R3/R15: labels clear the gauge arc and dial numeral.
    public static let captionGap = 2.0 // R8: warning glyph stays attached to its window name.
    public static let knockoutHorizontalPadding = 5.0 // KTD8: capsule leaves ink around the cut-out digits.
    public static let knockoutVerticalPadding = 1.5 // KTD8/R15: capsule fits fixed-size circle numerals.
    public static let knockoutStroke = 1.0 // KTD8/R14: Always On keeps the capsule as a fine outline.
    public static let arcRotation = 135.0 // R2: the quarter-circle opening sits below the number.
    public static let vesselNumeralGapRatio = 0.24 // KTD6: digit-ink vessel keeps the home hero's optical gap.

    /// R15: a Foundation-only cap mirrored by the host, below the home's xxLarge cap.
    public enum LabelDynamicTypeCap: Sendable { case xLarge }
    public static let labelDynamicTypeCap: LabelDynamicTypeCap = .xLarge
}
