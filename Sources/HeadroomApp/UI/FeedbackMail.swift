#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import AppKit
import HeadroomCore

/// Settings › About › Send Feedback (2026-11-03 feedback plan, R1/R6, revised Nov 3 by Kyle):
/// one click reads the diagnostics and opens a pre-filled email in the user's mail app, where
/// they see and edit every line before sending. Headroom sends nothing itself.
@MainActor
enum FeedbackMail {
    enum Outcome: Equatable {
        case opened
        /// No mail app took the link (webmail users): the whole email is on the clipboard.
        case copied
        /// R8: demos and harnesses read no CLI and open nothing.
        case skipped
    }

    static func send(store: UsageStore, isInert: Bool) async -> Outcome {
        guard !isInert else { return .skipped }
        let diagnostics = FeedbackDiagnosticsCollector.diagnostics(
            store: store,
            platform: .current(appVersion: AppVersionLabel.plain),
            cliVersions: await CLIVersionReader.versions()
        )
        let email = FeedbackEmail(source: .mac, diagnostics: diagnostics)
        if NSWorkspace.shared.open(email.mailtoURL) { return .opened }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(email.clipboardText, forType: .string)
        return .copied
    }
}
