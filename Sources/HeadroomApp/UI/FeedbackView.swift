#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import AppKit
import SwiftUI
import HeadroomCore

/// The Settings sheet behind About › Send Feedback (2026-11-03 feedback plan, R6). It shows
/// the exact email before anything opens, so the user sees every line Headroom suggests, and
/// hands the email to their own mail app. Headroom sends nothing itself.
struct FeedbackView: View {
    let store: UsageStore
    /// R8: demos and harnesses read no CLI and open no mail app.
    let isInert: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var includesDiagnostics = true
    @State private var diagnostics: FeedbackDiagnostics?
    @State private var notice: Notice?

    private enum Notice: Equatable {
        case copied
        case noMailApp
        case demo
    }

    static let width: CGFloat = 480

    private var email: FeedbackEmail {
        FeedbackEmail(source: .mac, diagnostics: includesDiagnostics ? diagnostics : nil)
    }

    /// Diagnostics are read once, when the sheet opens; until then the buttons wait so the
    /// email never goes out without the block the switch promises.
    private var isReading: Bool { includesDiagnostics && diagnostics == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupToGroup) {
            VStack(alignment: .leading, spacing: SettingsMetrics.headerToContent) {
                Text("Send Feedback")
                    .font(SettingsType.tileTitle)
                    .kerning(SettingsType.tileTitleKerning)
                SettingsHelpText(text: "Headroom opens an email to \(FeedbackEmail.address) in your mail app. You can read and change all of it before you send it. Headroom doesn’t send anything on its own.")
            }

            VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
                SettingsSwitchRow(title: "Include diagnostics", isOn: $includesDiagnostics)
                SettingsHelpText(text: "App, macOS and CLI versions, and each account’s status. Never your email, account names or sign-in details.")
            }

            preview

            HStack(spacing: 8) {
                noticeText
                Spacer(minLength: 12)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") { copy() }
                    .disabled(isReading)
                Button("Open in Mail") { openInMail() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isReading)
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(width: Self.width)
        .task { await readDiagnostics() }
    }

    private var preview: some View {
        ScrollView {
            Text(isReading ? "Reading app and CLI versions…" : email.clipboardText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isReading ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(height: 220)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .accessibilityLabel("Email preview")
    }

    @ViewBuilder private var noticeText: some View {
        switch notice {
        case .copied:
            Text("Copied. Paste it into an email to \(FeedbackEmail.address).")
        case .noMailApp:
            Text("No mail app opened, so the email is copied. Paste it into an email to \(FeedbackEmail.address).")
        case .demo:
            Text("Demo: nothing was opened.")
        case nil:
            EmptyView()
        }
    }

    private func readDiagnostics() async {
        let versions: [FeedbackDiagnostics.CLI] = isInert
            ? CLIVersionReader.providers.map { .init(providerID: $0, version: .version("1.0.0")) }
            : await CLIVersionReader.versions()
        diagnostics = FeedbackDiagnosticsCollector.diagnostics(
            store: store,
            platform: .current(appVersion: AppVersionLabel.plain),
            cliVersions: versions
        )
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(email.clipboardText, forType: .string)
        notice = .copied
    }

    private func openInMail() {
        guard !isInert else {
            notice = .demo
            return
        }
        if NSWorkspace.shared.open(email.mailtoURL) {
            dismiss()
        } else {
            copy()
            notice = .noMailApp
        }
    }
}
