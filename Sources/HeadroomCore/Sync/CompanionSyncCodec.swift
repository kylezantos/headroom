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
