import SwiftUI
import HeadroomCore

/// Draft-to-rule helpers for `ReminderRuleRow`, pure so the commit rules are testable
/// without a mounted field (R4, R6, KTD15).
enum ReminderRuleDraft {
    /// The digits of a typed draft, or nil for a blank field (R4: blank clamps to the
    /// floor). Capped at six digits so a pasted run of nines clamps to the ceiling instead
    /// of overflowing to nil and landing on the floor.
    static func parse(_ text: String) -> Int? {
        let digits = text.filter(\.isASCII).filter(\.isNumber).prefix(6)
        return Int(digits)
    }

    /// R4: the rule a committed draft stands for, clamped. A nil text leaves that part as is.
    static func committed(_ rule: ReminderRule, amountText: String? = nil, thresholdText: String? = nil) -> ReminderRule {
        var edited = rule
        if let amountText {
            edited.amount = ReminderRule.clampedAmount(parse(amountText), unit: rule.unit)
        }
        if let thresholdText {
            edited.threshold = ReminderRule.clampedThreshold(parse(thresholdText))
        }
        return edited.clamped()
    }

    /// The threshold stepper moves to the next multiple of 5 in its direction (23 → 25 up,
    /// 23 → 20 down), clamped to 1–100, so a typed odd value rejoins the round steps.
    static func steppedThreshold(_ value: Int, up: Bool) -> Int {
        let stepped = up ? ((value + 5) / 5) * 5 : ((value - 1) / 5) * 5
        return ReminderRule.clampedThreshold(stepped)
    }

    /// The lead-time stepper moves by one within the unit's range.
    static func steppedAmount(_ rule: ReminderRule, up: Bool) -> Int {
        ReminderRule.clampedAmount(rule.amount + (up ? 1 : -1), unit: rule.unit)
    }

    /// KTD15: per-row VoiceOver names, so a list of identical controls stays navigable —
    /// the `accessibilityLabel` convention on the Accounts and pill-card remove buttons.
    struct AccessibilityLabels: Equatable {
        let leadTime: String
        let leadTimeStepper: String
        let unit: String
        let threshold: String
        let thresholdStepper: String
        let remove: String

        init(position: Int) {
            let suffix = "reminder \(position)"
            leadTime = "Lead time, \(suffix)"
            leadTimeStepper = "Adjust lead time, \(suffix)"
            unit = "Lead time unit, \(suffix)"
            threshold = "Percent left, \(suffix)"
            thresholdStepper = "Adjust percent left, \(suffix)"
            remove = "Remove \(suffix)"
        }
    }
}

/// KTD15: one reminder rule — "[1][±] [days] before reset, if [50]%[±] or more is left [–]".
/// Native controls only: `.roundedBorder` numeric fields with tabular digits, a `Stepper`
/// beside each, a menu `Picker` for the unit, and the Accounts glyph-button remove idiom.
///
/// Typed digits stay a local draft until Return or focus loss commits them (R4, R6), so the
/// row never clamps or resorts under the caret. Stepper and unit changes commit at once.
struct ReminderRuleRow: View {
    let rule: ReminderRule
    /// 1-based, for the per-row accessibility labels.
    let position: Int
    let onCommit: (ReminderRule) -> Void
    let onRemove: () -> Void

    private enum Field: Hashable {
        case amount
        case threshold
    }

    @State private var amountText: String
    @State private var thresholdText: String
    @FocusState private var focusedField: Field?
    /// Measured widths behind the one-line/two-line choice in `body`.
    @State private var availableWidth: CGFloat = 0
    @State private var leadWidth: CGFloat = 0
    @State private var thresholdWidth: CGFloat = 0

    /// Field widths for the longest value each can hold — "48" and "100" in tabular digits
    /// inside the rounded border. Measured on the harness render: the mockup's 34 clipped
    /// "70", and 40 clipped "100".
    private static let amountFieldWidth: CGFloat = 40
    private static let thresholdFieldWidth: CGFloat = 46
    /// The unit menu at its widest label ("hours"), so "before reset, if" starts on one
    /// axis in every row instead of stepping with the unit's word length.
    private static let unitWidth: CGFloat = 68
    /// 5, a point under the mockup's 6, so the one-line row keeps some slack at the default
    /// window width.
    private static let spacing: CGFloat = 5

    init(
        rule: ReminderRule,
        position: Int,
        onCommit: @escaping (ReminderRule) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.rule = rule
        self.position = position
        self.onCommit = onCommit
        self.onRemove = onRemove
        _amountText = State(initialValue: String(rule.amount))
        _thresholdText = State(initialValue: String(rule.threshold))
    }

    private var labels: ReminderRuleDraft.AccessibilityLabels {
        ReminderRuleDraft.AccessibilityLabels(position: position)
    }

    var body: some View {
        // One line when it fits, the lead clause over the threshold clause when it doesn't.
        // At the 720pt window floor the one-line row is ~14pt wider than the well, and an
        // HStack that cannot shrink pushed the whole split view past the window, clipping
        // the sidebar (harness, 2026-09-26). `AnyLayout` keeps the fields' identity across
        // the switch, so a resize mid-edit never drops focus or a draft.
        let layout = fitsOnOneLine
            ? AnyLayout(HStackLayout(alignment: .center, spacing: Self.spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Self.spacing))
        HStack(spacing: Self.spacing) {
            layout {
                leadClause
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { leadWidth = $0 }
                thresholdClause
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { thresholdWidth = $0 }
            }
            // Takes the offered width whatever its content asks for, so the measurement below
            // is the room there is, not the room the one-line row wants.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
            removeButton
        }
        // R4: leaving a field commits it, the same as Return.
        .onChange(of: focusedField) { previous, current in
            if previous == .amount, current != .amount { commitAmountDraft() }
            if previous == .threshold, current != .threshold { commitThresholdDraft() }
        }
        // A resort, a stepper, or Reset to defaults changed the rule under the row: show the
        // committed values, except in a field the user is still typing in.
        .onChange(of: rule) { _, updated in
            if focusedField != .amount { amountText = String(updated.amount) }
            if focusedField != .threshold { thresholdText = String(updated.threshold) }
        }
        .onDisappear {
            // A pane switch mid-edit keeps what was typed rather than dropping it.
            if focusedField == .amount { commitAmountDraft() }
            if focusedField == .threshold { commitThresholdDraft() }
        }
    }

    private var fitsOnOneLine: Bool {
        // Unmeasured reads as fitting, the common case at the default window width.
        guard availableWidth > 0 else { return true }
        return leadWidth + Self.spacing + thresholdWidth <= availableWidth
    }

    private var leadClause: some View {
        HStack(spacing: Self.spacing) {
            numberField($amountText, field: .amount, width: Self.amountFieldWidth, label: labels.leadTime)
            Stepper(
                labels.leadTimeStepper,
                onIncrement: { stepAmount(up: true) },
                onDecrement: { stepAmount(up: false) }
            )
            .labelsHidden()
            Picker(labels.unit, selection: unitBinding) {
                Text(rule.amount == 1 ? "hour" : "hours").tag(ReminderLeadUnit.hours)
                Text(rule.amount == 1 ? "day" : "days").tag(ReminderLeadUnit.days)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: Self.unitWidth)
            connective("before reset, if")
        }
    }

    private var thresholdClause: some View {
        HStack(spacing: Self.spacing) {
            HStack(spacing: 2) {
                numberField($thresholdText, field: .threshold, width: Self.thresholdFieldWidth, label: labels.threshold)
                Text("%")
                    .accessibilityHidden(true)
            }
            Stepper(
                labels.thresholdStepper,
                onIncrement: { stepThreshold(up: true) },
                onDecrement: { stepThreshold(up: false) }
            )
            .labelsHidden()
            connective("or more is left")
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus.circle")
                .font(SettingsType.help)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
        .foregroundStyle(.secondary)
        .help("Remove this reminder")
        .accessibilityLabel(labels.remove)
    }

    private func numberField(_ text: Binding<String>, field: Field, width: CGFloat, label: String) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .focused($focusedField, equals: field)
            .onSubmit {
                switch field {
                case .amount: commitAmountDraft()
                case .threshold: commitThresholdDraft()
                }
            }
            .accessibilityLabel(label)
    }

    private func connective(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var unitBinding: Binding<ReminderLeadUnit> {
        Binding(
            get: { rule.unit },
            // R4: a unit change keeps the number and clamps it.
            set: { onCommit(rule.withUnit($0)) }
        )
    }

    private func commitAmountDraft() {
        let committed = ReminderRuleDraft.committed(rule, amountText: amountText)
        // A clamp that lands on the stored value changes nothing upstream, so the field is
        // reset here rather than waiting for a rule change that never comes.
        amountText = String(committed.amount)
        if committed != rule { onCommit(committed) }
    }

    private func commitThresholdDraft() {
        let committed = ReminderRuleDraft.committed(rule, thresholdText: thresholdText)
        thresholdText = String(committed.threshold)
        if committed != rule { onCommit(committed) }
    }

    /// Steppers commit at once (KTD15). They step from the field's draft, so a click while
    /// the field still holds typed digits builds on what is shown rather than on a value
    /// the focus-loss commit would then overwrite.
    private func stepAmount(up: Bool) {
        let base = ReminderRuleDraft.committed(rule, amountText: amountText)
        var edited = base
        edited.amount = ReminderRuleDraft.steppedAmount(base, up: up)
        amountText = String(edited.amount)
        if edited != rule { onCommit(edited) }
    }

    private func stepThreshold(up: Bool) {
        let base = ReminderRuleDraft.committed(rule, thresholdText: thresholdText)
        var edited = base
        edited.threshold = ReminderRuleDraft.steppedThreshold(base.threshold, up: up)
        thresholdText = String(edited.threshold)
        if edited != rule { onCommit(edited) }
    }
}
