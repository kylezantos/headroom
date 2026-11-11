import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
import HeadroomWidgetSharedUI
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

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

/// R2C8: the one suffix recipe every figure in the popover shares. A meter row prints
/// "used"/"left" after its percentage and a spend row prints "used"/"left" after its
/// amount, at the same size behind the same gap. CMM12: the term takes its natural width
/// and the row ends on the trailing axis; rows printing the same word share a numeral edge.
///
/// R2B2: the slot is reserved even when there is no term to print — an `.unavailable` row
/// that dropped its suffix used to pull its gauge and numeral ≈22.5pt right of the rows above
/// it.
public enum MeterSuffixColumn {
    public static let size: CGFloat = 11
    /// The gap the numeral cluster already spent between figure and term.
    public static let gap: CGFloat = 5
}

/// The suffix itself.
public struct MeterSuffixLabel: View {
    public let term: String
    /// R2B2: `false` reserves the column without printing anything. The word is still laid
    /// out — inked `Color.clear` rather than swapped for a spacer — so the reserved slot keeps
    /// a real term's line box and baseline instead of approximating them.
    public var isVisible: Bool = true
    /// KTD3: the phone's one type unit; the Mac passes 1.
    public var scale: CGFloat = 1

    public init(term: String, isVisible: Bool = true, scale: CGFloat = 1) {
        self.term = term
        self.isVisible = isVisible
        self.scale = scale
    }

    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        Text(term)
            .font(.system(size: MeterSuffixColumn.size * scale))
            .foregroundStyle(isVisible ? ProviderStyle.tertiaryText(scheme: scheme) : Color.clear)
            .lineLimit(1)
            // PA6: inert in Full's baseline row; in Micro it puts the term's cap centre on
            // the row's one optical axis. KTD2: CoreText metrics, identical to the Mac's.
            .widgetCapHeightCentered(size: MeterSuffixColumn.size * scale, weight: .regular)
            // CMM12 (Kyle, 2026-09-10): natural width, no reserved column. The row is
            // trailing-aligned, so its last glyph always lands on the 34pt axis — evenly
            // gapped left and right — and rows that print the same word (every meter row in
            // a popover, since the term comes from one percentage mode) still share a
            // numeral edge. A fixed column sized to the widest word left "left" rows 8pt
            // short of the axis whenever "used" was on screen.
            .fixedSize()
            .accessibilityHidden(!isVisible)
    }
}

/// One usage row in either the full two-line frame or the compact micro frame.
/// The row owns text, accessibility, and value motion; `MeterGauge` owns every
/// shape × fill rendering decision.
///
/// KTD2 (iOS parity): the popover's row, made platform-neutral so the phone renders the same
/// object — CoreText measurement and optics instead of `NSFont`, one `scale` for KTD3, and a
/// `UsageMeterReading` as its only numeric input.
public struct UsageBarView: View {
    /// KTD6.2: the canonical normalized value plus the window it describes. The percentage,
    /// fill and severity ink all read `reading`, never the window's raw arithmetic.
    public let reading: UsageMeterReading
    public let percentageMode: UsagePercentageMode
    public let now: Date
    public let meterStyle: MeterStyle
    public var dimmed: Bool = false
    /// M4A: the account this row belongs to, and the row's opt-in to the once-per-launch
    /// draw-in. `nil` — the default — means "paint the final value immediately", which is
    /// what every preview, specimen, and non-account surface wants.
    public var arrivalKey: AccountKey? = nil
    /// KTD3: type, spacing, the numeral column and the gauge all multiply by this, so the
    /// row reserves its larger layout rather than being scaled after layout. The Mac passes 1.
    public var scale: CGFloat = 1
    /// Popover account layout (R11, KTD7): set, a Micro row draws as one Compact cell — this
    /// short window label, the gauge and the numeral — with no countdown, suffix term or
    /// tooltip of its own. The Compact row owns those (R13), so this cell stays out of the
    /// accessibility tree.
    public var compactLabel: String? = nil
    /// Default-login plan U8 (R8): a remembered account's window whose reset has passed
    /// (`RememberedRowRecipe.resetNotReadLine`). Set, the row draws its window label and
    /// this line in place of the gauge and the number, inside the height a meter row takes,
    /// so the card does not jump when a reset passes. Ignored by a Compact cell, whose row
    /// carries the wording in its tooltip. Nil, the default, draws the meter as before.
    public var resetNotReadLine: String? = nil
    /// U8 (R7): false on a remembered account's rows, whose identity row already says when
    /// they were last read, so Full's per-window "· Last known …" label is not repeated under
    /// it. VoiceOver keeps the state. True, the default, is every existing row.
    public var showsWindowState: Bool = true
    /// U8 (R7, mock dl-a2): true on a remembered account's rows, which read as secondary
    /// beside the live rows. The window label takes the dimmed numeral's `.secondary` ink and
    /// the countdown the tertiary text token, alongside the gauge and number `dimmed` already
    /// quiets. False, the default, keeps every other row's label and countdown ink, stale
    /// and unavailable engine rows included.
    public var dimsLabels: Bool = false
    /// The labels of every window in the same account that draws a reset line. The label
    /// column of a reset line is as wide as the widest of them, so the lines start at one
    /// x ("5-hour" and "Weekly" are not the same width). Empty, the default, sizes the label
    /// to itself.
    public var resetLabelPeers: [String] = []
    /// `resetNotReadLine` in its compact form ("Reset Wed 10:00 AM · not read since"), which
    /// is what the row draws; the sentence form stays in the tooltip and for VoiceOver. Nil
    /// draws the sentence.
    public var resetNotReadCompactLine: String? = nil

    public func resetLine(peers: [String], compact: String?) -> UsageBarView {
        var copy = self
        copy.resetLabelPeers = peers
        copy.resetNotReadCompactLine = compact
        return copy
    }

    public init(
        reading: UsageMeterReading,
        percentageMode: UsagePercentageMode,
        now: Date,
        meterStyle: MeterStyle,
        dimmed: Bool = false,
        arrivalKey: AccountKey? = nil,
        scale: CGFloat = 1,
        compactLabel: String? = nil,
        resetNotReadLine: String? = nil,
        showsWindowState: Bool = true,
        dimsLabels: Bool = false
    ) {
        self.reading = reading
        self.percentageMode = percentageMode
        self.now = now
        self.meterStyle = meterStyle
        self.dimmed = dimmed
        self.arrivalKey = arrivalKey
        self.scale = scale
        self.compactLabel = compactLabel
        self.resetNotReadLine = resetNotReadLine
        self.showsWindowState = showsWindowState
        self.dimsLabels = dimsLabels
    }

    /// The Mac's form: the reading is normalized from the actual provider window.
    public init(
        window: UsageWindow,
        percentageMode: UsagePercentageMode,
        now: Date,
        meterStyle: MeterStyle,
        dimmed: Bool = false,
        arrivalKey: AccountKey? = nil,
        scale: CGFloat = 1,
        compactLabel: String? = nil,
        resetNotReadLine: String? = nil,
        showsWindowState: Bool = true,
        dimsLabels: Bool = false
    ) {
        self.init(
            reading: UsageMeterReading(window: window),
            percentageMode: percentageMode,
            now: now,
            meterStyle: meterStyle,
            dimmed: dimmed,
            arrivalKey: arrivalKey,
            scale: scale,
            compactLabel: compactLabel,
            resetNotReadLine: resetNotReadLine,
            showsWindowState: showsWindowState,
            dimsLabels: dimsLabels
        )
    }

    private var window: UsageWindow { reading.window }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.headroomTuning) private var tuning

    /// M1A: what the row is currently *painting*, which differs from what the window says
    /// only while a capture lands. Two reasons the paint is mirrored instead of read
    /// straight from the props: S2A needs each motion kind on its own animation, and the
    /// fill has to live inside a `withAnimation` transaction so its completion is a genuine
    /// "the bar landed" signal for the state label — never a guessed delay.
    @State private var landedValue: RowValue?
    @State private var landedSeverity: UsageSeverity?
    @State private var landedTone: RowTone?
    @State private var visibleStateText: String?
    /// R2B4: which landing is allowed to commit. `land()` captures `stateText` at entry and
    /// writes it back when the fill's spring completes ~0.3s later; a second capture arriving
    /// inside that window used to let the older landing overwrite the newer state text. The
    /// completion cannot read the live property — it captures the view value, not the live
    /// one — so it checks whether it is still the current landing instead.
    @State private var landGeneration = 0

    private var labelSize: CGFloat { tuning.labelSize * scale }
    private var resetSize: CGFloat { tuning.resetSize * scale }
    private static let percentSize: CGFloat = 18
    private var percentSize: CGFloat { tuning.percentSize * scale }
    private var percentWeight: Font.Weight { HeadroomTuning.weight(tuning.percentWeight) }
    private var labelWeight: Font.Weight { HeadroomTuning.weight(tuning.labelWeight) }
    /// FS1 (Kyle, Sep 2026): Full sat its full-width gauge 5pt under the label it belongs
    /// to, which crowded the two into one band; 7 lets the bar breathe without breaking the
    /// pairing. Only Full stacks a gauge under its label now — Micro is always a single row —
    /// so this is Full's label→gauge gap.
    private var rowSpacing: CGFloat { tuning.fullLabelToGauge * scale }
    /// The row's HStack gaps and its spacer's floor.
    private var gap: CGFloat { tuning.meterGap * scale }

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
        var state: String?
    }

    /// The numeral sits in a fixed, trailing-aligned column wide enough for "100%" — the
    /// widest string either percentage mode can print. Without the reservation a
    /// three-digit row is wider than a two-digit one and drags the gauge left, so the
    /// meters in a card stop sharing a right edge. Measured from the same
    /// monospaced-digit system font the numeral renders in, so it stays correct if
    /// `percentSize` changes instead of drifting from a hard-coded pixel guess.
    /// M4A leans on it too: the roll from "0%" happens inside a frame that never resizes.
    /// KTD2: measured with CoreText (`HeadroomWidgetFontMetrics.textWidth`), which reports
    /// exactly what `NSString.size(withAttributes:)` did for the same face.
    private func percentColumnWidth(size: CGFloat, weight: Font.Weight) -> CGFloat {
        ceil(HeadroomWidgetFontMetrics.textWidth("100%", size: size, weight: weight, mono: true))
    }

    // MARK: - What the window says

    private var pct: Int? { reading.roundedPercentage(for: percentageMode) }

    private var fraction: Double { reading.fraction(for: percentageMode) }

    private var liveValue: RowValue { RowValue(fraction: fraction, pct: pct) }

    /// KTD6.2: the normalized severity. A reading with no finite value has none to paint and
    /// shows no fill or figure, so it takes the neutral band rather than a guessed one.
    private var severity: UsageSeverity { reading.severity ?? .healthy }

    private var tone: RowTone { RowTone(freshness: window.freshness, dimmed: dimmed) }

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
            state: stateText
        )
    }

    // MARK: - What the row paints

    /// M4A: an arriving row paints its fill empty first, so the first live data draws in once
    /// on `arrivalSpring` (AR1) instead of snapping into place. AR2 (2026-09-25 motion audit):
    /// the numeral paints its real value from the first frame. It used to start at "0%" and
    /// roll up, which told the user they had 0% left for the whole arrival beat. Everything
    /// else paints its final value on the first frame: a row with no `arrivalKey`, an
    /// account that already arrived this launch, a window that shows up already stale or
    /// unavailable and so has no arrival to stage, and every row under Reduce Motion.
    private var firstPaintValue: RowValue {
        isStagedArrival ? RowValue(fraction: 0, pct: liveValue.pct) : liveValue
    }

    /// M4A/M9A: true only when this row will draw in from empty — an account with an
    /// `arrivalKey` that hasn't arrived yet this launch, on a live window, Reduce Motion off.
    /// Both the empty first paint above and the delayed trigger below key off this so they
    /// can never disagree about whether an arrival is happening.
    private var isStagedArrival: Bool {
        guard let arrivalKey,
              !ArrivalRegistry.hasLanded(arrivalKey),
              window.freshness.isLive,
              !reduceMotion
        else { return false }
        return true
    }

    private var displayedValue: RowValue { landedValue ?? firstPaintValue }
    private var displayedSeverity: UsageSeverity { landedSeverity ?? severity }
    private var displayedTone: RowTone { landedTone ?? tone }

    private var isEffectivelyDimmed: Bool {
        displayedTone.dimmed || !displayedTone.freshness.isLive
    }

    /// AP1 (Kyle, Sep 2026): critical is one treatment everywhere now — the numeral goes red
    /// and the meter's own critical indicators carry the rest. The "Low" capsule that used to
    /// stand beside single-account rows (H3a kept it there while multi-account rows went
    /// chipless) said the same thing a third time, so it is gone and every row reads the way
    /// the multi-account meter already did.
    private var usesCriticalInk: Bool {
        !isEffectivelyDimmed && displayedSeverity == .critical
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
        HeadroomMotion.resolved(tuning.valueSpring, .movement, reduceMotion: reduceMotion)
    }

    private var valueCrossfade: Animation? {
        HeadroomMotion.resolved(tuning.valueSpring, .crossfade, reduceMotion: reduceMotion)
    }

    private var arrivalMovement: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.arrivalSpring, .movement, reduceMotion: reduceMotion)
    }

    private var arrivalCrossfade: Animation? {
        HeadroomMotion.resolved(HeadroomMotion.arrivalSpring, .crossfade, reduceMotion: reduceMotion)
    }

    private var settleCrossfade: Animation? {
        HeadroomMotion.resolved(tuning.settle, .crossfade, reduceMotion: reduceMotion)
    }

    private var countdownMovement: Animation? {
        HeadroomMotion.resolved(tuning.settle, .movement, reduceMotion: reduceMotion)
    }

    /// One capture, one landing. The fill leads; Full's state label enters only once it has
    /// settled (M1A, M3A′). Exits never wait — they leave on the way in, which is the subtler
    /// half of the pair. AP1 removed the "Low" chip from this sequence; the rest is intact.
    private func land() {
        landGeneration &+= 1
        let generation = landGeneration
        let state = stateText
        // Read what the row is currently showing before touching the registry, so the
        // comparison below is against the frame the user actually saw.
        let from = displayedValue
        // AR1: read before the claim below, which is what makes `isStagedArrival` false.
        let isArrival = landedValue == nil && isStagedArrival
        // M4A: this account has now shown its arrival, so no later row for it draws in again.
        if landedValue == nil, let arrivalKey {
            ArrivalRegistry.claim(arrivalKey)
        }
        // M3A′: on the way to `.unavailable` the fill keeps its length and fades out, so
        // nothing travels and a return to live crossfades back at the same length.
        let value = reading.hidesValue
            ? RowValue(fraction: from.fraction, pct: nil)
            : liveValue

        // M1A: severity colour is the same cause as the fill and rides the same spring, but
        // as its own kind so Reduce Motion keeps the colour while the length snaps.
        withAnimation(isArrival ? arrivalCrossfade : valueCrossfade) { landedSeverity = severity }
        // M3A′/PA8: stale grey, the unavailable fade-out, and the dimmed numeral ink are
        // colour. The numeral only joined this transaction with PA8 — M3A′ described it, but
        // `numeral` was reading `.primary` unconditionally, so the claim was aspirational
        // until `numeralInk` started consulting `landedTone` too.
        withAnimation(settleCrossfade) { landedTone = tone }

        if state == nil || visibleStateText != nil {
            withAnimation(settleCrossfade) { visibleStateText = state }
        }

        // A fill that is not moving — a window going stale keeps its last percentage — has
        // already landed, so the entrances have nothing to wait behind. Deciding that here
        // rather than leaning on a completion callback for a transaction that animates
        // nothing keeps the sequencing true under Reduce Motion too.
        guard let movement = isArrival ? arrivalMovement : valueMovement, value != from else {
            landedValue = value
            withAnimation(settleCrossfade) { visibleStateText = state }
            return
        }
        withAnimation(movement) {
            landedValue = value
        } completion: {
            // R2B4: a landing that has already been superseded has nothing left to say.
            guard landGeneration == generation else { return }
            withAnimation(settleCrossfade) { visibleStateText = state }
        }
    }

    public var body: some View {
        let _ = SharedBenchCounters.hit("UsageBarView")
        Group {
            if compactLabel == nil, let resetNotReadLine {
                resetNotReadRow(resetNotReadLine)
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            } else {
                switch meterStyle.format {
                case .full:
                    // The meter leaves on a fade when its reset passes on a remembered row.
                    fullRow
                        .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
                case .micro:
                    if let compactLabel {
                        compactCell(compactLabel)
                    } else {
                        // M3A′: Micro has no room for the state label — a rendered "· Last known …"
                        // pushes the gauge and numeral out of the card — so the state travels in
                        // the tooltip and the accessibility value instead of a line of its own.
                        microRow.help(microHelp)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenLabel) usage")
        .accessibilityValue(accessibilityValue)
        .accessibilityHidden(compactLabel != nil)
        // M9A: a staged arrival waits one beat so the count-up starts after the popover has
        // finished opening, not behind it. `.task` is cancelled on close, so a popover shut
        // inside that beat never claims the arrival — it simply draws in on the next open.
        // Everything else lands the instant it appears, exactly as before.
        .task {
            guard isStagedArrival else { land(); return }
            try? await Task.sleep(for: HeadroomMotion.arrivalDelay)
            guard !Task.isCancelled else { return }
            land()
        }
        .onChange(of: rowSignal) { _, _ in land() }
    }

    /// U8 (R8): a remembered window past its reset. In Micro the meter row it replaces is
    /// laid out hidden underneath, so the line takes that row's height on its one optical
    /// axis and nothing travels when a reset passes. In Full the row is the line alone: a
    /// band kept open for a gauge that is no longer there read as an accident (Kyle, Nov
    /// 2026). There the row closes when the reset passes, and the scope that owns the stack
    /// animates it: the gauge and number fade, the height closes, the line fades in.
    private func resetNotReadRow(_ line: String) -> some View {
        let isFull = meterStyle.format == .full
        return ZStack(alignment: .leading) {
            if !isFull { microRow.hidden() }
            HStack(alignment: isFull ? .firstTextBaseline : .center, spacing: gap) {
                if isFull {
                    // Laid out as the meter's top line is: a label on the numeral's baseline.
                    // The zero-width numeral holds that baseline, so the label does not move
                    // while the meter fades out and this line fades in.
                    resetLabelColumn
                    resetHint(line)
                    Spacer(minLength: 0)
                    Text("0")
                        .font(.system(size: percentSize, weight: percentWeight).monospacedDigit())
                        .widgetCapHeightCentered(size: percentSize, weight: percentWeight)
                        .frame(width: 0)
                        .hidden()
                } else {
                    resetLabelColumn
                        .widgetCapHeightCentered(size: labelSize, weight: labelWeight)
                    resetHint(line)
                        .widgetCapHeightCentered(size: resetSize, weight: .regular)
                    Spacer(minLength: 0)
                }
            }
            .help("\(spokenLabel): \(line)")
        }
    }

    /// Every peer is laid out hidden with its own optical leading, this row's label among
    /// them, so the column is one width on every reset line.
    private var resetLabelColumn: some View {
        ZStack(alignment: .leading) {
            ForEach(resetLabelPeers.filter { $0 != label }, id: \.self) { peer in
                Text(peer)
                    .font(.system(size: labelSize, weight: labelWeight))
                    .lineLimit(1)
                    .fixedSize()
                    .widgetOpticalLeading(peer, size: labelSize, weight: labelWeight)
                    .hidden()
            }
            labelText.fixedSize()
        }
    }

    /// The compact form on every reset line: the sentence ("Reset yesterday at 12:32 AM ·
    /// …") does not fit a Micro row, and two forms in one account read as two different
    /// things. The tooltip and VoiceOver keep the sentence.
    private func resetHint(_ line: String) -> some View {
        Text(resetNotReadCompactLine ?? line)
            .font(.system(size: resetSize).monospacedDigit())
            .foregroundStyle(hintInk)
            .lineLimit(1)
            .truncationMode(.tail)
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
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                labelText
                stateLabel
                if inlineReset { resetLabel(fixedSize: true) }
                Spacer(minLength: gap)
                numeralCluster(capCentred: false)
            }

            gauge

            if !inlineReset {
                resetLabel(fixedSize: false)
            }
        }
    }

    /// Micro is always one row (Kyle, Sep 2026: "should always be 1 row"). The ladder degrades
    /// the row within its single line rather than dropping the gauge + numeral to a second one:
    /// first the full countdown, then the coarse countdown ("22h 54m" → "22h"), and finally —
    /// when even that overruns — the label truncates with a tail ellipsis. The last rung is the
    /// guaranteed fit: `ViewThatFits` falls to it when none fit, and there the label is the only
    /// flexible element, so it gives while the gauge, numeral, and (short) countdown stay whole.
    /// The full label and countdown always remain in the tooltip (`microHelp`).
    ///
    /// PA6 (Kyle): "center aligned with each other, not the bottom baseline." The row keeps
    /// `.center` — a shared baseline would leave the 18pt numeral riding visibly high over a
    /// 13pt label — but every text element now declares where its **cap-height centre** is,
    /// measured from the real font (CoreText, `HeadroomWidgetFontMetrics`), instead of its line
    /// box. SwiftUI's plain `.center` centres line boxes, and a line box is asymmetric about
    /// its ink by a different amount at each size (0.68pt at 13, 0.36pt at 18), so the label
    /// was sitting ~0.3pt below the numeral it labels. The gauge keeps the default `.center`
    /// guide: its geometric centre is the axis every cap centre is measured against.
    private var microRow: some View {
        ViewThatFits(in: .horizontal) {
            microLine(short: false, truncatesLabel: false)
            microLine(short: true, truncatesLabel: false)
            microLine(short: true, truncatesLabel: true)
        }
    }

    private func microLine(short: Bool, truncatesLabel: Bool) -> some View {
        HStack(alignment: .center, spacing: gap) {
            labelCluster(short: short, truncatesLabel: truncatesLabel)
            Spacer(minLength: gap)
            gauge
            numeralCluster(capCentred: true)
        }
    }

    /// The Compact cell (R11): label, gauge and numeral on the row's one optical axis, each
    /// at a fixed width so cells line up row to row. Sizes are the options doc's proposal
    /// (HC-D: numeral 15) pending live review.
    private func compactCell(_ label: String) -> some View {
        HStack(alignment: .center, spacing: compactGap) {
            // An empty label draws none: the Compact card's header names the column instead.
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: MeterSuffixColumn.size * scale))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .fixedSize()
                    .widgetCapHeightCentered(size: MeterSuffixColumn.size * scale, weight: .regular)
            }
            gauge
            Text(percentText)
                .font(.system(size: compactPercentSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(numeralInk)
                .contentTransition(numeralTransition)
                .frame(minWidth: percentColumnWidth(size: compactPercentSize, weight: .semibold), alignment: .trailing)
                .widgetCapHeightCentered(size: compactPercentSize, weight: .semibold)
        }
        .fixedSize()
    }

    private var compactGap: CGFloat { 4 * scale }
    private var compactPercentSize: CGFloat { 15 * scale }

    /// Micro's label + countdown. `truncatesLabel` decides whether the pair pins to its ideal
    /// width (the label never truncates) or yields to the proposed width — where the label is
    /// the sole flexible element, so it truncates while the countdown stays whole. `short`
    /// selects the coarse countdown. Cap centres keep the pair on the row's one optical axis.
    private func labelCluster(short: Bool, truncatesLabel: Bool) -> some View {
        HStack(alignment: .center, spacing: gap) {
            labelText
                .widgetCapHeightCentered(size: labelSize, weight: labelWeight)
            resetLabel(fixedSize: true, short: short)
        }
        .fixedSize(horizontal: !truncatesLabel, vertical: false)
    }

    private var labelText: some View {
        Text(label)
            .font(.system(size: labelSize, weight: labelWeight))
            .foregroundStyle(labelInk)
            .lineLimit(1)
            .truncationMode(.tail)
            // OA1: "Weekly" (a diagonal) against "5-hour" (a flat stem) is the widest
            // stagger in the card — 1.25pt apart at this size before the correction.
            .widgetOpticalLeading(label, size: labelSize, weight: labelWeight)
    }

    /// M3A′: Full has a row wide enough for the state, so it keeps the label — it fades in
    /// behind the fill and leaves ahead of it, both driven by `land()`.
    @ViewBuilder
    private var stateLabel: some View {
        if showsWindowState, let visibleStateText {
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
    private func resetLabel(fixedSize: Bool, short: Bool = false) -> some View {
        if let resetLine {
            Text(short ? resetLine.shortCountdown : resetLine.countdown)
                .font(.system(size: resetSize).monospacedDigit())
                .foregroundStyle(countdownInk)
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
                .widgetCapHeightCentered(size: resetSize, weight: .regular)
        }
    }

    /// PA6: Micro asks for cap centres — the figure and its term each land on the row's one
    /// optical axis — while Full keeps the shared baseline that makes "72% used" read as one
    /// phrase across a wide row.
    private func numeralCluster(capCentred: Bool) -> some View {
        HStack(alignment: capCentred ? .center : .firstTextBaseline, spacing: MeterSuffixColumn.gap * scale) {
            Text(percentText)
                .font(.system(size: percentSize, weight: percentWeight).monospacedDigit())
                .foregroundStyle(numeralInk)
                .contentTransition(numeralTransition)
                .frame(minWidth: percentColumnWidth(size: percentSize, weight: percentWeight), alignment: .trailing)
                .widgetCapHeightCentered(size: percentSize, weight: percentWeight)
            // R2B2: an `.unavailable` row has no term to print, but it keeps the column —
            // otherwise its "—" and gauge slide right of the live rows stacked above it.
            MeterSuffixLabel(term: percentageMode.term, isVisible: displayedValue.pct != nil, scale: scale)
        }
        .fixedSize()
    }

    /// R2C14: at critical the row's question changes from "how much is left" to "when does
    /// it come back", and the countdown was the smallest, dimmest text in it. Critical and
    /// live only — `usesCriticalInk` is already false on a dimmed or stale row, where a
    /// louder countdown would be describing a reading we no longer stand behind. Size,
    /// position and digits are unchanged; only the ink steps up. It rides `landedSeverity`,
    /// so it crossfades with the fill on the same transaction.
    private var countdownInk: Color {
        if usesCriticalInk { return Color.secondary }
        // U8: a remembered row's countdown steps down with its label (`dimsLabels`).
        return dimsLabels ? hintInk : ProviderStyle.meterCountdownInk(scheme: scheme)
    }

    /// The countdown and the reset line beside a window label. On a remembered row the label
    /// is already `.secondary`, and the tertiary text token reads as bright as that, so the
    /// hint steps one notch under the label (Kyle, Nov 2026). Elsewhere the label is full
    /// ink and the token is already the quieter of the two.
    private var hintInk: Color {
        dimsLabels ? Color.secondary.opacity(0.72) : ProviderStyle.tertiaryText(scheme: scheme)
    }

    /// U8: a remembered row's label takes the dimmed numeral's ink (`numeralInk`); every
    /// other row keeps the meter label token.
    private var labelInk: AnyShapeStyle {
        dimsLabels ? AnyShapeStyle(.secondary) : AnyShapeStyle(ProviderStyle.meterLabelInk(scheme: scheme))
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
            freshness: gaugeFreshness,
            scale: scale
        )
    }

    private var label: String { window.kind.displayName }

    /// The label with its period spoken — "Fable weekly" where the row itself reads "Fable".
    private var spokenLabel: String { window.kind.spokenName }

    /// M3A′: the tooltip is where a Micro row's state lives. It always says something, so the
    /// row keeps one stable view identity rather than gaining and losing a modifier.
    private var microHelp: String {
        if showsWindowState, let stateText { return stateText }
        return resetLine?.tooltip ?? "\(spokenLabel) usage"
    }

    /// The word VoiceOver adds to a live Critical row's value.
    public static let criticalSpokenState = "critical"

    private var accessibilityValue: String {
        // U8 (R8): the reset line is the row's whole statement; it carries no number.
        if compactLabel == nil, let resetNotReadLine { return resetNotReadLine }
        var parts: [String] = []
        if let pct {
            parts.append("\(pct) percent \(percentageMode.term)")
        }
        // U8 (R3, AP1): the red numeral is critical's whole visible signal now the "Low" chip
        // is gone, so VoiceOver says it in words. Same gate as the ink: live, not dimmed.
        if reading.usesCriticalInk(dimmed: dimmed) {
            parts.append(Self.criticalSpokenState)
        }
        if let stateText {
            parts.append(stateText)
        }
        if let resetLine {
            parts.append(resetLine.tooltip)
        }
        return parts.joined(separator: ", ")
    }
}
