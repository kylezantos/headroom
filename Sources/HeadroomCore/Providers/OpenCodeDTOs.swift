import Foundation

// The shapes the official client prints (KTD1, KTD4, KTD20), pinned to U12's v2.2.5 captures.
// Each DTO decodes only what a decision needs: the workspace block (id, name, Console URL),
// budgets, credential IDs and connection labels are never decoded (R4, KTD19), so they can't
// reach a value Headroom returns.

/// `opencode api --standalone experimental.usage.limits`, exit 0:
/// `{"location":{…},"data":null}` or `{"location":{…},"data":{"workspace":…,"go":…,"budgets":…}}`.
struct OpenCodeUsageEnvelopeDTO: Decodable {
    /// Nil means the client printed `data: null` (KTD20). A missing `data` key is a different
    /// contract and fails decoding.
    let data: OpenCodeUsageDataDTO?

    private enum CodingKeys: String, CodingKey { case data }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.data) else {
            throw DecodingError.keyNotFound(
                CodingKeys.data,
                .init(codingPath: container.codingPath, debugDescription: "usage envelope has no data")
            )
        }
        data = try container.decodeIfPresent(OpenCodeUsageDataDTO.self, forKey: .data)
    }
}

struct OpenCodeUsageDataDTO: Decodable {
    /// Absent (or null) when the Go route answered 403: a workspace with no Go plan (KTD7).
    let go: OpenCodeGoDTO?
}

struct OpenCodeGoDTO: Decodable {
    let rolling: OpenCodeGoWindowDTO
    let weekly: OpenCodeGoWindowDTO
    let monthly: OpenCodeGoWindowDTO
}

struct OpenCodeGoWindowDTO: Decodable {
    /// Percent used, as reported. KTD6: `limited` is the authority, so this reported value
    /// stays here and never reaches the capture for a limited window.
    let percent: Double
    let limited: Bool
    /// Milliseconds since the epoch.
    let resetsAt: Double

    /// Nil when the reading can't be trusted: KTD6 never invents a reset, so a non-finite or
    /// non-positive reset (or percentage) fails the whole reading as format changed.
    var window: OpenCodeGoWindow? {
        guard percent.isFinite, resetsAt.isFinite, resetsAt > 0 else { return nil }
        return OpenCodeGoWindow(
            percentUsed: limited ? 100 : percent,
            isLimited: limited,
            resetsAt: Date(timeIntervalSince1970: resetsAt / 1_000)
        )
    }
}

extension OpenCodeGoDTO {
    var usage: OpenCodeGoUsage? {
        guard let rolling = rolling.window, let weekly = weekly.window, let monthly = monthly.window else {
            return nil
        }
        return OpenCodeGoUsage(rolling: rolling, weekly: weekly, monthly: monthly)
    }
}

/// The exit-1 error line: `{"_tag":"ServiceUnavailableError","message":"…","service":"…"}`.
/// Only `message` is read, and only to match fixed phrases; it is never returned or logged,
/// because it can carry the Console URL.
struct OpenCodeErrorDTO: Decodable {
    let message: String
}

/// `opencode auth list --standalone --format json`: integration `id` and each connection's
/// `type` and `method`, nothing else (KTD20: never decode labels).
struct OpenCodeAuthIntegrationDTO: Decodable {
    let id: String
    let connections: [OpenCodeAuthConnectionDTO]
}

struct OpenCodeAuthConnectionDTO: Decodable {
    let type: String?
    let method: String?
}
