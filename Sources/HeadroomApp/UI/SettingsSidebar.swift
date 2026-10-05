import AppKit
import SwiftUI
import HeadroomCore

/// Sidebar column of the Settings window (R1/R3): identity block on top, then the
/// destinations in their sections. Order and section membership are read straight off
/// `SettingsPane`, so there is no second list to keep in sync.
///
/// KTD1: the list is a value-driven `List(selection:)`, never `NavigationLink(destination:)`
/// — the latter leaves the detail column blank on the first selection on macOS 15.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    /// R2M8: the window opens with the destination list focused, so arrow keys move between
    /// rooms without a mouse trip first. Nothing here animates — a keyboard-initiated pane
    /// change rides the same 120ms cross-fade a click does, which is M6B's decision, and
    /// focus itself is instant by construction.
    @FocusState private var listFocused: Bool

    /// L10A: the identity block's top inset. The window has a hidden title bar (KTD8),
    /// so this is measured from the top of the sidebar column and has two jobs at once —
    /// clear the floating traffic lights, and land the logo's vertical centre on the same
    /// line as the detail pane's title, which sits at `SettingsPaneScaffold`'s 20pt top
    /// padding. The old 30pt only did the first, which is the "weird relationship with the
    /// top of the content" in the review.
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
    ///
    /// Re-measured after PB2 (pane title 15 → 17 semibold) on the harness render: the
    /// identity row's cap centre sat at 27.5pt and the pane title's at 29.5pt, so the inset
    /// grew by that 2pt. Still a measurement, not arithmetic — the two columns' insets do
    /// not close, which is why this note exists at all.
    private static let identityTopInset: CGFloat = 7.5

    /// L10A: gap between the identity block and the first navigation row.
    private static let navigationGap: CGFloat = 14

    /// L10A: 28, down from 34. The block reads as a stamp beside the pane title rather
    /// than a masthead, and 28 is what puts the centre on the title's line at a top
    /// inset that still clears the traffic lights.
    private static let logoSize: CGFloat = 28

    var body: some View {
        let _ = BenchCounters.hit("SettingsSidebar")
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, Self.identityTopInset)
                // R2B2: 10, down from 12. `List(.sidebar)`'s own row insets put the
                // destination glyphs and labels one step further in than this block was, so
                // the mark now lands on the row pills' edge and "Headroom" on the row-label
                // axis instead of both sitting 2pt proud of the list beneath them.
                .padding(.horizontal, 10)
                .padding(.bottom, Self.navigationGap)

            List(selection: $selection) {
                ForEach(SettingsPane.Group.allCases) { group in
                    if let label = group.label {
                        Section(label) { rows(for: group) }
                    } else {
                        Section { rows(for: group) }
                    }
                }
            }
            .listStyle(.sidebar)
            .focused($listFocused)
        }
        // R2M8: focus the destination list when the window opens.
        .defaultFocus($listFocused, true)
    }

    private func rows(for group: SettingsPane.Group) -> some View {
        ForEach(group.panes) { pane in
            Label {
                Text(pane.label)
            } icon: {
                Image(systemName: pane.symbolName)
                    .imageScale(pane.symbolScale)
            }
            // The column is sized for the longest destination
            // ("Widgets & iPhone", 108pt of glyphs at 13pt), but a
            // future name or a larger text size must truncate on one
            // line rather than wrap a sidebar row to two.
            .lineLimit(1)
            .tag(pane)
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
                        .font(SettingsType.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @Environment(\.colorScheme) private var colorScheme

    /// The sidebar's stamp is the plain version with the family's "v" prefix. The
    /// bundle reads live in `AppVersionLabel` so the General pane's Updates row (L13)
    /// prints the same number without a second copy of this logic.
    static var versionLabel: String? { AppVersionLabel.prefixed }
}

extension SettingsPane {
    /// SF Symbol per destination. Kept beside the sidebar rather than in Core: the
    /// enum is the pure identity, the glyph is presentation.
    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        // PB12: striped, not filled. Appearance was the one solid glyph in a sidebar of
        // outlines, so it read as the selected row even when it wasn't.
        case .appearance: "circle.lefthalf.striped.horizontal"
        case .menuBar: "menubar.rectangle"
        case .widgets: "square.grid.2x2"
        // R1 (notifications plan): the outline bell, matching the sidebar's outline family.
        case .notifications: "bell"
        case .accounts: "person"
        case .apiSpend: "key"
        case .about: "info.circle"
        }
    }

    /// R2B3: `person` and `key` are drawn inside a narrower optical box than the four
    /// geometric symbols beside them, so at one nominal size they read about a point
    /// smaller in the row. One scale step up puts all six on the same apparent height.
    /// The correction is optical, not geometric — re-check it if the glyphs ever change.
    /// `bell` fills its box like the App-group glyphs above it, so it stays at `.medium`.
    var symbolScale: Image.Scale {
        switch self {
        case .accounts, .apiSpend: .large
        case .general, .appearance, .menuBar, .widgets, .notifications, .about: .medium
        }
    }
}

/// The app's marketing version and build, read once from the bundle. Nil under
/// `swift run` (no bundle Info.plist), so callers hide their row rather than print a
/// placeholder.
enum AppVersionLabel {
    /// "1.4.0 (32)", or "1.4.0" when no build number is stamped.
    static let plain: String? = {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.isEmpty else { return nil }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }()

    /// "v1.4.0 (32)" — the sidebar identity block's form.
    static var prefixed: String? { plain.map { "v\($0)" } }
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
