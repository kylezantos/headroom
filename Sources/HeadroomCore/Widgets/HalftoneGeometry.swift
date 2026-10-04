import Foundation

/// KTD7: the options document's capsule dot field, independent of any drawing framework.
public struct HalftoneGeometry: Sendable, Equatable {
    public struct Dot: Sendable, Equatable {
        public let column: Int
        /// Top-down row index; print coverage rises from the bottom.
        public let row: Int
        public let x: Double
        public let y: Double
    }

    public static let dotFill = 0.42
    public static let speckRadiusFraction = 0.32
    public static let emptyCoverage = 0.08
    public let width: Double
    public let height: Double
    public let columns: Int
    public let rows: Int
    public let inset: Double
    public let pitch: Double
    public let dots: [Dot]

    public init(width: Double, height: Double, columns: Int, rows: Int, inset: Double = 2) {
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.inset = max(0, inset)
        let innerWidth = width - 2 * self.inset
        let innerHeight = height - 2 * self.inset
        guard columns > 0, rows > 0, innerWidth > 0, innerHeight > 0,
              innerWidth.isFinite, innerHeight.isFinite else {
            pitch = 0
            dots = []
            return
        }
        let dx = innerWidth / Double(columns)
        let dy = innerHeight / Double(rows)
        pitch = min(dx, dy)
        let radius = min(innerWidth, innerHeight) / 2
        let top = self.inset + radius
        let bottom = height - self.inset - radius
        let centerX = width / 2
        var points: [Dot] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x = self.inset + (Double(column) + 0.5) * dx
                let y = self.inset + (Double(row) + 0.5) * dy
                let beyondStraightWall = max(0, max(top - y, y - bottom))
                if hypot(x - centerX, beyondStraightWall) <= radius {
                    points.append(Dot(column: column, row: row, x: x, y: y))
                }
            }
        }
        dots = points
    }

    public func radius(coverage: Double) -> Double {
        let coverage = min(1, max(0, coverage))
        return pitch * Self.dotFill * (Self.speckRadiusFraction + (1 - Self.speckRadiusFraction) * coverage)
    }

    public static func inkOpacity(coverage: Double) -> Double {
        0.14 + 0.86 * min(1, max(0, coverage))
    }
}
