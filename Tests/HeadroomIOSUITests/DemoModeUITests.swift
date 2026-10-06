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
        // U21: the shared spend row speaks its identity line as one element.
        XCTAssertTrue(spendIdentity("Anthropic API").exists)
        XCTAssertTrue(spendIdentity("OpenAI API").exists)
    }

    // MARK: U21: freshness, past reset and old Mac

    /// R10/AE5: a quiet Mac dims the surface and says so in the stamp's slot, once: the rows
    /// take one demotion and gain no per-row "Last known" on top.
    func testDimmedSurfaceSaysNoUpdateInTheStampSlotAndDimsOnce() {
        launchDemo("dimmed")
        let line = element("headroom.status-line")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertTrue(line.label.hasPrefix("No update from your Mac since "), "got \(line.label)")
        XCTAssertEqual(line.value as? String, "dimmed")
        XCTAssertFalse(line.label.contains("Updated"))
        let weekly = element("headroom.account.claude.primary").descendants(matching: .any)["Weekly usage"]
        XCTAssertTrue(weekly.exists)
        XCTAssertFalse((weekly.value as? String)?.contains("Last known") ?? true, "dimming never stacks a row state")
        XCTAssertFalse((weekly.value as? String)?.contains("critical") ?? true)
        XCTAssertTrue(app.buttons["headroom.settings"].isHittable, "the gear stays at full strength")
    }

    /// R9: a healthy Mac's stamp names the oldest live reading.
    func testHealthyStampNamesTheOldestLiveReading() {
        launchDemo("multiAccount")
        let line = element("headroom.status-line")
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(line.label, "Updated 2 min ago")
    }

    /// R11/AE6: the row past its reset hides its number and says when it reset.
    func testPastResetRowHidesItsNumberAndSaysWhenItReset() {
        launchDemo("pastReset")
        let personal = element("headroom.account.claude.primary")
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
        let note = personal.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Reset at' AND label ENDSWITH '· waiting for your Mac'"))
            .firstMatch
        XCTAssertTrue(note.exists)
        let fiveHour = personal.descendants(matching: .any)["5-hour usage"]
        XCTAssertFalse((fiveHour.value as? String)?.contains("percent") ?? true, "the number is hidden")
        let weekly = personal.descendants(matching: .any)["Weekly usage"]
        XCTAssertTrue((weekly.value as? String)?.contains("percent") ?? false, "rows before their reset keep numbers")
    }

    /// R14/AE1: an older Mac shows its main accounts and says what updating it adds.
    func testOldMacShowsTheUpdateLineAndMainAccountsOnly() {
        launchDemo("oldMac")
        XCTAssertTrue(element("headroom.update-mac").waitForExistence(timeout: 5))
        XCTAssertEqual(element("headroom.update-mac").label, "Update Headroom on your Mac to see every account")
        XCTAssertTrue(element("headroom.provider.claude").exists)
        XCTAssertFalse(element("headroom.account.claude.work").exists)
        XCTAssertFalse(element("headroom.account.codex.codex-work").exists)
    }

    /// KTD6.5: a current Mac never asks to be updated.
    func testCurrentMacHasNoUpdateLine() {
        launchDemo("multiAccount")
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 5))
        XCTAssertFalse(element("headroom.update-mac").exists)
    }

    // MARK: U9: pull to check now

    /// AE8: a demo pull plays the bundled receipt — a landed account "n of N" — and ends at
    /// "Updated just now", then the stamp returns; no request key is written.
    func testDemoPullPlaysTheReceiptToJustNowAndWritesNothing() {
        launchDemo("multiAccount")
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 5))
        pullToRefresh()
        let seen = statusLines(until: { $0 == "Updated just now" }, timeout: 15)
        XCTAssertEqual(seen.last, "Updated just now", "saw \(seen)")
        XCTAssertTrue(seen.contains { $0.contains(" of 5") }, "a landed account reads n of 5; saw \(seen)")
        XCTAssertTrue(seen.contains { $0 == "Asking your Mac…" || $0.hasPrefix("Checking 5 accounts") || $0.contains(" of 5") })
        let line = element("headroom.status-line")
        let reverted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'freshness'"), object: line)
        XCTAssertEqual(XCTWaiter.wait(for: [reverted], timeout: 6), .completed, "the stamp returns after Just now")
        XCTAssertEqual(element("headroom.checknow.writes").value as? String, "0", "demo writes nothing (AE8)")
    }

    /// AE1 / KTD14.1: an older Mac's pull re-reads, with no "Asking your Mac" state.
    func testOldMacPullReReadsWithoutAsking() {
        launchDemo("oldMac")
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 5))
        let rereads = element("headroom.checknow.rereads")
        XCTAssertEqual(rereads.value as? String, "0")
        pullToRefresh()
        let seen = statusLines(until: { _ in false }, timeout: 3)
        // Review 2 #6: the pull ran and took the re-read path, and the line was sampled.
        let reread = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: rereads)
        XCTAssertEqual(XCTWaiter.wait(for: [reread], timeout: 5), .completed, "the pull re-read once")
        XCTAssertFalse(seen.isEmpty, "the status line was sampled")
        XCTAssertFalse(seen.contains("Asking your Mac…"), "saw \(seen)")
        XCTAssertTrue(seen.allSatisfy { $0.hasPrefix("Updated") }, "saw \(seen)")
        XCTAssertEqual(element("headroom.checknow.writes").value as? String, "0")
    }

    /// U9: iPad's ⌘R runs the same check as the pull.
    func testCommandRChecksNowOnIPad() throws {
        launchDemo("fourProviders")
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 5))
        guard app.windows.firstMatch.frame.width >= 700 else { throw XCTSkip("⌘R is the iPad keyboard path") }
        app.typeKey("r", modifierFlags: .command)
        let seen = statusLines(until: { $0 == "Updated just now" }, timeout: 15)
        XCTAssertEqual(seen.last, "Updated just now", "saw \(seen)")
    }

    /// A slow drag from the top of the content, long enough to pass the refresh threshold on
    /// an iPad's taller window too.
    private func pullToRefresh() {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = start.withOffset(CGVector(dx: 0, dy: max(420, window.frame.height * 0.45)))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Every distinct label the status line shows until `stop` matches or time runs out.
    private func statusLines(until stop: (String) -> Bool, timeout: TimeInterval) -> [String] {
        let line = element("headroom.status-line")
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if line.exists {
                let label = line.label
                if seen.last != label { seen.append(label) }
                if stop(label) { break }
            }
        }
        return seen
    }

    private func spendIdentity(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
    }

    private func launchDemo(_ variant: String) {
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-variant", variant]
        app.launch()
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
