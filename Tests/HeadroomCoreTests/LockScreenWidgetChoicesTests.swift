import Testing
@testable import HeadroomCore

struct LockScreenWidgetChoicesTests {
    @Test func lockScreenDefaultsDoNotChangeHomeDefaults() {
        for value in [nil, "", "unknown"] as [String?] {
            #expect(LockScreenWidgetChoices.style(storedValue: value) == .liquidLevel)
            #expect(LockScreenProviderChoice(storedValue: value) == .automatic)
        }
        #expect(LockScreenWidgetChoices.style(nil) == .liquidLevel)
        #expect(LockScreenWidgetChoices.provider(nil) == .automatic)
        #expect(WidgetLayoutStyle.default == .nestedMeter)
    }

    @Test func choicesRoundTripWithStableIdentifiers() {
        #expect(LockScreenWidgetFamily.allCases == [.circle, .rectangle, .inline])
        // Stored with placed widgets: append only, never reorder or rename.
        #expect(LockScreenProviderChoice.allCases.map(\.rawValue) == ["automatic", "claude", "codex", "grok", "cursor", "copilot", "opencode", "antigravity"])
        #expect(LockScreenProviderChoice(storedValue: "antigravity") == .antigravity)
        #expect(LockScreenProviderChoice.antigravity.providerID == .antigravity)
        #expect(LockScreenProviderChoice(storedValue: "opencode") == .opencode)
        for choice in LockScreenProviderChoice.allCases {
            #expect(LockScreenProviderChoice(storedValue: choice.rawValue) == choice)
            if let id = choice.providerID { #expect(choice.rawValue == id.raw) }
        }
        for style in WidgetLayoutStyle.allCases {
            #expect(LockScreenWidgetChoices.style(storedValue: style.rawValue) == style)
        }
    }
}
