import SwiftUI
import AppKit
import HeadroomCore

/// The always-visible menu bar content (R5, UI-03): the compact vessel glyph, with the
/// weekly remaining percent optionally shown beside it. The glyph is tinted by weekly
/// *severity* (healthy → amber → red), not by brand color, so the menu bar means "how
/// close is my weekly allotment to running out" at a glance; a small warning dot appears
/// when a provider needs re-auth, so a dead provider isn't silently invisible. Static
/// only — no pulsing (user's standing rule).
struct MenuBarLabel: View {
    let meters: [MenuBarMeter]
    let showsPercentage: Bool

    var body: some View {
        let result = MenuBarLabelRenderer.render(meters: meters, showsPercentage: showsPercentage)
        Image(nsImage: result.image)
            .accessibilityLabel(result.accessibilityLabel)
            .help(result.tooltip)
    }
}

@MainActor
struct MenuBarLabelRenderResult {
    let image: NSImage
    let accessibilityLabel: String
    let tooltip: String
    let regions: [MenuBarLabelTooltipRegion]
}

struct MenuBarLabelTooltipRegion {
    let rect: NSRect
    let tooltip: String
}

@MainActor
enum MenuBarLabelRenderer {
    private static let height: CGFloat = 18
    private static let vesselWidth: CGFloat = 11
    private static let vesselTextGap: CGFloat = 7
    private static let meterGapWithPercentage: CGFloat = 16
    private static let meterGapIconOnly: CGFloat = 8
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)

    static func render(meters: [MenuBarMeter], showsPercentage: Bool) -> MenuBarLabelRenderResult {
        let visibleMeters = meters.isEmpty ? [MenuBarMeter(summary: .neutral, fill: nil)] : meters
        let meterGap = showsPercentage ? meterGapWithPercentage : meterGapIconOnly
        let measured = visibleMeters.map { meter -> (meter: MenuBarMeter, textSize: NSSize?) in
            guard showsPercentage, !meter.summary.isNeutral else { return (meter, nil) }
            return (meter, textSize(for: meter.summary.text))
        }
        let width = measured.reduce(CGFloat.zero) { total, item in
            let textWidth = item.textSize.map { vesselTextGap + ceil($0.width) } ?? 0
            let gap = total > 0 ? meterGap : 0
            return total + gap + vesselWidth + textWidth
        }
        let regions = tooltipRegions(for: measured, meterGap: meterGap, imageWidth: max(vesselWidth, ceil(width)))
        let image = NSImage(size: NSSize(width: max(vesselWidth, ceil(width)), height: height), flipped: false) { bounds in
            var x = bounds.minX
            for item in measured {
                if x > bounds.minX { x += meterGap }
                let vessel = VesselGlyph.menuBarImage(
                    fill: item.meter.fill,
                    severity: item.meter.summary.severity,
                    isNeutral: item.meter.summary.isNeutral
                )
                vessel.draw(in: NSRect(x: x, y: 0, width: vesselWidth, height: height))
                if item.meter.summary.needsAttention {
                    NSColor.systemRed.setFill()
                    NSBezierPath(ovalIn: NSRect(x: x + vesselWidth - 2, y: height - 5, width: 5, height: 5)).fill()
                }
                x += vesselWidth
                if let textSize = item.textSize {
                    x += vesselTextGap
                    let textHeight = ceil(textSize.height)
                    let rect = NSRect(
                        x: x,
                        y: (height - textHeight) / 2,
                        width: ceil(textSize.width),
                        height: textHeight
                    )
                    item.meter.summary.text.draw(in: rect, withAttributes: [
                        .font: font,
                        .foregroundColor: textColor(for: item.meter.summary)
                    ])
                    x += ceil(textSize.width)
                }
            }
            return true
        }
        image.isTemplate = false
        let accessibilityLabel = accessibilityLabel(for: visibleMeters)
        return MenuBarLabelRenderResult(
            image: image,
            accessibilityLabel: accessibilityLabel,
            tooltip: accessibilityLabel,
            regions: regions
        )
    }

    private static func textSize(for text: String) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func tooltipRegions(
        for measured: [(meter: MenuBarMeter, textSize: NSSize?)],
        meterGap: CGFloat,
        imageWidth: CGFloat
    ) -> [MenuBarLabelTooltipRegion] {
        guard !measured.isEmpty else { return [] }
        var x: CGFloat = 0
        return measured.map { item in
            if x > 0 { x += meterGap }
            let start = x
            x += vesselWidth
            if let textSize = item.textSize {
                x += vesselTextGap + ceil(textSize.width)
            }
            return MenuBarLabelTooltipRegion(
                rect: NSRect(x: start, y: 0, width: min(imageWidth - start, x - start), height: height),
                tooltip: tooltip(for: item.meter.summary)
            )
        }
    }

    private static func accessibilityLabel(for meters: [MenuBarMeter]) -> String {
        if meters.count == 1, let summary = meters.first?.summary, summary.needsAttention, summary.isNeutral {
            return "AI usage — a provider needs sign-in"
        }
        let parts = meters.compactMap { meter -> String? in
            guard meter.summary.detail != nil else { return nil }
            return tooltip(for: meter.summary)
        }
        return parts.isEmpty ? "AI usage" : parts.joined(separator: "; ")
    }

    private static func tooltip(for summary: MenuBarSummary) -> String {
        guard let detail = summary.detail else {
            return summary.needsAttention ? "AI usage — a provider needs sign-in" : "AI usage"
        }
        let base = summary.isNeutral ? detail : "\(detail), \(summary.text) remaining"
        return summary.needsAttention ? "\(base), needs sign-in" : base
    }

    private static func textColor(for summary: MenuBarSummary) -> NSColor {
        if !summary.isNeutral {
            return severityColor(for: summary.severity)
        }
        return summary.needsAttention ? severityColor(for: .critical) : .labelColor
    }

    private static func severityColor(for severity: UsageSeverity) -> NSColor {
        // Dynamic so the status-item text re-resolves with the menu bar's own appearance
        // (which follows the wallpaper/system, not the app), picking the scheme-tuned
        // value from the shared severity palette.
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = HeadroomSeverityColorValues.color(for: severity, dark: dark)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
        }
    }
}
