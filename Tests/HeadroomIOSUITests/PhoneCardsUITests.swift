import XCTest

/// U8: the phone's provider cards, driven by U7's bundled v4 demo variants through `--demo`
/// screenshot launches (no banner, nothing written to iCloud).
@MainActor
final class PhoneCardsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// R2/R3: every account, main first in the Mac's order, rows 5-hour first.
    func testMultiAccountStacksEveryAccountMainFirstInMacOrder() {
        launch("multiAccount")
        let claude = ["primary", "work", "studio"].map { element("headroom.account.claude.\($0).title") }
        let codex = ["primary", "codex-work"].map { element("headroom.account.codex.\($0).title") }
        XCTAssertTrue(claude[0].waitForExistence(timeout: 5))
        XCTAssertEqual(claude.map(\.label), ["Personal", "Work", "Studio"])
        XCTAssertEqual(codex.map(\.label), ["Personal", "Work"])
        for stack in [claude, codex] {
            let tops = stack.map(\.frame.minY)
            XCTAssertEqual(tops, tops.sorted(), "accounts render in the Mac's order")
        }
        // U11: a window wide enough for two columns (876pt) flows Codex into the next one;
        // a phone or a narrower iPad stacks it below.
        let claudeCard = element("headroom.provider.claude").frame
        let codexCard = element("headroom.provider.codex").frame
        if FlowingColumnsExpectation.columns(width: app.windows.firstMatch.frame.width) >= 2 {
            XCTAssertGreaterThan(codexCard.minX, claudeCard.maxX)
        } else {
            XCTAssertGreaterThan(codexCard.minY, claudeCard.minY)
        }

        // The model row prints "Fable" and is one element ("Fable weekly usage").
        XCTAssertTrue(element("Fable weekly usage").exists)
        let personal = element("headroom.account.claude.primary")
        let fiveHour = personal.descendants(matching: .any)["5-hour usage"]
        let weekly = personal.descendants(matching: .any)["Weekly usage"]
        XCTAssertLessThan(fiveHour.frame.minY, weekly.frame.minY, "5-hour reads first")
        XCTAssertFalse(element("headroom.demo.banner").exists, "a --demo launch hides the banner")
    }

    /// R3/AP1: a critical limit is a red numeral that VoiceOver calls critical; no "Low" chip.
    func testCriticalRowIsSpokenAsCriticalAndThereIsNoLowChip() {
        launch("multiAccount")
        let work = element("headroom.account.claude.work")
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        let critical = work.descendants(matching: .any)["Weekly usage"]
        XCTAssertTrue(critical.exists)
        XCTAssertTrue((critical.value as? String)?.contains("12 percent left, critical") == true,
                      "got \(String(describing: critical.value))")
        let healthy = element("headroom.account.claude.primary").descendants(matching: .any)["Weekly usage"]
        XCTAssertFalse((healthy.value as? String)?.contains("critical") ?? true)
        XCTAssertFalse(app.staticTexts["Low"].exists)
        XCTAssertFalse(element("Low").exists)
    }

    /// R5: the capsule opens on tap, and on its own while a live 5-hour/weekly is Critical.
    func testPlanCapsuleOpensOnTapAndOnItsOwnWhenCritical() {
        launch("bankedResets")
        let main = element("headroom.account.codex.primary.plan")
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        XCTAssertEqual(main.value as? String, "Plus")
        main.tap()
        XCTAssertTrue(waitForValue(main, "Plus · 2 resets"))
        XCTAssertFalse(element("headroom.title-disclosure.title").exists, "the capsule tap only opens the capsule")
        main.tap()
        XCTAssertTrue(waitForValue(main, "Plus"))

        let onCall = element("headroom.account.codex.codex-critical.plan")
        XCTAssertEqual(onCall.value as? String, "Plus · 1 reset", "a Critical account opens without a tap")
    }

    /// V12/R4: a never-signed-in extra account reads one typed line, in neutral ink.
    func testSignedOutExtraAccountReadsItsSignInLine() {
        launch("accountStates")
        XCTAssertTrue(app.staticTexts["Sign in to Account 2 on your Mac"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("headroom.account.claude.claude-account-2").exists)
    }

    /// U3-A: the glyph marks only the main account of a provider the widgets show.
    func testWidgetGlyphMarksOnlyTheFollowedMainAccountAndExplainsItself() {
        launch("accountStates")
        let codexGlyph = element("headroom.widget-glyph.codex")
        XCTAssertTrue(codexGlyph.waitForExistence(timeout: 5))
        XCTAssertFalse(element("headroom.widget-glyph.claude").exists, "Claude is not in the widget selection")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "headroom.widget-glyph.codex").count, 1)
        codexGlyph.tap()
        XCTAssertTrue(app.staticTexts["Your widgets follow this account. Change it with Make Main on your Mac."]
            .waitForExistence(timeout: 3))
        XCTAssertFalse(element("headroom.title-disclosure.title").exists, "the glyph tap only explains")
    }

    /// U3 step 6: shared long prefixes stay distinguishable through the full-name sheet. A
    /// regular-width card (at least KTD17's 400pt) fits these titles at the default size, and
    /// a title that never truncates stays plain text with no sheet (review 2 #7).
    func testTruncatedTitlesDiscloseTheFullNameAtDefaultSize() {
        launch("accountStates")
        let twin = element("headroom.account.codex.codex-northwind-2.title")
        XCTAssertTrue(twin.waitForExistence(timeout: 5))
        if FlowingColumnsExpectation.isRegularWidth(app.windows.firstMatch.frame.width) {
            assertTitlesStayPlainText()
        } else {
            assertTitleDisclosure()
        }
    }

    func testTruncatedTitlesDiscloseTheFullNameAtXXLarge() {
        launch("accountStates", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"])
        assertTitleDisclosure()
    }

    /// KTD7 level 2: a capped stack ends with "N more on your Mac".
    func testAboveEnvelopeEndsCappedStacksWithTheCount() {
        launch("aboveEnvelope")
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "60 more on your Mac"))
            .firstMatch.waitForExistence(timeout: 5))
    }

    /// The tested envelope is the all-accounts fixture: nothing is capped.
    func testMulti20ShowsEveryAccountWithNoCap() {
        launch("multi20")
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 10))
        XCTAssertTrue(element("headroom.account.claude.claude-generated-20").exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "more on your Mac"))
            .firstMatch.exists)
    }

    /// KTD16: the entrance plays on launch and never again on a data refresh.
    func testEntrancePlaysOnceAndNotOnARefresh() {
        launch("multiAccount")
        let marker = element("headroom.entrance")
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(marker, "1"))
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        XCTAssertTrue(element("headroom.provider.claude").waitForExistence(timeout: 5))
        // A refresh lands a new snapshot; give it time to, then check nothing replayed.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)], timeout: 2)
        XCTAssertEqual(marker.value as? String, "1")
    }

    // MARK: Helpers

    private func assertTitleDisclosure() {
        let twin = element("headroom.account.codex.codex-northwind-2.title")
        XCTAssertTrue(twin.waitForExistence(timeout: 5))
        XCTAssertEqual(twin.label, "Northwind Research Workspace · 2")
        XCTAssertEqual(twin.elementType, .button, "a truncated title is a button")
        twin.tap()
        let full = element("headroom.title-disclosure.title")
        XCTAssertTrue(full.waitForExistence(timeout: 3))
        XCTAssertEqual(full.label, "Northwind Research Workspace · 2")
        app.buttons["headroom.title-disclosure.done"].tap()
        XCTAssertTrue(waitForDisappearance(full))
        XCTAssertTrue(element("headroom.provider.codex").exists)

        let main = element("headroom.account.codex.primary.title")
        main.tap()
        XCTAssertTrue(full.waitForExistence(timeout: 3))
        XCTAssertEqual(full.label, "Northwind Research Workspace")
        app.buttons["headroom.title-disclosure.done"].tap()
        XCTAssertTrue(waitForDisappearance(full))
    }

    /// Nontruncated titles stay plain text: not buttons, whole, and a tap opens nothing.
    private func assertTitlesStayPlainText() {
        let titles = [
            ("headroom.account.codex.codex-northwind-2.title", "Northwind Research Workspace · 2"),
            ("headroom.account.codex.primary.title", "Northwind Research Workspace"),
        ]
        for (identifier, label) in titles {
            let title = element(identifier)
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, label)
            XCTAssertNotEqual(title.elementType, .button, "\(label) fits, so it is not a button")
            XCTAssertFalse(app.buttons.matching(identifier: identifier).firstMatch.exists)
        }
        element(titles[0].0).tap()
        XCTAssertFalse(element("headroom.title-disclosure.title").waitForExistence(timeout: 1.5),
                       "a title that fits opens no sheet")
    }

    private func launch(_ variant: String, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-variant", variant] + extra
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
