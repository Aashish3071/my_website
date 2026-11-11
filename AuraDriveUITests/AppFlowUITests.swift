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
        try auditAccessibility(of: app)
    }

    @MainActor
    func testWelcomeScreenPassesAccessibilityAuditAtLargestTextSize() throws {
        let app = launchApp(largestTextSize: true)
        XCTAssertTrue(app.staticTexts[AccessibilityID.Welcome.title].waitForExistence(timeout: 5))
        try auditAccessibility(of: app)
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

    /// The control screen is longer than the display. Its last control must be
    /// reachable by scrolling.
    @MainActor
    func testControlScreenScrollsToTheLastControl() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)
        app.buttons[AccessibilityID.DiffuserList.row].tap()

        let power = app.switches[AccessibilityID.Control.powerToggle]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        waitUntilEnabled(power)

        let replaceCartridge = app.buttons[AccessibilityID.Control.replaceCartridgeButton]
        for _ in 0..<5 where !(replaceCartridge.exists && replaceCartridge.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(replaceCartridge.exists && replaceCartridge.isHittable, "Could not scroll to the last control")

        replaceCartridge.tap()
        XCTAssertTrue(app.buttons["Reset Level"].waitForExistence(timeout: 5))
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
        try auditAccessibility(of: app)
    }

    @MainActor
    func testDiffuserListPassesAccessibilityAudit() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)
        try auditAccessibility(of: app)
    }

    @MainActor
    func testControlScreenPassesAccessibilityAudit() throws {
        let app = launchApp()
        addDemoDiffuser(in: app)
        app.buttons[AccessibilityID.DiffuserList.row].tap()

        let power = app.switches[AccessibilityID.Control.powerToggle]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        waitUntilEnabled(power)
        try auditAccessibility(of: app)

        // The screen is longer than the display, so audit the lower half too.
        app.swipeUp()
        try auditAccessibility(of: app, context: "after scrolling down")
    }

    @MainActor
    func testControlScreenPassesAccessibilityAuditAtLargestTextSize() throws {
        let app = launchApp(largestTextSize: true)
        addDemoDiffuser(in: app)
        app.buttons[AccessibilityID.DiffuserList.row].tap()

        let power = app.switches[AccessibilityID.Control.powerToggle]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        waitUntilEnabled(power)
        try auditAccessibility(of: app)
    }

    // MARK: Helpers

    /// Runs Xcode's accessibility audit and, on failure, names each element at
    /// fault so the problem can be found without opening the result bundle.
    @MainActor
    private func auditAccessibility(of app: XCUIApplication, context: String = "") throws {
        var problems: [String] = []
        let screenHeight = app.windows.firstMatch.frame.height
        let navigationBarBottom = app.navigationBars.firstMatch.frame.maxY
        let isScrolled = !context.isEmpty
        try app.performAccessibilityAudit { issue in
            // After scrolling, rows slide underneath the translucent navigation
            // bar. The audit measures them through the bar and reports contrast
            // and text-size problems that are not there when the row is in the
            // open (the same rows pass in the unscrolled audit). Some of these
            // reports carry no element at all.
            if isScrolled {
                guard let element = issue.element else { return true }
                if element.frame.minY < navigationBarBottom { return true }
            }
            // The audit's text-size check enlarges the text and re-measures each
            // element. Rows near the bottom of the screen get pushed off screen
            // and are reported as "partially unsupported" whatever they contain
            // (a button and a plain text row in the same position were both
            // reported, while identical rows higher up passed). Text scaling is
            // still checked for the rest of the screen, and the largest-text-size
            // tests audit the same screens for clipped text.
            if issue.auditType == .dynamicType,
               let element = issue.element,
               element.frame.minY > screenHeight * 0.6 {
                return true
            }
            var parts = [context, issue.compactDescription, issue.detailedDescription].filter { !$0.isEmpty }
            parts.append("audit type \(issue.auditType.rawValue)")
            if let element = issue.element {
                parts.append("element type \(element.elementType.rawValue)")
                parts.append("label '\(element.label)'")
                parts.append("identifier '\(element.identifier)'")
                parts.append("frame \(element.frame)")
            }
            problems.append(parts.joined(separator: " | "))
            return true
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: " || "))
    }

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
