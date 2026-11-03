import SwiftUI
import UIKit

/// R23 / S4-C (approved): the identity card, the one-line "Get Headroom for Mac" row and the
/// maker's links. No tip jar on the phone this round.
struct AboutSection: View {
    /// Feedback plan R7: the sync state word the email names ("On", "Paused on your Mac").
    /// Never an account title.
    var syncStatus: String? = nil

    @Environment(\.openURL) private var openURL
    @State private var showsCopiedAlert = false

    var body: some View {
        Section("About") {
            identityCard
                .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            // Kyle (S4-C): "make the language shorter so that it's not 2 rows for the Mac
            // link". The destination stays in the accessibility value, not on the row.
            linkRow(AboutLinks.getHeadroomForMac, showsDestination: false)
                .accessibilityIdentifier("headroom.about.mac")
            feedbackRow
                .accessibilityIdentifier("headroom.about.feedback")
                .alert("Email copied", isPresented: $showsCopiedAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("No mail app opened, so the email is on your clipboard. Paste it into a message to \(FeedbackEmail.address).")
                }
        }

        Section("Made by \(AboutLinks.makerName)") {
            ForEach(AboutLinks.maker) { link in
                linkRow(link, showsDestination: true)
            }
        }
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            HeadroomAppIconView(size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Headroom")
                    .font(.title3.weight(.semibold))
                Text(AboutLinks.companionTagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Version \(versionText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func linkRow(_ link: AboutLink, showsDestination: Bool) -> some View {
        Button {
            openURL(link.url)
        } label: {
            HStack(spacing: 8) {
                Text(link.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if showsDestination {
                    Text(link.destination)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(link.title)
        .accessibilityValue(link.destination)
        .accessibilityHint("Opens in Safari")
    }

    /// Feedback plan R2/R7: opens a pre-filled email in the user's mail app. The phone sends
    /// nothing itself; if no mail app takes the link, the email is copied instead.
    private var feedbackRow: some View {
        Button {
            let email = FeedbackEmail(
                source: .iPhone,
                diagnostics: FeedbackDiagnostics(
                    appVersion: versionText,
                    operatingSystem: "iOS \(UIDevice.current.systemVersion)",
                    syncStatus: syncStatus
                )
            )
            openURL(email.mailtoURL) { accepted in
                guard !accepted else { return }
                UIPasteboard.general.string = email.clipboardText
                showsCopiedAlert = true
            }
        } label: {
            HStack(spacing: 8) {
                Text("Send Feedback")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("Email")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Send Feedback")
        .accessibilityValue(FeedbackEmail.address)
        .accessibilityHint("Opens an email in your mail app")
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "\(version) (\(build))"
    }
}
