import XCTest

@MainActor
final class ChartPerformanceUITests: XCTestCase {
    func testSegmentSwitchHitches() {
        let app = XCUIApplication()
        app.launchArguments = ["--live", "--light"]
        app.launch()
        XCTAssertTrue(app.otherElements["batteryGauge"].waitForExistence(timeout: 10))
        app.scrollViews["contentScroll"].swipeUp()
        let control = app.segmentedControls["chartWindow"]
        XCTAssertTrue(control.isHittable)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app)], options: options) {
            for _ in 0 ..< 3 {
                control.buttons["Session"].tap()
                control.buttons["5 min"].tap()
            }
        }
    }
}
