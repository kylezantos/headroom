import SwiftUI

/// R30 / KTD21: Explore Demo, and while in demo a picker over every bundled variant so a
/// reviewer can see each state. Visible in Release: App Review uses it. Choosing a variant
/// writes only the App Group demo variant, never iCloud or a cache.
struct DemoSection: View {
    let isDemoMode: Bool
    let canExitDemo: Bool
    let demoWidgetUnavailable: Bool
    @Binding var variant: CompanionDemoVariant
    let onEnterDemo: () -> Void
    let onExitDemo: () -> Void

    var body: some View {
        Section {
            if isDemoMode {
                Label(
                    demoWidgetUnavailable
                        ? PhoneSettingsCopy.demoActiveWidgetsUnavailable
                        : PhoneSettingsCopy.demoActive,
                    systemImage: "sparkles"
                )
                .font(.footnote)
                Picker("Sample state", selection: $variant) {
                    ForEach(CompanionDemoVariant.allCases) { variant in
                        Text(variant.title).tag(variant)
                    }
                }
                .accessibilityIdentifier("headroom.demo.variant")
                if canExitDemo {
                    Button("Exit Demo", role: .destructive, action: onExitDemo)
                        .accessibilityIdentifier("headroom.demo.exit")
                }
            } else {
                Button("Explore Demo", action: onEnterDemo)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("headroom.demo.enter.settings")
            }
        } header: {
            Text("Demo")
        } footer: {
            if isDemoMode {
                Text(PhoneSettingsCopy.demoVariantFooter)
            }
        }
    }
}
