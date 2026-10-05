import SwiftUI
import HeadroomCore
#if canImport(HeadroomWidgetSharedUI)
import HeadroomWidgetSharedUI
#endif

/// R8/KTD10: neutral vector vessel at the row's 7×11 optical size.
struct MiniPill: View, @preconcurrency Animatable {
    enum Mode: Sendable, Equatable {
        case still
        case slosh
        case drip
        case drain(progress: Double)
    }

    var mode: Mode = .still
    var level: Double = LoadingMotionConstants.decorativeLevel
    var sloshEndedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var animatableData: Double {
        get { if case .drain(let progress) = mode { return progress }; return 0 }
        set { if case .drain = mode { mode = .drain(progress: newValue) } }
    }

    var body: some View {
        LoadingTimeline(active: !reduceMotion && (mode == .slosh || mode == .drip),
                        until: reduceMotion ? nil : sloshEndedAt.map { Date(timeIntervalSince1970: floor($0.timeIntervalSince1970) + 1) },
                        interval: mode == .drip ? 1 / 30 : LoadingMotionConstants.sloshFrameInterval) { date in
            Canvas { context, _ in
                let pose = MiniPillPose(mode: mode, level: level, date: date, reduceMotion: reduceMotion,
                                        sloshEndedAt: sloshEndedAt)
                let wall = Path(roundedRect: MiniPillPose.wall, cornerRadius: MiniPillPose.wall.width / 2)
                context.stroke(wall, with: .foreground, lineWidth: MiniPillPose.lineWidth)
                var liquid = context
                liquid.clip(to: Path(roundedRect: MiniPillPose.inner, cornerRadius: MiniPillPose.inner.width / 2))
                liquid.opacity = 0.72 // Neutral liquid stays below the wall ink, like VesselGlyph.
                liquid.fill(pose.liquidPath, with: .foreground)
                if let drop = pose.drop {
                    context.fill(Path(ellipseIn: drop), with: .foreground)
                }
                if let ripple = pose.ripple {
                    var rippleInk = context
                    rippleInk.opacity = pose.rippleOpacity
                    rippleInk.stroke(Path(ellipseIn: ripple), with: .foreground, lineWidth: 0.6)
                }
            }
        }
        .frame(width: MiniPillPose.size.width, height: MiniPillPose.size.height)
        .accessibilityHidden(true)
    }
}

/// The render pose is also the test seam: the vector drawing and acceptance preview use
/// the same drop bounds, wave and drain level rather than parallel approximations.
struct MiniPillPose {
    static let size = CGSize(width: 7, height: 11)
    static let lineWidth = 1.0 // Scaled VesselGlyph wall; retains a clear centre at row size.
    static let wall = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
    static let inner = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth + 0.6, dy: lineWidth + 0.6)
    static let dropDiameter = 1.2 // KTD10's minimum readable drop, never scaled down.

    let level: Double
    let wavePhase: Int?
    let drop: CGRect?
    let ripple: CGRect?
    let rippleOpacity: Double

    init(mode: MiniPill.Mode, level: Double, date: Date, reduceMotion: Bool, sloshEndedAt: Date? = nil) {
        let startingLevel = min(1, max(0, level))
        switch mode {
        case .drip: self.level = 0
        case .drain(let progress): self.level = startingLevel * (1 - min(1, max(0, progress)))
        case .still, .slosh: self.level = startingLevel
        }
        let sloshing = LoadingMotionClock.isSloshing(active: mode == .slosh, endedAt: sloshEndedAt,
                                                    now: date, reduceMotion: reduceMotion)
        wavePhase = sloshing ? LoadingMotionClock.sloshPhase(at: date) : nil
        guard mode == .drip, !reduceMotion else {
            drop = nil; ripple = nil; rippleOpacity = 0
            return
        }
        let remainder = date.timeIntervalSince1970.truncatingRemainder(dividingBy: LoadingMotionConstants.dripCycle)
        let cycle = remainder < 0 ? remainder + LoadingMotionConstants.dripCycle : remainder
        if cycle < LoadingMotionConstants.dripFall {
            let progress = cycle / LoadingMotionConstants.dripFall
            // The fall starts below the rounded cap and lands just above the base.
            let start = Self.inner.minY + Self.dropDiameter / 2
            let end = Self.inner.maxY - Self.dropDiameter / 2
            let y = start + (end - start) * progress * progress
            drop = CGRect(x: Self.size.width / 2 - Self.dropDiameter / 2,
                          y: y - Self.dropDiameter / 2, width: Self.dropDiameter, height: Self.dropDiameter)
            ripple = nil; rippleOpacity = 0
        } else {
            drop = nil
            let progress = (cycle - LoadingMotionConstants.dripFall) / LoadingMotionConstants.dripRipple
            if progress < 1 {
                let width = Self.dropDiameter + (Self.inner.width - Self.dropDiameter) * progress
                ripple = CGRect(x: (Self.size.width - width) / 2, y: Self.inner.maxY - 1.3, width: width, height: 0.65)
                rippleOpacity = (1 - progress) * 0.7
            } else {
                ripple = nil; rippleOpacity = 0
            }
        }
    }

    var liquidPath: Path {
        var path = Path()
        guard level > 0 else { return path }
        let inner = Self.inner
        let surface = inner.maxY - inner.height * level
        path.move(to: CGPoint(x: inner.minX, y: inner.maxY))
        for step in 0...24 {
            let x = Double(step) / 24
            let shift = Double(wavePhase ?? 0) / Double(LoadingMotionConstants.sloshFrameCount)
            // Same wavelength as VesselGlyph, scaled to the smaller vessel.
            let wave = wavePhase == nil ? 0 : 0.42 * sin(2 * .pi * (x - shift))
            path.addLine(to: CGPoint(x: inner.minX + inner.width * x, y: surface + wave))
        }
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.closeSubpath()
        return path
    }
}
