import XCTest

@MainActor
final class LockScreenLayoutUITests: XCTestCase {
    func testCircularReadableContentFitsAtDefaultSize() {
        check(fixture: "claudeCodex", provider: "automatic", size: "UICTContentSizeCategoryL")
    }

    func testCircularReadableContentFitsAtLargestLabelSize() {
        for provider in ["claude", "codex", "grok", "cursor"] {
            for fixture in ["full", "empty"] {
                check(fixture: fixture, provider: provider, size: "UICTContentSizeCategoryXL")
            }
        }
    }

    func testCircularStatusLabelsFitAtLargestLabelSize() {
        for fixture in ["staleUnavailable", "pending", "signedOut", "resetReached"] {
            check(fixture: fixture, provider: "automatic", size: "UICTContentSizeCategoryXL")
        }
    }

    private func check(fixture: String, provider: String, size: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-screen", "widgets", "--widget-wall", "lock",
                               "-UIPreferredContentSizeCategoryName", size]
        app.launchEnvironment["HEADROOM_LOCK_FIXTURE"] = fixture
        app.launchEnvironment["HEADROOM_LOCK_PROVIDER"] = provider
        app.launch()
        for style in ["nestedMeter", "vesselHero", "tightestFirst", "liquidLevel"] {
            for side in [58, 62, 68, 76] {
                let result = app.staticTexts["lock.bounds.\(style).\(side)"]
                if style == "nestedMeter", side == 58 {
                    XCTAssertTrue(result.waitForExistence(timeout: 5))
                } else {
                    XCTAssertTrue(result.exists)
                }
                XCTAssertEqual(result.label, "0", "\(fixture)/\(provider)/\(style)/\(side): \(result.value ?? "")")
            }
        }
        app.terminate()
    }
}
