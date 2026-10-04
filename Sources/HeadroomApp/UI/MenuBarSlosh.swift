import Foundation
import Observation
import HeadroomCore

/// KTD6/KTD13: records edges; a small view derives wave and first-reading ink from dates.
/// The native status label must stay one Image: a nested TimelineView causes MenuBarExtra
/// to continuously rasterize its label. Its existing small clock boundary remains here,
/// with wall-clock phase instead of tick counting and no task while still (KTD17).
@MainActor
@Observable
final class MenuBarSlosh {
    nonisolated static let frameCount = LoadingMotionConstants.sloshFrameCount

    enum MeterKey: Hashable { case provider(ProviderID), automatic }
    struct Presentation: Equatable {
        var ink: VesselGlyph.Ink = .solid
        var wavePhase: Int?
    }

    private(set) var frameDate = Date()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let autoTick: Bool

    init(autoTick: Bool = true) { self.autoTick = autoTick }
    deinit { ticker?.cancel() }

    private var updating: Set<ProviderID> = []
    private var endedAt: [ProviderID: Date] = [:]
    private var printStarts: [MeterKey: Date] = [:]
    private var reduceMotion = false
    @ObservationIgnored private var previous: [MeterKey: MenuBarMeter] = [:]
    @ObservationIgnored private var previousSources: [ProviderID: AccountKey] = [:]

    var isActive: Bool { !reduceMotion && !updating.isEmpty }
    var isClockRunning: Bool { ticker != nil }
    var deadline: Date? {
        let prints = printStarts.values.map { $0.addingTimeInterval(Self.printDuration) }
        let waves = reduceMotion ? [] : endedAt.values.map {
            Date(timeIntervalSince1970: floor($0.timeIntervalSince1970) + LoadingMotionConstants.sloshCycle)
        }
        return (prints + waves).max()
    }

    private static var printDuration: TimeInterval {
        Double(LoadingMotionConstants.menuBarPrintFrameCount) * LoadingMotionConstants.sloshFrameInterval
    }

    func update(meters: [MenuBarMeter], automatic: Bool, updating next: Set<ProviderID>,
                reduceMotion: Bool, sourceAccounts: [ProviderID: AccountKey] = [:],
                probeEndTimes: [ProviderID: Date] = [:], clockEnabled: Bool = true, at now: Date) {
        let changedSources = Set(meters.compactMap { meter -> ProviderID? in
            guard let provider = meter.summary.providerID,
                  let old = previous[Self.key(for: meter, automatic: automatic)],
                  old.sourceAccountKey != meter.sourceAccountKey else { return nil }
            return provider
        }).union(sourceAccounts.compactMap { provider, source in
            previousSources[provider].map { $0 != source ? provider : nil } ?? nil
        })
        let visible = automatic && meters.contains(where: \.awaitingFirstReading)
            ? next.union(updating).union(endedAt.keys) : Set(meters.compactMap { $0.summary.providerID })
        let next = next.intersection(visible)
        endedAt = endedAt.filter { visible.contains($0.key) && !changedSources.contains($0.key) }
        for provider in updating.subtracting(next) where visible.contains(provider) && !changedSources.contains(provider) {
            endedAt[provider] = probeEndTimes[provider] ?? now
        }
        for provider in next { endedAt.removeValue(forKey: provider) }
        updating = next
        self.reduceMotion = reduceMotion
        var observations: [MeterKey: MenuBarMeter] = [:]
        for meter in meters {
            let key = Self.key(for: meter, automatic: automatic)
            observations[key] = meter
            if let old = previous[key] {
                let sameSource = automatic ? previousSources == sourceAccounts
                    : old.sourceAccountKey == meter.sourceAccountKey
                if !sameSource || meter.awaitingFirstReading {
                    printStarts.removeValue(forKey: key)
                } else if old.awaitingFirstReading, !meter.awaitingFirstReading, meter.isLiveReading {
                    printStarts[key] = now
                }
            }
        }
        printStarts = printStarts.filter { observations[$0.key] != nil && now < $0.value.addingTimeInterval(Self.printDuration) }
        previous = observations
        previousSources = sourceAccounts
        frameDate = now
        if autoTick && clockEnabled { startIfNeeded(at: now) } else { suspend() }
    }

    func suspend() {
        ticker?.cancel()
        ticker = nil
    }

    private func needsClock(at date: Date) -> Bool {
        isActive || deadline.map { date < $0 } == true
    }

    private func startIfNeeded(at date: Date) {
        guard needsClock(at: date) else { suspend(); return }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(LoadingMotionConstants.sloshFrameInterval)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                self.frameDate = now
                if !self.needsClock(at: now) {
                    self.ticker = nil
                    return
                }
            }
        }
    }

    func presentation(for meter: MenuBarMeter, automatic: Bool, at now: Date) -> Presentation {
        var result = Self.staticPresentation(for: meter)
        if let start = printStarts[Self.key(for: meter, automatic: automatic)] {
            let elapsed = now.timeIntervalSince(start)
            if elapsed >= 0, elapsed < Self.printDuration {
                let frame = min(LoadingMotionConstants.menuBarPrintFrameCount - 1,
                                Int(floor((elapsed + 0.000001) / LoadingMotionConstants.sloshFrameInterval)))
                result.ink = reduceMotion ? .crossfade(frame: frame) : .printing(frame: frame)
            }
        }
        let providers: Set<ProviderID> = automatic && meter.awaitingFirstReading
            ? updating.union(endedAt.keys)
            : Set(meter.summary.providerID.map { [$0] } ?? [])
        if providers.contains(where: { LoadingMotionClock.isSloshing(active: updating.contains($0),
                                endedAt: endedAt[$0], now: now, reduceMotion: reduceMotion) }) {
            result.wavePhase = LoadingMotionClock.sloshPhase(at: now)
        }
        return result
    }

    static func staticPresentation(for meter: MenuBarMeter) -> Presentation {
        Presentation(ink: meter.awaitingFirstReading ? .ghost : .solid)
    }

    static func key(for meter: MenuBarMeter, automatic: Bool) -> MeterKey {
        automatic ? .automatic : meter.summary.providerID.map(MeterKey.provider) ?? .automatic
    }
}
