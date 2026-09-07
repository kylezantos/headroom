import SwiftUI
import AppKit
import HeadroomCore

/// First-run Claude connection flow (onboarding redesign, Jul 2026): the trust-required
/// failure renders as a calm, guided "Connect Claude" card — value proposition, one
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
/// button label ≥4.6:1, accent text 6.3:1, chip ink 5.1:1) and its dark equivalents.
enum ClaudeSetupStyle {
    /// Dark values darkened (audit): the original dark gradient left the white 13pt
    /// label at 3.1–3.8:1; this ramp averages ≈4.5:1 across the button face.
    static func buttonTop(dark: Bool) -> Color {
        dark ? Color(red: 0.75, green: 0.40, blue: 0.22) : Color(red: 0.733, green: 0.345, blue: 0.133)
    }
    static func buttonBottom(dark: Bool) -> Color {
        dark ? Color(red: 0.69, green: 0.34, blue: 0.17) : Color(red: 0.663, green: 0.302, blue: 0.110)
    }
    /// Clay accent used as *text* — darker than the brand fill so it passes AA.
    static func accentText(dark: Bool) -> Color {
        dark ? Color(red: 0.910, green: 0.561, blue: 0.369) : Color(red: 0.604, green: 0.282, blue: 0.106)
    }
    static func stepBackground(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }
    static func stepBorder(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    static func wellBackground(dark: Bool) -> Color {
        dark ? Color.black.opacity(0.32) : Color.black.opacity(0.05)
    }
    static func codeBackground(dark: Bool) -> Color {
        wellBackground(dark: dark)
    }
    static func hairline(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
    /// "Connected" chip ink — offset from the bar-fill green so it passes AA as text on
    /// the chip tint in both schemes (light darker, dark brighter + thinner tint).
    static func connectedInk(dark: Bool) -> Color {
        dark ? Color(red: 0.25, green: 0.86, blue: 0.42) : Color(red: 0.082, green: 0.447, blue: 0.208)
    }
    static func connectedBackground(dark: Bool) -> Color {
        let green = HeadroomSeverityColorValues.healthy(dark: dark)
        return Color(red: green.red, green: green.green, blue: green.blue).opacity(0.12)
    }
}

/// State 1 — "Connect Claude": value first, one primary action, guided steps, and the
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
                Text(outcome == .claudeLoginRequired ? "Sign in to Claude" : "Connect Claude")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
            }
            Text(outcome == .claudeLoginRequired
                 ? "Sign in with the Claude CLI to show this account's usage."
                 : "See your remaining Claude usage right here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                // W2A: the only body copy in this card that was missing the wrap allowance.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            reassurance
                .padding(.top, 11)
            Button(action: onOpenSetup) {
                Label(outcome.recoveryPresentation.primaryLabel, systemImage: "terminal")
            }
            .buttonStyle(ClaudePrimaryButtonStyle())
            .padding(.top, 12)
            steps(dark: dark)
                .padding(.top, 14)
            ClaudeManualCommandDisclosure()
                .padding(.top, 13)
        }
    }

    /// "official /usage · no login · never spends usage" — the trust line that makes a
    /// first-run user comfortable pressing the button.
    private var reassurance: some View {
        Text("Reads Claude's official \(Text("/usage").font(.system(size: 10.5, design: .monospaced))) panel through its CLI. Headroom never receives your password or tokens, and the check never spends usage.")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func steps(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("Takes about 20 seconds")
                    .font(.system(size: 11, weight: .semibold))
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
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: Circle())
                .overlay(Circle().strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
            text
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
                    .kerning(-0.2)
            }
            // W2A: the trust variant was three lines ending on the single word "approve."
            Text(outcome == .claudeLoginRequired
                 ? "Finish signing in in the Terminal that just opened. Headroom checks this account automatically."
                 : "Choose the option below in Terminal. Headroom connects as soon as you approve.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if outcome == .claudeTrustRequired {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("“Yes, I trust this folder”")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.vertical, 6)
                .padding(.leading, 9).padding(.trailing, 11)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
                .padding(.top, 11)
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
                .padding(.top, 13)
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
        return VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? nil : HeadroomMotion.settle) { open.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("Rather run it yourself?")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 5, verticalPadding: 3))
            if open {
                HStack(alignment: .top, spacing: 8) {
                    Text(ClaudeSetupSession.displayForm(of: command))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Button {
                        ClaudeSetupSession.copy(command, for: account)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
                    .foregroundStyle(.secondary)
                    .help("Copy command")
                    .accessibilityLabel("Copy command")
                }
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(ClaudeSetupStyle.codeBackground(dark: dark), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(.opacity)
            }
        }
    }
}

/// Full-width clay gradient primary — the card's one unmistakable action. Hover
/// brightens, press settles 0.98; both input-driven (no idle motion).
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
                // the 0.98 scale below is movement, so it carries its own modifier.
                .animation(HeadroomMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: hovering)
                .animation(HeadroomMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

/// B3A (Sep 2026): the one secondary button for every text-labelled action inside a card or
/// tile. The bare `HoverButtonStyle` is reserved for glyph controls and the popover footer.
/// Two sizes so the same chip fits a card foot (regular) and an account row (small).
///
/// B3H (Kyle, Sep 2026): "only have the button chrome show up on hover (like Refresh and
/// Quit)". Two chromes now. `.hover` — the popover — starts with **no** container at all and
/// brings today's hover fill, border and shadow up from zero when the pointer arrives, so a
/// card foot reads as sentence → action rather than sentence → boxes; the label stays 11.5
/// semibold in the chip ink, which is what still marks it as a control at rest. `.resting`
/// — Settings — keeps the container, because a bare label sitting beside a native bordered
/// button on a pane reads as text, not as something clickable.
struct SetupChipButtonStyle: ButtonStyle {
    enum Size {
        case regular
        case small

        var fontSize: CGFloat { self == .regular ? 12.5 : 11.5 }
        var horizontalPadding: CGFloat { self == .regular ? 13 : 10 }
        var verticalPadding: CGFloat { self == .regular ? 6 : 4 }
        var cornerRadius: CGFloat { self == .regular ? 8 : 7 }
    }

    /// B3H: `.hover` is the default — every chip in the popover takes it, which is all but
    /// three call sites, and only Settings has to ask for the resting container by name.
    enum Chrome {
        case hover
        case resting
    }

    var size: Size = .regular
    var chrome: Chrome = .hover

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
                .foregroundStyle(dark ? Color(white: 0.85) : Color(red: 0.24, green: 0.24, blue: 0.26))
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background {
                    shape
                        .fill(fillColor)
                        .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
                        .shadow(color: .black.opacity(dark ? 0 : 0.10), radius: 1, y: 1)
                        // B3H: one opacity on the whole container, so the `.hover` chrome
                        // arrives and leaves as a single object rather than three fades.
                        .opacity(chromeOpacity)
                }
                // S2A: the fill is a colour change and survives Reduce Motion; the 0.98 scale
                // below is the only movement here, so it resolves separately.
                .animation(HeadroomMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: hovering)
                .animation(HeadroomMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                // B3H: borrowed verbatim from `HoverButtonStyle` — extend the hit target 8pt
                // past the visible chip so a 22pt chip still clears the 40pt floor, then pull
                // the padding back out of layout so `ActionChipFlow` measures the chip alone.
                .padding(8)
                .contentShape(Rectangle())
                .padding(-8)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(HeadroomMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { hovering = $0 }
        }

        /// `.resting` keeps round 3's two-step fill. `.hover` reuses the *same* hover value
        /// as its arrival state and goes one step deeper while pressed, so the two chromes
        /// are the one recipe seen from different rest positions.
        private var fillColor: Color {
            switch chrome {
            case .resting:
                dark ? Color.white.opacity(hovering ? 0.14 : 0.10)
                     : Color.white.opacity(hovering ? 0.9 : 0.72)
            case .hover:
                if configuration.isPressed {
                    dark ? Color.white.opacity(0.20) : Color.white.opacity(1.0)
                } else {
                    dark ? Color.white.opacity(0.14) : Color.white.opacity(0.9)
                }
            }
        }

        private var borderColor: Color {
            dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        }

        /// The whole container is absent at rest in `.hover` — that absence is the point of
        /// B3H, and it is what lets the chip's label sit on the 34pt content axis (B3X).
        private var chromeOpacity: Double {
            switch chrome {
            case .resting:
                1
            case .hover:
                (hovering || configuration.isPressed) ? 1 : 0
            }
        }
    }
}
