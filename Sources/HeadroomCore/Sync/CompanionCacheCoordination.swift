import Foundation

/// The one cross-process transaction anchor for every companion cache reader, writer and
/// invalidation (KTD6.8). An in-process actor and atomic file replacement alone do not
/// serialize the app, the widget extension, Siri and Control, so every access to the
/// sidecar, the v4 cache and `widget-snapshot.json` runs inside `coordinate`.
public protocol CompanionCacheCoordinating: Sendable {
    /// Runs `body` exclusively against the anchor. Returns nil when coordination fails;
    /// callers then serve no cached account content rather than reading uncoordinated.
    func coordinate<T>(_ body: () -> T) -> T?
}

/// Production anchor: an `NSFileCoordinator` write claim on one App Group file, taken for
/// reads too, because any read may create first-seen times or invalidate.
public struct CompanionFileCacheCoordinator: CompanionCacheCoordinating {
    public static let anchorFileName = "companion-cache.anchor"
    public let anchor: URL

    public init(anchor: URL) {
        self.anchor = anchor
    }

    public init?(appGroupIdentifier: String = WidgetSnapshotCache.appGroupSuiteName) {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else { return nil }
        self.init(anchor: container.appendingPathComponent(Self.anchorFileName))
    }

    public func coordinate<T>(_ body: () -> T) -> T? {
        var error: NSError?
        var result: T?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: anchor, options: [], error: &error
        ) { _ in
            result = body()
        }
        return error == nil ? result : nil
    }
}
