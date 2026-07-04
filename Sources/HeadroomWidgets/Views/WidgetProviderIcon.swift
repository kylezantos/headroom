import HeadroomCore
import SwiftUI

struct WidgetProviderIcon: View {
    let providerID: String
    var size: CGFloat = 16

    var body: some View {
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
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
