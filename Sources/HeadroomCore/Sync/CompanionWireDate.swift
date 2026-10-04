import Foundation

/// U4: Unix-second transport dates, independent of JSONEncoder's Date strategy.
/// Durations and cadence are separate quantities and retain their fractional Doubles.
public struct CompanionWireDate: Codable, Equatable, Sendable {
    public let epochSeconds: Int64

    /// Invalid/unrepresentable dates reject the export rather than becoming now or zero.
    public init?(date: Date) {
        let interval = date.timeIntervalSince1970
        guard interval.isFinite, let seconds = Int64(exactly: floor(interval)) else { return nil }
        self.init(epochSeconds: seconds)
    }

    public init?(epochSeconds: Int64) {
        let interval = Double(epochSeconds)
        // Date stores a Double relative to 2001. Check both conversions: even an exact
        // Unix Double integer can lose precision when that reference offset is applied.
        guard Int64(exactly: interval) == epochSeconds,
              Int64(exactly: Date(timeIntervalSince1970: interval).timeIntervalSince1970) == epochSeconds else {
            return nil
        }
        self.epochSeconds = epochSeconds
    }

    /// This inverse is safe because every initializer validates its exact round trip.
    public var date: Date { Date(timeIntervalSince1970: Double(epochSeconds)) }

    public static func canonicalize(_ date: Date) -> Date? { Self(date: date)?.date }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Int64.self)
        guard let value = Self(epochSeconds: seconds) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrepresentable Unix seconds")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(epochSeconds)
    }
}
