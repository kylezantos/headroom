import XCTest

@MainActor
final class DemoModeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCleanInstallCanExploreFullDemoAndExitToWaiting() {
        app = makeApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["Waiting for Mac"].waitForExistence(timeout: 5))

        app.buttons["headroom.demo.enter"].tap()
        assertFullDemo()

        app.buttons["headroom.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["You are viewing sample data. Your synced snapshot is unchanged."].exists)
        app.buttons["headroom.demo.exit"].tap()

        XCTAssertTrue(app.staticTexts["Waiting for Mac"].waitForExistence(timeout: 5))
    }

    func testDemoPersistsAcrossRelaunchUntilExit() {
        app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["headroom.demo.enter"].waitForExistence(timeout: 5))
        app.buttons["headroom.demo.enter"].tap()
        XCTAssertTrue(element("headroom.demo.banner").waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment["HEADROOM_UI_TEST_RESET_DEMO"] = "0"
        app.launch()
        XCTAssertTrue(element("headroom.demo.banner").waitForExistence(timeout: 5))

        app.buttons["headroom.settings"].tap()
        app.buttons["headroom.demo.exit"].tap()
        XCTAssertTrue(app.staticTexts["Waiting for Mac"].waitForExistence(timeout: 5))
    }

    private func assertFullDemo() {
        XCTAssertTrue(element("headroom.demo.banner").waitForExistence(timeout: 5))
        XCTAssertTrue(element("headroom.provider.claude").exists)
        XCTAssertTrue(element("headroom.provider.codex").exists)
        // The model row prints "Fable" and is one accessibility element ("Fable weekly usage").
        XCTAssertTrue(element("Fable weekly usage").exists)

        if !element("headroom.api-spend").exists {
            app.swipeUp()
        }
        XCTAssertTrue(element("headroom.api-spend").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Anthropic API"].exists)
        XCTAssertTrue(app.staticTexts["OpenAI API"].exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HEADROOM_UI_TEST_STATE"] = "waiting"
        app.launchEnvironment["HEADROOM_UI_TEST_RESET_DEMO"] = "1"
        return app
    }
}
