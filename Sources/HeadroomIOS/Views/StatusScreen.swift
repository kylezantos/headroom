import SwiftUI

struct StatusScreen: View {
    let title: String
    let message: String
    var isWaiting = false
    var onExploreDemo: (() -> Void)?
    var onRefresh: () async -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)
            Group {
                if isWaiting {
                    HalftonePillRow()
                } else {
                    VesselMark(fill: 0.40)
                }
            }
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
            StatusRefreshButton(onRefresh: onRefresh)
            if let onExploreDemo {
                Button("Explore Demo", systemImage: "sparkles") {
                    onExploreDemo()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Shows sample usage without connecting a Mac or account")
                .accessibilityIdentifier("headroom.demo.enter")
            }
            Spacer(minLength: 36)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
    }

}

/// KTD17: the button owns the check and its bounded tail; the status screen stays static.
private struct StatusRefreshButton: View {
    let onRefresh: () async -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.loadingDate) private var pinnedDate
    @State private var isChecking = false
    @State private var endedAt: Date?

    var body: some View {
        let current = recipe(at: pinnedDate ?? Date())
        LoadingTimeline(active: isChecking && !reduceMotion, until: current.waveEnd) { date in
            let frame = recipe(at: date)
            Button {
                Task { await refresh() }
            } label: {
                if frame.isWorking {
                    HStack(spacing: 8) {
                        HalftonePillRow(pills: frame.pills, sloshEndedAt: endedAt)
                        Text("Checking…")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(frame.isWorking)
        }
    }

    private func recipe(at date: Date) -> LoadingCheckRecipe {
        LoadingCheckRecipe(isChecking: isChecking, endedAt: endedAt, now: date, reduceMotion: reduceMotion)
    }

    private func refresh() async {
        guard !recipe(at: pinnedDate ?? Date()).isWorking else { return }
        endedAt = nil
        isChecking = true
        await onRefresh()
        endedAt = Date()
        isChecking = false
    }
}
