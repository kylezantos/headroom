import Foundation

/// One destination in the Settings sidebar (R1). The case order *is* the sidebar order
/// and `Group` *is* the section split, so the window never keeps a second hand-ordered
/// list that can drift from this one.
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case menuBar
    case widgets
    case accounts
    case apiSpend

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBar: "Menu Bar"
        case .widgets: "Widgets & iPhone"
        case .accounts: "Accounts"
        case .apiSpend: "API Spend"
        }
    }

    /// Height the detail column asks the window for, in points, at the default text size.
    ///
    /// The Sep 2026 rebuild pinned one Appearance-sized frame to every room, so General
    /// showed two rows above ~600pt of nothing. Each pane now declares its own budget and
    /// the window resizes when the destination changes.
    ///
    /// These are content *budgets*, not measurements of a live layout: every pane body is
    /// a `ScrollView`, so a pane that outgrows its budget (larger accessibility text, a
    /// fifth account, an extra provider) scrolls internally instead of growing the window.
    /// Appearance is deliberately the tallest and keeps the previous window height.
    public var preferredContentHeight: CGFloat {
        switch self {
        // Two rows and a help line, then Software updates in bundled builds. Well under
        // the floor, so it takes the floor.
        case .general: Self.minimumContentHeight
        // Specimen + Theme + Meter style + In-app display: the tallest room, and still
        // the window's default size.
        case .appearance: 812
        // Preview strip, percentage switch, Priority providers, then one preferred-window
        // row per registered provider (four today) with room for their fallback lines.
        case .menuBar: 540
        // Two switch rows, a checkbox, and their help text. Also under the floor.
        case .widgets: Self.minimumContentHeight
        // Four provider groups at one-to-two accounts each — the common shape. Deeper
        // catalogues (up to five accounts per provider) scroll inside the pane rather
        // than pushing the window past Appearance.
        case .accounts: 700
        // Three admin-key rows, each a title, a field, three lines of guidance and a
        // link, plus the trailing Period row.
        case .apiSpend: 640
        }
    }

    /// Floor under every pane. The sidebar column — identity block, two section headers,
    /// six destinations — occupies roughly 340pt, so a shorter window would scroll the
    /// sidebar and read like an alert rather than a settings room.
    public static let minimumContentHeight: CGFloat = 400

    public var group: Group {
        switch self {
        case .general, .appearance, .menuBar, .widgets: .preferences
        case .accounts, .apiSpend: .sources
        }
    }

    /// Sidebar section headers: what the app does (`Preferences`) versus where the
    /// numbers come from (`Sources`).
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case preferences
        case sources

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .preferences: "Preferences"
            case .sources: "Sources"
            }
        }

        /// Derived, never hand-listed, so the two groups always partition every pane.
        public var panes: [SettingsPane] { SettingsPane.allCases.filter { $0.group == self } }
    }
}
