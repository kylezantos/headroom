import SwiftUI
import UIKit

/// U8 (U9-A "Neutral, like the Mac popover"; R4, G6): the phone's control colours, built from
/// the named Core values in `HeadroomControlColorValues`. The root `.tint` covers bare text
/// buttons, toolbar items and links; filled buttons and switches name their own fill, label
/// and on-state because SwiftUI's defaults would paint a white label on the near-white dark
/// fill and a full-ink switch track that swallows its knob. No `AccentColor` asset: the
/// catalog is shared with the Mac app.
enum PhoneControlStyle {
    /// The root `.tint` (scheme-adaptive).
    static let tint = Color(lightRGB: HeadroomControlColorValues.tint(dark: false),
                            darkRGB: HeadroomControlColorValues.tint(dark: true))
    static let buttonFill = Color(lightRGB: HeadroomControlColorValues.buttonFill(dark: false),
                                  darkRGB: HeadroomControlColorValues.buttonFill(dark: true))
    static let buttonLabel = Color(lightRGB: HeadroomControlColorValues.buttonLabel(dark: false),
                                   darkRGB: HeadroomControlColorValues.buttonLabel(dark: true))
    static let switchOn = Color(lightTint: HeadroomControlColorValues.switchOn(dark: false),
                                darkTint: HeadroomControlColorValues.switchOn(dark: true))
}

extension View {
    /// The one filled button: neutral fill, its named label ink, never system blue.
    func headroomProminentButton() -> some View {
        buttonStyle(.borderedProminent)
            .tint(PhoneControlStyle.buttonFill)
            .foregroundStyle(PhoneControlStyle.buttonLabel)
    }

    /// A switch's neutral on-state. Apply to each `Toggle` (U12's Settings rows).
    func headroomSwitchTint() -> some View {
        tint(PhoneControlStyle.switchOn)
    }
}

extension Color {
    /// A light/dark pair from Core values, resolved by the trait collection like an asset.
    init(lightRGB light: HeadroomRGBColor, darkRGB dark: HeadroomRGBColor) {
        self.init(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }

    init(lightTint light: HeadroomTint, darkTint dark: HeadroomTint) {
        self.init(uiColor: UIColor { traits in
            let tint = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: tint.color.red, green: tint.color.green, blue: tint.color.blue, alpha: tint.opacity)
        })
    }
}
