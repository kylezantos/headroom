import Foundation
import Observation
import HeadroomCore

/// Round-3 S2 (Oct 2026, design/refresh-stamp-merge-round3.html): the frame clock behind the
/// menu-bar slosh. A pill's liquid surface travels while its provider's main account is being
/// checked, timer polls included, and goes flat when the check ends. The motion is bound to
/// that work: it is a travelling surface, never a pulse, and nothing runs while no account is
/// being checked.
///
/// A pill whose check ends finishes the wave it is on before going flat, so the surface never
/// snaps mid-cycle (the same rule as the popover's loops). Reduce Motion keeps every pill flat.
@MainActor
@Observable
final class MenuBarSlosh {
    /// Frames per wavelength. At `frameInterval` the wave crosses the vessel once a second.
    nonisolated static let frameCount = 10
    /// 10fps: the label is one rasterized image, so each frame is a cached `NSImage` swap.
    static let frameInterval: Duration = .milliseconds(100)

    private(set) var phase = 0
    private(set) var sloshing: Set<ProviderID> = []
    @ObservationIgnored private var requested: Set<ProviderID> = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let autoTick: Bool

    /// `autoTick: false` lets tests step frames with `advance()` instead of a timer.
    init(autoTick: Bool = true) {
        self.autoTick = autoTick
    }

    /// The pills whose wave frame is `phase`; every other pill renders flat.
    var phases: [ProviderID: Int] {
        Dictionary(uniqueKeysWithValues: sloshing.map { ($0, phase) })
    }

    func update(_ updating: Set<ProviderID>, reduceMotion: Bool) {
        guard !reduceMotion else {
            requested = []
            if !sloshing.isEmpty { sloshing = [] }
            stop()
            return
        }
        requested = updating
        let next = sloshing.union(updating)
        if next != sloshing { sloshing = next }
        if !sloshing.isEmpty, autoTick, ticker == nil { start() }
    }

    /// One frame. Pills no longer being checked drop out only as the wave wraps.
    func advance() {
        phase = (phase + 1) % Self.frameCount
        if phase == 0 {
            let kept = sloshing.intersection(requested)
            if kept != sloshing { sloshing = kept }
        }
        if sloshing.isEmpty { stop() }
    }

    private func start() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                guard let self, !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    private func stop() {
        ticker?.cancel()
        ticker = nil
        if phase != 0 { phase = 0 }
    }
}
