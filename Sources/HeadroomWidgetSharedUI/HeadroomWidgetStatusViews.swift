#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI
import WidgetKit

/// WCF5/WCW4: one vessel mark for both widget extensions. The macOS widget and the iOS
/// widget each carried a private copy and they had already drifted (one drew a liquid level,
/// the other a flat capsule). This is the macOS drawing, verbatim — an outlined capsule with
/// the level masked in from the bottom — because it is the one that matches the app's
/// `VesselGlyph`. `HeadroomCore` is intentionally SwiftUI-free, so a `Shape` cannot live
/// there; this module is the shared home.
public struct HeadroomVesselMark: View {
    private let lineWidth: CGFloat
    private let fill: Double

    public init(lineWidth: CGFloat = 1.6, fill: Double = 0.46) {
        self.lineWidth = lineWidth
        self.fill = fill
    }

    public var body: some View {
        ZStack {
            Capsule().strokeBorder(lineWidth: lineWidth)
            Capsule()
                .inset(by: lineWidth + 0.6)
                .fill()
                .mask {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(height: proxy.size.height * CGFloat(fill))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
        }
        .accessibilityHidden(true)
    }
}

/// WCW4: the shared status card. One copy table in Core, sentence case, the title at the
/// provider-name step rather than `.headline` (which outranked every name on the tile), and
/// **no padding of its own** — the host applies the family residual, so the status text
/// starts on the same content axis the meters use instead of 10pt further in.
///
/// Small prints the message only: at 170pt a title plus a sentence wrapped the title to two
/// lines and the mark ended up centred on the pair.
public struct HeadroomWidgetStatusCard: View {
    private let state: WidgetStatusState
    private let family: HeadroomWidgetFamily
    private let scale: WidgetTypeScale

    @Environment(\.colorScheme) private var scheme

    @ScaledMetric private var titleSize: Double
    @ScaledMetric private var messageSize: Double

    public init(state: WidgetStatusState, family: HeadroomWidgetFamily, scale: WidgetTypeScale) {
        self.state = state
        self.family = family
        self.scale = scale
        _titleSize = ScaledMetric(wrappedValue: scale.statusTitle, relativeTo: .body)
        _messageSize = ScaledMetric(wrappedValue: scale.statusMessage, relativeTo: .body)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: CGFloat(WidgetMetrics.markGap)) {
            // WCF3: the mark hangs in the gutter, leading-aligned, and the text starts on
            // the content axis (mark slot + 6) — the same axis the meters start on.
            HeadroomVesselMark(fill: state.vesselFill)
                .frame(width: 12, height: 20)
                .frame(width: CGFloat(WidgetMetrics.markSlot(for: family)), alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if family != .small {
                    Text(state.title)
                        .font(HeadroomWidgetType.font(size: titleSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .widgetOpticalLeading(state.title, size: titleSize, weight: .semibold)
                }
                // WCF7: the sentence is the element that gives — two lines, then a tail
                // ellipsis. Nothing here clips or overlaps the tile's content box.
                Text(state.message)
                    .font(HeadroomWidgetType.font(size: messageSize, weight: .medium))
                    .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .widgetOpticalLeading(state.message, size: messageSize, weight: .medium)
            }
            Spacer(minLength: 0)
        }
        // The block is vertically centred in whatever the host gives it; horizontal
        // alignment stays leading. No padding — the host owns the family residual.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(family == .small ? state.message : "\(state.title). \(state.message)")
    }
}
