import XCTest

@MainActor
final class ResponsiveLayoutUITests: XCTestCase {
    func testCompactAPISpendRowsUseInlineLedgerAlignment() {
        let app = XCUIApplication()
        // U8: one account per provider, so the Claude card is titled "Claude" (KTD9's flip).
        app.launchArguments = ["--demo", "--demo-variant", "fourProviders"]
        app.launch()

        let window = app.windows.firstMatch
        guard window.frame.width < 700 else { return }

        let claudeTitle = app.staticTexts["Claude"].firstMatch
        let apiSpendTitle = app.staticTexts["API SPEND"].firstMatch
        let anthropicTitle = app.staticTexts["Anthropic API"].firstMatch
        let openAITitle = app.staticTexts["OpenAI API"].firstMatch
        let anthropicAmount = app.staticTexts["$142.67"].firstMatch
        let openAIAmount = app.staticTexts["$58.90"].firstMatch
        let periodLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "· Current month"))
        XCTAssertTrue(claudeTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(apiSpendTitle.exists)
        XCTAssertTrue(anthropicTitle.exists)
        XCTAssertTrue(openAITitle.exists)
        XCTAssertTrue(anthropicAmount.exists)
        XCTAssertTrue(openAIAmount.exists)
        XCTAssertEqual(periodLabels.count, 2)
        guard periodLabels.count == 2 else { return }

        let periods = (0..<periodLabels.count)
            .map { periodLabels.element(boundBy: $0) }
            .sorted { $0.frame.minY < $1.frame.minY }
        let anthropicPeriod = periods[0]
        let openAIPeriod = periods[1]
        XCTAssertEqual(anthropicTitle.frame.minX, apiSpendTitle.frame.minX, accuracy: 1)
        XCTAssertEqual(openAITitle.frame.minX, apiSpendTitle.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(anthropicPeriod.frame.minX, anthropicTitle.frame.maxX)
        XCTAssertGreaterThan(openAIPeriod.frame.minX, openAITitle.frame.maxX)
        XCTAssertLessThan(abs(anthropicPeriod.frame.midY - anthropicTitle.frame.midY), 3)
        XCTAssertLessThan(abs(openAIPeriod.frame.midY - openAITitle.frame.midY), 3)
        XCTAssertEqual(anthropicAmount.frame.maxX, openAIAmount.frame.maxX, accuracy: 1)
        XCTAssertGreaterThan(anthropicAmount.frame.minX, anthropicTitle.frame.maxX)
        XCTAssertGreaterThan(openAIAmount.frame.minX, openAITitle.frame.maxX)
        XCTAssertLessThan(
            abs(anthropicAmount.frame.midY - anthropicTitle.frame.midY),
            abs(anthropicAmount.frame.midY - anthropicPeriod.frame.midY)
        )
        XCTAssertLessThan(
            abs(openAIAmount.frame.midY - openAITitle.frame.midY),
            abs(openAIAmount.frame.midY - openAIPeriod.frame.midY)
        )
        XCTAssertLessThan(apiSpendTitle.frame.minX, claudeTitle.frame.minX)
    }

    func testCompactAPISpendKeepsStaleStatusBelowAmountBaseline() {
        let app = XCUIApplication()
        // U8: the v4 form of build 33's `--demo-stale-api-spend`.
        app.launchArguments = ["--demo", "--demo-variant", "staleSpend"]
        app.launch()

        let window = app.windows.firstMatch
        guard window.frame.width < 700 else { return }

        let anthropicTitle = app.staticTexts["Anthropic API"].firstMatch
        let anthropicAmount = app.staticTexts["$142.67"].firstMatch
        let staleStatuses = app.staticTexts.matching(NSPredicate(format: "label == %@", "Stale"))
        XCTAssertTrue(anthropicTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(anthropicAmount.exists)
        XCTAssertEqual(staleStatuses.count, 2)
        guard staleStatuses.count == 2 else { return }

        let firstStaleStatus = (0..<staleStatuses.count)
            .map { staleStatuses.element(boundBy: $0) }
            .min { $0.frame.minY < $1.frame.minY }
        guard let firstStaleStatus else { return }
        XCTAssertGreaterThan(firstStaleStatus.frame.minY, anthropicTitle.frame.minY)
        XCTAssertLessThan(
            abs(anthropicAmount.frame.midY - anthropicTitle.frame.midY),
            abs(anthropicAmount.frame.midY - firstStaleStatus.frame.midY)
        )
    }

    func testAccessibilityDynamicTypeKeepsAPISpendAmountsVisible() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--demo",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let window = app.windows.firstMatch
        let anthropicTitle = app.staticTexts["Anthropic API"].firstMatch
        let anthropicAmount = app.staticTexts["$142.67"].firstMatch
        let openAIAmount = app.staticTexts["$58.90"].firstMatch
        XCTAssertTrue(anthropicTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(anthropicAmount.exists)
        XCTAssertTrue(openAIAmount.exists)
        XCTAssertGreaterThan(anthropicAmount.frame.width, 0)
        XCTAssertGreaterThan(openAIAmount.frame.width, 0)
        XCTAssertLessThanOrEqual(anthropicAmount.frame.maxX, window.frame.maxX)
        XCTAssertLessThanOrEqual(openAIAmount.frame.maxX, window.frame.maxX)
        XCTAssertGreaterThan(anthropicAmount.frame.minY, anthropicTitle.frame.minY)
    }

    func testDemoContentFitsCurrentPhoneOrTabletWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()

        let window = app.windows.firstMatch
        let isTablet = window.frame.width >= 700
        defer { XCUIDevice.shared.orientation = .portrait }
        let claude = app.descendants(matching: .any)["headroom.provider.claude"]
        let codex = app.descendants(matching: .any)["headroom.provider.codex"]
        XCTAssertTrue(claude.waitForExistence(timeout: 5))
        XCTAssertTrue(codex.exists)
        XCTAssertTrue(window.frame.contains(claude.frame))
        XCTAssertTrue(window.frame.contains(codex.frame))

        if isTablet {
            XCTAssertLessThan(abs(claude.frame.midY - codex.frame.midY), 80)
            XCTAssertGreaterThan(codex.frame.minX, claude.frame.minX)
        } else {
            XCTAssertGreaterThan(codex.frame.minY, claude.frame.minY)
        }

        XCTAssertTrue(app.buttons["headroom.settings"].isHittable)

        if isTablet {
            XCUIDevice.shared.orientation = .landscapeLeft
            let rotated = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in window.frame.width > window.frame.height },
                object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            XCTAssertTrue(window.frame.contains(claude.frame))
            XCTAssertTrue(window.frame.contains(codex.frame))
            XCTAssertLessThan(abs(claude.frame.midY - codex.frame.midY), 80)
            XCTAssertTrue(app.buttons["headroom.settings"].isHittable)
        }
    }
}
