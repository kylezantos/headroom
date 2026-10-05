import SwiftUI

/// U8 (R1–R6, KTD3): the popover's provider card at phone scale. One opaque tile per provider
/// with every account stacked inside it, main first in the Mac's order (U3-A), each drawn
/// from the shared identity row, meter rows and plan capsule. Every popover size and gap is
/// multiplied by the host's one `PhoneScale` factor; the tile keeps the phone's own r17
/// surface (P29).
enum PhoneCardMetrics {
    /// Popover literals (`ProviderCardView`), multiplied by the phone scale at use.
    static let cardPadding: CGFloat = 13
    /// G3/T1A: the gap that separates one account from the next inside a card.
    static let accountGap: CGFloat = 26
    /// T1A/FS1: meter row gaps, Micro 10 and Full 12 (`UsageBarsStack`).
    static let microRowGap: CGFloat = 10
    static let fullRowGap: CGFloat = 12
    /// The skeleton's rhythm (`ProviderCardView.pendingSkeleton`).
    static let skeletonGap: CGFloat = 9
    /// V13b: a sentence and the dimmed rows it keeps.
    static let sentenceToMetersGap: CGFloat = 6
    /// The ladder lines sit a row step under the stack they close.
    static let footerGap: CGFloat = 14
    /// The phone's status glyph: the sentence's size plus its cap-height pad (mock `sent + 2.5`).
    static let statusGlyphSize: CGFloat = 13
    static let statusGlyphGap: CGFloat = 7
}

/// What every card on one screen shares.
struct PhoneCardContext {
    let display: ResolvedPhoneDisplay
    let usesAccountRows: Bool
    let widgetProviderIDs: [String]
    let ladder: CompanionDropLadder
    let surfaceDimmed: Bool
    let now: Date
    /// KTD3: the host's one `@ScaledMetric` factor.
    let scale: CGFloat
    let onTruncatedTitle: (DisclosedTitle) -> Void
}

/// The full resolved title handed to the disclosure sheet (U3 step 6). Never an email.
struct DisclosedTitle: Identifiable, Equatable {
    let providerID: String
    let providerName: String
    let title: String

    var id: String { "\(providerID)|\(title)" }
}

struct PhoneProviderCard: View {
    let provider: CompanionResolvedProvider
    let context: PhoneCardContext

    private var scale: CGFloat { context.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let capability = provider.capabilityAttention {
                capabilityHeader(capability)
                    .padding(.bottom, PhoneCardMetrics.accountGap * scale)
            }
            if provider.accounts.isEmpty {
                providerSkeleton
            }
            // G3: the inter-account gap chunks accounts without chrome; each section owns its
            // identity, so there is no provider header or account counter.
            VStack(alignment: .leading, spacing: PhoneCardMetrics.accountGap * scale) {
                ForEach(provider.accounts) { account in
                    PhoneAccountSection(
                        provider: provider,
                        account: account,
                        context: context,
                        showsMark: provider.capabilityAttention == nil
                    )
                }
            }
            footer
        }
        .padding(PhoneCardMetrics.cardPadding * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .headroomTile()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("headroom.provider.\(provider.id)")
    }

    /// R2C22: a capability problem belongs to the provider, not an account, so the card
    /// names its provider once with the line, and the account rows beneath keep the mark
    /// slot empty.
    private func capabilityHeader(_ attention: CompanionAttention) -> some View {
        VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToSentenceGap * scale) {
            providerIdentityRow
            PhoneStatusLine(text: CompanionAttentionCopy.account(attention), scale: scale)
        }
    }

    /// KTD6.3/P24: a provider with no usable key is a skeleton that becomes "Waiting for
    /// your Mac" once the app's freshness rule dims. No spinner: nothing here is working.
    private var providerSkeleton: some View {
        VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToMetersGap * scale) {
            providerIdentityRow
            PhoneSkeletonBody(
                format: context.display.meterStyle.format,
                line: provider.showsWaitingForMac(surfaceDimmed: context.surfaceDimmed)
                    ? CompanionCardCopy.waitingForMac
                    : CompanionCardPresentation.pendingLine(surfaceDimmed: context.surfaceDimmed),
                scale: scale
            )
        }
    }

    private var providerIdentityRow: some View {
        IdentityRow(
            providerID: ProviderID(provider.id),
            title: provider.displayName,
            planLabel: nil,
            isMenuBarAccount: false,
            isStale: false,
            email: nil,
            showsPersistentEmail: false,
            showsConnectedChip: false,
            scale: scale
        ) { slot in
            ProviderLogoView(providerID: provider.id, slot: slot)
        }
    }

    /// KTD7: "Model rows are on your Mac" and "N more on your Mac", plain and neutral.
    @ViewBuilder private var footer: some View {
        let lines = CompanionCardPresentation.footerLines(for: provider, ladder: context.ladder)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: IdentityRowMetrics.identityToSentenceGap * scale) {
                ForEach(lines, id: \.self) { line in
                    StatusSentence(text: line, severity: .neutral, scale: scale)
                        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
                }
            }
            .padding(.top, PhoneCardMetrics.footerGap * scale)
        }
    }
}

/// One account inside a card: the shared identity row, then its meters, its typed line or
/// its skeleton (R2–R5).
struct PhoneAccountSection: View {
    let provider: CompanionResolvedProvider
    let account: CompanionResolvedAccount
    let context: PhoneCardContext
    var showsMark = true

    /// R5: the phone's capsule opens on tap (there is no hover on iPhone).
    @State private var isCapsuleOpen = false
    @State private var showsWidgetNote = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { context.scale }

    private var title: String {
        CompanionCardPresentation.title(for: account, in: provider, usesAccountRows: context.usesAccountRows)
    }

    private var identifier: String { "headroom.account.\(provider.id).\(account.id)" }

    var body: some View {
        let state = CompanionCardPresentation.body(for: account, title: title)
        VStack(alignment: .leading, spacing: identityGap(for: state) * scale) {
            identityRow
            content(state)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) account")
        .accessibilityIdentifier(identifier)
        // M4A/S2A: a body swap (pending → live, live → signed out) crossfades; the section's
        // height inside the stack is movement, so Reduce Motion snaps it.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
            value: account.freshness
        )
    }

    /// CMM4: 4 over meters or the skeleton that stands in for them, 6 over a sentence.
    private func identityGap(for body: CompanionAccountBody) -> CGFloat {
        if case .attention = body { return IdentityRowMetrics.identityToSentenceGap }
        return IdentityRowMetrics.identityToMetersGap
    }

    private var identityRow: some View {
        let showsGlyph = CompanionCardPresentation.showsWidgetGlyph(
            account: account, in: provider, title: title,
            usesAccountRows: context.usesAccountRows, widgetProviderIDs: context.widgetProviderIDs)
        let hasBankedResets = (account.bankedResets ?? 0) > 0
        return IdentityRow(
            providerID: ProviderID(provider.id),
            title: title,
            planLabel: account.planName,
            isMenuBarAccount: false,
            isStale: CompanionCardPresentation.showsStaleChip(account),
            email: nil,
            showsPersistentEmail: false,
            showsConnectedChip: false,
            showsMark: showsMark,
            bankedResets: account.bankedResets,
            isCritical: CompanionCardPresentation.autoOpensPlanCapsule(account),
            isRevealing: isCapsuleOpen,
            scale: scale,
            onTruncatedTitle: { full in
                context.onTruncatedTitle(
                    DisclosedTitle(providerID: provider.id, providerName: provider.displayName, title: full))
            },
            onPlanCapsuleTap: hasBankedResets ? { isCapsuleOpen.toggle() } : nil,
            accessoryPlacement: .afterChips,
            accessibilityIdentifierPrefix: identifier
        ) { slot in
            ProviderLogoView(providerID: provider.id, slot: slot)
        } accessory: {
            if showsGlyph {
                widgetGlyphButton
            }
        }
    }

    /// U3-A: the account the widgets follow. A tap explains it; Make Main lives on the Mac.
    private var widgetGlyphButton: some View {
        Button {
            showsWidgetNote = true
        } label: {
            PhoneWidgetGlyph(scale: scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Widgets follow this account")
        .accessibilityIdentifier("headroom.widget-glyph.\(provider.id)")
        .popover(isPresented: $showsWidgetNote) {
            Text(CompanionCardCopy.widgetFollows)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(16)
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("headroom.widget-glyph.note")
        }
    }

    @ViewBuilder private func content(_ body: CompanionAccountBody) -> some View {
        switch body {
        case .meters(let dimmed):
            meterRows(dimmed: dimmed)
        case .attention(let text, let keepsMeters):
            VStack(alignment: .leading, spacing: PhoneCardMetrics.sentenceToMetersGap * scale) {
                PhoneStatusLine(text: text, scale: scale)
                if keepsMeters {
                    meterRows(dimmed: true)
                }
            }
        case .pending:
            PhoneSkeletonBody(
                format: context.display.meterStyle.format,
                line: CompanionCardPresentation.pendingLine(surfaceDimmed: context.surfaceDimmed),
                scale: scale
            )
        }
    }

    private func meterRows(dimmed: Bool) -> some View {
        PhoneMeterRows(
            windows: CompanionCardPresentation.rows(context.display.appWindows(account.windows)),
            display: context.display,
            now: context.now,
            dimmed: dimmed,
            arrivalKey: AccountKey(
                providerID: ProviderID(provider.id),
                accountID: AccountID(account.accountID ?? AccountID.primary.raw)),
            scale: scale
        )
    }
}

/// The popover's meter stack at phone scale (`UsageBarsStack`).
struct PhoneMeterRows: View {
    let windows: [WidgetWindowSummary]
    let display: ResolvedPhoneDisplay
    let now: Date
    let dimmed: Bool
    let arrivalKey: AccountKey
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if windows.isEmpty {
                Text(CompanionCardCopy.noUsageData)
                    .font(.system(size: StatusSentence.size * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: rowGap * scale) {
                    // RI1: rows keyed by kind (and occurrence), so a row that arrives or
                    // leaves fades instead of handing its neighbour another window's value.
                    ForEach(Self.keyed(windows), id: \.key) { row in
                        UsageBarView(
                            reading: UsageMeterReading(widgetSummary: row.window),
                            percentageMode: display.percentageMode,
                            now: now,
                            meterStyle: display.meterStyle,
                            dimmed: dimmed,
                            arrivalKey: arrivalKey,
                            scale: scale
                        )
                        .transition(HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion))
                    }
                }
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                    value: windows.map(\.kind)
                )
            }
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
    }

    private var rowGap: CGFloat {
        display.meterStyle.format == .micro ? PhoneCardMetrics.microRowGap : PhoneCardMetrics.fullRowGap
    }

    static func keyed(_ windows: [WidgetWindowSummary]) -> [(key: String, window: WidgetWindowSummary)] {
        var seen: [String: Int] = [:]
        return windows.map { window in
            let occurrence = seen[window.id, default: 0]
            seen[window.id] = occurrence + 1
            return (key: "\(window.id)#\(occurrence)", window: window)
        }
    }
}

/// P39/P40: the popover's unboxed status line for the phone — a Mac glyph in the tertiary
/// ink and the typed sentence in the neutral attention ink. There is nothing to act on here;
/// the line says what to do on the Mac.
struct PhoneStatusLine: View {
    let text: String
    let scale: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PhoneCardMetrics.statusGlyphGap * scale) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: PhoneCardMetrics.statusGlyphSize * scale, weight: .regular))
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                .accessibilityHidden(true)
            StatusSentence(text: text, severity: .attention, indented: false, scale: scale)
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
    }
}

/// P24/R8: static skeleton meters and the waiting line. No spinner and no pulse.
struct PhoneSkeletonBody: View {
    let format: GaugeFormat
    let line: String
    let scale: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: PhoneCardMetrics.skeletonGap * scale) {
            SkeletonMeter(labelWidth: 72, valueWidth: 42, format: format, scale: scale)
                .accessibilityHidden(true)
            SkeletonMeter(labelWidth: 86, valueWidth: 36, format: format, scale: scale)
                .accessibilityHidden(true)
            Text(line)
                .font(.system(size: StatusSentence.size * scale, weight: .medium))
                .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
    }
}

/// U3-A: the widget glyph from the approved mock — two small tiles over one wide one, drawn
/// at the capsule label's size so it reads as one more chip on the identity line.
struct PhoneWidgetGlyph: View {
    let scale: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = (IdentityRowMetrics.capsuleLabelSize + 1) * scale
        Canvas { context, size in
            let unit = size.width / 12
            let line = 1.2 * unit
            let radius = 1.3 * unit
            let tiles = [
                CGRect(x: 0.6, y: 0.6, width: 4.6, height: 4.6),
                CGRect(x: 6.8, y: 0.6, width: 4.6, height: 4.6),
                CGRect(x: 0.6, y: 6.8, width: 10.8, height: 4.6),
            ]
            for tile in tiles {
                let rect = CGRect(x: tile.minX * unit, y: tile.minY * unit,
                                  width: tile.width * unit, height: tile.height * unit)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: radius),
                    with: .color(ProviderStyle.tertiaryText(scheme: scheme)),
                    lineWidth: line)
            }
        }
        .frame(width: side, height: side)
        // A 13pt glyph is too small a target; the hit area grows without moving the layout.
        .contentShape(Rectangle().inset(by: -10 * scale))
    }
}
