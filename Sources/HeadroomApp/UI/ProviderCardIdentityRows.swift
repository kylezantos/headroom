import SwiftUI
import HeadroomCore

// MARK: - Unified identity row

enum IdentityRowMetrics {
    static let markSlotWidth: CGFloat = 15
    static let spacing: CGFloat = 6
    static let meterContentInset = markSlotWidth + spacing
    /// L4B: the trailing gutter mirrors the label column instead of the mark. With the
    /// card's own 13pt padding this ends every identity row and every meter row 34pt from
    /// the card's right edge — the same 34pt the titles and meter labels start at — and
    /// leaves the provider mark hanging alone in its 13pt gutter.
    static let contentTrailingInset = meterContentInset
    /// C6A: one capsule height for everything that rides an identity line. Vertical padding
    /// could not deliver it — a 10.5pt tag's line box is taller than a 9.5pt pill's, so the
    /// same `vPad 3` produced 18/19/20 — and the drift is invisible until two capsules sit
    /// side by side. An explicit height with centred text cannot drift.
    static let capsuleHeight: CGFloat = 18
}

extension View {
    /// C6A: the one identity-line capsule. Each recipe keeps its own horizontal padding and
    /// fill; the height is not negotiable.
    func identityCapsule<Fill: ShapeStyle>(fill: Fill, horizontalPadding: CGFloat) -> some View {
        fixedSize()
            .frame(height: IdentityRowMetrics.capsuleHeight)
            .padding(.horizontal, horizontalPadding)
            .background(fill, in: Capsule())
    }
}

// MARK: - S2B status sentence

/// S2B: severity lives in the sentence's ink, so the mapping from state to ink is stated
/// once here rather than re-decided at each of the six former glyph sites.
enum StatusSentenceSeverity {
    /// Something needs the user, and the account is otherwise intact: sign in needed, a
    /// stale capture, a missing CLI, a handoff standing in the way.
    case attention
    /// The provider or the OS said no: a rejected sign-in, a denied read, a failed handoff.
    case critical
    /// A handoff is running. Not a severity at all — the row is mid-flight.
    case progress

    func ink(scheme: ColorScheme) -> Color {
        switch self {
        case .attention: ProviderStyle.severityColor(for: .low, scheme: scheme)
        case .critical: ProviderStyle.criticalText(scheme: scheme)
        case .progress: Color.secondary
        }
    }

    /// S2B: only the provider's own refusals earn the critical ink. Everything else is a
    /// state the user can walk out of, so it stays attention rather than shouting.
    static func forSetupOutcome(_ outcome: ProviderSetupOutcome?) -> StatusSentenceSeverity {
        switch outcome {
        case .codexRejectedAuth, .codexPermissionDenied, .codexUnsafePermissions,
             .grokRejectedAuth, .grokPermissionDenied, .grokUnsafePermissions:
            .critical
        default:
            .attention
        }
    }
}

/// S2B: the whole status line — no glyph, no state tag. 11.5 medium, inked by severity,
/// starting on the 34pt content axis (the 21pt inset inside the card's own 13pt padding),
/// wrapping freely and stopping at the card's own 13pt trailing edge.
struct StatusSentence: View {
    let text: String
    let severity: StatusSentenceSeverity
    /// False where the row supplies the axis itself — the waiting row's spinner occupies
    /// the 15pt mark slot, and the single-account setup notice sits above a guided card
    /// that starts at the card's own 13pt edge.
    var indented: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(severity.ink(scheme: scheme))
            .fixedSize(horizontal: false, vertical: true)
            // OA1: the sentence starts a line on the same content axis as the titles and
            // meter labels above it, so it hangs on the same optical edge they do.
            .opticalLeading(text, size: 11.5, weight: .medium)
            .padding(.leading, indented ? IdentityRowMetrics.meterContentInset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one identity treatment used for provider-name and account-name rows (KTD9).
/// The mark owns the only brand color; account metadata and state remain neutral.
struct IdentityRow: View {
    let providerID: ProviderID
    let title: String
    let planLabel: String?
    let isMenuBarAccount: Bool
    let isStale: Bool
    let email: String?
    let showsPersistentEmail: Bool
    let showsConnectedChip: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder var body: some View {
        let email = normalizedEmail
        if let tooltip = rowHelp(email: email) {
            row(email: email)
                .help(tooltip)
        } else {
            row(email: email)
        }
    }

    private func row(email: String?) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing) {
            ProviderLogoView(providerID: providerID, size: IdentityRowMetrics.markSlotWidth)
            titleText
            if let planDisplayName {
                Text(planDisplayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    // T1A/C6A: the capsule reads as a peer of the title beside it rather than
                    // a hairline sticker stuck to it — now from an explicit height, so it
                    // cannot drift away from the tags sharing this line.
                    .identityCapsule(
                        fill: ClaudeSetupStyle.stepBackground(dark: scheme == .dark),
                        horizontalPadding: 5
                    )
            }
            if showsPersistentEmail, let email {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            Spacer(minLength: 6)
            if isStale {
                staleTag
            }
            if showsConnectedChip {
                ConnectedChip()
                    .transition(.connectedChip(reduceMotion: reduceMotion))
            }
        }
        // L4B: trailing controls stop level with the meter rows below them.
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentity(email: email))
    }

    /// T1A sized this off Kyle's Paper mock at 15pt on the `accountTitle` ink so the name
    /// labels its meters instead of competing with the popover's own 20pt bold header. G1
    /// restored `.semibold` — `.medium` on a recessive grey lost the row's anchor — and the
    /// ink is now the user's `AccountTitleInk` choice (neutral grey or the provider's brand
    /// tint). Kerning is unchanged throughout.
    private var titleText: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .kerning(-0.15)
            .accountTitleInk(for: providerID)
            .lineLimit(1)
            .truncationMode(.tail)
            // OA1: "Personal" and "Work" carry side bearings 0.66pt apart at this size, so
            // without this the title column visibly jitters account to account.
            .opticalLeading(title, size: 15, weight: .semibold)
    }

    /// L5D: the main account carries no visible marker. Order already says it — main is
    /// always its provider's first row — and a second capsule beside the plan badge made a
    /// busy title cluster busier, so the fact moves to this row's tooltip and to VoiceOver.
    /// One `.help` per row: nested help modifiers let the innermost win on macOS, so a
    /// separate tooltip on the title would swallow the email the row has always shown.
    private func rowHelp(email: String?) -> String? {
        switch (email, isMenuBarAccount) {
        case (let email?, true): return "\(email)\n\(Self.mainAccountHelp)"
        case (let email?, false): return email
        case (nil, true): return Self.mainAccountHelp
        case (nil, false): return nil
        }
    }

    private var normalizedEmail: String? {
        guard let email, !email.isEmpty else { return nil }
        return email
    }

    /// Raw ids (`prolite`, `SuperGrok`) never reach the badge — Core owns the humanizing
    /// so the lenient provider models keep their verbatim value (#709).
    private var planDisplayName: String? {
        PlanLabelPresentation.displayName(planLabel)
    }

    /// S2B removed the status glyphs and left severity to the sentence's ink — but a
    /// transient-stale row renders no sentence at all (`stateContent` keeps its dimmed
    /// meters), so this tag survives as that state's only visible signal. C6A gives it the
    /// same 18pt as the plan pill beside it.
    private var staleTag: some View {
        Text("Stale")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .identityCapsule(fill: Color.secondary.opacity(0.18), horizontalPadding: 5)
    }

    /// L5D: with the badge gone, the row tooltip and this VoiceOver phrase are the only
    /// places the fact is stated — keep them in step.
    static let mainAccountHelp = "Main account — shown in the menu bar and widgets"

    private func accessibilityIdentity(email: String?) -> String {
        var parts = [title]
        if let planDisplayName { parts.append("\(planDisplayName) plan") }
        if isMenuBarAccount { parts.append("Main account, shown in the menu bar and widgets") }
        if isStale { parts.append("Stale") }
        if let email { parts.append("signed in as \(email)") }
        if showsConnectedChip { parts.append("Connected") }
        return parts.joined(separator: ", ")
    }
}

private extension AnyTransition {
    /// M8A: a sign-in payoff earns a little arrival, so the chip enters on opacity plus a
    /// 0.96 scale; it leaves on opacity alone, because an exit that announces itself twice
    /// reads as an error. S2A drops the scale under Reduce Motion and keeps the fade.
    static func connectedChip(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
    }
}

private struct ConnectedChip: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Connected")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
        // C6A: was the tallest of the three capsules at ~19–20pt; now the same 18 as the rest.
        .identityCapsule(
            fill: ClaudeSetupStyle.connectedBackground(dark: scheme == .dark),
            horizontalPadding: 8
        )
    }
}

// MARK: - Account section (multi-account rows)

/// One account's section inside a multi-account provider card. The round-6 unified identity
/// row carries its title and account-scoped state; a 22pt inter-account gap plus the meter
/// inset provides the G3 hierarchy without a band or divider (R15, R18, KTD18).
struct AccountSectionView: View {
    let entry: ProviderAccountEntry
    let providerDisplayName: String
    let identityTitle: String
    let showsPersistentEmail: Bool
    let percentageMode: UsagePercentageMode
    let meterStyle: MeterStyle
    let now: Date
    /// The selected primary account (`entries.first`) is the one the menu bar and widgets
    /// follow; its identity row carries the mark that explains which login drives the glyph.
    let isMenuBarAccount: Bool
    let showsStopWaiting: Bool
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsConnectedChip = false

    private var snapshot: UsageSnapshot { entry.snapshot }
    private var account: ProviderAccount { entry.account }

    var body: some View {
        // G3/R4A: 6pt binds the identity to its meters; the 26pt inter-section gap in
        // `multiAccountBody` does the separating (proximity, not chrome). 6-inside against
        // 12-to-the-action-row is the 2× the grouping rule wants — the old 7/8 was 1.14×,
        // which read as four evenly stacked lines. The whole section is one VoiceOver
        // container so the rotor can jump account-to-account instead of the meters floating
        // free of their identity row.
        VStack(alignment: .leading, spacing: 6) {
            identityRow
            // M4A/S2A: the innermost scope around the switching body, so the crossfade —
            // not the section's height change — is what this animation drives. The wrapper
            // repeats the parent's 6pt spacing so it stays layout-neutral for the
            // multi-view `signInContent` branch. Fill and numeral roll are `UsageBarView`'s.
            VStack(alignment: .leading, spacing: 6) {
                stateContent
            }
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion),
                value: snapshot.freshness
            )
            if showsStopWaiting,
               SetupSessions.state(for: account) != .blockedByOpenHandoff {
                // P4C/R4A/B3: the section's one action row, leading-aligned at the mark
                // column. The stack's own 6pt supplies half of R4A's 12pt gap, so the row
                // adds the other 6, and it takes no trailing inset — a leading row ends
                // wherever its last chip ends.
                CardActionRow(topPadding: 6) {
                    StopWaitingButton(account: account, style: .chip(.small))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(identityTitle) account")
        // M4A/S2A: the section's own geometry — its height inside the 22pt account stack —
        // is travel, so Reduce Motion snaps it while the body above still crossfades.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
            value: snapshot.freshness
        )
        .onChange(of: snapshot.freshness) { evaluateConnectedPayoff() }
        .onAppear {
            evaluateConnectedPayoff()
            SetupSessions.announceFailureIfNeeded(for: account)
        }
        .onChange(of: SetupSessions.state(for: account)) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    private var identityRow: some View {
        return IdentityRow(
            providerID: account.providerID,
            title: identityTitle,
            planLabel: snapshot.planLabel,
            isMenuBarAccount: isMenuBarAccount,
            isStale: providerCardHasTransientStaleState(snapshot),
            email: snapshot.accountEmail,
            showsPersistentEmail: showsPersistentEmail,
            showsConnectedChip: showsConnectedChip
        )
    }

    @ViewBuilder private var stateContent: some View {
        Group {
            switch snapshot.freshness {
            case .pending:
                accountSkeleton
            case .live:
                bars(dimmed: false)
            case .stale(let reason):
                if reason.isPermanent {
                    signInContent(reason)
                } else {
                    bars(dimmed: true)
                }
            }
        }
        .transition(.opacity)
    }

    private func bars(dimmed: Bool) -> some View {
        // Multi-account meters go chipless: critical windows paint the numeral instead of
        // stacking a "Low" chip beside the identity row's account-scoped state.
        // M4A: account sections only ever render real accounts — the Appearance specimen is
        // single-account and never reaches here — so the arrival key is unconditional.
        UsageBarsStack(
            windows: snapshot.windows,
            percentageMode: percentageMode,
            now: now,
            dimmed: dimmed,
            meterStyle: meterStyle,
            chiplessCriticalInk: true,
            arrivalKey: account.key
        )
        .padding(.leading, IdentityRowMetrics.meterContentInset)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }

    /// Permanent failure on one account: one inked sentence on its own line (S2B — no glyph,
    /// no tag), then one leading-aligned action row (P4C/B3) — so a dead login never
    /// dominates its healthy siblings and no control hides at the end of a sentence. While
    /// the handoff Terminal is open it becomes a quiet waiting row with a real-progress
    /// spinner (bound to the retry cycle, not decorative).
    @ViewBuilder private func signInContent(_ reason: FailureReason) -> some View {
        let recoveryPresentation = reason.providerSetupOutcome?.recoveryPresentation
        let setupState = SetupSessions.state(for: account)
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let refusalMessage = setupHandoffRefusalMessage(for: setupState) {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusSentence(text: refusalMessage, severity: .attention)
                        CardActionRow {
                            StopWaitingButton(account: account, style: .chip(.small))
                        }
                    }
                } else if case .blockedByProviderLogin = setupState {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusSentence(
                            text: "Another \(providerDisplayName) sign-in is open",
                            severity: .attention
                        )
                        CardActionRow {
                            Button("Continue Setup") { SetupSessions.continueSetup(for: account) }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                                .accessibilityLabel("Continue \(providerDisplayName) setup for \(account.label)")
                        }
                    }
                } else if isWaitingForSetup {
                    VStack(alignment: .leading, spacing: 0) {
                        // S2B: the spinner is the one thing besides a brand mark allowed in
                        // the mark column — it reports progress, not severity — and taking
                        // the 15pt slot still lands the sentence on the 34pt content axis.
                        HStack(alignment: .top, spacing: IdentityRowMetrics.spacing) {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: IdentityRowMetrics.markSlotWidth, height: 15)
                            StatusSentence(
                                text: SetupSessions.mode(for: account) == .deviceCode
                                    ? "Waiting for device code…"
                                    : "Waiting for sign-in…",
                                severity: .progress,
                                indented: false
                            )
                        }
                        // B3A: the bare accent label is gone — a waiting row's one control
                        // now carries the same resting container as the sign-in chip.
                        CardActionRow {
                            Button("Check Now") { onRetry() }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        StatusSentence(
                            text: SetupSessions.failureMessage(for: account) ?? reason.message,
                            severity: SetupSessions.failureMessage(for: account) != nil
                                ? .critical
                                : .forSetupOutcome(reason.providerSetupOutcome)
                        )
                        // P4C/B3: both actions share one row, and a leading row reads in
                        // reading order — the primary first, its alternative after it.
                        CardActionRow {
                            Button {
                                if let recoveryPresentation {
                                    SetupSessions.performRecovery(
                                        recoveryPresentation.primaryAction,
                                        for: account,
                                        onRetry: onRetry
                                    )
                                } else {
                                    SetupSessions.openSetup(for: account, onRetry: onRetry)
                                }
                            } label: {
                                Text(recoveryPresentation?.primaryLabel ?? "Sign In")
                            }
                            .buttonStyle(SetupChipButtonStyle(size: .small))
                            .accessibilityLabel("\(recoveryPresentation?.primaryLabel ?? "Sign In") for \(account.label)")
                            if let secondaryLabel = recoveryPresentation?.secondaryLabel,
                               let secondaryAction = recoveryPresentation?.secondaryAction {
                                Button(secondaryLabel) {
                                    SetupSessions.performRecovery(
                                        secondaryAction,
                                        for: account,
                                        onRetry: onRetry
                                    )
                                }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                            } else if SetupSessions.failureMessage(for: account) != nil {
                                Button("Check Now", action: onRetry)
                                    .buttonStyle(SetupChipButtonStyle(size: .small))
                            }
                        }
                    }
                }
            }
            if !snapshot.windows.isEmpty {
                bars(dimmed: true)
            }
        }
    }

    private var isWaitingForSetup: Bool {
        SetupSessions.isWaiting(for: account)
    }

    /// Account-scoped setup payoff: the chip belongs to the row whose login completed.
    private func evaluateConnectedPayoff() {
        guard case .live = snapshot.freshness, SetupSessions.isConnected(account) else { return }
        guard !showsConnectedChip else { return }
        // M8A/S2A: as in `ProviderCardView` — the transition owns the scale, so this stays
        // a crossfade and the fade survives Reduce Motion.
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion)) {
            showsConnectedChip = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)) {
                showsConnectedChip = false
            }
            SetupSessions.settle(for: account)
        }
    }

    private var accountSkeleton: some View {
        SkeletonMeter(labelWidth: 72, valueWidth: 38, format: meterStyle.format)
            .padding(.leading, IdentityRowMetrics.meterContentInset)
            .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
    }
}
