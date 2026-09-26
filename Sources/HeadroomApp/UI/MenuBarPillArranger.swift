import SwiftUI
import HeadroomCore

/// The two rows a pill card can sit in (PS1, 2026-09-23): the menu bar well on top and the
/// "Not shown" shelf under it.
enum PillShelf: Hashable {
    case menuBar
    case notShown
}

/// A card's place: which row, and which slot from the left.
struct PillShelfSlot: Hashable {
    var shelf: PillShelf
    var index: Int
}

/// What a finished drag writes to the store. Everything else about a drag is display-only.
enum PillShelfCommit: Equatable {
    case none
    case move(ProviderID, before: ProviderID?)
    case add(ProviderID, before: ProviderID?)
    case remove(ProviderID)
}

/// The arranger's pure decisions, apart from the generic view so they can be tested: where a
/// dragged card would land, where every other card sits meanwhile, and what the drop commits.
enum PillShelfModel {
    /// The first slot's inset inside either well, and the gap between neighbouring cards.
    static let wellPadding: CGFloat = 9
    static let spacing: CGFloat = 8
    static let maximumCardWidth: CGFloat = 100
    /// Below this the name, value, and arrows stop fitting a card. At the Settings window's
    /// 720pt floor four cards still get 98pt, so this only bites on a fifth provider.
    static let minimumCardWidth: CGFloat = 84

    /// Every card shares one width so a card keeps its size across both rows, and four cards
    /// fit one row at the window's minimum width instead of scrolling.
    static func cardWidth(forWidth width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return maximumCardWidth }
        let available = width - 2 * wellPadding - CGFloat(count - 1) * spacing
        return min(maximumCardWidth, max(minimumCardWidth, (available / CGFloat(count)).rounded(.down)))
    }

    /// The last pill cannot leave the menu bar; a shelf card can always go up.
    static func canLeave(_ origin: PillShelfSlot, shownCount: Int) -> Bool {
        origin.shelf == .notShown || shownCount > 1
    }

    static func origin(of id: ProviderID, shown: [ProviderID], notShown: [ProviderID]) -> PillShelfSlot? {
        if let index = shown.firstIndex(of: id) { return PillShelfSlot(shelf: .menuBar, index: index) }
        if let index = notShown.firstIndex(of: id) { return PillShelfSlot(shelf: .notShown, index: index) }
        return nil
    }

    /// Where the dragged card would land. The pointer's row picks the shelf; across the menu
    /// bar row the card's horizontal travel picks the slot, rounded at each midpoint. The
    /// shelf keeps canonical provider order, so a card dropped there always returns to its
    /// own slot. The last pill cannot leave the menu bar.
    static func drop(
        for id: ProviderID,
        shown: [ProviderID],
        notShown: [ProviderID],
        canonicalOrder: [ProviderID],
        translation: CGFloat,
        pointerInNotShown: Bool,
        pitch: CGFloat
    ) -> PillShelfSlot? {
        guard let origin = origin(of: id, shown: shown, notShown: notShown), pitch > 0 else { return nil }
        if pointerInNotShown && canLeave(origin, shownCount: shown.count) {
            let landing = canonicalOrder.filter { $0 == id || notShown.contains($0) }
            return PillShelfSlot(shelf: .notShown, index: landing.firstIndex(of: id) ?? notShown.count)
        }
        let others = shown.filter { $0 != id }.count
        let steps = Int((translation / pitch).rounded())
        return PillShelfSlot(shelf: .menuBar, index: min(max(origin.index + steps, 0), others))
    }

    /// Every card's slot while `dragging` hovers over `drop`: the other cards close the gap
    /// the dragged card left and open one where it would land. Under the pointer the dragged
    /// card keeps its origin slot, because its offset is measured from there; once released
    /// (`holdsOrigin: false`) it is anchored at its drop slot for the landing (PS7).
    static func slots(
        shown: [ProviderID],
        notShown: [ProviderID],
        dragging: ProviderID?,
        drop: PillShelfSlot?,
        holdsOrigin: Bool = true
    ) -> [ProviderID: PillShelfSlot] {
        var menuBar = shown
        var shelf = notShown
        var origin: PillShelfSlot?
        if let dragging, let drop, let from = Self.origin(of: dragging, shown: shown, notShown: notShown) {
            origin = from
            menuBar.removeAll { $0 == dragging }
            shelf.removeAll { $0 == dragging }
            switch drop.shelf {
            case .menuBar: menuBar.insert(dragging, at: min(drop.index, menuBar.count))
            case .notShown: shelf.insert(dragging, at: min(drop.index, shelf.count))
            }
        }
        var slots: [ProviderID: PillShelfSlot] = [:]
        for (index, id) in menuBar.enumerated() { slots[id] = PillShelfSlot(shelf: .menuBar, index: index) }
        for (index, id) in shelf.enumerated() { slots[id] = PillShelfSlot(shelf: .notShown, index: index) }
        if holdsOrigin, let dragging, let origin { slots[dragging] = origin }
        return slots
    }

    static func commit(
        for id: ProviderID,
        shown: [ProviderID],
        notShown: [ProviderID],
        drop: PillShelfSlot
    ) -> PillShelfCommit {
        guard let origin = origin(of: id, shown: shown, notShown: notShown) else { return .none }
        switch (origin.shelf, drop.shelf) {
        case (.menuBar, .menuBar):
            guard drop.index != origin.index, shown.indices.contains(drop.index) else { return .none }
            return .move(id, before: insertionTarget(in: shown, moving: origin.index, to: drop.index))
        case (.notShown, .menuBar):
            return .add(id, before: shown.indices.contains(drop.index) ? shown[drop.index] : nil)
        case (.menuBar, .notShown):
            return shown.count > 1 ? .remove(id) : .none
        case (.notShown, .notShown):
            return .none
        }
    }

    /// The id the moved card should land before once it has left `start` and settled at
    /// `target`, or nil for the end of the row.
    static func insertionTarget(in ids: [ProviderID], moving start: Int, to target: Int) -> ProviderID? {
        var order = ids
        let moved = order.remove(at: start)
        order.insert(moved, at: target)
        let next = target + 1
        return order.indices.contains(next) ? order[next] : nil
    }

    /// SM3: past a row's first or last slot the card keeps following with diminishing
    /// returns (the iOS rubber-band curve).
    static func rubberBanded(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        if value < lower { return lower - resistance(lower - value) }
        if value > upper { return upper + resistance(value - upper) }
        return value
    }

    private static func resistance(_ overshoot: CGFloat) -> CGFloat {
        let limit: CGFloat = 18
        return (1 - 1 / (overshoot * 0.55 / limit + 1)) * limit
    }
}

/// Module-level rather than a static on the generic view: the geometry callbacks are Sendable
/// closures, and a static would capture the view's metatype.
private let pillArrangerSpace = "MenuBarPillArranger"

/// SM3 → PS1 (2026-09-23): the Menu Bar pane's pill cards, in two rows. The top well is the
/// menu bar; the "Not shown" shelf under it holds every other provider. Drag a card up to add
/// its pill, down to remove it, or along the top row to reorder. The cards' own +, ×, and
/// arrow buttons do all of it without dragging.
///
/// SM3's feel carries across both rows:
///
/// - the picked-up card lifts (slight scale, deeper shadow) and tracks the pointer 1:1;
/// - the other cards slide the moment the drop target changes, so the open gap always shows
///   where the card will land, and the row it left closes up;
/// - past the top row's ends the card follows with rubber-band friction, and the last pill
///   rubber-bands on every side because it cannot leave;
/// - on release the store commits inside the same spring that settles the card, so the card
///   glides from where it was let go into its slot, even into the other row.
///
/// Every card is a child of one `PillShelfLayout`, not of a per-row stack. That is what lets
/// a card change rows as a *move*: in two stacks it would be removed from one and inserted
/// into the other, and the glide would become a fade. Nothing writes to the store while the
/// pointer is down, so a drag abandoned at its origin writes nothing.
struct MenuBarPillArranger<Card: View>: View {
    /// Pills in the menu bar, left to right.
    let shown: [ProviderID]
    /// Every other registered provider, in canonical order.
    let notShown: [ProviderID]
    /// Registered order: the shelf's order, and the cards' stable identity order.
    let canonicalOrder: [ProviderID]
    /// Switched-off providers stay on the shelf but cannot be picked up.
    let canDrag: (ProviderID) -> Bool
    /// Shown inside the menu bar well when it has no cards (the automatic summary).
    let menuBarMessage: (title: String?, detail: String)?
    let notShownCaption: String
    let notShownHelp: String
    let onCommit: (PillShelfCommit) -> Void
    /// Draws a card in the form of the given row. A dropped card takes its drop row's form
    /// the moment it is let go, so it morphs while it lands (PS8).
    @ViewBuilder let card: (ProviderID, PillShelf) -> Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Kept apart from `drop` on purpose: the translation changes every frame *without*
    /// animation (the card is glued to the pointer), while the drop target changes rarely and
    /// *with* the nudge spring (the other cards glide). One struct would force both through
    /// one transaction.
    @State private var dragged: (id: ProviderID, translation: CGSize)?
    @State private var drop: PillShelfSlot?
    /// PS8: the card between release and commit. See the landing storyboard on `land`.
    @State private var landing: Landing?
    /// MS3: which landing a settle completion belongs to, so a completion that arrives after
    /// a new grab finished its landing early can't commit a later one.
    @State private var landingGeneration = 0
    @State private var width: CGFloat = 0
    /// Where the pointer crosses into the shelf: halfway down the gap under the menu bar well.
    @State private var shelfBoundary: CGFloat = .infinity

    /// SM3: how far the lifted card grows. Well under the press scale's 4% give — a lift is
    /// a hint of height, not a zoom.
    private static var liftScale: CGFloat { 1.03 }

    private var cardWidth: CGFloat {
        PillShelfModel.cardWidth(forWidth: width, count: canonicalOrder.count)
    }

    private var pitch: CGFloat { cardWidth + PillShelfModel.spacing }

    private var slots: [ProviderID: PillShelfSlot] {
        if let landing {
            return PillShelfModel.slots(
                shown: shown, notShown: notShown, dragging: landing.id, drop: landing.drop, holdsOrigin: false
            )
        }
        return PillShelfModel.slots(shown: shown, notShown: notShown, dragging: dragged?.id, drop: drop)
    }

    /// Which row each card's height counts toward: its slot's row. A card under the pointer
    /// still counts toward the row it came from, so nothing resizes until it is let go.
    private var heightRows: [ProviderID: PillShelf] {
        slots.mapValues(\.shelf)
    }

    /// A row with no card in it, judged from the pending arrangement rather than the store, so
    /// its message comes and goes with the cards instead of at the commit.
    private func isEmpty(_ shelf: PillShelf) -> Bool {
        !heightRows.values.contains(shelf)
    }

    /// The row a card from the other row is hovering over, which lights to take it. Only
    /// while the pointer is down: the ring fades as the card is let go.
    private var receivingShelf: PillShelf? {
        guard let moving = dragged?.id, let drop,
              let origin = PillShelfModel.origin(of: moving, shown: shown, notShown: notShown),
              origin.shelf != drop.shelf else { return nil }
        return drop.shelf
    }

    var body: some View {
        PillShelfLayout(
            slots: slots,
            cardWidth: cardWidth,
            spacing: PillShelfModel.spacing,
            wellPadding: PillShelfModel.wellPadding,
            heightRows: heightRows,
            pointer: dragged.map { ($0.id, offset(for: $0.id)) },
            landing: landing?.id
        ) {
            well(.menuBar, cornerRadius: 20) {
                if let menuBarMessage, isEmpty(.menuBar), receivingShelf != .menuBar {
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                        if let title = menuBarMessage.title {
                            Text(title)
                                .font(.system(size: 13, weight: .medium))
                        }
                        SettingsHelpText(text: menuBarMessage.detail)
                    }
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(pillArrangerSpace)).maxY
            } action: { maxY in
                shelfBoundary = maxY + SettingsMetrics.groupToGroup / 2
            }
            // The layout reads its tag from a subview's outermost modifier, so the tag goes
            // last.
            .layoutValue(key: PillShelfPartKey.self, value: .well(.menuBar))

            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsGroupLabel(notShownCaption)
                SettingsHelpText(text: notShownHelp)
            }
            .layoutValue(key: PillShelfPartKey.self, value: .notShownHeader)

            well(.notShown, cornerRadius: 20) {
                if isEmpty(.notShown), receivingShelf != .notShown {
                    SettingsHelpText(text: "All providers shown.")
                        .padding(.horizontal, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .layoutValue(key: PillShelfPartKey.self, value: .well(.notShown))

            ForEach(shown + notShown, id: \.self) { id in
                let lifted = dragged?.id == id
                card(id, presentation(of: id))
                    .scaleEffect(lifted ? Self.liftScale : 1)
                    .shadow(
                        color: .black.opacity(lifted ? (colorScheme == .dark ? 0.45 : 0.16) : 0),
                        radius: lifted ? 10 : 0,
                        y: lifted ? 5 : 0
                    )
                    // Scoped *under* the offset: the lift eases in and out, but the offset
                    // below must stay un-animated while the pointer drives it.
                    .animation(
                        HeadroomMotion.resolved(HeadroomMotion.quickSettle, .movement, reduceMotion: reduceMotion),
                        value: lifted
                    )
                    .zIndex(lifted || landing?.id == id ? 2 : 1)
                    .gesture(dragGesture(for: id), including: canDrag(id) ? .all : .subviews)
                    .pointerStyle(canDrag(id) ? (lifted ? .grabActive : .grabIdle) : .default)
                    .transition(Self.cardTransition(reduceMotion: reduceMotion))
                    .layoutValue(key: PillShelfPartKey.self, value: .card(id))
            }
        }
        .coordinateSpace(.named(pillArrangerSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func well<Content: View>(
        _ shelf: PillShelf,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // A ZStack root, not the content itself: a well whose content is an `if` would stop
        // being one layout subview whenever the condition is false.
        return ZStack(alignment: .leading) {
            shape.fill(ProviderStyle.recessedWell(dark: colorScheme == .dark))
            // A faint ring on the row a card from the other row would drop into. The gap the
            // cards open already shows the slot; the ring is for an empty row, which has no
            // cards to part.
            shape.strokeBorder(.primary.opacity(receivingShelf == shelf ? 0.16 : 0), lineWidth: 1.5)
            content()
                .padding(PillShelfModel.wellPadding)
        }
        // Scoped to the well, not the whole layout: an animation keyed on the drop target
        // over the cards would override the drag's nudge and settle springs, and animate
        // the dragged card's pointer-glued offset.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.quickSettle, .crossfade, reduceMotion: reduceMotion),
            value: receivingShelf == shelf
        )
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.settle, .crossfade, reduceMotion: reduceMotion),
            value: isEmpty(shelf)
        )
        .zIndex(0)
    }

    // MARK: - Geometry

    private func presentation(of id: ProviderID) -> PillShelf {
        if let landing, landing.id == id { return landing.drop.shelf }
        return shown.contains(id) ? .menuBar : .notShown
    }

    private func offset(for id: ProviderID) -> CGSize {
        guard let dragged, dragged.id == id,
              let origin = PillShelfModel.origin(of: id, shown: shown, notShown: notShown) else { return .zero }
        let translation = dragged.translation
        let canLeave = PillShelfModel.canLeave(origin, shownCount: shown.count)
        guard drop?.shelf == .menuBar else { return translation }
        // Along the menu bar row the card stays between its first and last possible slot.
        let others = shown.filter { $0 != id }.count
        let x = PillShelfModel.rubberBanded(
            translation.width,
            lower: -CGFloat(origin.index) * pitch,
            upper: CGFloat(others - origin.index) * pitch
        )
        let y = canLeave ? translation.height : PillShelfModel.rubberBanded(translation.height, lower: 0, upper: 0)
        return CGSize(width: x, height: y)
    }

    // MARK: - Gesture

    private func dragGesture(for id: ProviderID) -> some Gesture {
        // Named space, not local: the card moves under the pointer, so a local translation
        // would feed its own offset back into itself and shudder.
        DragGesture(minimumDistance: 3, coordinateSpace: .named(pillArrangerSpace))
            .onChanged { value in
                // MS3 (2026-09-25 motion audit): a grab during a card's ~300ms landing used to
                // be ignored until the pointer was released and pressed again. The landing now
                // finishes at once and the new drag starts from the settled rows.
                if landing != nil, dragged == nil, canDrag(id) { finishLandingNow() }
                guard canDrag(id), landing == nil, dragged == nil || dragged?.id == id else { return }
                dragged = (id, value.translation)
                let target = PillShelfModel.drop(
                    for: id,
                    shown: shown,
                    notShown: notShown,
                    canonicalOrder: canonicalOrder,
                    translation: value.translation.width,
                    pointerInNotShown: value.location.y > shelfBoundary,
                    pitch: pitch
                )
                if target != drop {
                    withAnimation(
                        HeadroomMotion.resolved(HeadroomMotion.dragNudge, .movement, reduceMotion: reduceMotion)
                    ) {
                        drop = target
                    }
                }
            }
            .onEnded { _ in
                guard dragged?.id == id else { return }
                let commit = drop.map {
                    PillShelfModel.commit(for: id, shown: shown, notShown: notShown, drop: $0)
                } ?? .none
                if commit != .none, let drop {
                    land(id, at: drop, commit: commit)
                    return
                }
                // Nothing to write: the card springs back to its own slot, and any card that
                // parted for it closes up on the same spring.
                withAnimation(
                    HeadroomMotion.resolved(HeadroomMotion.dragSettle, .movement, reduceMotion: reduceMotion)
                ) {
                    dragged = nil
                    drop = nil
                }
            }
    }

    struct Landing {
        let id: ProviderID
        let drop: PillShelfSlot
        let commit: PillShelfCommit
        /// The rows as they stood when the card was let go. The commit only applies if they
        /// still do: a +, ×, arrow, or mode change during the landing wins over it.
        let shown: [ProviderID]
        let notShown: [ProviderID]
    }

    /* ─────────────────────────────────────────────────────────
     * LANDING STORYBOARD (PS8, Kyle 2026-09-24)
     *
     * Read top-to-bottom. Times are after the pointer lets go.
     *
     *    0ms   one transaction on dragSettle (~300ms, no overshoot):
     *          • the layout stops placing the card at pointer + origin
     *            and places it at its drop slot, so SwiftUI glides the
     *            card from exactly where it was let go;
     *          • the card takes the drop row's form (parts leave in
     *            80ms, arrive after 30ms in 160ms out of 0.97/blur 1.5 — MB1) and both
     *            rows resize to fit;
     *          • lift, drop ring and row messages ease on their own.
     * ~300ms   the store commits. The screen already shows the committed
     *          arrangement, so no card moves; mode-dependent chrome (the
     *          summary's shelf values) eases on cardMorph. A commit whose
     *          rows changed meanwhile (+, ×, arrows, mode) is dropped.
     *
     * The card's position is only ever the layout's placement — at the
     * pointer while dragging, at the slot once let go. Every earlier try
     * (SM3–PS7) moved it with an `.offset` layered over the placement and
     * needed the two to hand over cleanly; SwiftUI folded the handover
     * into one frame and the card jumped (to part-way back, then to the
     * far corner). One mechanism has nothing to hand over.
     * Reduce Motion: everything that moves is instant; fades keep their
     * timing (S2A).
     * ───────────────────────────────────────────────────────── */
    private func land(_ id: ProviderID, at drop: PillShelfSlot, commit: PillShelfCommit) {
        guard PillShelfModel.origin(of: id, shown: shown, notShown: notShown) != nil else { return }
        let animation = HeadroomMotion.resolved(HeadroomMotion.dragSettle, .movement, reduceMotion: reduceMotion)
        guard animation != nil else {
            landing = Landing(id: id, drop: drop, commit: commit, shown: shown, notShown: notShown)
            dragged = nil
            self.drop = nil
            commitLanding()
            return
        }
        landingGeneration &+= 1
        let generation = landingGeneration
        withAnimation(animation, completionCriteria: .removed) {
            landing = Landing(id: id, drop: drop, commit: commit, shown: shown, notShown: notShown)
            dragged = nil
            self.drop = nil
        } completion: {
            guard landingGeneration == generation else { return }
            commitLanding()
        }
    }

    /// MS3: the landing's commit without its remaining settle, for a grab that interrupts it.
    private func finishLandingNow() {
        landingGeneration &+= 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let landing, shown == landing.shown, notShown == landing.notShown {
                onCommit(landing.commit)
            }
            landing = nil
        }
    }

    /// ~300ms: the store catches up with the screen. Animated on `cardMorph`, not disabled:
    /// the arrangement already matches, so nothing moves, but leaving the automatic summary
    /// changes the pane around the card — the other shelf cards drop their values, the
    /// shelf and its copy resize — and those should ease, not snap.
    private func commitLanding() {
        guard let landing else { return }
        withAnimation(HeadroomMotion.resolved(HeadroomMotion.cardMorph, .movement, reduceMotion: reduceMotion)) {
            if shown == landing.shown, notShown == landing.notShown {
                onCommit(landing.commit)
            }
            self.landing = nil
        }
    }

    /// Adding or removing a provider altogether: the card resolves in (or out) from 96% with a
    /// fade, and its neighbours slide on the caller's `reorder` scope. Under Reduce Motion
    /// that scope is one `.movement` transaction resolved to nil — the Accounts list's M7A
    /// precedent, which keeps the fade and the row's slide in one scope — so the edit lands
    /// instantly; the scale is dropped here too so no other animated transaction can scale a
    /// card.
    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}

// MARK: - Layout

enum PillShelfPart: Hashable {
    case well(PillShelf)
    case notShownHeader
    case card(ProviderID)
}

struct PillShelfPartKey: LayoutValueKey {
    static let defaultValue: PillShelfPart? = nil
}

/// Places the two wells, the shelf's header between them, and every card at its slot. A row is
/// as tall as its tallest card, so a well grows when a taller card lands in it; placement
/// changes animate in whatever transaction changed the slots.
struct PillShelfLayout: Layout {
    var slots: [ProviderID: PillShelfSlot]
    var cardWidth: CGFloat
    var spacing: CGFloat
    var wellPadding: CGFloat
    /// PS7: the row each card's height counts toward; see `MenuBarPillArranger.heightRows`.
    var heightRows: [ProviderID: PillShelf] = [:]
    /// PS8: the card under the pointer and how far it has travelled from its slot. The layout
    /// places it there itself, so letting go is just a change of placement.
    var pointer: (id: ProviderID, offset: CGSize)? = nil
    /// PS7: a landing card takes its own height rather than its row's, so the form change
    /// is the only thing that resizes it.
    var landing: ProviderID? = nil
    /// An empty row keeps room for its message and for a card to be dropped into it.
    var emptyRowHeight: CGFloat = 56

    private struct Frames {
        var parts: [Int: CGRect] = [:]
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? naturalWidth(subviews)
        return CGSize(width: width, height: frames(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard let frame = frames.parts[index] else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func naturalWidth(_ subviews: Subviews) -> CGFloat {
        let count = CGFloat(subviews.filter { $0.part?.isCard == true }.count)
        return 2 * wellPadding + count * cardWidth + max(count - 1, 0) * spacing
    }

    private func frames(width: CGFloat, subviews: Subviews) -> Frames {
        var rowHeights: [PillShelf: CGFloat] = [.menuBar: 0, .notShown: 0]
        var cardHeights: [Int: CGFloat] = [:]
        for (index, subview) in subviews.enumerated() {
            guard case .card(let id) = subview.part, let slot = slots[id] else { continue }
            let height = subview.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
            cardHeights[index] = height
            let row = heightRows[id] ?? slot.shelf
            rowHeights[row] = max(rowHeights[row] ?? 0, height)
        }
        func rowHeight(_ shelf: PillShelf) -> CGFloat {
            let height = rowHeights[shelf] ?? 0
            return height > 0 ? height : emptyRowHeight
        }

        var frames = Frames()
        let menuBarWell = CGRect(x: 0, y: 0, width: width, height: rowHeight(.menuBar) + 2 * wellPadding)
        var y = menuBarWell.maxY + SettingsMetrics.groupToGroup
        var headerHeight: CGFloat = 0
        if let header = subviews.firstIndex(where: { $0.part == .notShownHeader }) {
            // A floor on the measuring width: the pane's own sizing pass proposes zero, where
            // the help line would wrap a word per line.
            headerHeight = subviews[header].sizeThatFits(ProposedViewSize(width: max(width, 200), height: nil)).height
            frames.parts[header] = CGRect(x: 0, y: y, width: width, height: headerHeight)
            y += headerHeight + SettingsMetrics.labelToControl * 2
        }
        let notShownWell = CGRect(x: 0, y: y, width: width, height: rowHeight(.notShown) + 2 * wellPadding)
        frames.height = notShownWell.maxY

        for (index, subview) in subviews.enumerated() {
            switch subview.part {
            case .well(.menuBar): frames.parts[index] = menuBarWell
            case .well(.notShown): frames.parts[index] = notShownWell
            case .card(let id):
                guard let slot = slots[id] else { continue }
                let well = slot.shelf == .menuBar ? menuBarWell : notShownWell
                let travel = pointer?.id == id ? pointer?.offset ?? .zero : .zero
                frames.parts[index] = CGRect(
                    x: wellPadding + CGFloat(slot.index) * (cardWidth + spacing) + travel.width,
                    y: well.minY + wellPadding + travel.height,
                    width: cardWidth,
                    height: id == landing || id == pointer?.id
                        ? cardHeights[index] ?? 0
                        : max(rowHeight(slot.shelf), cardHeights[index] ?? 0)
                )
            case .notShownHeader, nil:
                continue
            }
        }
        return frames
    }
}

private extension LayoutSubview {
    var part: PillShelfPart? { self[PillShelfPartKey.self] }
}

private extension PillShelfPart {
    var isCard: Bool {
        if case .card = self { return true }
        return false
    }
}

// MARK: - Card parts

/// PS2 (2026-09-23): what a card's pill shows, as a small borderless menu under the provider
/// name. It lists the limits the provider's main account reports, each with its current value
/// and reset, then Closest to limit. A provider with one limit (Grok) has nothing to choose,
/// so its card shows that limit as plain text.
struct PillValueMenu: View {
    let store: UsageStore
    let id: ProviderID
    let name: String
    /// PC2: a shelf card's value reads lighter, like the rest of its card.
    var dimmed = false

    private var selection: MenuBarWindowChoice { store.menuBarWindowPickerSelection(for: id) }
    private var resolved: WindowKind? { store.resolvedMenuBarWindowKind(for: id) }

    var body: some View {
        if store.hasSelectableMenuBarWindows(for: id) {
            let options = store.menuBarWindowOptions(for: id)
            Menu {
                Section("\(name) pill shows") {
                    ForEach(options.filter { $0.choice != .closest }) { option in
                        item(option.choice, title: option.title, detail: detail(for: option))
                    }
                }
                if options.contains(where: { $0.choice == .closest }) {
                    Divider()
                    item(.closest, title: MenuBarWindowChoice.closest.title, detail: closestDetail)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // PC2: a pull-down's single chevron. Up/down read as a stepper at 7pt.
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            // PC2: a borderless pull-down on the card's footer tray, so every footer reads the
            // same at rest and only the chevron marks the ones you can change.
            .menuStyle(.button)
            .buttonStyle(PillValueTrayStyle(dimmed: dimmed))
            .menuIndicator(.hidden)
            // No `fixedSize`: a long model row ("GPT-5.3-Codex-Spark · Weekly") must
            // truncate inside the card rather than spill over its neighbour.
            .help(note ?? "Choose what the \(name) pill shows")
            .accessibilityLabel("\(name) pill shows")
            .accessibilityValue(spokenValue)
        } else {
            Text(resolved?.displayName ?? "Waiting…")
                .font(SettingsType.help)
                .foregroundStyle(dimmed ? .tertiary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: PillValueTrayStyle.height)
                .help(resolved.map { "\(name) reports one limit: \($0.spokenName)." }
                    ?? "Waiting for \(name)’s first usage report.")
        }
    }

    /// Checkmarked item; a second `Text` is the menu item's subtitle line.
    private func item(_ choice: MenuBarWindowChoice, title: String, detail: String?) -> some View {
        Toggle(isOn: Binding(
            get: { selection == choice },
            set: { isOn in if isOn { store.setMenuBarWindowChoice(choice, for: id) } }
        )) {
            Text(title)
            if let detail { Text(detail) }
        }
    }

    /// The card's label: the limit the pill follows. Closest reads as "Closest" to fit the
    /// card; a chosen limit the data no longer carries shows the one actually on screen, and
    /// the tooltip says why.
    private var label: String {
        if selection == .closest { return "Closest" }
        if let resolved, !selection.matches(resolved) { return resolved.displayName }
        return selection.title
    }

    /// What VoiceOver hears: the limit the pill actually shows, as the visible label does,
    /// never a saved choice the data no longer carries.
    private var spokenValue: String {
        if selection == .closest {
            return resolved.map { "Closest to limit, now \($0.spokenName)" } ?? "Closest to limit"
        }
        let chosen = selection.kind?.spokenName ?? selection.title
        if let resolved, !selection.matches(resolved) {
            return "\(resolved.spokenName), while \(chosen) isn’t reported"
        }
        return chosen
    }

    /// Carried over from the old per-provider list's help line, now the menu's tooltip.
    private var note: String? {
        guard let resolved else { return nil }
        if selection == .closest {
            return "Following \(resolved.spokenName), the lowest right now."
        }
        if !selection.matches(resolved) {
            return "Showing \(resolved.spokenName) while \(selection.kind?.spokenName ?? selection.title) isn’t reported."
        }
        if resolved.spokenName != resolved.displayName {
            return "\(resolved.displayName) is a weekly limit."
        }
        return nil
    }

    private func detail(for option: MenuBarWindowOption) -> String? {
        guard let window = option.window else { return "Not in the latest usage" }
        if window.freshness.isUnavailable { return "Not available right now" }
        let mode = store.usagePercentageMode
        let reset = Countdown.resetText(for: window, now: .now)
        return "\(mode.roundedPercentage(for: window))% \(mode.term) · \(reset)"
    }

    private var closestDetail: String? {
        resolved.map { "Now \($0.displayName)" }
    }
}

/// PS4: the one control size inside a pill card. ×, +, the arrows, the value menu, and the
/// Off link are all 18pt tall with a quiet fill that only appears on hover, so a card's
/// controls read as one family instead of three.
struct PillCardChipStyle: ButtonStyle {
    static let side: CGFloat = 18

    /// Zero for the square glyph chips; the value menu pads its text.
    var horizontalPadding: CGFloat = 0
    /// PC2: the card's × and + rest in tertiary ink until the card is hovered, so the header
    /// reads as the provider's name rather than as a row of controls.
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, horizontalPadding: horizontalPadding, quiet: quiet)
    }

    private struct Chip: View {
        let configuration: Configuration
        let horizontalPadding: CGFloat
        let quiet: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var ink: HierarchicalShapeStyle {
            if hovering && isEnabled { return .primary }
            return quiet ? .tertiary : .secondary
        }

        var body: some View {
            configuration.label
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: PillCardChipStyle.side, minHeight: PillCardChipStyle.side)
                .background(
                    .primary.opacity(configuration.isPressed ? 0.12 : hovering && isEnabled ? 0.07 : 0),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { inside in
                    withAnimation(HeadroomMotion.resolved(
                        inside ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut, .crossfade, reduceMotion: reduceMotion
                    )) { hovering = inside }
                }
                .pointerStyle(.default)
        }
    }
}

/// PC2: the card footer's value pull-down. It spans the card 3pt in from each edge, and its
/// hover tray takes an 8pt radius (the card's 11 minus that inset) so the fill nests in the
/// card's bottom corners. No fill at rest.
struct PillValueTrayStyle: ButtonStyle {
    static let height: CGFloat = 22
    static let cornerRadius: CGFloat = 8

    var dimmed = false

    func makeBody(configuration: Configuration) -> some View {
        Tray(configuration: configuration, dimmed: dimmed)
    }

    private struct Tray: View {
        let configuration: Configuration
        let dimmed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(SettingsType.help)
                .foregroundStyle(hovering ? .primary : dimmed ? .tertiary : .secondary)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: PillValueTrayStyle.height)
                .background(
                    .primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.065 : 0),
                    in: RoundedRectangle(cornerRadius: PillValueTrayStyle.cornerRadius, style: .continuous)
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    withAnimation(HeadroomMotion.resolved(
                        inside ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut, .crossfade, reduceMotion: reduceMotion
                    )) { hovering = inside }
                }
                .pointerStyle(.default)
        }
    }
}

/// PC2: the move carets beside the pill — an 11 × 25pt target, the empty flank's own size,
/// so even an 84pt card holding a percentage pill keeps them clear of it.
struct PillCaretStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Caret(configuration: configuration)
    }

    private struct Caret: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovering = false

        /// PC3 (Kyle, 2026-09-26): no hover plate. A filled box beside the pill crowded the
        /// card, so the caret answers the pointer with ink alone — secondary at rest, full
        /// strength on hover (a step past `.primary`'s 85%), back to secondary while pressed
        /// — plus the pointing-hand cursor, which is what tells it apart from the card's grab.
        private var ink: Color {
            guard hovering, !configuration.isPressed else { return Color.secondary }
            return colorScheme == .dark ? .white : .black
        }

        var body: some View {
            configuration.label
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ink)
                // The 11 × 25 target is kept, just invisible.
                .frame(width: 11, height: 25)
                .contentShape(Rectangle())
                .onHover { inside in
                    withAnimation(HeadroomMotion.resolved(
                        inside ? HeadroomMotion.hoverIn : HeadroomMotion.hoverOut, .crossfade, reduceMotion: reduceMotion
                    )) { hovering = inside }
                }
                .pointerStyle(.link)
        }
    }
}

extension View {
    /// PS1: a shelf card is flatter than a pill card — a faint fill and ring instead of the
    /// raised tile — but still opaque, because it can be lifted over the menu bar row.
    func shelfCardSurface(dark: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return self
            .background(.primary.opacity(dark ? 0.05 : 0.03), in: shape)
            .overlay { shape.strokeBorder(.primary.opacity(dark ? 0.1 : 0.08), lineWidth: 1) }
            .background(Color(nsColor: .windowBackgroundColor), in: shape)
            .contentShape(shape)
    }
}
