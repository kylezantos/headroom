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

    func testSettingsOmitsDemoAndReminders() {
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-screen", "settings"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["headroom.about.mac"].exists)
        for _ in 0..<8 {
            XCTAssertFalse(app.staticTexts["Demo"].exists)
            XCTAssertFalse(app.staticTexts["Reminders"].exists)
            XCTAssertFalse(app.buttons["headroom.demo.variant"].exists)
            XCTAssertFalse(app.buttons["headroom.demo.enter.settings"].exists)
            XCTAssertFalse(element("headroom.settings.reminders").exists)
            app.swipeUp()
        }
    }

    func testDimmedSnapshotStillShowsItsSyncStatus() {
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-variant", "dimmed", "--demo-screen", "settings"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        let dimmed = element("headroom.settings.sync.dimmed")
        scrollTo(dimmed)
        XCTAssertTrue(dimmed.waitForExistence(timeout: 3))
        XCTAssertTrue(dimmed.label.hasPrefix("No update from your Mac since "), dimmed.label)
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
