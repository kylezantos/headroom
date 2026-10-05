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
        scrollTo(website)
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
        selectVariant("Multiple accounts")
        scrollTo(status)
        XCTAssertTrue(status.exists)
        XCTAssertFalse(dimmed.exists)

        selectVariant("No recent update")
        scrollTo(status)
        XCTAssertTrue(dimmed.waitForExistence(timeout: 3))
        XCTAssertTrue(dimmed.label.hasPrefix("No update from your Mac since "), dimmed.label)

        // Leave the shared App Group variant as Explore Demo's default for other suites.
        selectVariant("Multiple accounts")
        scrollTo(status)
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
