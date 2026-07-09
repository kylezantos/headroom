import SwiftUI

enum HeadroomMotion {
    static let settle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
    static let quickSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.12)
    static let valueSpring = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let press = Animation.easeOut(duration: 0.12)
}
