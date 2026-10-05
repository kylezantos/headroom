import CoreGraphics

/// KTD17's column arithmetic at the default text size, mirroring
/// `FlowingColumnsGeometry.resolve` with `FlowingColumnsMetrics.standard` (UI tests cannot link
/// HeadroomCore). Two columns need 876pt in a regular-width window, so 744pt and 834pt iPads
/// in portrait are one column and only wider windows flow cards side by side.
enum FlowingColumnsExpectation {
    static let regularMargin: CGFloat = 28
    /// `MirrorView.sideMargin`: a compact (phone) window keeps 20pt margins.
    static let compactMargin: CGFloat = 20
    static let gap: CGFloat = 20
    static let minimumCardWidth: CGFloat = 400

    /// Stands in for the horizontal size class, which XCUITest cannot read: every iPad window
    /// these suites run in is regular, every phone portrait window compact.
    static func isRegularWidth(_ width: CGFloat) -> Bool { width >= 700 }

    static func columns(width: CGFloat, cardCount: Int = .max) -> Int {
        let margin = isRegularWidth(width) ? regularMargin : compactMargin
        let content = max(width - 2 * margin, 0)
        // The same epsilon as the geometry: an exact fit keeps its column.
        let fitting = Int(((content + gap) / (minimumCardWidth + gap) + 1e-9).rounded(.down))
        return max(min(fitting, cardCount), 1)
    }
}
