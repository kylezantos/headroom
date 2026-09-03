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
