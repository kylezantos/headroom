import Foundation

public enum CompanionDemoModeWriteResult: Equatable, Sendable {
    case changed
    case unchanged
    case unavailable
}

/// A deliberately tiny App Group preference shared by the iOS companion and widget.
/// Demo content itself remains an in-memory fixture and never enters the real snapshot
/// cache or iCloud publication path (KTD21, R30): snapshots and check-now receipts replay
/// bundled `CompanionDemoData`, and nothing here holds an iCloud store or a cache.
public struct CompanionDemoModeStore: @unchecked Sendable { // UserDefaults is thread-safe
    public static let defaultsKey = "companionDemoModeEnabled"
    public static let variantKey = "companionDemoVariant"
    /// KTD21: set by a `--demo` screenshot launch so the widget extension, which cannot see
    /// launch arguments, hides its DEMO badge too.
    public static let screenshotPresentationKey = "companionDemoScreenshotPresentation"

    private let defaults: UserDefaults?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    /// - Parameters:
    ///   - now: The demo clock. Snapshots, reset deadlines and receipt times derive from it.
    ///   - sleep: Paces the check-now replay; tests inject one that returns at once.
    public init(
        defaults: UserDefaults?,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
    }

    public static func appGroup() -> CompanionDemoModeStore {
        CompanionDemoModeStore(defaults: UserDefaults(suiteName: WidgetSnapshotCache.appGroupSuiteName))
    }

    public var isEnabled: Bool {
        defaults?.bool(forKey: Self.defaultsKey) ?? false
    }

    /// The stored variant token. Defaults to 'full' when unset; the build-33 envelopes
    /// resolve it through `DemoScreenshotData.envelope(for:)`, the v4 path through
    /// `selectedVariant`.
    public var variant: String {
        defaults?.string(forKey: Self.variantKey) ?? "full"
    }

    /// Explore Demo's v4 variant. An unset, legacy or unknown token is the default (U7).
    public var selectedVariant: CompanionDemoVariant {
        CompanionDemoVariant.resolving(defaults?.string(forKey: Self.variantKey))
    }

    public var isScreenshotPresentation: Bool {
        defaults?.bool(forKey: Self.screenshotPresentationKey) ?? false
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> CompanionDemoModeWriteResult {
        guard let defaults else { return .unavailable }
        guard isEnabled != enabled else { return .unchanged }

        if enabled {
            defaults.set(true, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        // WidgetKit may launch the extension immediately after the host requests a
        // timeline reload, so flush this one cross-process flag before that handoff.
        defaults.synchronize()
        return .changed
    }

    @discardableResult
    public func setVariant(_ variant: String) -> CompanionDemoModeWriteResult {
        guard let defaults else { return .unavailable }
        let currentVariant = self.variant
        guard currentVariant != variant else { return .unchanged }

        defaults.set(variant, forKey: Self.variantKey)
        defaults.synchronize()
        return .changed
    }

    @discardableResult
    public func setVariant(_ variant: CompanionDemoVariant) -> CompanionDemoModeWriteResult {
        setVariant(variant.rawValue)
    }

    @discardableResult
    public func setScreenshotPresentation(_ enabled: Bool) -> CompanionDemoModeWriteResult {
        guard let defaults else { return .unavailable }
        guard isScreenshotPresentation != enabled else { return .unchanged }
        if enabled {
            defaults.set(true, forKey: Self.screenshotPresentationKey)
        } else {
            defaults.removeObject(forKey: Self.screenshotPresentationKey)
        }
        defaults.synchronize()
        return .changed
    }

    // MARK: Bundled data (KTD21)

    /// Whether this process shows demo data: a `--demo` launch or Explore Demo's switch.
    public func isActive(launch: CompanionDemoLaunchOptions) -> Bool {
        launch.isDemoLaunch || isEnabled
    }

    /// The variant to show: `--demo-variant` wins over Explore Demo's stored choice.
    public func variant(launch: CompanionDemoLaunchOptions) -> CompanionDemoVariant {
        launch.resolvedVariant(stored: selectedVariant)
    }

    /// The demo snapshot at the store's clock, resolved through the real v4 codec and
    /// resolver. Reads and writes nothing outside memory.
    public func snapshot(_ variant: CompanionDemoVariant) -> CompanionResolvedSnapshot {
        CompanionDemoData.snapshot(variant, now: now())
    }

    /// The `demo` seam for `CompanionSnapshotLoader` (KTD21): while demo is active the loader
    /// returns bundled data and never reads iCloud or any cache.
    public func loaderSeam(launch: CompanionDemoLaunchOptions) -> @Sendable () -> CompanionResolvedSnapshot? {
        let store = self
        return { store.isActive(launch: launch) ? store.snapshot(store.variant(launch: launch)) : nil }
    }

    /// A demo pull (AE8): replays the bundled receipt sequence through `onStep`, paced by the
    /// injected sleep, and writes nothing — no request key, no receipt, no cache. The finished
    /// step carries the snapshot at its `finishedGeneration`. Returns false, replaying
    /// nothing, when the variant cannot check (KTD14.1) or the task was cancelled first.
    @discardableResult
    public func replayCheckNow(
        _ variant: CompanionDemoVariant,
        requestID: String = CompanionDemoData.requestID,
        onStep: @Sendable (CompanionDemoCheckNowStep) async -> Void
    ) async -> Bool {
        let steps = CompanionDemoData.checkNowSteps(variant, requestID: requestID, startedAt: now())
        guard !steps.isEmpty else { return false }
        for step in steps {
            await sleep(step.delay)
            guard !Task.isCancelled, let built = try? step.build(now()) else { return false }
            await onStep(built)
        }
        return true
    }
}
