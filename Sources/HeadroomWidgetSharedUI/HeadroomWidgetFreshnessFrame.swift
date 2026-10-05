#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// U13 (iOS parity plan, KTD15): the one layout every widget style shares for the freshness
/// states. The recipe already carries the window treatments (past-reset windows unavailable,
/// dimmed windows stale), so the style bodies only gained last-resort shedding rungs; this
/// frame adds the two lines those states print:
///
/// - R11's "Reset at <time>" notes, under the style (in its tail, above the footer, on large).
///   They are the first thing every family drops: the recipe's note rungs are tried with the
///   style at its fullest, then the style alone sheds its own ladder (KTD10). The window
///   itself already reads "—".
/// - R10's dimmed sentence at the foot of every family. It never drops; the style sheds rows
///   to make room, and on large it takes the place of the footer stamp and spend strip.
struct HeadroomWidgetFreshnessFrame<Content: View>: View {
    let recipe: WidgetStyleRecipe
    /// The style body, given the notes it should print itself: large prints them in its
    /// tail, above the footer; other families get none and the frame prints them below.
    @ViewBuilder let content: ([WidgetPastResetNote]) -> Content

    /// The gap above a freshness line: the style bodies' 6pt caption rhythm (WCF7 rows).
    private let lineGap: CGFloat = 6

    var body: some View {
        if recipe.pastResetNotes.isEmpty, !recipe.isDimmed {
            content([])
        } else {
            VStack(alignment: .leading, spacing: lineGap) {
                if recipe.pastResetNotes.isEmpty {
                    fill(content([]))
                } else {
                    ViewThatFits(in: .vertical) {
                        ForEach(Array(recipe.pastResetNoteRungs.enumerated()), id: \.offset) { _, rung in
                            if recipe.family == .large {
                                fill(content(rung))
                            } else {
                                VStack(alignment: .leading, spacing: lineGap) {
                                    fill(content([]))
                                    HeadroomWidgetPastResetNotes(notes: rung, family: recipe.family)
                                }
                            }
                        }
                        fill(content([]))
                    }
                }
                if recipe.isDimmed {
                    HeadroomWidgetFittingCaption(recipe.dimmedCaptions, size: WidgetTypeScale.scale(for: recipe.family).footer, ink: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func fill(_ view: Content) -> some View {
        view.frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

/// R11: one line per note, each trying its wording longest first (WCF7).
struct HeadroomWidgetPastResetNotes: View {
    let notes: [WidgetPastResetNote]
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(notes) { note in
                HeadroomWidgetFittingCaption(note.captions, size: WidgetTypeScale.scale(for: family).countdown, ink: .countdown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
