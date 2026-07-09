#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif
import SwiftUI

typealias WidgetProviderStyle = HeadroomWidgetStyle

extension View {
    func largeProviderCard() -> some View {
        headroomWidgetLargeProviderCard()
    }
}
