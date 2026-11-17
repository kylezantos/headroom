import AppKit
import Foundation
import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

/// SQ1 (macOS 15.0 report, 2026-10-11: "The header 'Usage' is clipped"): when the popover's
/// window is shorter than its content, the header must stay in the window and the card list
/// gives up the difference. OS-independent: the window here is sized by hand, the way a
/// `MenuBarExtra` window that grew late or too little would be.
@MainActor
@Suite(.sharedAppState, .serialized)
struct PopoverWindowHeightFitTests {
    // MARK: Hosted popover in a short window

    /// Where the header title landed, in the hosting view's top-left coordinates.
    @MainActor
    private final class TitleProbe {
        var frame: CGRect?
    }

    @MainActor
    private struct Hosted {
        let hosting: NSHostingView<AnyView>
        let window: NSWindow
        let title: TitleProbe

        func settle(turns: Int = 40) async {
            for _ in 0..<turns {
                try? await Task.sleep(for: .milliseconds(5))
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
        }

        /// Resizes the window with its top edge kept, as under the status item.
        func resize(height: CGFloat, width: CGFloat) {
            let top = window.frame.maxY
            window.setFrame(NSRect(x: window.frame.minX, y: top - height, width: width, height: height), display: false)
        }

        /// The cards' scroll viewport height.
        var viewport: CGFloat? {
            func find(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                for child in view.subviews { if let found = find(child) { return found } }
                return nil
            }
            return find(hosting)?.contentView.bounds.height
        }

        func teardown() {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
    }

    /// Far off every display, below the wallpaper and never key: nothing reaches the screen.
    private static let parkedOrigin = NSPoint(x: -20_000, y: -20_000)

    /// Hosts the popover at its own fitting size, then shortens the window by `shortfall` from
    /// the bottom (top edge kept, as under the status item). The hosting view's sizing options
    /// are cleared first so it can't push the window back to its fitting size: the
    /// `MenuBarExtra` window keeps whatever height its host gave it.
    private func host(_ store: UsageStore, shortfall: CGFloat) async -> (Hosted, fitting: NSSize, viewport: CGFloat) {
        let hosted = await hostInWindow(store, fitsWindow: false)
        await hosted.settle()
        let fitting = hosted.hosting.fittingSize
        hosted.hosting.sizingOptions = []
        hosted.resize(height: fitting.height, width: fitting.width)
        await hosted.settle()
        let fullViewport = hosted.viewport ?? 0
        hosted.resize(height: fitting.height - shortfall, width: fitting.width)
        await hosted.settle()
        return (hosted, fitting, fullViewport)
    }

    /// The popover in a parked 800×900 window, inside a plain container: as a window's content
    /// view, a hosting view sizes the window to the content whatever its sizing options.
    private func hostInWindow(_ store: UsageStore, fitsWindow: Bool) async -> Hosted {
        let probe = TitleProbe()
        let root = PopoverView(store: store, onOpenSettings: {}, fitsMenuBarWindowHeight: fitsWindow)
            .overlayPreferenceValue(PopoverHeaderTitleAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    let frame = anchor.map { proxy[$0].offsetBy(dx: proxy.frame(in: .global).minX, dy: proxy.frame(in: .global).minY) }
                    Color.clear.onChange(of: frame, initial: true) { probe.frame = frame }
                }
            }
        let hosting = NSHostingView(rootView: AnyView(root))
        let window = NSWindow(
            contentRect: NSRect(origin: Self.parkedOrigin, size: NSSize(width: 800, height: 900)),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 900))
        window.contentView = container
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.orderFrontRegardless()
        return Hosted(hosting: hosting, window: window, title: probe)
    }

    private func defaults() -> UserDefaults {
        let name = "co.zantos.headroom.popover-height-fit.\(UUID().uuidString)"
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

    private func singleClaude() async -> UsageStore {
        await store([(
            ProviderAccount.builtIn(for: .claude),
            DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot)
        )])
    }

    private func multiSeven() async -> UsageStore {
        let fixture = DemoFixture.multiFixture(for: .multiSeven)
        return await store(Array(zip(fixture.accounts, fixture.providers)))
    }

    @Test(arguments: [false, true])
    func theHeaderStaysInAWindowShorterThanItsContent(multiAccount: Bool) async throws {
        let store = multiAccount ? await multiSeven() : await singleClaude()
        let (hosted, fitting, fullViewport) = await host(store, shortfall: 120)
        defer { hosted.teardown() }
        // The window really is shorter than the popover wants.
        #expect(abs(hosted.window.frame.height - (fitting.height - 120)) < 0.5)
        let title = try #require(hosted.title.frame)
        let bounds = hosted.hosting.bounds
        #expect(title.minY >= bounds.minY - 0.5)
        #expect(title.maxY <= bounds.maxY + 0.5)
        // The 19pt shell margin still sits above the title's line box.
        #expect(title.minY >= PopoverCardMetrics.shellMargin - 1)
        // The scrollable card list gives up the difference, so header and footer both stay.
        let viewport = try #require(hosted.viewport)
        #expect(abs(viewport - (fullViewport - 120)) < 1)
    }

    /// The macOS 15 path, forced on: the fitter shrinks a too-tall window to the content and
    /// grows a too-short one back on the next open, its top edge kept.
    ///
    /// This proves the fitter's own wiring against a plain test window only. It says nothing
    /// about whether a real macOS 15 `MenuBarExtra` window accepts the frame and keeps it; that
    /// is a device check (BUGS.md).
    @Test func theForcedFitterResizesAPlainTestWindowWithItsTopKept() async throws {
        PopoverWindowHeightFitter.debugOverride = true
        defer { PopoverWindowHeightFitter.debugOverride = nil }
        let store = await singleClaude()
        // The content's own size, from a reference host with no fitter.
        let reference = await hostInWindow(store, fitsWindow: false)
        await reference.settle()
        let ideal = reference.hosting.fittingSize
        reference.teardown()
        #expect(ideal.height > 100)

        let hosted = await hostInWindow(store, fitsWindow: true)
        defer { hosted.teardown() }
        hosted.hosting.sizingOptions = []
        let top = hosted.window.frame.maxY
        await hosted.settle()
        // Shrink: 900pt down to the content, top kept.
        #expect(abs(hosted.window.frame.height - ideal.height) < 0.5)
        #expect(abs(hosted.window.frame.maxY - top) < 0.5)

        // A host that hands back a window 120pt short, then the popover opens again.
        hosted.resize(height: ideal.height - 120, width: ideal.width)
        hosted.hosting.removeFromSuperview()
        await hosted.settle(turns: 4)
        hosted.window.contentView?.addSubview(hosted.hosting)
        hosted.hosting.frame = hosted.window.contentView?.bounds ?? .zero
        await hosted.settle()
        #expect(abs(hosted.window.frame.height - ideal.height) < 0.5)
        #expect(abs(hosted.window.frame.maxY - top) < 0.5)
        let title = try #require(hosted.title.frame)
        #expect(title.minY >= PopoverCardMetrics.shellMargin - 1)
    }

    // MARK: Host chrome rounding (SQ2)

    /// Hosted as the window's content view, the way `MenuBarExtra` hosts it, the popover's
    /// window chrome (PC1) rounds only leaves that span the content. On macOS 15.7.7 the header's
    /// title, status line and gear were such leaves and drew pill-clipped. On macOS 26 the leaves
    /// here are small `KeyViewProxy` views that draw nothing; before SQ2 they were rounded too,
    /// which is what this test catches on a 26 host.
    @Test(arguments: [false, true])
    func theHostChromeRoundsOnlyLeavesSpanningTheContent(multiAccount: Bool) async throws {
        let store = multiAccount ? await multiSeven() : await singleClaude()
        let hosting = NSHostingView(rootView: AnyView(
            PopoverView(store: store, onOpenSettings: {}, fitsMenuBarWindowHeight: false)
        ))
        let window = NSWindow(
            contentRect: NSRect(origin: Self.parkedOrigin, size: NSSize(width: 384, height: 600)),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.contentView = hosting
        window.orderFrontRegardless()
        let hosted = Hosted(hosting: hosting, window: window, title: TitleProbe())
        defer { hosted.teardown() }
        await hosted.settle()

        let bounds = hosting.bounds
        #expect(bounds.height > 100)
        let radius = HeadroomTuning().shellCornerRadius
        for leaf in hosting.subviews where leaf.subviews.isEmpty {
            guard !PopoverHostBackdrop.spansContent(leaf.frame, bounds: bounds, cornerRadius: radius),
                  let layer = leaf.layer else { continue }
            #expect(!(layer.masksToBounds && layer.cornerRadius == radius), "\(type(of: leaf)) \(leaf.frame)")
        }
    }

    // MARK: Frame math (pure)

    private let current = NSRect(x: 100, y: 400, width: 384, height: 300)

    @Test func aFittedFrameKeepsItsTopEdgeAndWidth() throws {
        let grown = try #require(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 420))
        #expect(grown.maxY == current.maxY)
        #expect(grown.height == 420)
        #expect(grown.minX == current.minX && grown.width == current.width)
        let shrunk = try #require(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 180))
        #expect(shrunk.maxY == current.maxY)
        #expect(shrunk.height == 180)
        #expect(shrunk.minY == 520)
    }

    @Test func aFrameWithinHalfAPointIsLeftAlone() {
        #expect(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 300) == nil)
        #expect(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 300.5) == nil)
        #expect(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 299.6) == nil)
        #expect(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 300.6) != nil)
        #expect(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 0) == nil)
    }

    /// The window stops at the screen's visible bottom; the top-pinned popover scrolls the rest.
    @Test func aFittedFrameStopsAtTheVisibleBottom() throws {
        let limited = try #require(
            PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 900, bottomLimit: 50)
        )
        #expect(limited.maxY == current.maxY)
        #expect(limited.minY == 50)
        #expect(PopoverWindowHeightFitter.fittedFrame(current: current, targetHeight: 900, bottomLimit: 400) == nil)
    }

    /// A window that keeps 28pt above its hosting view (a title bar or top inset) needs those
    /// 28pt on top of the content, or every fit leaves the popover 28pt short.
    @Test func theTargetCountsWhatTheWindowKeepsOutsideTheHostingView() {
        #expect(PopoverWindowHeightFitter.windowHeight(forContent: 440, windowHeight: 300, hostHeight: 300) == 440)
        #expect(PopoverWindowHeightFitter.windowHeight(forContent: 440, windowHeight: 328, hostHeight: 300) == 468)
        #expect(PopoverWindowHeightFitter.windowHeight(
            forContent: 440, windowHeight: 300, hostHeight: 300, hostSafeArea: 28
        ) == 468)
        // A hosting view taller than its window adds nothing.
        #expect(PopoverWindowHeightFitter.windowHeight(forContent: 440, windowHeight: 300, hostHeight: 320) == 440)
    }

    /// Two displays, the second stacked below the menu-bar one. A popover hanging from the top
    /// display stops at that display's visible bottom even when most of it overlaps the lower one.
    @Test func theBottomLimitComesFromTheScreenHoldingTheTopEdge() {
        let top = (frame: NSRect(x: 0, y: 0, width: 1440, height: 900), visible: NSRect(x: 0, y: 70, width: 1440, height: 805))
        let below = (frame: NSRect(x: 0, y: -1080, width: 1920, height: 1080), visible: NSRect(x: 0, y: -1080, width: 1920, height: 1080))
        let window = NSRect(x: 600, y: -700, width: 384, height: 800)
        #expect(PopoverWindowHeightFitter.visibleFrame(under: window, screens: [below, top], fallback: below.visible) == top.visible)
        #expect(PopoverWindowHeightFitter.visibleBottom(under: window, screens: [below, top], fallback: below.visible) == 70)
        // A top edge on no screen falls back to the window's own screen.
        let lost = NSRect(x: 5000, y: 0, width: 384, height: 300)
        #expect(PopoverWindowHeightFitter.visibleBottom(under: lost, screens: [below, top], fallback: below.visible) == -1080)
        #expect(PopoverWindowHeightFitter.visibleBottom(under: lost, screens: [top], fallback: nil) == nil)
    }

    // MARK: Root layout sizing (pure)

    /// Only a real window shorter than the content changes the height the content is laid out
    /// at; every probe and a taller window still get the content's own height.
    @Test func theContentKeepsItsHeightExceptInAShorterWindow() {
        let ideal: CGFloat = 500
        #expect(PopoverTopPinnedLayout.visibleHeight(proposed: nil, ideal: ideal) == ideal)
        #expect(PopoverTopPinnedLayout.visibleHeight(proposed: 0, ideal: ideal) == ideal)
        #expect(PopoverTopPinnedLayout.visibleHeight(proposed: .infinity, ideal: ideal) == ideal)
        #expect(PopoverTopPinnedLayout.visibleHeight(proposed: 900, ideal: ideal) == ideal)
        #expect(PopoverTopPinnedLayout.visibleHeight(proposed: 380, ideal: ideal) == 380)
    }
}
