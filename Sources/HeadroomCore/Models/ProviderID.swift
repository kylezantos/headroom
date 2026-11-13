/// Stable identifier for a usage provider. A struct rather than a closed enum so a
/// third provider can be added (R13) without changing this type.
public struct ProviderID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    public static let claude = ProviderID("claude")
    public static let codex = ProviderID("codex")
    public static let grok = ProviderID("grok")
    public static let cursor = ProviderID("cursor")
    public static let copilot = ProviderID("copilot")
    /// KTD13 (OpenCode plan): the raw value is stored and synced, so it never changes.
    public static let opencode = ProviderID("opencode")

    /// Human-facing provider name. Registry-backed so display strings never reach for a
    /// Claude-or-Codex ternary (KTD9 switch-site inventory). An unknown id falls back to a
    /// capitalized raw so a future provider still reads reasonably before it is named here.
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .opencode: "OpenCode"
        default: raw.capitalized
        }
    }

    public var description: String { raw }
}
