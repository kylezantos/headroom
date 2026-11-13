import Foundation
import Testing
@testable import HeadroomCore

@Suite struct AccountStorageLifecycleTests {
    @Test func additionalAccountDirectoriesAreOwnerOnlyAndRemovalIsExact() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = ProviderAccount(id: AccountID("selected"), providerID: .claude, label: "Selected")
        let sibling = ProviderAccount(id: AccountID("sibling"), providerID: .claude, label: "Sibling")

        let selectedURL = try AccountStorage.ensureDirectories(for: selected, baseDirectoryURL: root)
        let siblingURL = try AccountStorage.ensureDirectories(for: sibling, baseDirectoryURL: root)
        for url in [selectedURL,
                    selectedURL.appendingPathComponent("config"),
                    selectedURL.appendingPathComponent("workspace")] {
            let mode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            #expect(mode.intValue & 0o077 == 0)
        }

        try AccountStorage.removeDirectories(for: selected, baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: selectedURL.path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    @Test func missingDirectoryCountsAsAlreadyRemovedAndBuiltInIsNeverTouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try AccountStorage.removeDirectories(
            for: ProviderAccount(id: AccountID("missing"), providerID: .codex, label: "Missing"),
            baseDirectoryURL: root
        )
        try AccountStorage.removeDirectories(for: .builtIn(for: .codex), baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func grokRemovalDeletesOnlyTheRequestedIsolatedHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-grok-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = ProviderAccount(id: AccountID("selected"), providerID: .grok, label: "Selected")
        let sibling = ProviderAccount(id: AccountID("sibling"), providerID: .grok, label: "Sibling")
        let selectedURL = try AccountStorage.ensureDirectories(for: selected, baseDirectoryURL: root)
        let siblingURL = try AccountStorage.ensureDirectories(for: sibling, baseDirectoryURL: root)

        #expect(selectedURL.path.hasSuffix("/grok/selected"))
        #expect(siblingURL.path.hasSuffix("/grok/sibling"))
        try AccountStorage.removeDirectories(for: selected, baseDirectoryURL: root)

        #expect(!FileManager.default.fileExists(atPath: selectedURL.path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    @Test func openCodeExtraGetsFourOwnerOnlyXDGFoldersAndRemovalIsExact() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-opencode-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = ProviderAccount(id: AccountID("selected"), providerID: .opencode, label: "Selected")
        let sibling = ProviderAccount(id: AccountID("sibling"), providerID: .opencode, label: "Sibling")
        let selectedURL = try AccountStorage.ensureDirectories(for: selected, baseDirectoryURL: root)
        let siblingURL = try AccountStorage.ensureDirectories(for: sibling, baseDirectoryURL: root)

        #expect(selectedURL.path.hasSuffix("/opencode/selected"))
        for name in ["data", "config", "cache", "state"] {
            let url = selectedURL.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue, "\(name)")
            let mode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
            #expect(mode.intValue & 0o077 == 0, "\(name)")
        }
        #expect(AccountStorage.opencodeAccountHome(for: selected, baseDirectoryURL: root) == .isolated(root: selectedURL.path))
        #expect(AccountStorage.opencodeAccountHome(for: .builtIn(for: .opencode), baseDirectoryURL: root) == .builtIn)

        try AccountStorage.removeDirectories(for: selected, baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: selectedURL.path))
        #expect(FileManager.default.fileExists(atPath: siblingURL.appendingPathComponent("state").path))
    }

    @Test func openCodeRemovalIsRefusedWhileAHandoffIsActive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-opencode-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = ProviderAccount(id: AccountID("selected"), providerID: .opencode, label: "Selected")
        let accountURL = try AccountStorage.ensureDirectories(for: account, baseDirectoryURL: root)
        let marker = SetupCompletionMarker(
            pendingPath: accountURL.appendingPathComponent(".headroom-setup-pending").path,
            completedPath: accountURL.appendingPathComponent(".headroom-setup-complete").path
        )
        _ = try AccountStorage.prepareSetupCompletionMarker(marker)
        #expect(throws: (any Error).self) {
            try AccountStorage.removeDirectories(for: account, baseDirectoryURL: root)
        }
        #expect(FileManager.default.fileExists(atPath: accountURL.appendingPathComponent("data").path))

        AccountStorage.clearSetupCompletionMarkers(marker)
        try AccountStorage.removeDirectories(for: account, baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: accountURL.path))
    }

    @Test func credentialPermissionCheckRejectsGroupOrWorldReadableFiles() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("sentinel".utf8).write(to: file)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(AccountStorage.credentialFilePermissionsAreSafe(at: file))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(!AccountStorage.credentialFilePermissionsAreSafe(at: file))
    }

    @Test func activeSetupMarkerBlocksRemovalAndDeadProcessMarkerRecovers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = ProviderAccount(id: AccountID("selected"), providerID: .codex, label: "Selected")
        let accountURL = try AccountStorage.ensureDirectories(for: account, baseDirectoryURL: root)
        let marker = SetupCompletionMarker(
            pendingPath: accountURL.appendingPathComponent(".headroom-setup-pending").path,
            completedPath: accountURL.appendingPathComponent(".headroom-setup-complete").path
        )
        let generation = try AccountStorage.prepareSetupCompletionMarker(marker)
        #expect(AccountStorage.setupHandoffIsActive(marker: marker))
        #expect(throws: (any Error).self) {
            try AccountStorage.removeDirectories(for: account, baseDirectoryURL: root)
        }

        try Data("setup:standard:\(generation):2147483647\n".utf8).write(
            to: URL(fileURLWithPath: AccountStorage.generatedPendingPath(
                marker,
                generation: generation
            ))
        )
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
        try AccountStorage.removeDirectories(for: account, baseDirectoryURL: root)
        #expect(!FileManager.default.fileExists(atPath: accountURL.path))
    }

    @Test func abandonedOpeningMarkerExpiresWithoutWeakeningUnknownMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let startedAt = Date(timeIntervalSince1970: 1_000)
        try Data("opening:\(startedAt.timeIntervalSince1970)\n".utf8)
            .write(to: URL(fileURLWithPath: marker.pendingPath))

        #expect(AccountStorage.setupHandoffIsActive(
            marker: marker,
            now: startedAt.addingTimeInterval(AccountStorage.preparedMarkerGracePeriod - 1)
        ))
        #expect(!AccountStorage.setupHandoffIsActive(
            marker: marker,
            now: startedAt.addingTimeInterval(AccountStorage.preparedMarkerGracePeriod + 1)
        ))
        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))

        try Data("unrecognized\n".utf8).write(to: URL(fileURLWithPath: marker.pendingPath))
        #expect(AccountStorage.setupHandoffIsActive(
            marker: marker,
            now: startedAt.addingTimeInterval(86_400)
        ))
    }

    @Test func pendingMarkerRestoresExplicitDeviceCodeMode() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-mode-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let marker = SetupCompletionMarker(
            pendingPath: file.path,
            completedPath: file.path + "-complete"
        )

        try Data("deviceCode:2147483647\n".utf8).write(to: file)
        #expect(AccountStorage.setupHandoffMode(marker: marker) == .deviceCode)
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
    }

    @Test func resetPurposeAndModeSurviveTheOpeningGapAndActiveMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-reset-purpose-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )

        let generation = try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .deviceCode,
            purpose: .reset
        )

        #expect(AccountStorage.setupHandoffIsActive(marker: marker))
        #expect(AccountStorage.setupHandoffMode(marker: marker) == .deviceCode)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)

        try Data("reset:deviceCode:\(generation):2147483647\n".utf8)
            .write(to: URL(fileURLWithPath: AccountStorage.generatedPendingPath(
                marker,
                generation: generation
            )))
        #expect(AccountStorage.setupHandoffMode(marker: marker) == .deviceCode)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
    }

    /// Regression (code-review finding): built-in setup markers live in the shared
    /// `Setup/` directory beside the built-in Claude workspace — not under the
    /// per-account `Accounts/<provider>/<id>/` tree. The removal gate's storage check
    /// must resolve that real location, or stop-tracking a built-in account detaches
    /// the row while its Terminal handoff is still open.
    @Test func builtInSetupMarkerAtSharedSetupDirectoryBlocksStopTracking() async throws {
        let supportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-builtin-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportRoot) }
        let workspace = supportRoot.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let account = ProviderAccount.builtIn(for: .claude)

        let marker = AccountStorage.setupCompletionMarker(
            for: account, builtInClaudeWorkspace: workspace
        )
        #expect(marker.pendingPath == supportRoot
            .appendingPathComponent("Setup", isDirectory: true)
            .appendingPathComponent(".headroom-claude-setup-pending").path)

        try AccountStorage.prepareSetupCompletionMarker(marker)
        #expect(AccountStorage.setupHandoffIsActive(
            for: account, builtInClaudeWorkspace: workspace
        ))
        let storage = DefaultAccountStorage(builtInClaudeWorkspace: workspace)
        let activeWhileMarkerPresent = await storage.setupHandoffIsActive(for: account)
        #expect(activeWhileMarkerPresent)

        AccountStorage.clearPreparedSetupCompletionMarker(marker)
        let activeAfterClear = await storage.setupHandoffIsActive(for: account)
        #expect(!activeAfterClear)
    }

    @Test func extraAccountSetupMarkerStaysInsideItsConfigHome() {
        let extra = ProviderAccount(id: AccountID("extra"), providerID: .claude, label: "Extra")
        let marker = AccountStorage.setupCompletionMarker(
            for: extra,
            builtInClaudeWorkspace: URL(fileURLWithPath: "/nonexistent/ClaudeProbe")
        )
        let home = AccountStorage.accountDirectoryURL(for: extra)
        #expect(marker.pendingPath == home.appendingPathComponent(".headroom-setup-pending").path)
        #expect(marker.completedPath == home.appendingPathComponent(".headroom-setup-complete").path)
    }

    @Test func completionMarkerClassifiesOnlyRedactionSafeExitStatus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-completion-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let completedURL = URL(fileURLWithPath: marker.completedPath)

        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        try Data("complete:0\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .succeeded)
        try Data("complete:130\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .failed)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .setup)
        try Data("complete:reset:0\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .succeeded)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)
        try Data("complete:unknown:0\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == nil)
        try Data("complete:reset:256\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        try Data("complete:reset:+1\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        try Data("provider output must not be parsed\n".utf8).write(to: completedURL)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
    }

    @Test func forceCancelMarkerCleanupRemovesPendingAndCompletedFilesAndIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-force-cancel-marker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        try Data("standard:2147483647\n".utf8).write(to: URL(fileURLWithPath: marker.pendingPath))
        try Data("complete:0\n".utf8).write(to: URL(fileURLWithPath: marker.completedPath))

        AccountStorage.clearSetupCompletionMarkers(marker)
        AccountStorage.clearSetupCompletionMarkers(marker)

        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))
        #expect(!FileManager.default.fileExists(atPath: marker.completedPath))
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
        #expect(!AccountStorage.setupHandoffIsActive(marker: marker))
    }

    @Test func cancelledGenerationCannotOverwriteOrDeleteImmediateSuccessorMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-force-cancel-wrapper-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let cancelledGeneration = try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .standard,
            purpose: .setup
        )
        let acceptedOwner = try String(
            contentsOfFile: AccountStorage.generatedPendingPath(
                marker,
                generation: cancelledGeneration
            ),
            encoding: .utf8
        )
        #expect(!acceptedOwner.isEmpty)

        AccountStorage.clearSetupCompletionMarkers(marker)
        let successorGeneration = try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .deviceCode,
            purpose: .reset
        )
        #expect(successorGeneration != cancelledGeneration)

        // Model the cancelled wrapper's already-authorized EXIT work. Its unique
        // generation paths cannot overwrite or remove the successor's markers.
        try Data("complete:setup:\(cancelledGeneration):0\n".utf8).write(
            to: URL(fileURLWithPath: AccountStorage.generatedCompletedPath(
                marker,
                generation: cancelledGeneration
            ))
        )
        try? FileManager.default.removeItem(
            atPath: AccountStorage.generatedPendingPath(
                marker,
                generation: cancelledGeneration
            )
        )

        #expect(AccountStorage.setupHandoffGeneration(marker: marker) == successorGeneration)
        #expect(AccountStorage.setupHandoffIsActive(marker: marker))
        #expect(AccountStorage.setupHandoffMode(marker: marker) == .deviceCode)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .unknown)
    }
}
