import SwiftUI

struct StatusScreen: View {
    let title: String
    let message: String
    var isWaiting = false
    var onRefresh: () async -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isRefreshing = false

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
            Button {
                Task { await refresh() }
            } label: {
                if isRefreshing {
                    Label {
                        Text("Checking…")
                    } icon: {
                        ProgressView()
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isRefreshing)
            Spacer(minLength: 36)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await onRefresh()
        isRefreshing = false
    }
}
