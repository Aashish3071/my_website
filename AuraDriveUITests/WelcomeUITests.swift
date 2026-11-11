import XCTest

final class WelcomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenShowsTitleAndPrimaryAction() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts[AccessibilityID.Welcome.title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[AccessibilityID.Welcome.getStartedButton].isHittable)
    }

    /// Runs Xcode's built-in accessibility audit: contrast, hit-target size,
    /// missing labels, clipped text and Dynamic Type support.
    @MainActor
    func testWelcomeScreenPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts[AccessibilityID.Welcome.title].waitForExistence(timeout: 5))

        try app.performAccessibilityAudit()
    }

    /// Same audit at the largest accessibility text size.
    @MainActor
    func testWelcomeScreenPassesAccessibilityAuditAtLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts[AccessibilityID.Welcome.title].waitForExistence(timeout: 5))

        try app.performAccessibilityAudit()
    }
}
