import HeadroomCore
import SwiftUI

struct WidgetUsageMeter: View {
    let window: WidgetWindowSummary?
    let fallbackLabel: String
    var now: Date?
    var showsResetInline = false
    var compact = false
    // Large widget's tiles read as a premium surface, so their meters get bumped type
    // and a taller bar than the medium/small families.
    var prominent = false

    @Environment(\.colorScheme) private var scheme

    private var percentText: String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private var resetText: String? {
        guard let window, showsResetInline else { return nil }
        if let label = window.resetLabel { return label }
        guard let now else { return nil }
        if window.resetsAt <= now { return "Resets now" }
        return "Resets in \(Countdown.string(to: window.resetsAt, now: now))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 5 : (compact ? 2 : 4)) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window?.label ?? fallbackLabel)
                    .font(labelFont)
                    .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                if let resetText {
                    Text("· \(resetText)")
                        .font(resetFont)
                        .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 2)
                Text(percentText)
                    .font(percentFont)
                    .foregroundStyle(window == nil ? WidgetProviderStyle.secondaryText(scheme: scheme) : .primary)
            }
            WidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil,
                height: prominent ? 8 : 6
            )
        }
    }

    private var labelFont: Font {
        prominent ? .system(size: 13, weight: .medium) : (compact ? .system(size: 11, weight: .medium) : .caption)
    }

    private var resetFont: Font {
        prominent ? .system(size: 11).monospacedDigit() : .caption2.monospacedDigit()
    }

    private var percentFont: Font {
        // Medium (compact) percent reads at 14pt bold monospaced per the redesign (R3/KTD4).
        prominent ? .system(size: 16, weight: .bold).monospacedDigit() : (compact ? .system(size: 14, weight: .bold).monospacedDigit() : Font.caption.bold().monospacedDigit())
    }
}
