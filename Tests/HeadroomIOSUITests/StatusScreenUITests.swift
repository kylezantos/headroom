import UIKit
import XCTest

/// U10 (R4, R23; G5–G9): every status screen leads somewhere, in neutral ink, and nothing on
/// it moves unless a refresh is running. Waiting, paused and unreadable come from real routes
/// (the build-33 waiting fixture, U7's `paused` demo variant, and a corrupt v3 key run through
/// the resolver); the screens no fixture reaches are posed through the DEBUG
/// `HEADROOM_UI_TEST_STATUS` hook.
@MainActor
final class StatusScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testWaitingShowsTitleMacLinkAndExploreDemoWithoutSystemTint() {
        for appearance in ["light", "dark"] {
            app = makeApp(appearance: appearance)
            app.launchEnvironment["HEADROOM_UI_TEST_STATE"] = "waiting"
            app.launch()

            XCTAssertTrue(app.staticTexts["Waiting for Your Mac"].waitForExistence(timeout: 5))
            assertPrimary("Refresh")
            assertExploreDemo()
            // CA-I6: the two actions share one width and the screen owns the Usage header.
            XCTAssertEqual(element("headroom.status.primary").frame.width,
                           element("headroom.demo.enter").frame.width, accuracy: 1)
            XCTAssertTrue(app.buttons["headroom.settings"].isHittable)
            XCTAssertFalse(app.navigationBars.firstMatch.exists && app.navigationBars.firstMatch.isHittable,
                           "the native navigation bar is hidden")
            let getMac = element("headroom.status.getMac")
            XCTAssertTrue(getMac.exists)
            XCTAssertTrue(getMac.label.contains("Get Headroom for Mac"), "label was \(getMac.label)")
            assertNoIdleSpinner()
            assertNoSystemTint(appearance)
            app.terminate()
        }
    }

    func testPausedNamesTheMacSwitch() {
        for appearance in ["light", "dark"] {
            app = makeApp(appearance: appearance)
            app.launchArguments += ["--demo", "--demo-variant", "paused"]
            app.launch()

            XCTAssertTrue(app.staticTexts["Sync Is Off"].waitForExistence(timeout: 5))
            let naming = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sync usage to iPhone"))
            XCTAssertGreaterThan(naming.count, 0, "the paused screen must name the Mac switch")
            XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sync snapshot")).count > 0)
            assertPrimary("Refresh")
            assertExploreDemo()
            XCTAssertTrue(element("headroom.status.getMac").exists)
            assertNoIdleSpinner()
            assertNoSystemTint(appearance)
            app.terminate()
        }
    }

    /// U10: a corrupt key with nothing cached resolves to Snapshot Unreadable, which points at
    /// the Mac and never asks anyone to "publish a fresh snapshot".
    func testUnreadableComesFromACorruptKey() {
        for appearance in ["light", "dark"] {
            app = makeApp(appearance: appearance)
            app.launchEnvironment["HEADROOM_UI_TEST_STATE"] = "unreadable"
            app.launch()

            XCTAssertTrue(app.staticTexts["Couldn’t Read the Data"].waitForExistence(timeout: 5))
            let pointsAtMac = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "Open Headroom on your Mac"))
            XCTAssertGreaterThan(pointsAtMac.count, 0, "the unreadable screen must point at the Mac")
            XCTAssertEqual(
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "publish")).count, 0)
            XCTAssertFalse(app.staticTexts["Waiting for Your Mac"].exists)
            assertPrimary("Refresh")
            assertExploreDemo()
            XCTAssertFalse(element("headroom.status.getMac").exists)
            assertNoIdleSpinner()
            assertNoSystemTint("\(appearance) · unreadable")
            app.terminate()
        }
    }

    /// A refresh ends with the button at rest and nothing left moving. XCUITest's tap waits
    /// for the app to go idle, which outlasts the 550ms check and its wave, so the in-flight
    /// "Checking…" frame can't be observed here; `LoadingCheckRecipe`'s Core tests pin it.
    func testRefreshLeavesNoSpinnerBehind() {
        app = makeApp(appearance: "light")
        app.launchEnvironment["HEADROOM_UI_TEST_STATE"] = "waiting"
        app.launch()
        XCTAssertTrue(app.staticTexts["Waiting for Your Mac"].waitForExistence(timeout: 5))
        assertNoIdleSpinner()

        let primary = element("headroom.status.primary")
        primary.tap()
        XCTAssertTrue(waitForLabel(primary, "Refresh", timeout: 6), "label was \(primary.label)")
        XCTAssertTrue(primary.isEnabled)
        assertNoIdleSpinner()
    }

    /// The posed screens: each one's own primary action plus Explore Demo, and no Mac link
    /// (G9 puts it on waiting and paused only).
    func testPosedScreensLeadSomewhere() {
        let screens: [(status: String, title: String, primary: String)] = [
            ("iCloudUnavailable", "iCloud Not Available", "Open iOS Settings"),
            ("unreadable", "Couldn’t Read the Data", "Refresh"),
            ("updatePhone", "Update Headroom", "Open App Store"),
            ("updateMac", "Update Headroom on your Mac", "Get Headroom for Mac"),
        ]
        for screen in screens {
            app = makeApp(appearance: "dark")
            app.launchEnvironment["HEADROOM_UI_TEST_STATE"] = "waiting"
            app.launchEnvironment["HEADROOM_UI_TEST_STATUS"] = screen.status
            app.launch()

            XCTAssertTrue(app.staticTexts[screen.title].waitForExistence(timeout: 5), screen.title)
            assertPrimary(screen.primary)
            assertExploreDemo()
            XCTAssertFalse(element("headroom.status.getMac").exists, screen.title)
            assertNoIdleSpinner()
            assertNoSystemTint("dark · \(screen.status)")
            app.terminate()
        }
    }

    /// The detector itself: system blue in both schemes must trip it, and the neutral
    /// control inks must not.
    func testSystemTintDetectorCatchesSystemBlue() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let blue = UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            XCTAssertGreaterThan(Self.systemTintPixelCount(in: Self.swatch(blue)), 0, "\(style.rawValue)")
        }
        let neutral = UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1)
        XCTAssertEqual(Self.systemTintPixelCount(in: Self.swatch(neutral)), 0)
        let darkNeutral = UIColor(red: 0.92, green: 0.92, blue: 0.96, alpha: 1)
        XCTAssertEqual(Self.systemTintPixelCount(in: Self.swatch(darkNeutral)), 0)
    }

    // MARK: Assertions

    private func assertPrimary(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let primary = element("headroom.status.primary")
        XCTAssertTrue(primary.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertEqual(primary.label, label, file: file, line: line)
    }

    private func assertExploreDemo(file: StaticString = #filePath, line: UInt = #line) {
        let demo = app.buttons["headroom.demo.enter"]
        XCTAssertTrue(demo.exists, file: file, line: line)
        XCTAssertEqual(demo.label, "Explore Demo", file: file, line: line)
    }

    /// No system progress view, and the checking row isn't built while nothing runs.
    private func assertNoIdleSpinner(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.activityIndicators.count, 0, "a system spinner is on screen", file: file, line: line)
        XCTAssertFalse(app.staticTexts["Checking…"].exists, file: file, line: line)
        XCTAssertNotEqual(element("headroom.status.primary").label, "Checking…", file: file, line: line)
    }

    /// G6: no pixel on screen is system blue (bright, saturated, blue-hued).
    private func assertNoSystemTint(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "status \(context)"
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
        guard let image = screenshot.image.cgImage else {
            XCTFail("no screenshot", file: file, line: line)
            return
        }
        XCTAssertEqual(Self.systemTintPixelCount(in: image), 0, "system blue on screen (\(context))", file: file, line: line)
    }

    // MARK: Helpers

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func makeApp(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-headroom.ios.appearance", appearance]
        app.launchEnvironment["HEADROOM_UI_TEST_RESET_DEMO"] = "1"
        return app
    }

    /// Bright, saturated pixels in system blue's hue band. The dark scheme's navy glass ring
    /// (≈ 54, 62, 95) and the neutral inks fall outside it; system blue in either scheme
    /// (0, 122, 255 / 10, 132, 255) and anything tinted with it at label strength fall inside.
    nonisolated static func systemTintPixelCount(in image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return Int.max }
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            let maximum = max(r, g, b), minimum = min(r, g, b)
            guard maximum == b, maximum > 0.5, maximum - minimum > 0.45 else { continue }
            let saturation = (maximum - minimum) / maximum
            let hue = (4 + (r - g) / (maximum - minimum)) / 6
            if saturation > 0.6, (0.54...0.65).contains(hue) { count += 1 }
        }
        return count
    }

    private static func swatch(_ color: UIColor) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.cgImage!
    }
}
