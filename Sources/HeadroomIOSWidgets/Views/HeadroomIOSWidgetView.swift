import SwiftUI
import WidgetKit

/// iPhone Continuity widget. WCF5: this host no longer re-implements any family body — the
/// small, medium and large bodies are the shared `HeadroomWidgetSharedUI` ones the Mac
/// extension draws, and the only platform parameters left are the footer prefix (WCW3), the
/// margin table (WCF4/WCL4) and the DEMO capsule (WCW8).
struct HeadroomIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: HeadroomIOSWidgetEntry

    var body: some View {
        ZStack {
            // The OS 26 Liquid Glass presentation composites a translucent sheen over the
            // `containerBackground` layer (bright at the widget's top edge, fading by
            // mid-tile — measured ~+28 RGB at top on both platforms), which made the top
            // provider card sit on a lighter surround than the bottom one. Content is not
            // veiled, so the background is drawn here in the content layer instead —
            // `contentMarginsDisabled` lets it bleed to the container edges, and the
            // system's own margins are re-applied around the actual content below. The
            // `containerBackground` copy remains for accented rendering and contexts that
            // strip backgrounds (StandBy / lock screen), where the system look should win.
            if showsContainerBackground && renderingMode == .fullColor {
                HeadroomWidgetContainerBackground()
            }
            stateContent
                .padding(familyContentMargins)
        }
        .overlay(alignment: .topTrailing) {
            if isDemoMode {
                demoCapsule
            }
        }
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
        .widgetURL(URL(string: "headroom://usage"))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// WCF1's family token. Spelled through the shared alias because `WidgetKit` exports a
    /// `WidgetFamily` of its own and this file imports both.
    private var coreFamily: HeadroomWidgetFamily {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }

    /// WCF4: effective margin = system content margin + the body's 2pt residual. WidgetKit's
    /// stock iPhone margins are deliberately generous, so small and large reclaim four
    /// points on every edge (the one sanctioned platform split, landing at 14 effective).
    /// WCL4: **medium** does not take the reclaim — it is pinned at 16 effective, because
    /// the 28pt gutter and the two-column meters need the tile's width more than its edges.
    private var familyContentMargins: EdgeInsets {
        if family == .systemMedium {
            let inset = CGFloat(WidgetMetrics.iOSMediumMargin - WidgetMetrics.residualMargin)
            return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
        }
        let reduction = CGFloat(WidgetMetrics.iOSMarginReclaim)
        return EdgeInsets(
            top: max(0, contentMargins.top - reduction),
            leading: max(0, contentMargins.leading - reduction),
            bottom: max(0, contentMargins.bottom - reduction),
            trailing: max(0, contentMargins.trailing - reduction)
        )
    }

    /// WCW8: the popover's state-chip recipe — `low` ink on `low @ 0.16`, a `secondary @
    /// 0.35` ring, 9 semibold tracked 0.5 — aligned to the same margins the content uses so
    /// it sits on the tile's own edge rather than 4pt outside it.
    private var demoCapsule: some View {
        let ink = HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme)
        return Text("DEMO")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(ink.opacity(0.16), in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    HeadroomWidgetStyle.secondaryText(scheme: scheme).opacity(0.35),
                    lineWidth: HeadroomWidgetStyle.hairlineWidth(displayScale: 2)
                )
            }
            .padding(familyContentMargins)
            .accessibilityLabel("Demo data")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch entry.state {
        case .demo(let envelope):
            content(envelope)
        case .content(let envelope):
            content(envelope)
        case .disabled:
            statusCard(.iosDisabled)
        case .setupNeeded:
            statusCard(.iosSetupNeeded)
        case .waitingForMac:
            statusCard(.iosWaitingForMac)
        case .corrupt:
            statusCard(.iosCorrupt)
        case .incompatibleSchema:
            statusCard(.iosIncompatibleSchema)
        }
    }

    private var isDemoMode: Bool {
        if case .demo = entry.state { true } else { false }
    }

    @ViewBuilder
    private func content(_ envelope: WidgetSnapshotEnvelope) -> some View {
        switch family {
        case .systemSmall:
            HeadroomSmallWidgetView(envelope: envelope)
        case .systemMedium:
            HeadroomMediumWidgetView(envelope: envelope, now: entry.date, footerPrefix: footerPrefix)
        default:
            HeadroomLargeWidgetView(envelope: envelope, now: entry.date, footerPrefix: footerPrefix)
        }
    }

    /// WCW4: the status block takes the family residual, not its own 12pt inset, so the
    /// status axis is the content axis.
    private func statusCard(_ state: WidgetStatusState) -> some View {
        HeadroomWidgetStatusCard(
            state: state,
            family: coreFamily,
            scale: WidgetTypeScale.scale(for: coreFamily)
        )
        .padding(WidgetMetrics.residualMargin)
    }

    /// WCW3: "From Mac · N ago" is true on the phone and false on the Mac, which is the one
    /// place the mirror rule licenses a split. Demo tiles drop it — the DEMO capsule already
    /// says the data is a sample, and "From Mac" would be a lie about a fixture.
    private var footerPrefix: String {
        isDemoMode ? HeadroomWidgetCopy.macFooterPrefix : HeadroomWidgetCopy.iosFooterPrefix
    }
}
