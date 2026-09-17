import XCTest

@MainActor
final class CurrentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = ["--light"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-privateTelemetryEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["batteryGauge"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDashboardHealthAndSessionNavigation() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["currentPower"].label, "USB input")
        XCTAssertFalse(app.buttons["healthShortcut"].exists)
        XCTAssertNotEqual(app.otherElements["dataMode"].label, "DEMO")
        capture("01-Charging-Light")
        app.buttons["tab.health"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["batteryTemperature"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["healthEstimate"].exists)
        XCTAssertFalse(app.staticTexts["Capacity"].exists)
        XCTAssertFalse(app.staticTexts["healthAccessNotice.message"].exists)
        XCTAssertEqual(
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Charge cycles")).count,
            0
        )
        capture("02-Health-Light")
        app.buttons["tab.sessions"].firstMatch.tap()
        XCTAssertTrue(app.tables["sessionsList"].waitForExistence(timeout: 5))
        capture("03-Sessions-Light")
    }

    func testChartWindowSwitching() {
        let app = launch()
        app.scrollViews["contentScroll"].swipeUp()
        let control = app.segmentedControls["chartWindow"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.buttons["Session"].tap()
        XCTAssertTrue(control.buttons["Session"].isSelected)
        let chart = app.otherElements["powerChart"]
        XCTAssertTrue(chart.exists)
        chart.tap()
        capture("05-Charging-Curve")
        control.buttons["5 min"].tap()
        XCTAssertTrue(control.buttons["5 min"].isSelected)
    }

    func testVerticalScrollStartingOnChart() {
        let app = launch()
        app.scrollViews["contentScroll"].swipeUp()
        let chart = app.otherElements["powerChart"]
        XCTAssertTrue(chart.isHittable)
        let initialY = chart.frame.minY
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 120)))
        XCTAssertGreaterThan(chart.frame.minY, initialY + 30, "Dragging down on the curve must scroll the page.")
        let lowerY = chart.frame.minY
        let next = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        next.press(forDuration: 0.05, thenDragTo: next.withOffset(CGVector(dx: 0, dy: -120)))
        XCTAssertLessThan(chart.frame.minY, lowerY - 30, "Dragging up on the curve must scroll the page.")
        capture("16-Chart-Vertical-Scrolling")
    }

    func testHorizontalChartDragDoesNotScrollPage() {
        let app = launch()
        app.scrollViews["contentScroll"].swipeUp()
        let chart = app.otherElements["powerChart"]
        XCTAssertTrue(chart.isHittable)
        let initialY = chart.frame.minY
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(chart.frame.minY, initialY, accuracy: 3)
    }

    func testDemoModeCannotBeReenabledByOldPreferencesOrArguments() {
        let app = launch(["--demo", "-demoEnabled", "YES", "--light"])
        XCTAssertNotEqual(app.otherElements["dataMode"].label, "DEMO")
        #if targetEnvironment(simulator)
            XCTAssertEqual(app.staticTexts["currentPower"].value as? String, "Unavailable")
        #endif
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.switches["privateTelemetryToggle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["demoToggle"].exists)
        XCTAssertEqual(app.switches.count, 2)
        capture("07-Settings")
    }

    func testLimitedDataNoticeOpensReaderDiagnostics() throws {
        #if targetEnvironment(simulator)
            let app = launch()
            app.buttons["chargingAccessNotice.details"].tap()
            XCTAssertTrue(app.staticTexts["sensorReadout"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["sensorReadout"].label.contains("iOS battery state"))
            XCTAssertTrue(app.staticTexts["sensorReadout"].label.contains("IOHID read"))
            capture("15-Limited-Data-Diagnostics")
        #else
            throw XCTSkip("The simulator-only fallback notice is not expected on a working physical sensor.")
        #endif
    }

    func testSettingsAndDiagnostics() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.switches["privateTelemetryToggle"].waitForExistence(timeout: 5))
        if !app.cells["sourceDiagnostics"].isHittable { app.tables["settingsList"].swipeUp() }
        app.cells["sourceDiagnostics"].tap()
        XCTAssertTrue(app.staticTexts["diagnosticMessage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["diagnosticMessage"].label.lowercased().contains("simulated"))
        capture("08-Diagnostics")
    }

    func testAppearanceSwitchesLiveAndPersistsAcrossLaunches() {
        var app = launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.cells["appearance.light"].waitForExistence(timeout: 5))
        app.cells["appearance.dark"].tap()
        XCTAssertTrue(app.cells["appearance.dark"].isSelected)
        capture("17-Settings-Dark")
        app.buttons["closeSettings"].tap()
        capture("18-Charging-Dark-Setting")
        app.buttons["tab.health"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["batteryTemperature"].waitForExistence(timeout: 5))
        capture("19-Health-Dark-Setting")
        app.buttons["settingsButton"].tap()
        app.cells["appearance.light"].tap()
        XCTAssertTrue(app.cells["appearance.light"].isSelected)
        capture("20-Settings-Light")
        app.cells["appearance.dark"].tap()
        app.terminate()

        // Do not pass a debug appearance override when verifying persistence.
        app = launch([])
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.cells["appearance.dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["appearance.dark"].isSelected)
        app.cells["appearance.auto"].tap()
        XCTAssertTrue(app.cells["appearance.auto"].isSelected)
        capture("21-Settings-Auto")
        app.terminate()

        app = launch([])
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.cells["appearance.auto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["appearance.auto"].isSelected)
    }

    func testDarkAppearanceAndRotation() {
        let app = launch(["--dark"])
        capture("09-Charging-Dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["batteryGauge"].exists)
        capture("10-Landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    func testExportPresentsShareSheet() {
        let app = launch()
        app.buttons["exportButton"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["LP.CaptionBar.TopCaption"].label, "Current-readings")
        capture("14-Export")
    }

    func testDeleteHistoryRequiresConfirmation() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        app.tables["settingsList"].swipeUp()
        app.cells["deleteSessions"].tap()
        let alert = app.alerts["Delete saved sessions?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
    }

    func testAccessibilityTextSize() {
        let app = launch([
            "--light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        capture("11-Accessibility-Charging")
        app.buttons["tab.health"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["batteryTemperature"].waitForExistence(timeout: 5))
        capture("12-Accessibility-Health")
        app.buttons["tab.sessions"].firstMatch.tap()
        XCTAssertTrue(app.tables["sessionsList"].waitForExistence(timeout: 5))
        capture("13-Accessibility-Sessions")
    }
}
