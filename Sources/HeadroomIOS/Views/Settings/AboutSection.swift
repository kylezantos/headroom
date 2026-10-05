import SwiftUI

/// R23 / S4-C (approved): the identity card, the one-line "Get Headroom for Mac" row and the
/// maker's links. No tip jar on the phone this round.
struct AboutSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("About") {
            identityCard
                .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            // Kyle (S4-C): "make the language shorter so that it's not 2 rows for the Mac
            // link". The destination stays in the accessibility value, not on the row.
            linkRow(AboutLinks.getHeadroomForMac, showsDestination: false)
                .accessibilityIdentifier("headroom.about.mac")
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

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "\(version) (\(build))"
    }
}
