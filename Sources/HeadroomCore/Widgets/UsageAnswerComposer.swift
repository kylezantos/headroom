import Foundation

/// What the asking surface knows that the snapshot does not (KTD18).
public struct UsageAnswerContext: Sendable, Equatable {
    public var now: Date
    /// False while the phone is locked: answers omit account titles.
    public var isProtectedDataAvailable: Bool
    /// Explore Demo or a `--demo` launch: the answer says it is sample data (KTD21).
    public var isSampleData: Bool
    /// The phone's Spark switch; nil follows the Mac's app Spark switch (KTD11, KTD13).
    public var sparkEnabled: Bool?
    public var timeZone: TimeZone
    public var locale: Locale

    public init(
        now: Date, isProtectedDataAvailable: Bool, isSampleData: Bool, sparkEnabled: Bool? = nil,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) {
        self.now = now
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.isSampleData = isSampleData
        self.sparkEnabled = sparkEnabled
        self.timeZone = timeZone
        self.locale = locale
    }
}

public enum UsageAnswerKind: String, Sendable, Equatable, CaseIterable {
    /// At least one window of the main account was spoken (a number or a past reset).
    case usage
    /// The provider is tracked but has nothing to speak; its attention line explains why.
    case noReading
    /// No first reading yet, inside the dim threshold.
    case pending
    /// A skeleton past the dim threshold (KTD6.3).
    case waitingForMac
    case untracked
    case paused
    case waiting
    case updatePhone
    /// U10: the Mac's last update couldn't be read and nothing else is usable.
    case unreadable
    case accountScopeUnavailable
}

/// The spoken dialog plus a structured value, because Siri with Apple Intelligence may not
/// show the dialog and phrases its own answer from the value (KTD18).
public struct UsageAnswer: Sendable, Equatable {
    public let providerID: String
    public let providerName: String
    public let kind: UsageAnswerKind
    public let dialog: String
    /// The main account's tightest shown window, as the number a surface may show (R11).
    public let percentLeft: Int?
    /// That window's widget label ("5-hour", "Weekly", "Fable", "Other Models").
    public let windowLabel: String?
    /// The oldest reading the main account's answer speaks.
    public let updatedAt: Date?
    public let isDimmed: Bool
    /// The time in "No update from your Mac since <time>", only while dimmed.
    public let lastUpdateFromMac: Date?
    public let isSampleData: Bool
}

/// KTD18: Siri and Shortcuts answer "How much <provider> is left?" from the last sync.
/// The main account's tightest window, plus weekly if different, plus any other account
/// that is tighter, each with its age. Dimming changes the opening; a window past its reset
/// is spoken as reset at its clock time, never as a percentage (KTD15, R11). Always "left".
public enum UsageAnswerComposer {
    /// A 20-account envelope must not become a minute-long answer; the rest are counted.
    static let tighterAccountLimit = 3

    public static func answer(
        for providerID: ProviderID, in snapshot: CompanionResolvedSnapshot, context: UsageAnswerContext
    ) -> UsageAnswer {
        var composer = Composer(providerID: providerID, context: context)
        return composer.compose(snapshot)
    }
}

private struct Composer {
    let providerID: ProviderID
    let context: UsageAnswerContext
    var sentences: [String] = []
    var kind: UsageAnswerKind = .usage
    var percentLeft: Int?
    var windowLabel: String?
    var updatedAt: Date?
    var isDimmed = false
    var lastUpdateFromMac: Date?

    init(providerID: ProviderID, context: UsageAnswerContext) {
        self.providerID = providerID
        self.context = context
    }

    var name: String { providerID.displayName }
    var now: Date { context.now }

    mutating func compose(_ snapshot: CompanionResolvedSnapshot) -> UsageAnswer {
        switch snapshot.state {
        case .accountScopeUnavailable:
            finish(.accountScopeUnavailable, UsageAnswerCopy.accountScopeUnavailable)
        case .paused:
            finish(.paused, UsageAnswerCopy.paused)
        case .waiting(.updatePhone):
            finish(.updatePhone, UsageAnswerCopy.updatePhone)
        case .waiting:
            finish(.waiting, UsageAnswerCopy.waiting)
        case .unreadable:
            finish(.unreadable, UsageAnswerCopy.unreadable)
        case .content(let content):
            compose(content)
        }
        let body = sentences.joined(separator: " ")
        return UsageAnswer(
            providerID: providerID.raw, providerName: name, kind: kind,
            dialog: context.isSampleData ? "\(UsageAnswerCopy.sampleData) \(body)" : body,
            percentLeft: percentLeft, windowLabel: windowLabel, updatedAt: updatedAt,
            isDimmed: isDimmed, lastUpdateFromMac: lastUpdateFromMac,
            isSampleData: context.isSampleData)
    }

    mutating func finish(_ kind: UsageAnswerKind, _ sentence: String) {
        self.kind = kind
        sentences.append(sentence)
    }

    mutating func compose(_ content: CompanionResolvedContent) {
        guard let provider = content.providers.first(where: { $0.id == providerID.raw }) else {
            return finish(.untracked, UsageAnswerCopy.untracked(name))
        }
        isDimmed = CompanionFreshnessRule.isDimmed(content.freshness, surface: .siri, at: now)
        if isDimmed {
            let heard = CompanionFreshnessRule.lastHeardFromMac(content.freshness)
            lastUpdateFromMac = heard
            sentences.append("\(CompanionFreshnessCopy.noUpdate(since: clock(heard))).")
        }

        let sparkEnabled = context.sparkEnabled ?? content.display?.appSparkEnabled ?? false
        func shown(_ account: CompanionResolvedAccount) -> [WidgetWindowSummary] {
            account.windows.filter { !$0.isSpark || sparkEnabled }.map(\.summary)
        }

        guard let main = provider.mainAccount ?? provider.extraAccounts.first else {
            if provider.capabilityAttention != nil { return noReading(provider, account: nil) }
            return provider.showsWaitingForMac(surfaceDimmed: isDimmed)
                ? finish(.waitingForMac, UsageAnswerCopy.waitingForMac(name))
                : finish(.pending, UsageAnswerCopy.pending(name))
        }
        let mainPlan = SpokenPlan(windows: shown(main), now: now)
        guard let lead = mainPlan.lead else {
            if provider.capabilityAttention != nil || main.freshness != .pending {
                return noReading(provider, account: main)
            }
            return finish(.pending, UsageAnswerCopy.pending(name))
        }

        kind = .usage
        let hasExtras = !provider.extraAccounts.isEmpty
        if let value = lead.value {
            percentLeft = value
            windowLabel = lead.window.widgetDisplayLabel
            let subject: String
            if !hasExtras {
                subject = name
            } else if context.isProtectedDataAvailable {
                subject = "Your main \(name) account, \(main.title),"
            } else {
                subject = "Your main \(name) account"
            }
            var phrases = [phrase(lead)]
            if let second = mainPlan.second, second.value != nil { phrases.append(phrase(second)) }
            sentences.append("\(subject) has \(phrases.joined(separator: ", and ")).")
            if let second = mainPlan.second, second.value == nil {
                sentences.append("The \(pastReset(second))")
            }
        } else {
            let opening: String
            if !hasExtras {
                opening = "\(name)’s"
            } else if context.isProtectedDataAvailable {
                opening = "On your main \(name) account, \(main.title), the"
            } else {
                opening = "On your main \(name) account, the"
            }
            sentences.append("\(opening) \(pastReset(lead))")
            // A past-reset lead means no window has a number, so a second one is past reset too.
            if let second = mainPlan.second { sentences.append("The \(pastReset(second))") }
        }
        let age = mainPlan.age ?? main.capturedAt ?? content.generatedAt
        updatedAt = age
        sentences.append(UsageAnswerCopy.updated(age, now: now))
        if let attention = attentionLine(provider, account: main) { sentences.append(attention) }

        guard let mainValue = percentLeft else { return }
        // Default-login R12: a remembered row's last reading is not current, so Siri never
        // offers it as the tighter account.
        let tighter = provider.accounts.filter { $0.id != main.id && !$0.isRemembered }.compactMap {
            account -> (CompanionResolvedAccount, SpokenWindow)? in
            guard let lead = SpokenPlan(windows: shown(account), now: now).lead,
                let value = lead.value, value < mainValue
            else { return nil }
            return (account, lead)
        }
        for (account, lead) in tighter.prefix(UsageAnswerComposer.tighterAccountLimit) {
            let subject = context.isProtectedDataAvailable ? account.title : "Another \(name) account"
            sentences.append("\(subject) is tighter, with \(phrase(lead)).")
            let age = lead.window.observedAt ?? account.capturedAt ?? content.generatedAt
            sentences.append(UsageAnswerCopy.updated(age, now: now))
        }
        let remainder = tighter.count - UsageAnswerComposer.tighterAccountLimit
        if remainder > 0 { sentences.append(UsageAnswerCopy.moreTighter(remainder, name)) }
    }

    mutating func noReading(_ provider: CompanionResolvedProvider, account: CompanionResolvedAccount?) {
        finish(.noReading, UsageAnswerCopy.noReading(name))
        sentences.append(attentionLine(provider, account: account) ?? "\(CompanionAttentionCopy.generic).")
    }

    /// Typed attention only: provider capability first, then the account's own category.
    /// No Mac-written free text is ever spoken (KTD10).
    func attentionLine(_ provider: CompanionResolvedProvider, account: CompanionResolvedAccount?) -> String? {
        if let capability = provider.capabilityAttention {
            return "\(CompanionAttentionCopy.account(capability))."
        }
        guard let account else { return nil }
        if account.attention != nil || account.freshness.needsAttention {
            return "\(CompanionAttentionCopy.account(account.attention))."
        }
        return nil
    }

    // MARK: Phrases

    func phrase(_ spoken: SpokenWindow) -> String {
        var text = "\(spoken.value!)% left in \(UsageAnswerCopy.windowName(spoken.window))"
        if let deadline = spoken.window.resetSchedule.deadline {
            // KTD13/KTD19: resets are named by clock time through the shared formatter.
            text += !(deadline > now)
                ? ", resetting now"
                : ", resetting \(ResetClockFormatter.phrase(for: deadline, now: now, timeZone: context.timeZone, locale: context.locale))"
        }
        return text
    }

    /// R11/AE6: past its reset, a window is spoken by the clock time it reset at.
    func pastReset(_ spoken: SpokenWindow) -> String {
        var name = UsageAnswerCopy.windowName(spoken.window)
        if name.hasPrefix("the ") { name.removeFirst(4) }
        return "\(name) reset at \(clock(spoken.pastReset!)), waiting for your Mac."
    }

    /// A past moment as a clock time: "9:30 AM", "yesterday at 2:00 PM", "Sep 22 at 10:00 AM".
    func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        calendar.locale = context.locale
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let time = formatter.string(from: date)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ...0: return time
        case 1: return "yesterday at \(time)"
        default:
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return "\(formatter.string(from: date)) at \(time)"
        }
    }
}

/// One window as the answer speaks it: a number, or the time it reset at.
struct SpokenWindow {
    let window: WidgetWindowSummary
    let value: Int?
    let pastReset: Date?
}

/// Which windows of one account are spoken (KTD18): the tightest shown number, then the
/// weekly (or the period pool for Grok and Cursor) when it is a different window.
struct SpokenPlan {
    let lead: SpokenWindow?
    let second: SpokenWindow?

    init(windows: [WidgetWindowSummary], now: Date) {
        func spoken(_ window: WidgetWindowSummary) -> SpokenWindow? {
            if let reset = CompanionFreshnessRule.pastResetTime(window, at: now) {
                return SpokenWindow(window: window, value: nil, pastReset: reset)
            }
            guard let value = CompanionFreshnessRule.visiblePercentRemaining(window, at: now) else {
                return nil
            }
            return SpokenWindow(window: window, value: Int(value.rounded()), pastReset: nil)
        }
        let numbered = windows.filter { spoken($0)?.value != nil }
        let period = WidgetProviderSummary(
            id: "", displayName: "", planLabel: nil, freshness: .live, windows: windows, renewalDate: nil
        ).primarySubscriptionWindow
        let leadWindow =
            WidgetWindowRanking.tightest(numbered)
            ?? period.flatMap { spoken($0)?.pastReset != nil ? $0 : nil }
            ?? WidgetWindowRanking.displayOrder(windows).first { spoken($0)?.pastReset != nil }
        lead = leadWindow.flatMap(spoken)
        second = period.flatMap { period in period.id == leadWindow?.id ? nil : spoken(period) }
    }

    /// The oldest numbered reading among the spoken windows.
    var age: Date? {
        [lead, second].compactMap { $0 }.compactMap(\.window.observedAt).min()
    }
}

/// KTD18 sentences, held to the R2C6 rules (curly apostrophes, one sign-in verb, no
/// "connect"), KTD15 ("never Your Mac is asleep") and "left", never "used".
public enum UsageAnswerCopy {
    public static let sampleData = "This is sample data."
    public static let accountScopeUnavailable =
        "iCloud isn’t available on this iPhone, so Headroom can’t read your usage."
    public static let paused =
        "Companion Sync is paused. Turn on Sync usage to iPhone in Headroom on your Mac."
    public static let waiting = "Waiting for your Mac. Open Headroom on your Mac to send a reading."
    public static let updatePhone = "Update Headroom on this iPhone to read your Mac’s usage."
    public static let unreadable =
        "Headroom couldn’t read your Mac’s last update. Open Headroom on your Mac to send a new one."

    public static func untracked(_ provider: String) -> String {
        "Your Mac isn’t tracking \(provider)."
    }

    public static func pending(_ provider: String) -> String {
        "Waiting for your Mac’s first \(provider) reading."
    }

    public static func waitingForMac(_ provider: String) -> String {
        "Waiting for your Mac to send \(provider) usage."
    }

    public static func noReading(_ provider: String) -> String {
        "Headroom has no \(provider) reading to share."
    }

    public static func moreTighter(_ count: Int, _ provider: String) -> String {
        count == 1
            ? "1 more \(provider) account is tighter."
            : "\(count) more \(provider) accounts are tighter."
    }

    /// The reading's age through the shared "updated" formatter.
    public static func updated(_ date: Date, now: Date) -> String {
        "Updated \(Countdown.updatedLabel(capturedAt: date, now: now) ?? "just now")."
    }

    /// How a window is named aloud: "the 5-hour window", "the Fable weekly window", "the
    /// weekly pool", or a named pool such as Cursor's "Other Models".
    public static func windowName(_ window: WidgetWindowSummary) -> String {
        switch window.widgetRole {
        case .fiveHour: return "the 5-hour window"
        case .weekly: return "the weekly window"
        case .spark: return "the Spark weekly window"
        case .model:
            if let model = WindowKind.weeklyModelName(in: window.label) {
                return "the \(model) weekly window"
            }
            return window.label.isEmpty ? "the usage window" : "the \(window.label) window"
        case .pool:
            switch window.label.lowercased() {
            case "weekly", "monthly", "included": return "the \(window.label.lowercased()) pool"
            case "": return "the usage pool"
            default: return window.label
            }
        }
    }
}
