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
    let text: String

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

/// Persistent configured state for credential rows. Only the checkmark carries the
/// success treatment; the text stays quiet so this reads as status, not a celebratory
/// badge competing with the provider title.
struct SavedCredentialStatus: View {
    @Environment(\.colorScheme) private var scheme

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
            Text("Saved securely")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Key saved securely")
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
/// the family: one step under the popover's 16pt card titles, two above the 13pt
/// controls, so size separates the levels instead of weight alone.
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
        VStack(alignment: .leading, spacing: 10) {
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
/// the Menu Bar pane applies `menuBarPreviewPlate()` directly because its strip stacks two
/// labels for a reflow-free percentage swap.
struct MenuBarPreviewPill: View {
    let meters: [MenuBarMeter]
    let showsPercentage: Bool

    var body: some View {
        MenuBarLabel(meters: meters, showsPercentage: showsPercentage)
            .menuBarPreviewPlate()
    }
}

extension View {
    /// The menu-bar specimen's dark plate. The specimens use `MenuBarLabel`'s default
    /// `.pinnedDark` appearance (white ink + dark severity colors) rather than following the
    /// live menu bar (L1A), so on a light well that ink would vanish; the plate keeps the
    /// preview faithful in both appearances. Shared by the Menu Bar pane and the Appearance
    /// specimen so the two strips cannot drift.
    func menuBarPreviewPlate() -> some View {
        self
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Color(white: 0.15),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    /// The recessed well behind a settings preview (specimen or menu-bar strip).
    func settingsPreviewWell(dark: Bool, verticalPadding: CGFloat) -> some View {
        self
            .padding(.horizontal, 9)
            .padding(.vertical, verticalPadding)
            .background(
                ClaudeSetupStyle.wellBackground(dark: dark),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}
