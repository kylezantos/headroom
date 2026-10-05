#if canImport(HeadroomCore)
import HeadroomCore
#endif
import SwiftUI

/// Design 10 / R4: one image and one line beside the date. The system styles the text and
/// ignores anything but text and one image, so the line carries no font or ink of its own.
/// `ViewThatFits` takes the recipe's longest candidate that fits; the last one truncates.
struct HeadroomWidgetLockScreenInline<Icon: View>: View {
    let recipe: LockScreenWidgetRecipe
    let icon: (LockScreenInlineImage) -> Icon
    private var environment = HeadroomWidgetLockScreenEnvironment()

    init(recipe: LockScreenWidgetRecipe, icon: @escaping (LockScreenInlineImage) -> Icon) {
        self.recipe = recipe
        self.icon = icon
    }

    /// R16: a hidden reading shows an empty vessel, never the stepped level.
    private var image: LockScreenInlineImage {
        if environment.hidesContent, case .vessel = recipe.inlineImage { return .vessel(level: 0) }
        return recipe.inlineImage
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(recipe.inlineTextCandidates.enumerated()), id: \.offset) { _, text in
                Label {
                    Text(text).privacySensitive()
                } icon: {
                    icon(image)
                }
                .headroomWidgetProbe()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recipe.accessibilityText)
    }
}
