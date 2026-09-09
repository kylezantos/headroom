import AppKit
import SwiftUI
import HeadroomCore

/// M4A: which accounts have already shown their arrival this launch. Session-scoped, in
/// memory, exactly like `PopoverEntranceAnimation` — and for the same reason. The popover
/// rebuilds its content on every open, so a draw-in keyed only to view lifetime would
/// replay on every open; the Appearance specimen would replay it again on every
/// `.id(meterStyle)` crossfade. An arrival is a once-per-launch event per account.
///
/// The trigger is "the first time this account's live windows are actually shown this
/// launch" rather than the literal `.pending → .live` flip. The flip commonly happens
/// while the popover is closed, and `.pending` renders the card's skeleton rather than
/// this view, so from here the flip is neither observable nor the thing the user sees
/// arrive.
@MainActor
private enum ArrivalRegistry {
    private static var landed: Set<AccountKey> = []

    static func hasLanded(_ key: AccountKey) -> Bool { landed.contains(key) }

    /// Claimed *after* the current update finishes, never during it. Both meter rows of an
    /// account are built in one body pass and their `onAppear`s run in that same turn, so a
    /// synchronous claim would let the first row lock the key and leave the second — already
    /// painted empty — with nothing left to animate to.
    static func claim(_ key: AccountKey) {
        Task { @MainActor in landed.insert(key) }
    }
}

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
    /// M4A: the account this row belongs to, and the row's opt-in to the once-per-launch
    /// draw-in. `nil` — the default — means "paint the final value immediately", which is
    /// what every preview, specimen, and non-account surface wants.
    var arrivalKey: AccountKey? = nil

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

    /// M4A: an arriving row paints empty first — fill at 0, numeral at "0%" — so the first
    /// live data draws in once on `valueSpring` instead of snapping into place. Everything
    /// else paints its final value on the first frame: a row with no `arrivalKey`, an
    /// account that already arrived this launch, a window that shows up already stale or
    /// unavailable and so has no arrival to stage, and every row under Reduce Motion.
    private var firstPaintValue: RowValue {
        guard let arrivalKey,
              !ArrivalRegistry.hasLanded(arrivalKey),
              window.freshness.isLive,
              !reduceMotion
        else { return liveValue }
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
        // Read what the row is currently showing before touching the registry, so the
        // comparison below is against the frame the user actually saw.
        let from = displayedValue
        // M4A: this account has now shown its arrival, so no later row for it draws in again.
        if landedValue == nil, let arrivalKey {
            ArrivalRegistry.claim(arrivalKey)
        }
        // M3A′: on the way to `.unavailable` the fill keeps its length and fades out, so
        // nothing travels and a return to live crossfades back at the same length.
        let value = window.freshness.isUnavailable
            ? RowValue(fraction: from.fraction, pct: nil)
            : liveValue

        // M1A: severity colour is the same cause as the fill and rides the same spring, but
        // as its own kind so Reduce Motion keeps the colour while the length snaps.
        withAnimation(valueCrossfade) { landedSeverity = severity }
        // M3A′/PA8: stale grey, the unavailable fade-out, and the dimmed numeral ink are
        // colour. The numeral only joined this transaction with PA8 — M3A′ described it, but
        // `numeral` was reading `.primary` unconditionally, so the claim was aspirational
        // until `numeralInk` started consulting `landedTone` too.
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
        guard let valueMovement, value != from else {
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
                numeralCluster(capCentred: false)
            }

            gauge

            if !inlineReset {
                resetLabel(fixedSize: false)
            }
        }
    }

    /// Micro tries the approved one-line reading cluster first. Its fallback preserves
    /// the same information while moving only the gauge + numeral to a second line.
    ///
    /// PA6 (Kyle): "center aligned with each other, not the bottom baseline." The row keeps
    /// `.center` — a shared baseline would leave the 18pt numeral riding visibly high over a
    /// 13pt label — but every text element now declares where its **cap-height centre** is,
    /// measured from the real `NSFont` (`OpticalCentering`), instead of leaning on its line
    /// box. SwiftUI's plain `.center` centres line boxes, and a line box is asymmetric about
    /// its ink by a different amount at each size (0.68pt at 13, 0.36pt at 18), so the label
    /// was sitting ~0.3pt below the numeral it labels. The gauge keeps the default `.center`
    /// guide: its geometric centre is the axis every cap centre is measured against.
    private var microRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                labelCluster(fixedReset: true, capCentred: true)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                urgencyChip
                gauge
                numeralCluster(capCentred: true)
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(alignment: .center, spacing: 6) {
                    labelCluster(fixedReset: false, capCentred: true)
                    Spacer(minLength: 6)
                    urgencyChip
                }
                HStack(alignment: .center, spacing: 6) {
                    Spacer(minLength: 0)
                    gauge
                    numeralCluster(capCentred: true)
                }
            }
        }
    }

    /// PA6: Micro asks for cap centres; Full keeps the shared baseline, which is the right
    /// answer on a wide row where the label and its countdown read as one phrase. The
    /// per-element guides below are inert under `.firstTextBaseline`, so both callers can
    /// carry them.
    private func labelCluster(fixedReset: Bool, capCentred: Bool = false) -> some View {
        HStack(alignment: capCentred ? .center : .firstTextBaseline, spacing: 6) {
            labelText
                .capHeightCentered(size: labelSize, weight: .medium)
            resetLabel(fixedSize: fixedReset)
        }
    }

    private var labelText: some View {
        Text(label)
            .font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(ProviderStyle.meterLabelInk(scheme: scheme))
            .lineLimit(1)
            .truncationMode(.tail)
            // OA1: "Weekly" (a diagonal) against "5-hour" (a flat stem) is the widest
            // stagger in the card — 1.25pt apart at this size before the correction.
            .opticalLeading(label, size: labelSize, weight: .medium)
    }

    /// M3A′: Full has a row wide enough for the state, so it keeps the label — it fades in
    /// behind the fill and leaves ahead of it, both driven by `land()`.
    @ViewBuilder
    private var stateLabel: some View {
        if let visibleStateText {
            Text("· \(visibleStateText)")
                // PB11: "Last known 4 min ago" ticks a digit at a time beside a countdown
                // that already sets its digits monospaced, so it takes the same tabular
                // figures — otherwise the whole label re-flows every minute.
                .font(.system(size: resetSize, weight: .medium).monospacedDigit())
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
                // PA6: inert in Full's baseline row; in Micro it puts the countdown's cap
                // centre on the same axis as the label beside it.
                .capHeightCentered(size: resetSize, weight: .regular)
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

    /// PA6: Micro asks for cap centres — the figure and its term each land on the row's one
    /// optical axis — while Full keeps the shared baseline that makes "72% used" read as one
    /// phrase across a wide row.
    private func numeralCluster(capCentred: Bool) -> some View {
        HStack(alignment: capCentred ? .center : .firstTextBaseline, spacing: 5) {
            Text(percentText)
                .font(.system(size: Self.percentSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(numeralInk)
                .contentTransition(numeralTransition)
                .frame(minWidth: Self.percentColumnWidth, alignment: .trailing)
                .capHeightCentered(size: Self.percentSize, weight: .semibold)
            if displayedValue.pct != nil {
                Text(percentageMode.term)
                    .font(.system(size: termSize))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                    .capHeightCentered(size: termSize, weight: .regular)
            }
        }
        .fixedSize()
    }

    /// PA8: the numeral is the loudest thing in the row, and it was the only element still
    /// painting live ink on a stale one — the meter dimmed, the "Stale" capsule appeared, and
    /// the figure carried on at full contrast. It now dims with everything else, riding
    /// `landedTone` and therefore `land()`'s `settleCrossfade`. Critical ink still wins:
    /// `usesCriticalInk` is already false on a dimmed row, so the order below is what keeps a
    /// live critical numeral red rather than merely secondary.
    private var numeralInk: AnyShapeStyle {
        if usesCriticalInk {
            AnyShapeStyle(ProviderStyle.criticalText(scheme: scheme))
        } else if isEffectivelyDimmed {
            AnyShapeStyle(.secondary)
        } else {
            AnyShapeStyle(.primary)
        }
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
            // PA7: the type is the capsule's now — C6A unified the six capsules' height but
            // left four sizes and two weights inside them, so they still read as tiers.
            .foregroundStyle(ProviderStyle.severityColor(for: displayedSeverity, scheme: scheme))
            // C6A: was 15pt from vPad 1 — one shared 18pt capsule now, so it reads as a peer
            // of the plan pill and Stale tag rather than a second, shorter tier.
            .identityCapsule(
                fill: ProviderStyle.severityColor(for: displayedSeverity, scheme: scheme).opacity(0.16),
                horizontalPadding: 5
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
