import SwiftUI
import AppKit
import HeadroomCore

/// Provider brand mark used at small UI sizes. Bundled SVGs render through AppKit;
/// SF Symbols remain the fallback for unknown providers.
struct ProviderLogoView: View {
    let providerID: ProviderID
    var size: CGFloat = 16

    var body: some View {
        // Per-provider optical-size correction inside a fixed slot (shared with iOS via
        // HeadroomCore), so Claude's edge-to-edge starburst and Codex's inset blob read as
        // equal weight across every surface.
        let scale = CGFloat(HeadroomBrandMark.opticalScale(for: providerID.raw))
        if let image = BrandIconImage.image(for: providerID) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: ProviderStyle.symbol(for: providerID))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(ProviderStyle.accent(for: providerID))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

private enum BrandIconImage {
    static func image(for providerID: ProviderID) -> NSImage? {
        guard let name = ProviderStyle.svgResourceName(for: providerID),
              let url = url(forResource: name) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func url(forResource name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            return url
        }
        let swiftPMBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Headroom_HeadroomApp.bundle")
        return Bundle(url: swiftPMBundleURL)?
            .url(forResource: name, withExtension: "svg")
    }
}
