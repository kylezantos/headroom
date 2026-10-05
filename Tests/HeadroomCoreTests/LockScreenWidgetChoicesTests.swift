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
        #expect(LockScreenProviderChoice.allCases.map(\.rawValue) == ["automatic", "claude", "codex", "grok", "cursor"])
        for choice in LockScreenProviderChoice.allCases {
            #expect(LockScreenProviderChoice(storedValue: choice.rawValue) == choice)
            if let id = choice.providerID { #expect(choice.rawValue == id.raw) }
        }
        for style in WidgetLayoutStyle.allCases {
            #expect(LockScreenWidgetChoices.style(storedValue: style.rawValue) == style)
        }
    }
}
