import Foundation

/// One usage window parsed out of Claude Code's `/usage` panel.
public struct ParsedUsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let percentUsed: Double
    public let resetLabel: String?
}

/// Extracts usage windows from the (ANSI-stripped) text of Claude Code's `/usage`
/// panel. Deliberately defensive: the panel is a TUI that re-renders several times
/// and whose exact wording can drift, so parsing keys on stable shapes ("N% used",
/// "Resets …", the window labels) rather than fixed line positions, tolerates the
/// intermediate render states, and keeps the last (settled) value for each window.
/// It never throws — a panel it can't read yields an empty result, which the provider
/// turns into a graceful stale state.
public enum ClaudeUsageParser {
    public static func parse(_ text: String) -> [ParsedUsageWindow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Later renders overwrite earlier ones (the panel settles as it scans), so a
        // dictionary keyed by window kind naturally keeps the final value.
        var byKind: [WindowKind: ParsedUsageWindow] = [:]

        var i = 0
        while i < lines.count {
            guard let kind = windowKind(for: lines[i]) else { i += 1; continue }
            // Scan the next few lines for this window's percent + reset text.
            var percent: Double?
            var reset: String?
            var j = i + 1
            let limit = min(lines.count, i + 5)
            while j < limit {
                if percent == nil, let p = percentUsed(in: lines[j]) { percent = p }
                if reset == nil, let r = resetText(in: lines[j]) { reset = r }
                // Stop early if the next window label appears.
                if windowKind(for: lines[j]) != nil { break }
                j += 1
            }
            if let percent {
                byKind[kind] = ParsedUsageWindow(kind: kind, percentUsed: percent, resetLabel: reset)
            }
            i += 1
        }

        // Stable order: 5-hour, weekly, then any extras alphabetically.
        return byKind.values.sorted { rank($0.kind) < rank($1.kind) }
    }

    /// Best-effort subscription tier from the panel header (e.g. the
    /// "… · Claude Max" line Claude Code prints at the top of `/usage`). Returned
    /// without the "Claude" prefix ("Max", "Pro", "Max 20x") for the plan pill; nil
    /// when the header advertises no tier. Keyed on the stable "Claude <Tier>" shape and
    /// fails safe — a miss just leaves the pill hidden, exactly as before.
    public static func plan(in text: String) -> String? {
        guard let m = text.firstMatch(
            of: /Claude\s+(Max|Pro|Free|Team|Enterprise)(?:\s+(\d+x))?/.ignoresCase()
        ) else { return nil }
        let tier = String(m.1).capitalized
        if let mult = m.2 { return "\(tier) \(String(mult).lowercased())" }
        return tier
    }

    // MARK: line classifiers

    /// Maps a panel label line to a window kind. Tolerant of casing and drift.
    static func windowKind(for line: String) -> WindowKind? {
        let l = line.lowercased()
        // Must be a short label line, not the paragraph mentioning "weekly usage limit".
        guard line.count <= 40 else { return nil }
        if l.hasPrefix("current session") { return .fiveHour }
        if l.hasPrefix("current week") {
            // "current week (all models)" -> weekly; "current week (Fable)" -> other
            if let inner = parenContents(line) {
                if inner.lowercased().contains("all models") { return .weekly }
                return .other("Weekly (\(inner))")
            }
            return .weekly
        }
        return nil
    }

    /// Extracts "N% used" -> N (Double), tolerant of surrounding bar characters and
    /// occasional TUI repaint gaps like "89% us d".
    static func percentUsed(in line: String) -> Double? {
        guard let m = line.firstMatch(of: /(\d{1,3})\s*%\s*u\s*s\s*e?\s*d/) else { return nil }
        return Double(m.1)
    }

    /// Extracts the "Resets …" text, dropping a trailing timezone parenthetical.
    static func resetText(in line: String) -> String? {
        guard let m = line.firstMatch(of: /[Rr]\s*e?sets?\s+(.+)/) else { return nil }
        var value = String(m.1).trimmingCharacters(in: .whitespaces)
        // Drop a trailing "(America/Los_Angeles)" for brevity.
        if let paren = value.range(of: " (") { value = String(value[..<paren.lowerBound]) }
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b([A-Za-z]{3,9}\s+\d{1,2})\s+t\s+(\d)"#, with: "$1 at $2", options: .regularExpression)
        return "Resets \(value)"
    }

    // MARK: helpers

    private static func parenContents(_ line: String) -> String? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"),
              open < close else { return nil }
        return String(line[line.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
    }

    private static func rank(_ kind: WindowKind) -> Int {
        switch kind {
        case .fiveHour: return 0
        case .weekly: return 1
        case .other: return 2
        }
    }
}
