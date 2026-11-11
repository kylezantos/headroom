import Foundation

/// The phone-bound capture (iPhone parity U5): every account in Make Main order with
/// KTD9 titles and KTD10 attention, banked resets, flagged Spark rows, API spend, the
/// display block and cadence, plus the paired schema-3 phone export of the same state.
@MainActor
extension UsageStore {
    /// KTD22: the Settings footnote's sync status; nil when this launch has no publisher
    /// (demo, test hosts).
    public var phoneSyncStatus: CompanionSyncStatus? {
        (phoneSyncExporter as? CompanionPhoneSync)?.status
    }

    func companionCapture() -> CompanionPublishCapture {
        let stamp = CompanionWireDate(date: now()) ?? CompanionWireDate(epochSeconds: 0)!
        let chosen = max(1, Int(schedulerChosenInterval.rounded()))
        guard syncToIPhoneEnabled else {
            return .disabled(at: stamp, chosenIntervalSeconds: chosen)
        }

        let subscription = providerOrder
        let spendExports = Dictionary(
            uniqueKeysWithValues: apiSpendProviderOrder.compactMap { id in
                apiSpendSnapshots[id].flatMap(CompanionPhoneProjection.spend).map { (id, $0) }
            })
        let spendOrder = apiSpendProviderOrder.filter { spendExports[$0] != nil }
        // A provider key exists while its subscription or its API-spend switch is on
        // (KTD6.1); with only spend on it is spend-only and carries no accounts. A spend
        // row the Mac hides (Cursor with on-demand off) leaves nothing to carry.
        let spendOnly = registeredAPISpendProviderOrder.filter { id in
            !subscription.contains(id) && spendExports[id] != nil
                && UsageSurface.api(for: id).map(enabledSurfaces.contains) == true
        }

        var providers: [CompanionCapturedProvider] = []
        var mainAttention: [ProviderID: CompanionAttention] = [:]
        for id in subscription {
            // KTD8: the capture reads the display projection and its primary. Remembered
            // rows follow the engine rows as extras, flagged (KTD14), under their random
            // local ids; the store serves their aged last reading (U6).
            let projection = displayProjection(for: id)
            let stored = storedOrderAccounts(for: id, projection: projection)
            // The Mac's displayed name (KTD9 amended): the same snapshot email
            // `desktopAccountName(for:)` reads, a remembered row's from its last reading.
            let titles = CompanionPhoneProjection.titles(
                storedOrder: stored,
                emails: stored.reduce(into: [:]) { emails, account in
                    emails[account.id] = snapshot(for: account.key).accountEmail
                },
                usesEmailAsName: useEmailAsAccountName)
            let engineKeys = projection.rows.filter { $0.kind == .engine }.map(\.key)
            var main: CompanionAccountSummary?
            var extras: [CompanionAccountSummary] = []
            for row in projection.rows {
                let account = row.account
                let snapshot = snapshot(for: account.key)
                let title = titles[account.id] ?? account.label
                guard row.kind == .engine else {
                    // R12: never the main account and never a source of attention, so it
                    // carries no attention and no session overlay.
                    if let summary = CompanionPhoneProjection.account(
                        id: account.id, title: title, snapshot: snapshot, attention: nil,
                        isRemembered: true)
                    {
                        extras.append(summary)
                    }
                    continue
                }
                let attention = CompanionAttentionMapping.accountAttention(
                    freshness: snapshot.freshness, isBuiltIn: account.isBuiltIn,
                    session: companionSession(for: account.key))
                let summary = CompanionPhoneProjection.account(
                    id: account.id, title: title,
                    snapshot: snapshot, attention: attention)
                if account.key == projection.primaryKey {
                    main = summary
                    if let attention { mainAttention[id] = attention }
                } else if let summary {
                    extras.append(summary)
                }
            }
            // A main account that cannot form a valid record leaves the key out; the
            // phone then shows this Mac's schema-3 main account (KTD6.3). Such a record
            // needs a live reading with no capture time, which no provider produces.
            guard let main else { continue }
            providers.append(
                CompanionCapturedProvider(
                    providerID: id.raw, mode: .subscription,
                    capabilityAttention: CompanionAttentionMapping.providerAttention(
                        capability: providerCapabilities[id]?.state,
                        sessions: engineKeys.compactMap(companionSession)),
                    mainAccount: main, extraAccounts: extras,
                    apiSpend: spendExports[id],
                    effectiveIntervalSeconds: pollCadence(for: id).effectiveInterval))
        }
        for id in spendOnly {
            providers.append(
                CompanionCapturedProvider(
                    providerID: id.raw, mode: .spendOnly, mainAccount: nil,
                    apiSpend: spendExports[id], effectiveIntervalSeconds: Double(chosen)))
        }

        let selection = resolvedWidgetProviderSelection()
        let primaries = Dictionary(uniqueKeysWithValues: subscription.map { ($0, snapshot(for: $0)) })
        let v3 = WidgetSnapshotProjector.project(
            snapshots: primaries, providerOrder: subscription, displayNames: displayNames,
            renewalDate: { _ in nil }, widgetsEnabled: true, widgetProviderSelection: selection,
            showsCodexSparkCounters: showCodexSparkCountersInWidgets,
            apiSpendSnapshots: apiSpendSnapshots, apiSpendProviderOrder: spendOrder,
            generatedAt: stamp.date, context: .phoneSync(attention: mainAttention))

        return CompanionPublishCapture(
            generatedAt: stamp, status: .enabled, providers: providers,
            providerOrder: subscription.map(\.raw), spendOrder: spendOrder.map(\.raw),
            chosenIntervalSeconds: chosen,
            display: CompanionDisplayBlock(
                meterStyle: meterStyle, percentageMode: usagePercentageMode,
                accountTitleInk: accountTitleInk, appSparkEnabled: showCodexSparkCountersInApp),
            // The same normalized selection the schema-3 export carries (KTD13).
            widgetProviderSelection: v3.widgetProviderSelection,
            widgetSparkEnabled: showCodexSparkCountersInWidgets,
            reminderSummary: companionReminderSummary(),
            answeredRequests: checkNowAnsweredRequests, v3: v3)
    }

    /// KTD9: suffixes follow stored registry order, never the main-first display order.
    /// Remembered rows follow in their stored order, so a remembered "Work" beside a live
    /// "Work" takes the suffix and the live row keeps its name.
    private func storedOrderAccounts(
        for id: ProviderID, projection: DisplayAccountsProjection
    ) -> [ProviderAccount] {
        let visible = projection.rows.filter { $0.kind == .engine }.map(\.account)
        let remembered = projection.rows.filter { $0.kind == .remembered }.map(\.account)
        guard let accountRegistry else { return visible + remembered }
        let stored = accountRegistry.storedOrderAccounts(for: id, capacity: accountCapacity(for: id))
            .map(\.id)
        let ordered = stored.compactMap { storedID in visible.first { $0.id == storedID } }
        return ordered + visible.filter { account in !stored.contains(account.id) } + remembered
    }

    /// The typed overlay of a live setup session (KTD10). Only the typed state and
    /// purpose cross; no title, path or source string.
    private func companionSession(for key: AccountKey) -> CompanionSessionInput? {
        if let companionSessionLookup { return companionSessionLookup(key) }
        guard let setupCoordinator else { return nil }
        let state = setupCoordinator.state(for: key)
        guard state != .idle else { return nil }
        return CompanionSessionInput(
            state: state,
            purpose: setupCoordinator.sessionPurpose(for: key),
            interactiveReason: companionInteractiveReasonLookup?(key)
        )
    }

    /// KTD19: a read-only summary of the Notifications pane. The phone channel switch
    /// arrives with U16; until then it reports off.
    private func companionReminderSummary() -> CompanionReminderSummary {
        CompanionReminderSummary(
            macUseItUpEnabled: useItUpRemindersEnabled,
            macBankedResetEnabled: bankedResetNotificationsEnabled,
            phoneChannelEnabled: false,
            rules: reminderRules.compactMap { rule in
                guard let unit = CompanionReminderUnit(rawValue: rule.unit.rawValue) else { return nil }
                return try? CompanionReminderRuleSummary(
                    amount: rule.amount, unit: unit, threshold: rule.threshold)
            },
            scope: ReminderScope.allCases.filter(reminderScope.contains).compactMap {
                CompanionReminderScope(rawValue: $0.rawValue)
            })
    }
}
