import SwiftUI
import WidgetKit

@main
struct HeadroomIOSApp: App {
    @AppStorage("headroom.ios.appearance") private var appearanceRawValue = AppearanceSetting.system.rawValue

    var body: some Scene {
        WindowGroup {
            IOSCompanionView(appearance: appearanceBinding)
                .demoWidgetWall()
                .preferredColorScheme(appearanceBinding.wrappedValue.colorScheme)
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
