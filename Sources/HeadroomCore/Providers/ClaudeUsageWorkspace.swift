import Foundation

/// Stable workspace used when Headroom drives Claude Code for `/usage`.
/// Claude Code records trust per working directory, so using a Headroom-owned empty
/// folder avoids asking users to trust transient locations like the DMG or /Applications.
public enum ClaudeUsageWorkspace {
    public static let trustRequiredMessage = "Open Claude setup to trust Headroom's Claude folder"

    public static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Headroom", isDirectory: true)
            .appendingPathComponent("ClaudeProbe", isDirectory: true)
    }

    @discardableResult
    public static func ensureDefaultDirectory() throws -> URL {
        let url = defaultDirectoryURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
