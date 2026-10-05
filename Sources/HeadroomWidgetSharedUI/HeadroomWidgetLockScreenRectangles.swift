#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// R2: one rectangle design per style — Nested Rows (05), Twin Vessels (06), Gauge Pair (12A)
/// and Liquid Strip (08). Widths flex across the 153–172 pt range (KTD12); heights use
/// `ViewThatFits` rungs that tighten gaps, then drop whole detail lines (R15/WCF7).
struct HeadroomWidgetLockScreenRectangle: View {
    let recipe: LockScreenWidgetRecipe
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        Group {
            if let status = recipe.status {
                HeadroomWidgetLockScreenStatusRectangle(status: status, prefix: recipe.headingPrefix)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(recipe.accessibilityText)
            } else {
                switch recipe.style {
                case .nestedMeter: HeadroomWidgetLockScreenNestedRows(recipe: recipe, art: art)
                case .vesselHero: HeadroomWidgetLockScreenTwinVessels(recipe: recipe, art: art)
                case .tightestFirst: HeadroomWidgetLockScreenGaugePair(recipe: recipe, art: art)
                case .liquidLevel: HeadroomWidgetLockScreenLiquidStrip(recipe: recipe, art: art)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// R17: two-provider rectangles and Gauge Pair read one element per slot.
private extension View {
    func lockScreenSlotElement(_ recipe: LockScreenWidgetRecipe, index: Int) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(recipe.accessibilityElements.indices.contains(index)
                                ? recipe.accessibilityElements[index] : recipe.accessibilityText)
    }
}

private extension LockScreenWindowState {
    /// R7/R8: these states have no reading to draw, so their word replaces the meter.
    var hasNoReading: Bool { self == .off || self == .pending || self == .signIn }
}

// MARK: - 05 Nested Rows

struct HeadroomWidgetLockScreenNestedRows: View {
    let recipe: LockScreenWidgetRecipe
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        if recipe.slots.count > 1 {
            pair
        } else if let slot = recipe.slots.first {
            single(slot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recipe.accessibilityText)
        }
    }

    /// The pair has no name line, so demo data adds a one-word heading (R10).
    private var pair: some View {
        VStack(alignment: .leading, spacing: recipe.isDemo ? 5 : 10) {
            if recipe.isDemo {
                HeadroomWidgetLockScreenLabel(text: "Demo", size: 10, weight: .semibold)
            }
            ForEach(Array(recipe.slots.enumerated()), id: \.offset) { index, slot in
                HStack(spacing: 8) {
                    HeadroomWidgetLockScreenSlotMark(slot: slot, size: 15, art: art)
                    meter(slot)
                    HeadroomWidgetLockScreenNumeral(slot.primary, size: LockScreenWidgetTokens.tightestNumeral)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .lockScreenSlotElement(recipe, index: index)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func single(_ slot: LockScreenProviderSlot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: 15, art: art)
                HeadroomWidgetLockScreenLabel(text: recipe.title(forSlotAt: 0), size: 15, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HeadroomWidgetLockScreenNumeral(slot.primary, size: 20)
            }
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)
                    meter(slot)
                    Spacer().frame(height: 7)
                    detail(slot)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 5)
                    meter(slot)
                    Spacer().frame(height: 4)
                    detail(slot)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 6)
                    meter(slot)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func meter(_ slot: LockScreenProviderSlot) -> some View {
        if slot.primary.state.hasNoReading {
            HeadroomWidgetLockScreenCaption(slot.primary, size: 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HeadroomWidgetLockScreenNestedBars(slot, width: nil, parentHeight: 6, railHeight: 2.5,
                                              gap: slot.hasSiblingPools ? 3.5 : 2.5)
        }
    }

    /// The next window with its countdown, else when the main window refills.
    @ViewBuilder
    private func detail(_ slot: LockScreenProviderSlot) -> some View {
        let main = slot.primary
        if main.state.hasNoReading {
            // The meter line already carries the word.
            EmptyView()
        } else if main.state == .stale || main.state == .unavailable {
            HeadroomWidgetLockScreenCaption(main, size: 11.5)
        } else if let next = slot.secondary.first {
            let tail = next.countdownText.map { " · \($0)" } ?? ""
            HeadroomWidgetLockScreenFittingLabel(candidates: [
                "\(next.caption) \(next.numberText)\(tail)",
                "\(next.shortCaption) \(next.numberText)\(tail)",
                "\(next.shortCaption) \(next.numberText)",
            ])
        } else if let refill = main.refillText {
            HeadroomWidgetLockScreenFittingLabel(candidates: [refill, main.shortRefillText ?? refill])
        }
    }
}

// MARK: - 06 Twin Vessels

struct HeadroomWidgetLockScreenTwinVessels: View {
    let recipe: LockScreenWidgetRecipe
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        if recipe.slots.count > 1 {
            HStack(spacing: 0) {
                ForEach(Array(recipe.slots.enumerated()), id: \.offset) { index, slot in
                    if index > 0 {
                        Rectangle().fill(Color(white: LockScreenWidgetTokens.trackInk))
                            .frame(width: 1)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 9)
                    }
                    column(slot, name: recipe.displayName(forSlotAt: index), numeralSize: 21, gapAboveHero: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lockScreenSlotElement(recipe, index: index)
                }
            }
        } else if let slot = recipe.slots.first {
            HStack(alignment: .center, spacing: 12) {
                column(slot, name: recipe.displayName(forSlotAt: 0), numeralSize: 30, gapAboveHero: 5)
                    .fixedSize(horizontal: true, vertical: false)
                trailing(slot)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recipe.accessibilityText)
        }
    }

    private func column(_ slot: LockScreenProviderSlot, name: String, numeralSize: Double, gapAboveHero: Double) -> some View {
        let indent = HeadroomWidgetLockScreenHero.indent(numeralSize: numeralSize)
        return ViewThatFits(in: .vertical) {
            columnBody(slot, name: name, numeralSize: numeralSize, gap: gapAboveHero, captionGap: 4, indent: indent)
            columnBody(slot, name: name, numeralSize: numeralSize, gap: 2, captionGap: 1, indent: indent)
        }
    }

    private func columnBody(_ slot: LockScreenProviderSlot, name: String, numeralSize: Double,
                            gap: Double, captionGap: Double, indent: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                HeadroomWidgetLockScreenSlotMark(slot: slot, size: 12, art: art)
                HeadroomWidgetLockScreenLabel(text: name, size: 12, weight: .semibold)
            }
            Spacer().frame(height: gap)
            HeadroomWidgetLockScreenHero(recipe: slot.primary, numeralSize: numeralSize)
            Spacer().frame(height: captionGap)
            HeadroomWidgetLockScreenCaption(slot.primary, size: 10)
                .padding(.leading, indent)
        }
    }

    /// The other windows, else when the main window resets.
    @ViewBuilder
    private func trailing(_ slot: LockScreenProviderSlot) -> some View {
        if slot.secondary.isEmpty || slot.primary.state.hasNoReading {
            let reset = [slot.primary.resetText, slot.primary.refillText, slot.primary.shortRefillText].compactMap { $0 }
            if !reset.isEmpty, !slot.primary.state.hasNoReading {
                HeadroomWidgetLockScreenFittingLabel(candidates: reset, size: 11)
                    .padding(.top, 14)
            }
        } else {
            // R11/R15: a window's name never drops; a narrow column stacks it over the number.
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(slot.secondary.enumerated()), id: \.offset) { _, window in
                        HStack(spacing: 6) {
                            HeadroomWidgetLockScreenLabel(text: window.shortCaption, size: 11).fixedSize()
                            Spacer(minLength: 0)
                            HeadroomWidgetLockScreenNumeral(window, size: 13)
                        }
                    }
                }
                .padding(.top, 14)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(slot.secondary.enumerated()), id: \.offset) { _, window in
                        HeadroomWidgetLockScreenLabel(text: window.shortCaption, size: 11)
                        HeadroomWidgetLockScreenNumeral(window, size: 13)
                    }
                }
            }
        }
    }
}

// MARK: - 12A Gauge Pair

struct HeadroomWidgetLockScreenGaugePair: View {
    let recipe: LockScreenWidgetRecipe
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.height, 76)
            HStack(spacing: 16) {
                ForEach(Array(recipe.slots.prefix(2).enumerated()), id: \.offset) { index, slot in
                    HeadroomWidgetLockScreenTightestGauge(slot: slot, art: art)
                        .frame(width: side, height: side)
                        .lockScreenSlotElement(recipe, index: index)
                }
                if recipe.slots.count == 1, let slot = recipe.slots.first {
                    loneSide(slot)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// R12: Only limit when the provider has one window; otherwise the waiting word.
    @ViewBuilder
    private func loneSide(_ slot: LockScreenProviderSlot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if recipe.showsOnlyLimit {
                HeadroomWidgetLockScreenLabel(text: "Only limit")
                if let reset = slot.primary.resetText {
                    HeadroomWidgetLockScreenFittingLabel(
                        candidates: [reset, slot.primary.shortRefillText ?? reset], size: 11)
                }
            } else {
                // R7: the slot names its provider beside the gauge's own word.
                HeadroomWidgetLockScreenLabel(text: recipe.displayName(forSlotAt: 0), size: 12, weight: .semibold)
                HeadroomWidgetLockScreenCaption(slot.primary, size: 11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 08 Liquid Strip

struct HeadroomWidgetLockScreenLiquidStrip: View {
    let recipe: LockScreenWidgetRecipe
    let art: HeadroomWidgetLockScreenArt

    var body: some View {
        ZStack {
            art.accessoryBackground()
            HStack(spacing: 0) {
                ForEach(Array(recipe.slots.enumerated()), id: \.offset) { _, slot in
                    HeadroomWidgetLockScreenWash(slot.primary)
                }
            }
            if recipe.slots.count > 1 {
                Rectangle().fill(Color(white: LockScreenWidgetTokens.trackInk)).frame(width: 1)
            }
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if recipe.slots.count > 1 {
            HStack(spacing: 0) {
                ForEach(Array(recipe.slots.enumerated()), id: \.offset) { index, slot in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 5) {
                            HeadroomWidgetLockScreenSlotMark(slot: slot, size: 12, art: art)
                            HeadroomWidgetLockScreenLabel(text: recipe.displayName(forSlotAt: index), size: 12, weight: .semibold)
                        }
                        Spacer(minLength: 0)
                        HeadroomWidgetLockScreenNumeral(slot.primary, size: 22)
                        HeadroomWidgetLockScreenCaption(slot.primary, size: 10)
                            .padding(.top, 1)
                    }
                    // R15: the knockout capsule is taller than a bare numeral; these insets
                    // keep a low half inside the 68 pt strip.
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .lockScreenSlotElement(recipe, index: index)
                }
            }
        } else if let slot = recipe.slots.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    HeadroomWidgetLockScreenSlotMark(slot: slot, size: 13, art: art)
                    HeadroomWidgetLockScreenLabel(text: recipe.displayName(forSlotAt: 0), size: 13, weight: .semibold)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let next = slot.secondary.first, !slot.primary.state.hasNoReading {
                        // WCF7: the secondary reading drops whole rather than truncating.
                        ViewThatFits(in: .horizontal) {
                            HeadroomWidgetLockScreenLabel(text: "\(next.shortCaption) \(next.numberText)", size: 11).fixedSize()
                            EmptyView()
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HeadroomWidgetLockScreenNumeral(slot.primary, size: 28)
                    ViewThatFits(in: .horizontal) {
                        HeadroomWidgetLockScreenCaption(slot.primary, size: 10.5).fixedSize()
                        HeadroomWidgetLockScreenCaption(slot.primary, compact: true, size: 10.5)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recipe.accessibilityText)
        }
    }
}

// MARK: - Status

/// R9: title and a two-line message.
struct HeadroomWidgetLockScreenStatusRectangle: View {
    let status: LockScreenWidgetStatusForm
    let prefix: String
    @HeadroomWidgetTypeUnit private var typeUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HeadroomWidgetLockScreenLabel(text: prefix + status.title, size: 13, weight: .semibold,
                                          ink: Color(white: LockScreenWidgetTokens.fullInk))
            Text(status.message)
                .font(.system(size: 11.5 * typeUnit, weight: .medium))
                .foregroundStyle(HeadroomWidgetLockScreenInk.label)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .headroomWidgetProbe()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
