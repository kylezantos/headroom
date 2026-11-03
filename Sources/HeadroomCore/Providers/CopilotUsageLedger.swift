import Foundation

public struct CopilotUsageAnchor: Sendable, Equatable {
    public let used: Double
    public let observedAt: Date

    public init(used: Double, observedAt: Date) {
        self.used = used
        self.observedAt = observedAt
    }
}

public struct CopilotLedgerInput: Sendable, Equatable {
    public let tokenBasedBilling: Bool
    public let anchor: CopilotUsageAnchor?
    public let evidenceNotBefore: Date?

    public init(tokenBasedBilling: Bool, anchor: CopilotUsageAnchor? = nil, evidenceNotBefore: Date? = nil) {
        self.tokenBasedBilling = tokenBasedBilling
        self.anchor = anchor
        self.evidenceNotBefore = evidenceNotBefore
    }
}

public struct CopilotLedgerReading: Sendable, Equatable {
    public let usedCredits: Double?
    public let resetsAt: Date?
    public let newestEvidenceAt: Date?

    public init(usedCredits: Double?, resetsAt: Date?, newestEvidenceAt: Date?) {
        self.usedCredits = usedCredits
        self.resetsAt = resetsAt
        self.newestEvidenceAt = newestEvidenceAt
    }
}

public enum CopilotLedgerOutcome: Sendable, Equatable {
    case reading(CopilotLedgerReading)
    case unreadable
}

/// Computes Copilot credit usage from the CLI's local session logs at
/// `<copilotHome>/session-state/<session>/events.jsonl`. Those files hold prompts and tool
/// output, so only event times, credit amounts, usage IDs and quota figures ever leave the
/// parser. Polls reread only what changed, because session files reach 900 KB.
public actor CopilotUsageLedger {
    private let sessionStateDirectory: URL
    private let now: @Sendable () -> Date
    private var memo: [String: MemoizedSessionLog] = [:]

    public init(copilotHome: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        sessionStateDirectory = copilotHome.appendingPathComponent("session-state", isDirectory: true)
        self.now = now
    }

    public func read(_ input: CopilotLedgerInput) -> CopilotLedgerOutcome {
        let now = now()
        let period = CopilotLedgerCalculator.utcMonth(containing: now)
        guard let logs = sessionLogs(changedSince: period.lowerBound) else { return .unreadable }
        return .reading(CopilotLedgerCalculator.reading(logs: logs, input: input, now: now, period: period))
    }

    /// This month's usage records summed alone, with no quota snapshot or server count, so
    /// `--probe-copilot` can set the bare sum beside the anchored value. Nil when a log could
    /// not be read.
    public func recordedCredits() -> Double? {
        let period = CopilotLedgerCalculator.utcMonth(containing: now())
        guard let logs = sessionLogs(changedSince: period.lowerBound) else { return nil }
        return CopilotLedgerCalculator.recordedCredits(logs: logs, period: period)
    }

    /// Nil when anything that exists could not be read: a partial sum would look like a
    /// real, lower number. A missing directory is an account with no sessions yet.
    private func sessionLogs(changedSince periodStart: Date) -> [CopilotSessionLog]? {
        let sessions: [String]
        do {
            sessions = try FileManager.default.contentsOfDirectory(atPath: sessionStateDirectory.path)
        } catch {
            return (error as? CocoaError)?.code == .fileReadNoSuchFile ? [] : nil
        }

        var logs: [CopilotSessionLog] = []
        var nextMemo: [String: MemoizedSessionLog] = [:]
        var allReadable = true
        for session in sessions {
            let path = sessionStateDirectory
                .appendingPathComponent(session, isDirectory: true)
                .appendingPathComponent("events.jsonl")
                .path
            switch SessionFileStamp.current(at: path) {
            case .absent:
                continue
            case .unreadable:
                allReadable = false
            case .present(let stamp):
                guard stamp.modifiedAt >= periodStart else { continue }
                if let known = memo[path], known.stamp == stamp {
                    nextMemo[path] = known
                    logs.append(known.log)
                } else if let contents = FileManager.default.contents(atPath: path) {
                    let log = CopilotSessionLog(parsing: contents)
                    nextMemo[path] = MemoizedSessionLog(stamp: stamp, log: log)
                    logs.append(log)
                } else {
                    allReadable = false
                }
            }
        }
        memo = nextMemo
        return allReadable ? logs : nil
    }
}

private struct MemoizedSessionLog {
    let stamp: SessionFileStamp
    let log: CopilotSessionLog
}

private struct SessionFileStamp: Equatable {
    let size: Int64
    let modifiedAt: Date

    enum Lookup {
        case present(SessionFileStamp)
        case absent
        case unreadable
    }

    /// `stat` rather than FileManager: its errno separates a session with no log, or a stray
    /// file beside the session folders, from one the user's permissions hide.
    static func current(at path: String) -> Lookup {
        var info = stat()
        guard stat(path, &info) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .absent : .unreadable
        }
        let seconds = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return .present(SessionFileStamp(size: info.st_size, modifiedAt: Date(timeIntervalSince1970: seconds)))
    }
}

/// The usage values of one session file. Holds nothing else, so the memo cannot retain
/// prompt or tool content.
struct CopilotSessionLog: Sendable, Equatable {
    struct UsageRecord: Sendable, Equatable {
        let usageID: String
        let nanoAIU: Int
        let recordedAt: Date
    }

    struct QuotaSnapshot: Sendable, Equatable {
        let used: Double
        let resetsAt: Date
        let observedAt: Date
    }

    private(set) var records: [UsageRecord] = []
    private(set) var snapshots: [QuotaSnapshot] = []

    // The quotes are part of the needle: a prompt or tool output naming an event reaches the
    // log JSON-escaped, so only a real string value matches. Decoding still checks `type`.
    private static let usageRecordNeedle = Data(#""session.usage_record""#.utf8)
    private static let quotaSnapshotNeedle = Data(#""model.model_call_success""#.utf8)

    /// Malformed lines are dropped one by one. That includes a running session's truncated
    /// final line, which is read whole on the poll after it completes.
    init(parsing contents: Data) {
        let decoder = JSONDecoder()
        for line in contents.split(separator: 0x0A) {
            if line.range(of: Self.usageRecordNeedle) != nil,
               let event = try? decoder.decode(UsageRecordEvent.self, from: line),
               event.type == "session.usage_record",
               let recordedAt = DateParsing.iso8601(event.timestamp) {
                records.append(UsageRecord(
                    usageID: event.data.usage.accounting.usageId,
                    nanoAIU: event.data.usage.copilotUsage.totalNanoAiu,
                    recordedAt: recordedAt
                ))
            }
            if line.range(of: Self.quotaSnapshotNeedle) != nil,
               let event = try? decoder.decode(ModelCallEvent.self, from: line),
               event.type == "model.model_call_success",
               let observedAt = DateParsing.iso8601(event.timestamp),
               let resetsAt = DateParsing.iso8601(event.data.quotaSnapshots.premium_interactions.resetDate) {
                snapshots.append(QuotaSnapshot(
                    used: event.data.quotaSnapshots.premium_interactions.usedRequests,
                    resetsAt: resetsAt,
                    observedAt: observedAt
                ))
            }
        }
    }
}

private struct UsageRecordEvent: Decodable {
    struct Payload: Decodable {
        struct Usage: Decodable {
            struct CopilotUsage: Decodable { let totalNanoAiu: Int }
            struct Accounting: Decodable { let usageId: String }
            let copilotUsage: CopilotUsage
            let accounting: Accounting
        }
        let usage: Usage
    }
    let type: String
    let timestamp: String
    let data: Payload
}

private struct ModelCallEvent: Decodable {
    struct Payload: Decodable {
        struct QuotaSnapshots: Decodable {
            struct Premium: Decodable {
                let usedRequests: Double
                let resetDate: String
            }
            let premium_interactions: Premium
        }
        let quotaSnapshots: QuotaSnapshots
    }
    let type: String
    let timestamp: String
    let data: Payload
}

enum CopilotLedgerCalculator {
    private static let nanoAIUPerCredit = 1_000_000_000.0

    static func utcMonth(containing date: Date) -> Range<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let month = calendar.dateInterval(of: .month, for: date) else { return date..<date }
        return month.start..<month.end
    }

    static func reading(
        logs: [CopilotSessionLog],
        input: CopilotLedgerInput,
        now: Date,
        period: Range<Date>
    ) -> CopilotLedgerReading {
        // Logs carry no login, so nothing from before a login change is known to be this
        // account's, its reset date included.
        func isAfterFloor(_ date: Date) -> Bool {
            input.evidenceNotBefore.map { date > $0 } ?? true
        }

        let liveSnapshots = logs.flatMap(\.snapshots).filter { $0.resetsAt > now && isAfterFloor($0.observedAt) }
        let resetsAt = liveSnapshots.max { $0.observedAt < $1.observedAt }?.resetsAt

        let snapshotAnchors = liveSnapshots.map { CopilotUsageAnchor(used: $0.used, observedAt: $0.observedAt) }
        let anchor = ([input.anchor].compactMap { $0 } + snapshotAnchors)
            .filter { period.contains($0.observedAt) && isAfterFloor($0.observedAt) }
            .max { $0.observedAt < $1.observedAt }

        // nanoAIU only measures the allowance on token-billed accounts.
        let records = input.tokenBasedBilling ? uniqueRecords(in: logs) : []
        let laterRecords = records.filter { record in
            period.contains(record.recordedAt) && isAfterFloor(record.recordedAt)
                && anchor.map { record.recordedAt > $0.observedAt } ?? true
        }

        // After a login change a bare sum would understate the new account, which may have
        // spent credits before this machine saw any of them. Zero records is no evidence.
        guard anchor != nil || (input.evidenceNotBefore == nil && !laterRecords.isEmpty) else {
            return CopilotLedgerReading(usedCredits: nil, resetsAt: resetsAt, newestEvidenceAt: nil)
        }

        let laterNanoAIU = laterRecords.reduce(0.0) { $0 + Double($1.nanoAIU) }
        let newestRecordAt = laterRecords.map(\.recordedAt).max()
        return CopilotLedgerReading(
            usedCredits: (anchor?.used ?? 0) + laterNanoAIU / nanoAIUPerCredit,
            resetsAt: resetsAt,
            newestEvidenceAt: [anchor?.observedAt, newestRecordAt].compactMap { $0 }.max()
        )
    }

    static func recordedCredits(logs: [CopilotSessionLog], period: Range<Date>) -> Double {
        uniqueRecords(in: logs)
            .filter { period.contains($0.recordedAt) }
            .reduce(0.0) { $0 + Double($1.nanoAIU) } / nanoAIUPerCredit
    }

    /// Keeps a repeated ID's earliest copy, so the result does not depend on the order the
    /// directory listing returned the files.
    private static func uniqueRecords(in logs: [CopilotSessionLog]) -> [CopilotSessionLog.UsageRecord] {
        var byID: [String: CopilotSessionLog.UsageRecord] = [:]
        for record in logs.flatMap(\.records) {
            if let known = byID[record.usageID], known.recordedAt <= record.recordedAt { continue }
            byID[record.usageID] = record
        }
        return Array(byID.values)
    }
}
