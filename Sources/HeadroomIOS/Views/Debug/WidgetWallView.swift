import SwiftUI

// U18 (iOS parity plan, R31, KTD21): the App Store widget frames. `--demo --demo-screen widgets`
// replaces the companion with a Home Screen-like wall of the real shared widget views, so
// `simctl io screenshot` captures them with true iOS text metrics (research appstore.md §6.2).
// Screenshot scaffolding only: the wall is compiled out of Release and the hook below is a
// no-op there.

extension View {
    /// The app's one-line hook (HeadroomIOSApp). DEBUG: a `--demo --demo-screen widgets`
    /// launch shows the widget wall instead of the companion. Release: returns the view as is.
    @ViewBuilder
    func demoWidgetWall() -> some View {
        #if DEBUG
        modifier(WidgetWallLaunchHook(launch: .current))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct WidgetWallLaunchHook: ViewModifier {
    let launch: CompanionDemoLaunchOptions

    func body(content: Content) -> some View {
        if launch.isDemoLaunch && launch.screen == .widgets {
            WidgetWallView(launch: launch)
        } else {
            content
        }
    }
}

/// Every tile reads the one envelope a real Home Screen widget would get in this demo variant:
/// the same `CompanionWidgetLoad` projection and freshness treatment as
/// `HeadroomIOSTimelineProvider`, so the wall can only pose states real widgets reach. Widgets
/// have no per-widget provider choice, so tiles differ by style and family, never by provider.
struct WidgetWallView: View {
    /// `--widget-wall home|styles`: which arrangement shots.json asks for (`widgetWall`).
    enum Arrangement: String {
        /// Nested Meter large with two smalls (frames I2, P2).
        case home
        /// One tile per style (frames I6, P4).
        case styles

        static let flag = "--widget-wall"

        static func parse(_ arguments: [String]) -> Self {
            guard let index = arguments.lastIndex(of: flag), arguments.indices.contains(index + 1) else { return .home }
            return Self(rawValue: arguments[index + 1]) ?? .home
        }
    }

    private let arrangement: Arrangement
    private let state: IOSWidgetSnapshotState
    private let freshness: WidgetFreshnessTreatment
    private let now: Date

    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(launch: CompanionDemoLaunchOptions, arguments: [String] = CommandLine.arguments) {
        let store = CompanionDemoModeStore.appGroup()
        let now = Date()
        let load = CompanionWidgetLoad.from(store.snapshot(store.variant(launch: launch)), isDemo: true)
        arrangement = Arrangement.parse(arguments)
        state = load.state
        freshness = .widget(inputs: load.freshness, now: now, host: .phone)
        self.now = now
    }

    var body: some View {
        let geometry = sizeClass == .regular ? WallGeometry.iPad13 : WallGeometry.iPhone69
        ZStack(alignment: .top) {
            wallpaper.ignoresSafeArea()
            Group {
                switch arrangement {
                case .home: home(geometry)
                case .styles: styles(geometry)
                }
            }
            .padding(.top, geometry.topInset)
        }
    }

    // MARK: Arrangements

    @ViewBuilder
    private func home(_ g: WallGeometry) -> some View {
        if g.isWide {
            HStack(alignment: .top, spacing: g.columnGap) {
                tile(.nestedMeter, .large, g)
                VStack(spacing: g.rowGap) {
                    tile(.vesselHero, .small, g)
                    tile(.tightestFirst, .small, g)
                }
            }
        } else {
            VStack(spacing: g.rowGap) {
                tile(.nestedMeter, .large, g)
                HStack(spacing: g.columnGap) {
                    tile(.vesselHero, .small, g)
                    tile(.tightestFirst, .small, g)
                }
            }
        }
    }

    @ViewBuilder
    private func styles(_ g: WallGeometry) -> some View {
        if g.isWide {
            VStack(spacing: g.rowGap) {
                HStack(spacing: g.columnGap) {
                    tile(.nestedMeter, .medium, g)
                    tile(.liquidLevel, .medium, g)
                }
                HStack(spacing: g.columnGap) {
                    tile(.vesselHero, .small, g)
                    tile(.tightestFirst, .small, g)
                }
            }
        } else {
            VStack(spacing: g.rowGap) {
                tile(.nestedMeter, .medium, g)
                HStack(spacing: g.columnGap) {
                    tile(.vesselHero, .small, g)
                    tile(.tightestFirst, .small, g)
                }
                tile(.liquidLevel, .medium, g)
            }
        }
    }

    // MARK: Tile

    /// The harness's non-host composition (`HeadroomWidgetStyledTile`): the style's full-bleed
    /// layer under the body padded by the iOS content margin, on the widgets' own container
    /// gradient, clipped to the Home Screen corner.
    @ViewBuilder
    private func tile(_ style: WidgetLayoutStyle, _ family: HeadroomWidgetFamily, _ g: WallGeometry) -> some View {
        let size = g.size(family)
        Group {
            switch state {
            case .demo(let envelope), .content(let envelope):
                HeadroomWidgetStyledTile(
                    style: style, family: family, envelope: envelope, colorMode: .solid, now: now,
                    // WCW3: demo tiles use the Mac prefix, exactly as the iOS widget host does.
                    footerPrefix: HeadroomWidgetCopy.macFooterPrefix,
                    contentMargin: g.margin(family), freshness: freshness)
            case .disabled: status(.iosDisabled, family, g)
            case .setupNeeded: status(.iosSetupNeeded, family, g)
            case .waitingForMac: status(.iosWaitingForMac, family, g)
            case .corrupt: status(.iosCorrupt, family, g)
            case .incompatibleSchema: status(.iosIncompatibleSchema, family, g)
            }
        }
        .frame(width: size.width, height: size.height)
        .background { tileBackground }
        .clipShape(RoundedRectangle(cornerRadius: g.cornerRadius, style: .continuous))
    }

    private func status(_ state: WidgetStatusState, _ family: HeadroomWidgetFamily, _ g: WallGeometry) -> some View {
        HeadroomWidgetStatusCard(state: state, family: family, scale: WidgetTypeScale.scale(for: family))
            .padding(g.margin(family) + WidgetMetrics.residualMargin)
    }

    /// The widgets' three-stop container falloff (`HeadroomWidgetContainerBackground`), from
    /// the one Core token set.
    private var tileBackground: some View {
        let dark = scheme == .dark
        return LinearGradient(
            colors: [
                Self.color(HeadroomWidgetColorValues.containerBackgroundTop(dark: dark)),
                Self.color(HeadroomWidgetColorValues.containerBackgroundMiddle(dark: dark)),
                Self.color(HeadroomWidgetColorValues.containerBackgroundBottom(dark: dark)),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// A plain Home Screen wallpaper in the Vessel icon's graphite (dark) or wall (light)
    /// colors (`design/vessel-app-icon.svg`), with no app icons (research appstore.md §6.2).
    private var wallpaper: some View {
        let stops: [UInt32] = scheme == .dark ? [0x33404F, 0x1A2330, 0x0B111A] : [0xDFE8E6, 0xC9D5D3, 0xB7C4C2]
        return LinearGradient(colors: stops.map(Self.color(hex:)), startPoint: .top, endPoint: .bottom)
    }

    private static func color(_ rgb: HeadroomRGBColor) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func color(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Home Screen widget geometry in points. iPhone 6.9″ matches the render harness's `ios67`
/// table (`WidgetRenderHarness.geometries`): 170/364×170/364×382 with the 12/14/12 content
/// margins the iOS host lands on (WCF4/WCL4); the gaps follow from those sizes. The iPad 13″
/// sizes are estimates carried over from the 12.9″ iPad Pro and are unverified (research
/// appstore.md §7): confirm them on a device before the final capture.
private struct WallGeometry {
    let small: CGSize
    let medium: CGSize
    let large: CGSize
    let cornerRadius: CGFloat
    let topInset: CGFloat
    let isWide: Bool

    static let iPhone69 = WallGeometry(
        small: CGSize(width: 170, height: 170), medium: CGSize(width: 364, height: 170),
        large: CGSize(width: 364, height: 382), cornerRadius: 23, topInset: 28, isWide: false)
    static let iPad13 = WallGeometry(
        small: CGSize(width: 170, height: 170), medium: CGSize(width: 379, height: 170),
        large: CGSize(width: 379, height: 379), cornerRadius: 22, topInset: 48, isWide: true)

    /// Medium spans two smalls plus one column gap; large spans two small rows plus one row gap.
    var columnGap: CGFloat { medium.width - 2 * small.width }
    var rowGap: CGFloat { large.height - 2 * small.height }

    func size(_ family: HeadroomWidgetFamily) -> CGSize {
        switch family {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    func margin(_ family: HeadroomWidgetFamily) -> CGFloat {
        family == .medium ? 14 : 12
    }
}
#endif
