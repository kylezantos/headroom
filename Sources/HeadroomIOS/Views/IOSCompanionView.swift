import SwiftUI
import WidgetKit

struct IOSCompanionView: View {
    @State private var state: IOSWidgetSnapshotState = .waitingForMac
    @State private var updatedAt: Date?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Headroom")
                .toolbar {
                    Button("Refresh") { refresh() }
                }
        }
        .onAppear { refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .content(let envelope):
            List {
                Section {
                    ForEach(envelope.providers) { provider in
                        providerRow(provider)
                    }
                } header: {
                    Text(statusText(for: envelope))
                }
            }
        case .disabled:
            IOSSyncStatusView(
                title: "iPhone Sync Paused",
                message: "Enable iPhone sync in Headroom Settings on your Mac."
            )
        case .setupNeeded:
            IOSSyncStatusView(
                title: "iCloud Not Available",
                message: "Make sure iCloud is enabled for Headroom on this iPhone and your Mac."
            )
        case .waitingForMac:
            IOSSyncStatusView(
                title: "Waiting for Mac",
                message: "Enable iPhone sync in Headroom on your Mac, then open this app again."
            )
        case .corrupt:
            IOSSyncStatusView(
                title: "Snapshot Unreadable",
                message: "Open Headroom on your Mac to publish a fresh snapshot."
            )
        case .incompatibleSchema:
            IOSSyncStatusView(
                title: "Update Needed",
                message: "Update Headroom on your Mac and iPhone so their snapshot formats match."
            )
        }
    }

    private func providerRow(_ provider: WidgetProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                freshnessLabel(provider.freshness)
            }
            ForEach(provider.subscriptionWindows) { window in
                HStack {
                    Text(window.label)
                    Spacer()
                    Text("\(Int(window.percentRemaining.rounded()))% left")
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private func freshnessLabel(_ freshness: WidgetProviderFreshness) -> some View {
        Group {
            switch freshness {
            case .pending:
                Text("Pending")
            case .live:
                Text("Live")
            case .stale(_, let needsAttention):
                Text(needsAttention ? "Needs attention" : "Stale")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statusText(for envelope: WidgetSnapshotEnvelope) -> String {
        let generated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: updatedAt ?? .now)
        return generated.map { "Published \($0)" } ?? "Latest Mac snapshot"
    }

    private func refresh() {
        let cache = WidgetSnapshotCache.appGroup()
        let sync = iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore())
        let read = sync.read()
        if case .snapshot(let envelope) = read {
            try? cache.write(envelope.snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
        state = IOSWidgetSnapshotState.from(cacheRead: cache.read(), syncRead: read)
        updatedAt = .now
    }
}
