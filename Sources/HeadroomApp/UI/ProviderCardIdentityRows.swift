import SwiftUI
import HeadroomCore

// MARK: - Unified identity row

enum IdentityRowMetrics {
    static let markSlotWidth: CGFloat = 15
    static let spacing: CGFloat = 6
    static let meterContentInset = markSlotWidth + spacing
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

    @ViewBuilder var body: some View {
        if let email = normalizedEmail {
            row(email: email)
                .help(email)
        } else {
            row(email: nil)
        }
    }

    private func row(email: String?) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing) {
            ProviderLogoView(providerID: providerID, size: IdentityRowMetrics.markSlotWidth)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.15)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let planDisplayName {
                Text(planDisplayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        ClaudeSetupStyle.stepBackground(dark: scheme == .dark),
                        in: Capsule()
                    )
                    .fixedSize()
            }
            if isMenuBarAccount {
                mainTag
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
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentity(email: email))
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

    /// The primary account's marker. A `menubar.rectangle` glyph read as a stray icon at
    /// this size, so it is a word: same geometry as the plan badge, outlined rather than
    /// tinted so it separates from both the tertiary plan badge and the filled stale tag
    /// while account metadata stays neutral — the mark owns the only brand color (KTD9).
    private var mainTag: some View {
        Text("Main")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(ClaudeSetupStyle.stepBackground(dark: scheme == .dark), in: Capsule())
            .overlay(Capsule().strokeBorder(ClaudeSetupStyle.stepBorder(dark: scheme == .dark), lineWidth: 1))
            .fixedSize()
            .help("Main account — shown in the menu bar and widgets")
            .accessibilityLabel("Main account, shown in the menu bar")
    }

    private var staleTag: some View {
        Text("Stale")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.18), in: Capsule())
    }

    private func accessibilityIdentity(email: String?) -> String {
        var parts = [title]
        if let planDisplayName { parts.append("\(planDisplayName) plan") }
        if isMenuBarAccount { parts.append("Main account, shown in the menu bar") }
        if isStale { parts.append("Stale") }
        if let email { parts.append("signed in as \(email)") }
        if showsConnectedChip { parts.append("Connected") }
        return parts.joined(separator: ", ")
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
            stateContent
            if showsStopWaiting,
               SetupSessions.state(for: account) != .blockedByOpenHandoff {
                HStack {
                    Spacer(minLength: 0)
                    StopWaitingButton(account: account)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(identityTitle) account")
        .animation(reduceMotion ? nil : HeadroomMotion.valueSpring, value: snapshot.freshness)
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
        UsageBarsStack(
            windows: snapshot.windows,
            percentageMode: percentageMode,
            now: now,
            dimmed: dimmed,
            meterStyle: meterStyle,
            chiplessCriticalInk: true
        )
        .padding(.leading, IdentityRowMetrics.meterContentInset)
    }

    /// Permanent failure on one account: a single compact row — the reason, then the
    /// Terminal handoff — so one dead login never dominates its healthy siblings.
    /// While the handoff Terminal is open it becomes a quiet waiting row with a
    /// real-progress spinner (bound to the retry cycle, not decorative).
    @ViewBuilder private func signInContent(_ reason: FailureReason) -> some View {
        let recoveryPresentation = reason.providerSetupOutcome?.recoveryPresentation
        let setupState = SetupSessions.state(for: account)
        VStack(alignment: .leading, spacing: 7) {
            if let refusalMessage = setupHandoffRefusalMessage(for: setupState) {
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(refusalMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                    Spacer(minLength: 6)
                    StopWaitingButton(account: account)
                }
            } else if case .blockedByProviderLogin = setupState {
                HStack(spacing: 7) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Another \(providerDisplayName) sign-in is open")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("Continue setup") { SetupSessions.continueSetup(for: account) }
                        .buttonStyle(SetupChipButtonStyle())
                        .accessibilityLabel("Continue \(providerDisplayName) setup for \(account.label)")
                }
            } else if isWaitingForSetup {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(SetupSessions.mode(for: account) == .deviceCode
                         ? "Waiting for device code…"
                         : "Waiting for sign-in…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("Check now") { onRetry() }
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                    Text(SetupSessions.failureMessage(for: account) ?? reason.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
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
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(SetupChipButtonStyle())
                    .accessibilityLabel("\(recoveryPresentation?.primaryLabel ?? "Sign in") for \(account.label)")
                }
                if let secondaryLabel = recoveryPresentation?.secondaryLabel,
                   let secondaryAction = recoveryPresentation?.secondaryAction {
                    Button(secondaryLabel) {
                        SetupSessions.performRecovery(
                            secondaryAction,
                            for: account,
                            onRetry: onRetry
                        )
                    }
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
                } else if SetupSessions.failureMessage(for: account) != nil {
                    Button("Check now", action: onRetry)
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
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
        withAnimation(reduceMotion ? nil : HeadroomMotion.valueSpring) {
            showsConnectedChip = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(reduceMotion ? nil : HeadroomMotion.settle) {
                showsConnectedChip = false
            }
            SetupSessions.settle(for: account)
        }
    }

    private var accountSkeleton: some View {
        SkeletonMeter(labelWidth: 72, valueWidth: 38, format: meterStyle.format)
            .padding(.leading, IdentityRowMetrics.meterContentInset)
    }
}
