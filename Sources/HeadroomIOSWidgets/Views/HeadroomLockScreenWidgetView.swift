import SwiftUI
import WidgetKit

/// U2 device spike only: U6 replaces this text scaffold with the tested Core recipe bodies.
struct HeadroomLockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeadroomLockScreenWidgetEntry

    var body: some View {
        Group {
            if let lockScreenFamily {
                scaffold(for: lockScreenFamily)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "headroom://usage"))
        .privacySensitive()
        .dynamicTypeSize(...labelDynamicTypeCap)
    }

    private var labelDynamicTypeCap: DynamicTypeSize {
        switch LockScreenWidgetTokens.labelDynamicTypeCap {
        case .xLarge: .xLarge
        }
    }

    /// KTD2: unknown WidgetKit sizes stay empty, never route into a home family.
    private var lockScreenFamily: LockScreenWidgetFamily? {
        switch family {
        case .accessoryCircular: .circle
        case .accessoryRectangular: .rectangle
        case .accessoryInline: .inline
        default: nil
        }
    }

    @ViewBuilder
    private func scaffold(for family: LockScreenWidgetFamily) -> some View {
        switch family {
        case .circle:
            VStack(spacing: 2) {
                Text(providerName).font(.caption2)
                Text(number).font(.system(size: LockScreenWidgetTokens.liquidNumeral, weight: .semibold))
                Text(isDemo ? "Demo" : caption).font(.system(size: LockScreenWidgetTokens.captionSize))
            }
            .lineLimit(1)
        case .rectangle:
            HStack(spacing: 6) {
                // U2 diagnostic: observe whether system privacy redaction also removes a
                // drawn fill. Final R16 behavior is implemented after the device answer.
                if !entry.isPlaceholder {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: LockScreenWidgetTokens.secondaryInk))
                        .frame(width: 12, height: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(isDemo ? "Demo · " : "")\(providerName)")
                    Text("\(caption) · \(number)")
                }
                .font(.caption)
                .lineLimit(1)
            }
        case .inline:
            if entry.isPlaceholder {
                Text("Headroom · —")
            } else {
                // KTD9/U2: one custom template image next to system-styled text. Kyle's
                // device answer is the gate before generating the real stepped images.
                Label {
                    Text("\(isDemo ? "Demo · " : "")\(providerName) \(caption) \(number)")
                } icon: {
                    Image("LockScreenInlineSpike")
                        .renderingMode(.template)
                }
            }
        }
    }

    private var envelope: WidgetSnapshotEnvelope? {
        switch entry.state {
        case .content(let envelope), .demo(let envelope): envelope
        default: nil
        }
    }

    private var isDemo: Bool {
        if case .demo = entry.state { true } else { false }
    }

    private var provider: WidgetProviderSummary? {
        guard let envelope else { return nil }
        if let pinned = entry.providerChoice.providerID {
            return envelope.providers.first { $0.id == pinned.raw }
        }
        return envelope.widgetProviders.first
    }

    private var providerName: String {
        if entry.isPlaceholder { return "Headroom" }
        return provider?.displayName ?? entry.providerChoice.providerID?.displayName ?? "Headroom"
    }

    private var window: WidgetWindowSummary? {
        provider?.primarySubscriptionWindow ?? provider?.windows.first
    }

    private var number: String {
        entry.isPlaceholder ? "—" : WidgetWindowText.percent(window)
    }

    private var caption: String {
        if entry.isPlaceholder { return "—" }
        if let window { return window.label }
        if let provider {
            return provider.freshness == .pending ? "Waiting" : "Sign in"
        }
        if envelope != nil { return "Off" }
        switch entry.state {
        case .disabled: return "Sync is off"
        case .setupNeeded: return "iCloud is off"
        case .waitingForMac: return "Waiting for Mac"
        case .corrupt: return "Can't read data"
        case .incompatibleSchema: return "Update Headroom"
        case .demo, .content: return "Off"
        }
    }
}
