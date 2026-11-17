import Foundation

// The shapes `agy -p "/usage" --output-format json` and `/credits` print, pinned to agy 1.5.9
// captures. Each DTO decodes only what a decision needs: the `response` text, group and bucket
// names and descriptions, and the conversation ID are never decoded, so they can't reach a
// value Headroom returns.

/// The print-mode result every `agy -p … --output-format json` run prints:
/// `{"status":"SUCCESS","num_turns":0,"usage":{…},"command":{"name":"usage","data":{…}}}`.
/// `command` is present only when a read-only slash command answered without a model turn.
struct AntigravityResultDTO: Decodable {
    let status: String?
    /// Only read to match fixed phrases. Never returned or logged.
    let error: String?
    let numTurns: Int?
    let usage: AntigravityTokenUsageDTO?
    let command: AntigravityCommandDTO?

    private enum CodingKeys: String, CodingKey {
        case status, error, usage, command
        case numTurns = "num_turns"
    }

    /// True only when the result itself shows that no model turn ran and no token was spent.
    /// A missing count is not proof of zero.
    var provesNoTurn: Bool {
        guard numTurns == 0, let usage else { return false }
        return usage.counts.allSatisfy { $0 == 0 }
    }
}

struct AntigravityTokenUsageDTO: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let thinkingTokens: Int?
    let cacheReadTokens: Int?
    let totalTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case thinkingTokens = "thinking_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
    }

    /// Every count, with a missing one read as unproven rather than zero.
    var counts: [Int] {
        [inputTokens, outputTokens, thinkingTokens, cacheReadTokens, totalTokens].map { $0 ?? -1 }
    }
}

/// `command` with its `data` left undecoded, so the name can be checked before the payload.
struct AntigravityCommandDTO: Decodable {
    let name: String
}

/// `command.data` of `/usage`.
struct AntigravityUsageCommandDTO: Decodable {
    let command: Command

    struct Command: Decodable {
        let data: Data
    }

    struct Data: Decodable {
        let groups: [Group]
    }

    struct Group: Decodable {
        let buckets: [Bucket]
    }

    struct Bucket: Decodable {
        let id: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: String?

        private enum CodingKeys: String, CodingKey {
            case id, window
            case remainingFraction = "remaining_fraction"
            case resetTime = "reset_time"
        }
    }
}

/// `command.data` of `/credits`.
struct AntigravityCreditsCommandDTO: Decodable {
    let command: Command

    struct Command: Decodable {
        let data: Data
    }

    struct Data: Decodable {
        let remainingCredits: Double

        private enum CodingKeys: String, CodingKey {
            case remainingCredits = "remaining_credits"
        }
    }
}
