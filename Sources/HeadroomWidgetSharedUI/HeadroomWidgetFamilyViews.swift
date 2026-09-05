#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI
import WidgetKit

// L9P: the small and medium family bodies live here rather than in the widget extension
// so Settings › Widgets & iPhone can render the *real* widget layout instead of a
// hand-kept mock. Nothing WidgetKit-family-specific is in these two views — the
// `widgetFamily` switch, `containerBackground`, and `widgetContentMargins` all stay in
// the extension's `HeadroomWidgetView`, which is what makes the move possible.
//
// The brand mark is injected because the two hosts resolve it differently: the widget
// extension draws `BrandIcons.xcassets` through `HeadroomWidgetProviderIcon`, while the
// Mac app draws the same marks from its bundled SVGs (`ProviderLogoView`) and carries no
// brand asset catalog. A generic parameter keeps that swap allocation-free on the shipping
// widget path; the `where Mark == HeadroomWidgetProviderIcon` convenience inits below mean
// the extension's call sites are unchanged.

/// Small widget: one weekly meter per provider under a quiet column header.
///
/// The provider lines form one compact group centered in the space below the header.
/// Hierarchy has one clear step per level: 11pt header (defers), 13pt brand-accent names,
/// 16pt bold percent (the glance payload, same step as the large widget's prominent meters).
///
/// Only the provider's overall weekly window appears here — one line per provider.
/// Model-specific sub-limits (Claude's "Weekly (Fable)") are detail for the large widget
/// and the popover; at this size a third line reads as a phantom third provider.
public struct HeadroomSmallWidgetView<Mark: View>: View {
    private let envelope: WidgetSnapshotEnvelope
    private let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    public init(
        envelope: WidgetSnapshotEnvelope,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.envelope = envelope
        self.mark = mark
    }

    public var body: some View {
        let providers = envelope.widgetProviders
        VStack(alignment: .leading, spacing: 0) {
            Text(providers.contains(where: { $0.primarySubscriptionWindow?.isBillingPeriod == true }) ? "Usage left" : "Weekly left")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(providers) { provider in
                    HeadroomWidgetProviderWeeklyLine(provider: provider, mark: mark)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the meters have room to breathe.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}

public extension HeadroomSmallWidgetView where Mark == HeadroomWidgetProviderIcon {
    init(envelope: WidgetSnapshotEnvelope) {
        self.init(envelope: envelope) { providerID, size in
            HeadroomWidgetProviderIcon(providerID: providerID, size: size)
        }
    }
}

public struct HeadroomMediumWidgetView<Mark: View>: View {
    private let envelope: WidgetSnapshotEnvelope
    private let now: Date
    private let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    public init(
        envelope: WidgetSnapshotEnvelope,
        now: Date,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.envelope = envelope
        self.now = now
        self.mark = mark
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The two-column region flexes to fill the tile so the center rule reads as a
            // true column separator (full height, small symmetric inset) rather than a stub
            // tied to the text block. The footer / API-spend row sit below it either way.
            if envelope.apiSpendProviders.isEmpty {
                providerColumns
                footerText(prefix: "from Mac · ")
            } else {
                providerColumns
                // Same shared strip as the large widget; the footer drops its "from Mac"
                // prefix here because the medium tile's width carries icons + amounts too.
                HeadroomWidgetAPISpendStrip(
                    summaries: envelope.apiSpendProviders,
                    now: now,
                    footerText: Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now)
                )
            }
        }
        // KTD1: rely on WidgetKit's default content margins for the outer margin;
        // keep only a small residual so the two-column meters do not feel cramped.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    @ViewBuilder private var providerColumns: some View {
        let providers = envelope.widgetProviders
        if providers.count <= 1 {
            ForEach(providers) { provider in
                HeadroomWidgetMediumProviderColumn(provider: provider, dense: false, mark: mark)
            }
        } else if providers.count == 2 {
            HStack(alignment: .top, spacing: 12) {
                ForEach(providers) { provider in
                    HeadroomWidgetMediumProviderColumn(provider: provider, dense: false, mark: mark)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay {
                // The column rule is drawn as a full-height overlay rather than an inline
                // sibling so it spans the entire two-column band — headers included — and
                // isn't pulled short by how each column's content distributes vertically.
                // Two equal-width columns with a symmetric gap put the tile's horizontal
                // centre inside that gap, so a centred 1pt rule lands cleanly between them.
                // Guarded to the 2-provider layout, which is the app's invariant.
                Rectangle()
                    .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 6)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    HeadroomWidgetMediumProviderColumn(provider: provider, dense: true, mark: mark)
                    if index < providers.count - 1 {
                        Rectangle()
                            .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder private func footerText(prefix: String) -> some View {
        if let updated = Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) {
            Text("\(prefix)\(updated)")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

public extension HeadroomMediumWidgetView where Mark == HeadroomWidgetProviderIcon {
    init(envelope: WidgetSnapshotEnvelope, now: Date) {
        self.init(envelope: envelope, now: now) { providerID, size in
            HeadroomWidgetProviderIcon(providerID: providerID, size: size)
        }
    }
}

/// One prominent weekly line per provider — brand mark + name + percent + bar for the
/// provider's overall weekly window. Dims when that window is missing rather than dropping
/// the row. Kept in step with the iOS small widget's `providerWeeklyLine`.
struct HeadroomWidgetProviderWeeklyLine<Mark: View>: View {
    let provider: WidgetProviderSummary
    @ViewBuilder let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let window = provider.primarySubscriptionWindow
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                mark(provider.id, 16)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(percent(window))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(window == nil ? HeadroomWidgetStyle.secondaryText(scheme: scheme) : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 42, alignment: .trailing)
            }
            HeadroomWidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil
            )
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }
}

struct HeadroomWidgetMediumProviderColumn<Mark: View>: View {
    let provider: WidgetProviderSummary
    let dense: Bool
    @ViewBuilder let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                mark(provider.id, 18)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme))
                }
            }
            if provider.displaySubscriptionWindows.isEmpty {
                HeadroomWidgetUsageMeter(window: nil, fallbackLabel: "Weekly", compact: true, scale: dense ? .dense : nil)
            } else {
                ForEach(provider.displaySubscriptionWindows) { window in
                    HeadroomWidgetUsageMeter(window: window, fallbackLabel: window.label, compact: true, scale: dense ? .dense : nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
