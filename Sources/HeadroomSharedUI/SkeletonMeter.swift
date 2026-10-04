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

    public init(labelWidth: CGFloat, valueWidth: CGFloat, format: GaugeFormat) {
        self.labelWidth = labelWidth
        self.valueWidth = valueWidth
        self.format = format
    }

    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        switch format {
        case .full:
            VStack(alignment: .leading, spacing: 5) {
                skeletonTextRow
                Capsule().fill(track).frame(height: MeterGeometry.fullTrackHeight)
            }
        case .micro:
            HStack {
                skeletonLabel
                Spacer(minLength: 6)
                Capsule()
                    .fill(track)
                    .frame(
                        width: MeterGeometry.microChipWidth,
                        height: MeterGeometry.microChipHeight
                    )
                skeletonValue
            }
        }
    }

    private var skeletonTextRow: some View {
        HStack {
            skeletonLabel
            Spacer(minLength: 6)
            skeletonValue
        }
    }

    private var skeletonLabel: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(track)
            .frame(width: labelWidth, height: 13)
    }

    private var skeletonValue: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(track)
            .frame(width: valueWidth, height: 13)
    }

    private var track: Color { ProviderStyle.barTrack(scheme: scheme) }
}
