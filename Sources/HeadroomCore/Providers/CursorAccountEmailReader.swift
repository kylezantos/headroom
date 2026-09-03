import Foundation

/// The email the Cursor account is signed in as. Injected so the provider can be tested
/// against fixture JSON instead of spawning the real CLI.
public protocol CursorAccountEmailReading: Sendable {
    /// The account email, or nil for every miss — CLI absent, timed out, signed out,
    /// or unparseable output. Never throws: identity is display context, and a missing
    /// email must never downgrade an otherwise good usage capture (KTD7).
    func readAccountEmail() async -> String?
}

/// Decodes **only** `userInfo.email` out of `cursor-agent status --format json`. The
/// decoder declares that single field, so nothing else the official CLI reports about
/// the session can be read into Headroom by accident.
public enum CursorStatusBlob {
    private struct Root: Decodable {
        struct UserInfo: Decodable {
            let email: String?
        }
        let userInfo: UserInfo?
    }

    public static func email(in data: Data) -> String? {
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return nil }
        return AccountEmail.normalized(root.userInfo?.email)
    }
}

/// Production reader: asks the official CLI who it is signed in as via
/// `cursor-agent status --format json`. Same compliant principle as every other path
/// here — the official client owns the session and this only reads what it prints. The
/// command is a free status surface: no model request, no auth mutation.
///
/// The panel probe carries no identity, so this is a second short, bounded invocation
/// rather than an extra parse of the TUI. A non-zero exit needs no special case: the
/// decode above is the gate, and error output carries no `userInfo.email`. CLI output is
/// never logged and never embedded in a `FailureReason`.
public struct CursorStatusEmailProbe: CursorAccountEmailReading {
    public let cursorPath: String?
    public let timeout: TimeInterval

    public init(
        cursorPath: String? = CursorUsageCLIProbe.resolveCursorPath(),
        timeout: TimeInterval = 5
    ) {
        self.cursorPath = cursorPath
        self.timeout = timeout
    }

    public func readAccountEmail() async -> String? {
        guard let cursorPath, FileManager.default.isExecutableFile(atPath: cursorPath) else {
            return nil
        }
        // Off the main actor and off the cooperative pool: the capture blocks on poll()
        // until the CLI answers or the hard deadline passes.
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let data = CursorUsageCLIProbe.captureStatusJSON(
                    cursorPath: cursorPath,
                    timeout: timeout,
                    // Stop as soon as the buffered bytes decode to an email — a report
                    // that is fully written but whose process lingers past the deadline
                    // must not cost the identity (or the full 5s) every poll.
                    isSufficient: { CursorStatusBlob.email(in: $0) != nil }
                )
                continuation.resume(returning: data.flatMap(CursorStatusBlob.email))
            }
        }
    }
}
