import SwiftUI

public enum IdentityRowMetrics {
    public static let markSlotWidth: CGFloat = 15
    public static let spacing: CGFloat = 6
    /// CMM4 (Kyle, 2026-09-10): the identity row's gap to what it heads — 4 over meters,
    /// 6 over a sign-in sentence. Frame units; ≈14pt / ≈12.5pt of ink in Micro.
    public static let identityToMetersGap: CGFloat = 4
    public static let identityToSentenceGap: CGFloat = 6
    /// CMM10 (Kyle, 2026-09-10): one title recipe for account rows *and* spend rows — same
    /// ink token, same size, same kerning — so "Anthropic API" and "Personal" are one object.
    public static let titleSize: CGFloat = 15
    public static let titleKerning: CGFloat = -0.15
    /// CMM6: how far a chip row's first box hangs outside the text axis.
    public static let chipBoxOutdent: CGFloat = 1
    public static let meterContentInset = markSlotWidth + spacing
    /// L4B: the trailing gutter mirrors the label column instead of the mark. With the
    /// card's own 13pt padding this ends every identity row and every meter row 34pt from
    /// the card's right edge — the same 34pt the titles and meter labels start at — and
    /// leaves the provider mark hanging alone in its 13pt gutter.
    public static let contentTrailingInset = meterContentInset
    /// C6A: one capsule height for everything that rides an identity line. Vertical padding
    /// could not deliver it — a 10.5pt tag's line box is taller than a 9.5pt pill's, so the
    /// same `vPad 3` produced 18/19/20 — and the drift is invisible until two capsules sit
    /// side by side. An explicit height with centred text cannot drift.
    public static let capsuleHeight: CGFloat = 18

    /// PA7: one capsule *label* role to go with C6A's one capsule height. The six capsules
    /// were sharing a box while running 9.5 medium / 10 semibold / 10.5 semibold / 11
    /// semibold inside it, with kerning on two of the six — and the spend state tag swaps
    /// into the period chip's own slot, so "Rejected" changed size and weight in place where
    /// "September" had been. Capsules only read as peers if their labels are peers. Ink and
    /// fill stay per-recipe; only the type is shared.
    public static let capsuleLabelSize: CGFloat = 10.5
    public static let capsuleLabelWeight: Font.Weight = .medium
    public static let capsuleLabelKerning: CGFloat = 0.2
}

/// R2C17: one capsule was carrying four meanings — plan (Max, Pro Lite), period (September),
/// measure (Remaining balance) and the freshness *warning* (Stale) all in the same grey
/// chrome, so "Work · Pro · Stale" read the warning as a third subscription tier. Things that
/// look the same must behave the same, so the family splits: metadata is a flat label, state
/// is a filled-and-outlined chip. These are the shared values that split needs.
public enum IdentityCapsuleStyle {
    /// R2C17: the stale chip's fill, previously an untokenised `secondary.opacity(0.18)`
    /// written out once on the identity row and again in the spend view.
    public static let staleFill = Color.secondary.opacity(0.18)
    /// CMM9: the plan / period pill — a step quieter than a state chip and without its ring.
    public static let metadataFill = Color.secondary.opacity(0.12)

    /// R2C17: outlined-and-filled reads as state; flat reads as label. One hairline is the
    /// whole difference, so it lives here rather than at either call site.
    public static let stateBorder = Color.secondary.opacity(0.35)
    public static let stateBorderWidth: CGFloat = 1
}

public extension View {
    /// C6A: the one identity-line capsule. Each recipe keeps its own horizontal padding and
    /// fill; the height is not negotiable. PA7 added the label role — set through the
    /// environment, so a call site that still declares `Text.font(_:)` would silently win.
    /// None do: the six recipes were stripped when this took the type over.
    ///
    /// R2C17 added `border`, defaulted off: only a state chip is outlined.
    func identityCapsule<Fill: ShapeStyle>(
        fill: Fill,
        horizontalPadding: CGFloat,
        border: Color? = nil
    ) -> some View {
        font(.system(
            size: IdentityRowMetrics.capsuleLabelSize,
            weight: IdentityRowMetrics.capsuleLabelWeight
        ))
        // PA7: kerning is applied on each capsule Text at the call site, not here — as a
        // View modifier it leaked into the sibling layout and truncated the spend title.
        .fixedSize()
        .frame(height: IdentityRowMetrics.capsuleHeight)
        .padding(.horizontal, horizontalPadding)
        .background(fill, in: Capsule())
        .overlay {
            if let border {
                Capsule().strokeBorder(border, lineWidth: IdentityCapsuleStyle.stateBorderWidth)
            }
        }
    }

    /// The metadata half of the split — plan, period, measure.
    ///
    /// CMM9 (Kyle, 2026-09-10): back in its own pill. R2C17 had flattened it to a bare label
    /// so that only *state* chips carried a fill; Kyle wants the plan and period "in their
    /// own dip like they used to be", just styled apart from Stale — so this is a quiet fill
    /// with no ring, and the state chips keep the fill-plus-hairline recipe.
    func identityMetadataLabel() -> some View {
        identityCapsule(fill: IdentityCapsuleStyle.metadataFill, horizontalPadding: 5)
    }
}
