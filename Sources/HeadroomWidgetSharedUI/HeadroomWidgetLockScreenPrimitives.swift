#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// KTD5/KTD6: presentation of Core's resolved states, independent of home rendering modes.
enum HeadroomWidgetLockScreenInk {
    static func numeral(_ state: LockScreenWindowState) -> Color {
        switch state {
        case .stale: Color(white: LockScreenWidgetTokens.halfInk)
        case .off, .pending, .signIn, .unavailable, .resetReached:
            Color(white: LockScreenWidgetTokens.secondaryInk)
        case .critical, .live: Color(white: LockScreenWidgetTokens.fullInk)
        }
    }

    /// R7/R8: a mark beside a provider with no reading steps back to secondary ink.
    static func mark(_ state: LockScreenWindowState) -> Double {
        switch state {
        case .off, .pending, .signIn: LockScreenWidgetTokens.secondaryInk
        default: LockScreenWidgetTokens.fullInk
        }
    }

    static let label = Color(white: LockScreenWidgetTokens.secondaryInk)

    static func caption(_ state: LockScreenWindowState) -> Color {
        switch state {
        case .stale: Color(white: LockScreenWidgetTokens.halfInk)
        case .off, .pending, .signIn: Color(white: LockScreenWidgetTokens.secondaryInk)
        case .unavailable, .resetReached, .critical, .live: Color(white: LockScreenWidgetTokens.fullInk)
        }
    }

    /// R8: reset-reached softens only the number; the retained fill keeps its ink.
    static func fill(_ state: LockScreenWindowState) -> Color {
        Color(white: state == .stale ? LockScreenWidgetTokens.halfInk : LockScreenWidgetTokens.fullInk)
    }
}

/// R16: both system privacy and gallery placeholders suppress every data-bearing fill.
struct HeadroomWidgetLockScreenEnvironment: DynamicProperty {
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.redactionReasons) private var redactionReasons

    var hidesContent: Bool {
        redactionReasons.contains(.privacy) || redactionReasons.contains(.placeholder)
    }

    func liquidFill(for state: LockScreenWindowState) -> Color {
        isLuminanceReduced
            ? Color(white: LockScreenWidgetTokens.alwaysOnWash)
            : HeadroomWidgetLockScreenInk.fill(state)
    }
}

/// KTD7: a flat silhouette; masking also preserves holes in injected original artwork.
public struct HeadroomWidgetLockScreenBrandMark<Mark: View>: View {
    private let providerID: String
    private let size: CGFloat
    private let ink: Double
    private let mark: (String, CGFloat) -> Mark

    public init(providerID: String, size: CGFloat, ink: Double = LockScreenWidgetTokens.fullInk,
                @ViewBuilder mark: @escaping (String, CGFloat) -> Mark) {
        self.providerID = providerID
        self.size = size
        self.ink = ink
        self.mark = mark
    }

    public var body: some View {
        Color(white: ink)
            .frame(width: size, height: size)
            .mask { mark(providerID, size) }
            .fixedSize()
            .accessibilityHidden(true)
            .headroomWidgetProbe()
    }
}

/// KTD8: destinationOut punches through only the capsule, leaving the wallpaper visible.
public struct HeadroomWidgetLockScreenNumeral: View {
    private let recipe: LockScreenWindowRecipe
    private let size: Double
    private var environment = HeadroomWidgetLockScreenEnvironment()

    public init(_ recipe: LockScreenWindowRecipe, size: Double) {
        self.recipe = recipe
        self.size = size
    }

    public var body: some View {
        Group {
            if recipe.usesKnockout, !environment.hidesContent {
                if environment.isLuminanceReduced {
                    number
                        .padding(.horizontal, LockScreenWidgetTokens.knockoutHorizontalPadding)
                        .padding(.vertical, LockScreenWidgetTokens.knockoutVerticalPadding)
                        .overlay { Capsule().strokeBorder(Color(white: LockScreenWidgetTokens.fullInk),
                                                          lineWidth: LockScreenWidgetTokens.knockoutStroke) }
                } else {
                    number
                        .padding(.horizontal, LockScreenWidgetTokens.knockoutHorizontalPadding)
                        .padding(.vertical, LockScreenWidgetTokens.knockoutVerticalPadding)
                        .background { Capsule().fill(Color(white: LockScreenWidgetTokens.fullInk)) }
                        .overlay { number.blendMode(.destinationOut) }
                        // KTD8: the capsule must be the destination, not the entire tile.
                        .compositingGroup()
                }
            } else {
                number
            }
        }
        .fixedSize()
        .headroomWidgetProbe()
    }

    private var number: some View {
        Text(recipe.numberText)
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(HeadroomWidgetLockScreenInk.numeral(recipe.state))
            .lineLimit(1)
            .fixedSize()
            .privacySensitive()
            .headroomWidgetProbe()
    }
}

/// R8: Core supplies the warning prefix and label; the glyph stays monochrome rather than emoji.
public struct HeadroomWidgetLockScreenCaption: View {
    private let recipe: LockScreenWindowRecipe
    private let compact: Bool
    private let size: Double
    @HeadroomWidgetTypeUnit private var typeUnit

    public init(_ recipe: LockScreenWindowRecipe, compact: Bool = false, size: Double = LockScreenWidgetTokens.captionSize) {
        self.recipe = recipe
        self.compact = compact
        self.size = size
    }

    public var body: some View {
        let caption = compact ? recipe.shortCaption : recipe.caption
        HStack(spacing: LockScreenWidgetTokens.captionGap) {
            if caption.hasPrefix("⚠ ") {
                Image(systemName: "exclamationmark.triangle")
                    .fixedSize()
                    .headroomWidgetProbe()
            }
            Text(caption.hasPrefix("⚠ ") ? String(caption.dropFirst(2)) : caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .headroomWidgetProbe()
        }
        .font(.system(size: size * typeUnit, weight: .semibold))
        .foregroundStyle(HeadroomWidgetLockScreenInk.caption(recipe.state))
        .privacySensitive()
        .headroomWidgetProbe()
    }
}

/// R3/R15: fixed-size open arc; the recipe's level never gets re-ranked in the view.
public struct HeadroomWidgetLockScreenArc: View {
    private let recipe: LockScreenWindowRecipe
    private var environment = HeadroomWidgetLockScreenEnvironment()

    public init(_ recipe: LockScreenWindowRecipe) { self.recipe = recipe }

    public var body: some View {
        ZStack {
            arc(fraction: LockScreenWidgetTokens.arcSweep)
                .stroke(Color(white: LockScreenWidgetTokens.trackInk), style: stroke)
            if !environment.hidesContent, recipe.fillFraction > 0 {
                arc(fraction: LockScreenWidgetTokens.arcSweep * recipe.fillFraction)
                    .stroke(HeadroomWidgetLockScreenInk.fill(recipe.state), style: stroke)
            }
        }
        .rotationEffect(.degrees(LockScreenWidgetTokens.arcRotation))
        .frame(width: LockScreenWidgetTokens.arcRadius * 2 + LockScreenWidgetTokens.arcStroke,
               height: LockScreenWidgetTokens.arcRadius * 2 + LockScreenWidgetTokens.arcStroke)
        .fixedSize()
        .accessibilityHidden(true)
        .headroomWidgetProbe()
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: LockScreenWidgetTokens.arcStroke, lineCap: .round) }
    private func arc(fraction: Double) -> some Shape {
        Circle().inset(by: LockScreenWidgetTokens.arcStroke / 2).trim(from: 0, to: fraction)
    }
}

/// R2: Cursor sibling pools use equal bars; rolling windows use the thinner rails. A nil
/// width fills the offered width (Nested Rows); the badge passes its fixed bar width.
public struct HeadroomWidgetLockScreenNestedBars: View {
    private let slot: LockScreenProviderSlot
    private let width: Double?
    private let parentHeight: Double
    private let railHeight: Double
    private let gap: Double
    private var environment = HeadroomWidgetLockScreenEnvironment()

    public init(_ slot: LockScreenProviderSlot,
                width: Double? = LockScreenWidgetTokens.nestedBarWidth,
                parentHeight: Double = LockScreenWidgetTokens.nestedParentHeight,
                railHeight: Double = LockScreenWidgetTokens.nestedRailHeight,
                gap: Double = LockScreenWidgetTokens.nestedRailGap) {
        self.slot = slot
        self.width = width
        self.parentHeight = parentHeight
        self.railHeight = railHeight
        self.gap = gap
    }

    public var body: some View {
        VStack(spacing: gap) {
            bar(slot.primary, height: parentHeight)
            ForEach(Array(slot.secondary.enumerated()), id: \.offset) { _, recipe in
                bar(recipe, height: slot.hasSiblingPools ? parentHeight : railHeight)
            }
        }
        .frame(width: width.map { CGFloat($0) })
        .fixedSize(horizontal: width != nil, vertical: true)
        .accessibilityHidden(true)
        .headroomWidgetProbe()
    }

    private func bar(_ recipe: LockScreenWindowRecipe, height: Double) -> some View {
        Capsule().fill(Color(white: LockScreenWidgetTokens.trackInk))
            .overlay(alignment: .leading) {
                if !environment.hidesContent, recipe.fillFraction > 0 {
                    GeometryReader { geometry in
                        // R8: a nonzero reading never shrinks below a round end cap.
                        Capsule().fill(HeadroomWidgetLockScreenInk.fill(recipe.state))
                            .frame(width: max(height, geometry.size.width * recipe.fillFraction))
                    }
                }
            }
            .frame(height: height)
            .headroomWidgetProbe()
    }
}

/// KTD5/R3: only a lower wash, with no bright surface edge.
public struct HeadroomWidgetLockScreenWash: View {
    private let recipe: LockScreenWindowRecipe
    private var environment = HeadroomWidgetLockScreenEnvironment()

    public init(_ recipe: LockScreenWindowRecipe) { self.recipe = recipe }

    public var body: some View {
        GeometryReader { geometry in
            if !environment.hidesContent, recipe.fillFraction > 0 {
                let strength = recipe.state == .stale ? LockScreenWidgetTokens.halfInk : LockScreenWidgetTokens.fullInk
                let top = environment.isLuminanceReduced ? LockScreenWidgetTokens.alwaysOnWash : LockScreenWidgetTokens.washTop * strength
                let bottom = environment.isLuminanceReduced ? LockScreenWidgetTokens.alwaysOnWash : LockScreenWidgetTokens.washBottom * strength
                LinearGradient(colors: [Color(white: top), Color(white: bottom)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * recipe.fillFraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .headroomWidgetProbe()
            }
        }
        .accessibilityHidden(true)
        .headroomWidgetProbe()
    }
}

/// KTD6: identical capsule geometry and digit-ink optics to the home vessel, in one ink.
public struct HeadroomWidgetLockScreenVessel: View {
    private let fraction: Double
    private let state: LockScreenWindowState
    private let geometry: WidgetVesselGeometry
    private var environment = HeadroomWidgetLockScreenEnvironment()

    public init(_ recipe: LockScreenWindowRecipe, geometry: WidgetVesselGeometry) {
        self.init(fraction: recipe.fillFraction, state: recipe.state, geometry: geometry)
    }

    /// WCW4/R9: the status mark draws `WidgetStatusState.vesselFill`, never a reading.
    public init(fraction: Double, state: LockScreenWindowState = .live, geometry: WidgetVesselGeometry) {
        self.fraction = fraction
        self.state = state
        self.geometry = geometry
    }

    public static func geometry(numeralSize: Double) -> WidgetVesselGeometry {
        let ink = HeadroomWidgetFontMetrics.digitInk(size: CGFloat(numeralSize), weight: .semibold)
        return WidgetVesselGeometry(height: Double(((ink.ascent + ink.descent) * 2).rounded() / 2))
    }

    public var body: some View {
        let liquid = geometry.liquidHeight(fraction: fraction)
        ZStack {
            Capsule().inset(by: geometry.stroke / 2)
                .stroke(Color(white: LockScreenWidgetTokens.secondaryInk), lineWidth: geometry.stroke)
            if !environment.hidesContent, liquid > 0 {
                Rectangle().fill(environment.liquidFill(for: state))
                    .frame(height: liquid)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .frame(width: geometry.innerWidth, height: geometry.innerHeight)
                    .clipShape(Capsule())
                    .headroomWidgetProbe()
            }
        }
        .frame(width: geometry.width, height: geometry.height)
        .fixedSize()
        .accessibilityHidden(true)
        .headroomWidgetProbe()
    }
}
