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
    /// L5D: the provider's main row when it has two or more accounts. It drives the
    /// "Main account" tooltip line and VoiceOver phrase, never the glyph.
    public let isMenuBarAccount: Bool
    public let isStale: Bool
    public let email: String?
    public let showsPersistentEmail: Bool
    public let showsConnectedChip: Bool
    /// R2C22: the capability card stamps the provider mark on its own header row *and* on
    /// every account row beneath it, so "✳ Claude" sat 7pt above "✳ Personal". A nested
    /// account row hides its mark and keeps the slot, so the title column never shifts.
    public var showsMark: Bool = true
    /// CA-MB3: this row's reading feeds a menu-bar pill (`IdentityRowText.feedsMenuBar`), so
    /// it draws `MenuBarSourceGlyph`. Separate from `isMenuBarAccount`: a main account whose
    /// provider is not in the menu bar is still the main account. False draws none.
    public var showsMenuBarSourceGlyph: Bool = false
    public var bankedResets: Int? = nil
    public var isCritical: Bool = false
    public var isRevealing: Bool = false
    /// Default-login plan U8 (R7, R21): a remembered account's "Last read 2 min ago"
    /// (`Countdown.lastReadLabel`). Set, it draws as a state capsule in the place the "Stale"
    /// capsule takes, and "Stale" is never drawn beside it. Nil, the default, leaves every
    /// existing row exactly as it was.
    public var lastReadLabel: String? = nil
    /// CA-P3: when a stale engine row was last read, so its chip can say "Last read" with its
    /// age instead of "Stale". Nil, the default, draws "Stale" as today.
    public var staleReadAge: IdentityRowReadAge? = nil
    /// KTD3: the phone's one Dynamic Type unit over the popover ramp; the Mac passes 1.
    public var scale: CGFloat = 1
    /// U3: where a host shows the full account name once the title has truncated. The Mac
    /// passes nil and keeps the row tooltip; the phone turns only a truncated title into a
    /// neutral text button that hands the full resolved title to its native disclosure. The
    /// plan capsule and any accessory keep their own taps.
    public var onTruncatedTitle: ((String) -> Void)? = nil
    /// U8 (R5): where the plan capsule is a control. The phone has no hover, so a tap toggles
    /// the banked-reset detail; the Mac passes nil and keeps hover. Only the capsule takes
    /// the tap — the title's disclosure and the accessory keep their own.
    public var onPlanCapsuleTap: (() -> Void)? = nil
    /// U8 (U3-A): where the accessory sits. The Mac's loading pill trails the row; the phone's
    /// widget glyph reads as one more chip after the plan capsule.
    public var accessoryPlacement: IdentityRowAccessoryPlacement = .trailing
    /// U8: a stable accessibility identifier stem for the row's own controls (".title",
    /// ".plan"), so UI tests can reach them. Nil adds none.
    public var accessibilityIdentifierPrefix: String? = nil
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
        showsMenuBarSourceGlyph: Bool = false,
        bankedResets: Int? = nil,
        isCritical: Bool = false,
        isRevealing: Bool = false,
        lastReadLabel: String? = nil,
        staleReadAge: IdentityRowReadAge? = nil,
        scale: CGFloat = 1,
        onTruncatedTitle: ((String) -> Void)? = nil,
        onPlanCapsuleTap: (() -> Void)? = nil,
        accessoryPlacement: IdentityRowAccessoryPlacement = .trailing,
        accessibilityIdentifierPrefix: String? = nil,
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
        self.showsMenuBarSourceGlyph = showsMenuBarSourceGlyph
        self.bankedResets = bankedResets
        self.isCritical = isCritical
        self.isRevealing = isRevealing
        self.lastReadLabel = lastReadLabel
        self.staleReadAge = staleReadAge
        self.scale = scale
        self.onTruncatedTitle = onTruncatedTitle
        self.onPlanCapsuleTap = onPlanCapsuleTap
        self.accessoryPlacement = accessoryPlacement
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.mark = mark
        self.accessory = accessory
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.headroomTuning) private var tuning
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
        HStack(spacing: tuning.markGap * scale) {
            if showsMark {
                mark(markSlot)
            } else {
                // R2C22: the slot stays reserved, so a nested row's title lands on the same
                // axis as the header row's above it.
                Color.clear.frame(width: markSlot, height: markSlot)
            }
            titleView
            if planDisplayName != nil || (bankedResets ?? 0) > 0 {
                planCapsule
            }
            // CMM9 (Kyle): the state chips sit *next to* the plan pill, leading-aligned,
            // rather than pushed to the row's trailing edge — one chip run reading
            // "Work · Pro · Stale" in order, not a tier on the left and a warning on the right.
            if let lastReadLabel {
                // U8: a remembered row's one state chip; it replaces "Stale" rather than
                // joining it, so the row says what it is once.
                stateTag(lastReadLabel)
                    // CA-P3 (UX-01): the chip says why nothing reads the account. Nested
                    // help wins on macOS, so the row's own tooltip is untouched elsewhere.
                    .help(Countdown.rememberedReadHelp(for: providerID))
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
                    .accessibilityHidden(containsControls)
            } else if isStale {
                staleTag
                    // RM1: the freshness scope around it is `.movement`, so the tag keeps
                    // its fade under Reduce Motion on its own.
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
                    // U8: in a containing row the title already says "Stale".
                    .accessibilityHidden(containsControls)
            }
            if showsConnectedChip {
                ConnectedChip(scale: scale)
                    .transition(.connectedChip(reduceMotion: reduceMotion))
            }
            if showsMenuBarSourceGlyph {
                // CA-MB3: which account feeds the pill, said where the user looks when they
                // wonder. Hosts set it only when the provider has two or more accounts
                // (`IdentityRowText.feedsMenuBar`), so one account draws none.
                MenuBarSourceGlyph(scale: scale)
                    .accessibilityHidden(true)
            }
            if showsPersistentEmail, let email {
                Text(email)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            if accessoryPlacement == .afterChips {
                accessory()
            }
            Spacer(minLength: 6 * scale)
            if accessoryPlacement == .trailing {
                accessory()
            }
        }
        // L4B: trailing controls stop level with the meter rows below them.
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
        .modifier(IdentityRowAccessibility(
            containsControls: containsControls,
            label: accessibilityIdentity(email: email),
            fullTitleAction: titleIsTruncated ? onTruncatedTitle.map { action in { action(title) } } : nil
        ))
    }

    /// U8: a row whose title or capsule is a control (the phone) keeps those controls as their
    /// own accessibility elements, so each one is reachable and does only its own job; the
    /// title carries the row's identity phrase. A display-only row (the Mac) stays one
    /// combined element, exactly as before.
    private var containsControls: Bool {
        onPlanCapsuleTap != nil || onTruncatedTitle != nil
    }

    @ViewBuilder private var planCapsule: some View {
        let capsule = PlanCapsule(
            planDisplayName: planDisplayName,
            bankedResets: bankedResets,
            isCritical: isCritical,
            isRevealing: isRevealing,
            scale: scale
        )
        if let onPlanCapsuleTap {
            Button(action: onPlanCapsuleTap) {
                capsule
                    // CA-I9 (IOS-09): the phone's only tappable chip was about 21pt tall. The
                    // hit area reaches 44pt without moving a pixel: padding the content shape
                    // out, then laying it back in. The leading outset stays inside the gap so
                    // the title's own button keeps every point it had.
                    .padding(.vertical, Self.planTapOutsetVertical * scale)
                    .padding(.leading, Self.planTapOutsetLeading * scale)
                    .padding(.trailing, Self.planTapOutsetTrailing * scale)
                    .contentShape(Rectangle())
                    .padding(.vertical, -Self.planTapOutsetVertical * scale)
                    .padding(.leading, -Self.planTapOutsetLeading * scale)
                    .padding(.trailing, -Self.planTapOutsetTrailing * scale)
            }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan")
                .accessibilityValue(planCapsuleSpokenValue)
                .accessibilityIdentifier(controlIdentifier("plan"))
        } else {
            capsule
                .accessibilityHidden(containsControls)
        }
    }

    /// What the capsule shows right now: "Plus", or "Plus · 2 resets" while it is open.
    private var planCapsuleSpokenValue: String {
        PlanCapsulePresentation.resolve(
            planDisplayName: planDisplayName,
            bankedResets: bankedResets,
            isHovering: false,
            isCritical: isCritical,
            isRevealing: isRevealing
        ).visibleLabel
    }

    private func controlIdentifier(_ suffix: String) -> String {
        accessibilityIdentifierPrefix.map { "\($0).\(suffix)" } ?? ""
    }

    private var markSlot: CGFloat { tuning.markSlotWidth * scale }
    private var titleWeight: Font.Weight { HeadroomTuning.weight(tuning.titleWeight) }

    /// T1A sized this off Kyle's Paper mock at 15pt on the `accountTitle` ink so the name
    /// labels its meters instead of competing with the popover's own 20pt bold header. G1
    /// restored `.semibold` — `.medium` on a recessive grey lost the row's anchor — and the
    /// ink is now the user's `AccountTitleInk` choice (neutral grey or the provider's brand
    /// tint). Kerning is unchanged throughout.
    private var titleText: some View {
        Text(title)
            .font(.system(size: tuning.titleSize * scale, weight: titleWeight))
            .kerning(tuning.titleKerning * scale)
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
                    .accessibilityHint("Shows the full name")
            } else {
                titleText
            }
        }
        // U8: in a containing row the title is the row's element — its name as the label and
        // the rest of the identity phrase (plan, Stale, banked resets) as its value.
        .accessibilityLabel(title)
        .accessibilityValue(containsControls ? accessibilityDetail(email: normalizedEmail) : "")
        .accessibilityIdentifier(controlIdentifier("title"))
        // OA1: "Personal" and "Work" carry side bearings 0.66pt apart at this size, so
        // without this the title column visibly jitters account to account.
        .widgetOpticalLeading(title, size: tuning.titleSize * scale, weight: titleWeight)
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
    /// so the lenient provider models keep their verbatim value (#709). The provider picks
    /// its own id table: Codex `team` reads "Business" while Claude's Team stays "Team".
    private var planDisplayName: String? {
        PlanLabelPresentation.displayName(planLabel, provider: providerID)
    }

    /// S2B removed the status glyphs and left severity to the sentence's ink — but a
    /// transient-stale row renders no sentence at all (`stateContent` keeps its dimmed
    /// meters), so this tag survives as that state's only visible signal. C6A gives it the
    /// same 18pt as the plan pill beside it.
    ///
    /// CA-P3 (COPY-01): with `staleReadAge` set the chip says "Last read 14 min ago", the
    /// remembered row's own phrase, because "Stale" was the one state with no time on it. Its
    /// tooltip says what Headroom is doing about it. Nil keeps "Stale" for a host that has not
    /// passed an age.
    @ViewBuilder private var staleTag: some View {
        if staleReadAge != nil {
            stateTag(staleLabel)
                .help(Countdown.staleReadHelp)
        } else {
            stateTag(staleLabel)
        }
    }

    /// The stale chip's words, shared with VoiceOver so the two never differ.
    private var staleLabel: String {
        guard let staleReadAge else { return IdentityRowText.staleFallbackLabel }
        return Countdown.staleReadLabel(capturedAt: staleReadAge.capturedAt, now: staleReadAge.now)
    }

    /// CA-I9: the phone plan capsule's hit outsets. 18pt capsule + 2 × 12 ≈ 44pt at scale 1
    /// (≈ 48pt at the phone's 1.15 base). The leading 6 matches the row's gap to the title.
    static var planTapOutsetVertical: CGFloat { 12 }
    static var planTapOutsetLeading: CGFloat { 6 }
    static var planTapOutsetTrailing: CGFloat { 8 }

    /// The "Stale" capsule's recipe, shared by U8's last-read tag so the two can never drift.
    private func stateTag(_ text: String) -> some View {
        Text(text)
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

    private func accessibilityDetail(email: String?) -> String {
        IdentityRowText.accessibilityDetail(
            planDisplayName: planDisplayName,
            isMenuBarAccount: isMenuBarAccount,
            isStale: isStale,
            email: email,
            showsConnectedChip: showsConnectedChip,
            bankedPhrase: PlanCapsulePresentation.accessibilityPhrase(count: bankedResets),
            lastReadLabel: lastReadLabel,
            staleLabel: staleLabel
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
            bankedPhrase: PlanCapsulePresentation.accessibilityPhrase(count: bankedResets),
            lastReadLabel: lastReadLabel,
            staleLabel: staleLabel
        )
    }
}

/// CA-P3: a stale row's read time with the moment it is judged against, since the row has no
/// clock of its own. A nil `capturedAt` means nothing records the read.
public struct IdentityRowReadAge: Equatable, Sendable {
    public let capturedAt: Date?
    public let now: Date

    public init(capturedAt: Date?, now: Date) {
        self.capturedAt = capturedAt
        self.now = now
    }
}

/// U8: where `IdentityRow` places its accessory.
public enum IdentityRowAccessoryPlacement: Sendable {
    /// The Mac's loading pill, after the spacer on the trailing edge.
    case trailing
    /// The phone's widget glyph, leading-aligned after the plan and state chips.
    case afterChips
}

/// One combined element (display-only rows) or a container of controls (U8).
private struct IdentityRowAccessibility: ViewModifier {
    let containsControls: Bool
    let label: String
    let fullTitleAction: (() -> Void)?

    func body(content: Content) -> some View {
        if containsControls {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
                // U3: VoiceOver reaches the full name through the same host disclosure.
                .accessibilityActions {
                    if let fullTitleAction {
                        Button("Show Full Name", action: fullTitleAction)
                    }
                }
        }
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
        showsMenuBarSourceGlyph: Bool = false,
        bankedResets: Int? = nil,
        isCritical: Bool = false,
        isRevealing: Bool = false,
        lastReadLabel: String? = nil,
        staleReadAge: IdentityRowReadAge? = nil,
        scale: CGFloat = 1,
        onTruncatedTitle: ((String) -> Void)? = nil,
        onPlanCapsuleTap: (() -> Void)? = nil,
        accessibilityIdentifierPrefix: String? = nil,
        @ViewBuilder mark: @escaping (CGFloat) -> Mark
    ) {
        self.init(
            providerID: providerID, title: title, planLabel: planLabel,
            isMenuBarAccount: isMenuBarAccount, isStale: isStale, email: email,
            showsPersistentEmail: showsPersistentEmail, showsConnectedChip: showsConnectedChip,
            showsMark: showsMark, showsMenuBarSourceGlyph: showsMenuBarSourceGlyph,
            bankedResets: bankedResets, isCritical: isCritical,
            isRevealing: isRevealing, lastReadLabel: lastReadLabel, staleReadAge: staleReadAge, scale: scale, onTruncatedTitle: onTruncatedTitle,
            onPlanCapsuleTap: onPlanCapsuleTap, accessibilityIdentifierPrefix: accessibilityIdentifierPrefix,
            mark: mark, accessory: { EmptyView() }
        )
    }
}

/// The identity row's pure text decisions — tooltip, VoiceOver phrase and the truncation
/// test — kept off the generic view so tests and hosts can reach them without naming a mark.
public enum IdentityRowText {
    /// L5D: with the badge gone, the row tooltip and this VoiceOver phrase are the only
    /// places the fact is stated — keep them in step.
    /// CA-S8: two sentences, no em dash.
    public static let mainAccountHelp = "Main account. Shown in the menu bar and widgets."

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
        bankedPhrase: String?,
        lastReadLabel: String? = nil,
        staleLabel: String = staleFallbackLabel
    ) -> String {
        let detail = accessibilityDetail(
            planDisplayName: planDisplayName, isMenuBarAccount: isMenuBarAccount, isStale: isStale,
            email: email, showsConnectedChip: showsConnectedChip, bankedPhrase: bankedPhrase,
            lastReadLabel: lastReadLabel, staleLabel: staleLabel)
        return detail.isEmpty ? title : "\(title), \(detail)"
    }

    /// The stale chip's words when a host passes no read age.
    public static let staleFallbackLabel = "Stale"

    /// CA-MB3: whether a row carries the menu-bar source glyph. Only the account that feeds
    /// a pill, and only when its provider has two or more accounts: with one, the glyph is
    /// noise. Hosts pass the result as `showsMenuBarSourceGlyph`.
    public static func feedsMenuBar(isPillSource: Bool, providerAccountCount: Int) -> Bool {
        isPillSource && providerAccountCount >= 2
    }

    /// L5D: the row the "Main account" tooltip line, VoiceOver phrase and Compact label name:
    /// the provider's display primary, only when it has two or more accounts. Independent of
    /// the menu-bar selection (CA-MB3 review fix), because widgets, the phone and Make Main
    /// treat it as main whichever pill shows. Hosts pass it as `isMenuBarAccount`.
    public static func isMainAccountRow(isDisplayPrimary: Bool, providerAccountCount: Int) -> Bool {
        isDisplayPrimary && providerAccountCount >= 2
    }

    /// CA-MB3: the glyph's tooltip.
    public static let menuBarSourceHelp = "Shown in the menu bar"

    /// Everything the identity phrase says after the title, in the same order. U8: a
    /// remembered row's `lastReadLabel` takes the place of "Stale", as its capsule does.
    /// CA-P3: `staleLabel` is the chip's own words ("Last read 14 min ago"), so VoiceOver
    /// says what the chip shows.
    public static func accessibilityDetail(
        planDisplayName: String?,
        isMenuBarAccount: Bool,
        isStale: Bool,
        email: String?,
        showsConnectedChip: Bool,
        bankedPhrase: String?,
        lastReadLabel: String? = nil,
        staleLabel: String = staleFallbackLabel
    ) -> String {
        var parts: [String] = []
        if let planDisplayName { parts.append("\(planDisplayName) plan") }
        if isMenuBarAccount { parts.append("Main account, shown in the menu bar and widgets") }
        if let lastReadLabel {
            parts.append(lastReadLabel)
        } else if isStale {
            parts.append(staleLabel)
        }
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

/// CA-MB3 (MB-F): a 7×11pt copy of the menu-bar vessel, marking the account whose reading
/// feeds a pill. The wall and the liquid are both tertiary ink at the decorative level the
/// menu bar uses with no value (`LoadingMotionConstants.decorativeLevel`, `VesselGlyph`'s
/// `staticFill`), so it never claims a severity or a number. The identity row draws it 6pt
/// after its last capsule; the Compact row draws it 6pt after the account name.
public struct MenuBarSourceGlyph: View {
    public static let size = CGSize(width: 7, height: 11)
    /// `VesselGlyph`'s 1.6pt wall and 0.6pt liquid gap at 11pt wide, scaled to 7.
    static let wallWidth: CGFloat = 1
    static let liquidGap: CGFloat = 0.4

    public var scale: CGFloat = 1
    @Environment(\.colorScheme) private var scheme

    public init(scale: CGFloat = 1) {
        self.scale = scale
    }

    public var body: some View {
        let ink = ProviderStyle.tertiaryText(scheme: scheme)
        let wall = Self.wallWidth * scale
        let inset = wall + Self.liquidGap * scale
        let width = Self.size.width * scale
        let height = Self.size.height * scale
        let innerHeight = height - inset * 2
        ZStack {
            Capsule()
                .strokeBorder(ink, lineWidth: wall)
            Rectangle()
                .fill(ink)
                .frame(height: innerHeight * CGFloat(LoadingMotionConstants.decorativeLevel))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(width: width - inset * 2, height: innerHeight)
                .clipShape(Capsule())
        }
        .frame(width: width, height: height)
        .help(IdentityRowText.menuBarSourceHelp)
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
