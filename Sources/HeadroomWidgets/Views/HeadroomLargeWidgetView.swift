import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(envelope.providers) { provider in
                    LargeProviderSection(provider: provider, now: now)
                        .largeProviderCard()
                }
            }
            if !envelope.apiSpendProviders.isEmpty {
                Rectangle()
                    .fill(WidgetProviderStyle.hairline(scheme: scheme))
                    .frame(height: 1)
                    .padding(.vertical, 13)
                WidgetAPISpendSection(summaries: envelope.apiSpendProviders, now: now)
            }
            Spacer(minLength: 0)
            if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) {
                Text("from Mac · \(updated)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }
}

private struct LargeProviderSection: View {
    let provider: WidgetProviderSummary
    let now: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            WidgetUsageMeter(window: window(.weekly), fallbackLabel: "Weekly", now: now, showsResetInline: true, prominent: true)
            WidgetUsageMeter(window: window(.fiveHour), fallbackLabel: "5-hour", now: now, showsResetInline: true, prominent: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            WidgetProviderIcon(providerID: provider.id, size: 20)
            Text(provider.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                .lineLimit(1)
            if let planLabel = provider.planLabel {
                Text(planLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(WidgetProviderStyle.barTrack(scheme: scheme), in: Capsule())
            }
            Spacer(minLength: 4)
            if provider.freshness.needsAttention {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.severityColor(for: .low))
            }
        }
    }

    private func window(_ kind: WidgetWindowKind) -> WidgetWindowSummary? {
        provider.subscriptionWindows.first { $0.kind == kind }
    }
}

private struct LargeProviderCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(cardShape)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(WidgetProviderStyle.cardFill(scheme: scheme))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(WidgetProviderStyle.cardRing(scheme: scheme), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(WidgetProviderStyle.cardTopRim(scheme: scheme))
                    .frame(height: 1)
                    .padding(.horizontal, 7)
                    .allowsHitTesting(false)
            }
            .shadow(color: WidgetProviderStyle.cardEdgeShadow(scheme: scheme), radius: 1.5, x: 0, y: 1)
            .shadow(color: WidgetProviderStyle.cardCloseShadow(scheme: scheme), radius: scheme == .dark ? 11 : 6, x: 0, y: scheme == .dark ? 9 : 3)
            .shadow(color: WidgetProviderStyle.cardAmbientShadow(scheme: scheme), radius: 13, x: 0, y: 9)
    }
}

private extension View {
    func largeProviderCard() -> some View {
        modifier(LargeProviderCardModifier())
    }
}
