import AppKit
import Foundation
import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

/// U5 (popover account layout plan): the popover flows accounts into a second column only past
/// the cards-height cap (R4), pins exactly one or two card widths (R7), keeps its plan while
/// heights change (R6), and splits a provider card so that only the first piece carries a
/// capability header (R9, KTD6).
@MainActor
@Suite(.sharedAppState, .serialized)
struct PopoverColumnsSizingTests {
    // MARK: Plan model

    private func slots(_ provider: ProviderID, _ count: Int) -> [PopoverColumnSlot] {
        (0..<count).map { PopoverColumnSlot(id: "\(provider.raw)/\($0)", providerID: provider) }
    }

    private func measure(_ model: PopoverPlanModel, _ slots: [PopoverColumnSlot], height: CGFloat) async {
        for slot in slots { model.record(slot.isSpend ? 40 : height, for: slot.id) }
        await afterLayout()
    }

    /// Heights arrive during layout, so the replan they complete runs on the next main turn.
    private func afterLayout() async {
        try? await Task.sleep(for: .milliseconds(5))
    }

    @Test func thePlanWaitsForEveryHeightThenSplitsPastTheCap() async {
        let model = PopoverPlanModel(cap: 640)
        let all = slots(.claude, 7) + slots(.codex, 1)
        model.update(slots: all)
        #expect(model.plan == nil)
        #expect(model.drawnPlan(for: all).columnCount == 1)
        await measure(model, Array(all.dropLast()), height: 74)
        #expect(model.plan == nil)
        model.record(74, for: all.last!.id)
        await afterLayout()
        let plan = try! #require(model.plan)
        #expect(plan.columnCount == 2)
        #expect(plan.itemIDs.first == "claude/0")
    }

    /// GF2: heights saved at the last close plan the first open's columns before it draws, so
    /// it never shows one column and then two.
    @Test func savedHeightsPlanTheFirstDrawBeforeAnyMeasurement() {
        let all = slots(.claude, 7) + slots(.codex, 1)
        let saved = Dictionary(uniqueKeysWithValues: all.map { ($0.id, 74.0) })
        var asked: [PopoverHeightsKey] = []
        let model = PopoverPlanModel(cap: 640, savedHeights: { key in
            asked.append(key)
            return saved
        })
        #expect(model.drawnPlan(for: all, layout: .standard).columnCount == 2)
        #expect(model.plan?.columnCount == 2)
        #expect(asked == [PopoverHeightsKey(layout: .standard, format: .micro)])
        // The onChange handlers that run after the first pass find nothing to change.
        model.update(slots: all)
        model.setLayout(.standard)
        model.setAllowsHorizontalExpansion(true)
        #expect(model.drawnPlan(for: all, layout: .standard).columnCount == 2)
        #expect(asked == [PopoverHeightsKey(layout: .standard, format: .micro)])
    }

    /// GF2: a new install has no saved heights; the estimate plans the first draw instead.
    @Test func estimatesPlanTheFirstDrawWhenNothingWasSaved() async {
        let all = slots(.claude, 7) + slots(.codex, 1)
        let model = PopoverPlanModel(cap: 640)
        let estimate = PopoverHeightEstimate.account(windows: 2, layout: .standard, format: .micro)
        #expect(model.drawnPlan(for: all, layout: .standard, estimatedHeights: {
            Dictionary(uniqueKeysWithValues: all.map { ($0.id, estimate) })
        }).columnCount == 2)
        // Real heights replace the estimate but never replan while the popover is open (R6).
        await measure(model, all, height: 30)
        #expect(model.drawnPlan(for: all).columnCount == 2)
        model.popoverDidClose()
        #expect(model.drawnPlan(for: all).columnCount == 1)
    }

    /// A saved height wins over the estimate; a slot with neither waits for its measurement.
    @Test func savedHeightsWinAndAnUnknownSlotWaits() async {
        let all = slots(.claude, 7) + slots(.codex, 1)
        let saved = Dictionary(uniqueKeysWithValues: all.dropLast().map { ($0.id, 74.0) })
        let model = PopoverPlanModel(cap: 640, savedHeights: { _ in saved })
        #expect(model.drawnPlan(for: all, layout: .standard, estimatedHeights: { [:] }).columnCount == 1)
        model.update(slots: all)
        model.record(74, for: all.last!.id)
        await afterLayout()
        #expect(model.plan?.columnCount == 2)
    }

    /// The estimate reproduces the heights the popover drew in the 2026-11-25 renders.
    @Test func theEstimateMatchesMeasuredSectionHeights() {
        let micro = (1...4).map { PopoverHeightEstimate.account(windows: $0, layout: .standard, format: .micro) }
        #expect(micro == [44, 75, 106, 137])
        let full = (1...4).map { PopoverHeightEstimate.account(windows: $0, layout: .standard, format: .full) }
        #expect(full == [59, 107, 155, 203])
        #expect(PopoverHeightEstimate.account(windows: 0, layout: .standard, format: .micro) == 51)
        #expect(PopoverHeightEstimate.account(windows: 3, layout: .compact, format: .micro) == 26)
        #expect(PopoverHeightEstimate.account(windows: 0, layout: .compact, format: .micro) == 73)
        #expect(PopoverHeightEstimate.spend(providers: 2, layout: .standard) == 51)
        #expect(PopoverHeightEstimate.spend(providers: 2, layout: .compact) == 82)
    }

    @Test func closingSavesTheHeightsForTheLayoutAndFormatItDrew() async {
        var saved: [PopoverHeightsKey: [String: Double]] = [:]
        let model = PopoverPlanModel(cap: 640, saveHeights: { heights, key in saved[key] = heights })
        let all = slots(.claude, 3)
        _ = model.drawnPlan(for: all, layout: .compact, format: .full)
        model.update(slots: all)
        model.setLayout(.compact)
        await measure(model, all, height: 30)
        model.popoverDidClose()
        #expect(saved[PopoverHeightsKey(layout: .compact, format: .full)]
                == Dictionary(uniqueKeysWithValues: all.map { ($0.id, 30.0) }))
        #expect(saved.count == 1)
    }

    /// A first pass with no slots yet leaves the seed for the pass that has them.
    @Test func anEmptyFirstPassDoesNotUseUpTheSeed() {
        let all = slots(.claude, 7) + slots(.codex, 1)
        let saved = Dictionary(uniqueKeysWithValues: all.map { ($0.id, 74.0) })
        let model = PopoverPlanModel(cap: 640, savedHeights: { _ in saved })
        #expect(model.drawnPlan(for: []).columnCount == 1)
        #expect(model.drawnPlan(for: all).columnCount == 2)
    }

    /// Vertical-only: the seed plans one column without writing the observed preference.
    @Test func seedingInVerticalOnlyModePlansOneColumn() {
        let all = slots(.claude, 20)
        let saved = Dictionary(uniqueKeysWithValues: all.map { ($0.id, 74.0) })
        let model = PopoverPlanModel(cap: 640, savedHeights: { _ in saved })
        #expect(model.drawnPlan(for: all, allowsHorizontalExpansion: false).columnCount == 1)
        #expect(model.plan?.columnCount == 1)
        model.setAllowsHorizontalExpansion(false)
        #expect(model.drawnPlan(for: all, allowsHorizontalExpansion: false).columnCount == 1)
    }

    @Test func expansionCanBeSwitchedWithoutNewHeightReports() async {
        let model = PopoverPlanModel(cap: 640)
        let all = slots(.claude, 20)
        model.update(slots: all)
        await measure(model, all, height: 74)
        #expect(model.drawnPlan(for: all).columnCount == 2)
        // The view can draw the preference before its onChange configures the model.
        #expect(model.drawnPlan(for: all, allowsHorizontalExpansion: false).columnCount == 1)
        model.setAllowsHorizontalExpansion(false)
        #expect(model.plan?.columnCount == 1)
        model.popoverDidClose()
        #expect(model.drawnPlan(for: all).columnCount == 1)
        model.setAllowsHorizontalExpansion(true)
        #expect(model.plan?.columnCount == 2)
    }

    @Test func disablingExpansionDoesNotCarryTwoColumnsWhileANewRowIsUnmeasured() async {
        let model = PopoverPlanModel(cap: 640)
        var all = slots(.claude, 20)
        model.update(slots: all)
        await measure(model, all, height: 74)
        all += slots(.codex, 1)
        model.update(slots: all)
        model.setAllowsHorizontalExpansion(false)
        #expect(model.drawnPlan(for: all).columnCount == 1)
        model.record(74, for: all.last!.id)
        await afterLayout()
        #expect(model.plan?.columnCount == 1)
    }

    @Test func aHeightChangeWhileOpenKeepsThePlanUntilThePopoverCloses() async {
        let model = PopoverPlanModel(cap: 640)
        let all = slots(.claude, 5)
        model.update(slots: all)
        await measure(model, all, height: 74)
        #expect(model.plan?.columnCount == 1)
        // Data lands and every section grows past the cap: same plan while open (R6).
        await measure(model, all, height: 160)
        #expect(model.plan?.columnCount == 1)
        model.popoverDidClose()
        #expect(model.plan?.columnCount == 2)
    }

    @Test func anAccountSetChangeCarriesTwoColumnsUntilTheNewAccountIsMeasured() async {
        let model = PopoverPlanModel(cap: 640)
        var all = slots(.claude, 7) + slots(.codex, 1)
        model.update(slots: all)
        await measure(model, all, height: 74)
        let before = try! #require(model.plan)
        all.insert(PopoverColumnSlot(id: "claude/new", providerID: .claude), at: 1)
        model.update(slots: all)
        #expect(model.plan == before)
        #expect(model.drawnPlan(for: all).columnCount == 2)
        model.record(74, for: "claude/new")
        await afterLayout()
        #expect(model.plan?.itemIDs == all.map(\.id))
    }

    /// The spend card reports its height only when it changes, so a layout switch that leaves it
    /// alone must replan from the account sections' new heights without it reporting again.
    @Test func aLayoutChangeReplansFromTheSectionsItRedraws() async {
        let model = PopoverPlanModel(cap: 640)
        let accounts = slots(.claude, 7) + slots(.codex, 1)
        let all = accounts + [.spend]
        model.setLayout(.standard)
        model.update(slots: all)
        await measure(model, all, height: 74)
        #expect(model.plan?.columnCount == 2)
        model.setLayout(.compact)
        await measure(model, accounts, height: 26)
        #expect(model.plan?.columnCount == 1)
    }

    /// 13 rows of 26pt: Standard's 26pt gap stacks 13·26 + 12·26 + 26 = 676 (past the cap),
    /// Compact's 4pt gap 13·26 + 12·4 + 26 = 412.
    @Test func compactPlansWithItsOwnAccountGap() async {
        let model = PopoverPlanModel(cap: 640)
        let all = slots(.claude, 13)
        model.setLayout(.standard)
        model.update(slots: all)
        await measure(model, all, height: 26)
        #expect(model.plan?.columnCount == 2)
        model.setLayout(.compact)
        await measure(model, all, height: 26)
        model.popoverDidClose()
        #expect(model.plan?.columnCount == 1)
    }

    @Test func aCapabilityHeaderIsFoldedIntoTheProvidersFirstItem() async {
        let model = PopoverPlanModel(cap: 640)
        let claude = [
            PopoverColumnSlot(id: "claude/0", providerID: .claude, headerID: "header:claude"),
            PopoverColumnSlot(id: "claude/1", providerID: .claude),
        ]
        model.update(slots: claude)
        await measure(model, claude, height: 74)
        #expect(model.plan == nil)
        model.record(400, for: "header:claude")
        await afterLayout()
        // 13 + (400 + 26 + 74) + 26 + 74 + 13 = 626: still under the cap.
        #expect(model.plan?.columnCount == 1)
        model.record(420, for: "header:claude")
        await afterLayout()
        model.popoverDidClose()
        #expect(model.plan?.columnCount == 2)
    }

    // MARK: Card slots and fragments (KTD6, R9)

    private func entries(_ provider: ProviderID, _ count: Int, pendingAfter: Int = .max) -> [ProviderAccountEntry] {
        (0..<count).map { index in
            let account = index == 0
                ? ProviderAccount.builtIn(for: provider)
                : ProviderAccount(id: AccountID("\(provider.raw)-\(index)"), providerID: provider, label: "Account \(index)")
            let snapshot = index >= pendingAfter ? UsageSnapshot.pending(for: provider) : DemoFixture.claudeSnapshot
            return ProviderAccountEntry(account: account, snapshot: snapshot)
        }
    }

    @Test func aMultiAccountCardOffersOneSlotPerAccountWithoutAHeader() {
        let slots = ProviderCardView.columnSlots(providerID: .claude, entries: entries(.claude, 3), capabilityStatus: nil)
        #expect(slots.count == 3)
        #expect(slots.allSatisfy { $0.headerID == nil })
    }

    /// Kyle, 2026-10-13: a Compact card repeats its column header in each column, so a split
    /// card's slots carry the header for the planner; Standard and a card with no Compact row
    /// carry none.
    @Test func compactCardSlotsCarryTheirRepeatedHeader() {
        let compact = ProviderCardView.columnSlots(
            providerID: .claude, entries: entries(.claude, 3), capabilityStatus: nil, accountLayout: .compact
        )
        #expect(compact.allSatisfy { $0.fragmentHeader == Double(CompactCardHeader.height) })
        let standard = ProviderCardView.columnSlots(
            providerID: .claude, entries: entries(.claude, 3), capabilityStatus: nil, accountLayout: .standard
        )
        #expect(standard.allSatisfy { $0.fragmentHeader == 0 })
    }

    @Test func compactColumnsFollowTheAccountShowingTheMostWindows() {
        let columns = ProviderCardView.compactColumns(entries: entries(.claude, 2), showsCodexSparkCounters: false)
        #expect(columns?.map(\.persistentID) == ["fiveHour", "weekly"])
        let pendingOnly = entries(.claude, 2, pendingAfter: 0)
        #expect(ProviderCardView.compactColumns(entries: pendingOnly, showsCodexSparkCounters: false) == [])
    }

    /// The Compact header follows "Show 5-hour windows": with it off, Antigravity's columns
    /// are its two weekly rows, the same rows the Standard section draws.
    @Test func compactColumnsFollowTheAntigravityFiveHourSwitch() {
        let rows = UsageSnapshot(providerID: .antigravity, windows: [
            UsageWindow(kind: .other("Gemini 5h"), utilization: 20, resetsAt: Date().addingTimeInterval(3_600)),
            UsageWindow(kind: .other("Gemini weekly"), utilization: 40, resetsAt: Date().addingTimeInterval(86_400)),
            UsageWindow(kind: .other("Other 5h"), utilization: 90, resetsAt: Date().addingTimeInterval(3_600)),
            UsageWindow(kind: .other("Other weekly"), utilization: 50, resetsAt: Date().addingTimeInterval(86_400)),
        ], planLabel: nil, capturedAt: Date(), freshness: .live)
        let entries = [ProviderAccountEntry(account: .builtIn(for: .antigravity), snapshot: rows)]
        let shown = ProviderCardView.compactColumns(entries: entries, showsCodexSparkCounters: false)
        #expect(shown?.map(\.persistentID).contains("other:Other 5h") == true)
        let hidden = ProviderCardView.compactColumns(
            entries: entries, showsCodexSparkCounters: false, showsAntigravityFiveHourWindows: false)
        #expect(hidden?.map(\.persistentID) == ["other:Gemini weekly", "other:Other weekly"])
    }

    @Test func aSingleAccountCardIsOneWholeSlot() {
        let slots = ProviderCardView.columnSlots(providerID: .codex, entries: entries(.codex, 1), capabilityStatus: nil)
        #expect(slots.map(\.id) == ["card:codex"])
    }

    @Test func aCapabilityCardFoldsItsHeaderIntoItsFirstDrawnAccountOnly() {
        let status = ProviderCapabilityStatus(state: .confirmedAbsent, observedAt: Date())
        let slots = ProviderCardView.columnSlots(
            providerID: .claude, entries: entries(.claude, 4, pendingAfter: 3), capabilityStatus: status
        )
        // The capability body leaves out accounts still waiting on a first reading.
        #expect(slots.count == 3)
        #expect(slots.first?.headerID == "header:claude")
        #expect(slots.dropFirst().allSatisfy { $0.headerID == nil })
    }

    @Test func aSplitProviderGivesTwoFragmentsAndOnlyTheFirstLeadsTheCard() {
        let all = slots(.claude, 7) + [PopoverColumnSlot(id: "card:codex", providerID: .codex), .spend]
        let plan = AccountColumnsPlan(columnCount: 2, splitIndex: 4, itemIDs: all.map(\.id), generation: 0)
        let fragments = PopoverCardFragment.fragments(slots: all, plan: plan)
        #expect(fragments.map(\.id) == ["claude#0", "claude#1", "codex#0", "spend#0"])
        #expect(fragments.map(\.accountRange) == [0..<4, 4..<7, nil, nil])
        #expect(fragments.map(\.isFirstFragment) == [true, false, true, true])
        #expect(fragments.map(\.column) == [0, 1, 1, 1])
    }

    @Test func anUnsplitProviderDrawsItsWholeCard() {
        let all = slots(.claude, 3) + [PopoverColumnSlot(id: "card:codex", providerID: .codex)]
        let plan = AccountColumnsPlan(columnCount: 1, splitIndex: 4, itemIDs: all.map(\.id), generation: 0)
        let fragments = PopoverCardFragment.fragments(slots: all, plan: plan)
        #expect(fragments.map(\.accountRange) == [nil, nil])
        #expect(fragments.allSatisfy { $0.column == 0 && $0.isFirstFragment })
    }

    @Test func shellWidthsAreOneOrExactlyTwoCards() {
        #expect(PopoverCardMetrics.shellWidth(columns: 1) == 384)
        #expect(PopoverCardMetrics.shellWidth(columns: 2) == 750)
        #expect(PopoverCardMetrics.shellWidth(columns: 1) == PopoverCardMetrics.shellWidth)
        // The planner's card width is the shell's inner width (R2C20's specimen reads it too).
        #expect(PopoverCardMetrics.cardWidth == PopoverCardMetrics.shellWidth - 2 * PopoverCardMetrics.shellMargin)
    }

    // MARK: Hosted popover (R4, R7, R8)

    @MainActor
    private struct Hosted {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow

        func settle(turns: Int = 40) async {
            for _ in 0..<turns {
                try? await Task.sleep(for: .milliseconds(5))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
        }

        var size: CGSize { hosting.fittingSize }

        /// The cards' scroll view: its viewport and its content height.
        var scroll: (viewport: CGFloat, content: CGFloat)? {
            func find(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                for child in view.subviews { if let found = find(child) { return found } }
                return nil
            }
            guard let scroll = find(hosting) else { return nil }
            return (scroll.contentView.bounds.height, scroll.documentView?.frame.height ?? 0)
        }

        /// Set `TEST_RUNNER_HEADROOM_COLUMNS_SNAPSHOT_DIR` to keep a PNG of each hosted
        /// popover for a visual check (not evidence: the shell's glass doesn't rasterize).
        func snapshot(_ name: String) {
            guard let dir = ProcessInfo.processInfo.environment["HEADROOM_COLUMNS_SNAPSHOT_DIR"] else { return }
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }

        func teardown() {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
    }

    private func host(_ store: UsageStore, visibleScreenHeight: CGFloat? = nil) async -> Hosted {
        let hosting = NSHostingView(rootView: AnyView(PopoverView(
            store: store, onOpenSettings: {}, visibleScreenHeightOverride: visibleScreenHeight
        )))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 1100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.contentView = hosting
        window.orderFrontRegardless()
        let hosted = Hosted(hosting: hosting, window: window)
        await hosted.settle()
        return hosted
    }

    private func defaults() -> UserDefaults {
        let name = "co.zantos.headroom.popover-columns.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func store(
        _ pairs: [(account: ProviderAccount, provider: any UsageProvider)],
        layout: AccountLayout = .standard
    ) async -> UsageStore {
        let prefs = Preferences(defaults: defaults())
        prefs.accountLayout = layout
        for id in Set(pairs.map(\.account.providerID)) {
            if let surface = UsageSurface.subscription(for: id) { prefs.setSurfaceEnabled(true, for: surface) }
        }
        let registry = AccountRegistry(defaults: defaults())
        registry.seed(pairs.map(\.account))
        let store = UsageStore(
            providers: pairs.map(\.provider),
            preferences: prefs,
            accounts: pairs.map(\.account),
            accountRegistry: registry,
            providerFactory: { account in
                DemoUsageProvider(
                    id: account.providerID, displayName: account.providerID.displayName,
                    snapshot: .pending(for: account.providerID), accountID: account.id
                )
            }
        )
        await store.refreshAll()
        return store
    }

    @Test func oneAccountKeepsTheSingleColumnWidth() async {
        let store = await store([(
            ProviderAccount.builtIn(for: .claude),
            DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot)
        )])
        let hosted = await host(store)
        defer { hosted.teardown() }
        hosted.snapshot("single")
        #expect(hosted.size.width == 384)
        let scroll = try! #require(hosted.scroll)
        #expect(scroll.content <= scroll.viewport + 0.5)
    }

    @Test func sevenClaudeAndOneCodexTakeTwoColumnsWithoutScrolling() async {
        let fixture = DemoFixture.multiFixture(for: .multiSeven)
        let hosted = await host(await store(Array(zip(fixture.accounts, fixture.providers))))
        defer { hosted.teardown() }
        hosted.snapshot("multi-7")
        #expect(hosted.size.width == 750)
        let scroll = try! #require(hosted.scroll)
        #expect(scroll.viewport < PopoverCardMetrics.cardsHeightCap)
        #expect(scroll.content <= scroll.viewport + 0.5)
    }

    @Test func theEnvelopeTakesTwoColumnsAndScrollsAtTheCap() async {
        let pairs = DemoFixture.generatedAccounts(provider: .claude, count: 20)
            + DemoFixture.generatedAccounts(provider: .codex, count: 20)
        let hosted = await host(await store(pairs))
        defer { hosted.teardown() }
        hosted.snapshot("multi-20")
        #expect(hosted.size.width == 750)
        let scroll = try! #require(hosted.scroll)
        #expect(abs(scroll.viewport - PopoverCardMetrics.cardsHeightCap) < 0.5)
        #expect(scroll.content > scroll.viewport)
    }

    @Test(arguments: AccountLayout.allCases, [CGFloat(700), CGFloat(1440)])
    func verticalOnlyAccountsScrollAtTheCapAndCanExpandAgain(
        layout: AccountLayout, visibleScreenHeight: CGFloat
    ) async {
        let pairs = DemoFixture.generatedAccounts(provider: .claude, count: 20)
            + DemoFixture.generatedAccounts(provider: .codex, count: 20)
        let store = await store(pairs, layout: layout)
        store.setExpandAccountsHorizontally(false)
        let hosted = await host(store, visibleScreenHeight: visibleScreenHeight)
        defer { hosted.teardown() }
        #expect(hosted.size.width == 384)
        let scroll = try! #require(hosted.scroll)
        let expectedViewport: CGFloat = visibleScreenHeight == 700 ? 547 : 900
        #expect(abs(scroll.viewport - expectedViewport) < 0.5)
        #expect(scroll.content > scroll.viewport)
        store.setExpandAccountsHorizontally(true)
        await hosted.settle()
        #expect(hosted.size.width == 750)
        store.setExpandAccountsHorizontally(false)
        await hosted.settle()
        #expect(hosted.size.width == 384)
    }

    @Test func aFewVerticalOnlyAccountsFitWithoutScrollingOnATallScreen() async {
        let store = await store(DemoFixture.generatedAccounts(provider: .claude, count: 3))
        store.setExpandAccountsHorizontally(false)
        let hosted = await host(store, visibleScreenHeight: 1440)
        defer { hosted.teardown() }
        let scroll = try! #require(hosted.scroll)
        #expect(scroll.viewport < 900)
        #expect(abs(scroll.viewport - scroll.content) < 0.5)
    }

    // MARK: Compact (R11, R15)

    @Test func sevenClaudeAndOneCodexFitOneCompactColumn() async {
        let fixture = DemoFixture.multiFixture(for: .multiSeven)
        let hosted = await host(await store(Array(zip(fixture.accounts, fixture.providers)), layout: .compact))
        defer { hosted.teardown() }
        hosted.snapshot("compact-multi-7")
        #expect(hosted.size.width == 384)
        let scroll = try! #require(hosted.scroll)
        #expect(scroll.content <= scroll.viewport + 0.5)
    }

    @Test func theEnvelopeTakesTwoCompactColumns() async {
        let pairs = DemoFixture.generatedAccounts(provider: .claude, count: 20)
            + DemoFixture.generatedAccounts(provider: .codex, count: 20)
            + DemoFixture.generatedAccounts(provider: .grok, count: 20)
        let hosted = await host(await store(pairs, layout: .compact))
        defer { hosted.teardown() }
        hosted.snapshot("compact-multi-20")
        #expect(hosted.size.width == 750)
    }

    /// R15: a signed-out account keeps its Standard section — and so its sign-in action — in
    /// place among Compact rows, which makes its card taller than an all-Compact one.
    @Test func aSignedOutAccountKeepsItsStandardSectionInCompact() async {
        var pairs = DemoFixture.generatedAccounts(provider: .claude, count: 3)
        let allCompact = await host(await store(pairs, layout: .compact))
        let compactHeight = allCompact.size.height
        allCompact.teardown()
        let signedOut = pairs[1].account
        pairs[1] = (signedOut, DemoUsageProvider(
            id: .claude, displayName: "Claude",
            snapshot: .stale(for: .claude, reason: .notLoggedIn(UsageStore.finishSignInMessage)),
            accountID: signedOut.id
        ))
        let hosted = await host(await store(pairs, layout: .compact))
        defer { hosted.teardown() }
        hosted.snapshot("compact-signed-out")
        #expect(hosted.size.height > compactHeight + 20)
    }

    @Test func verticalOnlyCapUsesScreenSpaceUpTo900Points() {
        #expect(PopoverCardMetrics.verticalCardsHeightCap(visibleScreenHeight: 300) == 300)
        #expect(PopoverCardMetrics.verticalCardsHeightCap(visibleScreenHeight: 700) == 547)
        #expect(PopoverCardMetrics.verticalCardsHeightCap(visibleScreenHeight: 1000) == 847)
        #expect(PopoverCardMetrics.verticalCardsHeightCap(visibleScreenHeight: 1440) == 900)
        #expect(PopoverCardMetrics.verticalCardsHeightCap(visibleScreenHeight: nil) == 640)
    }
}
