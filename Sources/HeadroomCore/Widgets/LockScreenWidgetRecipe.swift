import Foundation

/// R8: semantic one-ink states. The source severity, not another threshold, owns critical.
public enum LockScreenWindowState: String, Sendable, Equatable {
    case off, pending, signIn, unavailable, stale, resetReached, critical, live

    public var usesKnockout: Bool { self == .critical }
    public var needsWarningImage: Bool {
        switch self {
        case .off, .pending, .signIn, .unavailable, .stale: true
        case .resetReached, .critical, .live: false
        }
    }
}

public enum LockScreenInlineImage: Sendable, Equatable {
    case warning
    /// KTD9: eleven images, 0…10; a positive printed number always has a nonempty step.
    case vessel(level: Int)
}

/// KTD3/KTD4: one window's truthful drawing and copy, including an absent provider/window.
public struct LockScreenWindowRecipe: Sendable, Equatable {
    public let window: WidgetWindowSummary?
    public let state: LockScreenWindowState
    public let numberText: String
    public let caption: String
    public let shortCaption: String
    public let fillFraction: Double
    public let refillText: String?
    public let shortRefillText: String?
    /// WCW1: the bare countdown ("4d 2h") for detail lines that already name the window.
    public let countdownText: String?
    public let shortCountdownText: String?
    public let resetText: String?
    public let accessibilityText: String
    public var usesKnockout: Bool { state.usesKnockout }

    init(provider: WidgetProviderSummary?, window sourceWindow: WidgetWindowSummary?, family: LockScreenWidgetFamily, isDemo: Bool, demoCaption: Bool, now: Date) {
        let window = provider?.freshness.isStale == true ? sourceWindow?.demotedToStale() : sourceWindow
        self.window = window
        let state: LockScreenWindowState
        if provider == nil {
            state = .off
        } else if provider?.freshness == .pending, provider?.windows.isEmpty == true {
            state = .pending
        } else if provider?.freshness.isStale == true, provider?.windows.isEmpty == true {
            state = .signIn
        } else if window?.freshness.isUnavailable == true {
            state = .unavailable
        } else if window?.freshness.isStale == true || provider?.freshness.isStale == true {
            state = .stale
        } else if window?.resetSchedule.meterResetLine(now: now)?.countdown == "now" {
            state = .resetReached
        } else if window?.severity == .critical {
            state = .critical
        } else if window == nil {
            state = .pending
        } else {
            state = .live
        }
        self.state = state
        numberText = WidgetWindowText.percent(window)
        fillFraction = window?.displayPercentRemaining.map { min(1, max(0, $0 / 100)) } ?? 0

        let fullLabel = window?.widgetDisplayLabel ?? ""
        let compactLabel = LockScreenWidgetCopy.compactWindowLabel(window, providerID: provider?.id)
        let label = family == .circle ? compactLabel : fullLabel
        let stateCaption: String
        let shortStateCaption: String
        switch state {
        case .off: stateCaption = "Off"; shortStateCaption = "Off"
        case .pending: stateCaption = "Waiting"; shortStateCaption = "Waiting"
        case .signIn: stateCaption = "Sign in"; shortStateCaption = "Sign in"
        case .stale:
            stateCaption = "⚠ \(label)"
            shortStateCaption = "⚠ \(compactLabel)"
        case .unavailable, .resetReached, .critical, .live:
            stateCaption = label
            shortStateCaption = compactLabel
        }
        // R10 explicitly gives Demo the circle caption even for Cursor pool numbers. Gauge
        // Pair is two circle gauges with no name line, so it follows the circle rule.
        caption = isDemo && demoCaption ? "Demo" : stateCaption
        shortCaption = isDemo && demoCaption ? "Demo" : shortStateCaption

        if let window, !window.freshness.isUnavailable,
           let line = window.resetSchedule.meterResetLine(now: now),
           let deadline = window.resetSchedule.deadline {
            refillText = line.countdown == "now" ? "Refills now" : "Refills in \(line.countdown)"
            countdownText = line.countdown
            shortCountdownText = line.shortCountdown
            shortRefillText = line.shortCountdown == "now" ? "Refills now" : "Refills in \(line.shortCountdown)"
            resetText = line.countdown == "now" ? line.tooltip
                : "Resets \(ResetClockFormatter.phrase(for: deadline, now: now))"
        } else {
            refillText = nil
            shortRefillText = nil
            countdownText = nil
            shortCountdownText = nil
            resetText = nil
        }

        switch state {
        case .off: accessibilityText = "Off"
        case .pending: accessibilityText = "Waiting"
        case .signIn: accessibilityText = "Sign in"
        default:
            var parts = [fullLabel]
            if let percent = window?.displayPercentRemaining { parts.append("\(Int(percent.rounded())) percent left") }
            if state == .unavailable { parts.append("unavailable") }
            if state == .stale { parts.append("last known") }
            if state == .critical { parts.append("low") }
            if let refillText { parts.append(refillText) }
            accessibilityText = parts.joined(separator: ", ")
        }
    }
}

/// A provider slot in visual order. Gauge Pair emits two slots, possibly for the same provider.
public struct LockScreenProviderSlot: Sendable, Equatable, Identifiable {
    public let providerID: String
    public let providerName: String
    public let primary: LockScreenWindowRecipe
    public let secondary: [LockScreenWindowRecipe]
    public let hasSiblingPools: Bool
    public let accessibilityText: String
    public var id: String { "\(providerID)|\(primary.window?.id ?? "missing")" }

    init(provider: WidgetProviderSummary?, providerID: String, window: WidgetWindowSummary?, secondary: [WidgetWindowSummary], family: LockScreenWidgetFamily, isDemo: Bool, demoCaption: Bool, now: Date) {
        self.providerID = providerID
        providerName = provider?.displayName ?? ProviderID(providerID).displayName
        primary = LockScreenWindowRecipe(provider: provider, window: window, family: family, isDemo: isDemo, demoCaption: demoCaption, now: now)
        self.secondary = secondary.map { LockScreenWindowRecipe(provider: provider, window: $0, family: family, isDemo: isDemo, demoCaption: demoCaption, now: now) }
        hasSiblingPools = provider?.weeklyWindow == nil && (provider?.windows.filter(\.isBillingPeriod).count ?? 0) > 1
        accessibilityText = ([providerName, primary.accessibilityText] + self.secondary.map(\.accessibilityText)).joined(separator: ", ")
    }
}

public struct LockScreenWidgetStatusForm: Sendable, Equatable {
    public let circleWord: String
    public let title: String
    public let message: String
    /// WCW4: the status mark's own level, never a reading.
    public let vesselFill: Double
    public var inlineText: String { "Headroom · \(title)" }

    init(_ status: WidgetStatusState) {
        circleWord = status.lockScreenWord
        vesselFill = status.vesselFill
        title = status.title
        message = status.message
    }
}

/// KTD3: the only policy layer for all Lock Screen bodies. Views draw these decisions.
public struct LockScreenWidgetRecipe: Sendable, Equatable {
    public let style: WidgetLayoutStyle
    public let family: LockScreenWidgetFamily
    public let providerChoice: LockScreenProviderChoice
    public let isDemo: Bool
    public let status: LockScreenWidgetStatusForm?
    public let slots: [LockScreenProviderSlot]
    public let isSingleProvider: Bool
    public let showsOnlyLimit: Bool
    public let inlineTextCandidates: [String]
    public let inlineImage: LockScreenInlineImage
    public let accessibilityElements: [String]
    public var headingPrefix: String { isDemo ? "Demo · " : "" }

    /// R10: the name a rectangle prints for a slot. One provider prefixes "Demo · "; a pair
    /// has no room for the prefix, so the first slot's name becomes "Demo" and its mark
    /// still names the provider. Circles and Gauge Pair carry Demo in the caption instead.
    public func displayName(forSlotAt index: Int) -> String {
        guard slots.indices.contains(index) else { return "" }
        let name = slots[index].providerName
        guard isDemo else { return name }
        if slots.count > 1 { return index == 0 ? "Demo" : name }
        return headingPrefix + name
    }

    /// R11: a title line that stands for the main window (Nested Rows, which prints no
    /// caption) names Cursor's pool, never a bare "Cursor N%".
    public func title(forSlotAt index: Int) -> String {
        guard slots.indices.contains(index) else { return "" }
        let slot = slots[index]
        guard slot.providerID == ProviderID.cursor.raw, slot.primary.window != nil,
              ![.off, .pending, .signIn].contains(slot.primary.state) else { return displayName(forSlotAt: index) }
        let pool = slot.primary.window?.widgetDisplayLabel ?? slot.providerName
        return slots.count > 1 ? pool : headingPrefix + pool
    }
    public var accessibilityText: String { accessibilityElements.joined(separator: "; ") }

    public init(style: WidgetLayoutStyle, family: LockScreenWidgetFamily, providerChoice: LockScreenProviderChoice, state: IOSWidgetSnapshotState, now: Date) {
        self.style = style
        self.family = family
        self.providerChoice = providerChoice
        let envelope: WidgetSnapshotEnvelope?
        let statusState: WidgetStatusState?
        switch state {
        case .content(let content): envelope = content; isDemo = false; statusState = nil
        case .demo(let content): envelope = content; isDemo = true; statusState = nil
        case .disabled: envelope = nil; isDemo = false; statusState = .iosDisabled
        case .setupNeeded: envelope = nil; isDemo = false; statusState = .iosSetupNeeded
        case .waitingForMac: envelope = nil; isDemo = false; statusState = .iosWaitingForMac
        case .corrupt: envelope = nil; isDemo = false; statusState = .iosCorrupt
        case .incompatibleSchema: envelope = nil; isDemo = false; statusState = .iosIncompatibleSchema
        }
        let resolvedStatus = statusState ?? (envelope?.status == .disabled || envelope?.providers.isEmpty == true ? .iosDisabled : nil)
        if let resolvedStatus {
            let form = LockScreenWidgetStatusForm(resolvedStatus)
            status = form
            slots = []
            isSingleProvider = false
            showsOnlyLimit = false
            inlineTextCandidates = [(isDemo ? "Demo · " : "") + form.inlineText]
            inlineImage = .warning
            accessibilityElements = [(isDemo ? "Demo, " : "") + form.title + ", " + form.message]
            return
        }
        status = nil
        // The switch above yields either a status or an envelope; this fallback is neutral.
        guard let envelope else {
            slots = []; isSingleProvider = false; showsOnlyLimit = false
            inlineTextCandidates = ["Headroom · Waiting"]; inlineImage = .warning
            accessibilityElements = ["Headroom, Waiting"]
            return
        }

        let selected: [WidgetStyleProviderRecipe]
        if let pinned = providerChoice.providerID {
            selected = envelope.providers.filter { $0.id == pinned.raw }.map(WidgetStyleProviderRecipe.init(summary:))
        } else if style == .tightestFirst {
            selected = envelope.providers.map(WidgetStyleProviderRecipe.init(summary:))
        } else {
            let providers = envelope.widgetProviders.map(WidgetStyleProviderRecipe.init(summary:))
            selected = family == .circle ? WidgetProviderSelection.singleProvider(from: providers).map { [$0] } ?? [] : providers
        }
        isSingleProvider = providerChoice != .automatic || selected.count == 1
        let demo = isDemo

        func slot(_ provider: WidgetStyleProviderRecipe?, _ window: WidgetWindowSummary?, secondary: [WidgetWindowSummary] = []) -> LockScreenProviderSlot {
            LockScreenProviderSlot(
                provider: provider?.summary, providerID: provider?.id ?? providerChoice.providerID?.raw ?? "headroom",
                window: window, secondary: secondary, family: family, isDemo: demo,
                demoCaption: family == .circle || (family == .rectangle && style == .tightestFirst), now: now
            )
        }

        if selected.isEmpty {
            slots = [slot(nil, nil)]
            showsOnlyLimit = false
        } else if style == .tightestFirst {
            let ranked = WidgetProviderSelection.rankedRows(from: selected)
            let count = family == .rectangle ? 2 : 1
            var result = ranked.prefix(count).map { row in
                slot(selected.first { $0.id == row.providerID }, row.window)
            }
            if result.isEmpty { result = [slot(selected.first, nil)] }
            // R12: a second window with no value still occupies a dash gauge. A second
            // windowless provider does too; Only limit requires exactly one total window.
            if count == 2, result.count == 1,
               let windowless = selected.first(where: { $0.id != result[0].providerID && $0.windows.isEmpty }) {
                result.append(slot(windowless, nil))
            }
            slots = result
            showsOnlyLimit = count == 2 && ranked.count == 1 && selected.count == 1
        } else {
            let singleProvider = isSingleProvider
            slots = selected.map { provider in
                let secondary: [WidgetWindowSummary]
                switch (family, style) {
                case (.circle, .nestedMeter), (.rectangle, .nestedMeter):
                    secondary = Array(provider.secondary.prefix(2))
                case (.rectangle, .vesselHero) where singleProvider:
                    secondary = Array(provider.secondary.prefix(2))
                case (.rectangle, .liquidLevel) where singleProvider:
                    secondary = Array(provider.secondary.prefix(1))
                default:
                    secondary = []
                }
                return slot(provider, provider.primary, secondary: secondary)
            }
            showsOnlyLimit = false
        }

        let prefix = isDemo ? "Demo · " : ""
        inlineTextCandidates = LockScreenWidgetCopy.inlineCandidates(slots: slots, tightest: style == .tightestFirst, prefix: prefix)
        if slots.contains(where: { $0.primary.state.needsWarningImage }) {
            inlineImage = .warning
        } else if let lowest = slots.compactMap({ $0.primary.window?.displayPercentRemaining }).min() {
            let level = lowest <= 0 ? 0 : max(1, min(10, Int((lowest / 10).rounded())))
            inlineImage = .vessel(level: level)
        } else {
            inlineImage = .warning
        }

        let slotText = slots.map { (demo ? "Demo, " : "") + $0.accessibilityText }
        if family == .rectangle, style == .tightestFirst || slots.count > 1 {
            accessibilityElements = slotText
        } else {
            accessibilityElements = [slotText.joined(separator: "; ")]
        }
    }
}

enum LockScreenWidgetCopy {
    static func compactWindowLabel(_ window: WidgetWindowSummary?, providerID: String?) -> String {
        guard let window else { return "" }
        if providerID == ProviderID.cursor.raw {
            switch window.label {
            case "Cursor Models": return "Models"
            case "Other Models": return "Other"
            default: return window.widgetDisplayLabel
            }
        }
        return window.widgetDisplayLabel
    }

    static func inlineCandidates(slots: [LockScreenProviderSlot], tightest: Bool, prefix: String) -> [String] {
        func label(_ slot: LockScreenProviderSlot, compact: Bool, minimal: Bool = false) -> String {
            let main = slot.primary
            switch main.state {
            case .off, .pending, .signIn:
                return "\(slot.providerName) · \(main.caption)"
            default:
                let name: String
                if slot.providerID == ProviderID.cursor.raw {
                    let pool = compactWindowLabel(main.window, providerID: slot.providerID)
                    name = compact ? "Cursor \(pool)" : main.window?.widgetDisplayLabel ?? "Cursor"
                } else {
                    if minimal { return main.numberText }
                    let windowName = compact ? compactWindowLabel(main.window, providerID: slot.providerID) : main.window?.widgetDisplayLabel ?? ""
                    name = tightest ? "\(slot.providerName) \(windowName)" : slot.providerName
                }
                return "\(name) \(main.numberText)"
            }
        }
        let full = slots.map { label($0, compact: false) }.joined(separator: " · ")
        let short = slots.map { label($0, compact: true) }.joined(separator: " · ")
        let minimal = slots.map { label($0, compact: true, minimal: true) }.joined(separator: " · ")
        let refill = tightest ? slots.first?.primary.refillText.map { " · " + $0.lowercased() } ?? "" : ""
        let shortRefill = tightest ? slots.first?.primary.shortRefillText.map { " · " + $0.lowercased() } ?? "" : ""
        var texts = [full + refill, short + refill, minimal + shortRefill]
        // Design 10: a narrow Tightest First line keeps the window and a bare countdown
        // ("5-hour 8% · 3h") before it drops the window name; Cursor always keeps it (R11).
        if tightest, let slot = slots.first, let countdown = slot.primary.shortCountdownText,
           ![.off, .pending, .signIn].contains(slot.primary.state) {
            let isCursor = slot.providerID == ProviderID.cursor.raw
            let pool = compactWindowLabel(slot.primary.window, providerID: slot.providerID)
            let window = "\(isCursor ? "Cursor \(pool)" : pool) \(slot.primary.numberText) · \(countdown)"
            texts = [full + refill, short + refill, window]
            if !isCursor { texts.append("\(slot.primary.numberText) · \(countdown)") }
        }
        var candidates: [String] = []
        for text in texts {
            let candidate = prefix + text
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }
        return candidates
    }
}
