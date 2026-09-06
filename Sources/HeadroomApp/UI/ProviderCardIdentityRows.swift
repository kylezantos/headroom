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
                    // T1A: 3pt vertical takes the capsule to ~16pt tall so it reads as a peer
                    // of the title beside it rather than a hairline sticker stuck to it.
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        ClaudeSetupStyle.stepBackground(dark: scheme == .dark),
                        in: Capsule()
                    )
                    .fixedSize()
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

    /// T1A: measured off Kyle's Paper mock — 15pt stays, but the weight drops to `.medium`
    /// on the `accountTitle` ink so the name labels its meters instead of competing with the
    /// popover's own 20pt bold header. Kerning is unchanged.
    private var titleText: some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .kerning(-0.15)
            .foregroundStyle(ProviderStyle.accountTitleInk(scheme: scheme))
            .lineLimit(1)
            .truncationMode(.tail)
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

    private var staleTag: some View {
        Text("Stale")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.18), in: Capsule())
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(ClaudeSetupStyle.connectedBackground(dark: scheme == .dark), in: Capsule())
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
    @Environment(\.colorScheme) private var scheme
    @State private var showsConnectedChip = false

    private var snapshot: UsageSnapshot { entry.snapshot }
    private var account: ProviderAccount { entry.account }

    var body: some View {
        // G3: 7pt binds the identity to its meters; the 22pt inter-section gap in
        // `multiAccountBody` does the separating (proximity, not chrome). The whole section
        // is one VoiceOver container so the rotor can jump account-to-account instead of
        // the meters floating free of their identity row.
        VStack(alignment: .leading, spacing: 7) {
            identityRow
            // M4A/S2A: the innermost scope around the switching body, so the crossfade —
            // not the section's height change — is what this animation drives. The wrapper
            // repeats the parent's 7pt spacing so it stays layout-neutral for the
            // multi-view `signInContent` branch. Fill and numeral roll are `UsageBarView`'s.
            VStack(alignment: .leading, spacing: 7) {
                stateContent
            }
            .animation(
                HeadroomMotion.resolved(HeadroomMotion.valueSpring, .crossfade, reduceMotion: reduceMotion),
                value: snapshot.freshness
            )
            if showsStopWaiting,
               SetupSessions.state(for: account) != .blockedByOpenHandoff {
                // P4C: the section's one action row. The stack's own 7pt already sets the
                // gap above it, so it adds none, and it stops at the content trailing edge
                // so it lines up with the sign-in chips and the meters.
                CardActionRow(topPadding: 0) {
                    StopWaitingButton(account: account, style: .chip(.small))
                }
                .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
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

    /// Permanent failure on one account: the reason on its own line, then one
    /// trailing-aligned action row (P4C) — so a dead login never dominates its healthy
    /// siblings and no control hides at the end of a sentence. While the handoff Terminal
    /// is open it becomes a quiet waiting row with a real-progress spinner (bound to the
    /// retry cycle, not decorative).
    @ViewBuilder private func signInContent(_ reason: FailureReason) -> some View {
        let recoveryPresentation = reason.providerSetupOutcome?.recoveryPresentation
        let setupState = SetupSessions.state(for: account)
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let refusalMessage = setupHandoffRefusalMessage(for: setupState) {
                    VStack(alignment: .leading, spacing: 0) {
                        messageRow(systemImage: "terminal", glyphInk: .secondary) {
                            Text(refusalMessage)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                        }
                        CardActionRow {
                            StopWaitingButton(account: account, style: .chip(.small))
                        }
                    }
                } else if case .blockedByProviderLogin = setupState {
                    VStack(alignment: .leading, spacing: 0) {
                        messageRow(systemImage: "terminal", glyphInk: .secondary) {
                            Text("Another \(providerDisplayName) sign-in is open")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        CardActionRow {
                            Button("Continue setup") { SetupSessions.continueSetup(for: account) }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                                .accessibilityLabel("Continue \(providerDisplayName) setup for \(account.label)")
                        }
                    }
                } else if isWaitingForSetup {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(SetupSessions.mode(for: account) == .deviceCode
                                 ? "Waiting for device code…"
                                 : "Waiting for sign-in…")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        // B3A: the bare accent label is gone — a waiting row's one control
                        // now carries the same resting container as the sign-in chip.
                        CardActionRow {
                            Button("Check now") { onRetry() }
                                .buttonStyle(SetupChipButtonStyle(size: .small))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        messageRow(
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            glyphInk: ProviderStyle.severityColor(for: .low, scheme: scheme)
                        ) {
                            Text(SetupSessions.failureMessage(for: account) ?? reason.message)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        // P4C: the secondary recovery used to hang on its own line beneath a
                        // filled chip. Both actions share one row now, the primary last.
                        CardActionRow {
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
                                Button("Check now", action: onRetry)
                                    .buttonStyle(SetupChipButtonStyle(size: .small))
                            }
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
                                Label(recoveryPresentation?.primaryLabel ?? "Sign in", systemImage: "terminal")
                            }
                            .buttonStyle(SetupChipButtonStyle(size: .small))
                            .accessibilityLabel("\(recoveryPresentation?.primaryLabel ?? "Sign in") for \(account.label)")
                        }
                    }
                }
            }
            // P4C: messages and their action row stop level with the meter rows below —
            // the 21pt content trailing edge, 34pt in from the card's own edge.
            .padding(.trailing, IdentityRowMetrics.contentTrailingInset)
            if !snapshot.windows.isEmpty {
                bars(dimmed: true)
            }
        }
    }

    /// P4C: the message half of a state row — glyph and copy on their own line, free to wrap
    /// now that no control shares the line's trailing end.
    private func messageRow<Message: View>(
        systemImage: String,
        glyphInk: Color,
        @ViewBuilder message: () -> Message
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(glyphInk)
            message()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
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
