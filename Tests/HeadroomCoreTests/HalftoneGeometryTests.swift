import Testing
@testable import HeadroomCore

struct HalftoneGeometryTests {
    @Test func clipsFourByEightFieldToTheInnerCapsule() {
        let geometry = HalftoneGeometry(width: 10, height: 16, columns: 4, rows: 8, inset: 2)
        #expect(geometry.dots.count == 28)
        #expect(!geometry.dots.contains { $0.column == 0 && $0.row == 0 })
        #expect(geometry.dots.contains { $0.column == 1 && $0.row == 0 })
        #expect(geometry.dots.contains { $0.column == 0 && $0.row == 1 })
        #expect(geometry.dots.allSatisfy { $0.x >= 2 && $0.x <= 8 && $0.y >= 2 && $0.y <= 14 })
        #expect(geometry.pitch == 1.5)
    }

    @Test func coverageUsesWebsiteSpeckAndFullRadiusAndInk() {
        let geometry = HalftoneGeometry(width: 10, height: 16, columns: 4, rows: 8, inset: 2)
        #expect(abs(geometry.radius(coverage: 0) - 0.2016) < 0.00001)
        #expect(abs(geometry.radius(coverage: 1) - 0.63) < 0.00001)
        #expect(geometry.radius(coverage: -1) == geometry.radius(coverage: 0))
        #expect(geometry.radius(coverage: 2) == geometry.radius(coverage: 1))
        #expect(HalftoneGeometry.inkOpacity(coverage: 0) == 0.14)
        #expect(HalftoneGeometry.inkOpacity(coverage: 1) == 1)
    }

    @Test func impossibleFieldsHaveNoDots() {
        #expect(HalftoneGeometry(width: 3, height: 3, columns: 4, rows: 8, inset: 2).dots.isEmpty)
        #expect(HalftoneGeometry(width: 10, height: 16, columns: 0, rows: 8).dots.isEmpty)
    }
}
