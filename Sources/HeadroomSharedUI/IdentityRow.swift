import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
import HeadroomWidgetSharedUI
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif

/// The one identity treatment used for provider-name and account-name rows (KTD9).
/// The mark owns the only brand color; account metadata and state remain neutral.
///
/// KTD1/KTD2 (iOS parity): generic over its mark, like `HeadroomWidgetIdentityRow<Mark>`, so
/// each app passes its own `ProviderLogoView`, and over a trailing accessory the Mac uses
/// for its per-account loading pill. Measurement and optics are CoreText, and `scale`
/// carries KTD3's one type unit through the title, gaps, mark slot, gutter and capsules.
public struct IdentityRow<Mark: View, Accessory: View>: View {
    public let providerID: ProviderID
    public let title: String
    public let planLabel: String?
    public let isMenuBarAccount: Bool
    public let isStale: Bool
    public let email: String?
    public let showsPersistentEmail: Bool
    public let showsConnectedChip: Bool
    /// R2C22: the capability card stamps the provider mark on its own header row *and* on
    /// every account row beneath it, so "✳ Claude" sat 7pt above "✳ Personal". A nested
    /// account row hides its mark and keeps the slot, so the title column never shifts.
    public var showsMark: Bool = true
    public var bankedResets: Int? = nil
    public var isCritical: Bool = false
    public var isRevealing: Bool = false
    /// KTD3: the phone's one Dynamic Type unit over the popover ramp; the Mac passes 1.
    public var scale: CGFloat = 1
    /// U3: where a host shows the full account name once the title has truncated. The Mac
    /// passes nil and keeps the row tooltip; the phone turns only a truncated title into a
    /// neutral text button that hands the full resolved title to its native disclosure. The
    /// plan capsule and any accessory keep their own taps.
    public var onTruncatedTitle: ((String) -> Void)? = nil
    private let mark: (CGFloat) -> Mark
    private let accessory: () -> Accessory

    /// `mark` receives the slot's side, already scaled; the host sizes its logo to it.
    public init(
        providerID: ProviderID,
        title: String,
        planLabel: String?,
        isMenuBarAccount: Bool,
        isStale: Bool,
        email: String?,
        showsPersistentEmail: Bool,
        showsConnectedChip: Bool,
        showsMark: Bool = true,
        bankedResets: Int? = nil,
        isCritical: Bool = false,
        isRevealing: Bool = false,
        scale: CGFloat = 1,
        onTruncatedTitle: ((String) -> Void)? = nil,
        @ViewBuilder mark: @escaping (CGFloat) -> Mark,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.providerID = providerID
        self.title = title
        self.planLabel = planLabel
        self.isMenuBarAccount = isMenuBarAccount
        self.isStale = isStale
        self.email = email
        self.showsPersistentEmail = showsPersistentEmail
        self.showsConnectedChip = showsConnectedChip
        self.showsMark = showsMark
        self.bankedResets = bankedResets
        self.isCritical = isCritical
        self.isRevealing = isRevealing
        self.scale = scale
        self.onTruncatedTitle = onTruncatedTitle
        self.mark = mark
        self.accessory = accessory
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// PB11: whether the tail truncation actually bit. Measured, not guessed — SwiftUI has
    /// no "did this Text truncate" signal, so the rendered width is compared against the
    /// string's intrinsic width in the same font.
    @State private var titleIsTruncated = false

    @ViewBuilder public var body: some View {
        let email = normalizedEmail
        if let tooltip = rowHelp(email: email) {
            row(email: email)
                .help(tooltip)
        } else {
            row(email: email)
        }
    }

    private func row(email: String?) -> some View {
        HStack(spacing: IdentityRowMetrics.spacing * scale) {
            if showsMark {
                mark(markSlot)
            } else {
                // R2C22: the slot stays reserved, so a nested row's title lands on the same
                // axis as the header row's above it.
                Color.clear.frame(width: markSlot, height: markSlot)
            }
            titleView
            if planDisplayName != nil || (bankedResets ?? 0) > 0 {
                PlanCapsule(
                    planDisplayName: planDisplayName,
                    bankedResets: bankedResets,
                    isCritical: isCritical,
                    isRevealing: isRevealing,
                    scale: scale
                )
            }
            // CMM9 (Kyle): the state chips sit *next to* the plan pill, leading-aligned,
            // rather than pushed to the row's trailing edge — one chip run reading
            // "Work · Pro · Stale" in order, not a tier on the left and a warning on the right.
            if isStale {
                staleTag
                    // RM1: the freshness scope around it is `.movement`, so the tag keeps
                    // its fade under Reduce Motion on its own.
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
            if showsConnectedChip {
                ConnectedChip(scale: scale)
                    .transition(.connectedChip(reduceMotion: reduceMotion))
            }
            if showsPersistentEmail, let email {
                Text(email)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            Spacer(minLength: 6 * scale)
            accessory()
        }
        // L4B: trailing controls stop level with the meter rows below them.
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentity(email: email))
        // U3: VoiceOver reaches the full name through the same host disclosure.
        .accessibilityActions {
            if let onTruncatedTitle, titleIsTruncated {
                Button("Show Full Name") { onTruncatedTitle(title) }
            }
        }
    }

    private var markSlot: CGFloat { IdentityRowMetrics.markSlotWidth * scale }

    /// T1A sized this off Kyle's Paper mock at 15pt on the `accountTitle` ink so the name
    /// labels its meters instead of competing with the popover's own 20pt bold header. G1
    /// restored `.semibold` — `.medium` on a recessive grey lost the row's anchor — and the
    /// ink is now the user's `AccountTitleInk` choice (neutral grey or the provider's brand
    /// tint). Kerning is unchanged throughout.
    private var titleText: some View {
        Text(title)
            .font(.system(size: IdentityRowMetrics.titleSize * scale, weight: .semibold))
            .kerning(IdentityRowMetrics.titleKerning * scale)
            .accountTitleInk(for: providerID)
            .lineLimit(1)
            .truncationMode(.tail)
            // PB11: measured on the Text itself, before the optical pull-back, so the
            // comparison is against the width the string was actually given.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                titleIsTruncated = IdentityRowText.titleIsTruncated(title, renderedWidth: width, scale: scale)
            }
    }

    /// U3: only a truncated title becomes a button, and only where the host offers a
    /// disclosure; everywhere else it is the plain title it always was.
    private var titleView: some View {
        Group {
            if let onTruncatedTitle, titleIsTruncated {
                Button { onTruncatedTitle(title) } label: { titleText }
                    .buttonStyle(.plain)
            } else {
                titleText
            }
        }
        // OA1: "Personal" and "Work" carry side bearings 0.66pt apart at this size, so
        // without this the title column visibly jitters account to account.
        .widgetOpticalLeading(title, size: IdentityRowMetrics.titleSize * scale, weight: .semibold)
        // PB11: the account name identifies the row; the email is a detail the tooltip
        // has always carried anyway. Outranking the email's `layoutPriority(1)` stops a
        // long address eating the name it belongs to.
        .layoutPriority(2)
    }

    /// L5D: the main account carries no visible marker. Order already says it — main is
    /// always its provider's first row — and a second capsule beside the plan badge made a
    /// busy title cluster busier, so the fact moves to this row's tooltip and to VoiceOver.
    /// One `.help` per row: nested help modifiers let the innermost win on macOS, so a
    /// separate tooltip on the title would swallow the email the row has always shown.
    ///
    /// PB11: a truncated title joins it. The tail ellipsis is the only place the row loses
    /// information the user cannot recover any other way, and the row already owns the one
    /// tooltip on this line.
    private func rowHelp(email: String?) -> String? {
        IdentityRowText.helpLines(
            title: title,
            titleIsTruncated: titleIsTruncated,
            email: email,
            isMenuBarAccount: isMenuBarAccount,
            bankedHelp: PlanCapsulePresentation.helpLine(count: bankedResets)
        )
    }

    private var normalizedEmail: String? {
        guard let email, !email.isEmpty else { return nil }
        return email
    }

    /// Raw ids (`prolite`, `SuperGrok`) never reach the badge — Core owns the humanizing
    /// so the lenient provider models keep their verbatim value (#709).
    private var planDisplayName: String? {
        PlanLabelPresentation.displayName(planLabel)
    }

    /// S2B removed the status glyphs and left severity to the sentence's ink — but a
    /// transient-stale row renders no sentence at all (`stateContent` keeps its dimmed
    /// meters), so this tag survives as that state's only visible signal. C6A gives it the
    /// same 18pt as the plan pill beside it.
    private var staleTag: some View {
        Text("Stale")
            .kerning(IdentityRowMetrics.capsuleLabelKerning * scale)
            // PA7: type comes from `identityCapsule` now.
            .foregroundStyle(.secondary)
            // R2C17: a state chip, so it keeps its fill and takes the hairline that tells it
            // apart from the flat plan label now sitting beside it.
            .identityCapsule(
                fill: IdentityCapsuleStyle.staleFill,
                horizontalPadding: 5,
                border: IdentityCapsuleStyle.stateBorder,
                scale: scale
            )
    }

    private func accessibilityIdentity(email: String?) -> String {
        IdentityRowText.accessibilityParts(
            title: title,
            planDisplayName: planDisplayName,
            isMenuBarAccount: isMenuBarAccount,
            isStale: isStale,
            email: email,
            showsConnectedChip: showsConnectedChip,
            bankedPhrase: PlanCapsulePresentation.accessibilityPhrase(count: bankedResets)
        )
    }
}

public extension IdentityRow where Accessory == EmptyView {
    /// A row with nothing trailing: the phone, the spend card and provider header rows.
    init(
        providerID: ProviderID,
        title: String,
        planLabel: String?,
        isMenuBarAccount: Bool,
        isStale: Bool,
        email: String?,
        showsPersistentEmail: Bool,
        showsConnectedChip: Bool,
        showsMark: Bool = true,
        bankedResets: Int? = nil,
        isCritical: Bool = false,
        isRevealing: Bool = false,
        scale: CGFloat = 1,
        onTruncatedTitle: ((String) -> Void)? = nil,
        @ViewBuilder mark: @escaping (CGFloat) -> Mark
    ) {
        self.init(
            providerID: providerID, title: title, planLabel: planLabel,
            isMenuBarAccount: isMenuBarAccount, isStale: isStale, email: email,
            showsPersistentEmail: showsPersistentEmail, showsConnectedChip: showsConnectedChip,
            showsMark: showsMark, bankedResets: bankedResets, isCritical: isCritical,
            isRevealing: isRevealing, scale: scale, onTruncatedTitle: onTruncatedTitle,
            mark: mark, accessory: { EmptyView() }
        )
    }
}

/// The identity row's pure text decisions — tooltip, VoiceOver phrase and the truncation
/// test — kept off the generic view so tests and hosts can reach them without naming a mark.
public enum IdentityRowText {
    /// L5D: with the badge gone, the row tooltip and this VoiceOver phrase are the only
    /// places the fact is stated — keep them in step.
    public static let mainAccountHelp = "Main account — shown in the menu bar and widgets"

    /// PB11: the width the title wants, from the same font, size and kerning it renders in
    /// (CoreText, matching `NSString.size(withAttributes:)` on the Mac). Kept separate from
    /// the comparison below so the predicate is testable without a render.
    public static func titleIntrinsicWidth(_ title: String, scale: CGFloat = 1) -> CGFloat {
        HeadroomWidgetFontMetrics.textWidth(
            title,
            size: IdentityRowMetrics.titleSize * scale,
            weight: .semibold,
            kerning: IdentityRowMetrics.titleKerning * scale
        )
    }

    /// True once the row is narrower than the string needs. The half-point slack keeps
    /// sub-pixel layout rounding from claiming a truncation that never happened; a zero
    /// width is the pre-layout pass, not a truncation.
    public static func titleIsTruncated(_ title: String, renderedWidth: CGFloat, scale: CGFloat = 1) -> Bool {
        guard renderedWidth > 0 else { return false }
        return renderedWidth + 0.5 < titleIntrinsicWidth(title, scale: scale)
    }

    /// One tooltip, in a fixed order: truncated title, email, main-account note, banked resets.
    public static func helpLines(
        title: String,
        titleIsTruncated: Bool,
        email: String?,
        isMenuBarAccount: Bool,
        bankedHelp: String?
    ) -> String? {
        var lines: [String] = []
        if titleIsTruncated { lines.append(title) }
        if let email { lines.append(email) }
        if isMenuBarAccount { lines.append(mainAccountHelp) }
        if let bankedHelp { lines.append(bankedHelp) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public static func accessibilityParts(
        title: String,
        planDisplayName: String?,
        isMenuBarAccount: Bool,
        isStale: Bool,
        email: String?,
        showsConnectedChip: Bool,
        bankedPhrase: String?
    ) -> String {
        var parts = [title]
        if let planDisplayName { parts.append("\(planDisplayName) plan") }
        if isMenuBarAccount { parts.append("Main account, shown in the menu bar and widgets") }
        if isStale { parts.append("Stale") }
        if let email { parts.append("signed in as \(email)") }
        if showsConnectedChip { parts.append("Connected") }
        if let bankedPhrase { parts.append(bankedPhrase) }
        return parts.joined(separator: ", ")
    }
}

private extension AnyTransition {
    /// M8A: a sign-in payoff earns a little arrival, so the chip enters on opacity plus a
    /// 0.96 scale; it leaves on opacity alone, because an exit that announces itself twice
    /// reads as an error. S2A drops the scale under Reduce Motion and keeps the fade.
    static func connectedChip(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity
        )
    }
}

private struct ConnectedChip: View {
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: "checkmark")
                // R2B3: 9pt bold beside a 10.5 medium label was the heavier of the two at the
                // smaller size; semibold puts the glyph's stroke back in step with its word.
                .font(.system(size: 9 * scale, weight: .semibold))
            // PA7: the tallest label of the six took the shared role too; only the
            // checkmark keeps a font of its own, because it is a glyph, not a label.
            Text("Connected")
                .kerning(IdentityRowMetrics.capsuleLabelKerning * scale)
        }
        // U3: the shared connected tokens, identical to the Mac setup style's.
        .foregroundStyle(ProviderStyle.connectedInk(dark: scheme == .dark))
        // C6A: was the tallest of the three capsules at ~19–20pt; now the same 18 as the rest.
        .identityCapsule(
            fill: ProviderStyle.connectedBackground(dark: scheme == .dark),
            horizontalPadding: 8,
            scale: scale
        )
    }
}
