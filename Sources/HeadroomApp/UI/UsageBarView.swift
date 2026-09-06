import AppKit
import SwiftUI
import HeadroomCore

/// One usage row in either the full two-line frame or the compact micro frame.
/// The row owns text, accessibility, and value motion; `MeterGauge` owns every
/// shape × fill rendering decision.
struct UsageBarView: View {
    let window: UsageWindow
    let percentageMode: UsagePercentageMode
    let now: Date
    let meterStyle: MeterStyle
    var dimmed: Bool = false
    /// H3a (Jul 2026 multi-account design review): in the multi-account meter the critical
    /// band drops the "Low" chip and paints the percentage numeral a decoupled critical text
    /// color instead. Single-account rows keep the chip exactly as before.
    var chiplessCriticalInk: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// M1A: what the row is currently *painting*, which differs from what the window says
    /// only while a capture lands. Two reasons the paint is mirrored instead of read
    /// straight from the props: S2A needs each motion kind on its own animation, and the
    /// fill has to live inside a `withAnimation` transaction so its completion is a genuine
    /// "the bar landed" signal for the chip and the state label — never a guessed delay.
    @State private var landedValue: RowValue?
    @State private var landedSeverity: UsageSeverity?
    @State private var landedTone: RowTone?
    @State private var showsChip = false
    @State private var visibleStateText: String?

    private let labelSize: CGFloat = 13
    private let resetSize: CGFloat = 11
    private static let percentSize: CGFloat = 18
    private let termSize: CGFloat = 11
    private let rowSpacing: CGFloat = 5

    /// Fill length and numeral — one cause, one motion (M1A). Both are `.movement`.
    private struct RowValue: Equatable {
        var fraction: Double
        var pct: Int?
    }

    /// Everything staleness repaints (M3A′). Colour only; no geometry travels.
    private struct RowTone: Equatable {
        var freshness: UsageWindowFreshness
        var dimmed: Bool
    }

    /// The single "a capture arrived" trigger. Every field is a cause the row answers with
    /// motion, so one `onChange` covers the whole row instead of racing modifiers.
    private struct RowSignal: Equatable {
        var value: RowValue
        var tone: RowTone
        var severity: UsageSeverity
        var chip: Bool
        var state: String?
    }

    /// The numeral sits in a fixed, trailing-aligned column wide enough for "100%" — the
    /// widest string either percentage mode can print. Without the reservation a
    /// three-digit row is wider than a two-digit one and drags the gauge left, so the
    /// meters in a card stop sharing a right edge. Measured from the same
    /// monospaced-digit system font the numeral renders in, so it stays correct if
    /// `percentSize` changes instead of drifting from a hard-coded pixel guess.
    /// M4A leans on it too: the roll from "0%" happens inside a frame that never resizes.
    private static let percentColumnWidth: CGFloat = {
        let font = NSFont.monospacedDigitSystemFont(ofSize: percentSize, weight: .semibold)
        return ceil(("100%" as NSString).size(withAttributes: [.font: font]).width)
    }()

    // MARK: - What the window says

    private var pct: Int? {
        window.freshness.isUnavailable ? nil : percentageMode.roundedPercentage(for: window)
    }

    private var fraction: Double {
        window.freshness.isUnavailable ? 0 : percentageMode.fraction(for: window)
    }

    private var liveValue: RowValue { RowValue(fraction: fraction, pct: pct) }

    private var severity: UsageSeverity { window.severity }

    private var tone: RowTone { RowTone(freshness: window.freshness, dimmed: dimmed) }

    /// The chip's gate is unchanged: critical band only, never on a dimmed or non-live row,
    /// never in the chipless multi-account meter (H3a).
    private var chipIsWarranted: Bool {
        !(dimmed || !window.freshness.isLive) && severity == .critical && !chiplessCriticalInk
    }

    private var stateText: String? {
        switch window.freshness {
        case .live:
            nil
        case .stale(let observedAt):
            Countdown.updatedLabel(capturedAt: observedAt, now: now)
                .map { "Last known \($0)" } ?? "Last known"
        case .unavailable:
            "Unavailable"
        }
    }

    private var resetLine: MeterResetLine? {
        guard !window.freshness.isUnavailable else { return nil }
        return window.resetSchedule.meterResetLine(now: now)
    }

    /// M2A: `MeterResetLine` carries formatted text only, so the roll is keyed on whole
    /// minutes remaining derived from the same scheduled deadline. It shrinks monotonically,
    /// which is what makes the digits roll *down* as the countdown runs out.
    private var minutesUntilReset: Double {
        guard let deadline = window.resetSchedule.deadline else { return 0 }
        return max(0, (deadline.timeIntervalSince(now) / 60).rounded(.down))
    }

    private var rowSignal: RowSignal {
        RowSignal(
            value: liveValue,
            tone: tone,
            severity: severity,
            chip: chipIsWarranted,
            state: stateText
        )
    }

    // MARK: - What the row paints

    /// M4A: a freshly inserted row paints empty first — fill at 0, numeral at "0%" — so the
    /// first live data draws in once on `valueSpring` instead of snapping into place. A row
    /// that arrives already stale or unavailable has no arrival to stage, and Reduce Motion
    /// paints the final value outright.
    private var firstPaintValue: RowValue {
        guard window.freshness.isLive, !reduceMotion else { return liveValue }
        return RowValue(fraction: 0, pct: 0)
    }

    private var displayedValue: RowValue { landedValue ?? firstPaintValue }
    private var displayedSeverity: UsageSeverity { landedSeverity ?? severity }
    private var displayedTone: RowTone { landedTone ?? tone }

    private var isEffectivelyDimmed: Bool {
        displayedTone.dimmed || !displayedTone.freshness.isLive
    }

    private var usesCriticalInk: Bool {
        chiplessCriticalInk && !isEffectivelyDimmed && displayedSeverity == .critical
    }

    private var percentText: String { displayedValue.pct.map { "\($0)%" } ?? "—" }

    private var gaugeFreshness: UsageWindowFreshness {
        let freshness = displayedTone.freshness
        guard displayedTone.dimmed, !freshness.isUnavailable else { return freshness }
        if case .stale = freshness { return freshness }
        // Snapshot-level staleness is a visual state; the date is not rendered by the gauge.
        return .stale(observedAt: window.observedAt ?? now)
    }

    // MARK: - Motion

    private var valueMovement: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion)
    }

    private var valueCrossfade: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion)
    }

    private var settleCrossfade: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)
    }

    private var countdownMovement: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion)
    }

    /// One capture, one landing. The fill leads; the "Low" chip and Full's state label enter
    /// only once it has settled (M1A, M3A′). Exits never wait — they leave on the way in,
    /// which is the subtler half of the pair.
    private func land() {
        let chip = chipIsWarranted
        let state = stateText
        // M3A′: on the way to `.unavailable` the fill keeps its length and fades out, so
        // nothing travels and a return to live crossfades back at the same length.
        let value = window.freshness.isUnavailable
            ? RowValue(fraction: displayedValue.fraction, pct: nil)
            : liveValue

        // M1A: severity colour is the same cause as the fill and rides the same spring, but
        // as its own kind so Reduce Motion keeps the colour while the length snaps.
        withAnimation(valueCrossfade) { landedSeverity = severity }
        // M3A′: stale grey, the unavailable fade-out, and the dimmed numeral ink are colour.
        withAnimation(settleCrossfade) { landedTone = tone }

        if !chip {
            withAnimation(settleCrossfade) { showsChip = false }
        }
        if state == nil || visibleStateText != nil {
            withAnimation(settleCrossfade) { visibleStateText = state }
        }

        // A fill that is not moving — a window going stale keeps its last percentage — has
        // already landed, so the entrances have nothing to wait behind. Deciding that here
        // rather than leaning on a completion callback for a transaction that animates
        // nothing keeps the sequencing true under Reduce Motion too.
        guard let valueMovement, value != displayedValue else {
            landedValue = value
            withAnimation(settleCrossfade) {
                showsChip = chip
                visibleStateText = state
            }
            return
        }
        withAnimation(valueMovement) {
            landedValue = value
        } completion: {
            withAnimation(settleCrossfade) {
                showsChip = chip
                visibleStateText = state
            }
        }
    }

    var body: some View {
        Group {
            switch meterStyle.format {
            case .full:
                fullRow
            case .micro:
                // M3A′: Micro has no room for the state label — a rendered "· Last known …"
                // pushes the gauge and numeral out of the card — so the state travels in the
                // tooltip and the accessibility value instead of a line of its own.
                microRow.help(microHelp)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage")
        .accessibilityValue(accessibilityValue)
        .onAppear { land() }
        .onChange(of: rowSignal) { _, _ in land() }
    }

    /// Full keeps the established fit-aware frame: label metadata and numeral above the
    /// full-width gauge, with a reset subline only when a long label cannot share the top row.
    private var fullRow: some View {
        ViewThatFits(in: .horizontal) {
            fullMeter(inlineReset: true)
            fullMeter(inlineReset: false)
        }
    }

    private func fullMeter(inlineReset: Bool) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                labelText
                stateLabel
                if inlineReset { resetLabel(fixedSize: true) }
                Spacer(minLength: 6)
                urgencyChip
                numeral
            }

            gauge

            if !inlineReset {
                resetLabel(fixedSize: false)
            }
        }
    }

    /// Micro tries the approved one-line reading cluster first. Its fallback preserves
    /// the same information while moving only the gauge + numeral to a second line.
    private var microRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                labelCluster(fixedReset: true)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                urgencyChip
                gauge
                numeral
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    labelCluster(fixedReset: false)
                    Spacer(minLength: 6)
                    urgencyChip
                }
                HStack(alignment: .center, spacing: 6) {
                    Spacer(minLength: 0)
                    gauge
                    numeral
                }
            }
        }
    }

    private func labelCluster(fixedReset: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            labelText
            resetLabel(fixedSize: fixedReset)
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(ProviderStyle.meterLabelInk(scheme: scheme))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// M3A′: Full has a row wide enough for the state, so it keeps the label — it fades in
    /// behind the fill and leaves ahead of it, both driven by `land()`.
    @ViewBuilder
    private var stateLabel: some View {
        if let visibleStateText {
            Text("· \(visibleStateText)")
                .font(.system(size: resetSize, weight: .medium))
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .fixedSize()
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func resetLabel(fixedSize: Bool) -> some View {
        if let resetLine {
            Text(resetLine.countdown)
                .font(.system(size: resetSize).monospacedDigit())
                .foregroundStyle(ProviderStyle.meterCountdownInk(scheme: scheme))
                .lineLimit(1)
                .fixedSize(horizontal: fixedSize, vertical: true)
                // M2A: the minute tick is the row's quietest motion — the digits roll down
                // with the countdown instead of cutting once a minute.
                .contentTransition(
                    HeadroomMotion.numericText(value: minutesUntilReset, reduceMotion: reduceMotion)
                )
                .animation(countdownMovement, value: minutesUntilReset)
                .help(resetLine.tooltip)
        }
    }

    /// M1A: the chip is a consequence of the fill, not a peer of it, so `land()` reveals it
    /// only after the bar settles. Opacity only, and it leaves without waiting.
    @ViewBuilder
    private var urgencyChip: some View {
        if showsChip {
            lowChip
                .transition(.opacity)
        }
    }

    private var numeral: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(percentText)
                .font(.system(size: Self.percentSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(usesCriticalInk ? ProviderStyle.criticalText(scheme: scheme) : .primary)
                .contentTransition(numeralTransition)
                .frame(minWidth: Self.percentColumnWidth, alignment: .trailing)
            if displayedValue.pct != nil {
                Text(percentageMode.term)
                    .font(.system(size: termSize))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
        }
        .fixedSize()
    }

    /// M1A: the roll's direction follows the value. M3A′: the swap to "—" is a crossfade —
    /// an odometer has nothing to roll to once the number goes away.
    private var numeralTransition: ContentTransition {
        guard let pct = displayedValue.pct else { return .opacity }
        return HeadroomMotion.numericText(value: Double(pct), reduceMotion: reduceMotion)
    }

    private var gauge: some View {
        MeterGauge(
            style: meterStyle,
            fraction: displayedValue.fraction,
            severity: displayedSeverity,
            freshness: gaugeFreshness
        )
    }

    /// Small static "Low" flag shown only for the critical band (≤15% left).
    private var lowChip: some View {
        Text("Low")
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.2)
            .foregroundStyle(ProviderStyle.severityColor(for: displayedSeverity, scheme: scheme))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                ProviderStyle.severityColor(for: displayedSeverity, scheme: scheme).opacity(0.16),
                in: Capsule()
            )
    }

    private var label: String {
        switch window.kind {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .billingPeriod(let label, _): return label
        case .other(let raw): return Self.normalizeOther(raw)
        }
    }

    /// M3A′: the tooltip is where a Micro row's state lives. It always says something, so the
    /// row keeps one stable view identity rather than gaining and losing a modifier.
    private var microHelp: String {
        if let stateText { return stateText }
        return resetLine?.tooltip ?? "\(label) usage"
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let pct {
            parts.append("\(pct) percent \(percentageMode.term)")
        }
        if let stateText {
            parts.append(stateText)
        }
        if let resetLine {
            parts.append(resetLine.tooltip)
        }
        return parts.joined(separator: ", ")
    }

    /// Presentation-only tidy of Codex's constructed window labels. The model name stays
    /// verbatim; only the provider-appended period suffix is normalized.
    private static func normalizeOther(_ raw: String) -> String {
        if raw.hasSuffix(" weekly") { return "\(raw.dropLast(7)) · Weekly" }
        if raw.hasSuffix(" 5h") { return "\(raw.dropLast(3)) · 5-hour" }
        return raw
    }
}
