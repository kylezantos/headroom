import SwiftUI
import AppKit
import HeadroomCore

/// One provider's card (U7). Renders the four explicit states from the design review
/// off `snapshot.freshness`: `.pending` first-run skeleton, `.live`, transient stale
/// (last data kept, marked with a "Stale" pill), and permanent needs-reauth/scope (an
/// actionable message with a one-tap command to copy). Shows the plan-renewal date or a
/// tappable "add date" affordance.
///
/// UI craft (audit): the card is a single lighter translucent layer instead of a second
/// `.regularMaterial` stacked on the popover's glass, so Tahoe's Liquid Glass reads
/// cleanly rather than muddying (UI-07).
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    let renewalDate: Date?
    let now: Date
    let onOpenSettings: () -> Void
    let onRetrySetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { ProviderStyle.accent(for: providerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            renewalRow
        }
        .padding(12)
        // Raised tile, concentric with the popover shell (R22, 12pt inset → 10pt). Adapts its
        // elevation cue per appearance — lit rim in dark, shadow+fill in light (UI-07, R-depth).
        .raisedTile(cornerRadius: 10)
        // A refresh replacing the pending skeleton (or a stale card recovering) cross-fades
        // and springs its height change rather than hard-cutting — the arrival of a poll
        // cycle, felt not flashed. Snaps instead under Reduce Motion.
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: snapshot.freshness)
    }

    /// The per-card "Updated N min ago" was removed here — both providers poll on one
    /// cycle, so it now reads once in the popover header (PopoverView) instead of twice.
    /// A provider that's individually stale still says so via its own stale pill below.
    private var header: some View {
        HStack(spacing: 8) {
            ProviderLogoView(providerID: providerID, size: 17)
            Text(displayName).font(.headline)
            if let plan = snapshot.planLabel {
                Text(plan.capitalized)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 6)
        }
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
            VStack(spacing: 10) {
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

    /// Permanent failure the user can fix (UI-05): make the guided setup path primary
    /// and keep the command as a compact fallback.
    @ViewBuilder private func actionable(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
            if shouldOfferClaudeSetup(for: reason) {
                claudeSetupRecovery(reason)
            } else if let command = recoveryCommand(for: reason) {
                commandRecovery(command: command, reason: reason)
            }
        }
    }

    private func claudeSetupRecovery(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open setup, approve Claude's trust prompt, then return here. Headroom will retry automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: openClaudeSetup) {
                    Label("Open Setup", systemImage: "terminal")
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 8, verticalPadding: 4))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

                Spacer(minLength: 6)

                Button(action: { copyCommand(for: reason) }) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 4, verticalPadding: 4))
                .foregroundStyle(.secondary)
                .help("Copy manual setup command")
                .accessibilityLabel("Copy manual setup command")
            }
            if let command = recoveryCommand(for: reason) {
                Text("$ \(command)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func commandRecovery(command: String, reason: FailureReason) -> some View {
        HStack(spacing: 8) {
            Text("$ \(command)")
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button(action: { copyCommand(for: reason) }) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 4, verticalPadding: 4))
            .foregroundStyle(.secondary)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    private var renewalRow: some View {
        HStack {
            Text("Plan renews").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            if let renewalDate {
                Text(renewalDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Add date", action: onOpenSettings)
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 2))
                    .font(.caption2)
                    .foregroundStyle(accent)
            }
        }
    }

    /// The CLI command that recovers each provider (nil for unknown providers).
    private func recoveryCommand(for reason: FailureReason) -> String? {
        switch providerID {
        case .claude:
            if shouldOfferClaudeSetup(for: reason) {
                return "cd \(shellQuoted(ClaudeUsageWorkspace.defaultDirectoryURL.path)) && claude"
            }
            return "claude"
        case .codex: return "codex login"
        default: return nil
        }
    }

    private func shouldOfferClaudeSetup(for reason: FailureReason) -> Bool {
        providerID == .claude && reason.message == ClaudeUsageWorkspace.trustRequiredMessage
    }

    private func copyCommand(for reason: FailureReason) {
        guard let command = recoveryCommand(for: reason) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func openClaudeSetup() {
        do {
            let workspace = try ClaudeUsageWorkspace.ensureDefaultDirectory()
            let scriptURL = workspace.deletingLastPathComponent()
                .appendingPathComponent("Open Claude Setup.command")
            let script = """
            #!/bin/zsh
            clear
            export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
            cd \(shellQuoted(workspace.path)) || exit 1
            echo "Headroom needs Claude Code to trust this empty folder before it can read /usage."
            echo
            echo "When Claude asks, choose: Yes, I trust this folder"
            echo "After approving, return to Headroom. It will retry automatically."
            echo
            if ! command -v claude >/dev/null 2>&1; then
              echo "Claude Code CLI was not found. Install Claude Code, then reopen Headroom."
              echo
              echo "Press any key to close this window."
              read -k 1
              exit 127
            fi
            exec claude
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
            scheduleSetupRetries()
        } catch {
            copyCommand(for: .needsReauth(ClaudeUsageWorkspace.trustRequiredMessage))
        }
    }

    private func scheduleSetupRetries() {
        for delay in [12.0, 35.0, 75.0] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                onRetrySetup()
            }
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
