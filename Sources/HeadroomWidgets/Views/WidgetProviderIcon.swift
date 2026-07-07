import HeadroomCore
import SwiftUI

struct WidgetProviderIcon: View {
    let providerID: String
    var size: CGFloat = 16

    var body: some View {
        // Optical-size correction inside a fixed slot (shared with the app via HeadroomCore)
        // so Claude and Codex read as equal weight.
        let scale = CGFloat(HeadroomBrandMark.opticalScale(for: providerID))
        Group {
            if let assetName = WidgetProviderStyle.assetName(for: providerID) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: WidgetProviderStyle.symbol(for: providerID))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(WidgetProviderStyle.accent(for: providerID))
            }
        }
        .frame(width: size * scale, height: size * scale)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
