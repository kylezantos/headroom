import SwiftUI

struct StatusScreen: View {
    let title: String
    let message: String
    var isWaiting = false
    var onRefresh: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)
            VesselMark(fill: isWaiting ? 0.18 : 0.40, isEmpty: isWaiting)
                .frame(width: 88, height: 124)
            VStack(spacing: 9) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            Spacer(minLength: 36)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
    }
}
