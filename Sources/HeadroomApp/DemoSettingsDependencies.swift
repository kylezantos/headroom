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
        readIdentity: @escaping @Sendable (AccountID) -> AccountIdentity? = {
            ClaudeAccountEmailFileReader.forAccount($0).readAccountIdentity().identity
        }) -> ClaudeDuplicateLoginDetector {
        if isDemo { return ClaudeDuplicateLoginDetector(readIdentity: { _ in nil }) }
        return ClaudeDuplicateLoginDetector(readIdentity: readIdentity)
    }

    /// Default-login plan U11: like the duplicate detector, a demo or hosted-test launch
    /// gets an in-memory record store and never reads or writes `defaultLoginRecords.v1`.
    static func makeDefaultLoginRecordStore(isDemo: Bool,
        defaults: UserDefaults = launchDefaults) -> any DefaultLoginRecordStoring {
        if isDemo { return DemoDefaultLoginRecordStore() }
        return DefaultLoginRecordStore(defaults: defaults)
    }

    static let settingsDuplicateDetector = makeSettingsDuplicateDetector(isDemo: DemoFixture.isEnabled)
    static let settingsLaunchControl: any LaunchAtLoginControlling = DemoFixture.isEnabled ? DemoLaunchAtLogin() : LaunchAtLogin()
}
