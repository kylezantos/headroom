#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

private struct LoadingDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

public extension EnvironmentValues {
    /// Loading-language KTD16: render harnesses freeze every loading surface together.
    var loadingDate: Date? {
        get { self[LoadingDateKey.self] }
        set { self[LoadingDateKey.self] = newValue }
    }
}

/// KTD17: only this small boundary redraws. A one-shot expiry pauses the schedule after
/// finish-the-wave or print travel; no parent receives per-frame state writes.
public struct LoadingTimeline<Content: View>: View {
    private let active: Bool
    private let until: Date?
    private let interval: TimeInterval
    private let content: (Date) -> Content
    @Environment(\.loadingDate) private var pinnedDate
    @State private var expired: Date?

    public init(active: Bool, until: Date? = nil, interval: TimeInterval = LoadingMotionConstants.sloshFrameInterval,
                @ViewBuilder content: @escaping (Date) -> Content) {
        self.active = active
        self.until = until
        self.interval = interval
        self.content = content
    }

    nonisolated public static func isPaused(active: Bool, until: Date?, now: Date, pinned: Bool) -> Bool {
        pinned || (!active && (until.map { $0 <= now } ?? true))
    }

    public var body: some View {
        let now = pinnedDate ?? Date()
        let paused = Self.isPaused(active: active, until: until, now: now, pinned: pinnedDate != nil)
            || (!active && expired == until)
        TimelineView(.animation(minimumInterval: interval, paused: paused)) { context in
            content(pinnedDate ?? context.date)
        }
        .task(id: until) {
            expired = nil
            guard pinnedDate == nil, let until else { return }
            let delay = max(0, until.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            expired = until
        }
    }
}
