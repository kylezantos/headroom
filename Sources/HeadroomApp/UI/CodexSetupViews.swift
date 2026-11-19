#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import AppKit
import HeadroomCore
import SwiftUI
#if canImport(HeadroomWidgetSharedUI)
import HeadroomWidgetSharedUI
#endif

/// Session-local state for the official Codex CLI handoff. It is intentionally separate
/// from Claude setup so either provider can wait or recover without canceling the other.
@MainActor
enum CodexSetupSession {
    private static var retryTasks: [AccountID: [Task<Void, Never>]] = [:]
    private static var openingTasks: [AccountID: Task<Void, Never>] = [:]

    static func openedSetupAt(for accountID: AccountID) -> Date? {
        SetupSessionActivity.shared.openedAt(for: AccountKey(providerID: .codex, accountID: accountID))
    }

    static func setOpenedSetupAt(_ date: Date?, for accountID: AccountID) {
        SetupSessionActivity.shared.set(date, for: AccountKey(providerID: .codex, accountID: accountID))
    }

    /// Built-in-account accessor kept for the single-account flow (popover header,
    /// render harness).
    static var openedSetupAt: Date? {
        get { openedSetupAt(for: .primary) }
        set { setOpenedSetupAt(newValue, for: .primary) }
    }

    /// `CODEX_HOME` for an extra account; nil for the built-in (default `~/.codex`).
    static func codexHome(for account: ProviderAccount) -> String? {
        account.isBuiltIn ? nil : AccountStorage.codexHomeDirectoryURL(for: account).path
    }

    static func loginCommand(for account: ProviderAccount = .builtIn(for: .codex)) -> String {
        CodexCLI.accountLoginCommand(codexHome: codexHome(for: account))
    }

    /// R2M9: reports whether the write landed, so the copy button only confirms a copy that
    /// actually happened. The Terminal-handoff fallbacks below still ignore the result —
    /// there is nothing better to offer them if the pasteboard refuses.
    @discardableResult
    static func copyCommand(for account: ProviderAccount = .builtIn(for: .codex)) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(loginCommand(for: account), forType: .string)
    }

    @discardableResult
    static func copyCommand() -> Bool { copyCommand(for: .builtIn(for: .codex)) }

    static func openSetup(for account: ProviderAccount = .builtIn(for: .codex), onRetry: @escaping () -> Void) {
        guard openingTasks[account.id] == nil else { return }
        openingTasks[account.id] = Task { @MainActor in
            defer { openingTasks[account.id] = nil }
            if !account.isBuiltIn {
                _ = try? AccountStorage.ensureDirectories(for: account)
            }
            let codexHome = codexHome(for: account)
            // Per-account filename — see ClaudeSetupSession.openSetup (script-overwrite race).
            let scriptName = account.isBuiltIn
                ? "Open Codex Login.command"
                : "Add Codex Account \(account.id.raw.prefix(8)).command"
            let preparation = await Task.detached(priority: .userInitiated) { () -> (scriptURL: URL, hasExecutable: Bool)? in
                let supportDirectory = ClaudeUsageWorkspace.defaultDirectoryURL.deletingLastPathComponent()
                let scriptURL = supportDirectory.appendingPathComponent(scriptName)
                let executablePath = CodexCLI.resolveExecutable()
                do {
                    try FileManager.default.createDirectory(
                        at: supportDirectory,
                        withIntermediateDirectories: true
                    )
                    try CodexCLI.loginScript(executablePath: executablePath, codexHome: codexHome)
                        .write(to: scriptURL, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: scriptURL.path
                    )
                    return (scriptURL: scriptURL, hasExecutable: executablePath != nil)
                } catch {
                    return nil
                }
            }.value

            guard let preparation else {
                copyCommand(for: account)
                return
            }
            guard NSWorkspace.shared.open(preparation.scriptURL) else {
                copyCommand(for: account)
                return
            }
            guard preparation.hasExecutable else {
                setOpenedSetupAt(nil, for: account.id)
                cancelRetries(for: account.id)
                copyCommand(for: account)
                return
            }
            setOpenedSetupAt(Date(), for: account.id)
            scheduleRetries(for: account.id, onRetry)
        }
    }

    static func cancelRetries(for accountID: AccountID) {
        retryTasks[accountID]?.forEach { $0.cancel() }
        retryTasks[accountID] = nil
    }

    static func cancelRetries() { cancelRetries(for: .primary) }

    private static func scheduleRetries(for accountID: AccountID, _ onRetry: @escaping () -> Void) {
        cancelRetries(for: accountID)
        retryTasks[accountID] = [8.0, 20.0, 45.0, 90.0].map { delay in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                onRetry()
            }
        }
    }
}

struct CodexConnectCard<Retained: View>: View {
    let action: CodexConnectionAction
    var presentation: ProviderRecoveryPresentation? = nil
    let onOpenSetup: () -> Void
    var onSecondaryAction: (() -> Void)? = nil
    /// CA-P3 (UX-03): the old reading's "Last read …" chip on the title line. Set exactly when
    /// `retained` draws something; the card lays `retained` out only then.
    var retainedReadLabel: String? = nil
    /// CA-P3 (UX-03): the retained meters, directly under the title rather than 300pt below
    /// it under the instructions, so a number sits with its age.
    @ViewBuilder let retained: Retained

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reconnecting = action == .reconnect
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .codex, size: 20)
                // R2C6: one verb. "Connect Codex" / "Reconnect Codex" named the same act
                // the Claude card next to it called signing in.
                // CA-P8 (POP-08): primary ink, as Claude's title is. The brand stays in the
                // mark and the CTA, so the card spends its accent once.
                Text(ProviderSignInCopy.cardTitle(for: .codex, again: reconnecting))
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(SetupCardMetrics.titleKerning)
                if let retainedReadLabel {
                    SetupCardReadChip(label: retainedReadLabel)
                }
            }
            if retainedReadLabel != nil {
                retained
                    .padding(.top, SetupCardMetrics.retainedGap)
            }
            // CA-P9 (COPY-03): Core's sentences, so "quick" and "reconnects" are gone.
            Text(reconnecting
                 ? ProviderSignInCopy.codexSignedOutBody
                 : "See your remaining Codex usage right here.")
                .font(.system(size: SetupCardMetrics.bodySize))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.leadGap)
            // R2B2: the tertiary note tier, matching the Claude card's reassurance line.
            // CA-P9 (COPY-04): the privacy promise in the one shape both cards share.
            Text(ProviderSignInCopy.privacyNote(for: .codex) ?? "")
                .font(.system(size: SetupCardMetrics.noteSize))
                .foregroundStyle(.tertiary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.siblingGap)
            Button(action: onOpenSetup) {
                Label(
                    presentation?.primaryLabel
                        ?? (reconnecting ? ProviderSignInCopy.buttonAgain : ProviderSignInCopy.button),
                    systemImage: "terminal"
                )
            }
            .buttonStyle(CodexPrimaryButtonStyle())
            .padding(.top, SetupCardMetrics.siblingGap)
            if let secondaryLabel = presentation?.secondaryLabel,
               let onSecondaryAction {
                // B3A/P4C/B3: "Use Device Code" was a bare indigo label hanging under the
                // full-width primary. The primary keeps its width; the secondary becomes a
                // thin chip in the leading action row beneath it.
                // B3X: this card's prose starts at its own leading edge, not the 34pt axis.
                CardActionRow(labelInset: 0) {
                    Button(secondaryLabel, action: onSecondaryAction)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                        .accessibilityLabel(secondaryLabel)
                }
            }
            steps
                .padding(.top, SetupCardMetrics.sectionGap)
            CodexManualCommandDisclosure()
                .padding(.top, SetupCardMetrics.siblingGap)
        }
    }

    private var steps: some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("A minute or less")
                    .font(.system(size: SetupCardMetrics.noteSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(ClaudeSetupStyle.hairline(dark: dark))
                    .frame(height: 1)
            }
            step(1, "Terminal opens the official Codex login", dark: dark)
            step(2, "Finish signing in with ChatGPT in your browser", dark: dark)
            step(3, ProviderSignInCopy.comeBackStep, dark: dark)
        }
    }

    private func step(_ number: Int, _ text: String, dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: SetupCardMetrics.noteSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: Circle())
                .overlay(Circle().strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
            // R2B2: the steps answer the lead, so they read at the lead's size.
            Text(text)
                .font(.system(size: SetupCardMetrics.bodySize))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension CodexConnectCard where Retained == EmptyView {
    init(
        action: CodexConnectionAction,
        presentation: ProviderRecoveryPresentation? = nil,
        onOpenSetup: @escaping () -> Void,
        onSecondaryAction: (() -> Void)? = nil
    ) {
        self.init(action: action, presentation: presentation, onOpenSetup: onOpenSetup,
                  onSecondaryAction: onSecondaryAction, retained: { EmptyView() })
    }
}

extension CodexWaitingCard where Retained == EmptyView {
    init(
        mode: SetupHandoffMode = .standard,
        phase: SetupWaitingPhase? = nil,
        onReopen: @escaping () -> Void,
        stopWaitingAccount: ProviderAccount? = nil,
        onRemoveAccount: ((ProviderAccount) -> Void)? = nil
    ) {
        self.init(mode: mode, phase: phase, onReopen: onReopen, stopWaitingAccount: stopWaitingAccount,
                  onRemoveAccount: onRemoveAccount, retained: { EmptyView() })
    }
}

/// CA-P8 (COPY-06): the waiting Codex card's title, which the popover header's waiting
/// fallback reads too, so the two can never name different acts.
enum CodexWaitingCopy {
    static func title(mode: SetupHandoffMode, phase: SetupWaitingPhase?) -> String {
        phase?.copy.title ?? (mode == .deviceCode ? "Finish device-code sign-in…" : "Finish signing in…")
    }
}

/// CA-P8 (POP-09): a setup card's metadata line, a 10pt glyph 5pt before 11pt text.
struct SetupMetadataLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

enum CodexAccessRecoveryKind {
    case permission
    case storage
}

/// Recovery that cannot be repaired by silently reopening login. Permission denial
/// goes to macOS access guidance; storage mismatch deliberately names the file-store
/// repair before the user invokes the official CLI again.
struct CodexAccessRecoveryCard: View {
    let kind: CodexAccessRecoveryKind
    let onPrimaryAction: () -> Void
    let onCheckNow: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .codex, size: 20)
                // CA-P8 (POP-08): primary ink, like every setup card title.
                Text(kind == .permission ? "Allow Codex Access" : "Resolve Codex Storage")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(SetupCardMetrics.titleKerning)
            }
            Text(kind == .permission
                 ? "Headroom found the Codex sign-in file but macOS did not allow it to be read. Signing in again cannot repair this permission."
                 : "Codex did not leave a readable file for this account. Reopen its official login with Headroom’s account-specific file-storage setting.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // P4C/B3: the full-width primary keeps its own line, as in `CodexConnectCard`;
            // "Check Now" drops to the card's leading action row.
            VStack(alignment: .leading, spacing: 0) {
                Button(kind == .permission ? "Open Privacy & Security" : "Resolve Storage", action: onPrimaryAction)
                    .buttonStyle(CodexPrimaryButtonStyle())
                    .accessibilityLabel(kind == .permission
                                        ? "Open Privacy and Security for Codex file access"
                                        : "Resolve Codex storage for this account")
                // B3X: aligned with the card's prose, which starts at its own edge.
                CardActionRow(labelInset: 0) {
                    Button("Check Now", action: onCheckNow)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                }
            }
        }
    }
}

struct CodexWaitingCard<Retained: View>: View {
    var mode: SetupHandoffMode = .standard
    var phase: SetupWaitingPhase? = nil
    let onReopen: () -> Void
    /// CA-P7 (POP-05): the session's Stop Waiting, hosted in this card's own action row beside
    /// Reopen Terminal instead of in a second row appended after the whole body.
    var stopWaitingAccount: ProviderAccount? = nil
    /// CA-P14: passed through to Stop Waiting for a never-signed-in extra.
    var onRemoveAccount: ((ProviderAccount) -> Void)? = nil
    var retainedReadLabel: String? = nil
    /// CA-P3 (UX-03): the retained meters, under the title.
    @ViewBuilder let retained: Retained

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func loadingMotion(reduceMotion: Bool) -> SetupMotion {
        SetupMotion.resolve(phase: phase ?? .waitingForUser(.signIn), surface: .card, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .codex, size: 20)
                let loading = loadingMotion(reduceMotion: reduceMotion)
                // R7: the same title-slot vessel as Claude; setup phases own its motion.
                HalftoneVesselView(state: .init(id: "codex-setup", level: loading.level),
                                  motion: loading.motion, width: 10, height: 16, columns: 4, rows: 8)
                // CA-P8 (POP-08): primary ink, matching Claude's waiting title.
                Text(CodexWaitingCopy.title(mode: mode, phase: phase))
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(SetupCardMetrics.titleKerning)
                if let retainedReadLabel {
                    SetupCardReadChip(label: retainedReadLabel)
                }
            }
            if retainedReadLabel != nil {
                retained
                    .padding(.top, SetupCardMetrics.retainedGap)
            }
            // CA-P9 (COPY-03): "will reconnect" was the retired verb.
            Text(mode == .deviceCode
                 ? ProviderSignInCopy.codexDeviceCodeWaitingBody
                 : ProviderSignInCopy.codexBrowserWaitingBody)
                .font(.system(size: SetupCardMetrics.bodySize))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.leadGap)
            // CA-P8 (POP-09): the trust line was drawn as a bordered, filled capsule with an
            // icon, so it read as a button that did nothing and outranked the real chip below
            // it. It is quiet metadata now: no container, 6pt above the action row.
            Label {
                Text(mode == .deviceCode
                     ? "Official Codex CLI · device code · file-backed sign-in"
                     : "Official Codex CLI · file-backed sign-in")
                    .font(.system(size: SetupCardMetrics.noteSize))
            } icon: {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
            }
            .labelStyle(SetupMetadataLabelStyle())
            .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            .padding(.top, SetupCardMetrics.siblingGap)
            // B3A/P4C/B3: same as the Claude waiting card — a thin chip, leading-aligned at
            // the card's foot, with no icon inside it.
            // R13/KTD12 (2026-09-19 sign-in plan): Check Now left every waiting surface. The
            // row is shared with Claude, and nothing the user could force is outstanding
            // while the official CLI still owns the Terminal window.
            // B3X: same as the Claude waiting card — the guided card's own leading edge.
            // CA-P7: Stop Waiting trails Reopen Terminal on the same line, so the one decision
            // is one row.
            CardActionRow(topPadding: SetupCardMetrics.metadataToActionGap, labelInset: 0) {
                Button("Reopen Terminal", action: onReopen)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
                if let stopWaitingAccount {
                    StopWaitingButton(account: stopWaitingAccount, style: .chip(.small),
                                      onRemoveAccount: onRemoveAccount)
                }
            }
            CodexManualCommandDisclosure()
                .padding(.top, SetupCardMetrics.siblingGap)
        }
    }
}

struct CodexManualCommandDisclosure: View {
    @State private var open = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        // R2M7/S2A: see `ClaudeManualCommandDisclosure` — the revealed well is a crossfade
        // and keeps its timing under Reduce Motion; the chevron's rotation is movement and
        // snaps. `reduceMotion ? nil : token` silenced both, so the disclosure blinked.
        let movement = HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 9) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(movement, value: open)
                    Text("Rather run it yourself?")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 5, verticalPadding: 3))
            .accessibilityLabel(open ? "Hide manual Codex login command" : "Show manual Codex login command")
            if open {
                HStack(alignment: .top, spacing: 8) {
                    Text(CodexCLI.accountLoginCommand(codexHome: nil))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    CopyFeedbackButton(
                        copy: { CodexSetupSession.copyCommand() },
                        label: "Copy Codex login command"
                    )
                }
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(ClaudeSetupStyle.codeBackground(dark: dark), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
        }
        // RM1: `.movement`, so under Reduce Motion the disclosure's height snaps and only the
        // well's fade (on its transition) keeps its timing.
        .animation(movement, value: open)
    }
}

/// PB13: Codex's half of the setup palette, mirroring `ClaudeSetupStyle`. The CTA gradient
/// used to be four raw RGB literals inside the button's own body, which made it the one
/// brand colour in the app with no name and no shared home. It stays a *local* enum rather
/// than a Core token on purpose: the two provider setup flows are deliberately decoupled, so
/// a Codex tweak must never reach into Claude's ramp.
enum CodexSetupStyle {
    /// R2C18: the four literals are stops on Codex's constant-hue ramp (H 271.5°) in
    /// `HeadroomBrandRamp`; the dark top dropped L 0.611 → 0.565 because white on it measured
    /// 3.97:1, below AA. This enum stays the call surface, so a Codex tweak still cannot
    /// reach into Claude's ramp.
    static func buttonTop(dark: Bool) -> Color {
        ProviderStyle.codexCTATop(dark: dark)
    }

    static func buttonBottom(dark: Bool) -> Color {
        ProviderStyle.codexCTABottom(dark: dark)
    }
}

struct CodexPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, dark: scheme == .dark)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let dark: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            let top = CodexSetupStyle.buttonTop(dark: dark)
            let bottom = CodexSetupStyle.buttonBottom(dark: dark)
            // S3A: hover in fast, out slow; press lands inside 100ms and returns on settle.
            let hoverAnimation = hovering ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1).blendMode(.plusLighter).opacity(0.6))
                .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                .brightness(configuration.isPressed ? -0.03 : (hovering ? 0.04 : 0))
                // S2A: brightness is a colour change and keeps its timing under Reduce Motion;
                // the press scale below is movement, so it carries its own modifier.
                .animation(HeadroomMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: hovering)
                .animation(HeadroomMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                // PB12: one press scale across all four button styles.
                .scaleEffect(configuration.isPressed ? HeadroomMotion.pressScale : 1)
                .animation(HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
