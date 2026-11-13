import Foundation
import Darwin

/// Headroom-owned config homes for additional (non-built-in) accounts. Each extra
/// account gets an isolated directory the official CLI signs into once:
/// - Claude: `CLAUDE_CONFIG_DIR` pointed at `…/claude/<id>/config`, plus a stable
///   `workspace` folder the probe cd's into (trust is recorded per config dir, so each
///   account approves the folder once — same flow as the built-in account).
/// - Codex: `CODEX_HOME` pointed at `…/codex/<id>`; `codex login` writes `auth.json`
///   there and Headroom only ever reads it (KTD3 unchanged).
/// - Grok: `GROK_HOME` pointed at `…/grok/<id>`; `grok login` writes `auth.json`
///   there and the official CLI does not fall back to the built-in account.
/// - OpenCode: the four XDG variables pointed at `…/opencode/<id>/{data,config,cache,state}`
///   (KTD10); the official 2.x client keeps its credential and token-refresh lock there.
///
/// The built-in `.primary` account never routes through here — it uses the CLI's own
/// default config so existing installs keep working untouched.
public enum AccountStorage {
    static let preparedMarkerGracePeriod: TimeInterval = 5 * 60

    private enum PendingSetupMarker {
        case opening(
            purpose: SetupHandoffPurpose,
            mode: SetupHandoffMode?,
            generation: String?,
            startedAt: Date?
        )
        case active(
            purpose: SetupHandoffPurpose,
            mode: SetupHandoffMode,
            generation: String?,
            pid: Int32
        )

        var purpose: SetupHandoffPurpose {
            switch self {
            case .opening(let purpose, _, _, _), .active(let purpose, _, _, _): purpose
            }
        }

        var mode: SetupHandoffMode? {
            switch self {
            case .opening(_, let mode, _, _): mode
            case .active(_, let mode, _, _): mode
            }
        }

        var generation: String? {
            switch self {
            case .opening(_, _, let generation, _), .active(_, _, let generation, _): generation
            }
        }
    }

    private enum SetupGenerationState {
        case active(String)
        case cancelled(String)

        var generation: String {
            switch self {
            case .active(let generation), .cancelled(let generation): generation
            }
        }
    }

    private struct CompletedSetupMarker {
        let purpose: SetupHandoffPurpose
        let generation: String?
        let completion: SetupHandoffCompletion
    }

    public static var baseDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Headroom", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    public static func accountDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    static func accountDirectoryURL(for account: ProviderAccount, baseDirectoryURL: URL) -> URL {
        baseDirectoryURL
            .appendingPathComponent(safePathComponent(account.providerID.raw), isDirectory: true)
            .appendingPathComponent(safePathComponent(account.id.raw), isDirectory: true)
    }

    /// Encode arbitrary persisted identifiers into one literal filesystem component.
    /// Production IDs are UUIDs and pass through unchanged; encoding keeps malformed
    /// metadata such as `..` or `a/b` contained beneath the Accounts directory.
    static func safePathComponent(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".utf8)
        guard !raw.isEmpty else { return "%00" }
        return raw.utf8.map { byte in
            allowed.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }.joined()
    }

    /// `CLAUDE_CONFIG_DIR` for an extra Claude account.
    public static func claudeConfigDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account).appendingPathComponent("config", isDirectory: true)
    }

    /// `CLAUDE_CONFIG_DIR` for an extra Claude account, addressed by id alone. The path
    /// depends only on provider + account id, so the email reader can resolve it without
    /// threading a whole `ProviderAccount` down into the provider.
    static func claudeConfigDirectoryURL(forClaudeAccountID accountID: AccountID) -> URL {
        claudeConfigDirectoryURL(
            for: ProviderAccount(id: accountID, providerID: .claude, label: "")
        )
    }

    /// Working directory the probe runs `claude` in for an extra Claude account.
    public static func claudeWorkspaceDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account).appendingPathComponent("workspace", isDirectory: true)
    }

    /// `CODEX_HOME` for an extra Codex account; `auth.json` lives directly inside.
    public static func codexHomeDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account)
    }

    public static func codexAuthFileURL(for account: ProviderAccount) -> URL {
        codexHomeDirectoryURL(for: account).appendingPathComponent("auth.json")
    }

    /// `GROK_HOME` for an extra Grok account; `auth.json` lives directly inside.
    public static func grokHomeDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account)
    }

    public static func grokAuthFileURL(for account: ProviderAccount) -> URL {
        grokHomeDirectoryURL(for: account).appendingPathComponent("auth.json")
    }

    /// The root holding an extra OpenCode account's `data`, `config`, `cache` and `state`
    /// folders (KTD10). Data and state always come from this one root, because the client's
    /// token-refresh lock lives under state.
    public static func opencodeHomeDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account)
    }

    /// KTD10: the built-in account reads the default home; every extra reads only its own.
    public static func opencodeAccountHome(for account: ProviderAccount) -> OpenCodeAccountHome {
        opencodeAccountHome(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    static func opencodeAccountHome(for account: ProviderAccount, baseDirectoryURL: URL) -> OpenCodeAccountHome {
        guard !account.isBuiltIn else { return .builtIn }
        return .isolated(root: accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL).path)
    }

    /// The four XDG folders `ensureDirectories` creates for an extra OpenCode account.
    static let opencodeXDGFolderNames = ["data", "config", "cache", "state"]

    /// Single source of truth for setup-handoff marker paths, for ANY account.
    /// Extra accounts keep their markers inside their Headroom-owned config home.
    /// Built-in accounts have no config home Headroom owns (their config is the CLI's
    /// default), so their markers live in the shared `Setup/` directory beside the
    /// built-in Claude workspace — the same location `SetupSessions` stages handoff
    /// scripts. Every handoff-liveness check must resolve through here; a divergent
    /// resolver once let built-in stop-tracking look at the wrong path, report "no
    /// handoff", and detach the row mid-setup (code-review finding).
    public static func setupCompletionMarker(
        for account: ProviderAccount,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) -> SetupCompletionMarker {
        guard account.isBuiltIn else {
            let directory = accountDirectoryURL(for: account)
            return SetupCompletionMarker(
                pendingPath: directory.appendingPathComponent(".headroom-setup-pending").path,
                completedPath: directory.appendingPathComponent(".headroom-setup-complete").path
            )
        }
        let directory = builtInClaudeWorkspace
            .deletingLastPathComponent()
            .appendingPathComponent("Setup", isDirectory: true)
        let stem = ".headroom-\(safePathComponent(account.providerID.raw))-setup"
        return SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("\(stem)-pending").path,
            completedPath: directory.appendingPathComponent("\(stem)-complete").path
        )
    }

    /// Stage one generation before Terminal opens. Per-generation pending/completion
    /// files keep a cancelled wrapper physically separate from its successor, while
    /// the durable state file lets relaunch recovery reject cancelled generations.
    /// All fields are fixed allowlisted protocol data; no account identity is stored.
    @discardableResult
    public static func prepareSetupCompletionMarker(
        _ marker: SetupCompletionMarker,
        mode: SetupHandoffMode = .standard,
        purpose: SetupHandoffPurpose = .setup,
        startedAt: Date = .now
    ) throws -> String {
        let manager = FileManager.default
        let generation = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let pendingURL = URL(fileURLWithPath: generatedPendingPath(marker, generation: generation))
        try manager.createDirectory(
            at: pendingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if let previous = parseGenerationState(marker: marker) {
            removeGeneratedMarkers(marker, generation: previous.generation)
        }
        let opening = "opening:\(purpose.rawValue):\(markerName(for: mode)):\(generation):\(startedAt.timeIntervalSince1970)\n"
        do {
            try writeOwnerOnly(opening, to: pendingURL)
            // R2M12: the generation state is the only handoff file the wrapper never
            // rewrites, so it is where the waiting clock's start survives. The opening
            // marker carries the same instant but zsh replaces it with its PID as soon as
            // Terminal is up, which is exactly the window a relaunch lands in.
            try writeGenerationState(.active(generation), marker: marker, startedAt: startedAt)
        } catch {
            try? manager.removeItem(at: pendingURL)
            throw error
        }
        // A new generation safely supersedes a cancellation tombstone and any legacy
        // fixed-path marker. Late legacy wrappers can only touch these unused paths.
        try? manager.removeItem(atPath: marker.pendingPath)
        try? manager.removeItem(atPath: marker.completedPath)
        return generation
    }

    public static func clearPreparedSetupCompletionMarker(_ marker: SetupCompletionMarker) {
        if case .active(let generation) = parseGenerationState(marker: marker) {
            removeGeneratedMarkers(marker, generation: generation)
            try? FileManager.default.removeItem(atPath: generationStatePath(marker))
        }
        try? FileManager.default.removeItem(atPath: marker.pendingPath)
        try? FileManager.default.removeItem(atPath: marker.completedPath)
    }

    /// Cancel the current generation before removing its files. The tombstone remains
    /// until a successor is safely staged, so a late wrapper completion stays ignored
    /// across app relaunches. This never terminates the external Terminal process.
    public static func clearSetupCompletionMarkers(_ marker: SetupCompletionMarker) {
        let generation = parseGenerationState(marker: marker)?.generation ?? "legacy"
        try? writeGenerationState(.cancelled(generation), marker: marker)
        if generation != "legacy" {
            removeGeneratedMarkers(marker, generation: generation)
        }
        try? FileManager.default.removeItem(atPath: marker.pendingPath)
        try? FileManager.default.removeItem(atPath: marker.completedPath)
    }

    /// Consume an inactive handoff after its result has been delivered. Cancellation
    /// tombstones are deliberately retained until successor staging.
    public static func clearFinishedSetupCompletionMarkers(_ marker: SetupCompletionMarker) {
        switch parseGenerationState(marker: marker) {
        case .active(let generation):
            removeGeneratedMarkers(marker, generation: generation)
            try? FileManager.default.removeItem(atPath: generationStatePath(marker))
        case .cancelled:
            break
        case nil:
            try? FileManager.default.removeItem(atPath: marker.pendingPath)
            try? FileManager.default.removeItem(atPath: marker.completedPath)
        }
    }

    /// Read only the current generation's allowlisted completion marker, plus the two
    /// legacy fixed-path forms. Cancelled/stale generations remain unknown.
    public static func setupHandoffCompletion(
        marker: SetupCompletionMarker
    ) -> SetupHandoffCompletion {
        switch parseGenerationState(marker: marker) {
        case .active(let generation):
            let completed = parseCompletedMarker(
                atPath: generatedCompletedPath(marker, generation: generation)
            )
            return completed?.generation == generation ? completed?.completion ?? .unknown : .unknown
        case .cancelled:
            return .unknown
        case nil:
            if generationStateExists(marker) { return .unknown }
            return parseCompletedMarker(atPath: marker.completedPath)?.completion ?? .unknown
        }
    }

    /// Purpose is durable across both the opening/active pending marker and the final
    /// completion marker. Legacy markers predate reset and therefore mean setup.
    public static func setupHandoffPurpose(
        marker: SetupCompletionMarker
    ) -> SetupHandoffPurpose? {
        switch parseGenerationState(marker: marker) {
        case .active(let generation):
            let pending = parsePendingMarker(
                atPath: generatedPendingPath(marker, generation: generation)
            )
            if pending?.generation == generation { return pending?.purpose }
            let completed = parseCompletedMarker(
                atPath: generatedCompletedPath(marker, generation: generation)
            )
            return completed?.generation == generation ? completed?.purpose : nil
        case .cancelled:
            return nil
        case nil:
            if generationStateExists(marker) { return nil }
            if FileManager.default.fileExists(atPath: marker.pendingPath) {
                return parsePendingMarker(atPath: marker.pendingPath)?.purpose
            }
            return parseCompletedMarker(atPath: marker.completedPath)?.purpose
        }
    }

    /// A short-lived `opening` marker covers the gap between AppKit accepting the file
    /// and zsh replacing it with its PID. If the app or Terminal crashes in that gap,
    /// the marker expires rather than blocking account removal forever. Unknown marker
    /// formats still fail closed; a PID clears only when the process is provably gone.
    public static func setupHandoffIsActive(
        for account: ProviderAccount,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL,
        now: Date = .now
    ) -> Bool {
        setupHandoffIsActive(
            marker: setupCompletionMarker(
                for: account,
                builtInClaudeWorkspace: builtInClaudeWorkspace
            ),
            now: now
        )
    }

    public static func setupHandoffIsActive(
        marker: SetupCompletionMarker,
        now: Date = .now
    ) -> Bool {
        let manager = FileManager.default
        let pendingPath: String
        let isLegacy: Bool
        switch parseGenerationState(marker: marker) {
        case .active(let generation):
            isLegacy = false
            let completion = parseCompletedMarker(
                atPath: generatedCompletedPath(marker, generation: generation)
            )
            if completion?.generation == generation { return false }
            pendingPath = generatedPendingPath(marker, generation: generation)
            guard manager.fileExists(atPath: pendingPath) else { return true }
        case .cancelled:
            return false
        case nil:
            if generationStateExists(marker) { return true }
            isLegacy = true
            pendingPath = marker.pendingPath
            guard manager.fileExists(atPath: pendingPath) else { return false }
        }
        guard let pending = parsePendingMarker(atPath: pendingPath) else { return true }
        if !isLegacy,
           case .active(let generation) = parseGenerationState(marker: marker),
           pending.generation != generation {
            return true
        }
        switch pending {
        case .opening(_, _, _, let encodedDate):
            let attributes = try? manager.attributesOfItem(atPath: pendingPath)
            let writtenAt = encodedDate ?? attributes?[.modificationDate] as? Date
            guard let writtenAt,
                  now.timeIntervalSince(writtenAt) > preparedMarkerGracePeriod
            else { return true }
            if isLegacy { try? manager.removeItem(atPath: pendingPath) }
            return false
        case .active(_, _, _, let pid):
            if kill(pid, 0) == 0 || errno == EPERM { return true }
            guard errno == ESRCH else { return true }
            if isLegacy { try? manager.removeItem(atPath: pendingPath) }
            return false
        }
    }

    /// R2M12: when the current handoff started, so a wait restored after a relaunch can keep
    /// counting instead of falling back to the card-derived header line. Fails safe to `nil`
    /// — a cancelled generation, a state file written before the start was persisted, an
    /// unparseable timestamp, or a start in the future all mean "no clock", never a
    /// fabricated one.
    public static func setupHandoffStartedAt(
        marker: SetupCompletionMarker,
        now: Date = .now
    ) -> Date? {
        guard case .active = parseGenerationState(marker: marker),
              let startedAt = parseGenerationStart(marker: marker),
              !(startedAt > now)
        else { return nil }
        return startedAt
    }

    /// KTD8/KTD13 (2026-09-19 sign-in plan): write the handoff's own record beside its
    /// generation. It deliberately lives outside the pending and generation-state lines,
    /// which `SetupCompletionCommand.wrap` pins at open and compares at exit — appending to
    /// either would make every wrapper record no completion. All fields are allowlisted
    /// protocol data; the account is identified by the marker path alone, exactly as the
    /// other handoff files are.
    public static func writeSetupHandoffRecord(
        _ record: SetupHandoffRecord,
        marker: SetupCompletionMarker,
        generation: String
    ) throws {
        guard isMarkerGeneration(generation) else { return }
        let identifier = record.terminalBundleIdentifier.flatMap(bundleIdentifier(_:)) ?? ""
        // KTD11: the interactive reason joins the record for the same reason the policy did
        // — R15 asks a restored handoff to state its phase, and the CLI version the reason
        // was read from can change while the original Terminal is still open.
        let reason = record.claudeInteractiveReason?.rawValue ?? ""
        try writeOwnerOnly(
            "record:\(record.waitingPolicy.rawValue):\(identifier):\(reason)\n",
            to: URL(fileURLWithPath: setupHandoffRecordPath(marker, generation: generation))
        )
    }

    /// KTD8: the current generation's record, or nil when the handoff was opened by a
    /// build that wrote none — restore then falls back by purpose rather than guessing.
    public static func setupHandoffRecord(
        marker: SetupCompletionMarker
    ) -> SetupHandoffRecord? {
        guard case .active(let generation) = parseGenerationState(marker: marker),
              let value = markerValue(
                  atPath: setupHandoffRecordPath(marker, generation: generation)
              )
        else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        // A three-field record was written by a build before KTD11's reason field; it reads
        // back with no reason, which is the safe default (the plain sign-in copy).
        guard parts.count == 3 || parts.count == 4,
              parts[0] == "record",
              let policy = SetupWaitingPolicy(rawValue: String(parts[1]))
        else { return nil }
        return SetupHandoffRecord(
            waitingPolicy: policy,
            terminalBundleIdentifier: bundleIdentifier(String(parts[2])),
            claudeInteractiveReason: parts.count == 4
                ? ClaudeInteractiveLaunchReason(rawValue: String(parts[3]))
                : nil
        )
    }

    static func setupHandoffRecordPath(
        _ marker: SetupCompletionMarker,
        generation: String
    ) -> String {
        precondition(isMarkerGeneration(generation))
        return marker.pendingPath + ".record." + generation
    }

    /// Reverse-DNS identifiers only. Anything else — a separator that would break the
    /// record's own format, whitespace, a shell metacharacter — is dropped rather than
    /// stored and later handed to AppKit.
    private static func bundleIdentifier(_ value: String) -> String? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-".utf8)
        guard !value.isEmpty, value.utf8.count <= 255, value.utf8.allSatisfy(allowed.contains)
        else { return nil }
        return value
    }

    /// Restore the explicit login mode after an app relaunch while Terminal remains
    /// open. New opening markers include mode; legacy PID-only markers are standard.
    public static func setupHandoffMode(marker: SetupCompletionMarker) -> SetupHandoffMode? {
        switch parseGenerationState(marker: marker) {
        case .active(let generation):
            let pending = parsePendingMarker(
                atPath: generatedPendingPath(marker, generation: generation)
            )
            return pending?.generation == generation ? pending?.mode : nil
        case .cancelled:
            return nil
        case nil:
            if generationStateExists(marker) { return nil }
            return parsePendingMarker(atPath: marker.pendingPath)?.mode
        }
    }

    private static func parsePendingMarker(atPath path: String) -> PendingSetupMarker? {
        guard let value = markerValue(atPath: path) else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)

        if value == "opening" {
            return .opening(purpose: .setup, mode: nil, generation: nil, startedAt: nil)
        }
        if parts.count == 2,
           parts[0] == "opening",
           let timestamp = markerTimestamp(parts[1]) {
            return .opening(
                purpose: .setup,
                mode: nil,
                generation: nil,
                startedAt: Date(timeIntervalSince1970: timestamp)
            )
        }
        if parts.count == 4,
           parts[0] == "opening",
           let purpose = SetupHandoffPurpose(rawValue: String(parts[1])),
           let mode = setupMode(named: parts[2]),
           let timestamp = markerTimestamp(parts[3]) {
            return .opening(
                purpose: purpose,
                mode: mode,
                generation: nil,
                startedAt: Date(timeIntervalSince1970: timestamp)
            )
        }
        if parts.count == 5,
           parts[0] == "opening",
           let purpose = SetupHandoffPurpose(rawValue: String(parts[1])),
           let mode = setupMode(named: parts[2]),
           let generation = markerGeneration(parts[3]),
           let timestamp = markerTimestamp(parts[4]) {
            return .opening(
                purpose: purpose,
                mode: mode,
                generation: generation,
                startedAt: Date(timeIntervalSince1970: timestamp)
            )
        }
        if parts.count == 1,
           let pid = markerPID(parts[0]) {
            return .active(purpose: .setup, mode: .standard, generation: nil, pid: pid)
        }
        if parts.count == 2,
           let mode = setupMode(named: parts[0]),
           let pid = markerPID(parts[1]) {
            return .active(purpose: .setup, mode: mode, generation: nil, pid: pid)
        }
        if parts.count == 3,
           let purpose = SetupHandoffPurpose(rawValue: String(parts[0])),
           let mode = setupMode(named: parts[1]),
           let pid = markerPID(parts[2]) {
            return .active(purpose: purpose, mode: mode, generation: nil, pid: pid)
        }
        if parts.count == 4,
           let purpose = SetupHandoffPurpose(rawValue: String(parts[0])),
           let mode = setupMode(named: parts[1]),
           let generation = markerGeneration(parts[2]),
           let pid = markerPID(parts[3]) {
            return .active(purpose: purpose, mode: mode, generation: generation, pid: pid)
        }
        return nil
    }

    private static func parseCompletedMarker(atPath path: String) -> CompletedSetupMarker? {
        guard let value = markerValue(atPath: path) else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        let purpose: SetupHandoffPurpose
        let generation: String?
        let statusText: Substring
        switch parts.count {
        case 2 where parts[0] == "complete":
            purpose = .setup
            generation = nil
            statusText = parts[1]
        case 3 where parts[0] == "complete":
            guard let parsed = SetupHandoffPurpose(rawValue: String(parts[1])) else { return nil }
            purpose = parsed
            generation = nil
            statusText = parts[2]
        case 4 where parts[0] == "complete":
            guard let parsedPurpose = SetupHandoffPurpose(rawValue: String(parts[1])),
                  let parsedGeneration = markerGeneration(parts[2])
            else { return nil }
            purpose = parsedPurpose
            generation = parsedGeneration
            statusText = parts[3]
        default:
            return nil
        }
        guard decimalDigitsOnly(statusText), let status = UInt8(statusText) else { return nil }
        return CompletedSetupMarker(
            purpose: purpose,
            generation: generation,
            completion: status == 0 ? .succeeded : .failed
        )
    }

    private static func parseGenerationState(marker: SetupCompletionMarker) -> SetupGenerationState? {
        guard let value = markerValue(atPath: generationStatePath(marker)) else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        // R2M12 appended an optional start to the active form; a two-field file is a state
        // written before that and still names a valid generation.
        guard parts.count == 2 || parts.count == 3 else { return nil }
        if parts.count == 2, parts[0] == "cancelled", parts[1] == "legacy" { return .cancelled("legacy") }
        guard let generation = markerGeneration(parts[1]) else { return nil }
        switch parts[0] {
        case "active": return .active(generation)
        case "cancelled": return .cancelled(generation)
        default: return nil
        }
    }

    private static func parseGenerationStart(marker: SetupCompletionMarker) -> Date? {
        guard let value = markerValue(atPath: generationStatePath(marker)) else { return nil }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "active",
              markerGeneration(parts[1]) != nil,
              let timestamp = markerTimestamp(parts[2])
        else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func generationStateExists(_ marker: SetupCompletionMarker) -> Bool {
        FileManager.default.fileExists(atPath: generationStatePath(marker))
    }

    private static func writeGenerationState(
        _ state: SetupGenerationState,
        marker: SetupCompletionMarker,
        startedAt: Date? = nil
    ) throws {
        let kind = switch state {
        case .active: "active"
        case .cancelled: "cancelled"
        }
        // R2M12: a cancellation tombstone deliberately carries no start — the wait it
        // describes is over, so there is nothing left to clock.
        let start = startedAt.map { ":\($0.timeIntervalSince1970)" } ?? ""
        try writeOwnerOnly(
            "\(kind):\(state.generation)\(start)\n",
            to: URL(fileURLWithPath: generationStatePath(marker))
        )
    }

    private static func writeOwnerOnly(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func generationStatePath(_ marker: SetupCompletionMarker) -> String {
        marker.pendingPath + ".state"
    }

    static func generatedPendingPath(_ marker: SetupCompletionMarker, generation: String) -> String {
        precondition(isMarkerGeneration(generation))
        return marker.pendingPath + "." + generation
    }

    static func generatedCompletedPath(_ marker: SetupCompletionMarker, generation: String) -> String {
        precondition(isMarkerGeneration(generation))
        return marker.completedPath + "." + generation
    }

    static func setupHandoffGeneration(marker: SetupCompletionMarker) -> String? {
        guard case .active(let generation) = parseGenerationState(marker: marker) else { return nil }
        return generation
    }

    private static func removeGeneratedMarkers(
        _ marker: SetupCompletionMarker,
        generation: String
    ) {
        guard isMarkerGeneration(generation) else { return }
        try? FileManager.default.removeItem(
            atPath: generatedPendingPath(marker, generation: generation)
        )
        try? FileManager.default.removeItem(
            atPath: generatedCompletedPath(marker, generation: generation)
        )
        // KTD8: the record belongs to this generation, so it goes wherever the generation's
        // markers go — handoff end, force-cancel, and a successor superseding it.
        try? FileManager.default.removeItem(
            atPath: setupHandoffRecordPath(marker, generation: generation)
        )
    }

    private static func markerValue(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markerTimestamp(_ value: Substring) -> Double? {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (fields.count == 1 || fields.count == 2),
              fields.allSatisfy({ !$0.isEmpty && decimalDigitsOnly($0) }),
              let timestamp = Double(value), timestamp.isFinite
        else { return nil }
        return timestamp
    }

    private static func markerPID(_ value: Substring) -> Int32? {
        guard decimalDigitsOnly(value), let pid = Int32(value), pid > 1 else { return nil }
        return pid
    }

    private static func markerGeneration(_ value: Substring) -> String? {
        let generation = String(value)
        return isMarkerGeneration(generation) ? generation : nil
    }

    private static func isMarkerGeneration(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private static func decimalDigitsOnly(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    private static func markerName(for mode: SetupHandoffMode) -> String {
        mode == .deviceCode ? "deviceCode" : "standard"
    }

    private static func setupMode(named value: Substring) -> SetupHandoffMode? {
        switch value {
        case "standard": .standard
        case "deviceCode": .deviceCode
        default: nil
        }
    }

    /// Create the account's directories so the CLI handoff and probe never race a
    /// missing folder. Safe to call repeatedly.
    @discardableResult
    public static func ensureDirectories(for account: ProviderAccount) throws -> URL {
        try ensureDirectories(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    @discardableResult
    static func ensureDirectories(for account: ProviderAccount, baseDirectoryURL: URL) throws -> URL {
        let directory = accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL)
        var targets = [directory]
        if account.providerID == .claude {
            targets.append(directory.appendingPathComponent("config", isDirectory: true))
            targets.append(directory.appendingPathComponent("workspace", isDirectory: true))
        }
        if account.providerID == .opencode {
            // KTD10: all four, so the client never creates one with its own permissions and
            // data and state can never come from different roots.
            targets += opencodeXDGFolderNames.map { directory.appendingPathComponent($0, isDirectory: true) }
        }
        for url in targets {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        return directory
    }

    /// Delete an extra account's config home (its CLI session/token included) after the
    /// account is removed from the registry. Built-in accounts are never touched — their
    /// config belongs to the user's own CLI. The recursive delete runs off-main: a used
    /// config home holds thousands of small CLI files and must not beachball the
    /// Settings window (code-review finding).
    public static func removeDirectories(for account: ProviderAccount) throws {
        try removeDirectories(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    static func removeDirectories(for account: ProviderAccount, baseDirectoryURL: URL) throws {
        guard !account.isBuiltIn else { return }
        let url = accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let marker = SetupCompletionMarker(
            pendingPath: url.appendingPathComponent(".headroom-setup-pending").path,
            completedPath: url.appendingPathComponent(".headroom-setup-complete").path
        )
        guard !setupHandoffIsActive(marker: marker) else {
            throw AccountStorageOperationError.setupActive
        }
        try FileManager.default.removeItem(at: url)
    }

    public static func credentialFilePermissionsAreSafe(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else { return false }
        return permissions.intValue & 0o077 == 0
    }
}

/// KTD8/KTD13 (2026-09-19 sign-in plan): what a handoff has to remember about itself
/// across a relaunch, beyond the wrapper protocol's own marker lines. The waiting policy
/// is read back rather than re-derived, because the CLI version it was chosen from can
/// change while the original Terminal is still open.
public struct SetupHandoffRecord: Sendable, Equatable {
    public let waitingPolicy: SetupWaitingPolicy
    /// The app LaunchServices resolved when the handoff opened, so Show Terminal fronts
    /// the window that actually holds it. Nil when none was resolved.
    public let terminalBundleIdentifier: String?
    /// KTD11/R6: why staging chose the interactive launch, which decides whether the
    /// waiting copy tells the user to type `/login`. Nil for a sign-in script, for a
    /// non-Claude handoff, and for a record written before this field existed.
    public let claudeInteractiveReason: ClaudeInteractiveLaunchReason?

    public init(
        waitingPolicy: SetupWaitingPolicy,
        terminalBundleIdentifier: String?,
        claudeInteractiveReason: ClaudeInteractiveLaunchReason? = nil
    ) {
        self.waitingPolicy = waitingPolicy
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.claudeInteractiveReason = claudeInteractiveReason
    }
}

public enum AccountStorageFailure: Error, Sendable, Equatable {
    case createFailed
    case setupActive
    case removeFailed
}

private enum AccountStorageOperationError: Error {
    case setupActive
}

/// Injection seam for the account config-home file operations, so `UsageStore` unit
/// tests never touch the real Application Support tree (AGENTS.md: the suite is all
/// mocked — no CLI/network/Keychain/filesystem).
public protocol AccountStorageManaging: Sendable {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure>
    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure>
}

public extension AccountStorageManaging {
    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool { false }
}

public struct DefaultAccountStorage: AccountStorageManaging {
    /// Built-in accounts anchor their setup markers beside this workspace (see
    /// `AccountStorage.setupCompletionMarker`); injectable so tests never touch the
    /// real Application Support tree.
    private let builtInClaudeWorkspace: URL

    public init(builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL) {
        self.builtInClaudeWorkspace = builtInClaudeWorkspace
    }
    public func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> {
        do {
            _ = try AccountStorage.ensureDirectories(for: account)
            return .success(())
        } catch {
            return .failure(.createFailed)
        }
    }
    public func setupHandoffIsActive(for account: ProviderAccount) async -> Bool {
        let workspace = builtInClaudeWorkspace
        return await Task.detached(priority: .utility) {
            AccountStorage.setupHandoffIsActive(for: account, builtInClaudeWorkspace: workspace)
        }.value
    }
    public func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> {
        await Task.detached(priority: .utility) {
            do {
                try AccountStorage.removeDirectories(for: account)
                return .success(())
            } catch AccountStorageOperationError.setupActive {
                return .failure(.setupActive)
            } catch {
                return .failure(.removeFailed)
            }
        }.value
    }
}
