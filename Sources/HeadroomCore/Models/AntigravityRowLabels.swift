import Foundation

/// The stored labels of Antigravity's four rows ("Gemini 5h", "Gemini weekly", "Other 5h",
/// "Other weekly") and their compact short forms, in one platform-neutral place. The provider
/// builds the stored labels, and the compact recipe reads the pool and short form back off them,
/// so each spelling lives only here.
enum AntigravityRowLabels {
    enum Pool: String, CaseIterable {
        case gemini = "Gemini"
        case other = "Other"
    }

    enum Window: String, CaseIterable {
        case fiveHour = "5h"
        case weekly = "weekly"

        var shortName: String {
            switch self {
            case .fiveHour: "5h"
            case .weekly: "wk"
            }
        }
    }

    static func stored(_ pool: Pool, _ window: Window) -> String {
        "\(pool.rawValue) \(window.rawValue)"
    }

    static func short(_ pool: Pool, _ window: Window) -> String {
        "\(pool.rawValue) \(window.shortName)"
    }

    /// The pool and window a stored label names, or nil for any other label.
    static func parse(_ label: String) -> (pool: Pool, window: Window)? {
        for pool in Pool.allCases {
            for window in Window.allCases where label == stored(pool, window) {
                return (pool, window)
            }
        }
        return nil
    }
}
