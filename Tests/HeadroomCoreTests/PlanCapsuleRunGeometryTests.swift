import Foundation
import Testing
@testable import HeadroomCore

/// 1C: a hover-opened plan capsule opens over the chips after it instead of pushing them.
struct PlanCapsuleRunGeometryTests {
    @Test func atRestTheRunFollowsTheCapsule() {
        #expect(PlanCapsuleRunGeometry.runOffset(closedWidth: 60, liveWidth: 60, spacing: 8, overlaysRun: false) == 68)
        #expect(PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 60, runWidth: 110, spacing: 8,
                                             overlaysRun: false) == 178)
    }

    /// The screenshot case: "Business · 3 resets" over "Last read 4 days ago". The row is no
    /// wider than at rest, so the name keeps every point it had.
    @Test func aHoverOpenedCapsuleCoversTheRunWithoutWideningTheRow() {
        let rest = PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 60, runWidth: 110, spacing: 8,
                                                overlaysRun: false)
        let open = PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 112, runWidth: 110, spacing: 8,
                                                overlaysRun: true)
        #expect(open == rest)
        #expect(PlanCapsuleRunGeometry.runOffset(closedWidth: 60, liveWidth: 112, spacing: 8, overlaysRun: true) == 68)
    }

    /// A run narrower than the capsule's growth (the source glyph alone) reserves only the
    /// difference, so the open capsule never draws past the row's reserved width.
    @Test func aShortRunReservesOnlyWhatTheOpenCapsuleNeeds() {
        let open = PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 112, runWidth: 12, spacing: 8,
                                                overlaysRun: true)
        #expect(open == 112)
    }

    @Test func anEmptyRunTakesNoSpacing() {
        #expect(PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 112, runWidth: 0, spacing: 8,
                                             overlaysRun: true) == 112)
        #expect(PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 60, runWidth: 0, spacing: 8,
                                             overlaysRun: false) == 60)
    }

    /// Attention (Critical, reveal, the phone's tap) keeps pushing, so a capsule that can
    /// stay open never hides the run.
    @Test func anAttentionOpenedCapsuleStillPushesTheRun() {
        #expect(PlanCapsuleRunGeometry.runOffset(closedWidth: 60, liveWidth: 112, spacing: 8, overlaysRun: false) == 120)
        #expect(PlanCapsuleRunGeometry.width(closedWidth: 60, liveWidth: 112, runWidth: 110, spacing: 8,
                                             overlaysRun: false) == 230)
    }
}
