import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

/// Local DialKit tuning seam (see `HeadroomApp/UI/PopoverTuning.swift`). Every default equals
/// the shipped literal, and only the Mac popover injects a non-default value, so every other
/// surface (phone, widgets, Settings) renders exactly as before.
public struct HeadroomTuning: Codable, Equatable, Sendable {
    // Shell
    public var shellWidth = 384.0
    public var shellMargin = 19.0
    public var shellCornerRadius = 22.0
    // Stack
    public var cardGap = 20.0
    public var headerGap = 11.0
    // Card
    public var cardPadding = 13.0
    public var cardCornerRadius = 10.0
    public var accountGap = 26.0
    public var identityToMetersGap = 4.0
    public var microRowGap = 10.0
    public var fullRowGap = 12.0
    // Identity row
    public var titleSize = 15.0
    public var titleKerning = -0.15
    public var titleWeight = "semibold"
    public var markSlotWidth = 15.0
    public var markGap = 6.0
    // Meter row
    public var labelSize = 13.0
    public var labelWeight = "medium"
    public var resetSize = 11.0
    public var percentSize = 18.0
    public var percentWeight = "semibold"
    public var meterGap = 6.0
    public var fullLabelToGauge = 7.0
    // Gauge
    public var gaugeLengthScale = 1.0
    public var gaugeHeightScale = 1.0
    // Tile, dark
    public var darkFillTop = 0.075
    public var darkFillBottom = 0.045
    // CA-P2: an even ring, a faded inset lip and two tight shadows replace R2C1's white 0.20
    // → black 0.22 stroke and its one diffuse 0.6 @ r10 y3 shadow. `darkRimTop` is the lip
    // now; `darkRimBottom` is retired. Rim values come from Core, where rule 8's 0.15
    // ceiling is tested.
    public var darkRing = HeadroomTileEdgeValues.darkGlassRingOpacity
    public var darkRimTop = HeadroomTileEdgeValues.darkGlassLipOpacity
    public var darkShadowOpacity = 0.40
    public var darkShadowRadius = 0.5
    public var darkShadowY = 1.0
    public var darkAmbientShadowOpacity = 0.30
    public var darkAmbientShadowRadius = 4.0
    public var darkAmbientShadowY = 2.0
    // Tile, light
    public var lightFillTop = 0.98
    public var lightFillBottom = 0.94
    public var lightRimTop = 0.90
    public var lightRimBottom = 0.07
    public var lightShadowOpacity = 0.12
    public var lightShadowRadius = 5.0
    public var lightShadowY = 1.0
    // Motion. CA-F1: the defaults are the shipped tokens by construction.
    public var valueSpringResponse = HeadroomMotion.valueSpringResponse
    public var valueSpringDamping = HeadroomMotion.valueSpringDampingFraction
    public var settleDuration = HeadroomMotion.settleDuration

    public init() {}

    public var meterContentInset: CGFloat { markSlotWidth + markGap }

    public var valueSpring: Animation {
        .spring(response: valueSpringResponse, dampingFraction: valueSpringDamping)
    }

    public var settle: Animation {
        HeadroomMotion.houseCurve(duration: settleDuration)
    }

    public static func weight(_ name: String) -> Font.Weight {
        switch name {
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "bold": .bold
        case "heavy": .heavy
        default: .semibold
        }
    }

    public static let weightOptions = ["light", "regular", "medium", "semibold", "bold", "heavy"]
}

private struct HeadroomTuningKey: EnvironmentKey {
    static let defaultValue = HeadroomTuning()
}

extension EnvironmentValues {
    public var headroomTuning: HeadroomTuning {
        get { self[HeadroomTuningKey.self] }
        set { self[HeadroomTuningKey.self] = newValue }
    }
}
