import SwiftUI

struct VesselMark: View {
    var fill: CGFloat = 0.46
    var isEmpty = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Capsule()
                .strokeBorder(outlineStyle, lineWidth: 2)
            Capsule()
                .inset(by: 4)
                .fill(liquidStyle)
                .mask {
                    GeometryReader { proxy in
                        Rectangle()
                            .frame(height: proxy.size.height * clampedFill)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            if !isEmpty {
                Capsule()
                    .fill(Color.white.opacity(scheme == .dark ? 0.22 : 0.34))
                    .frame(width: 4)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 15)
            }
        }
        .shadow(color: Color.accentColor.opacity(scheme == .dark ? 0.20 : 0.12), radius: 18, y: 8)
        .accessibilityHidden(true)
    }

    private var clampedFill: CGFloat {
        isEmpty ? 0.26 : min(1, max(0, fill))
    }

    private var outlineStyle: AnyShapeStyle {
        if isEmpty {
            AnyShapeStyle(HeadroomTheme.hairline(scheme))
        } else {
            AnyShapeStyle(LinearGradient(
                colors: [
                    Color.white.opacity(scheme == .dark ? 0.22 : 0.72),
                    Color.black.opacity(scheme == .dark ? 0.12 : 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    private var liquidStyle: AnyShapeStyle {
        if isEmpty {
            AnyShapeStyle(HeadroomTheme.barTrack(scheme))
        } else {
            AnyShapeStyle(LinearGradient(
                colors: [Color.accentColor.opacity(0.72), Color.accentColor],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }
}
