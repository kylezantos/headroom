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
            .font(SettingsType.help)
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
/// 11pt label (T4: regular, the status role's weight). Only the checkmark carries the success
/// treatment; the text stays quiet so this reads as status, not a celebratory badge
/// competing with the row title.
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
                .font(SettingsType.help)
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

    // R2C19: one spacing scale for the whole window. Every container used to spend a single
    // value on both "header → its content" and "sibling → sibling" (pane 14/14, tile 18/18,
    // swatch tiles 16/16), which put three levels of hierarchy inside a 4pt band — the reason
    // Appearance read as one long list rather than three named tiles. Header→content is now
    // the tightest gap in the window and container→container the widest, so the level a gap
    // separates is legible from the gap alone. System Settings runs ~8 header→box, ~20
    // box→box.

    /// A title to the first thing it heads (pane title → first tile, tile title → first group).
    static let headerToContent: CGFloat = 10
    /// Sibling groups inside one tile (a switch with its help lines → the next control).
    static let groupToGroup: CGFloat = 20
    /// Sibling tiles inside a pane.
    static let tileToTile: CGFloat = 28
    /// A control's own label to the control (inline rows).
    static let labelToControl: CGFloat = 4
    /// A label stacked above what it names: `ResponsiveControlRow` once stacked, and a group
    /// label over its swatch grid or preview well (T6: those ran 4, 6 and 8 for one job).
    static let labelToStackedControl: CGFloat = 6
    /// Siblings inside one group — account rows, a switch's indented sub-options, a key
    /// editor's parts. Tighter than `groupToGroup`, so the group still reads as one unit.
    static let withinGroup: CGFloat = 8
}

/// T1 (2026-09-24 type audit): the window's type ramp, one role per step. Seven roles used
/// to share 11pt secondary and differ only by weight, which at that size and ink the eye
/// can't separate, and group labels ran quieter than the swatch labels they headed. Each
/// step now differs from its neighbour in size or ink, not weight alone, and maps to a
/// macOS text style.
enum SettingsType {
    /// The pane's own title (T5: 20, up from 17 — at 17 it was a twin of the 15pt tile
    /// titles under it). 20 is where SF switches to its Display cut.
    static let paneTitle = Font.system(size: 20, weight: .semibold)
    static let paneTitleKerning: CGFloat = -0.3
    /// A tile's title (title3, emphasized).
    static let tileTitle = Font.system(size: 15, weight: .semibold)
    static let tileTitleKerning: CGFloat = -0.2
    /// A label naming a group — swatch rows, preview wells, provider group headers
    /// (headline). Primary ink: a heading is never quieter than what it heads.
    static let groupLabel = Font.system(size: 13, weight: .semibold)
    /// Help lines, counts, and statuses (subheadline). Regular weight only; a status sets
    /// itself apart with an icon or colour. Warning-coloured statuses keep `.medium`.
    static let help = Font.system(size: 11)
    /// The caption under a swatch or thumbnail (T7: 11, off the 10.5 half-step).
    static let swatchLabel = Font.system(size: 11, weight: .medium)
    /// Small print: emails, tags, preview captions (footnote).
    static let footnote = Font.system(size: 10)
}

/// T1: the one group-label treatment — Format / Shape / Fill, Display, In your menu bar,
/// and every other label that names the controls under it.
struct SettingsGroupLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(SettingsType.groupLabel)
    }
}

/// Settings copy that more than one pane prints, so the two can never drift into two
/// wordings of one rule.
enum SettingsCopy {
    /// R2B1/PB9: one constant for the "off" consequence, shown as an Accounts help line and
    /// as the Menu Bar pane's Off-tag tooltip. No trailing stop — it is a label, not prose,
    /// and the two sites used to disagree on exactly that.
    static let providerOffNotice = "Not fetched while this provider is off"

    /// The same notice as a clause after the Menu Bar pane's "Off" tag, derived rather than
    /// retyped so VoiceOver and the tooltip stay one sentence.
    static let providerOffAccessibilityLabel =
        "Off — " + providerOffNotice.prefix(1).lowercased() + providerOffNotice.dropFirst()
}

/// One material for every section: the popover's card language — `RaisedTile` at
/// 13pt padding / 10pt radius (matching `ProviderCardView`), full width so sibling
/// tiles never render at two widths. Tile headers are `SettingsType.tileTitle`: under the
/// 20pt pane title (T5) and over the 13pt group labels and controls, so size separates the
/// levels instead of weight alone.
struct SettingsTile<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// Untitled form for the single-tile panes (General, Menu Bar, Widgets & iPhone,
    /// Accounts, API Spend). The sidebar rebuild made the pane scaffold print the destination
    /// name as the first row, so a lone tile repeating it said the same word twice a line
    /// apart. Multi-tile panes (Appearance) still need their tile titles.
    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.content = content()
    }

    var body: some View {
        // R2C19: the tile's two levels are spaced apart instead of sharing PB4's single 18.
        // PB4's reasoning stands — a tile's direct children are *groups* (a switch with its
        // help lines, a picker with its caption) running 4–8pt internally, so they need a
        // clear step above that — but the title heading them is a level up again and belongs
        // closer to what it names.
        VStack(alignment: .leading, spacing: SettingsMetrics.headerToContent) {
            if let title {
                Text(title)
                    .font(SettingsType.tileTitle)
                    .kerning(SettingsType.tileTitleKerning)
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.groupToGroup) {
                content
            }
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

            VStack(alignment: .leading, spacing: SettingsMetrics.labelToStackedControl) {
                Text(label)
                content
            }
        }
    }
}

/// R2M6: the hover flag `SettingsSwatchButtonStyle` publishes to the selection chrome inside
/// its label. The chrome owns every fill and border a swatch draws, so hover has to reach it
/// rather than stack a second neutral wash on top of a selected swatch's accent fill.
private struct SettingsSwatchHoverKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var settingsSwatchHovering: Bool {
        get { self[SettingsSwatchHoverKey.self] }
        set { self[SettingsSwatchHoverKey.self] = newValue }
    }
}

/// R2M6: the press-and-hover pair for the 17 Appearance swatches — the third control family
/// in the app, and the only one PA11b's "every custom button needs a press state" never
/// reached. Until this, clicking an already-selected swatch did literally nothing and the
/// first feedback on an unselected one arrived after the commit.
///
/// Hover lives in the chrome (see the environment flag above); this style owns the press.
/// No hover scale — a swatch is a plate in a grid, and lifting one shifts its neighbours'
/// apparent alignment.
struct SettingsSwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwatchBody(configuration: configuration)
    }

    private struct SettingsSwatchBody: View {
        let configuration: Configuration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// The disabled Tube swatch opts out of both bands: it already reads at 0.45 and a
        /// hover fill under a control that cannot be clicked teaches a false affordance.
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            // S3A: feedback lands on pointer-down and returns on settle.
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            configuration.label
                .environment(\.settingsSwatchHovering, hovering && isEnabled)
                // S2A: scaling is movement, so Reduce Motion drops it while the chrome's
                // fills below keep their timing — the `HoverButtonStyle` split.
                .scaleEffect(configuration.isPressed ? HeadroomMotion.pressScale : 1)
                .animation(
                    HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
                .onHover { hovering = $0 }
        }
    }
}

/// SM1: the namespace a swatch row's selection plate travels in. Set by
/// `settingsSelectionGroup(value:)`; nil outside a group or under Reduce Motion, where the
/// chrome falls back to cross-fading the ring in place.
private struct SettingsSelectionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private extension EnvironmentValues {
    var settingsSelectionNamespace: Namespace.ID? {
        get { self[SettingsSelectionNamespaceKey.self] }
        set { self[SettingsSelectionNamespaceKey.self] = newValue }
    }
}

/// SM1: one picker row whose selection plate travels. Each row owns its own namespace, so
/// Format, Shape, and Fill never trade plates with each other.
private struct SettingsSelectionGroup<Value: Equatable>: ViewModifier {
    let value: Value

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.settingsSelectionNamespace, reduceMotion ? nil : namespace)
            // The row-level scope is what puts the outgoing and incoming plate in one
            // animated transaction; each swatch's own `isSelected` scope below carries the
            // same spring, so the two can never disagree.
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.selectionTravel, .movement, reduceMotion: reduceMotion),
                value: value
            )
    }
}

/// PB13: one selection ring for every picker in Settings. `MeterStyleTile`,
/// `ThemeThumbnailPicker`, and `InAppDisplayTile` each carried a verbatim copy of this
/// ring, accent fill, and animation, so the three pickers standing side by side in
/// Appearance could silently drift apart on any one edit.
///
/// SM1 (2026-09-22): inside a `settingsSelectionGroup`, the accent ring and fill are one
/// plate that slides from the old swatch to the new one, the way a segmented control's
/// thumb does, instead of one ring fading out while another fades in two swatches away.
/// Every swatch keeps its own hairline and hover fill underneath the plate.
private struct SettingsSelectionChrome: ViewModifier {
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsSwatchHovering) private var hovering
    @Environment(\.settingsSelectionNamespace) private var namespace

    /// R2B3: 11, concentric with the r6 well the swatch body draws inside 5pt of padding.
    /// At r8 the ring was less round than the well it framed — the loudest "feels off"
    /// there is — and fixing it here fixes all three pickers at once.
    private static let cornerRadius: CGFloat = 11

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    }

    /// R2M6: a selected swatch *deepens* its own accent fill rather than stacking a neutral
    /// hover wash on top of it, so hover reads as one surface responding, not two.
    private var plateFill: Color {
        Color.accentColor.opacity(hovering ? 0.12 : 0.08)
    }

    /// The per-swatch layer. With a travelling plate, a selected swatch's own layer goes
    /// quiet (clear fill, hairline) because the plate above it draws the selected state.
    private var fillColor: Color {
        if isSelected { return namespace == nil ? plateFill : .clear }
        return hovering ? Color.primary.opacity(0.05) : .clear
    }

    private var borderColor: Color {
        if isSelected && namespace == nil { return .accentColor }
        return hovering && !isSelected
            ? Color.primary.opacity(0.14)
            : ClaudeSetupStyle.hairline(dark: colorScheme == .dark)
    }

    private var selectionAnimation: Animation? {
        // R2B4: `settle`, not `pressDown`. Selection is a settled state change; the 100ms
        // press curve belongs to the press that caused it, which the style above owns.
        // S2A: the in-place ring is colour work, so Reduce Motion keeps the cross-fade;
        // the travelling plate only exists when motion is allowed.
        namespace == nil
            ? HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)
            : HeadroomMotion.selectionTravel
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(shape)
            // Later backgrounds draw *behind* earlier ones: the plate sits over the swatch's
            // own layer, and both sit under the content (which keeps 5pt clear of the edge).
            .background { travellingPlate }
            .background {
                shape
                    .fill(fillColor)
                    .overlay {
                        shape.strokeBorder(borderColor, lineWidth: isSelected && namespace == nil ? 2 : 1)
                    }
            }
            .animation(selectionAnimation, value: isSelected)
            // S3A: hover in fast, out slow — the fill is there when the pointer arrives and
            // lingers a beat when it leaves.
            .animation(
                HeadroomMotion.resolved(
                    hovering ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut,
                    .crossfade,
                    reduceMotion: reduceMotion
                ),
                value: hovering
            )
    }

    @ViewBuilder private var travellingPlate: some View {
        if isSelected, let namespace {
            shape
                .fill(plateFill)
                .overlay { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
                .matchedGeometryEffect(id: "selectionPlate", in: namespace)
        }
    }
}

extension View {
    /// The selected/unselected chrome for a Settings swatch or thumbnail (PB13).
    func selectionChrome(isSelected: Bool) -> some View {
        modifier(SettingsSelectionChrome(isSelected: isSelected))
    }

    /// SM1: marks one picker row — the grid holding its swatches — so the selection plate
    /// slides between them. `value` is the row's current selection.
    func settingsSelectionGroup<Value: Equatable>(value: Value) -> some View {
        modifier(SettingsSelectionGroup(value: value))
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

    /// R2M7/S2A: the same reveal, split by kind. The rise and the blur are movement and drop
    /// under Reduce Motion; the fade is a cross-fade and keeps its timing. A `.animation`
    /// scope cannot split a transition from the layout change beside it, so the split has to
    /// live in the transition itself — which is why the API-spend reveal could only choose
    /// between "no fade at all" and "a 4pt rise under Reduce Motion" before.
    ///
    /// RM1: under Reduce Motion the fade carries its own `settle`, so the scope that inserts
    /// it can resolve as `.movement` and let the height snap.
    static func settingsReveal(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: true) : .settingsReveal
    }

    /// SM2: the Settings pane switch. The incoming pane fades in out of a slight blur on
    /// `paneIn`; the outgoing one fades out fast on `paneOut`, so the two never sit on screen
    /// at half opacity together. S2A: the blur is movement and drops under Reduce Motion;
    /// both fades keep their timing.
    static func settingsPane(reduceMotion: Bool) -> AnyTransition {
        let insertion: AnyTransition = reduceMotion
            ? .opacity
            : .modifier(
                active: SettingsPaneTransitionModifier(active: true),
                identity: SettingsPaneTransitionModifier(active: false)
            )
        return .asymmetric(
            insertion: insertion.animation(HeadroomMotion.paneIn),
            removal: AnyTransition.opacity.animation(HeadroomMotion.paneOut)
        )
    }
}

private struct SettingsPaneTransitionModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 3 : 0)
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
    ///
    /// R2C9: so is the radius, for the same reason. A fixed r7 well held an r10 provider card
    /// at 16/14pt padding, r20 widget tiles at 9/10, and an r6 menu-bar plate at 9 — the
    /// first two inner-rounder-than-outer, which is the loudest "feels off" in concentric
    /// geometry and sat at the top of the Appearance pane. Each caller passes the radius its
    /// own content and padding make concentric.
    func settingsPreviewWell(
        dark: Bool,
        verticalPadding: CGFloat,
        horizontalPadding: CGFloat = 9,
        cornerRadius: CGFloat
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                ProviderStyle.recessedWell(dark: dark),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
