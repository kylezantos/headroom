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
    #endif

    @ObservationIgnored private var client: CheckNowClient??
    @ObservationIgnored private var lastSnapshot: CompanionResolvedSnapshot?
    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var replay: Task<Void, Never>?
    /// Review #10 for the demo path: a newer pull or a reset drops an older replay's steps.
    @ObservationIgnored private var replayGeneration = 0
    @ObservationIgnored private var demoState: CheckNowRequestState?
    @ObservationIgnored private var demoAdopt: ((CompanionResolvedSnapshot) -> Void)?

    /// What the slot under the title shows right now.
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

    /// One wake at the earlier of the request's own timeout and the completion hold's end.
    private func scheduleWake() {
        wake?.cancel()
        let dates = [status?.nextDeadline, CheckNowLinePolicy.revertsAt(status: status, completedAt: completedAt)]
        guard let at = dates.compactMap({ $0 }).min() else { return }
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

/// U9/U21: the one line under "Usage". While a check runs it is the Mac's receipt —
/// "Asking your Mac…", "Checking 3 accounts…", "✓ Work · 2 of 3", "Just now" or a timeout
/// line — with the shared loading row at its leading edge only while a request is in flight
/// (KTD16). Otherwise it is the freshness stamp, or the dimmed "No update from your Mac
/// since <time>" in the same slot (R10). It never dims with the surface (U21).
struct CheckNowStatusLine: View {
    let slot: CheckNowSlot
    /// The freshness line, or the demo banner's sample-data note standing in for it.
    let restingText: String
    let inFlightEndedAt: Date?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate

    var body: some View {
        // The status glyph's gap (`PhoneCardMetrics.statusGlyphGap`): the loading row stands
        // where a line's leading glyph does.
        HStack(spacing: PhoneCardMetrics.statusGlyphGap) {
            loadingRow
            ZStack(alignment: .leading) {
                content
                    .id(identity)
                    .transition(transition)
            }
            .animation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion), value: identity)
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        // The large-subtitle slot centres its item; the line belongs under the title's
        // leading edge, where the native subtitle sat.
        .frame(maxWidth: .infinity, alignment: .leading)
        // Measured on the iOS 26.5 simulator: the toolbar item sits 6pt inside the title's
        // leading edge; this puts the line's first glyph back under "Usage".
        .padding(.leading, -6)
        .accessibilityElement(children: .combine)
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
        case .checkNow(.receipt(let line), _): "\(line.text)|\(line.count ?? "")"
        }
    }

    @ViewBuilder private var content: some View {
        switch slot {
        case .freshness:
            Text(restingText)
                .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
        case .checkNow(.message(let text), _):
            Text(text)
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
                Text(line.text)
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                if let count = line.count {
                    Text(count)
                        .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                        .padding(.leading, 2)
                }
            }
        }
    }

    /// KTD16: the phone's existing check-in-flight object (`StatusScreen`'s Refresh), which
    /// finishes its wave after the request lands and then leaves.
    private var loadingRow: some View {
        let recipe = LoadingCheckRecipe(
            isChecking: isInFlight, endedAt: inFlightEndedAt, now: pinnedDate ?? Date(), reduceMotion: reduceMotion)
        return LoadingTimeline(active: isInFlight && !reduceMotion, until: recipe.waveEnd) { date in
            let frame = LoadingCheckRecipe(
                isChecking: isInFlight, endedAt: inFlightEndedAt, now: date, reduceMotion: reduceMotion)
            if frame.isWorking {
                HalftonePillRow(pills: frame.pills, sloshEndedAt: inFlightEndedAt)
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                    .transition(.opacity)
            }
        }
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity))
    }
}
