#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

// L9P: the family bodies live here rather than in the widget extensions so Settings ›
// Widgets & iPhone can render the *real* widget layout instead of a hand-kept mock, and
// so the iPhone extension has no second copy to drift (WCF5). Nothing WidgetKit-family-
// specific is in these views — the `widgetFamily` switch, `containerBackground` and
// `widgetContentMargins` all stay in each host, which is what makes the move possible.
//
// The brand mark is injected because the three hosts resolve it differently: both widget
// extensions draw `BrandIcons.xcassets` through `HeadroomWidgetProviderIcon`, while the
// Mac app draws the same marks from its bundled SVGs (`ProviderLogoView`) and carries no
// brand asset catalog. A generic parameter keeps that swap allocation-free on the shipping
// widget path; the `where Mark == HeadroomWidgetProviderIcon` convenience inits below mean
// the extensions' call sites are unchanged.
//
// WCF7 runs through every row here: nothing overlaps and nothing clips. Marks, plan pills,
// attention glyphs, numerals and bars are fixed; the provider name (and, on large, the
// stale sentence) is the element that gives, with `lineLimit(1)` + `.tail`. No
// `minimumScaleFactor` anywhere.

// WC-merge: `WidgetKit.WidgetFamily` and Core's `WidgetFamily` (WCF1) collide in any file
// that imports both. This file deliberately does **not** import WidgetKit, so the bare
// name resolves unambiguously in all four build configurations — Core-as-module (SPM,
// the Mac app, the macOS extension) and Core-compiled-in (the iOS extension). Files that
// do import WidgetKit spell it `HeadroomWidgetFamily` (the Core typealias) instead.

// MARK: - Small

/// Small widget: one glance meter per provider under a quiet column header (WCL5).
///
/// Only the provider's primary subscription window appears — one row per provider.
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
        let scale = WidgetTypeScale.scale(for: .small)
        let slot = WidgetMetrics.markSlot(for: .small)
        let axis = WidgetMetrics.contentAxis(for: .small)
        VStack(alignment: .leading, spacing: 0) {
            // WCW7: the noun is decided in Core from the shown providers' windows, so a
            // mixed or pending set says "Usage left" rather than mislabelling a period.
            // WCF3: the caption starts on the content axis; only the mark sits in the gutter.
            Text(envelope.smallHeaderTitle)
                .font(.system(size: scale.header, weight: .medium))
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, axis)
            // WCL5: the slack goes to the payload, not to a caption's void — a fixed 22
            // under the header, then the rows, then one trailing spacer.
            VStack(alignment: .leading, spacing: WidgetMetrics.smallRowToRow) {
                ForEach(envelope.widgetProviders) { provider in
                    glanceRow(provider, scale: scale, slot: slot)
                }
            }
            .padding(.top, WidgetMetrics.smallHeaderToRows)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // WCF4: the host supplies the system content margin; this is the 2pt residual.
        .padding(WidgetMetrics.residualMargin)
    }

    /// WCM4/WCM5: the row reads `displayPercentRemaining` and both freshness levels through
    /// the shared meter, so a retired window prints "—" and a stale provider dims.
    /// The mark is drawn here, in the gutter, so the meter's own content starts on the axis
    /// (WCF3); `glanceMarkSlot` only tells the meter which box height to cap-centre the
    /// name against — it must not add a leading inset of its own.
    private func glanceRow(_ provider: WidgetProviderSummary, scale: WidgetTypeScale, slot: Double) -> some View {
        HStack(alignment: .top, spacing: WidgetMetrics.markGap) {
            // WCL6: the mark box is the glance row's line box (the 18pt numeral sets it), so
            // the mark's centre lands on the name's cap centre rather than at the row's top.
            mark(provider.id, CGFloat(slot))
                .frame(width: CGFloat(slot), height: CGFloat(slot))
                .frame(width: CGFloat(slot), height: CGFloat((scale.numeral * 1.2).rounded()), alignment: .center)
            HeadroomWidgetUsageMeter(
                window: provider.primarySubscriptionWindow,
                fallbackLabel: HeadroomWidgetCopy.fallbackWindowLabel,
                // A glance row never prints a countdown, so `now` is inert here.
                now: Date(),
                scale: scale,
                family: .small,
                providerIsLive: provider.freshness == .live,
                glance: true,
                glanceName: provider.displayName,
                glanceMarkSlot: 0
            )
        }
    }
}

public extension HeadroomSmallWidgetView where Mark == HeadroomWidgetProviderIcon {
    init(envelope: WidgetSnapshotEnvelope) {
        self.init(envelope: envelope) { providerID, size in
            HeadroomWidgetProviderIcon(providerID: providerID, size: size)
        }
    }
}

// MARK: - Medium

/// Medium widget: two equal provider columns over a spend strip or a bare footer.
///
/// WCL4 (option B, adopted 2026-09-11): the columns are separated by a 28pt gutter with a
/// one-device-pixel rule **confined to the meter band**, and the spend row is separated by
/// air rather than a second hairline — so the tile reads as one surface instead of a T of
/// four boxes.
public struct HeadroomMediumWidgetView<Mark: View>: View {
    private let envelope: WidgetSnapshotEnvelope
    private let now: Date
    private let footerPrefix: String
    private let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

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
        let scale = WidgetTypeScale.scale(for: .medium)
        // WCF7/WCL7: the 14pt of air above the spend row is the design floor, not a
        // guarantee the tile can pay for it. The 6.1" iPhone's medium box is 130pt tall and
        // two full columns plus the spend row measure ~127 before the air, so a hard
        // `Spacer(minLength: 14)` pushed the strip 3pt past the content box (measured, not
        // computed). The second rung yields the air rather than the content: a 0 floor still
        // leaves the columns' own bottom padding between them and the strip, and every tile
        // that can afford 14 still gets 14.
        ViewThatFits(in: .vertical) {
            stack(scale: scale, spendAir: CGFloat(WidgetMetrics.mediumSpendAirFloor))
            stack(scale: scale, spendAir: 0)
        }
        // WCF4: host margins + a 2pt residual on every edge, both platforms.
        .padding(WidgetMetrics.residualMargin)
    }

    private func stack(scale: WidgetTypeScale, spendAir: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            providerColumns(scale: scale)
            // WCL4: a flexible spacer replaces the spend hairline.
            Spacer(minLength: spendAir)
            if envelope.apiSpendProviders.isEmpty {
                HeadroomWidgetFooterStamp(
                    text: footerPrefix,
                    capturedAt: envelope.generatedAt,
                    now: now,
                    size: scale.footer
                )
            } else {
                HeadroomWidgetAPISpendStrip(
                    summaries: envelope.apiSpendProviders,
                    now: now,
                    family: .medium,
                    scale: scale,
                    footerText: HeadroomWidgetCopy.footerText(prefix: footerPrefix, capturedAt: envelope.generatedAt, now: now),
                    showsRule: false
                )
            }
        }
    }

    @ViewBuilder
    private func providerColumns(scale: WidgetTypeScale) -> some View {
        let providers = envelope.widgetProviders
        if providers.count <= 1 {
            // L10: a single provider takes the full width on the same axis — no half-tile
            // column, no rule to draw.
            ForEach(providers) { provider in
                HeadroomWidgetMediumProviderColumn(provider: provider, now: now, scale: scale, mark: mark)
            }
        } else {
            HStack(alignment: .top, spacing: CGFloat(WidgetMetrics.mediumGutter)) {
                ForEach(providers) { provider in
                    HeadroomWidgetMediumProviderColumn(provider: provider, now: now, scale: scale, mark: mark)
                }
            }
            .overlayPreferenceValue(HeadroomMeterBandKey.self) { anchors in
                centreRule(anchors: anchors, scale: scale)
            }
        }
    }

    /// WCL4: the rule spans the meter band only — from the cap top of the first meter label
    /// to the bottom of the last bar in the *taller* column — measured off the columns'
    /// own anchors rather than guessed, and centred in the 28pt gutter so every bar ends
    /// 14 clear of it.
    private func centreRule(anchors: HeadroomMeterBandAnchors, scale: WidgetTypeScale) -> some View {
        GeometryReader { proxy in
            let capInset = HeadroomWidgetTypography.capTopInset(size: scale.label, weight: .medium)
            let tops = anchors.tops.map { proxy[$0].y + capInset }
            let bottoms = anchors.bottoms.map { proxy[$0].y }
            if let top = tops.min(), let bottom = bottoms.max(), bottom > top {
                Rectangle()
                    .fill(HeadroomWidgetStyle.widgetHairline(scheme: scheme))
                    .frame(
                        width: HeadroomWidgetStyle.hairlineWidth(displayScale: displayScale),
                        height: bottom - top
                    )
                    .position(x: proxy.size.width / 2, y: (top + bottom) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public extension HeadroomMediumWidgetView where Mark == HeadroomWidgetProviderIcon {
    init(envelope: WidgetSnapshotEnvelope, now: Date, footerPrefix: String = HeadroomWidgetCopy.macFooterPrefix) {
        self.init(envelope: envelope, now: now, footerPrefix: footerPrefix) { providerID, size in
            HeadroomWidgetProviderIcon(providerID: providerID, size: size)
        }
    }
}

/// One medium column: an identity header with the mark in the gutter, then the provider's
/// subscription meters on the content axis (WCF3), 6 under the header and 10 apart (WCL2).
struct HeadroomWidgetMediumProviderColumn<Mark: View>: View {
    let provider: WidgetProviderSummary
    let now: Date
    let scale: WidgetTypeScale
    @ViewBuilder let mark: (String, CGFloat) -> Mark

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let slot = WidgetMetrics.markSlot(for: .medium)
        let axis = WidgetMetrics.contentAxis(for: .medium)
        VStack(alignment: .leading, spacing: 0) {
            header(slot: slot)
            meters
                // WCL4: the column publishes its own meter band so the shared rule can be
                // clipped to the taller of the two. The anchors are attached *inside* the
                // paddings on purpose — they must describe the meters themselves, not the
                // padded box, or the rule would start 6pt above the first label.
                .anchorPreference(key: HeadroomMeterBandKey.self, value: .top) {
                    HeadroomMeterBandAnchors(tops: [$0])
                }
                .transformAnchorPreference(key: HeadroomMeterBandKey.self, value: .bottom) {
                    $0.bottoms.append($1)
                }
                .padding(.leading, CGFloat(axis))
                .padding(.top, CGFloat(WidgetMetrics.mediumHeaderToMeter))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// WCF7: the name is the only flexible element — mark, glyph and the gap are fixed, so
    /// a long display name truncates instead of pushing the glyph out of the column.
    /// WCD1: names take `accountTitle`; colour lives in the mark and in severity events.
    private func header(slot: Double) -> some View {
        HStack(spacing: WidgetMetrics.markGap) {
            mark(provider.id, CGFloat(slot))
                .frame(width: CGFloat(slot), height: CGFloat(slot))
            Text(provider.displayName)
                .font(.system(size: scale.name, weight: .semibold))
                .kerning(scale.nameKerning)
                .foregroundStyle(HeadroomWidgetStyle.accountTitle(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .widgetCapHeightCentered(size: scale.name, weight: .semibold)
            Spacer(minLength: 4)
            if provider.freshness.needsAttention {
                // WCM5: attention comes off the severity ramp (R2C5) — neutral ink, the
                // circle glyph, cap-centred against the name.
                HeadroomWidgetAttentionGlyph(kind: .provider, size: 10)
                    .fixedSize()
                    .widgetCapHeightCentered(size: scale.name, weight: .semibold)
            }
        }
    }

    @ViewBuilder private var meters: some View {
        let windows = provider.displaySubscriptionWindows
        VStack(alignment: .leading, spacing: CGFloat(WidgetMetrics.mediumMeterToMeter)) {
            if windows.isEmpty {
                meter(nil)
            } else {
                ForEach(windows) { window in
                    meter(window)
                }
            }
        }
    }

    private func meter(_ window: WidgetWindowSummary?) -> some View {
        // WCL9: medium ships the countdown switch; WCF2's two-rung ladder drops it whole
        // where the column cannot hold it, which in practice is the 6.1" iPhone.
        HeadroomWidgetUsageMeter(
            window: window,
            fallbackLabel: HeadroomWidgetCopy.fallbackWindowLabel,
            now: now,
            scale: scale,
            family: .medium,
            providerIsLive: provider.freshness == .live,
            showsResetInline: true
        )
    }
}

// MARK: - Shared pieces

/// WCW3: one footer treatment for medium and large. The platform difference is the prefix
/// the host passes in; the stamp itself is monospaced-digit so it stops reflowing once a
/// minute, and takes `secondaryText` rather than the tertiary tier it used to.
struct HeadroomWidgetFooterStamp: View {
    let text: String
    let capturedAt: Date?
    let now: Date
    let size: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let stamp = HeadroomWidgetCopy.footerText(prefix: text, capturedAt: capturedAt, now: now) {
            Text(stamp)
                .font(.system(size: size, weight: .medium).monospacedDigit())
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Strings the family bodies share with both hosts. Window labels and the small header
/// live in Core (WCW2/WCW7); these three are host-composition, not data.
public enum HeadroomWidgetCopy {
    /// WCW7: "Usage" at every fallback site — a pending Grok or Cursor row must not claim a
    /// weekly limit it does not have.
    public static let fallbackWindowLabel = "Usage"
    /// WCW3: the sentence is true on the Mac and false on the phone, which is the one place
    /// the mirror rule licenses a split.
    public static let macFooterPrefix = "Updated "
    public static let iosFooterPrefix = "From Mac · "

    public static func footerText(prefix: String, capturedAt: Date?, now: Date) -> String? {
        guard let updated = Countdown.updatedLabel(capturedAt: capturedAt, now: now) else { return nil }
        return prefix + updated
    }
}

/// WCL4: the medium centre rule is drawn once, in the gutter, from anchors the columns
/// publish — measured, not guessed.
struct HeadroomMeterBandAnchors: Equatable {
    var tops: [Anchor<CGPoint>] = []
    var bottoms: [Anchor<CGPoint>] = []
}

struct HeadroomMeterBandKey: PreferenceKey {
    static let defaultValue = HeadroomMeterBandAnchors()

    static func reduce(value: inout HeadroomMeterBandAnchors, nextValue: () -> HeadroomMeterBandAnchors) {
        let next = nextValue()
        value.tops += next.tops
        value.bottoms += next.bottoms
    }
}
