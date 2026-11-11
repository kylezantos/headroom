import SwiftUI

/// U3 step 6 / U8: a truncated account title opens this native sheet with the complete
/// resolved name, " · N" suffix included, so two accounts that share a long prefix stay
/// distinguishable. It names the provider for context and shows only the synced title,
/// which is an email only when the Mac uses that email as the account's name (KTD9).
struct PhoneTitleDisclosureSheet: View {
    let disclosed: DisclosedTitle

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProviderLogoView(providerID: disclosed.providerID, size: 14)
                    Text(disclosed.providerName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                }
                Text(disclosed.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("headroom.title-disclosure.title")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .navigationTitle("Account Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("headroom.title-disclosure.done")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
