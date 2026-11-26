#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// 1C: lays out the plan capsule and the chips after it by `PlanCapsuleRunGeometry`.
/// Subviews, in order: the closed capsule (laid out, never drawn), the run, the live capsule,
/// last so it draws above the run it opens over.
/// Every piece is fixed width (`identityCapsule` is `fixedSize`), so each is measured at its
/// ideal size and the proposal only matters to the row around it.
struct PlanCapsuleRunLayout: Layout {
    var spacing: CGFloat
    var overlaysRun: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let sizes = Self.sizes(subviews) else { return .zero }
        let width = PlanCapsuleRunGeometry.width(
            closedWidth: sizes.closed.width,
            liveWidth: sizes.live.width,
            runWidth: sizes.run.width,
            spacing: spacing,
            overlaysRun: overlaysRun
        )
        return CGSize(width: width, height: max(sizes.closed.height, sizes.live.height, sizes.run.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let sizes = Self.sizes(subviews) else { return }
        let runX = PlanCapsuleRunGeometry.runOffset(
            closedWidth: sizes.closed.width,
            liveWidth: sizes.live.width,
            spacing: spacing,
            overlaysRun: overlaysRun
        )
        let origins = [bounds.minX, bounds.minX + runX, bounds.minX]
        for (index, size) in [sizes.closed, sizes.run, sizes.live].enumerated() {
            subviews[index].place(
                at: CGPoint(x: origins[index], y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(size)
            )
        }
    }

    private static func sizes(_ subviews: Subviews) -> (closed: CGSize, live: CGSize, run: CGSize)? {
        guard subviews.count == 3 else { return nil }
        return (
            subviews[0].sizeThatFits(.unspecified),
            subviews[2].sizeThatFits(.unspecified),
            subviews[1].sizeThatFits(.unspecified)
        )
    }
}
