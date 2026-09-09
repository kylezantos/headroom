import Foundation

/// Stable workspace used when Headroom drives Claude Code for `/usage`.
/// Claude Code records trust per working directory, so using a Headroom-owned empty
/// folder avoids asking users to trust transient locations like the DMG or /Applications.
public enum ClaudeUsageWorkspace {
    public static let trustRequiredMessage = "Open Claude setup to trust Headroom’s Claude folder"

    public static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Headroom", isDirectory: true)
            .appendingPathComponent("ClaudeProbe", isDirectory: true)
    }

    @discardableResult
    public static func ensureDefaultDirectory() throws -> URL {
        try ensureDirectory(at: defaultDirectoryURL)
    }

    /// Provision the exact Headroom-owned workspace a Claude probe or setup handoff
    /// will enter. Keeping this idempotent invariant beside the path definition avoids
    /// handing a valid-looking URL to `posix_spawn` or zsh before the directory exists.
    @discardableResult
    public static func ensureDirectory(at url: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CocoaError(.fileWriteFileExists)
            }
            return url
        }
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }
}
