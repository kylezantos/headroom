import SwiftUI

struct MirrorView: View {
    let envelope: WidgetSnapshotEnvelope
    let syncInfo: IOSCompanionSyncInfo?
    @Binding var appearance: AppearanceSetting
    var onRefresh: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false

    var body: some View {
        // A per-minute `now` so "Updated N min ago" and the reset countdowns tick without a
        // data poll — same pattern the Mac popover uses.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderTileView(
                            provider: provider,
                            now: context.date,
                            entranceDelay: reduceMotion ? 0 : Double(index) * 0.055
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .refreshable { onRefresh() }
            // Native large title + subtitle (iOS 26): "Usage" is the screen title and
            // collapses into the bar on scroll; the freshness stamp rides along as the
            // subtitle instead of a hand-built header.
            .navigationTitle("Usage")
            .navigationSubtitle(updatedText(now: context.date))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheetView(envelope: envelope, syncInfo: syncInfo, appearance: $appearance)
            }
        }
    }

    private func updatedText(now: Date) -> String {
        if let updated = MirrorPresentation.updatedLabel(generatedAt: envelope.generatedAt, now: now) {
            return "Updated \(updated)"
        }
        return "Latest Mac snapshot"
    }
}
