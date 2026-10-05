import AppIntents
import SwiftUI
import WidgetKit

/// KTD2: exhaustive mappings in both directions make additions on either side fail to compile.
enum HeadroomLockScreenStyleOption: String, AppEnum {
    case nestedMeter, vesselHero, tightestFirst, liquidLevel

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .nestedMeter: "Nested Meter", .vesselHero: "Vessel Hero",
        .tightestFirst: "Tightest First", .liquidLevel: "Liquid Level",
    ]

    var layoutStyle: WidgetLayoutStyle {
        switch self {
        case .nestedMeter: .nestedMeter
        case .vesselHero: .vesselHero
        case .tightestFirst: .tightestFirst
        case .liquidLevel: .liquidLevel
        }
    }

    init(style: WidgetLayoutStyle) {
        switch style {
        case .nestedMeter: self = .nestedMeter
        case .vesselHero: self = .vesselHero
        case .tightestFirst: self = .tightestFirst
        case .liquidLevel: self = .liquidLevel
        }
    }
}

enum HeadroomLockScreenProviderOption: String, AppEnum {
    case automatic, claude, codex, grok, cursor

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic", .claude: "Claude", .codex: "Codex",
        .grok: "Grok", .cursor: "Cursor",
    ]

    var providerChoice: LockScreenProviderChoice {
        switch self {
        case .automatic: .automatic
        case .claude: .claude
        case .codex: .codex
        case .grok: .grok
        case .cursor: .cursor
        }
    }

    init(choice: LockScreenProviderChoice) {
        switch choice {
        case .automatic: self = .automatic
        case .claude: self = .claude
        case .codex: self = .codex
        case .grok: self = .grok
        case .cursor: self = .cursor
        }
    }
}

struct HeadroomLockScreenConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Headroom Lock Screen"
    static let description = IntentDescription("Choose a style and provider for your Lock Screen.")

    // KTD2: optional parameters tolerate nil on ad-hoc builds without using the home default.
    @Parameter(title: "Style", default: .liquidLevel)
    var style: HeadroomLockScreenStyleOption?

    @Parameter(title: "Provider", default: .automatic)
    var provider: HeadroomLockScreenProviderOption?

    init() {
        style = HeadroomLockScreenStyleOption(style: LockScreenWidgetChoices.defaultStyle)
        provider = HeadroomLockScreenProviderOption(choice: .automatic)
    }

    var layoutStyle: WidgetLayoutStyle { LockScreenWidgetChoices.style(style?.layoutStyle) }
    var providerChoice: LockScreenProviderChoice { LockScreenWidgetChoices.provider(provider?.providerChoice) }
}

struct HeadroomLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: HeadroomIOSWidgetConfiguration.lockScreenKind,
            intent: HeadroomLockScreenConfigurationIntent.self,
            provider: HeadroomLockScreenTimelineProvider()
        ) { entry in
            HeadroomLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Headroom Lock Screen")
        .description("AI subscription headroom without unlocking.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
