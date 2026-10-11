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
@Suite(.serialized)
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

    @Test func aLayoutChangeReplansFromFreshHeights() async {
        let model = PopoverPlanModel(cap: 640)
        let all = slots(.claude, 7) + slots(.codex, 1)
        model.update(slots: all)
        await measure(model, all, height: 74)
        #expect(model.plan?.columnCount == 2)
        model.layoutDidChange()
        await measure(model, all, height: 26)
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

    private func host(_ store: UsageStore) async -> Hosted {
        let hosting = NSHostingView(rootView: AnyView(PopoverView(store: store, onOpenSettings: {})))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 900),
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

    private func store(_ pairs: [(account: ProviderAccount, provider: any UsageProvider)]) async -> UsageStore {
        let prefs = Preferences(defaults: defaults())
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
}
