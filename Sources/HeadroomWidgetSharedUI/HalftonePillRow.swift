#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// R1/U3: input order, with one and two pills centred in the three-pill label slot.
public struct HalftonePillRow: View {
    public struct Layout: Equatable, Sendable {
        public let pillWidth: Double
        public let height: Double = 16
        public let columns: Int
        public let gap: Double
        public let origins: [Double]
        public let width: Double

        public init(count: Int, labelWidth: Double = 44) {
            let count = min(4, max(0, count))
            width = labelWidth
            let pillWidth = count == 4 ? 8.6 : 10.0
            self.pillWidth = pillWidth // U3: four slim 3×8; otherwise 4×8.
            columns = count == 4 ? 3 : 4
            let gap = count == 4 ? (labelWidth - 4 * pillWidth) / 3 : (labelWidth - 3 * pillWidth) / 2
            // Approved 12d: one/two retain the three-pill spacing in its 44pt slot.
            self.gap = gap
            let span = Double(count) * pillWidth + Double(max(0, count - 1)) * gap
            origins = (0..<count).map {
                min(labelWidth - pillWidth, max(0, (labelWidth - span) / 2 + Double($0) * (pillWidth + gap)))
            }
        }
    }

    private let pills: [LoadingPillState]
    private let labelWidth: Double
    private let sloshEndedAt: Date?

    public init(pills: [LoadingPillState] = LoadingPillState.ghostRow(), labelWidth: Double = 44,
                sloshEndedAt: Date? = nil) {
        self.pills = Array(pills.prefix(4))
        self.labelWidth = labelWidth
        self.sloshEndedAt = sloshEndedAt
    }

    public var body: some View {
        let layout = Layout(count: pills.count, labelWidth: labelWidth)
        HStack(spacing: layout.gap) {
            ForEach(pills) { pill in
                HalftoneVesselView(state: pill, width: layout.pillWidth, height: layout.height,
                                  columns: layout.columns, rows: 8, sloshEndedAt: sloshEndedAt)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .headroomWidgetProbe()
        .accessibilityHidden(true)
    }
}
