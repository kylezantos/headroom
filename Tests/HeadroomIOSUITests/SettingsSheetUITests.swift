import XCTest

/// U12: the phone's Settings sheet.
@MainActor
final class SettingsSheetUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// R23 / S4-C (Kyle): the Mac link row is one line at the default text size — the same
    /// height as a one-line maker row.
    func testMacLinkRowIsOneLineAtDefaultSize() {
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-screen", "settings"] + Self.contentSize("UICTContentSizeCategoryL")
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))

        let mac = app.buttons["headroom.about.mac"]
        let website = app.buttons["Website"]
        // On the taller iPad sheet a full swipe that brings "Website" in can leave the Mac row
        // above the lazily rendered rows. Scroll to the Mac row itself, then nudge in short
        // drags until the row below it is on screen too, so both rows are rendered together.
        scrollTo(mac)
        XCTAssertTrue(waitForHittable(mac), "the Mac row never came on screen")
        nudge(until: website)
        XCTAssertTrue(waitForHittable(website), "the Website row never came on screen")
        XCTAssertTrue(waitForHittable(mac), "the Mac row left the screen")
        XCTAssertTrue(mac.exists)
        XCTAssertEqual(mac.label, "Get Headroom for Mac")
        XCTAssertEqual(mac.frame.height, website.frame.height, accuracy: 1)
    }

    /// R30: switching the demo variant to "No recent update" shows the dimmed state. The
    /// Settings sync row carries KTD15's sentence; the Usage screen's dimmed rendering is U21's,
    /// so this asserts the variant took effect through the sheet's own reading of it.
    func testSwitchingDemoVariantToDimmedShowsTheDimmedSurface() {
        app = XCUIApplication()
        app.launchEnvironment["HEADROOM_UI_TEST_STATE"] = "waiting"
        app.launchEnvironment["HEADROOM_UI_TEST_RESET_DEMO"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["headroom.demo.enter"].waitForExistence(timeout: 5))
        app.buttons["headroom.demo.enter"].tap()
        XCTAssertTrue(element("headroom.demo.banner").waitForExistence(timeout: 5))

        app.buttons["headroom.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        // Explore Demo opens the multi-account variant: the Mac is current, nothing is dimmed.
        let status = element("headroom.settings.sync.status")
        let dimmed = element("headroom.settings.sync.dimmed")
        // The row right above where the dimmed sentence sits: once it is on screen, a dimmed
        // sentence would be too, so its absence is not just a lazy row scrolled out of view.
        let lastUpdate = element("headroom.settings.sync.lastUpdate")
        selectVariant("Multiple accounts")
        scrollTo(status)
        XCTAssertTrue(status.exists)
        scrollTo(lastUpdate)
        XCTAssertTrue(waitForDisappearance(dimmed))
        XCTAssertFalse(dimmed.exists)

        selectVariant("No recent update")
        scrollTo(status)
        XCTAssertTrue(status.exists)
        // On the taller iPad sheet the swipe that brings the status row in can leave the
        // sentence below the fold; scroll to the sentence itself before waiting on it.
        scrollTo(dimmed)
        XCTAssertTrue(dimmed.waitForExistence(timeout: 3))
        XCTAssertTrue(dimmed.label.hasPrefix("No update from your Mac since "), dimmed.label)

        // Leave the shared App Group variant as Explore Demo's default for other suites.
        selectVariant("Multiple accounts")
        scrollTo(status)
        scrollTo(lastUpdate)
        XCTAssertTrue(waitForDisappearance(dimmed))
        XCTAssertFalse(dimmed.exists)
        let exit = app.buttons["headroom.demo.exit"]
        scrollTo(exit, upward: true)
        exit.tap()
        XCTAssertTrue(app.staticTexts["Waiting for Mac"].waitForExistence(timeout: 5))

        // The picker wrote the App Group variant; a reset launch puts it back on the unset
        // default so suites that read it (the `--demo` layout tests) start clean.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Waiting for Mac"].waitForExistence(timeout: 5))
    }

    /// Capture pass (U12 verification), skipped unless the runner sets HEADROOM_CAPTURE
    /// (`TEST_RUNNER_HEADROOM_CAPTURE=1 xcodebuild test …`). Scrolls the sheet top to bottom
    /// with Match my Mac off, attaching a screenshot per screen for overflow review.
    func testCaptureSettingsSheet() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["HEADROOM_CAPTURE"] == "1", "capture pass only")
        let size = environment["HEADROOM_CAPTURE_SIZE"] ?? "UICTContentSizeCategoryL"
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-screen", "settings"] + Self.contentSize(size)
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))

        let match = app.switches["headroom.settings.matchMac"]
        scrollTo(match)
        let matchWasOn = (match.value as? String) == "1"
        if matchWasOn { match.switches.firstMatch.tap() }
        app.swipeDown()
        app.swipeDown()

        for index in 0..<14 {
            attach("settings-\(index)")
            if app.buttons["GitHub"].isHittable { break }
            app.swipeUp(velocity: .slow)
        }

        scrollTo(match, upward: true)
        if matchWasOn { match.switches.firstMatch.tap() }
    }

    // MARK: Helpers

    private static func contentSize(_ category: String) -> [String] {
        ["-UIPreferredContentSizeCategoryName", category]
    }

    private func selectVariant(_ title: String) {
        let picker = app.buttons["headroom.demo.variant"]
        scrollTo(picker, upward: true)
        picker.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        // The picker exists while its menu is still dismissing; wait until the menu has gone
        // and the picker's label carries the new choice, so the sheet has re-rendered from it.
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", title), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "the picker reads \(title); got \(picker.label)")
        XCTAssertTrue(waitForDisappearance(app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", title, "headroom.demo.variant")).firstMatch))
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    /// Scrolls the sheet until `target` is on screen, searching in `upward`'s direction
    /// first and then the other way.
    private func scrollTo(_ target: XCUIElement, upward: Bool = false) {
        for pass in [upward, !upward] {
            for _ in 0..<14 where !(target.exists && target.isHittable) {
                if pass { app.swipeDown() } else { app.swipeUp() }
            }
        }
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        return XCTWaiter.wait(for: [shown], timeout: timeout) == .completed
    }

    /// Scrolls the sheet up in short drags (a fraction of a swipe) until `target` is on
    /// screen, so a row already showing stays in view.
    private func nudge(until target: XCUIElement) {
        let list = app.collectionViews.firstMatch
        let surface: XCUIElement = list.exists ? list : app
        for _ in 0..<8 where !(target.exists && target.isHittable) {
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)))
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
