import SwiftUI
import HeadroomCore

/// Shared row vocabulary for the Settings window (settings-ui audit, Jul 2026): one
/// grammar everywhere — label on the leading edge, control on the trailing edge — so
/// the eye never re-learns a row. Master on/off rows are switches (the System Settings
/// idiom); dependent sub-options stay native checkboxes.
struct SettingsSwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                // Visually hidden; VoiceOver still announces the title, so the row
                // reads label-left/switch-right without duplicating the text.
                .labelsHidden()
        }
    }
}

/// Uniform descriptive fine print — 11pt secondary with opened line spacing, the same
/// step the popover uses for reset countdowns. One style for every help line in the
/// window (the Widgets section previously ran 10pt `.caption`, splitting one role
/// across two sizes).
struct SettingsHelpText: View {
    private let text: AttributedString

    init(text: String) {
        self.text = AttributedString(text)
    }

    /// PB8: the attributed form exists for help lines that carry an in-app link (the Widgets
    /// pane's pointer back to Menu Bar). Same role, same 11pt secondary treatment.
    init(attributed text: AttributedString) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .lineSpacing(2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            // W2A: cap the measure at ~75 characters (≈460pt at 11pt SF), the width a
            // help line stays comfortably readable at. Without it these lines inherit
            // the pane's 640 content cap, which stretches a two-line string until the
            // second line is a one- or two-word orphan.
            .frame(maxWidth: 460, alignment: .leading)
    }
}

/// PB13: the window's one affirmative-state row — a check in a tinted disc beside a quiet
/// 11pt semibold label. Only the checkmark carries the success treatment; the text stays
/// quiet so this reads as status, not a celebratory badge competing with the row title.
/// Shared by "Saved securely" (API Spend) and "Connected" (Accounts), which used to be two
/// unrelated drawings of the same idea.
struct SettingsSuccessStatus: View {
    let text: String
    /// Defaults to the visible text; API Spend spells its state out for VoiceOver.
    var accessibilityText: String?

    @Environment(\.colorScheme) private var scheme

    init(text: String, accessibilityText: String? = nil) {
        self.text = text
        self.accessibilityText = accessibilityText
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
                .frame(width: 16, height: 16)
                .background(
                    ClaudeSetupStyle.connectedBackground(dark: scheme == .dark),
                    in: Circle()
                )
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText ?? text)
    }
}

/// Persistent configured state for credential rows.
struct SavedCredentialStatus: View {
    var body: some View {
        SettingsSuccessStatus(text: "Saved securely", accessibilityText: "Key saved securely")
    }
}

/// The row-tag capsule: 10pt medium secondary ink on the step material. Shared so the
/// Accounts tags ("CLI login", "Same login as X") and the Menu Bar pane's "Off" tag
/// cannot drift into two badge styles for one role.
struct SettingsPillBadge: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(ClaudeSetupStyle.stepBackground(dark: colorScheme == .dark), in: Capsule())
    }
}

/// Shared metrics for the Settings window's panes.
enum SettingsMetrics {
    /// One trailing-control width for every segmented picker (Theme / provider window /
    /// Period). The old window ran three widths (280 / 200 / unconstrained), so the
    /// eye re-learned the layout per row.
    static let segmentedMaxWidth: CGFloat = 220
}

/// One material for every section: the popover's card language — `RaisedTile` at
/// 13pt padding / 10pt radius (matching `ProviderCardView`), full width so sibling
/// tiles never render at two widths. Tile headers are 15pt semibold, kerned like
/// the family: one step under the pane title's 17 (PB2) and two above the 13pt
/// controls, so size separates the levels instead of weight alone. This comment used to
/// cite "the popover's 16pt card titles" as the step above; that reference was stale —
/// the tile headers here are 15 and the level above them is the pane title.
struct SettingsTile<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// Untitled form for the single-tile panes (General, Menu Bar, Widgets & iPhone,
    /// API Spend). The sidebar rebuild made the pane scaffold print the destination name
    /// as the first row, so a lone tile repeating it said the same word twice a line
    /// apart. Multi-tile panes (Appearance, Accounts) still need their tile titles.
    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.content = content()
    }

    var body: some View {
        // PB4: 18, up from 10. A tile's direct children are *groups* (a switch with its
        // help lines, a picker with its caption), and those groups run 4–8pt internally,
        // so a 10pt gap between them was only ~1.4× the gap inside them — not enough for
        // "Period" to read as its own setting rather than the row above it's.
        VStack(alignment: .leading, spacing: 18) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
            }
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10, surface: .opaque)
    }
}

struct ResponsiveControlRow<Content: View>: View {
    private let label: String
    private let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                Spacer(minLength: 12)
                content
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                content
            }
        }
    }
}

/// PB13: one selection ring for every picker in Settings. `MeterStyleTile`,
/// `ThemeThumbnailPicker`, and `InAppDisplayTile` each carried a verbatim copy of this
/// 8pt ring, 8% accent fill, and press-curve animation, so the three pickers standing
/// side by side in Appearance could silently drift apart on any one edit.
private struct SettingsSelectionChrome: ViewModifier {
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor
                            : ClaudeSetupStyle.hairline(dark: colorScheme == .dark),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            // S1A/S2A/M5A: the ring's tint, its 1↔2pt width, and the 8% fill are all colour
            // work, so the house press curve carries them and Reduce Motion keeps the
            // cross-fade instead of hard-cutting.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.pressDown, .crossfade, reduceMotion: reduceMotion),
                value: isSelected
            )
    }
}

extension View {
    /// The selected/unselected chrome for a Settings swatch or thumbnail (PB13).
    func selectionChrome(isSelected: Bool) -> some View {
        modifier(SettingsSelectionChrome(isSelected: isSelected))
    }
}

private struct SettingsRevealTransitionModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .offset(y: active ? 4 : 0)
            .blur(radius: active ? 1.5 : 0)
    }
}

extension AnyTransition {
    /// Enter with the settle vocabulary (opacity + 4pt rise + slight blur), exit
    /// opacity-only — exits softer than enters.
    static var settingsReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettingsRevealTransitionModifier(active: true),
                identity: SettingsRevealTransitionModifier(active: false)
            ),
            removal: .opacity
        )
    }
}

/// A single-label menu-bar specimen on the shared plate. Used by the Appearance specimen;
/// the Menu Bar pane applies `menuBarPreviewPlate(darkMenuBar:)` directly because its strip
/// stacks two labels for a reflow-free percentage swap.
struct MenuBarPreviewPill: View {
    let meters: [MenuBarMeter]
    let showsPercentage: Bool

    var body: some View {
        // PB13: read inside `body` so the observation registers here and the plate repaints
        // with the label the moment the bar flips.
        let darkMenuBar = MenuBarAppearanceMonitor.shared.isDarkMenuBar
        return MenuBarLabel(meters: meters, showsPercentage: showsPercentage, appearance: .menuBar)
            .menuBarPreviewPlate(darkMenuBar: darkMenuBar)
    }
}

extension View {
    /// The menu-bar specimen's plate. PB13: the previews follow the *live* menu bar
    /// (`MenuBarAppearanceMonitor`, the same source the real status item reads) instead of
    /// pinning dark, because L1A's whole point is that a dark bar is not universal — a light
    /// wallpaper turns the bar light and the pinned specimen then previewed a state the user
    /// isn't in. `MenuBarLabel`'s own default stays `.pinnedDark`; the call sites here pass
    /// `.menuBar` explicitly and swap the plate underneath with the same flag, so dark ink on
    /// a light bar still lands on a light plate. Shared by the Menu Bar pane and the
    /// Appearance specimen so the two strips cannot drift.
    func menuBarPreviewPlate(darkMenuBar: Bool) -> some View {
        self
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                darkMenuBar ? Color(white: 0.15) : Color(white: 0.93),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    /// The recessed well behind a settings preview (specimen or menu-bar strip).
    ///
    /// AP3: the horizontal inset is a parameter now. 9pt is right for the narrow menu-bar
    /// strips — the plate is nearly the whole content — but the Appearance specimen holds a
    /// full provider card, which read as jammed against the well's edge; it passes more.
    func settingsPreviewWell(
        dark: Bool,
        verticalPadding: CGFloat,
        horizontalPadding: CGFloat = 9
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                ClaudeSetupStyle.wellBackground(dark: dark),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}
