import SwiftUI
import HeadroomCore

/// Theme picked from three mini-window thumbnails (R7, KD5). Theme used to be the one
/// visual choice in Settings with no preview, sitting beside meter swatches that all
/// preview themselves; the thumbnails give it the same feedback level.
///
/// KTD5: three plain `Button`s whose *container* carries an `accessibilityRepresentation`
/// of a `Picker`, so VoiceOver announces one control with three values instead of three
/// unrelated buttons. `.pickerStyle(.radioGroup)` was rejected: it can't host thumbnail
/// labels without the radio circles.
struct ThemeThumbnailPicker: View {
    @Binding var selection: AppearancePreference

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The row is a `LazyVGrid`, matching `MeterStyleTile`'s swatch rows, and that is
        // load-bearing rather than stylistic: with these fixed-size thumbnails in a plain
        // `HStack`, AppKit raised inside `-[NSWindow _postWindowNeedsUpdateConstraints]`
        // — an exception thrown *during* the window's layout pass, so the app terminated —
        // every time a sibling tile resized, e.g. switching Meter style Format between
        // Micro and Full. Bisected against the live demo window: identical thumbnails in
        // a grid, no crash.
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
            ForEach(AppearancePreference.allCases) { preference in
                thumbnail(preference)
            }
        }
        .accessibilityRepresentation {
            Picker("Theme", selection: $selection) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
        }
    }

    private static let columns = [
        GridItem(
            .adaptive(minimum: ThemeThumbnailPicker.artWidth + 10,
                      maximum: ThemeThumbnailPicker.artWidth + 36),
            spacing: 8
        )
    ]

    /// Same chrome as `MeterStyleTile`'s shape/fill swatches — 8pt continuous ring, 2pt
    /// accent when selected and a 1pt hairline otherwise, 10.5pt medium caption — so the
    /// Appearance pane reads as one family of choices rather than two control languages.
    private func thumbnail(_ preference: AppearancePreference) -> some View {
        let isSelected = selection == preference

        return Button {
            selection = preference
        } label: {
            VStack(spacing: 5) {
                ThemeThumbnailArt(preference: preference)
                    .frame(width: Self.artWidth, height: Self.artHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        // Keeps a light thumbnail's edge visible against the light tile.
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(ClaudeSetupStyle.hairline(dark: colorScheme == .dark), lineWidth: 1)
                    )

                Text(preference.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(5)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : ClaudeSetupStyle.hairline(dark: colorScheme == .dark),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(preference.themeHelpText)
        .accessibilityLabel("\(preference.label) theme")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        // S1A/S2A: the ring's tint, its 1↔2pt width, and the 8% accent fill are all colour
        // work, so the house press curve carries them and Reduce Motion keeps the cross-fade.
        .animation(HeadroomMotion.resolved(HeadroomMotion.pressDown, .crossfade, reduceMotion: reduceMotion),
                   value: isSelected)
    }

    static let artWidth: CGFloat = 96
    static let artHeight: CGFloat = 64
}

private extension AppearancePreference {
    var themeHelpText: String {
        switch self {
        case .system: "Follow the system appearance"
        case .light: "Always use the light appearance"
        case .dark: "Always use the dark appearance"
        }
    }
}

/// The thumbnail art: a mini window (title strip + three content rows) drawn in SwiftUI
/// from tokens rather than shipped as bitmaps, so it stays crisp at any scale and can't
/// drift from the real window's fills. Light and Dark are drawn at *fixed* values, not
/// scheme-derived ones — a Dark thumbnail has to look dark while the window is light.
/// System is the two drawings split on the diagonal.
private struct ThemeThumbnailArt: View {
    let preference: AppearancePreference

    var body: some View {
        switch preference {
        case .light:
            miniWindow(dark: false)
        case .dark:
            miniWindow(dark: true)
        case .system:
            ZStack {
                miniWindow(dark: false)
                miniWindow(dark: true)
                    .clipShape(DiagonalHalf())
            }
        }
    }

    /// Values mirror the shipping surfaces: the window background, the `RaisedTile`
    /// opaque fill that every settings tile uses, and the row ink at the same relative
    /// contrast — approximated as literals because the drawing must not follow the
    /// current scheme.
    private func miniWindow(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleStrip(dark: dark)
            VStack(alignment: .leading, spacing: 6) {
                row(widthFraction: 0.74, dark: dark, emphasis: true)
                row(widthFraction: 0.56, dark: dark, emphasis: false)
                row(widthFraction: 0.40, dark: dark, emphasis: false)
            }
            .padding(.horizontal, 8)
            .padding(.top, 9)
            Spacer(minLength: 0)
        }
        .frame(width: ThemeThumbnailPicker.artWidth, height: ThemeThumbnailPicker.artHeight, alignment: .topLeading)
        .background(dark ? Color(white: 0.13) : Color(white: 0.925))
    }

    private func titleStrip(dark: Bool) -> some View {
        Rectangle()
            .fill(dark ? Color(white: 0.19) : Color(white: 0.98))
            .frame(height: 13)
            .overlay(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(dark ? Color.white.opacity(0.24) : Color.black.opacity(0.16))
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .padding(.leading, 6)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                    .frame(height: 0.5)
            }
    }

    private func row(widthFraction: CGFloat, dark: Bool, emphasis: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(
                dark
                    ? Color.white.opacity(emphasis ? 0.34 : 0.18)
                    : Color.black.opacity(emphasis ? 0.30 : 0.16)
            )
            .frame(width: (ThemeThumbnailPicker.artWidth - 16) * widthFraction, height: 5)
    }
}

/// Lower-right triangle: the System thumbnail's dark half.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
