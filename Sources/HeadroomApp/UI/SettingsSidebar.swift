import AppKit
import SwiftUI
import HeadroomCore

/// Sidebar column of the Settings window (R1/R3): identity block on top, then the six
/// destinations in two sections. Order and section membership are read straight off
/// `SettingsPane`, so there is no second list to keep in sync.
///
/// KTD1: the list is a value-driven `List(selection:)`, never `NavigationLink(destination:)`
/// — the latter leaves the detail column blank on the first selection on macOS 15.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    /// L10A: the identity block's top inset. The window has a hidden title bar (KTD8),
    /// so this is measured from the top of the sidebar column and has two jobs at once —
    /// clear the floating traffic lights, and land the logo's vertical centre on the same
    /// line as the detail pane's title, which sits at `SettingsPaneScaffold`'s 20pt top
    /// padding at 15pt semibold. The old 30pt only did the first, which is the "weird
    /// relationship with the top of the content" in the review.
    ///
    /// **Measured, not derived.** `NavigationSplitView` gives the two columns different
    /// top insets under a hidden title bar — the sidebar's content starts 10pt lower than
    /// the detail's — so the arithmetic does not close. Read off the live window's
    /// accessibility frames at 800 × 700: identity block top 433, height 28 (centre 447);
    /// title top 437, height 19 (centre 446.5). The layout quantises to whole points, so
    /// 5.5 lands the mark 0.5pt above the title's box centre and 6.0 lands it 0.5pt
    /// below; 5.5 wins because the title's box carries descender space its glyphs don't,
    /// putting its optical centre slightly above its box centre. Re-measure if the pane
    /// title's size or the scaffold's top padding changes.
    private static let identityTopInset: CGFloat = 5.5

    /// L10A: gap between the identity block and the first navigation row.
    private static let navigationGap: CGFloat = 14

    /// L10A: 28, down from 34. The block reads as a stamp beside the pane title rather
    /// than a masthead, and 28 is what puts the centre on the title's line at a top
    /// inset that still clears the traffic lights.
    private static let logoSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, Self.identityTopInset)
                .padding(.horizontal, 12)
                .padding(.bottom, Self.navigationGap)

            List(selection: $selection) {
                ForEach(SettingsPane.Group.allCases) { group in
                    Section(group.label) {
                        ForEach(group.panes) { pane in
                            Label(pane.label, systemImage: pane.symbolName)
                                // The column is sized for the longest destination
                                // ("Widgets & iPhone", 108pt of glyphs at 13pt), but a
                                // future name or a larger text size must truncate on one
                                // line rather than wrap a sidebar row to two.
                                .lineLimit(1)
                                .tag(pane)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// Identity block replacing the removed window title and Done footer (KD3). The mark
    /// is rendered from the bundled SVG rather than `NSApplication.applicationIconImage`
    /// — the latter is a single flattened OS-cached snapshot (not the asset catalog's
    /// multi-resolution art) and rendered pixelated here.
    private var header: some View {
        HStack(spacing: 9) {
            if let image = AppIconGlyph.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.logoSize, height: Self.logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // Neutral 1pt inset outline defines the icon edge on the window
                    // surface — pure black in light, pure white in dark, never tinted
                    // (UI craft: image outlines). `.strokeBorder` insets so it stays
                    // concentric with the clip and doesn't grow the icon.
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                (colorScheme == .dark ? Color.white : Color.black).opacity(0.10),
                                lineWidth: 1
                            )
                    )
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Headroom")
                    .font(.system(size: 14, weight: .semibold))
                    .kerning(-0.2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let version = Self.versionLabel {
                    // Quiet stamp under the name. Hidden under `swift run` (no bundle
                    // Info.plist) rather than showing a placeholder.
                    Text(version)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @Environment(\.colorScheme) private var colorScheme

    static let versionLabel: String? = {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.isEmpty else { return nil }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return "v\(short) (\(build))"
        }
        return "v\(short)"
    }()
}

extension SettingsPane {
    /// SF Symbol per destination. Kept beside the sidebar rather than in Core: the
    /// enum is the pure identity, the glyph is presentation.
    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .appearance: "circle.lefthalf.filled"
        case .menuBar: "menubar.rectangle"
        case .widgets: "square.grid.2x2"
        case .accounts: "person"
        case .apiSpend: "key"
        }
    }
}

/// Loads the vessel mark straight from its bundled SVG (mirrors `ProviderLogoView`'s
/// `BrandIconImage` lookup) so the Settings sidebar always renders crisp, resolution-
/// independent art instead of depending on the OS's cached app-icon snapshot.
enum AppIconGlyph {
    static let image: NSImage? = {
        guard let url = url(forResource: "vessel-app-icon") else { return nil }
        return NSImage(contentsOf: url)
    }()

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
