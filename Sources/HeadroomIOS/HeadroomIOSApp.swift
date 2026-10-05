import SwiftUI
import WidgetKit

@main
struct HeadroomIOSApp: App {
    /// U8 step 8: the UIKit delegate hook. U16 fills `HeadroomIOSAppDelegate` (remote
    /// notification registration for CloudKit reminders); today it does nothing.
    @UIApplicationDelegateAdaptor(HeadroomIOSAppDelegate.self) private var appDelegate
    @AppStorage("headroom.ios.appearance") private var appearanceRawValue = AppearanceSetting.system.rawValue

    var body: some Scene {
        WindowGroup {
            IOSCompanionView(appearance: appearanceBinding)
                .preferredColorScheme(appearanceBinding.wrappedValue.colorScheme)
                // U8 (U9-A, G6): one neutral tint for the whole app — no system blue anywhere
                // and no AccentColor asset (the catalog is shared with the Mac app).
                .tint(PhoneControlStyle.tint)
        }
    }

    private var appearanceBinding: Binding<AppearanceSetting> {
        Binding {
            AppearanceSetting(rawValue: appearanceRawValue) ?? .system
        } set: { newValue in
            appearanceRawValue = newValue.rawValue
        }
    }
}
