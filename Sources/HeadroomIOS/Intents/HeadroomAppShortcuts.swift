import AppIntents

// KTD18: the one App Shortcuts provider, in the iOS app target. Every phrase names the app
// (`\(.applicationName)` speaks the bundle display name, "Headroom"); the provider is the
// `UsageProviderOption` AppEnum. A phrase without the provider makes Siri ask for one.
// The phrases are mirrored in `AppShortcuts.xcstrings`: without that catalog the SSU
// training step has no corpus and Siri loses flexible phrase matching. Edit both together.

struct HeadroomAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UsageLeftIntent(),
            phrases: [
                "How much \(\.$provider) is left in \(.applicationName)",
                "How much \(\.$provider) do I have left in \(.applicationName)",
                "Check \(\.$provider) in \(.applicationName)",
                "\(.applicationName) \(\.$provider) usage",
                "How much is left in \(.applicationName)",
            ],
            shortTitle: "Usage Left",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
    }
}
