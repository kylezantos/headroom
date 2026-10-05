import Foundation

/// Exact encoded sizes for a planned v4 namespace image (contract Decision 3): every value
/// under `headroom.sync.v4.`, including the receipt and request keys. The v3 key is outside
/// this budget. Key names are measured separately against the 64-byte key limit.
public struct CompanionBudgetMeasurement: Equatable, Sendable {
    public let valueBytes: [String: Int]

    public init(_ values: [String: Data]) {
        valueBytes = values.mapValues(\.count)
    }

    public var totalBytes: Int { valueBytes.values.reduce(0, +) }

    public var oversizedProviderKeys: [String] {
        valueBytes.filter { key, bytes in
            key.hasPrefix(CompanionSyncKeys.providerPrefix) && bytes > CompanionSyncBudget.providerKeyBytes
        }.keys.sorted()
    }

    public var fits: Bool {
        oversizedProviderKeys.isEmpty && totalBytes <= CompanionSyncBudget.namespaceBytes
    }
}

public enum CompanionBudgetError: Error, Equatable, Sendable {
    /// The permitted ladder could not fit; the publisher stops and leaves the last valid
    /// content intact rather than capping accounts at or below the envelope (Decision 3).
    case overBudget(CompanionBudgetMeasurement)
}

public struct CompanionBudgetFit: Equatable, Sendable {
    public let ladderLevel: Int
    public let payloads: [CompanionProviderPayload]
    /// Encoded provider values keyed by provider ID, the exact bytes to store and digest.
    public let providerValues: [String: Data]
    public let manifest: Data
    public let measurement: CompanionBudgetMeasurement
}

/// KTD7's drop ladder as a pure function, for the Mac publisher (U5) and the budget tests.
public enum CompanionPayloadBudget {
    /// Encodes and measures at each ladder level from `minimumLevel`: 0 full, 1 drops extra
    /// accounts' model rows, 2 caps extras only for providers above the 20-account
    /// envelope. `manifest` builds the manifest for a level from the exact provider bytes.
    public static func fit(
        payloads: [CompanionProviderPayload],
        protocolValues: [String: Data],
        minimumLevel: Int = 0,
        manifest: (_ level: Int, _ providerValues: [String: Data]) throws -> Data
    ) throws -> CompanionBudgetFit {
        var last: CompanionBudgetMeasurement?
        for level in max(0, minimumLevel)...2 {
            let stepped = try payloads.map { try apply(level: level, to: $0) }
            var providerValues: [String: Data] = [:]
            for payload in stepped {
                providerValues[payload.providerID] = try CompanionSyncCodec.encode(payload)
            }
            let manifestBytes = try manifest(level, providerValues)
            var image = protocolValues
            for (id, data) in providerValues {
                guard let key = CompanionSyncKeys.provider(id) else { continue }
                image[key] = data
            }
            image[CompanionSyncKeys.manifest] = manifestBytes
            let measurement = CompanionBudgetMeasurement(image)
            if measurement.fits {
                return CompanionBudgetFit(
                    ladderLevel: level, payloads: stepped, providerValues: providerValues,
                    manifest: manifestBytes, measurement: measurement)
            }
            last = measurement
        }
        throw CompanionBudgetError.overBudget(last ?? CompanionBudgetMeasurement([:]))
    }

    static func apply(level: Int, to payload: CompanionProviderPayload) throws -> CompanionProviderPayload {
        guard level >= 1 else { return payload }
        let trimmed = try payload.droppingExtraAccountModelRows()
        guard level >= 2, trimmed.allAccounts.count > CompanionSyncBudget.accountEnvelope else {
            return trimmed
        }
        return try trimmed.cappingExtraAccounts(to: CompanionSyncBudget.accountEnvelope - 1)
    }
}
