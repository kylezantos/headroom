import AppIntents

// KTD18: the provider parameter of the read-only Siri and Shortcuts answers. Named apart
// from the widget extensions' `HeadroomWidget…Option` enums: each bundle carries its own
// App Intents metadata. All five providers, every account (provider parity).

enum UsageProviderOption: String, AppEnum {
    case claude
    case codex
    case grok
    case cursor
    case copilot

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static let caseDisplayRepresentations: [UsageProviderOption: DisplayRepresentation] = [
        .claude: DisplayRepresentation(title: "Claude", synonyms: ["Claude Code"]),
        .codex: DisplayRepresentation(title: "Codex", synonyms: ["ChatGPT"]),
        .grok: DisplayRepresentation(title: "Grok", synonyms: ["Grok Build"]),
        .cursor: DisplayRepresentation(title: "Cursor", synonyms: ["Cursor Agent"]),
        .copilot: DisplayRepresentation(title: "Copilot", synonyms: ["GitHub Copilot"]),
    ]

    var providerID: ProviderID {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .grok: .grok
        case .cursor: .cursor
        case .copilot: .copilot
        }
    }
}
