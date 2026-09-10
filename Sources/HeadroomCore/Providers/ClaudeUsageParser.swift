import Foundation

/// One usage window parsed out of Claude Code's `/usage` panel.
public struct ParsedUsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let percentUsed: Double
    public let resetLabel: String?
    public let resetTimeZoneIdentifier: String?
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
            // Print-mode reports (`claude -p "/usage"`) carry a whole window on one
            // line: "Current week (Fable): 7% used · resets Aug 6 at 10am (…)". The
            // interactive panel never puts the percent on the label line, so this
            // shape cannot collide with the TUI scan below.
            if let inline = inlineWindow(in: lines[i]) {
                byKind[inline.kind] = inline
                i += 1
                continue
            }
            guard let kind = windowKind(for: lines[i]) else { i += 1; continue }
            // Scan the next few lines for this window's percent + reset text.
            var percent: Double?
            var reset: ResetMetadata?
            var j = i + 1
            let limit = min(lines.count, i + 5)
            while j < limit {
                if percent == nil, let p = percentUsed(in: lines[j]) { percent = p }
                if reset == nil, let r = resetMetadata(in: lines[j]) { reset = r }
                // Stop early if the next window label appears.
                if windowKind(for: lines[j]) != nil { break }
                j += 1
            }
            if let percent {
                byKind[kind] = ParsedUsageWindow(
                    kind: kind,
                    percentUsed: percent,
                    resetLabel: reset?.label,
                    resetTimeZoneIdentifier: reset?.timeZoneIdentifier
                )
            }
            i += 1
        }

        // Stable order: 5-hour, weekly, then any extras alphabetically.
        return byKind.values.sorted { displayRank($0.kind) < displayRank($1.kind) }
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

    /// Parses the single-line window shape of the non-interactive `/usage` report:
    /// "<label>: N% used · resets <when>". Returns nil for every interactive-panel
    /// line (label lines carry no percent; bar lines carry no window label).
    static func inlineWindow(in line: String) -> ParsedUsageWindow? {
        guard let colon = line.firstIndex(of: ":"),
              let kind = windowKind(for: String(line[..<colon]))
        else { return nil }
        let rest = String(line[line.index(after: colon)...])
        guard let percent = percentUsed(in: rest) else { return nil }
        let reset = resetMetadata(in: rest)
        return ParsedUsageWindow(
            kind: kind,
            percentUsed: percent,
            resetLabel: reset?.label,
            resetTimeZoneIdentifier: reset?.timeZoneIdentifier
        )
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

    /// Extracts normalized source copy and preserves a trailing IANA zone separately.
    private static func resetMetadata(in line: String) -> ResetMetadata? {
        guard let m = line.firstMatch(of: /[Rr]\s*e?sets?\s+(.+)/) else { return nil }
        var value = String(m.1).trimmingCharacters(in: .whitespaces)
        var timeZoneIdentifier: String?
        if value.hasSuffix(")"),
           let open = value.lastIndex(of: "("),
           open > value.startIndex {
            let zoneStart = value.index(after: open)
            let zoneEnd = value.index(before: value.endIndex)
            let candidate = String(value[zoneStart..<zoneEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            timeZoneIdentifier = candidate.isEmpty ? nil : candidate
            value = String(value[..<open]).trimmingCharacters(in: .whitespaces)
        }
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\b([A-Za-z]{3,9}\s+\d{1,2})\s+t\s+(\d)"#, with: "$1 at $2", options: .regularExpression)
        return ResetMetadata(label: "Resets \(value)", timeZoneIdentifier: timeZoneIdentifier)
    }

    // MARK: helpers

    private static func parenContents(_ line: String) -> String? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"),
              open < close else { return nil }
        return String(line[line.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
    }

    /// The one window order every Claude surface renders: 5-hour, then the weekly/billing
    /// pool, then model-specific extras. Exposed (rather than kept private to `parse`)
    /// because the demo fixtures must sort through the same rule — hand-ordered fixture
    /// literals drifted from it and shipped marketing captures with Weekly first while
    /// every live popover showed 5-hour first (pre-ship craft audit, 2026-09-08).
    public static func displayRank(_ kind: WindowKind) -> Int {
        switch kind {
        case .fiveHour: return 0
        case .weekly: return 1
        case .billingPeriod: return 1
        case .other: return 2
        }
    }

    /// `displayRank` applied to already-built windows, preserving the caller's order
    /// within a rank so equal-rank rows keep the sequence the source produced.
    public static func sortedForDisplay(_ windows: [UsageWindow]) -> [UsageWindow] {
        windows.enumerated()
            .sorted { lhs, rhs in
                let left = displayRank(lhs.element.kind)
                let right = displayRank(rhs.element.kind)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}

private struct ResetMetadata {
    let label: String
    let timeZoneIdentifier: String?
}
