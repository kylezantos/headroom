import SwiftUI
import AppKit
import HeadroomCore

/// First-run Claude sign-in flow (onboarding redesign, Jul 2026): the trust-required
/// failure renders as a calm, guided "Sign in to Claude" card — value proposition, one
/// primary action, three numbered steps — instead of an amber error. After the user
/// opens setup it becomes a "Waiting for approval…" card, so the existing silent
/// auto-retries (12/35/75s) have visible feedback. Values were tuned in the HTML
/// mockup (.context/headroom-claude-onboarding.html) and are transferred 1:1.
@MainActor
enum ClaudeSetupSession {
    /// Waiting state lives in the observable `SetupSessionActivity` so rows repaint
    /// the instant a Terminal handoff opens; cleared on app relaunch, so the payoff
    /// chip never becomes permanent UI.
    private static var retryTasks: [AccountID: [Task<Void, Never>]] = [:]

    static func openedSetupAt(for accountID: AccountID) -> Date? {
        SetupSessionActivity.shared.openedAt(for: AccountKey(providerID: .claude, accountID: accountID))
    }

    static func setOpenedSetupAt(_ date: Date?, for accountID: AccountID) {
        SetupSessionActivity.shared.set(date, for: AccountKey(providerID: .claude, accountID: accountID))
    }

    /// Built-in-account accessor kept for the single-account flow (popover header,
    /// render harness).
    static var openedSetupAt: Date? {
        get { openedSetupAt(for: .primary) }
        set { setOpenedSetupAt(newValue, for: .primary) }
    }

    /// The Claude workspace the probe drives for an account. Built-in keeps the
    /// original shared folder; extras get their own home under `AccountStorage`.
    static func workspaceURL(for account: ProviderAccount) -> URL {
        account.isBuiltIn
            ? ClaudeUsageWorkspace.defaultDirectoryURL
            : AccountStorage.claudeWorkspaceDirectoryURL(for: account)
    }

    /// KTD5: only a validated absolute executable yields a manual command. The old
    /// nil-path form produced bare `claude` — the very lookup that already failed.
    static func command(
        for account: ProviderAccount = .builtIn(for: .claude),
        executablePath: String
    ) -> String? {
        let configuration = ProviderAccountConfiguration.make(for: account)
        return ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account.key,
            executablePath: executablePath,
            loginPath: "",
            workspaceDirectory: configuration.claudeWorkspaceDirectory?.path ?? workspaceURL(for: account).path,
            configDirectory: configuration.claudeConfigDirectory?.path
        ))
    }

    /// Resolves through the shared locator so every displayed/copied command names the
    /// same validated executable the probe launches (R6). No resolution, no command.
    static func resolvedCommand(
        for account: ProviderAccount = .builtIn(for: .claude),
        locator: any CLIExecutableLocating = SetupSessions.claudeLocator
    ) async -> String? {
        guard let executablePath = await locator.locate().path else { return nil }
        return command(for: account, executablePath: executablePath)
    }

    private static func ensureWorkspace(for account: ProviderAccount) throws -> URL {
        if account.isBuiltIn {
            return try ClaudeUsageWorkspace.ensureDefaultDirectory()
        }
        try AccountStorage.ensureDirectories(for: account)
        return workspaceURL(for: account)
    }

    /// Tilde-abbreviated form of a resolved command for display; the absolute command is
    /// what's copied.
    static func displayForm(of command: String) -> String {
        command.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Copies an already-resolved absolute command. Callers hold the resolved value, so
    /// there is no path where an unresolved lookup reaches the pasteboard.
    @discardableResult
    static func copy(_ command: String, for account: ProviderAccount = .builtIn(for: .claude)) -> Bool {
        // Terminal may have filesystem permission the app lacks, and the manual command
        // provisions its own workspace. Never leave an older account command on the pasteboard.
        _ = try? ensureWorkspace(for: account)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(command, forType: .string)
    }

    /// Pure staged-script builder for the legacy handoff, extracted so the launch line can
    /// be proven without opening Terminal.
    static func script(
        for account: ProviderAccount,
        workspacePath: String,
        executablePath: String?
    ) -> String {
        let configExport = account.isBuiltIn
            ? ""
            : "export CLAUDE_CONFIG_DIR=\(shellQuoted(AccountStorage.claudeConfigDirectoryURL(for: account).path))\n"
        let intro = account.isBuiltIn
            ? """
            echo "Headroom needs Claude Code to trust this empty folder before it can read /usage."
            echo
            echo "When Claude asks, choose: Yes, I trust this folder"
            echo "After approving, return to Headroom. It will retry automatically."
            """
            : """
            echo "Adding another Claude account to Headroom."
            echo
            echo "1. Log in when Claude asks — use the account you want to add."
            echo "   (This login is kept separate from your main Claude Code account.)"
            echo "2. If Claude asks about this folder, choose: Yes, I trust this folder"
            echo "3. Return to Headroom. It will pick the account up automatically."
            """
        // R1a: the legacy migrate-installer location joins the fallback PATH so this
        // script's environment matches what discovery searches.
        let introduction = """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        \(configExport)cd \(shellQuoted(workspacePath)) || exit 1
        \(intro)
        echo
        """

        // R7/KTD5: without a validated absolute executable there is no launch to stage —
        // a bare `claude` here repeats the lookup Headroom already failed.
        guard let executablePath else {
            return introduction + "\n" + """
            echo "Claude Code CLI was not found. Install Claude Code, then reopen Headroom."
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The Claude CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        exec \(executable)
        """
    }

    /// Writes and opens the guided `.command` script (same mechanism as before the
    /// redesign), marks the session as waiting, and schedules the auto-retries.
    /// Extra accounts additionally export their `CLAUDE_CONFIG_DIR` and walk the user
    /// through signing in with the account being added. R6: discovery runs before
    /// staging so the script launches the same validated absolute executable the probe
    /// uses. The waiting flag flips first — resolution can take up to the locator's
    /// bounded search — and the call stays sync for UI callers.
    static func openSetup(for account: ProviderAccount = .builtIn(for: .claude), onRetry: @escaping () -> Void) {
        setOpenedSetupAt(Date(), for: account.id)
        Task { @MainActor in
            let executablePath = await SetupSessions.claudeLocator.locate().path
            stageAndOpen(for: account, executablePath: executablePath, onRetry: onRetry)
        }
    }

    private static func stageAndOpen(
        for account: ProviderAccount,
        executablePath: String?,
        onRetry: @escaping () -> Void
    ) {
        do {
            let workspace = try ensureWorkspace(for: account)
            // Script filename is per-account: a shared name let a second account's
            // Sign In overwrite the script a still-open Terminal was about to run,
            // landing the login in the wrong config home (code-review finding).
            let scriptURL = ClaudeUsageWorkspace.defaultDirectoryURL.deletingLastPathComponent()
                .appendingPathComponent(account.isBuiltIn
                    ? "Open Claude Setup.command"
                    : "Add Claude Account \(account.id.raw.prefix(8)).command")
            let script = script(
                for: account,
                workspacePath: workspace.path,
                executablePath: executablePath
            )
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            guard NSWorkspace.shared.open(scriptURL) else {
                setOpenedSetupAt(nil, for: account.id)
                cancelRetries(for: account.id)
                copyResolvedCommand(for: account, executablePath: executablePath)
                return
            }
            scheduleRetries(for: account.id, onRetry)
        } catch {
            // Failed to stage the handoff: clear the waiting flag (no Terminal ever
            // opened, so a spinner would wait forever — code-review finding) and fall
            // back to the copyable command.
            setOpenedSetupAt(nil, for: account.id)
            cancelRetries(for: account.id)
            copyResolvedCommand(for: account, executablePath: executablePath)
        }
    }

    /// Clipboard fallback for the legacy handoff. It reuses the executable resolved for
    /// this attempt, so it copies nothing when discovery found no validated launcher.
    private static func copyResolvedCommand(for account: ProviderAccount, executablePath: String?) {
        guard let executablePath,
              let command = command(for: account, executablePath: executablePath)
        else { return }
        copy(command, for: account)
    }

    /// Stop pending auto-retries. Called once the connection goes live — otherwise the
    /// 35s/75s retries keep spawning full 20–30s Claude CLI cycles after success, and
    /// the popover footer reads "Refreshing…" for minutes.
    static func cancelRetries(for accountID: AccountID) {
        retryTasks[accountID]?.forEach { $0.cancel() }
        retryTasks[accountID] = nil
    }

    static func cancelRetries() { cancelRetries(for: .primary) }

    private static func scheduleRetries(for accountID: AccountID, _ onRetry: @escaping () -> Void) {
        cancelRetries(for: accountID)
        retryTasks[accountID] = [12.0, 35.0, 75.0].map { delay in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                onRetry()
            }
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

/// Setup-flow palette, transferred from the mockup's OKLCH light palette (WCAG-checked:
/// button label ≥4.6:1, chip ink 5.1:1) and its dark equivalents.
///
/// PB13 removed `accentText`: S2B retired the last accent-inked label in the setup flow, so
/// the token had been a duplicate of `ProviderStyle.textAccent(for: .claude)` with no call
/// site left. Codex's CTA gradient lives in its own `CodexSetupStyle` rather than here —
/// mirrored deliberately, so the two provider streams stay decoupled.
enum ClaudeSetupStyle {
    /// R2C18: the four CTA literals moved to `HeadroomBrandRamp` as stops on Claude's
    /// constant-hue ramp (H 38.8°, the `claude-color.svg` fill's own hue). The dark top also
    /// dropped L 0.605 → 0.560: it measured white-on 4.05:1, below AA, while the comment here
    /// claimed the ramp "averages ≈4.5:1". It is 4.92:1 now, asserted in
    /// `BrandColorValuesTests`. This enum stays the setup flow's call surface — the two
    /// provider streams remain decoupled — but the numbers have one home.
    static func buttonTop(dark: Bool) -> Color {
        ProviderStyle.claudeCTATop(dark: dark)
    }
    static func buttonBottom(dark: Bool) -> Color {
        ProviderStyle.claudeCTABottom(dark: dark)
    }
    static func stepBackground(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }
    static func stepBorder(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    /// R2C18: the value now lives in Core as `ProviderStyle.recessedWell`, because the
    /// Settings preview wells read it too and a Claude-branded token should not own a pane
    /// with no Claude in it. Those Settings call sites are WS-C's to move.
    static func wellBackground(dark: Bool) -> Color {
        ProviderStyle.recessedWell(dark: dark)
    }
    static func codeBackground(dark: Bool) -> Color {
        wellBackground(dark: dark)
    }
    static func hairline(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
    /// "Connected" chip ink — offset from the bar-fill green so it passes AA as text on
    /// the chip tint in both schemes (light darker, dark brighter + thinner tint).
    ///
    /// R2C18: it was a hand-written green sitting beside a chip fill *derived* from
    /// `healthy` — one chip, two greens. It is now a documented OKLCH lightness offset from
    /// that same token, so the pair cannot drift apart again.
    static func connectedInk(dark: Bool) -> Color {
        ProviderStyle.connectedInk(dark: dark)
    }
    static func connectedBackground(dark: Bool) -> Color {
        let green = HeadroomSeverityColorValues.healthy(dark: dark)
        return Color(red: green.red, green: green.green, blue: green.blue).opacity(0.12)
    }
}

/// R2B2: the two guided setup cards ran a five-value top-padding ladder (6/11/12/14/13) and
/// a five-value body band (12.5/11.5/12/11/10.5). Five gaps inside a 7pt spread say nothing
/// about which boundaries are group breaks, so the stack read as one undifferentiated list.
/// The ladder is two values — 12 between siblings, 20 before the steps block, which is the
/// card's one real section break — and the band is two: 12.5 for the lead and the steps that
/// answer it, 11 for the tertiary notes.
enum SetupCardMetrics {
    /// Title → its own subtitle; the tightest bind in the card, unchanged.
    static let leadGap: CGFloat = 6
    static let siblingGap: CGFloat = 12
    static let sectionGap: CGFloat = 20

    static let bodySize: CGFloat = 12.5
    static let noteSize: CGFloat = 11

    /// R2B2: one kerning for the 15/semibold card titles. The app carried −0.15 and −0.2 at
    /// the same size and weight, which is a difference nobody chose.
    static let titleKerning: CGFloat = -0.2
}

/// State 1 — the first-run card: value first, one primary action, guided steps, and the
/// raw command demoted behind a disclosure.
struct ClaudeConnectCard: View {
    var outcome: ProviderSetupOutcome = .claudeTrustRequired
    let onOpenSetup: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .claude, size: 20)
                // R2C6: one title in both branches. The card used to say "Sign in to Claude"
                // for a login and "Connect Claude" for a workspace approval — two verbs for
                // the same guided handoff, in the same card, on the same run.
                Text(ProviderSignInCopy.cardTitle(for: .claude))
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(SetupCardMetrics.titleKerning)
            }
            Text(outcome == .claudeLoginRequired
                 ? "Sign in with the Claude CLI to show this account’s usage."
                 : "See your remaining Claude usage right here.")
                .font(.system(size: SetupCardMetrics.bodySize))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                // W2A: the only body copy in this card that was missing the wrap allowance.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.leadGap)
            reassurance
                .padding(.top, SetupCardMetrics.siblingGap)
            Button(action: onOpenSetup) {
                Label(outcome.recoveryPresentation.primaryLabel, systemImage: "terminal")
            }
            .buttonStyle(ClaudePrimaryButtonStyle())
            .padding(.top, SetupCardMetrics.siblingGap)
            steps(dark: dark)
                .padding(.top, SetupCardMetrics.sectionGap)
            ClaudeManualCommandDisclosure()
                .padding(.top, SetupCardMetrics.siblingGap)
        }
    }

    /// "official /usage · no login · never spends usage" — the trust line that makes a
    /// first-run user comfortable pressing the button.
    private var reassurance: some View {
        // R2B2: the tertiary note tier. The inline command run stays 0.5pt under the prose
        // around it — monospace at a matched point size reads a size larger.
        Text("Reads Claude’s official \(Text("/usage").font(.system(size: 10.5, design: .monospaced))) panel through its CLI. Headroom never receives your password or tokens, and the check never spends usage.")
            .font(.system(size: SetupCardMetrics.noteSize))
            .foregroundStyle(.tertiary)
            // PB11: the longest prose in the popover — three lines at 293pt — and the line
            // the audit measured at 1.22 leading against Settings' 1.4.
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func steps(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("Takes about 20 seconds")
                    .font(.system(size: SetupCardMetrics.noteSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
                Rectangle()
                    .fill(ClaudeSetupStyle.hairline(dark: dark))
                    .frame(height: 1)
            }
            step(1, Text("Terminal opens and starts Claude for you"), dark: dark)
            // W2A: both steps shed a word so neither drops a one-word orphan at 293pt.
            step(2, outcome == .claudeLoginRequired
                 ? Text("Sign in, then approve the workspace if asked")
                 : Text("Choose \(Text("“Yes, I trust this folder”").fontWeight(.semibold).foregroundColor(.primary)) when asked"), dark: dark)
            step(3, Text("Come back — usage appears here automatically"), dark: dark)
        }
    }

    private func step(_ number: Int, _ text: Text, dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: SetupCardMetrics.noteSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: Circle())
                .overlay(Circle().strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
            // R2B2: the steps answer the lead, so they read at the lead's size.
            text
                .font(.system(size: SetupCardMetrics.bodySize))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// State 2 — "Waiting for approval…": visible feedback for the auto-retry window. The
/// literal trust-prompt option is a quiet bordered token (not bold prose) so it never
/// competes with the bold title above it.
struct ClaudeWaitingCard: View {
    var outcome: ProviderSetupOutcome = .claudeTrustRequired
    let onCheckNow: () -> Void
    let onReopen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .claude, size: 20)
                ProgressView()
                    .controlSize(.small)
                Text(outcome == .claudeLoginRequired ? "Waiting for sign-in…" : "Waiting for approval…")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(SetupCardMetrics.titleKerning)
            }
            // W2A: the trust variant was three lines ending on the single word "approve."
            Text(outcome == .claudeLoginRequired
                 ? "Finish signing in in the Terminal that just opened. Headroom checks this account automatically."
                 : "Choose the option below in Terminal. Headroom connects as soon as you approve.")
                .font(.system(size: SetupCardMetrics.bodySize))
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.leadGap)
            if outcome == .claudeTrustRequired {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("“Yes, I trust this folder”")
                        .font(.system(size: SetupCardMetrics.bodySize, weight: .semibold))
                }
                .padding(.vertical, 6)
                .padding(.leading, 9).padding(.trailing, 11)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
                .padding(.top, SetupCardMetrics.siblingGap)
            }
            // B3A/P4C/B3: "Reopen Terminal" was a bare accent label standing next to a filled
            // chip. Both are thin chips now, leading-aligned at the card's foot with
            // "Check Now" — the action the waiting state is really about — first, and no
            // icon inside either one.
            // B3X: a guided setup card lays its prose out at its own leading edge, so its
            // chip labels start there too.
            CardActionRow(labelInset: 0) {
                Button("Check Now", action: onCheckNow)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
                Button("Reopen Terminal", action: onReopen)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
            }
            ClaudeManualCommandDisclosure()
                .padding(.top, SetupCardMetrics.siblingGap)
        }
    }
}

/// "Rather run it yourself?" — the manual command, demoted behind a disclosure so the
/// shell never dominates the first-run card. Shown tilde-abbreviated, wraps fully.
struct ClaudeManualCommandDisclosure: View {
    var account: ProviderAccount = .builtIn(for: .claude)

    @State private var open = false
    /// KTD5: the disclosure appears only once discovery produced a validated absolute
    /// executable — there is no command to show or copy without one.
    @State private var resolvedCommand: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .task {
                resolvedCommand = await ClaudeSetupSession.resolvedCommand(for: account)
            }
    }

    @ViewBuilder private var content: some View {
        if let resolvedCommand {
            disclosure(for: resolvedCommand)
        }
    }

    private func disclosure(for command: String) -> some View {
        let dark = scheme == .dark
        // R2M7/S2A: one toggle, two kinds of motion, so it needs two resolved scopes rather
        // than the `reduceMotion ? nil : token` this used to carry — `nil` kills the fade as
        // well as the travel, and S2A says a crossfade keeps its timing under Reduce Motion.
        // The revealed well is the crossfade; the chevron's rotation is movement and takes
        // its own scope below so it snaps.
        let crossfade = HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion)
        let movement = HeadroomMotion.resolved(HeadroomMotion.settle, .movement, reduceMotion: reduceMotion)
        return VStack(alignment: .leading, spacing: 9) {
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
            .accessibilityLabel(open ? "Hide manual Claude login command" : "Show manual Claude login command")
            if open {
                HStack(alignment: .top, spacing: 8) {
                    Text(ClaudeSetupSession.displayForm(of: command))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    CopyFeedbackButton(
                        copy: { ClaudeSetupSession.copy(command, for: account) },
                        label: "Copy command"
                    )
                }
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(ClaudeSetupStyle.codeBackground(dark: dark), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(.opacity)
            }
        }
        .animation(crossfade, value: open)
    }
}

/// Full-width clay gradient primary — the card's one unmistakable action. Hover brightens,
/// press settles on PB12's shared `pressScale`; both input-driven (no idle motion).
struct ClaudePrimaryButtonStyle: ButtonStyle {
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
            // S3A: hover in fast, out slow; press lands inside 100ms and returns on settle.
            let hoverAnimation = hovering ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    shape.fill(LinearGradient(
                        colors: [ClaudeSetupStyle.buttonTop(dark: dark), ClaudeSetupStyle.buttonBottom(dark: dark)],
                        startPoint: .top, endPoint: .bottom))
                )
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

/// B3A (Sep 2026): the one secondary button for every text-labelled action inside a card or
/// tile. The bare `HoverButtonStyle` is reserved for glyph controls. Two sizes so the same
/// chip fits a card foot (regular) and an account row (small).
///
/// **PA11b (Kyle, Sep 2026) supersedes B3H.** B3H had made the popover's chrome hover-only
/// — "only have the button chrome show up on hover (like Refresh and Quit)" — and shipping
/// it showed the cost: at rest, "Install Claude Code" and "Check Again" read as wrapped
/// prose, and the audit caught a half-visible one bisected by the 640pt scroll cap with
/// every signal that it was a control removed. Kyle's call on review: "we do need the
/// resting container for all our buttons." That also lines up with the macOS HIG — push
/// buttons carry a visible border, every custom button needs a press state, and borderless
/// buttons belong in toolbars and status bars, which is exactly where the glyph-only
/// controls (gear, `+`, `…`, copy, trash, reset) still live on `HoverButtonStyle`.
///
/// So there is one chrome now: a resting container everywhere, hover lifts the fill one
/// step, pressed goes one step further plus `HeadroomMotion.pressScale`. `Chrome` survives
/// as a single case because call sites that spell out `chrome: .resting` are stating the
/// decision, and because dropping the parameter would churn files this change does not own.
struct SetupChipButtonStyle: ButtonStyle {
    enum Size {
        case regular
        case small

        var fontSize: CGFloat { self == .regular ? 12.5 : 11.5 }
        // CMM1 (Kyle, 2026-09-09): squarer and tighter, after the CleanMyMac popover buttons
        // he sent — the reference sits its 15pt label in a 23pt chip with ≈9.5pt side padding
        // and a radius just over a quarter of the height. Ours keep their heights and take
        // the same proportions: radius ≈ 0.27 × height, 10/8pt sides.
        var horizontalPadding: CGFloat { self == .regular ? 10 : 8 }
        var verticalPadding: CGFloat { self == .regular ? 6 : 4 }
        var cornerRadius: CGFloat { self == .regular ? 7 : 6 }
    }

    /// PA11b: B3H's `.hover` case is gone with the behaviour it named.
    enum Chrome {
        case resting
    }

    var size: Size = .regular
    var chrome: Chrome = .resting

    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, size: size, chrome: chrome, dark: scheme == .dark)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let size: Size
        let chrome: Chrome
        let dark: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
            // M11A: the "Check Now" chip takes the same S3A pair as the popover's quiet buttons.
            let hoverAnimation = hovering ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut
            let pressAnimation = configuration.isPressed ? HeadroomMotion.pressDown : HeadroomMotion.settle
            configuration.label
                .font(.system(size: size.fontSize, weight: .semibold))
                // R2C18: was a byte-copy of the shared light neutral beside an unrelated
                // `Color(white: 0.85)`; both steps now read `setupChipInk`.
                .foregroundStyle(ProviderStyle.setupChipInk(dark: dark))
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background {
                    // CMM1 → CMM3 (Kyle, 2026-09-09): "a bit too bright now … more
                    // restrained in a James McDonald way." Four quiet layers instead of one
                    // loud rim: a low-alpha fill, a 1pt *inset* highlight along the top edge
                    // (the light catching the lip), a faint ring for the edge, and a 1pt
                    // shadow underneath so the chip sits *on* the card rather than being
                    // outlined on it. Each layer is near-invisible alone; together they read
                    // as a physical control.
                    shape
                        .fill(fillColor)
                        .overlay {
                            shape
                                .inset(by: 1)
                                .strokeBorder(topHighlight, lineWidth: 1)
                                // Fade the lip out down the sides rather than cutting it —
                                // a hard mask leaves a ledge where the highlight stops.
                                .mask {
                                    LinearGradient(
                                        colors: [.white, .clear],
                                        startPoint: .top,
                                        endPoint: .init(x: 0.5, y: 0.55)
                                    )
                                }
                        }
                        .overlay(shape.strokeBorder(ringColor, lineWidth: 1))
                        .shadow(color: shadowColor, radius: 0.5, y: 1)
                }
                // S2A: the fill is a colour change and survives Reduce Motion; the press scale
                // below is the only movement here, so it resolves separately.
                .animation(HeadroomMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: hovering)
                .animation(HeadroomMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                // B3H follow-up: preserve the 40pt interaction floor by expanding hit testing
                // without wrapping the rendered label in opposing paddings. That layout pair
                // was the only label-local transform after inverted text appeared on reopen.
                .contentShape(Rectangle().inset(by: -8))
                // PB12: the same `pressScale` every other button style uses. This was 0.98,
                // which on an 11.5pt chip was close enough to nothing that the press barely
                // registered next to a `HoverButtonStyle` glyph at 0.96.
                .scaleEffect(configuration.isPressed ? HeadroomMotion.pressScale : 1)
                .animation(HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        /// PA11b: one three-step ladder — rest, hover one step up, pressed one step further.
        ///
        /// Light goes **subtractive**. B3H's light fills were white-on-white (ΔL 0.012 over a
        /// Settings tile), so the resting container the chrome exists to guarantee did not
        /// render at all; black-alpha over the tile is the mirror of the dark branch's
        /// white-alpha and reads at every step. The drop shadow went with it — a recessed
        /// fill lit from above is a contradiction, and the 1pt border already carries the
        /// edge.
        private var fillColor: Color {
            let step = configuration.isPressed ? 2 : (hovering ? 1 : 0)
            return dark
                ? Color.white.opacity(Self.darkFillSteps[step])
                : Color.black.opacity(Self.lightFillSteps[step])
        }

        // CMM3: quiet steps — rest barely lifts off the card; hover and press add one step
        // each so the ladder still reads in motion.
        private static let darkFillSteps: [Double] = [0.07, 0.11, 0.15]
        private static let lightFillSteps: [Double] = [0.04, 0.07, 0.10]

        /// CMM3: the inset top lip. Dark catches white light; light catches a whiter white
        /// on the near-white tile, which is what makes a light chip look raised at all.
        private var topHighlight: Color {
            dark ? Color.white.opacity(0.12) : Color.white.opacity(0.70)
        }

        /// CMM3: the edge ring, a hair above the fill so the box still has a boundary.
        private var ringColor: Color {
            dark ? Color.white.opacity(0.08) : Color.black.opacity(0.09)
        }

        /// CMM3: one point of shadow, just enough to seat the chip.
        private var shadowColor: Color {
            dark ? Color.black.opacity(0.35) : Color.black.opacity(0.08)
        }
    }
}
