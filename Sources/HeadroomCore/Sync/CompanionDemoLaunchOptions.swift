import Foundation

/// The screen a screenshot launch opens on (`--demo-screen`, KTD21).
public enum CompanionDemoScreen: String, CaseIterable, Sendable {
    case usage, settings, widgets

    public static let `default`: Self = .usage
}

/// The phone's demo launch arguments (KTD21): `--demo` turns on a screenshot launch,
/// `--demo-variant <name>` picks a `CompanionDemoVariant` and `--demo-screen
/// <usage|settings|widgets>` the opening screen. Parsed from injected arguments so hosts and
/// tests share one parser. Launch options are in-memory only: they never write the demo
/// store, the caches or iCloud.
public struct CompanionDemoLaunchOptions: Equatable, Sendable {
    public static let demoFlag = "--demo"
    public static let variantFlag = "--demo-variant"
    public static let screenFlag = "--demo-screen"

    /// A `--demo` launch is a screenshot launch: hosts hide the demo banner and the widget
    /// DEMO badge, use a fixture stamp and let motion settle (KTD21). Explore Demo, the App
    /// Group switch, is not a launch option and keeps its neutral banner.
    public let isDemoLaunch: Bool
    /// The requested variant: nil when `--demo-variant` is absent, so Explore Demo's stored
    /// choice applies; an unknown or missing value falls back to the default (U7).
    public let variant: CompanionDemoVariant?
    public let screen: CompanionDemoScreen

    public init(isDemoLaunch: Bool, variant: CompanionDemoVariant?, screen: CompanionDemoScreen) {
        self.isDemoLaunch = isDemoLaunch
        self.variant = variant
        self.screen = screen
    }

    public static var current: Self { parse(CommandLine.arguments) }

    public static func parse(_ arguments: [String]) -> Self {
        let variant: CompanionDemoVariant? =
            arguments.contains(variantFlag)
            ? CompanionDemoVariant.resolving(value(after: variantFlag, in: arguments)) : nil
        return Self(
            isDemoLaunch: arguments.contains(demoFlag),
            variant: variant,
            screen: value(after: screenFlag, in: arguments).flatMap(CompanionDemoScreen.init(rawValue:))
                ?? .default)
    }

    /// The variant to show: the launch argument wins over Explore Demo's stored choice.
    public func resolvedVariant(stored: CompanionDemoVariant) -> CompanionDemoVariant {
        variant ?? stored
    }

    /// The token after `flag`, unless it is absent or another flag.
    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.lastIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        let token = arguments[index + 1]
        return token.hasPrefix("-") ? nil : token
    }
}
