import SwiftUI
import WidgetKit

struct HeadroomIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeadroomIOSWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .content(let envelope):
                content(envelope)
            case .disabled:
                IOSWidgetStatusView(title: "Sync Paused", message: "Enable iPhone sync on your Mac.")
            case .setupNeeded:
                IOSWidgetStatusView(title: "iCloud Needed", message: "Enable iCloud for Headroom.")
            case .waitingForMac:
                IOSWidgetStatusView(title: "Waiting for Mac", message: "Open Headroom on your Mac.")
            case .corrupt:
                IOSWidgetStatusView(title: "Unreadable Data", message: "Refresh Headroom on your Mac.")
            case .incompatibleSchema:
                IOSWidgetStatusView(title: "Update Needed", message: "Update Headroom on both devices.")
            }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(_ envelope: WidgetSnapshotEnvelope) -> some View {
        switch family {
        case .systemSmall:
            small(envelope)
        case .systemMedium:
            medium(envelope)
        default:
            large(envelope)
        }
    }

    private func small(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Weekly left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(envelope.weeklyProviders) { provider in
                providerWeeklyLine(provider)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func medium(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(envelope.providers) { provider in
                providerSummary(provider)
            }
        }
        .padding()
    }

    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(envelope.providers) { provider in
                providerSummary(provider, showsDetails: true)
            }
        }
        .padding()
    }

    private func providerWeeklyLine(_ provider: WidgetProviderSummary) -> some View {
        HStack(spacing: 6) {
            providerIcon(provider.id, size: 16)
            Text(provider.displayName)
                .font(.caption.weight(.medium))
            Spacer()
            Text(percent(provider.weeklyWindow))
                .font(.headline.monospacedDigit())
        }
    }

    private func providerSummary(_ provider: WidgetProviderSummary, showsDetails: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                providerIcon(provider.id, size: 15)
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent(for: provider.id))
                Spacer()
                if provider.freshness.needsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(provider.subscriptionWindows) { window in
                HStack {
                    Text(window.label)
                    Spacer()
                    Text("\(Int(window.percentRemaining.rounded()))%")
                        .monospacedDigit()
                }
                .font(.caption)
            }
            if showsDetails, let reset = provider.subscriptionWindows.first?.resetLabel {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private func symbol(for id: String) -> String {
        id == "claude" ? "sparkles" : "terminal"
    }

    @ViewBuilder
    private func providerIcon(_ id: String, size: CGFloat) -> some View {
        if let assetName = assetName(for: id) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol(for: id))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(accent(for: id))
                .accessibilityHidden(true)
        }
    }

    private func assetName(for id: String) -> String? {
        switch id {
        case "claude": "ClaudeBrandIcon"
        case "codex": "CodexBrandIcon"
        default: nil
        }
    }

    private func accent(for id: String) -> Color {
        id == "claude" ? .orange : .green
    }
}
