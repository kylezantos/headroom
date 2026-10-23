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
        } else {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        }
        // Best effort: the per-launch `--settings` opt-out is the primary guard, so a
        // file-system hiccup here must not make the account unprobeable.
        try? ensureRemoteControlOptOut(in: url)
        return url
    }

    /// Second Remote Control layer (Brief 03): Claude Code honors a project or local
    /// `remoteControlAtStartup: false` over every other source, managed settings
    /// included, so interactive launches in this folder never auto-connect. Only this
    /// key is written; other keys survive, and a file that is not a JSON object is left
    /// alone rather than overwritten. Whether the CLI reads it before the workspace is
    /// trusted is unverified, which is why it is the second layer.
    public static func ensureRemoteControlOptOut(in workspace: URL) throws {
        let fileManager = FileManager.default
        let directory = workspace.appendingPathComponent(".claude", isDirectory: true)
        let file = directory.appendingPathComponent("settings.local.json")
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        var settings: [String: Any] = [:]
        if fileManager.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            if !data.isEmpty {
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                settings = object
            }
        }
        if settings["remoteControlAtStartup"] as? Bool != false {
            settings["remoteControlAtStartup"] = false
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: file, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
