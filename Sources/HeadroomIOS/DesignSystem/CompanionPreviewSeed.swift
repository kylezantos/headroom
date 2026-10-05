#if DEBUG
import Foundation

/// DEBUG-only sample content so the companion can be driven in the Simulator without a
/// Mac syncing over iCloud. Enabled by launching with the `HEADROOM_PREVIEW=1`
/// environment variable (set in the scheme or via `simctl launch`). Never ships — the
/// whole file is compiled out of Release.
///
/// The numbers are the v4 multi-account demo (`CompanionDemoData`), held to the Mac's
/// `DemoFixture` by `DemoScenarioParityTests`, so the menu-bar popover, the macOS widgets,
/// and the iPhone all show the same moment. Unlike `--demo`, this path renders as ordinary *synced* content:
/// no Demo Mode banner, and Settings reports `Source: Mac snapshot`. That is what the
/// portfolio case-study phone pair needs — it illustrates the Mac→iPhone mirror, so a
/// "sample data / no accounts connected" banner would contradict the story it is proving.
/// See `Scripts/capture-case-study-shots.sh`.
enum CompanionPreviewSeed {
    enum UITestState: String {
        case waiting
        case content
        case stale
        /// U10: a corrupt v3 key and nothing cached, through the real resolver.
        case unreadable
    }

    /// Screen the preview harness should open on launch (`HEADROOM_PREVIEW_SCREEN`).
    /// Lets the capture script shoot the Settings sheet headlessly, with no UI automation.
    enum PreviewScreen: String {
        case settings
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HEADROOM_PREVIEW"] == "1"
    }

    static var previewScreen: PreviewScreen? {
        ProcessInfo.processInfo.environment["HEADROOM_PREVIEW_SCREEN"].flatMap(PreviewScreen.init(rawValue:))
    }

    static var uiTestState: UITestState? {
        ProcessInfo.processInfo.environment["HEADROOM_UI_TEST_STATE"].flatMap(UITestState.init(rawValue:))
    }

    /// U10: poses a status screen no fixture reaches (iCloud unavailable, either update
    /// screen) over a non-content state, for captures and UI tests. Raw values are
    /// `CompanionStatusScreen`'s. Unreadable has a real route: `HEADROOM_UI_TEST_STATE=unreadable`.
    static var uiTestStatus: CompanionStatusScreen? {
        ProcessInfo.processInfo.environment["HEADROOM_UI_TEST_STATUS"].flatMap(CompanionStatusScreen.init(rawValue:))
    }

    static var shouldResetDemoForUITest: Bool {
        ProcessInfo.processInfo.environment["HEADROOM_UI_TEST_RESET_DEMO"] == "1"
    }

    /// The preview's v4 moment: the multi-account demo variant, resolved through the real
    /// codec and resolver in memory (KTD21). Nothing here reads or writes iCloud or a cache.
    static func snapshot(now: Date = Date()) -> CompanionResolvedSnapshot {
        CompanionDemoData.snapshot(.multiAccount, now: now)
    }

    /// The build-33 view of the same moment: main accounts only (KTD13), so the preview's
    /// numbers, Fable included, are the demo's and the Mac's.
    static func envelope(now: Date = Date()) -> WidgetSnapshotEnvelope {
        snapshot(now: now).primaryProjection()
            ?? WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [], apiSpendProviders: [])
    }

    /// KTD21: the preview seed writes only the demo cache, never v4 into the real cache.
    /// The widget gallery renders the same moment by reading the App Group demo switch,
    /// variant and screenshot presentation (no DEMO badge); `WidgetSnapshotCache`, the v4
    /// `CompanionSnapshotCache` and iCloud are never touched.
    static func seedDemoCache(_ store: CompanionDemoModeStore = .appGroup()) {
        store.setVariant(.multiAccount)
        store.setScreenshotPresentation(true)
        store.setEnabled(true)
    }

    /// U10: what the phone resolves when the Mac's v3 key is present but undecodable and no
    /// v4 or cache stands in. The resolver decides the state, not a posed screen.
    static func unreadableSnapshot(now: Date = Date()) -> CompanionResolvedSnapshot {
        CompanionSnapshotResolver.resolve(
            CompanionResolverInput(manifest: nil, v3: Data("{".utf8), cache: .empty, now: now)
        ).snapshot
    }

    static func envelope(for state: UITestState, now: Date = Date()) -> WidgetSnapshotEnvelope? {
        switch state {
        case .waiting, .unreadable:
            return nil
        case .content:
            return envelope(now: now)
        case .stale:
            let content = envelope(now: now)
            return WidgetSnapshotEnvelope(
                generatedAt: content.generatedAt,
                status: content.status,
                providers: content.providers.map { provider in
                    WidgetProviderSummary(
                        id: provider.id,
                        displayName: provider.displayName,
                        planLabel: provider.planLabel,
                        freshness: .stale(message: "Using last snapshot", needsAttention: false),
                        windows: provider.windows,
                        renewalDate: provider.renewalDate
                    )
                },
                apiSpendProviders: content.apiSpendProviders
            )
        }
    }
}
#endif
