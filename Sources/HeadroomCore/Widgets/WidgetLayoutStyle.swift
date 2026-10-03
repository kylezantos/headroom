import Foundation

/// R7/KTD2 (2026-10-02 widget-styles plan): the four widget styles a user picks per widget
/// in Edit Widget. Plain Foundation so `swift test` covers it and the iOS targets compile it
/// with the rest of `Core/Widgets`; the App Intent `AppEnum` that surfaces it lives only in
/// the widget extensions and maps onto these raw values.
///
/// Raw values are persisted by WidgetKit inside each placed widget's configuration, so they
/// are stable identifiers — never rename one.
public enum WidgetLayoutStyle: String, CaseIterable, Sendable, Codable {
    case nestedMeter
    case vesselHero
    case tightestFirst
    case liquidLevel

    /// Key Decisions: new and already-placed widgets start on Nested Meter, which shows every
    /// window, so nobody loses information on update.
    public static let `default`: WidgetLayoutStyle = .nestedMeter

    /// KTD2: an unknown or missing value (a newer build's style read by an older one, or an
    /// ad-hoc-signed build where linkd delivers no parameter) renders the default rather than
    /// blanking the widget.
    public init(storedValue: String?) {
        self = storedValue.flatMap(WidgetLayoutStyle.init(rawValue:)) ?? .default
    }

    public var displayName: String {
        switch self {
        case .nestedMeter: "Nested Meter"
        case .vesselHero: "Vessel Hero"
        case .tightestFirst: "Tightest First"
        case .liquidLevel: "Liquid Level"
        }
    }
}

/// R7/KTD5: the per-widget color mode. It mirrors the popover's `GaugeFill` choices of the
/// same names (`solid` = "Always colored", `event` = "Only when low") but is chosen per widget
/// in Edit Widget — the widget cannot read the popover's meter setting.
public enum WidgetColorMode: String, CaseIterable, Sendable, Codable {
    case solid
    case event

    /// Key Decisions: Always colored is the default.
    public static let `default`: WidgetColorMode = .solid

    public init(storedValue: String?) {
        self = storedValue.flatMap(WidgetColorMode.init(rawValue:)) ?? .default
    }

    public var displayName: String {
        switch self {
        case .solid: "Always colored"
        case .event: "Only when low"
        }
    }
}
