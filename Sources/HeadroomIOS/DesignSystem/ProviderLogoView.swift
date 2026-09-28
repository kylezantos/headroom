import SwiftUI

struct ProviderLogoView: View {
    let providerID: String
    var size: CGFloat = 24
    var visualScale: CGFloat = 1

    @Environment(\.colorScheme) private var scheme

    // The raw brand mark, no tinted container — matching the Mac popover. OA2: the imageset
    // artwork is trimmed to its ink, so the mark is sized by the shared measured rule
    // (`HeadroomBrandMark`: larger ink dimension = 13/15 of the slot, aspect preserved) and
    // centred in the fixed slot, so every mark shares one centre line and an even gap to
    // its title — including a reduced (`visualScale`) mark.
    var body: some View {
        let slot = size * 1.35
        let mark = HeadroomBrandMark.markSize(for: providerID, slot: Double(slot))
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: CGFloat(mark.height), weight: .semibold))
                    .foregroundStyle(HeadroomTheme.providerTextAccent(for: providerID, scheme: scheme))
            }
        }
        .frame(width: CGFloat(mark.width) * visualScale, height: CGFloat(mark.height) * visualScale)
        .frame(width: slot, height: slot)
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        switch providerID {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        // Grok/Cursor imagesets carry a luminosity dark appearance, so the asset adapts
        // per scheme natively.
        case ProviderID.grok.raw: "GrokBrandIcon"
        case ProviderID.cursor.raw: "CursorBrandIcon"
        default: nil
        }
    }

    private var symbolName: String {
        switch providerID {
        case ProviderID.claude.raw: "sparkles"
        case ProviderID.codex.raw: "terminal"
        case ProviderID.grok.raw: "atom"
        case ProviderID.cursor.raw: "cursorarrow"
        default: "circle.dashed"
        }
    }
}
