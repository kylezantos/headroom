import SwiftUI
import HeadroomCore

/// One labeled usage bar showing percent remaining + reset countdown (U7, UI-01/04).
/// The fill color follows the window's static severity band (green → amber → red) so
/// "how much is left" reads before any number does; the percentage is promoted and
/// labeled "left" to kill the used-vs-remaining ambiguity. The bar carries an
/// `accessibilityValue` so VoiceOver reads the remaining percent — a custom bar is
/// invisible to VoiceOver otherwise (design review). `dimmed` renders the stale
/// treatment: the fill desaturates but the number stays fully legible, because a stale
/// last-known value is exactly what the user opened the app to see. The countdown ticks
/// per-minute via the caller's TimelineView `now`, so it never reads frozen.
struct UsageBarView: View {
    let window: UsageWindow
    let now: Date
    var dimmed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var pct: Int { Int(window.percentRemaining.rounded()) }
    private var fraction: Double { min(1, max(0, window.percentRemaining / 100)) }
    private var severity: UsageSeverity { window.severity }

    /// One spring drives the fill width, its color band, and the rolling percentage so the
    /// bar and its number describe the same value in lockstep. A no-overshoot spring reads
    /// as physical and is distance-aware — a 3% change settles faster than a 40% one — where
    /// the old fixed 450ms `easeOut` felt both slow (Emil: keep UI motion under ~300ms) and
    /// uniform regardless of distance. Nil'd under Reduce Motion so the value snaps instead.
    private static let valueSpring = Animation.spring(response: 0.3, dampingFraction: 0.9)
    private var valueAnimation: Animation? { reduceMotion ? nil : Self.valueSpring }

    /// Desaturated grey while stale; the live severity color otherwise.
    private var fillColor: Color {
        dimmed ? Color.secondary.opacity(0.55) : ProviderStyle.severityColor(for: severity, scheme: scheme)
    }

    /// Prefer the provider's verbatim reset text (Claude) over a computed countdown
    /// (Codex). Capitalized "Resets in …" so the computed Codex text matches Claude's
    /// verbatim "Resets …" casing in the same window, and the past-reset edge reads as
    /// "Resets now" instead of the nonsensical "resets in resets now".
    private var resetText: String {
        if let label = window.resetLabel { return label }
        if window.resetsAt <= now { return "Resets now" }
        return "Resets in \(Countdown.string(to: window.resetsAt, now: now))"
    }

    /// Standard windows carry the reset inline beside the label (2 lines total); the
    /// long `.other` model labels (Codex's "GPT-5.3-Codex-Spark …") would overflow, so
    /// theirs drops to its own left-aligned line under the bar.
    private var resetInline: Bool {
        switch window.kind {
        case .fiveHour, .weekly: return true
        case .other: return false
        }
    }

    private func fillWidth(in availableWidth: Double) -> Double {
        guard fraction > 0 else { return 0 }
        return max(4, availableWidth * fraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row recipe aligned with the large widget's meter (Jul 2026): 13pt medium
            // label + "· reset" in the shared WCAG-tuned widget grays (system .tertiary
            // sat at ~2.3:1 on the dark tile). Percent stays 18pt medium — the popover's
            // larger canvas earns the bigger numeral; weight ladder 400/500/600/700.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if resetInline {
                    Text("· \(resetText)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer(minLength: 6)
                if !dimmed, severity == .critical {
                    lowChip
                }
                Text("\(pct)%")
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(valueAnimation, value: pct)
                Text("left")
                    .font(.system(size: 11))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: fillWidth(in: geo.size.width))
                        // Width and its severity color ride one spring — a band change only
                        // ever happens when the fraction changes, so both animate together in
                        // the same transaction. The visible payoff of a refresh cycle; not a
                        // loop. (Stale desaturation rides the card's freshness cross-fade.)
                        .animation(valueAnimation, value: fraction)
                }
            }
            .frame(height: 8)
            if !resetInline {
                Text(resetText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage")
        .accessibilityValue("\(pct) percent remaining, \(resetText)")
    }

    /// Small static "Low" flag shown only for the critical band (≤15% left) — a word
    /// earns its place when you're nearly out, not across the whole amber range where
    /// the color alone is the right amount of signal.
    private var lowChip: some View {
        Text("Low")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(ProviderStyle.severityColor(for: severity, scheme: scheme))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(ProviderStyle.severityColor(for: severity, scheme: scheme).opacity(0.16), in: Capsule())
    }

    private var label: String {
        switch window.kind {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .other(let raw): return Self.normalizeOther(raw)
        }
    }

    /// Presentation-only tidy of Codex's constructed window labels so their period suffix
    /// matches the "5-hour"/"Weekly" windows shown above them. The model name is left
    /// verbatim (KTD6) — only the "5h"/"weekly" suffix the provider appends is normalized,
    /// with a middot setting it off from the model. Non-matching labels (Claude's
    /// "Weekly (Fable)") pass through untouched.
    private static func normalizeOther(_ raw: String) -> String {
        if raw.hasSuffix(" weekly") { return "\(raw.dropLast(7)) · Weekly" }
        if raw.hasSuffix(" 5h") { return "\(raw.dropLast(3)) · 5-hour" }
        return raw
    }
}
