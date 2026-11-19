import SwiftUI

/// U9 (R18, R19, KTD14): the phone's side of pull to check now. A real pull writes the
/// request through Core's `CheckNowClient`; Explore Demo replays the bundled receipt through
/// the same `CheckNowMachine` and writes nothing (KTD21, AE8). An older Mac — or anything the
/// machine says cannot check (KTD14.1) — re-reads only, with no "Asking your Mac" state.
@MainActor
@Observable
final class PhoneCheckNow {
    private(set) var status: CheckNowStatus?
    /// When this session first saw the status complete; `CheckNowLinePolicy` holds the
    /// completion line for three seconds from here.
    private(set) var completedAt: Date?
    /// When the in-flight phase last ended, so the loading row finishes its wave (KTD16).
    private(set) var inFlightEndedAt: Date?
    /// KTD22: Settings' "Last check" row. Real round trips only; a demo replay is not one.
    private(set) var lastRoundTrip: PhoneCheckNowRoundTrip?
    /// Bumped when a deadline passes with no new data, so the slot re-reads the policy.
    private(set) var tick = 0
    #if DEBUG
    /// AE8 UI-test marker: request keys this launch wrote. A demo pull must leave it at 0.
    private(set) var requestsWritten = 0
    /// AE1 UI-test marker: pulls that re-read instead of checking. It proves an older Mac's
    /// pull ran (review 2 #6), not merely that nothing was asked.
    private(set) var rereadPulls = 0

    func recordRereadPull() {
        rereadPulls += 1
    }
    #endif

    @ObservationIgnored private var client: CheckNowClient??
    @ObservationIgnored private var lastSnapshot: CompanionResolvedSnapshot?
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var replay: Task<Void, Never>?
    /// Review #10 for the demo path: a newer pull or a reset drops an older replay's steps.
    @ObservationIgnored private var replayGeneration = 0
    @ObservationIgnored private var demoState: CheckNowRequestState?
    @ObservationIgnored private var demoAdopt: ((CompanionResolvedSnapshot) -> Void)?

    /// What the inline header status shows right now.
    func slot(at now: Date) -> CheckNowSlot {
        _ = tick
        return CheckNowLinePolicy.slot(status: status, completedAt: completedAt, now: now)
    }

    // MARK: Real pulls

    /// Returns false when the host should re-read instead (KTD14.1, AE1).
    func pull(snapshot: CompanionResolvedSnapshot) -> Bool {
        lastSnapshot = snapshot
        guard let client = resolvedClient() else { return false }
        switch client.pull(snapshot: snapshot) {
        case .rereadOnly:
            return false
        case .requested(let status):
            #if DEBUG
            requestsWritten += 1
            #endif
            apply(status, recordsRoundTrip: true)
        case .pending(let status):
            apply(status, recordsRoundTrip: true)
        }
        return true
    }

    /// Folds the receipt and the latest snapshot into the request (every KVS change, reload
    /// and deadline). A launch adopts a stored request only while it is still open.
    func update(snapshot: CompanionResolvedSnapshot) {
        lastSnapshot = snapshot
        guard demoState == nil, let client = resolvedClient(), let next = client.update(snapshot: snapshot) else { return }
        if status == nil, !CheckNowLinePolicy.resumesAtLaunch(next) { return }
        apply(next, recordsRoundTrip: true)
    }

    // MARK: Demo pulls (AE8)

    /// Returns false when the variant cannot check (old Mac, paused, waiting).
    func pullDemo(
        snapshot: CompanionResolvedSnapshot, store: CompanionDemoModeStore, variant: CompanionDemoVariant,
        adopt: @escaping (CompanionResolvedSnapshot) -> Void
    ) -> Bool {
        guard case .requested(let state, _) = CheckNowMachine.begin(
            snapshot: snapshot, current: nil, requestID: CompanionDemoData.requestID, now: Date())
        else { return false }
        cancelReplay()
        demoState = state
        demoAdopt = adopt
        lastSnapshot = snapshot
        apply(CheckNowStatus.make(state: state, snapshot: snapshot, now: Date()), recordsRoundTrip: false)
        let generation = replayGeneration
        replay = Task { [weak self] in
            guard let model = self else { return }
            await store.replayCheckNow(variant) { step in
                await model.receiveDemo(step, generation: generation)
            }
        }
        return true
    }

    private func receiveDemo(_ step: CompanionDemoCheckNowStep, generation: Int) {
        guard generation == replayGeneration, var state = demoState else { return }
        let now = Date()
        state = CheckNowMachine.receive(step.receipt, into: state, now: now)
        if let snapshot = step.snapshot {
            // KTD14.7: the host adopts the finished generation before it shows "Just now".
            demoAdopt?(snapshot)
            lastSnapshot = snapshot
            state = CheckNowMachine.receive(snapshot, into: state, now: now)
        }
        demoState = state
        apply(CheckNowStatus.make(state: state, snapshot: lastSnapshot, now: now), recordsRoundTrip: false)
    }

    /// Demo switched on or off, or to another variant: nothing carries across.
    func reset() {
        cancelReplay()
        wake?.cancel()
        status = nil
        completedAt = nil
        inFlightEndedAt = nil
    }

    private func cancelReplay() {
        replayGeneration += 1
        replay?.cancel()
        replay = nil
        demoState = nil
        demoAdopt = nil
    }

    // MARK: State

    private func apply(_ next: CheckNowStatus, recordsRoundTrip: Bool) {
        let now = Date()
        if next.requestID != status?.requestID || !CheckNowLinePolicy.isCompletion(next.phase) {
            completedAt = nil
        }
        if status?.isInFlight == true, !next.isInFlight { inFlightEndedAt = now }
        if CheckNowLinePolicy.isCompletion(next.phase), completedAt == nil {
            completedAt = now
            if recordsRoundTrip {
                lastRoundTrip = PhoneCheckNowRoundTrip(requestedAt: next.askedAt, finishedAt: now)
            }
        }
        status = next
        scheduleWake()
    }

    /// One wake at the earlier of the request's own timeout and the completion hold's end;
    /// none once both have passed (review 2 #1).
    private func scheduleWake() {
        wake?.cancel()
        guard let at = CheckNowLinePolicy.nextWake(status: status, completedAt: completedAt, now: Date()) else { return }
        wake = Task { [weak self] in
            let delay = max(0, at.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.deadlinePassed()
        }
    }

    private func deadlinePassed() {
        if demoState == nil, let snapshot = lastSnapshot, let client = resolvedClient(),
           let next = client.update(snapshot: snapshot), next.requestID == status?.requestID {
            apply(next, recordsRoundTrip: true)
        } else if let state = demoState {
            apply(CheckNowStatus.make(state: state, snapshot: lastSnapshot, now: Date()), recordsRoundTrip: false)
        }
        tick += 1
    }

    /// Built on first use: Explore Demo and `--demo` launches never construct one.
    private func resolvedClient() -> CheckNowClient? {
        if let client { return client }
        let made = CheckNowClient.appGroup()
        client = .some(made)
        return made
    }
}

/// U9/U21: the inline status beside "Usage". While a check runs it is the Mac's receipt —
/// "Asking your Mac…", "Checking 3", "✓ Work · 2 of 3", "Updated just now" or a timeout
/// line — with one shared vessel through the request and its bounded completion animation.
/// Otherwise it is the freshness stamp, or, once dimmed, "Last update <time>" (CA-I2: the
/// full sentence sits on its own line under the header). It never dims with the surface (U21).
struct CheckNowStatusLine: View {
    let slot: CheckNowSlot
    /// The freshness line, or the demo banner's sample-data note standing in for it.
    let restingText: String
    let inFlightEndedAt: Date?
    let requestedAt: Date?
    let didUpdate: Bool
    let isDimmed: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate

    var body: some View {
        HStack(spacing: PhoneCardMetrics.statusGlyphGap) {
            loadingRow
            ZStack(alignment: .trailing) {
                content
                    .id(identity)
                    .transition(transition)
            }
            // CA-M1 (MOT-01): the outgoing line rose out of an unclipped slot; it now rolls
            // inside the slot's own bounds.
            .clipped()
            .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion), value: identity)
        }
        .font(.caption.monospacedDigit())
        // CA-I2: a large text size wraps the resting stamp onto a second line instead of
        // clipping it; the dimmed sentence no longer lives here.
        .lineLimit(slot == .freshness ? 2 : 1)
        .multilineTextAlignment(.trailing)
        // Approved F: reserve space for the large title and the 44pt Settings control.
        .frame(maxWidth: 190, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(slot == .freshness ? (isDimmed ? "dimmed" : "freshness") : "check-now")
        .accessibilityIdentifier("headroom.status-line")
    }

    private var isInFlight: Bool {
        if case .checkNow(_, true) = slot { true } else { false }
    }

    /// The Mac footer's receipt vocabulary: one line per state, so a new state crossfades in
    /// and a ticking stamp keeps its identity.
    private var identity: String {
        switch slot {
        case .freshness: "freshness"
        case .checkNow(.message(let text), _): text
        // CA-M1: a receipt keeps one identity; its name and count roll as two slots.
        case .checkNow(.receipt, _): "receipt"
        }
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case .freshness:
            Text(restingText)
                .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
        case .checkNow(.message(let text), _):
            Text(text == CheckNowCopy.justNow ? "Updated just now" : text)
                .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
        case .checkNow(.receipt(let line), _):
            // W4: the Mac footer's receipt line (`RefreshFooter.receiptLine`) — its 5pt gaps
            // and the count's extra 2pt — in the phone's type.
            HStack(spacing: 5) {
                if line.checked {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                        .accessibilityLabel("Checked")
                }
                // CA-M1: the name only moves when the account changes; "2 of 3 → 3 of 3"
                // rolls the count alone.
                rollSlot(id: line.text) {
                    Text(compactReceipt(line.text))
                        .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                }
                if let count = line.count {
                    rollSlot(id: count) {
                        Text(count)
                            .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                    }
                    .padding(.leading, 2)
                }
            }
        }
    }

    private func rollSlot<Content: View>(id: String, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            content()
                .id(id)
                .transition(transition)
        }
        .clipped()
        .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion), value: id)
    }

    private var accessibilityText: String {
        switch slot {
        case .freshness: restingText
        case .checkNow(.message(let text), _):
            text == CheckNowCopy.justNow ? "Updated just now" : text
        case .checkNow(.receipt(let line), _):
            [line.checked ? "Checked" : nil, line.text, line.count].compactMap { $0 }.joined(separator: " ")
        }
    }

    private func compactReceipt(_ text: String) -> String {
        guard text.hasPrefix("Checking ") else { return text }
        return text.replacingOccurrences(of: " accounts…", with: "")
            .replacingOccurrences(of: " account…", with: "")
    }

    /// Same vessel, ink transitions and wall-clock slosh as the desktop refresh pills.
    /// Only this child ticks; the header and cards don't observe animation frames.
    private var loadingRow: some View {
        let recipe = pillRecipe(at: pinnedDate ?? Date())
        // The outer clock only advances wipe/print/hold; the vessel owns the desktop's
        // 10fps slosh clock. Long requests must not keep a second 30fps clock alive.
        let deadline = isInFlight
            ? requestedAt?.addingTimeInterval(LoadingMotionConstants.ghostWipeDuration)
            : recipe.visibleUntil
        return LoadingTimeline(active: false, until: deadline,
                               interval: 1 / 30) { date in
            let frame = pillRecipe(at: date)
            if let pill = frame.pill {
                HalftoneVesselView(state: pill, width: 10, height: 16, columns: 4, rows: 8,
                                   sloshEndedAt: isInFlight ? nil : inFlightEndedAt)
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                    .transition(.opacity)
            }
        }
    }

    private func pillRecipe(at date: Date) -> PhoneRefreshPillRecipe {
        PhoneRefreshPillRecipe(isChecking: isInFlight, requestedAt: requestedAt,
                              endedAt: inFlightEndedAt, didUpdate: didUpdate,
                              now: date, reduceMotion: reduceMotion)
    }

    /// CA-M1 (MOT-01, the approved W4 mock): a 7pt roll, not a full line-height slide. The
    /// new line rises 7pt out of a 1.5pt blur on `settle`; the old one leaves 7pt up on the
    /// 80ms `partOut`, so the exit is the quieter half. Reduce Motion keeps a plain fade.
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .modifier(
                active: ReceiptRoll(offset: Self.rollDistance, blur: HeadroomMotion.revealBlur, opacity: 0),
                identity: ReceiptRoll(offset: 0, blur: 0, opacity: 1)),
            removal: AnyTransition.modifier(
                active: ReceiptRoll(offset: -Self.rollDistance, blur: 0, opacity: 0),
                identity: ReceiptRoll(offset: 0, blur: 0, opacity: 1))
                .animation(HeadroomMotion.partOut))
    }

    /// CA-M1: the W4 mock's `dist = 7`.
    private static let rollDistance: CGFloat = 7
}

private struct ReceiptRoll: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
