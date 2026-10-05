import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

/// Varied-width placeholder meter (audit UI-13): previews the true row shape so the
/// pending state reads intentional, not broken. Shared by both card paths.
public struct SkeletonMeter: View {
    public let labelWidth: CGFloat
    public let valueWidth: CGFloat
    public let format: GaugeFormat
    /// U8 (KTD3): the phone's one type unit; the placeholder reserves the scaled row it
    /// stands in for. The Mac passes 1.
    public var scale: CGFloat = 1

    public init(labelWidth: CGFloat, valueWidth: CGFloat, format: GaugeFormat, scale: CGFloat = 1) {
        self.labelWidth = labelWidth
        self.valueWidth = valueWidth
        self.format = format
        self.scale = scale
    }

    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        switch format {
        case .full:
            VStack(alignment: .leading, spacing: 5 * scale) {
                skeletonTextRow
                Capsule().fill(track).frame(height: MeterGeometry.fullTrackHeight * scale)
            }
        case .micro:
            HStack {
                skeletonLabel
                Spacer(minLength: 6 * scale)
                Capsule()
                    .fill(track)
                    .frame(
                        width: MeterGeometry.microChipWidth * scale,
                        height: MeterGeometry.microChipHeight * scale
                    )
                skeletonValue
            }
        }
    }

    private var skeletonTextRow: some View {
        HStack {
            skeletonLabel
            Spacer(minLength: 6 * scale)
            skeletonValue
        }
    }

    private var skeletonLabel: some View {
        RoundedRectangle(cornerRadius: 4 * scale)
            .fill(track)
            .frame(width: labelWidth * scale, height: 13 * scale)
    }

    private var skeletonValue: some View {
        RoundedRectangle(cornerRadius: 4 * scale)
            .fill(track)
            .frame(width: valueWidth * scale, height: 13 * scale)
    }

    private var track: Color { ProviderStyle.barTrack(scheme: scheme) }
}
