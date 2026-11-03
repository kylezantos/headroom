import Foundation

/// Turns the Mac's current state into the feedback email's diagnostics (2026-11-03 feedback
/// plan, R4). It reads each account's freshness and nothing else from its snapshot: never
/// `accountEmail`, `planLabel`, account labels or `AccountKey.description`.
public enum FeedbackDiagnosticsCollector {
    public struct Platform: Sendable, Equatable {
        public let appVersion: String?
        public let operatingSystem: String
        public let architecture: String?

        public init(appVersion: String?, operatingSystem: String, architecture: String?) {
            self.appVersion = appVersion
            self.operatingSystem = operatingSystem
            self.architecture = architecture
        }

        public static func current(appVersion: String?) -> Platform {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let version = os.patchVersion == 0
                ? "\(os.majorVersion).\(os.minorVersion)"
                : "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            return Platform(appVersion: appVersion, operatingSystem: "macOS \(version)", architecture: architecture)
        }
    }

    /// `registered` is every composed provider in display order; `enabled` is the subset the
    /// user has switched on. Off providers are named once and list no accounts.
    public static func diagnostics(
        platform: Platform,
        cliVersions: [FeedbackDiagnostics.CLI],
        registered: [ProviderID],
        enabled: [ProviderID],
        accounts: (ProviderID) -> [AccountKey],
        freshness: (AccountKey) -> Freshness
    ) -> FeedbackDiagnostics {
        let enabledSet = Set(enabled)
        let accountLines = registered.filter(enabledSet.contains).flatMap { providerID in
            accounts(providerID).enumerated().map { offset, key in
                FeedbackDiagnostics.Account(
                    providerID: providerID,
                    position: offset + 1,
                    status: FeedbackAccountStatus(freshness: freshness(key))
                )
            }
        }
        return FeedbackDiagnostics(
            appVersion: platform.appVersion,
            operatingSystem: platform.operatingSystem,
            architecture: platform.architecture,
            cliVersions: cliVersions,
            providersOff: registered.filter { !enabledSet.contains($0) },
            accounts: accountLines
        )
    }

    @MainActor
    public static func diagnostics(
        store: UsageStore,
        platform: Platform,
        cliVersions: [FeedbackDiagnostics.CLI]
    ) -> FeedbackDiagnostics {
        diagnostics(
            platform: platform,
            cliVersions: cliVersions,
            registered: store.registeredProviderOrder,
            enabled: store.providerOrder,
            accounts: { store.accounts(for: $0).map(\.key) },
            freshness: { store.snapshot(for: $0).freshness }
        )
    }
}
