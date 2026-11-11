import XCTest

final class AppFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Welcome

    @MainActor
    func testWelcomeScreenPassesAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts[AccessibilityID.Welcome.title].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testWelcomeScreenPassesAccessibilityAuditAtLargestTextSize() throws {
        let app = launchApp(largestTextSize: true)
        XCTAssertTrue(app.staticTexts[AccessibilityID.Welcome.title].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    // MARK: Main flow

    @MainActor
    func testAddDiffuserAndTurnItOn() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)

        app.buttons[AccessibilityID.DiffuserList.row].tap()

        let power = app.switches[AccessibilityID.Control.powerToggle]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        waitUntilEnabled(power)
        XCTAssertEqual(power.value as? String, "0")

        tapSwitch(power)
        waitForValue("1", of: power)
    }

    @MainActor
    func testForgettingADiffuserReturnsToTheEmptyList() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)

        app.buttons[AccessibilityID.DiffuserList.row].tap()
        let details = app.buttons[AccessibilityID.Control.detailsButton]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        let forget = app.buttons[AccessibilityID.Details.forgetButton]
        XCTAssertTrue(forget.waitForExistence(timeout: 5))
        forget.tap()
        let confirm = app.buttons["Forget Diffuser"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.buttons[AccessibilityID.DiffuserList.emptyAddButton].waitForExistence(timeout: 5))
    }

    // MARK: Accessibility audits of the main screens

    @MainActor
    func testEmptyListPassesAccessibilityAudit() throws {
        let app = launchApp()
        app.buttons[AccessibilityID.Welcome.getStartedButton].tap()
        XCTAssertTrue(app.buttons[AccessibilityID.DiffuserList.emptyAddButton].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testDiffuserListPassesAccessibilityAudit() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testControlScreenPassesAccessibilityAudit() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)
        app.buttons[AccessibilityID.DiffuserList.row].tap()

        let power = app.switches[AccessibilityID.Control.powerToggle]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        waitUntilEnabled(power)
        try app.performAccessibilityAudit()
    }

    @MainActor
    func testControlScreenPassesAccessibilityAuditAtLargestTextSize() throws {
        let app = launchApp(largestTextSize: true)
        addDemoDiffuser(in: app)
        app.buttons[AccessibilityID.DiffuserList.row].tap()

        let power = app.switches[AccessibilityID.Control.powerToggle]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        waitUntilEnabled(power)
        try app.performAccessibilityAudit()
    }

    // MARK: Helpers

    @MainActor
    private func launchApp(largestTextSize: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [LaunchArgument.uiTesting]
        if largestTextSize {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        return app
    }

    /// Goes from the welcome screen to a list that contains the demo diffuser.
    @MainActor
    private func addDemoDiffuser(in app: XCUIApplication) {
        let getStarted = app.buttons[AccessibilityID.Welcome.getStartedButton]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        let add = app.buttons[AccessibilityID.DiffuserList.emptyAddButton]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()

        let result = app.buttons[AccessibilityID.AddDiffuser.result].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        XCTAssertTrue(app.buttons[AccessibilityID.DiffuserList.row].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement) {
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: 5)
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement) {
        let matches = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [matches], timeout: 5)
    }

    /// In a form, the switch itself sits inside the row, so tap the inner control.
    @MainActor
    private func tapSwitch(_ element: XCUIElement) {
        let inner = element.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            element.tap()
        }
    }
}
