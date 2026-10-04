import SwiftUI
#if SWIFT_PACKAGE
import HeadroomCore
#elseif canImport(HeadroomCore)
import HeadroomCore
#endif
#if SWIFT_PACKAGE
import HeadroomWidgetSharedUI
#endif

/// S2B: severity lives in the sentence's ink, so the mapping from state to ink is stated
/// once here rather than re-decided at each of the six former glyph sites.
public enum StatusSentenceSeverity {
    /// Something needs the user, and the account is otherwise intact: sign in needed, a
    /// stale capture, a missing CLI, a handoff standing in the way.
    case attention
    /// The provider or the OS said no: a rejected sign-in, a denied read, a failed handoff.
    case critical
    /// A handoff is running. Not a severity at all — the row is mid-flight.
    case progress
    /// Informational and nobody's fault: retryable staleness the next poll may clear.
    case neutral
    /// Below informational — a first-run line with nothing to report yet.
    case quiet

    /// R2C5: `.attention` used to paint with the meter's Low amber, so an amber 38% Weekly bar
    /// could sit two rows above an amber "Sign in with the official Claude CLI" with no
    /// relationship between them — one colour, two meanings. Account lifecycle comes off the
    /// severity ramp onto the neutral label ink; the sentence is already 11.5 medium against
    /// 11 regular metadata, so weight and position carry it. `.critical` keeps the red,
    /// because a provider refusal genuinely is an error and is the card's only red.
    ///
    /// `AnyShapeStyle` rather than `Color` because `.neutral`/`.quiet` are the *hierarchical*
    /// inks the spend card was already painting with, and flattening them to `Color.secondary`
    /// / a tertiary literal would shift those two rows. `.progress` keeps `Color.secondary`
    /// for the same reason in reverse — that is the ink it has always drawn.
    public func ink(scheme: ColorScheme) -> AnyShapeStyle {
        switch self {
        case .attention: AnyShapeStyle(ProviderStyle.meterLabelInk(scheme: scheme))
        case .critical: AnyShapeStyle(ProviderStyle.criticalText(scheme: scheme))
        case .progress: AnyShapeStyle(Color.secondary)
        case .neutral: AnyShapeStyle(.secondary)
        case .quiet: AnyShapeStyle(.tertiary)
        }
    }

    /// S2B: only the provider's own refusals earn the critical ink. Everything else is a
    /// state the user can walk out of, so it stays attention rather than shouting.
    public static func forSetupOutcome(_ outcome: ProviderSetupOutcome?) -> StatusSentenceSeverity {
        switch outcome {
        case .codexRejectedAuth, .codexPermissionDenied, .codexUnsafePermissions,
             .grokRejectedAuth, .grokPermissionDenied, .grokUnsafePermissions:
            .critical
        default:
            .attention
        }
    }

    /// P4C: the API-spend card's four tones land on this same table, so its sentence is the
    /// account rows' `StatusSentence` rather than a second copy of the recipe. `.warning`
    /// is `.attention` by construction — R2C5 already took both off the severity ramp onto
    /// `meterLabelInk`.
    public static func forSpendTone(_ tone: APISpendRowStatus.Tone) -> StatusSentenceSeverity {
        switch tone {
        case .quiet: .quiet
        case .neutral: .neutral
        case .warning: .attention
        case .critical: .critical
        }
    }
}

/// S2B: the whole status line — no glyph, no state tag. 11.5 medium, inked by severity,
/// starting on the 34pt content axis (the 21pt inset inside the card's own 13pt padding),
/// wrapping freely and stopping at the card's own 13pt trailing edge.
public struct StatusSentence: View {
    public let text: String
    public let severity: StatusSentenceSeverity
    /// False where the row supplies the axis itself — the waiting row's spinner occupies
    /// the 15pt mark slot, and the single-account setup notice sits above a guided card
    /// that starts at the card's own 13pt edge.
    public var indented: Bool = true

    public init(text: String, severity: StatusSentenceSeverity, indented: Bool = true) {
        self.text = text
        self.severity = severity
        self.indented = indented
    }

    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(severity.ink(scheme: scheme))
            // PB11: this sentence routinely runs to three lines in a 299pt card, and at
            // SF's default it was setting at ~1.22 leading while Settings' help text gets
            // 1.4. Two points brings the popover's wrapping prose into the same band.
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            // OA1: the sentence starts a line on the same content axis as the titles and
            // meter labels above it, so it hangs on the same optical edge they do.
            .widgetOpticalLeading(text, size: 11.5, weight: .medium)
            .padding(.leading, indented ? IdentityRowMetrics.meterContentInset : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
