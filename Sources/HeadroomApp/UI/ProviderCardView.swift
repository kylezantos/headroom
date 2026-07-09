import SwiftUI
import AppKit
import HeadroomCore

/// One provider's card (U7). Renders the explicit states off `snapshot.freshness`:
/// `.pending` first-run skeleton, `.live`, transient stale (last data kept, marked with
/// a "Stale" pill), permanent needs-reauth (actionable command), and — for Claude's
/// trust-required first run — the guided Connect/Waiting onboarding cards
/// (`ClaudeSetupViews`, transferred from the HTML mockup Jul 2026).
///
/// Type + spacing were tuned in the mockup: 16pt bold card titles, 14pt vertical rhythm
/// between rows, 20pt card padding. Plan pills and the "Plan renews" row were removed
/// in the density audit (too much detail for the glance payload); the plan pill is kept
/// commented for easy restore.
///
/// UI craft (audit): the card is a single lighter translucent layer instead of a second
/// `.regularMaterial` stacked on the popover's glass, so Tahoe's Liquid Glass reads
/// cleanly rather than muddying (UI-07).
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    let now: Date
    let onRetrySetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var showsConnectedChip = false

    var body: some View {
        Group {
            if isClaudeTrustSetup {
                if ClaudeSetupSession.openedSetupAt != nil {
                    ClaudeWaitingCard(
                        onCheckNow: onRetrySetup,
                        onReopen: { ClaudeSetupSession.openSetup(onRetry: onRetrySetup) }
                    )
                } else {
                    ClaudeConnectCard(
                        onOpenSetup: { ClaudeSetupSession.openSetup(onRetry: onRetrySetup) }
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    content
                }
            }
        }
        // 16pt pad / 11pt rhythm — squeezed toward the large widget's density
        // (10/9 at smaller type) from the earlier 20/14.
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10)
        // A refresh replacing the pending skeleton (or a stale card recovering) cross-fades
        // and springs its height change rather than hard-cutting — the arrival of a poll
        // cycle, felt not flashed. Snaps instead under Reduce Motion.
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: snapshot.freshness)
        .onAppear { evaluateConnectedPayoff() }
        .onChange(of: snapshot.freshness) { evaluateConnectedPayoff() }
    }

    /// The guided-setup payoff: when Claude goes live after the user opened setup, stop
    /// the pending auto-retries (each spawns a 20–30s CLI cycle — without this the
    /// footer reads "Refreshing…" for minutes after success) and show the "Connected"
    /// chip briefly. One-shot: the session flag clears with the dismissal.
    private func evaluateConnectedPayoff() {
        guard providerID == .claude, case .live = snapshot.freshness,
              ClaudeSetupSession.openedSetupAt != nil else { return }
        ClaudeSetupSession.cancelRetries()
        guard !showsConnectedChip else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showsConnectedChip = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { showsConnectedChip = false }
            ClaudeSetupSession.openedSetupAt = nil
        }
    }

    /// Claude's folder-trust first run — the one failure that gets the guided flow.
    private var isClaudeTrustSetup: Bool {
        guard providerID == .claude, case .stale(let reason) = snapshot.freshness else { return false }
        return reason.isPermanent && reason.message == ClaudeUsageWorkspace.trustRequiredMessage
    }

    /// The per-card "Updated N min ago" was removed here — both providers poll on one
    /// cycle, so it reads once in the popover header (PopoverView) instead of twice.
    /// Header mirrors the large widget's recipe (icon ≈ 1.33× the title size, title in
    /// the shared brand text-accent) so popover and widgets read as one family.
    private var header: some View {
        HStack(spacing: 6) {
            ProviderLogoView(providerID: providerID, size: 21)
            Text(displayName)
                .font(.system(size: 16, weight: .semibold))
                .kerning(-0.2)
                .foregroundStyle(ProviderStyle.textAccent(for: providerID, scheme: scheme))
            // Plan tag omitted (density audit — unnecessary in this version):
            // if let plan = snapshot.planLabel {
            //     Text(plan.capitalized)
            //         .font(.caption2)
            //         .lineLimit(1)
            //         .padding(.horizontal, 6).padding(.vertical, 2)
            //         .background(ProviderStyle.accent(for: providerID).opacity(0.18), in: Capsule())
            // }
            Spacer(minLength: 6)
            if showsConnectedChip {
                connectedChip
                    .transition(.opacity)
            }
        }
    }

    private var connectedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Connected")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
        .padding(.horizontal, 8).padding(.vertical, 2.5)
        .background(ClaudeSetupStyle.connectedBackground(dark: scheme == .dark), in: Capsule())
    }

    @ViewBuilder private var content: some View {
        Group {
            switch snapshot.freshness {
            case .pending:
                pendingSkeleton
            case .live:
                bars(dimmed: false)
            case .stale(let reason):
                staleContent(reason)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func staleContent(_ reason: FailureReason) -> some View {
        if reason.isPermanent {
            actionable(reason)
            if !snapshot.windows.isEmpty { bars(dimmed: true) }
        } else {
            bars(dimmed: true)
            stalePill(reason)
        }
    }

    @ViewBuilder private func bars(dimmed: Bool) -> some View {
        if snapshot.windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 11) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(window: window, now: now, dimmed: dimmed)
                }
            }
        }
    }

    /// Varied widths (audit UI-13): real content isn't two identical bars, so the
    /// skeleton previews the true shape rather than reading as "broken". The wait names
    /// the ~20–30s first Claude poll so the delay feels intentional, not hung.
    private var pendingSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 150, height: 6)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 7)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 96, height: 6)
            Text("Fetching usage…")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// Permanent failure the user can fix (UI-05) that is *not* the guided Claude setup
    /// (that one renders the Connect/Waiting cards): message + compact copyable command.
    @ViewBuilder private func actionable(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
            if let command = recoveryCommand(for: reason) {
                commandRecovery(command: command)
            }
        }
    }

    private func commandRecovery(command: String) -> some View {
        HStack(spacing: 8) {
            Text("$ \(command)")
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button(action: { copyCommand(command) }) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 4, verticalPadding: 4))
            .foregroundStyle(.secondary)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(ClaudeSetupStyle.codeBackground(dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Small "Stale" flag + the transient reason, so a network blip is explicit rather
    /// than communicated only by a faint bar (which also reads as "disabled").
    private func stalePill(_ reason: FailureReason) -> some View {
        HStack(spacing: 6) {
            Text("Stale")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.20), in: Capsule())
            Text(reason.message)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The CLI command that recovers each provider (nil for unknown providers).
    private func recoveryCommand(for reason: FailureReason) -> String? {
        switch providerID {
        case .claude: return "claude"
        case .codex: return "codex login"
        default: return nil
        }
    }

    private func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
