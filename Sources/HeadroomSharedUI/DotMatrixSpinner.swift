// Adapted from FlickerDot 0.2.0 (https://github.com/laurieesc/flicker-dot) — the SwiftUI
// player, trimmed to what Headroom uses and re-tuned for small sizes. Pattern made with Flicker
// (flicker.laurie.fyi).
//
// MIT License
//
// Copyright (c) 2026 Laura Escobar
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import SwiftUI

/// A flip-dot animation: frames cut hard on a fixed beat with no eased fades, so it reads
/// as a mechanism working, not a pulse.
public struct DotMatrixPattern: Sendable {
    /// Dots per side; the grid is square.
    public let columns: Int
    /// Each frame is `columns * columns` flags, row-major.
    public let frames: [[Bool]]
    /// What Reduce Motion holds on. The library always holds frame 0, which is blank for
    /// patterns that build from empty.
    public let stillFrame: Int

    /// Frames drawn as rows of `#` (lit) and `.` (dark) so the pattern stays legible and
    /// editable in source.
    public init(stillFrame: Int = 0, _ art: [[String]]) {
        columns = art.first?.count ?? 0
        frames = art.map { rows in rows.flatMap { $0.map { $0 == "#" } } }
        self.stillFrame = stillFrame
    }

    public func isLit(dot: Int, frame: Int) -> Bool {
        frames.indices.contains(frame) && frames[frame].indices.contains(dot) && frames[frame][dot]
    }

    /// An arc sweeping clockwise round the ring. Authored on Flicker's 7×7 canvas but never
    /// touching the outer ring, so it's stored as the inner 5×5: fewer, larger dots at the
    /// small sizes the popover needs.
    public static let arc = DotMatrixPattern([
        [".###.", "....#", "....#", ".....", "....."],
        ["...#.", "....#", "....#", "....#", "...#."],
        [".....", ".....", "....#", "....#", ".###."],
        [".....", ".....", "#....", "#....", ".###."],
        [".#...", "#....", "#....", "#....", ".#..."],
        [".###.", "#....", "#....", ".....", "....."],
    ])

    /// 150ms a frame, the library's design speed.
    public static let frameInterval: TimeInterval = 0.150

    /// Which frame shows after `elapsed` seconds. Timeline dates land a hair before each
    /// boundary, so a thousandth of a frame absorbs that without ever showing a tick late.
    public static func frameIndex(elapsed: TimeInterval, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        return Int((max(elapsed, 0) / frameInterval + 1e-3).rounded(.down)) % frameCount
    }
}

/// Headroom's loading indicator in the popover footer and the setup waiting cards. The
/// settings and account-row spinners stay native: at 10pt the dots blur into grey.
public struct DotMatrixSpinner: View {
    public var pattern: DotMatrixPattern = .arc
    public var size: CGFloat

    public init(pattern: DotMatrixPattern = .arc, size: CGFloat) {
        self.pattern = pattern
        self.size = size
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()

    public var body: some View {
        Group {
            if reduceMotion {
                frame(pattern.stillFrame)
            } else {
                TimelineView(.periodic(from: origin, by: DotMatrixPattern.frameInterval)) { context in
                    frame(DotMatrixPattern.frameIndex(
                        elapsed: context.date.timeIntervalSince(origin),
                        frameCount: pattern.frames.count))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text("Loading"))
    }

    /// Every position draws a dot: lit ones in the secondary tint, the rest as a quiet grid.
    /// The dot is larger relative to its pitch than the library's (0.8 vs 0.67) so a
    /// small grid keeps round, separable dots instead of specks.
    private func frame(_ index: Int) -> some View {
        Canvas { context, canvasSize in
            let columns = pattern.columns
            let pitch = min(canvasSize.width, canvasSize.height) / CGFloat(columns)
            let diameter = pitch * 0.8
            for dot in 0..<(columns * columns) {
                let center = CGPoint(x: (CGFloat(dot % columns) + 0.5) * pitch,
                                     y: (CGFloat(dot / columns) + 0.5) * pitch)
                let circle = Path(ellipseIn: CGRect(x: center.x - diameter / 2,
                                                    y: center.y - diameter / 2,
                                                    width: diameter, height: diameter))
                context.fill(circle, with: pattern.isLit(dot: dot, frame: index)
                    ? .style(.secondary) : .style(.quaternary))
            }
        }
    }
}
