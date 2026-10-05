import Foundation
import HeadroomCore

struct DemoCodexAuthReader: CodexAuthReading {
    func readCodexCredential() throws -> CodexCredential { throw CredentialError.notLoggedIn }
}

final class DemoLaunchAtLogin: LaunchAtLoginControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    var isEnabled: Bool { lock.withLock { enabled } }
    func setEnabled(_ enabled: Bool) throws { lock.withLock { self.enabled = enabled } }
}

extension AppComposition {
    static func makeSettingsCredentialStore(isDemo: Bool,
        codexReader: (any CodexAuthReading)? = nil, apiKeyStore: (any APIKeyStoring)? = nil) -> CredentialStore {
        if isDemo { return CredentialStore(codexReader: DemoCodexAuthReader(), apiKeyStore: DemoAPIKeyStore()) }
        return CredentialStore(codexReader: codexReader ?? CodexAuthFileReader(), apiKeyStore: apiKeyStore ?? KeychainAPIKeyStore())
    }

    static func makeSettingsDuplicateDetector(isDemo: Bool,
        readAccountUUID: @escaping @Sendable (AccountID) -> String? = {
            ClaudeAccountEmailFileReader.forAccount($0).readAccountUUID()
        }) -> ClaudeDuplicateLoginDetector {
        if isDemo { return ClaudeDuplicateLoginDetector(readAccountUUID: { _ in nil }) }
        return ClaudeDuplicateLoginDetector(readAccountUUID: readAccountUUID)
    }

    static let settingsDuplicateDetector = makeSettingsDuplicateDetector(isDemo: DemoFixture.isEnabled)
    static let settingsLaunchControl: any LaunchAtLoginControlling = DemoFixture.isEnabled ? DemoLaunchAtLogin() : LaunchAtLogin()
}
