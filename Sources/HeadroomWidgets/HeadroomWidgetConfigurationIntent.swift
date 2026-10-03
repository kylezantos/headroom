import AppIntents
#if canImport(HeadroomCore)
import HeadroomCore
#endif
import WidgetKit

// KTD1/KTD2 (2026-10-02 widget-styles plan): the Edit Widget configuration shared by the
// macOS and iPhone widget extensions (project.yml adds this file to HeadroomIOSWidgets by
// path). It is compiled into the extensions only — never Core or the Mac app — and maps onto
// the Foundation-only `WidgetLayoutStyle` / `WidgetColorMode`, which own the defaults and the
// unknown-value fallback. Metadata is `static let` because Swift 6 rejects mutable statics.

enum HeadroomWidgetStyleOption: String, AppEnum {
    case nestedMeter
    case vesselHero
    case tightestFirst
    case liquidLevel

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [HeadroomWidgetStyleOption: DisplayRepresentation] = [
        .nestedMeter: "Nested Meter",
        .vesselHero: "Vessel Hero",
        .tightestFirst: "Tightest First",
        .liquidLevel: "Liquid Level",
    ]

    var layoutStyle: WidgetLayoutStyle { WidgetLayoutStyle(storedValue: rawValue) }
}

enum HeadroomWidgetColorOption: String, AppEnum {
    case solid
    case event

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Color"
    static let caseDisplayRepresentations: [HeadroomWidgetColorOption: DisplayRepresentation] = [
        .solid: "Always colored",
        .event: "Only when low",
    ]

    var colorMode: WidgetColorMode { WidgetColorMode(storedValue: rawValue) }
}

struct HeadroomWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Headroom"
    static let description = IntentDescription("Choose how this widget shows your usage.")

    @Parameter(title: "Style", default: .nestedMeter)
    var style: HeadroomWidgetStyleOption

    @Parameter(
        title: "Color",
        description: "Only when low keeps healthy meters neutral until a limit runs low.",
        default: .solid
    )
    var color: HeadroomWidgetColorOption

    init() {}

    var layoutStyle: WidgetLayoutStyle { style.layoutStyle }
    var colorMode: WidgetColorMode { color.colorMode }
}
