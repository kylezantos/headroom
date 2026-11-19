import XCTest

@MainActor
final class ResponsiveLayoutUITests: XCTestCase {
    /// U21 (KTD3, P45–P53): spend rows are the shared row — the title, the period chip and
    /// "used" — and the chip drops to the subline before the title gives up width. A 393pt
    /// phone needs the subline at the default size (~344pt against ~323pt); a wide card holds
    /// the chip inline.
    func testSpendRowsUseTheSharedRowAndItsChipFit() {
        let app = launch(["--demo", "--demo-variant", "fourProviders"])
        let anthropic = spendIdentity(app, "Anthropic API")
        let openAI = spendIdentity(app, "OpenAI API")
        XCTAssertTrue(anthropic.waitForExistence(timeout: 5))
        XCTAssertTrue(openAI.exists)
        XCTAssertEqual(anthropic.label, "Anthropic API, Current month, $142.67 used")
        XCTAssertEqual(openAI.label, "OpenAI API, Current month, $58.90 used")
        XCTAssertFalse(app.staticTexts["API SPEND"].exists, "no eyebrow")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.frame.contains(anthropic.frame))
        if window.frame.width < 430 {
            XCTAssertGreaterThan(anthropic.frame.height, Self.sublineHeight, "chip sits in the subline on a 393pt phone")
        } else if window.frame.width >= 700 {
            XCTAssertLessThan(anthropic.frame.height, Self.sublineHeight, "a wide card holds the chip inline")
        }
    }

    /// KTD3: at xxLarge the chip is in the subline on every phone, and the row stays inside
    /// the window with its whole label.
    func testSpendChipDropsToTheSublineAtXXLarge() {
        let app = launch([
            "--demo", "--demo-variant", "fourProviders",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL",
        ])
        let anthropic = spendIdentity(app, "Anthropic API")
        XCTAssertTrue(anthropic.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        if !window.frame.contains(anthropic.frame) { app.swipeUp() }
        XCTAssertTrue(window.frame.contains(anthropic.frame))
        XCTAssertEqual(anthropic.label, "Anthropic API, Current month, $142.67 used")
        if window.frame.width < 700 {
            XCTAssertGreaterThan(anthropic.frame.height, Self.sublineHeight)
        }
    }

    /// X5/S5A: a retained spend row puts its state tag in the chip's slot and its sentence
    /// under the identity line.
    func testStaleSpendRowsCarryTheirTagAndSentence() {
        let app = launch(["--demo", "--demo-variant", "staleSpend"])
        let anthropic = spendIdentity(app, "Anthropic API")
        XCTAssertTrue(anthropic.waitForExistence(timeout: 5))
        XCTAssertTrue(anthropic.label.contains("$142.67 used"), "a retained figure stays visible")
        // CA-P3: the retried figure says how old it is (the demo reads it three hours back).
        XCTAssertTrue(anthropic.label.contains("Last read"), "got \(anthropic.label)")
        let row = app.descendants(matching: .any)["headroom.spend.claude"]
        XCTAssertGreaterThan(row.frame.maxY, anthropic.frame.maxY, "the sentence sits under the identity line")
    }

    func testDemoContentFitsCurrentPhoneOrTabletWindow() {
        let app = launch(["--demo"])

        let window = app.windows.firstMatch
        let isTablet = FlowingColumnsExpectation.isRegularWidth(window.frame.width)
        defer { XCUIDevice.shared.orientation = .portrait }
        let claude = app.descendants(matching: .any)["headroom.provider.claude"]
        let codex = app.descendants(matching: .any)["headroom.provider.codex"]
        XCTAssertTrue(claude.waitForExistence(timeout: 5))
        XCTAssertTrue(codex.exists)
        XCTAssertTrue(window.frame.contains(claude.frame))
        XCTAssertTrue(window.frame.contains(codex.frame))

        // Review 2 #8: two columns need 876pt, not just an iPad; a 744pt or 834pt iPad stacks.
        if FlowingColumnsExpectation.columns(width: window.frame.width) >= 2 {
            XCTAssertLessThan(abs(claude.frame.minY - codex.frame.minY), 1, "two columns share a top edge")
            XCTAssertGreaterThan(codex.frame.minX, claude.frame.maxX)
        } else {
            XCTAssertGreaterThan(codex.frame.minY, claude.frame.minY)
        }

        XCTAssertTrue(app.buttons["headroom.settings"].isHittable)

        if isTablet {
            rotate(app, to: .landscapeLeft)
            XCTAssertTrue(window.frame.contains(claude.frame))
            XCTAssertTrue(window.frame.contains(codex.frame))
            if FlowingColumnsExpectation.columns(width: window.frame.width) >= 2 {
                XCTAssertLessThan(abs(claude.frame.minY - codex.frame.minY), 1)
            }
            XCTAssertTrue(app.buttons["headroom.settings"].isHittable)
        }
    }

    /// U11 (KTD17): iPad Pro 13 flows four providers and spend into two columns in portrait
    /// (1032pt) and three in landscape (1376pt); a phone stays one column.
    func testColumnCountFollowsTheWindowWidth() {
        let app = launch(["--demo", "--demo-variant", "fourProviders"])
        defer { XCUIDevice.shared.orientation = .portrait }
        let window = app.windows.firstMatch
        XCTAssertTrue(card(app, "headroom.provider.claude").waitForExistence(timeout: 5))
        let width = window.frame.width
        XCTAssertEqual(columnCount(app), Self.expectedColumns(width: width), "at \(width)pt")

        guard FlowingColumnsExpectation.isRegularWidth(width) else { return }
        rotate(app, to: .landscapeLeft)
        XCTAssertEqual(columnCount(app), Self.expectedColumns(width: window.frame.width), "at \(window.frame.width)pt")
        let cards = Self.cardIDs.map { card(app, $0) }
        XCTAssertTrue(cards.allSatisfy { window.frame.contains($0.frame) }, "no card leaves the window")
    }

    /// KTD17: VoiceOver reads provider order, then spend — not column by column.
    func testAccessibilityOrderFollowsProviderOrder() {
        let app = launch(["--demo", "--demo-variant", "fourProviders"])
        XCTAssertTrue(card(app, "headroom.provider.claude").waitForExistence(timeout: 5))
        let query = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'headroom.provider.' OR identifier == 'headroom.api-spend'"))
        let order = query.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(order, Self.cardIDs)
    }

    /// V38 capture pass, skipped unless the runner sets HEADROOM_CAPTURE_DIR
    /// (`TEST_RUNNER_HEADROOM_CAPTURE_DIR=<dir> xcodebuild test …`): each fixture in portrait
    /// and landscape, written as PNGs for the overflow and empty-region review.
    func testCaptureFlowingColumns() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["HEADROOM_CAPTURE_DIR"] ?? ""
        try XCTSkipIf(directory.isEmpty, "capture pass only")
        let device = environment["HEADROOM_CAPTURE_DEVICE"] ?? "device"
        defer { XCUIDevice.shared.orientation = .portrait }
        for variant in ["oldMac", "bankedResets", "multiAccount", "fourProviders", "multi20"] {
            XCUIDevice.shared.orientation = .portrait
            let app = launch(["--demo", "--demo-variant", variant])
            XCTAssertTrue(card(app, "headroom.provider.claude").waitForExistence(timeout: 10))
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)], timeout: 1.5)
            try write(directory: directory, name: "\(device)-\(variant)-portrait")
            if app.windows.firstMatch.frame.width >= 700 {
                rotate(app, to: .landscapeLeft)
                try write(directory: directory, name: "\(device)-\(variant)-landscape")
            }
            app.terminate()
        }
    }

    private func write(directory: String, name: String) throws {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    // MARK: Helpers

    /// One identity line at 1.15× is 21pt; with the chip in the subline it is about 46pt.
    private static let sublineHeight: CGFloat = 34

    private static let cardIDs = [
        "headroom.provider.claude", "headroom.provider.codex", "headroom.provider.grok",
        "headroom.provider.cursor", "headroom.api-spend",
    ]

    /// Never more columns than the five cards.
    private static func expectedColumns(width: CGFloat) -> Int {
        FlowingColumnsExpectation.columns(width: width, cardCount: cardIDs.count)
    }

    private func columnCount(_ app: XCUIApplication) -> Int {
        let edges = Self.cardIDs.map { card(app, $0).frame.minX.rounded() }
        return Set(edges).count
    }

    private func card(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func spendIdentity(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(title),")).firstMatch
    }

    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let window = app.windows.firstMatch
        let rotated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in window.frame.width > window.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        // Let the re-plan land before frames are read.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)], timeout: 1)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
