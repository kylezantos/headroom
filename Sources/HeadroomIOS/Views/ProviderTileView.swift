import SwiftUI

struct ProviderTileView: View {
    let provider: WidgetProviderSummary
    let now: Date
    var entranceDelay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var treatment: MirrorRowTreatment {
        MirrorPresentation.treatment(for: provider.freshness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            notice
            bars
        }
        .padding(17)
        .headroomTile()
        .opacity(reduceMotion || appeared ? 1 : 0)
        .offset(y: reduceMotion || appeared ? 0 : 10)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(HeadroomTheme.entranceAnimation.delay(entranceDelay)) {
                    appeared = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderLogoView(providerID: provider.id, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.headline.weight(.semibold))
                if let pillText = treatment.pillText {
                    Text(pillText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.16), in: Capsule())
                }
            }
            Spacer(minLength: 8)
            if let planLabel = provider.planLabel, !planLabel.isEmpty {
                Text(planLabel.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HeadroomTheme.secondaryText(scheme))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HeadroomTheme.barTrack(scheme), in: Capsule())
            }
        }
    }

    @ViewBuilder private var notice: some View {
        if let noticeText = treatment.noticeText {
            Label(noticeText, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HeadroomTheme.severityColor(for: .low, scheme: scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HeadroomTheme.severityColor(for: .low, scheme: scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var bars: some View {
        VStack(spacing: 14) {
            ForEach(provider.subscriptionWindows) { window in
                UsageBarView(window: window, now: now, dimmed: treatment.isDimmed)
            }
        }
    }

    // (Plan-renews row removed — Jul 2026 density audit cut renewal dates from all UI.)
}
