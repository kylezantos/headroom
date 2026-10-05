import CryptoKit
import Foundation

/// Static outcomes only. No caught error or source-associated value enters diagnostics.
public enum CompanionSyncDecodeResult<Value: Equatable & Sendable>: Equatable, Sendable {
    case missing
    case corrupt
    case unsupportedSchema
    case unsupportedReader
    case unsupportedControlState
    case value(Value)
}

public enum CompanionSyncCodec {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    public static func decodeRequest(_ data: Data?) -> CompanionSyncDecodeResult<CompanionRequest> {
        decode(data, as: CompanionRequest.self)
    }

    public static func decodeReceipt(_ data: Data?) -> CompanionSyncDecodeResult<CompanionReceipt> {
        decode(data, as: CompanionReceipt.self) { decoder, bytes in
            try decoder.decode(ReceiptControlHeader.self, from: bytes).state != .unknown
        }
    }

    /// KTD6.6/KTD14: request/receipt compatibility precedes IDs and body decoding.
    /// Manifest disabled source/status routing is a separate, earlier boundary.
    private static func decode<Value: Decodable & Equatable & Sendable>(
        _ data: Data?,
        as type: Value.Type,
        supportedControl: ((JSONDecoder, Data) throws -> Bool)? = nil
    ) -> CompanionSyncDecodeResult<Value> {
        guard let data else { return .missing }
        let decoder = JSONDecoder()
        do {
            let header = try decoder.decode(CompanionVersionHeader.self, from: data)
            if header.schemaVersion < 4 { return .unsupportedSchema }
            if header.minimumReaderVersion > 1 { return .unsupportedReader }
            if let supportedControl, try !supportedControl(decoder, data) {
                return .unsupportedControlState
            }
            return .value(try decoder.decode(type, from: data))
        } catch {
            return .corrupt
        }
    }

    /// Decision 1: source/status route first, so a disabled tombstone is recognized
    /// without the active version header or any active field.
    public static func decodeManifest(_ data: Data?) -> CompanionSyncDecodeResult<CompanionManifest> {
        guard let data else { return .missing }
        let decoder = JSONDecoder()
        guard let routing = try? decoder.decode(ManifestRoutingHeader.self, from: data),
            let sourceID = try? CompanionTransportValidation.uuid(routing.sourceID)
        else { return .corrupt }
        switch routing.status {
        case CompanionManifestStatus.disabled.rawValue:
            return .value(.disabled(sourceID: sourceID))
        case CompanionManifestStatus.enabled.rawValue:
            switch decode(data, as: CompanionActiveManifest.self) {
            case .value(let manifest): return .value(.active(manifest))
            case .missing: return .missing
            case .corrupt: return .corrupt
            case .unsupportedSchema: return .unsupportedSchema
            case .unsupportedReader: return .unsupportedReader
            case .unsupportedControlState: return .unsupportedControlState
            }
        default:
            // An unknown status never becomes enabled or disabled (contract manifest.s).
            return .unsupportedControlState
        }
    }

    /// Version header, then mode, then body. The key suffix must name the same provider;
    /// the source lineage is checked by the resolver against the manifest (KTD6.3).
    public static func decodeProviderPayload(
        _ data: Data?, providerID: String
    ) -> CompanionSyncDecodeResult<CompanionProviderPayload> {
        let result = decode(data, as: CompanionProviderPayload.self) { decoder, bytes in
            try decoder.decode(PayloadControlHeader.self, from: bytes).mode != .unknown
        }
        if case .value(let payload) = result, payload.providerID != providerID { return .corrupt }
        return result
    }

    /// KTD6.2: SHA-256 over the exact bytes stored in (or read from) a key. Callers pass
    /// the raw Data; hashing a re-encoding would let unknown future fields change it.
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct ManifestRoutingHeader: Decodable {
        let sourceID: String
        let status: String

        private enum CodingKeys: String, CodingKey {
            case sourceID = "i"
            case status = "s"
        }
    }

    private struct PayloadControlHeader: Decodable {
        let mode: CompanionPayloadMode

        private enum CodingKeys: String, CodingKey {
            case mode = "m"
        }
    }

    private struct ReceiptControlHeader: Decodable {
        let state: CompanionReceiptState

        private enum CodingKeys: String, CodingKey {
            case state = "s"
        }
    }
}

/// Versions are required positive integers even before deciding reader compatibility.
struct CompanionVersionHeader: Decodable {
    let schemaVersion: Int
    let minimumReaderVersion: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "v"
        case minimumReaderVersion = "r"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        minimumReaderVersion = try c.decode(Int.self, forKey: .minimumReaderVersion)
        try CompanionTransportValidation.headerVersions(
            schema: schemaVersion, minimumReader: minimumReaderVersion)
    }
}
