import Foundation

/// Claude usage provider (U4). Reads the real 5-hour and weekly windows from Claude
/// Code's own `/usage` panel via `ClaudeUsageSource` — the compliant path, since the
/// official CLI makes the request and this only reads what it prints. Never throws:
/// a missing CLI or unreadable panel degrades to a typed stale state (KTD7).
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude
    public let displayName = "Claude"

    private let source: ClaudeUsageSource
    private let now: @Sendable () -> Date

    public init(
        source: ClaudeUsageSource = ClaudeUsageCLIProbe(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await source.capturePanel() {
        case .cliNotFound:
            return stale(.notLoggedIn("Install Claude Code to show usage"))
        case .failed:
            return stale(.transient("Couldn't read Claude usage — will retry"))
        case .panel(let text):
            let parsed = ClaudeUsageParser.parse(text)
            guard !parsed.isEmpty else {
                if text.localizedCaseInsensitiveContains("Quick safety check")
                    || text.localizedCaseInsensitiveContains("trust this folder") {
                    return stale(.needsReauth(ClaudeUsageWorkspace.trustRequiredMessage))
                }
                // Panel captured but no windows found: most often "not logged in".
                if text.lowercased().contains("log in") || text.lowercased().contains("login") {
                    return stale(.needsReauth("Run `claude` and log in"))
                }
                return stale(.transient("Couldn't read Claude usage — will retry"))
            }
            let windows = parsed.map { window in
                UsageWindow(
                    kind: window.kind,
                    utilization: window.percentUsed,
                    resetsAt: ResetDate.parse(window.resetLabel, now: now()) ?? now(),
                    resetLabel: window.resetLabel
                )
            }
            return UsageSnapshot(
                providerID: id,
                windows: windows,
                planLabel: ClaudeUsageParser.plan(in: text),
                capturedAt: now(),
                freshness: .live
            )
        }
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}

/// Best-effort parse of Claude's reset text ("Resets 10:10am", "Resets Jul 2 at 10am")
/// into a `Date`, used only for the countdown fallback — the verbatim `resetLabel` is
/// what the UI actually shows, so a miss here is harmless.
enum ResetDate {
    static func parse(_ label: String?, now: Date) -> Date? {
        guard let label else { return nil }
        let text = label.replacingOccurrences(of: "Resets", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current

        // "10:10am" / "10am" -> next occurrence of that clock time.
        if let time = clockTime(text) {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = time.hour; comps.minute = time.minute
            if let candidate = cal.date(from: comps) {
                return candidate > now ? candidate : cal.date(byAdding: .day, value: 1, to: candidate)
            }
        }
        // "Jul 2 at 10am" -> that month/day at that hour.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        for format in ["MMM d 'at' ha", "MMM d 'at' h:mma", "MMMM d 'at' ha"] {
            df.dateFormat = format
            if let parsed = df.date(from: text) {
                var comps = cal.dateComponents([.month, .day, .hour, .minute], from: parsed)
                comps.year = cal.component(.year, from: now)
                if let candidate = cal.date(from: comps) { return candidate }
            }
        }
        return nil
    }

    private static func clockTime(_ text: String) -> (hour: Int, minute: Int)? {
        guard let m = text.firstMatch(of: /^(\d{1,2})(?::(\d{2}))?\s*(am|pm)/.ignoresCase()) else { return nil }
        var hour = Int(m.1) ?? 0
        let minute = m.2.flatMap { Int($0) } ?? 0
        let pm = m.3.lowercased() == "pm"
        if pm && hour < 12 { hour += 12 }
        if !pm && hour == 12 { hour = 0 }
        return (hour, minute)
    }
}
