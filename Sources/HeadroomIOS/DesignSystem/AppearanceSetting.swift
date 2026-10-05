import SwiftUI

/// U12: the phone's theme is Core's `AppearancePreference`, the Mac's own System / Light / Dark
/// enum, so the two can't drift. Theme stays a phone-only choice and never syncs (S3); the
/// stored raw values ("system", "light", "dark") are unchanged, so existing choices survive.
/// The alias keeps the app's call sites as they are.
typealias AppearanceSetting = AppearancePreference

extension AppearancePreference {
    var title: String { label }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
