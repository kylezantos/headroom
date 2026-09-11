#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

// WCF5: the large body moved out of `Sources/HeadroomWidgets/Views` into the shared module
// so the iPhone extension stops carrying a 100-line copy of it, and so Settings could
// render it from the Mac app. Like the small and medium bodies it takes the brand mark as
// a generic parameter — the extensions draw `BrandIcons.xcassets`, the app draws its
// bundled SVGs. This file deliberately does not import WidgetKit (see the alias note in
// `HeadroomWidgetFamilyViews.swift`).

/// Large widget: every provider's full meter set, then the API-spend strip or a bare
/// footer.
///
/// WCL1: three reachable density tiers with two type steps, **no inter-provider hairline**
/// (air separates them), and a weighted vertical rhythm — the top and bottom edge gaps take
/// `edgeGapWeight` (0.6) of a provider gap, so the tile gains a frame instead of the
/// content floating in a void.
public struct HeadroomLargeWidgetView<Mark: View>: View {
    private let envelope: WidgetSnapshotEnvelope
    private let now: Date
    private let footerPrefix: String
    private let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    public init(
        envelope: WidgetSnapshotEnvelope,
        now: Date,
        footerPrefix: String = HeadroomWidgetCopy.macFooterPrefix,
        @ViewBuilder mark: @escaping (String, CGFloat) -> Mark
    ) {
        self.envelope = envelope
        self.now = now
        self.footerPrefix = footerPrefix
        self.mark = mark
    }

    public var body: some View {
        let density = LargeWidgetDensity(envelope: envelope)
        let scale = WidgetTypeScale.scale(for: .large, step: density.typeStep)
        HeadroomLargeRhythm(
            gapFloor: CGFloat(density.providerGapFloor),
            edgeWeight: CGFloat(density.edgeGapWeight)
        ) {
            ForEach(envelope.widgetProviders) { provider in
                HeadroomLargeProviderSection(
                    provider: provider,
                    now: now,
                    density: density,
                    scale: scale,
                    mark: mark
                )
            }
            trailingBlock(scale: scale)
        }
        // WCF4: horizontal residual 2 on both hosts (the macOS `8` is gone); the hosts now
        // supply identical vertical margins, so both platforms distribute the same slack.
        .padding(.horizontal, WidgetMetrics.residualMargin)
    }

    @ViewBuilder
    private func trailingBlock(scale: WidgetTypeScale) -> some View {
        if !envelope.apiSpendProviders.isEmpty {
            // WCW6/WCL4: large keeps the spend hairline — a widget has no tiles, so this
            // one rule does the job the popover gives a separate card.
            HeadroomWidgetAPISpendStrip(
                summaries: envelope.apiSpendProviders,
                now: now,
                family: .large,
                scale: scale,
                footerText: HeadroomWidgetCopy.footerText(prefix: footerPrefix, capturedAt: envelope.generatedAt, now: now),
                showsRule: true
            )
        } else if HeadroomWidgetCopy.footerText(prefix: footerPrefix, capturedAt: envelope.generatedAt, now: now) != nil {
            // Checked here rather than inside the stamp so an absent capture time leaves the
            // rhythm with one fewer block instead of a zero-height block and a spare gap.
            HeadroomWidgetFooterStamp(
                text: footerPrefix,
                capturedAt: envelope.generatedAt,
                now: now,
                size: scale.footer
            )
        }
    }
}

public extension HeadroomLargeWidgetView where Mark == HeadroomWidgetProviderIcon {
    init(envelope: WidgetSnapshotEnvelope, now: Date, footerPrefix: String = HeadroomWidgetCopy.macFooterPrefix) {
        self.init(envelope: envelope, now: now, footerPrefix: footerPrefix) { providerID, size in
            HeadroomWidgetProviderIcon(providerID: providerID, size: size)
        }
    }
}

/// One provider block: an identity header with the mark in the gutter, then every meter on
/// the content axis (WCF3) at the tier's rhythm (WCL2).
struct HeadroomLargeProviderSection<Mark: View>: View {
    let provider: WidgetProviderSummary
    let now: Date
    let density: LargeWidgetDensity
    let scale: WidgetTypeScale
    @ViewBuilder let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let slot = density.providerIconSize
        VStack(alignment: .leading, spacing: 0) {
            header(slot: slot)
            meters
                .padding(.leading, CGFloat(slot + WidgetMetrics.markGap))
                .padding(.top, CGFloat(density.headerSpacing))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// WCF7 ladder for this row: the mark, the plan pill and the attention glyph stay
    /// whole; the provider name gives first (`lineLimit(1)` + `.tail`, and it outranks the
    /// stale sentence beside it); the pill drops whole only when the row cannot hold it at
    /// all, which is what the `ViewThatFits` pair around it expresses. The stale sentence
    /// is the second flexible element and truncates after the name.
    private func header(slot: Double) -> some View {
        HStack(spacing: WidgetMetrics.markGap) {
            mark(provider.id, CGFloat(slot))
                .frame(width: CGFloat(slot), height: CGFloat(slot))
            // WCD1: neutral names — colour lives in the mark and in severity events.
            Text(provider.displayName)
                .font(.system(size: scale.name, weight: .semibold))
                .kerning(scale.nameKerning)
                .foregroundStyle(HeadroomWidgetStyle.accountTitle(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .widgetCapHeightCentered(size: scale.name, weight: .semibold)
            if density.showsPlanPill, let plan = PlanLabelPresentation.displayName(provider.planLabel) {
                // WCF7: the pill is the less flexible sibling (min 0 … ideal ≈ 35 against
                // the name's ellipsis … full run), so an `HStack` offers it its ideal
                // before it truncates the name — and the `EmptyView` rung drops it whole
                // rather than squeezing it if a row ever gets that tight. No `fixedSize()`
                // here: that would propose an unspecified width and defeat the fallback.
                ViewThatFits(in: .horizontal) {
                    planPill(plan)
                    EmptyView()
                }
            }
            if provider.freshness.needsAttention {
                HeadroomWidgetAttentionGlyph(kind: .provider, size: 10)
                    .fixedSize()
                    .widgetCapHeightCentered(size: scale.name, weight: .semibold)
            }
            // WCM5-v: large is the one family with room to print the on-wire reason.
            if let message = staleMessage {
                Text(message)
                    .font(.system(size: scale.countdown, weight: .regular))
                    .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // WCF7: the second flexible element in the row gives before the name
                    // does. Negative priority (not a positive one on the name) is the safe
                    // direction — a higher-priority name would be offered the whole row and
                    // could squeeze the pill and the glyph out of it.
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
        }
    }

    /// WCW9: the popover's own pill object at the popover's ratios — capsule 15, 9.5 medium
    /// kern 0.2, `secondary @ 0.12`, no ring, `planLabel` ink. Roomy and regular only.
    private func planPill(_ plan: String) -> some View {
        Text(plan)
            .font(.system(size: scale.pillLabel, weight: .medium))
            .kerning(0.2)
            .foregroundStyle(HeadroomWidgetStyle.planLabel(scheme: scheme))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: CGFloat(scale.pillHeight))
            .background(HeadroomWidgetStyle.secondaryText(scheme: scheme).opacity(0.12), in: Capsule())
    }

    private var staleMessage: String? {
        guard case .stale(let message, _) = provider.freshness else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder private var meters: some View {
        let windows = provider.displaySubscriptionWindows
        VStack(alignment: .leading, spacing: CGFloat(density.meterSpacing)) {
            if windows.isEmpty {
                meter(nil)
            } else {
                ForEach(windows) { window in
                    meter(window)
                }
            }
            // Model-specific weekly sub-limits (Claude's Fable, Codex's Spark) follow the
            // subscription rows; only the large family has room for them.
            ForEach(provider.extraWeeklyWindows) { window in
                meter(window)
            }
        }
    }

    private func meter(_ window: WidgetWindowSummary?) -> some View {
        HeadroomWidgetUsageMeter(
            window: window,
            fallbackLabel: HeadroomWidgetCopy.fallbackWindowLabel,
            now: now,
            scale: scale,
            family: .large,
            providerIsLive: provider.freshness == .live,
            showsResetInline: true
        )
    }
}

/// WCL1-(3): the vertical rhythm of the large tile, as a layout rather than a column of
/// equal `Spacer`s.
///
/// Every gap — top edge, between blocks, bottom edge — flexes, but the two **edge** gaps
/// take `edgeWeight` (0.6) of the share an internal gap takes, so slack pools between the
/// providers and the tile gains a frame instead of the content floating in a void. Each
/// gap's floor is its own weight × `gapFloor`, so the ratio holds when the tile is full and
/// the blocks simply stack at their floors. This is the KTD-D amendment: the tokens and the
/// edge weighting change, the structure (one flexible gap per seam) does not.
///
/// Written as a `Layout` because `Spacer` has no weight: SwiftUI splits leftover height
/// between equal-priority spacers evenly, and `layoutPriority` removes a spacer from the
/// split rather than scaling it.
struct HeadroomLargeRhythm: Layout {
    let gapFloor: CGFloat
    let edgeWeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        let content = heights(of: subviews, width: width).reduce(0, +)
        let minimum = content + minimumGapTotal(blockCount: subviews.count)
        return CGSize(width: width, height: max(proposal.height ?? minimum, minimum))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let measured = heights(of: subviews, width: bounds.width)
        let weights = gapWeights(blockCount: subviews.count)
        let slack = bounds.height - measured.reduce(0, +)
        let totalWeight = weights.reduce(0, +)
        let gaps: [CGFloat]
        if totalWeight > 0, slack > minimumGapTotal(blockCount: subviews.count) {
            gaps = weights.map { slack * $0 / totalWeight }
        } else {
            // Not enough height for the weighted distribution: every gap sits on its floor
            // and the blocks keep their measured heights, so nothing overlaps (WCF7).
            gaps = weights.map { $0 * gapFloor }
        }

        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            y += gaps[index]
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: measured[index])
            )
            y += measured[index]
        }
    }

    /// `blockCount + 1` gaps: leading edge, one per seam, trailing edge.
    private func gapWeights(blockCount: Int) -> [CGFloat] {
        guard blockCount > 0 else { return [] }
        var weights = [CGFloat](repeating: 1, count: blockCount + 1)
        weights[0] = edgeWeight
        weights[blockCount] = edgeWeight
        return weights
    }

    private func minimumGapTotal(blockCount: Int) -> CGFloat {
        gapWeights(blockCount: blockCount).reduce(0) { $0 + $1 * gapFloor }
    }

    private func heights(of subviews: Subviews, width: CGFloat) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
    }
}
