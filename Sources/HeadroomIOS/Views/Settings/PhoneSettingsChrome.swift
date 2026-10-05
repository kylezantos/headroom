import SwiftUI

/// The phone's one display-preferences store. U8's cards and the Settings sheet read the same
/// instance, so a change in Settings reaches the Usage screen through observation (KTD11).
extension PhoneDisplayPreferencesStore {
    @MainActor static let app = PhoneDisplayPreferencesStore(defaults: .standard)
}

/// U12: the phone Settings sheet's swatch vocabulary. Kyle's U9-A: neutral like the popover,
/// never system blue, so every selected state and switch here is drawn in label ink.
enum PhoneSettingsStyle {
    /// Swatch geometry after the approved S2 mock (`design/ios-parity-options.html`, `.sw`):
    /// a 42pt well with a 10pt radius and 11pt medium names. The mock's 60pt swatch is 2pt
    /// short of the Format fragment the Mac draws (a 6pt "Weekly", a 4pt gap and the 32pt
    /// micro chip), so swatches are 62 on 5pt gaps: five columns need 330pt, inside the 332pt
    /// a list row leaves on a 390pt phone with the swatch rows' 12pt insets.
    static let swatchWidth: CGFloat = 62
    static let swatchSpacing: CGFloat = 5
    /// The swatch rows' list insets (see `swatchWidth`).
    static let swatchRowInset: CGFloat = 12
    static let wellHeight: CGFloat = 42
    static let wellCornerRadius: CGFloat = 10
    static let labelSpacing: CGFloat = 6
    static let swatchLabelFont = Font.system(size: 11, weight: .medium)
    /// Fixed-size swatch names: the five-column grid has no room to grow, and the list text
    /// around it keeps Dynamic Type (accessibility is best-effort this round, AGENTS.md).
    static let twoLineLabelHeight: CGFloat = 28
    /// The selected ring, from the mock's `--neutral-tint` (≈0.9 label ink in both schemes).
    static func selectionInk() -> Color { Color.primary.opacity(0.9) }
    /// The mock's `--toggle-neutral`: a switch's on-state is grey label ink, not blue (U9-A).
    static func switchTint() -> Color { Color.primary.opacity(0.62) }
    /// Controls that Match my Mac governs read as present but not choosable while it is on.
    static let governedOpacity: Double = 0.38
}

/// `MeterStyleTile`'s chrome on the phone: native list captions and help, a neutral ring for
/// the selection, and no container (the list section is the container).
struct PhoneMeterStyleChrome: MeterStyleTileChrome {
    var metrics: MeterStyleTileMetrics {
        MeterStyleTileMetrics(
            rowSpacing: 16,
            captionSpacing: 8,
            swatchWidth: PhoneSettingsStyle.swatchWidth,
            swatchSpacing: PhoneSettingsStyle.swatchSpacing,
            swatchPadding: 0,
            wellHeight: PhoneSettingsStyle.wellHeight,
            wellCornerRadius: PhoneSettingsStyle.wellCornerRadius,
            labelSpacing: PhoneSettingsStyle.labelSpacing,
            labelFont: PhoneSettingsStyle.swatchLabelFont,
            twoLineLabelHeight: PhoneSettingsStyle.twoLineLabelHeight,
            labelMinimumScaleFactor: 1,
            // The Mac's fragment, whole: it is the subject of the swatch.
            fragmentWidth: 60
        )
    }

    func caption(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    func help(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func selection(isSelected: Bool) -> PhoneSwatchSelection {
        PhoneSwatchSelection(isSelected: isSelected, cornerRadius: PhoneSettingsStyle.wellCornerRadius)
    }

    func selectionGroup(value: AnyHashable) -> PhoneSwatchSelectionGroup {
        PhoneSwatchSelectionGroup(value: value)
    }

    var swatchStyle: PhoneSwatchButtonStyle { PhoneSwatchButtonStyle() }

    func container() -> EmptyModifier { EmptyModifier() }
}

/// A selected swatch carries a 2pt neutral ring around its well and a heavier name; an
/// unselected one a 1pt hairline. The ring sits on the well's own radius, so the shared tile
/// and the theme, percentage and name swatches all read as one picker family (PB13).
struct PhoneSwatchSelection: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    var wellHeight: CGFloat = PhoneSettingsStyle.wellHeight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                // The ring frames the well only, so a two-line name never stretches it.
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? PhoneSettingsStyle.selectionInk() : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 2 : 1
                        )
                        .frame(height: min(proxy.size.height, wellHeight))
                }
            }
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
                value: isSelected
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One row of swatches. The ring cross-fades in place on `settle`; the Mac's travelling plate
/// (SM1) is a pointer-era affordance the phone's tap doesn't need.
struct PhoneSwatchSelectionGroup: ViewModifier {
    let value: AnyHashable

    func body(content: Content) -> some View {
        content
    }
}

/// S3A's press feedback on a swatch: the shared press scale, on the shared curves.
struct PhoneSwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? HeadroomMotion.pressScale : 1)
                .animation(
                    HeadroomMotion.resolved(
                        configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle,
                        .movement, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
        }
    }
}

/// A two-choice swatch picker (theme thumbnails, Left/Used, Neutral/Brand): each choice is a
/// well drawing its own sample over a name, in the tile's selection chrome.
struct PhoneSwatchPicker<Value: Hashable, Sample: View>: View {
    let options: [Value]
    let selection: Value
    let title: (Value) -> String
    let accessibilityName: String
    var wellWidth: CGFloat? = nil
    var wellHeight: CGFloat = 48
    let onSelect: (Value) -> Void
    @ViewBuilder let sample: (Value) -> Sample

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    VStack(spacing: PhoneSettingsStyle.labelSpacing) {
                        sample(option)
                            .frame(maxWidth: wellWidth ?? .infinity)
                            .frame(height: wellHeight)
                            .background(
                                ProviderStyle.recessedWell(dark: scheme == .dark),
                                in: RoundedRectangle(cornerRadius: PhoneSettingsStyle.wellCornerRadius, style: .continuous)
                            )
                        Text(title(option))
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .modifier(PhoneSwatchSelection(
                        isSelected: isSelected, cornerRadius: PhoneSettingsStyle.wellCornerRadius,
                        wellHeight: wellHeight))
                    .frame(maxWidth: wellWidth ?? .infinity)
                }
                .buttonStyle(PhoneSwatchButtonStyle())
                .accessibilityLabel("\(title(option)) \(accessibilityName)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
