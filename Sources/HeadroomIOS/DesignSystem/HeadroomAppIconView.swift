import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HeadroomAppIconView: View {
    var size: CGFloat = 30

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = Self.appIconImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackIcon
            }
            #else
            fallbackIcon
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: size * 0.16, y: size * 0.06)
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(red: 0.055, green: 0.070, blue: 0.095))
            VesselMark(fill: 0.58)
                .frame(width: size * 0.36, height: size * 0.62)
                // U10: the vessel's neutral inks follow the scheme; the icon tile is always
                // dark, so it takes the dark inks in either appearance.
                .environment(\.colorScheme, .dark)
        }
    }

    #if canImport(UIKit)
    private static var appIconImage: UIImage? {
        UIImage(named: "AppIcon") ?? primaryIconFileName.flatMap { UIImage(named: $0) }
    }

    private static var primaryIconFileName: String? {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primaryIcon["CFBundleIconFiles"] as? [String],
            let fileName = files.last
        else { return nil }
        return fileName
    }
    #endif
}
