#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// KTD7: persistent dot ink for cards, the Reprint row and phone placeholders.
public struct HalftoneVesselView: View {
    private let state: LoadingPillState
    private let motion: LoadingMotion
    private let size: CGSize
    private let columns: Int
    private let rows: Int
    private let sloshEndedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @HeadroomWidgetRendering private var rendering

    public init(state: LoadingPillState, motion: LoadingMotion = .still,
                width: CGFloat = 14, height: CGFloat = 22, columns: Int = 5, rows: Int = 10,
                sloshEndedAt: Date? = nil) {
        self.state = state
        self.motion = motion
        size = CGSize(width: width, height: height)
        self.columns = columns
        self.rows = rows
        self.sloshEndedAt = sloshEndedAt
    }

    public var body: some View {
        LoadingTimeline(active: !reduceMotion && (state.isSloshing || motion != .still),
                        until: reduceMotion ? nil : sloshEndedAt.map(Self.waveEnd),
                        interval: motion == .drip ? 1 / 30 : LoadingMotionConstants.sloshFrameInterval) { date in
            Canvas { context, bounds in
                let wall = Path(roundedRect: CGRect(origin: .zero, size: bounds).insetBy(dx: 0.6, dy: 0.6),
                                cornerRadius: bounds.width / 2)
                context.stroke(wall, with: .foreground, lineWidth: 1.2)
                if rendering != .monochrome { drawInk(context: context, bounds: bounds, date: date) }
            }
        }
        .frame(width: size.width, height: size.height)
        .headroomWidgetProbe()
        .accessibilityHidden(true)
    }

    private static func waveEnd(_ end: Date) -> Date {
        Date(timeIntervalSince1970: floor(end.timeIntervalSince1970) + LoadingMotionConstants.sloshCycle)
    }

    private func drawInk(context: GraphicsContext, bounds: CGSize, date: Date) {
        let geometry = HalftoneGeometry(width: bounds.width, height: bounds.height, columns: columns, rows: rows)
        var field = context
        let inner = CGRect(origin: .zero, size: bounds).insetBy(dx: geometry.inset, dy: geometry.inset)
        field.clip(to: Path(roundedRect: inner, cornerRadius: inner.width / 2))
        let dripping = motion == .drip
        let level = dripping ? 0 : state.level
        let sloshing = LoadingMotionClock.isSloshing(active: state.isSloshing || motion == .slosh,
                                                    endedAt: sloshEndedAt, now: date, reduceMotion: reduceMotion)
        let phase = Double(LoadingMotionClock.sloshPhase(at: date)) / Double(LoadingMotionConstants.sloshFrameCount)
        let cycle = date.timeIntervalSince1970.truncatingRemainder(dividingBy: LoadingMotionConstants.dripCycle)
        let fall = max(0, cycle) / LoadingMotionConstants.dripFall
        let inkMode: LoadingInk
        switch (reduceMotion, state.ink) {
        case (true, .ghostWipe(let progress)): inkMode = .crossfade(progress: 1 - progress)
        case (true, .printing(let progress)): inkMode = .crossfade(progress: progress)
        default: inkMode = state.ink
        }
        for dot in geometry.dots {
            let x = (dot.x - inner.minX) / inner.width
            let y = (dot.y - inner.minY) / inner.height
            let surface = 1 - level + (sloshing ? 0.055 * sin(2 * .pi * (x - phase)) : 0)
            var wet = min(1, max(0, (y - surface) * Double(rows) + 0.5))
            if dripping && !reduceMotion {
                if fall < 1 {
                    let dropY = 0.2 + 0.6 * fall * fall
                    wet = max(wet, max(0, 1 - hypot((x - 0.5) * 2.5, (y - dropY) * 5)))
                } else if cycle < LoadingMotionConstants.dripFall + LoadingMotionConstants.dripRipple {
                    let ripple = (cycle - LoadingMotionConstants.dripFall) / LoadingMotionConstants.dripRipple
                    let ring = abs(abs(x - 0.5) - ripple * 0.4)
                    wet = max(wet, max(0, 1 - ring * 18) * max(0, 1 - abs(y - 0.85) * 12) * (1 - ripple))
                }
            }
            let multiplier = inkMode.coverage(at: y)
            let coverage = HalftoneGeometry.emptyCoverage + (1 - HalftoneGeometry.emptyCoverage) * wet * multiplier
            let radius = geometry.radius(coverage: coverage)
            let circle = Path(ellipseIn: CGRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius))
            var ink = field
            ink.opacity = HalftoneGeometry.inkOpacity(coverage: coverage)
            ink.fill(circle, with: .foreground)
        }
    }
}
