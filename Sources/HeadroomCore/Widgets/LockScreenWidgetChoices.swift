import Foundation

/// KTD2 (2026-10-04 Lock Screen plan): separate from the home families, which are
/// iterated exhaustively by the existing home render sweep.
public enum LockScreenWidgetFamily: String, CaseIterable, Sendable, Codable {
    case circle, rectangle, inline
}

/// R7/KTD2: identifiers persist with placed widgets. A pinned choice never falls
/// back to another provider when that provider is absent from the envelope.
public enum LockScreenProviderChoice: String, CaseIterable, Sendable, Codable {
    case automatic, claude, codex, grok, cursor

    public init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .automatic
    }

    public var providerID: ProviderID? {
        switch self {
        case .automatic: nil
        case .claude: .claude
        case .codex: .codex
        case .grok: .grok
        case .cursor: .cursor
        }
    }
}

public enum LockScreenWidgetChoices {
    /// R5/KTD2: Liquid Level is the Lock Screen default; the home default stays Nested Meter.
    public static let defaultStyle: WidgetLayoutStyle = .liquidLevel

    public static func style(storedValue: String?) -> WidgetLayoutStyle {
        storedValue.flatMap(WidgetLayoutStyle.init(rawValue:)) ?? defaultStyle
    }

    /// KTD2: nil intent parameters on ad-hoc builds get the same defaults as stored values.
    public static func style(_ value: WidgetLayoutStyle?) -> WidgetLayoutStyle { value ?? defaultStyle }
    public static func provider(_ value: LockScreenProviderChoice?) -> LockScreenProviderChoice { value ?? .automatic }
}
