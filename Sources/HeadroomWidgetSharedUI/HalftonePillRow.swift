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

        /// Five providers can be selected, so the row holds five (U6, Copilot plan).
        public static let maximumCount = 5

        public init(count: Int, labelWidth: Double = 44) {
            let count = min(Self.maximumCount, max(0, count))
            width = labelWidth
            // U3: four slim 3×8; five slimmer still at 3×8 so all five share the slot.
            let pillWidth = switch count {
            case 5: 7.2
            case 4: 8.6
            default: 10.0
            }
            self.pillWidth = pillWidth
            columns = count >= 4 ? 3 : 4
            let gap = count >= 4
                ? (labelWidth - Double(count) * pillWidth) / Double(count - 1)
                : (labelWidth - 3 * pillWidth) / 2
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
        self.pills = Array(pills.prefix(Layout.maximumCount))
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
