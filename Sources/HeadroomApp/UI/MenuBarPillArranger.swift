import SwiftUI
import HeadroomCore

/// SM3 (2026-09-22): live drag-to-reorder for the Menu Bar pane's pill cards.
///
/// The old `.draggable` / `.dropDestination` pair ran a system drag session: the card stayed
/// where it was, a ghost image trailed the pointer, and nothing in the row moved until the
/// drop — then every card jumped at once. That is the "stuck frame" in the review. This view
/// owns the gesture instead, so the row behaves like a physical rearrangement:
///
/// - the picked-up card lifts (slight scale, deeper shadow) and tracks the pointer 1:1;
/// - a neighbour slides aside the moment the card crosses its midpoint, so the open gap
///   always shows where the card will land;
/// - past either end the card follows with rubber-band friction instead of a hard stop;
/// - on release the store order commits inside the same spring that settles the card, so the
///   card glides from where it was let go into its gap and nothing re-lays out after it.
///
/// Nothing reorders the store while the pointer is down — the row only *shows* the pending
/// order through offsets — so a drag abandoned back at its origin writes nothing.
struct MenuBarPillArranger<Card: View>: View {
    let ids: [ProviderID]
    let cardWidth: CGFloat
    let spacing: CGFloat
    /// Commit: move the first id before the second (nil appends). Same contract as
    /// `UsageStore.moveMenuBarProvider(_:before:)`.
    let onMove: (ProviderID, ProviderID?) -> Void
    @ViewBuilder let card: (ProviderID) -> Card

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The card under the pointer and how far it has travelled. Kept apart from
    /// `targetIndex` on purpose: the translation changes every frame *without* animation
    /// (the card is glued to the pointer), while the target changes rarely and *with* the
    /// nudge spring (the neighbours glide). One struct would force both through one
    /// transaction.
    @State private var dragged: (id: ProviderID, translation: CGFloat)?
    @State private var targetIndex: Int?

    private static var coordinateSpace: String { "MenuBarPillArranger" }

    /// SM3: how far the lifted card grows. Well under the press scale's 4% give — a lift is
    /// a hint of height, not a zoom.
    private static var liftScale: CGFloat { 1.03 }

    private var pitch: CGFloat { cardWidth + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                let lifted = dragged?.id == id
                card(id)
                    .frame(width: cardWidth)
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
                    .offset(x: offset(for: id, at: index))
                    .zIndex(lifted ? 1 : 0)
                    .gesture(dragGesture(for: id))
                    .pointerStyle(lifted ? .grabActive : .grabIdle)
                    .transition(Self.cardTransition(reduceMotion: reduceMotion))
            }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
    }

    // MARK: - Geometry

    private func offset(for id: ProviderID, at index: Int) -> CGFloat {
        guard let dragged, let start = ids.firstIndex(of: dragged.id) else { return 0 }
        if id == dragged.id { return rubberBanded(dragged.translation, from: start) }
        guard let target = targetIndex else { return 0 }
        // Cards between the origin and the target step one pitch toward the origin to open
        // the gap at the target.
        if start < target, index > start, index <= target { return -pitch }
        if target < start, index >= target, index < start { return pitch }
        return 0
    }

    private func index(for translation: CGFloat, from start: Int) -> Int {
        let steps = Int((translation / pitch).rounded())
        return min(max(start + steps, 0), ids.count - 1)
    }

    /// SM3: past the first or last slot the card keeps following with diminishing returns
    /// (the iOS rubber-band curve), capped well inside the preview well's edge.
    private func rubberBanded(_ translation: CGFloat, from start: Int) -> CGFloat {
        let lower = -CGFloat(start) * pitch
        let upper = CGFloat(ids.count - 1 - start) * pitch
        if translation < lower { return lower - resistance(lower - translation) }
        if translation > upper { return upper + resistance(translation - upper) }
        return translation
    }

    private func resistance(_ overshoot: CGFloat) -> CGFloat {
        let limit: CGFloat = 18
        return (1 - 1 / (overshoot * 0.55 / limit + 1)) * limit
    }

    // MARK: - Gesture

    private func dragGesture(for id: ProviderID) -> some Gesture {
        // Named space, not local: the card moves under the pointer, so a local translation
        // would feed its own offset back into itself and shudder.
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                guard let start = ids.firstIndex(of: id), ids.count > 1 else { return }
                guard dragged == nil || dragged?.id == id else { return }
                dragged = (id, value.translation.width)
                let target = index(for: value.translation.width, from: start)
                if target != targetIndex {
                    withAnimation(
                        HeadroomMotion.resolved(HeadroomMotion.dragNudge, .movement, reduceMotion: reduceMotion)
                    ) {
                        targetIndex = target
                    }
                }
            }
            .onEnded { _ in
                guard dragged?.id == id else { return }
                let start = ids.firstIndex(of: id)
                let target = targetIndex
                // One transaction for the commit and the release. The dragged card's slot
                // moves start → target while its offset returns to zero, and each neighbour's
                // slot shift cancels its gap offset — all on one spring, so the card glides
                // from where it was let go and no neighbour moves twice.
                withAnimation(
                    HeadroomMotion.resolved(HeadroomMotion.dragSettle, .movement, reduceMotion: reduceMotion)
                ) {
                    // `ids.indices` guards a pill removed mid-drag (a provider switched off
                    // in another window) from leaving the target past the end of the row.
                    if let start, let target, target != start, ids.indices.contains(target) {
                        onMove(id, Self.insertionTarget(in: ids, moving: start, to: target))
                    }
                    dragged = nil
                    targetIndex = nil
                }
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

    /// Adding or removing a pill: the card resolves in (or out) from 96% with a fade, and its
    /// neighbours slide on the caller's `reorder` scope. Under Reduce Motion that scope is one
    /// `.movement` transaction resolved to nil — the Accounts list's M7A precedent, which keeps
    /// the fade and the row's slide in one scope — so the edit lands instantly; the scale is
    /// dropped here too so no other animated transaction can scale a card.
    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }
}
