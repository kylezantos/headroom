import Foundation

// MARK: - Variants (KTD21, R30)

/// The bundled v4 demo states. Each one is a set of bytes a demo Mac would have published,
/// decoded by the real v4 codec and assembled by the real resolver, so Explore Demo and
/// `--demo` screenshots exercise the production decode path (KTD21). `multiAccount` is the
/// default (U7: Explore Demo opens it; U12's picker lists every case by `title`).
public enum CompanionDemoVariant: String, CaseIterable, Sendable, Identifiable {
    /// Claude Personal/Work/Studio and Codex Personal/Work, API spend and a sample reminder
    /// summary. Mirrors the Mac's `--demo multi-3`.
    case multiAccount
    /// One account of each provider, with Grok and Cursor's billing pools (`--demo multi-4`).
    case fourProviders
    /// Every registered provider, one account each: the four above plus Copilot's monthly
    /// credit pool (`--demo five-providers`).
    case fiveProviders
    /// OpenCode plan U9 (KTD14): every registered provider, one account each: the five above
    /// plus OpenCode Go's three windows (`--demo six-providers`).
    case sixProviders
    /// Codex banked resets: two, one on a Critical account, and a reported zero
    /// (`--demo banked-resets`).
    case bankedResets
    /// Non-default display block: Full segmented ghost meters, "used", brand ink, Spark on.
    case displayChoices
    /// The Mac last published two hours ago: every surface dims (KTD15, R10).
    case dimmed
    /// Claude Personal's 5-hour window reset 25 minutes ago with no newer reading (R11).
    case pastReset
    /// A 1.4 Mac publishing only primary-only v3: "Update Headroom on your Mac" (R14).
    case oldMac
    /// Companion sync turned off on the Mac (a disabled tombstone).
    case paused
    /// Nothing published yet.
    case waiting
    /// The tested envelope: 20 Claude, 20 Codex with Spark rows, 20 Grok, 1 Cursor, 1 Copilot
    /// (`--demo multi-20`).
    case multi20
    /// Above the envelope: the drop ladder caps extra accounts with "N more on your Mac"
    /// (KTD7 level 2).
    case aboveEnvelope
    /// U8 (V12, V13): account states the stacked card has to carry. Claude's never-signed-in
    /// "Account 2" under a live main; Codex's two accounts sharing a long name ("Northwind
    /// Research Workspace" and its " · 2" twin, the second retrying), banked resets on the
    /// main, and a widget selection of Codex alone.
    case accountStates
    /// The multi-account moment with both API spend rows retained from a read three hours
    /// ago that the Mac will retry (the v4 form of build 33's `--demo-stale-api-spend`).
    case staleSpend
    /// Default-login plan U9 (mock scenario A; AE1, AE2): Claude and Codex each show a live
    /// "Personal" and two accounts the Mac's default login left. "Work" was read two minutes
    /// ago with both resets ahead; "Studio" was read two days ago and both its resets have
    /// passed, so it shows no number. Mirrors the Mac's `--demo remembered`.
    case remembered

    public static let `default`: Self = .multiAccount

    /// Mac `--demo <scenario>` names that pose the same moment, so one token can drive both
    /// devices in a screenshot run.
    static let macScenarioAliases: [String: Self] = [
        "multi-3": .multiAccount,
        "multi-4": .fourProviders,
        "five-providers": .fiveProviders,
        "six-providers": .sixProviders,
        "banked-resets": .bankedResets,
        "multi-20": .multi20,
        "remembered": .remembered,
    ]

    /// Exact case names or Mac scenario aliases; nil for anything else.
    public init?(token: String) {
        guard let variant = Self(rawValue: token) ?? Self.macScenarioAliases[token] else { return nil }
        self = variant
    }

    /// A missing or unrecognized token falls back to the default, never an error (U7).
    public static func resolving(_ token: String?) -> Self {
        token.flatMap(Self.init(token:)) ?? .default
    }

    public var id: String { rawValue }

    /// The picker name in Settings › Demo (U12).
    public var title: String {
        switch self {
        case .multiAccount: "Multiple accounts"
        case .fourProviders: "Four providers"
        case .fiveProviders: "Five providers"
        case .sixProviders: "Six providers"
        case .bankedResets: "Banked resets"
        case .displayChoices: "Display choices"
        case .dimmed: "No recent update"
        case .pastReset: "Past reset"
        case .oldMac: "Older Mac app"
        case .paused: "Sync paused"
        case .waiting: "Waiting for Mac"
        case .multi20: "20 accounts each"
        case .aboveEnvelope: "More than 20 accounts"
        case .accountStates: "Account states"
        case .staleSpend: "Stale API spend"
        case .remembered: "Remembered accounts"
        }
    }

    /// Whether a demo pull replays a receipt. Requests go out only when the resolver's winner
    /// is v4 (KTD14.1), so the old-Mac, paused and waiting states have nothing to replay.
    public var supportsCheckNow: Bool {
        switch self {
        case .oldMac, .paused, .waiting: false
        default: true
        }
    }

    /// What the demo Mac publishes once a check finishes: a fresh reading clears the dimmed
    /// and past-reset states, the way a real check would.
    var afterCheckNow: Self {
        switch self {
        case .dimmed, .pastReset: .multiAccount
        default: self
        }
    }
}

// MARK: - Published bytes

/// The raw values a demo Mac would hold in iCloud for one variant: exactly what
/// `CompanionResolverInput` takes. Never written anywhere (KTD21).
public struct CompanionDemoPublication: Equatable, Sendable {
    public let manifest: Data?
    public let providerKeys: [String: Data]
    public let v3: Data?
    /// The drop-ladder level the real budget fit chose (KTD7); nil without a manifest.
    public let ladderLevel: Int?
}

/// One step of a demo check-now replay (KTD14 receipt states, KTD21).
public struct CompanionDemoCheckNowStep: Equatable, Sendable {
    /// Encoded and decoded through the real receipt codec, like a receipt read from iCloud.
    public let receipt: CompanionReceipt
    /// Present on the finished step: the demo snapshot at `finishedGeneration`, which a host
    /// adopts before it shows "Just now" (KTD14.7).
    public let snapshot: CompanionResolvedSnapshot?

    public init(receipt: CompanionReceipt, snapshot: CompanionResolvedSnapshot?) {
        self.receipt = receipt
        self.snapshot = snapshot
    }
}

// MARK: - Fixtures

/// v4 demo fixtures (KTD21). Numbers mirror the Mac's `DemoFixture` scenarios so the
/// popover, the Mac widgets and the phone show one moment; `DemoScenarioParityTests` holds
/// them to the Mac fixtures. Claude's Fable row reads 54% everywhere, plan labels are stored
/// in display form, and every reset is a deadline relative to `now` (the wire carries no
/// reset labels, so surfaces format them with the shared formatter).
public enum CompanionDemoData {
    /// A fixed demo lineage. Not a Mac's: nothing demo-shaped ever reaches iCloud.
    public static let sourceID = "0d3e6a51-7c2b-4f0e-9a8d-5e4b3c2a1f00"
    /// The request ID a demo pull uses; a real phone uses a fresh UUID per request.
    public static let requestID = "0d3e6a51-7c2b-4f0e-9a8d-5e4b3c2a1f01"
    public static let generation: Int64 = 42
    public static let chosenIntervalSeconds = 300
    /// Every demo reading is about two minutes old, like the Mac's demo snapshots.
    public static let captureAge: TimeInterval = 135
    /// The single Fable value every demo and screenshot surface shows.
    public static let fableUtilization: Double = 46

    /// The variant resolved through the real codec and resolver at `now`. A fixture that
    /// fails validation resolves to the waiting state rather than crashing a host;
    /// `DemoScreenshotDataVariantsTests` proves every variant builds.
    public static func snapshot(_ variant: CompanionDemoVariant, now: Date) -> CompanionResolvedSnapshot {
        snapshot(variant, now: now, generation: generation, answered: [])
    }

    static func snapshot(
        _ variant: CompanionDemoVariant, now: Date, generation: Int64,
        answered: [CompanionAnsweredRequest]
    ) -> CompanionResolvedSnapshot {
        guard
            let publication = try? publication(
                variant, now: now, generation: generation, answered: answered)
        else { return CompanionResolvedSnapshot(state: .waiting(nil)) }
        return resolve(publication, now: now)
    }

    /// The real resolver over an empty cache: first-seen is `now`, so dimming comes from the
    /// publication's own `generatedAt` (KTD15's min(first-seen, generatedAt + 10 min)).
    public static func resolve(_ publication: CompanionDemoPublication, now: Date) -> CompanionResolvedSnapshot {
        CompanionSnapshotResolver.resolve(
            CompanionResolverInput(
                manifest: publication.manifest, providerKeys: publication.providerKeys,
                v3: publication.v3, cache: .empty, now: now)
        ).snapshot
    }

    /// Encodes one variant's Mac state with the v4 codec and the real KTD7 budget fit.
    public static func publication(
        _ variant: CompanionDemoVariant, now: Date, generation: Int64 = generation,
        answered: [CompanionAnsweredRequest] = []
    ) throws -> CompanionDemoPublication {
        let clock = DemoClock(now: now)
        switch variant {
        case .paused:
            return CompanionDemoPublication(
                manifest: try CompanionSyncCodec.encode(CompanionManifest.disabledTombstone(sourceID: sourceID)),
                providerKeys: [:], v3: nil, ladderLevel: nil)
        case .waiting:
            return CompanionDemoPublication(manifest: nil, providerKeys: [:], v3: nil, ladderLevel: nil)
        case .oldMac:
            return try oldMacPublication(now: now)
        default:
            let state = try macState(variant, clock: clock, generation: generation)
            return try publish(state, clock: clock, generation: generation, answered: answered)
        }
    }

    // MARK: Check now

    /// The bundled receipt sequence for one demo pull: accepted, running n of total with each
    /// landed account in provider order (main first), then finished with the snapshot at the
    /// finished generation. Each receipt round-trips the real codec. `now` is read per step,
    /// so the receipt's display times follow the host's clock. Landed rows describe the
    /// readings the check produces, so they come from the post-check moment. Empty when the
    /// variant cannot check (KTD14.1).
    static func checkNowSteps(
        _ variant: CompanionDemoVariant, requestID: String, startedAt: Date
    ) -> [(delay: TimeInterval, build: @Sendable (Date) throws -> CompanionDemoCheckNowStep)] {
        guard variant.supportsCheckNow,
            let landed = snapshot(variant.afterCheckNow, now: startedAt).content?.providers.flatMap({ provider in
                provider.accounts.compactMap { account -> CompanionLastLanded? in
                    // A check never reads a remembered row (default-login R12).
                    guard let accountID = account.accountID, !account.isRemembered else { return nil }
                    return try? CompanionLastLanded(
                        providerID: provider.id, accountID: accountID, live: account.freshness == .live)
                }
            }), !landed.isEmpty
        else { return [] }
        let total = landed.count
        let finishedGeneration = generation + 1
        let perAccount = max(0.08, min(0.6, 4.0 / Double(total)))
        let started = CompanionWireDate(date: startedAt)

        var steps: [(delay: TimeInterval, build: @Sendable (Date) throws -> CompanionDemoCheckNowStep)] = []
        steps.append((0.8, { _ in
            try step(CompanionReceipt(
                sourceID: sourceID, state: .accepted, requestIDs: [requestID], startedAt: started))
        }))
        for (index, account) in landed.enumerated() {
            steps.append((perAccount, { _ in
                try step(CompanionReceipt(
                    sourceID: sourceID, state: .running, requestIDs: [requestID], startedAt: started,
                    total: total, completed: index + 1, lastLanded: account))
            }))
        }
        steps.append((0.5, { now in
            let answer = try CompanionAnsweredRequest(
                requestID: requestID, outcome: .finished, finishedGeneration: finishedGeneration)
            let refreshed = snapshot(
                variant.afterCheckNow, now: now, generation: finishedGeneration, answered: [answer])
            return try step(
                CompanionReceipt(
                    sourceID: sourceID, state: .finished, requestIDs: [requestID],
                    answeredRequests: [answer], startedAt: started,
                    finishedAt: CompanionWireDate(date: now), total: total, completed: total,
                    lastLanded: landed.last, finishedGeneration: finishedGeneration),
                snapshot: refreshed)
        }))
        return steps
    }

    private static func step(_ receipt: CompanionReceipt, snapshot: CompanionResolvedSnapshot? = nil) throws
        -> CompanionDemoCheckNowStep
    {
        guard case .value(let decoded) = CompanionSyncCodec.decodeReceipt(try CompanionSyncCodec.encode(receipt))
        else { throw CompanionSyncValidationError.state }
        return CompanionDemoCheckNowStep(receipt: decoded, snapshot: snapshot)
    }

    // MARK: Mac state per variant

    /// What the demo Mac's store holds before it publishes.
    struct MacState {
        var providers: [CompanionProviderPayload]
        var spendOrder: [String] = []
        var display = CompanionDisplayBlock()
        var reminder = CompanionReminderSummary()
        var generatedAgo: TimeInterval = 60
        /// The Mac's widget provider selection; nil is "the first two providers".
        var widgetSelection: [String]? = nil
    }

    static func macState(_ variant: CompanionDemoVariant, clock: DemoClock, generation: Int64) throws -> MacState {
        let g = generation
        switch variant {
        case .multiAccount:
            return try multiAccountState(clock: clock, generation: g)
        case .fourProviders:
            return try fourProvidersState(clock: clock, generation: g)
        case .fiveProviders:
            var state = try fourProvidersState(clock: clock, generation: g)
            state.providers.append(try payload("copilot", g, main: copilotAccount(clock)))
            return state
        case .sixProviders:
            var state = try fourProvidersState(clock: clock, generation: g)
            state.providers.append(try payload("copilot", g, main: copilotAccount(clock)))
            state.providers.append(try payload("opencode", g, main: opencodeAccount(clock)))
            return state
        case .bankedResets:
            return MacState(providers: [
                try payload("claude", g, main: claudePersonal(clock)),
                try payload(
                    "codex", g,
                    main: codexAccount(clock, id: "primary", title: "Northwind Research Workspace",
                                       plan: "Plus", fiveHour: 9, weekly: 36, banked: 2),
                    extras: [
                        codexAccount(clock, id: "codex-critical", title: "On call", plan: "Plus",
                                     fiveHour: 88, weekly: 36, banked: 1),
                        codexAccount(clock, id: "codex-zero", title: "Quiet", plan: "Plus",
                                     fiveHour: 22, weekly: 48, banked: 0),
                    ]),
            ])
        case .displayChoices:
            var state = try multiAccountState(clock: clock, generation: g, spark: true)
            state.display = CompanionDisplayBlock(
                meterStyle: MeterStyle(format: .full, shape: .segmented, fill: .ghost),
                percentageMode: .used, accountTitleInk: .brand, appSparkEnabled: true)
            return state
        case .dimmed:
            // The Mac went quiet two hours ago: its last readings and publish are that old.
            let quiet = DemoClock(now: clock.now, captureAge: 2 * 3_600 + captureAge, anchor: clock.now)
            var state = try multiAccountState(clock: quiet, generation: g)
            state.generatedAgo = 2 * 3_600
            return state
        case .pastReset:
            var state = try multiAccountState(clock: clock, generation: g)
            state.providers[0] = try payload(
                "claude", g, main: claudePersonalPastReset(clock),
                extras: claudeExtras(clock), spend: anthropicSpend(clock))
            return state
        case .multi20:
            return try envelopeState(clock: clock, generation: g, count: CompanionSyncBudget.accountEnvelope)
        case .aboveEnvelope:
            return try envelopeState(clock: clock, generation: g, count: aboveEnvelopeCount)
        case .accountStates:
            return try accountStatesState(clock: clock, generation: g)
        case .staleSpend:
            var state = try multiAccountState(clock: clock, generation: g)
            let retained = DemoClock(now: clock.now, captureAge: 3 * hour, anchor: clock.anchor)
            state.providers[0] = try payload(
                "claude", g, main: claudePersonal(clock), extras: claudeExtras(clock),
                spend: anthropicSpend(retained, stale: true))
            state.providers[1] = try payload(
                "codex", g,
                main: codexAccount(clock, id: "primary", title: "Personal", plan: "Pro Lite", fiveHour: 9, weekly: 36),
                extras: [codexAccount(clock, id: "codex-work", title: "Work", plan: "Pro", fiveHour: 54, weekly: 79)],
                spend: openAISpend(retained, stale: true))
            return state
        case .remembered:
            return try rememberedState(clock: clock, generation: g)
        case .oldMac, .paused, .waiting:
            throw CompanionSyncValidationError.state
        }
    }

    /// Default-login U9: the phone half of `DemoFixture`'s `remembered` scenario, with its
    /// numbers. Each remembered row is what the Mac capture sends after aging (U6): "Work"
    /// stale at its original read time, "Studio" unavailable since each reset.
    static func rememberedState(clock: DemoClock, generation g: Int64) throws -> MacState {
        func live(plan: String) throws -> CompanionAccountSummary {
            try CompanionAccountSummary(
                id: "primary", title: "Personal", planName: plan, capturedAt: clock.captured,
                windows: [
                    window(.fiveHour, utilization: 4, resetIn: 3.2 * hour, clock),
                    window(.weekly, utilization: 31, resetIn: 4 * day, clock),
                ])
        }
        func remembered(
            id: String, title: String, plan: String, readAgo: TimeInterval,
            fiveHour: (used: Double, resetIn: TimeInterval), weekly: (used: Double, resetIn: TimeInterval)
        ) throws -> CompanionAccountSummary {
            let readAt = try wire(clock.now.addingTimeInterval(-readAgo))
            func row(_ kind: CompanionWindowKind, used: Double, resetIn: TimeInterval) throws -> CompanionSlimWindow {
                guard let display = UsageDisplayValue(utilization: used) else {
                    throw CompanionLeafValidationError.number
                }
                let reset = try wire(clock.now.addingTimeInterval(resetIn))
                let past = !(resetIn > 0)
                return try CompanionSlimWindow(
                    kind: kind, percentRemaining: display.percentRemaining, utilization: used,
                    resetKind: .scheduled, resetDeadline: reset,
                    freshness: past ? .unavailable : .stale, observedAtOverride: readAt,
                    unavailableSince: past ? reset : nil)
            }
            return try CompanionAccountSummary(
                id: id, title: title, planName: plan, freshness: .stale, capturedAt: readAt,
                needsAttention: false,
                windows: [
                    row(.fiveHour, used: fiveHour.used, resetIn: fiveHour.resetIn),
                    row(.weekly, used: weekly.used, resetIn: weekly.resetIn),
                ],
                isRemembered: true)
        }
        func provider(_ id: String, live livePlan: String, work workPlan: String, studio studioPlan: String) throws
            -> CompanionProviderPayload
        {
            try payload(
                id, g, main: live(plan: livePlan),
                extras: [
                    // AE1: 22% and 10% left, resets in 1h 08m and 2d 4h.
                    remembered(id: "remembered-\(id)-work", title: "Work", plan: workPlan, readAgo: 2 * minute,
                               fiveHour: (78, 68 * minute + 30), weekly: (90, 2 * day + 4 * hour + 30 * minute)),
                    // AE2: both resets passed since the read two days ago.
                    remembered(id: "remembered-\(id)-studio", title: "Studio", plan: studioPlan, readAgo: 2 * day,
                               fiveHour: (40, -2 * day + 3 * hour), weekly: (65, -6 * hour)),
                ])
        }
        return MacState(providers: [
            try provider("claude", live: "Max", work: "Team", studio: "Pro"),
            try provider("codex", live: "Pro Lite", work: "Pro", studio: "Plus"),
        ])
    }

    static func fourProvidersState(clock: DemoClock, generation g: Int64) throws -> MacState {
        MacState(
            providers: [
                try payload("claude", g, main: claudePersonal(clock), spend: anthropicSpend(clock)),
                try payload("codex", g, main: codexAccount(clock, id: "primary", title: "Personal",
                                                           plan: "Pro Lite", fiveHour: 9, weekly: 36),
                            spend: openAISpend(clock)),
                try payload("grok", g, main: grokAccount(clock, id: "primary", title: "Grok")),
                try payload("cursor", g, main: cursorAccount(clock)),
            ],
            spendOrder: ["claude", "codex"])
    }

    /// U8: see `CompanionDemoVariant.accountStates`. Numbers reuse the multi-account moment.
    static func accountStatesState(clock: DemoClock, generation g: Int64) throws -> MacState {
        let northwind = "Northwind Research Workspace"
        // V12: an extra account added on the Mac and never signed in. It has nothing to read,
        // so it carries no capture time and no rows.
        let neverSignedIn = try CompanionAccountSummary(
            id: "claude-account-2", title: "Account 2", freshness: .stale, attention: .neverOnboarded,
            needsAttention: true, windows: [])
        let retrying = try CompanionAccountSummary(
            id: "codex-northwind-2", title: "\(northwind) · 2", planName: "Pro", freshness: .stale,
            capturedAt: clock.captured, attention: .retrying, needsAttention: false,
            windows: [
                window(.fiveHour, utilization: 54, resetIn: 3.2 * hour, clock),
                window(.weekly, utilization: 79, resetIn: 4 * day, clock),
            ])
        return MacState(
            providers: [
                try payload("claude", g, main: claudePersonal(clock), extras: [neverSignedIn]),
                try payload(
                    "codex", g,
                    main: codexAccount(clock, id: "primary", title: northwind, plan: "Plus",
                                       fiveHour: 9, weekly: 36, banked: 2),
                    extras: [retrying]),
            ],
            widgetSelection: ["codex"])
    }

    /// Accounts per multi-account provider in `aboveEnvelope`: enough that the real budget
    /// fit reaches KTD7's account cap on its own. The compact encoding fits about 70 per
    /// provider after the model-row drop, so the cap starts near 75.
    static let aboveEnvelopeCount = 80

    static func multiAccountState(clock: DemoClock, generation g: Int64, spark: Bool = false) throws -> MacState {
        MacState(
            providers: [
                try payload("claude", g, main: claudePersonal(clock), extras: claudeExtras(clock),
                            spend: anthropicSpend(clock)),
                try payload(
                    "codex", g,
                    main: codexAccount(clock, id: "primary", title: "Personal", plan: "Pro Lite",
                                       fiveHour: 9, weekly: 36, spark: spark ? 18 : nil),
                    extras: [
                        codexAccount(clock, id: "codex-work", title: "Work", plan: "Pro",
                                     fiveHour: 54, weekly: 79, spark: spark ? 63 : nil),
                    ],
                    spend: openAISpend(clock)),
            ],
            spendOrder: ["claude", "codex"],
            // A Mac reminder switch that is on, with one rule (U7): 1 day before reset at 50%.
            reminder: CompanionReminderSummary(
                macUseItUpEnabled: true,
                rules: [try CompanionReminderRuleSummary(amount: 1, unit: .days, threshold: 50)],
                scope: [.weekly, .billingPeriod]))
    }

    /// Mirrors `DemoFixture.generatedAccounts`: the first account built in, labels and
    /// utilizations spread from the index so every severity band appears.
    static func envelopeState(clock: DemoClock, generation g: Int64, count: Int) throws -> MacState {
        let plans = ["Max", "Pro", "Team", "Plus", "Pro Lite"]
        func id(_ provider: String, _ index: Int) -> String {
            index == 0 ? "primary" : "\(provider)-generated-\(index + 1)"
        }
        func title(_ index: Int) -> String { index == 0 ? "Personal" : "Account \(index + 1)" }
        func fiveHour(_ index: Int) -> Double { Double((index * 37) % 100) }
        func weekly(_ index: Int) -> Double { Double((index * 53 + 11) % 100) }

        let claude = try (0..<count).map { i in
            try rollingAccount(clock, id: id("claude", i), title: title(i), plan: plans[i % plans.count],
                               fiveHour: fiveHour(i), weekly: weekly(i))
        }
        let codex = try (0..<count).map { i in
            try codexAccount(clock, id: id("codex", i), title: title(i), plan: plans[i % plans.count],
                             fiveHour: fiveHour(i), weekly: weekly(i), spark: Double((i * 29 + 7) % 100))
        }
        let grok = try (0..<count).map { i in try grokAccount(clock, id: id("grok", i), title: title(i)) }
        return MacState(
            providers: [
                try payload("claude", g, main: claude[0], extras: Array(claude.dropFirst())),
                try payload("codex", g, main: codex[0], extras: Array(codex.dropFirst())),
                try payload("grok", g, main: grok[0], extras: Array(grok.dropFirst())),
                try payload("cursor", g, main: cursorAccount(clock)),
                try payload("copilot", g, main: copilotAccount(clock)),
            ],
            // The phone shows Spark rows only when the Mac's in-app switch is on (KTD11).
            display: CompanionDisplayBlock(appSparkEnabled: true))
    }

    // MARK: Accounts (numbers mirror DemoFixture)

    /// Claude Personal as the Mac's multi-account scenarios pose it (5-hour and weekly from
    /// `demoAccount`), plus the unified Fable row from the bare `--demo` snapshot.
    static func claudePersonal(_ clock: DemoClock) throws -> CompanionAccountSummary {
        try rollingAccount(
            clock, id: "primary", title: "Personal", plan: "Max", fiveHour: 28, weekly: 62,
            extra: [
                window(.other, name: "Weekly (Fable)", utilization: fableUtilization, resetIn: 4 * day, clock),
            ])
    }

    /// R11: the Mac's Claude reads kept failing while its 5-hour window reset 25 minutes ago,
    /// so the retained reading is stale and that row's number must hide (KTD15 past-reset).
    static func claudePersonalPastReset(_ clock: DemoClock) throws -> CompanionAccountSummary {
        let observed = clock.now.addingTimeInterval(-50 * minute)
        let observedWire = try wire(observed)
        return try CompanionAccountSummary(
            id: "primary", title: "Personal", planName: "Max", freshness: .stale,
            capturedAt: observedWire, attention: .retrying, needsAttention: false,
            windows: [
                window(.fiveHour, utilization: 28, resetIn: -25 * minute, clock),
                window(.weekly, utilization: 62, resetIn: 4 * day, clock),
                window(.other, name: "Weekly (Fable)", utilization: fableUtilization, resetIn: 4 * day, clock),
            ])
    }

    static func claudeExtras(_ clock: DemoClock) throws -> [CompanionAccountSummary] {
        [
            try rollingAccount(clock, id: "work", title: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
            try rollingAccount(clock, id: "studio", title: "Studio", plan: "Max", fiveHour: 12, weekly: 41),
        ]
    }

    /// `DemoFixture.demoAccount`'s 5-hour/weekly pair: resets in 3.2 hours and 4 days.
    static func rollingAccount(
        _ clock: DemoClock, id: String, title: String, plan: String, fiveHour: Double, weekly: Double,
        banked: Int? = nil, extra: [CompanionSlimWindow] = []
    ) throws -> CompanionAccountSummary {
        try CompanionAccountSummary(
            id: id, title: title, planName: plan, capturedAt: clock.captured, bankedResets: banked,
            windows: [
                window(.fiveHour, utilization: fiveHour, resetIn: 3.2 * hour, clock),
                window(.weekly, utilization: weekly, resetIn: 4 * day, clock),
            ] + extra)
    }

    static func codexAccount(
        _ clock: DemoClock, id: String, title: String, plan: String, fiveHour: Double, weekly: Double,
        banked: Int? = nil, spark: Double? = nil
    ) throws -> CompanionAccountSummary {
        // The Mac flags Spark explicitly; the phone never guesses from the label (KTD13).
        let sparkRow = try spark.map {
            try window(.other, name: "GPT-5.3-Codex-Spark Weekly", utilization: $0, resetIn: 4 * day,
                       clock, spark: true)
        }
        return try rollingAccount(
            clock, id: id, title: title, plan: plan, fiveHour: fiveHour, weekly: weekly, banked: banked,
            extra: sparkRow.map { [$0] } ?? [])
    }

    /// `DemoFixture.grokSnapshot`: one weekly credit pool.
    static func grokAccount(_ clock: DemoClock, id: String, title: String) throws -> CompanionAccountSummary {
        try CompanionAccountSummary(
            id: id, title: title, planName: "SuperGrok", capturedAt: clock.captured,
            windows: [
                window(.billingPeriod, name: "Weekly", period: 7 * day, utilization: 44,
                       resetIn: 3 * day + 2 * hour + 30 * minute, clock),
            ])
    }

    /// `DemoFixture.cursorSnapshot`: two monthly pools with one reset.
    static func cursorAccount(_ clock: DemoClock) throws -> CompanionAccountSummary {
        try CompanionAccountSummary(
            id: "primary", title: "Cursor", planName: "Pro+", capturedAt: clock.captured,
            windows: [
                window(.billingPeriod, name: "Cursor Models", period: 30 * day, utilization: 31,
                       resetIn: 12 * day, clock),
                window(.billingPeriod, name: "Other Models", period: 30 * day, utilization: 63,
                       resetIn: 12 * day, clock),
            ])
    }

    /// `DemoFixture.copilotSnapshot`: one monthly credit pool, no plan name, no spend.
    static func copilotAccount(_ clock: DemoClock) throws -> CompanionAccountSummary {
        try CompanionAccountSummary(
            id: "primary", title: "Copilot", capturedAt: clock.captured,
            windows: [
                window(.billingPeriod, name: "Monthly", period: 30 * day, utilization: 24,
                       resetIn: 18 * day + 30 * minute, clock),
            ])
    }

    /// `DemoFixture.opencodeSnapshot`: Go's 5-hour, weekly and Monthly windows, no plan name
    /// (KTD19) and no spend (D1).
    static func opencodeAccount(_ clock: DemoClock) throws -> CompanionAccountSummary {
        try CompanionAccountSummary(
            id: "primary", title: "OpenCode", capturedAt: clock.captured,
            windows: [
                window(.fiveHour, utilization: 18, resetIn: 2 * hour + 40 * minute + 30, clock),
                window(.weekly, utilization: 47, resetIn: 3 * day + 6 * hour + 30 * minute, clock),
                window(.billingPeriod, name: "Monthly", period: 30 * day, utilization: 71,
                       resetIn: 19 * day + 30 * minute, clock),
            ])
    }

    static func anthropicSpend(_ clock: DemoClock, stale: Bool = false) throws -> CompanionSpendSummary {
        try CompanionSpendSummary(
            id: "claude", displayName: "Anthropic API", amount: 142.67, currency: "usd",
            periodLabel: "Current month", capturedAt: clock.captured,
            freshness: stale ? .stale : .live, needsAttention: stale ? false : nil)
    }

    static func openAISpend(_ clock: DemoClock, stale: Bool = false) throws -> CompanionSpendSummary {
        try CompanionSpendSummary(
            id: "codex", displayName: "OpenAI API", amount: 58.90, currency: "usd",
            periodLabel: "Current month", capturedAt: clock.captured,
            freshness: stale ? .stale : .live, needsAttention: stale ? false : nil)
    }

    // MARK: Encoding

    static func payload(
        _ providerID: String, _ generation: Int64, main: CompanionAccountSummary,
        extras: [CompanionAccountSummary] = [], spend: CompanionSpendSummary? = nil
    ) throws -> CompanionProviderPayload {
        try CompanionProviderPayload(
            sourceID: sourceID, providerID: providerID, payloadGeneration: generation,
            mode: .subscription, mainAccount: main, accounts: extras, apiSpend: spend)
    }

    /// KTD7 as the Mac publishes it: the real budget fit picks the ladder level, and the
    /// manifest's digests are SHA-256 of the exact provider bytes (KTD6.2).
    static func publish(
        _ state: MacState, clock: DemoClock, generation: Int64, answered: [CompanionAnsweredRequest]
    ) throws -> CompanionDemoPublication {
        let generatedAt = try wire(clock.now.addingTimeInterval(-state.generatedAgo))
        let order = state.providers.map(\.providerID)
        let fit = try CompanionPayloadBudget.fit(
            payloads: state.providers, protocolValues: [:]
        ) { level, values in
            var entries: [String: CompanionManifestProviderEntry] = [:]
            for (id, data) in values {
                entries[id] = try CompanionManifestProviderEntry(
                    payloadGeneration: generation, digest: CompanionSyncCodec.digest(data),
                    effectiveIntervalSeconds: Double(chosenIntervalSeconds))
            }
            return try CompanionSyncCodec.encode(
                CompanionManifest.active(
                    CompanionActiveManifest(
                        sourceID: sourceID, generation: generation, generatedAt: generatedAt,
                        macAppVersion: "1.5", providerOrder: order, providers: entries,
                        spendOrder: state.spendOrder, chosenIntervalSeconds: chosenIntervalSeconds,
                        display: state.display, widgetProviderSelection: state.widgetSelection,
                        reminderSummary: state.reminder,
                        answeredRequests: answered, dropLadderLevel: level)))
        }
        return CompanionDemoPublication(
            manifest: fit.manifest, providerKeys: fit.providerValues, v3: nil, ladderLevel: fit.ladderLevel)
    }

    /// R14: a 1.4 Mac publishes only the primary-only v3 key, with no lineage. Its content is
    /// the multi-account moment's main accounts, encoded by the real v3 codec.
    static func oldMacPublication(now: Date) throws -> CompanionDemoPublication {
        let v4 = try publication(.multiAccount, now: now)
        guard let primary = resolve(v4, now: now).primaryProjection() else {
            throw CompanionSyncValidationError.state
        }
        let v3 = SyncedWidgetSnapshotEnvelope(
            publishedAt: primary.generatedAt, sourceID: "Demo", sourcePlatform: .macOS, snapshot: primary)
        return CompanionDemoPublication(
            manifest: nil, providerKeys: [:], v3: try SyncedWidgetSnapshotCodec.encode(v3), ladderLevel: nil)
    }

    static func window(
        _ kind: CompanionWindowKind, name: String? = nil, period: Double? = nil, utilization: Double,
        resetIn: TimeInterval, _ clock: DemoClock, spark: Bool = false
    ) throws -> CompanionSlimWindow {
        guard let display = UsageDisplayValue(utilization: utilization) else {
            throw CompanionLeafValidationError.number
        }
        return try CompanionSlimWindow(
            kind: kind, kindName: name, billingPeriodDuration: period,
            percentRemaining: display.percentRemaining, utilization: utilization,
            resetKind: .scheduled, resetDeadline: wire(clock.anchor.addingTimeInterval(resetIn)),
            isSpark: spark)
    }

    static func wire(_ date: Date) throws -> CompanionWireDate {
        guard let value = CompanionWireDate(date: date) else { throw CompanionLeafValidationError.capture }
        return value
    }

    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400

    /// `now` for the variant; `anchor` is what reset deadlines count from (always `now`, so
    /// resets stay in the future); `captureAge` is how old each reading is.
    struct DemoClock {
        let now: Date
        var captureAge: TimeInterval = CompanionDemoData.captureAge
        var anchor: Date

        init(now: Date, captureAge: TimeInterval = CompanionDemoData.captureAge, anchor: Date? = nil) {
            self.now = now
            self.captureAge = captureAge
            self.anchor = anchor ?? now
        }

        var captured: CompanionWireDate {
            CompanionWireDate(date: now.addingTimeInterval(-captureAge)) ?? CompanionWireDate(epochSeconds: 0)!
        }
    }
}
