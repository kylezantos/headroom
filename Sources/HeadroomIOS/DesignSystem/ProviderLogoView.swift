import SwiftUI

struct ProviderLogoView: View {
    let providerID: String
    var size: CGFloat = 24

    @Environment(\.colorScheme) private var scheme

    // The raw brand mark, no tinted container — matching the Mac popover. The mark scales
    // by a per-provider optical factor inside a *fixed* slot, so Claude's edge-to-edge
    // starburst and Codex's inset blob read as equal-sized while the icon column stays
    // aligned across rows.
    var body: some View {
        let slot = size * 1.35
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.9, weight: .semibold))
                    .foregroundStyle(HeadroomTheme.providerTextAccent(for: providerID, scheme: scheme))
            }
        }
        .frame(width: slot * opticalScale, height: slot * opticalScale)
        .frame(width: slot, height: slot)
        .accessibilityHidden(true)
    }

    private var opticalScale: CGFloat {
        CGFloat(HeadroomBrandMark.opticalScale(for: providerID))
    }

    private var assetName: String? {
        switch providerID {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        default: nil
        }
    }

    private var symbolName: String {
        switch providerID {
        case ProviderID.claude.raw: "sparkles"
        case ProviderID.codex.raw: "terminal"
        default: "circle.dashed"
        }
    }
}
