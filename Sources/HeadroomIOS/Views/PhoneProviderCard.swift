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
    /// R11: the past-reset line takes the countdown's size (`UsageBarView` 11pt) and sits a
    /// label-to-gauge step (Full's 7, minus the line box) under the row it explains.
    static let pastResetSize: CGFloat = 11
    static let pastResetGap: CGFloat = 4
    /// Default-login R7: the "Last read …" tag takes the Mac identity row's 10pt email size.
    static let lastReadSize: CGFloat = 10
}

/// What every card on one screen shares.
struct PhoneCardContext {
    let display: ResolvedPhoneDisplay
    let usesAccountRows: Bool
    let ladder: CompanionDropLadder
    let surfaceDimmed: Bool
    let now: Date
    /// KTD3: the host's one `@ScaledMetric` factor.
    let scale: CGFloat
    let onTruncatedTitle: (DisclosedTitle) -> Void
}

/// The full resolved title handed to the disclosure sheet (U3 step 6): the Mac's
/// displayed name, an email only when the Mac names the account by email (KTD9).
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
            // CA-P3: the chip reads "Last read 14 min ago" (`staleChipLabel`), never "Stale".
            staleReadAge: IdentityRowReadAge(capturedAt: account.capturedAt, now: context.now),
            scale: scale,
            onTruncatedTitle: { full in
                context.onTruncatedTitle(
                    DisclosedTitle(providerID: provider.id, providerName: provider.displayName, title: full))
            },
            onPlanCapsuleTap: hasBankedResets ? { isCapsuleOpen.toggle() } : nil,
            accessoryPlacement: .afterChips,
            accessibilityIdentifierPrefix: identifier,
            mark: { slot in
                ProviderLogoView(providerID: provider.id, slot: slot)
            },
            accessory: { lastReadTag }
        )
    }

    /// Default-login R7/R21: a remembered row says how long ago it was read, in the Mac's
    /// words, where a stale row's chip would sit.
    @ViewBuilder private var lastReadTag: some View {
        if let label = CompanionCardPresentation.lastReadLabel(for: account, now: context.now) {
            Text(label)
                .font(.system(size: PhoneCardMetrics.lastReadSize * scale).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
                .accessibilityIdentifier("\(identifier).last-read")
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
            rows: CompanionCardPresentation.meterRows(
                context.display.appWindows(account.windows), now: context.now, isRemembered: account.isRemembered),
            display: context.display,
            isRemembered: account.isRemembered,
            now: context.now,
            // KTD15: the surface's dimming and the account's own stale treatment are one
            // demotion; a stale row under a dimmed surface adds only its "Last known" state.
            dimmed: CompanionCardPresentation.rowsDimmed(accountDimmed: dimmed, surfaceDimmed: context.surfaceDimmed),
            identifierPrefix: identifier,
            providerID: ProviderID(provider.id),
            scale: scale
        )
    }
}

/// The popover's meter stack at phone scale (`UsageBarsStack`).
struct PhoneMeterRows: View {
    let rows: [CompanionMeterRow]
    let display: ResolvedPhoneDisplay
    var isRemembered = false
    let now: Date
    let dimmed: Bool
    let identifierPrefix: String
    /// Names the provider in an empty row's tooltip (CA-P4).
    let providerID: ProviderID
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if rows.isEmpty {
                Text(CompanionCardCopy.noUsageData)
                    .font(.system(size: StatusSentence.size * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                // Reset lines start at one x: their label column is the widest label among them.
                let resetLabelPeers = rows.compactMap { row in
                    CompanionCardPresentation.meterRowLayout(row, isRemembered: isRemembered, now: now)
                        .resetNotReadLine == nil
                        ? nil : UsageMeterReading(widgetSummary: row.window).window.kind.displayName
                }
                VStack(spacing: rowGap * scale) {
                    // RI1: rows keyed by kind (and occurrence), so a row that arrives or
                    // leaves fades instead of handing its neighbour another window's value.
                    ForEach(Self.keyed(rows.map(\.window)), id: \.key) { keyed in
                        let layout = CompanionCardPresentation.meterRowLayout(
                            rows.first { $0.window.id == keyed.window.id }
                                ?? CompanionMeterRow(window: keyed.window, pastResetAt: nil),
                            isRemembered: isRemembered, now: now)
                        // A remembered window past its reset is a reset note, not a reading.
                        let isMuted = layout.showsMeter && (dimmed || !keyed.window.freshness.isLive)
                        VStack(alignment: .leading, spacing: PhoneCardMetrics.pastResetGap * scale) {
                            UsageBarView(
                                reading: UsageMeterReading(widgetSummary: keyed.window),
                                percentageMode: display.percentageMode,
                                now: now,
                                meterStyle: display.meterStyle,
                                dimmed: dimmed,
                                // CA-M5: no arrival key, so the fill paints final inside the
                                // rising card instead of drawing in behind it (KTD16 overturned).
                                arrivalKey: nil,
                                scale: scale,
                                resetNotReadLine: layout.resetNotReadLine,
                                showsWindowState: layout.showsWindowState,
                                providerID: providerID
                            )
                            .resetLine(peers: resetLabelPeers, compact: layout.resetNotReadCompactLine)
                            // Retained readings should look inactive beside live accounts;
                            // keep identity, recovery instructions and reset notes at full ink.
                            .saturation(isMuted ? 0 : 1)
                            .opacity(isMuted ? 0.6 : 1)
                            if let line = layout.pastResetLine {
                                pastResetLine(line, key: keyed.key)
                            }
                        }
                        .transition(HeadroomMotion.fade(HeadroomMotion.valueSpring, reduceMotion: reduceMotion))
                    }
                }
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                    value: rows.map(\.window.kind)
                )
                // A Full-style reset line is shorter than the meter it replaces, so the row
                // closes when a remembered window's reset passes.
                .animation(
                    HeadroomMotion.resolved(HeadroomMotion.valueSpring, .movement, reduceMotion: reduceMotion),
                    value: resetLabelPeers
                )
            }
        }
        .padding(.leading, IdentityRowMetrics.meterContentInset * scale)
        .padding(.trailing, IdentityRowMetrics.contentTrailingInset * scale)
    }

    private var rowGap: CGFloat {
        display.meterStyle.format == .micro ? PhoneCardMetrics.microRowGap : PhoneCardMetrics.fullRowGap
    }

    /// R11/AE6: the row already reads "—"; this says why, in the countdown's place and ink.
    private func pastResetLine(_ line: String, key: String) -> some View {
        Text(line)
            .font(.system(size: PhoneCardMetrics.pastResetSize * scale).monospacedDigit())
            .foregroundStyle(ProviderStyle.meterCountdownInk(scheme: scheme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(identifierPrefix).past-reset.\(key)")
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
