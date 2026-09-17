@testable import Current
import UIKit
import XCTest

@MainActor
final class ChartPerformanceTests: XCTestCase {
    func testRepeatedEightHourWindowRendering() {
        // Synthetic samples exist only in the test bundle, never in the app.
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0 ... 14400).map { index in
            ChargingSample(
                timestamp: epoch.addingTimeInterval(Double(index * 2)),
                powerWatts: 12 + sin(Double(index) / 30) * 8
            )
        }
        let session = ChargingSession(startedAt: epoch, isDemo: false, powerMeasurement: .usbInput, samples: samples)
        let chart = PowerChartView(frame: CGRect(x: 0, y: 0, width: 350, height: 176))
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: chart.bounds.size, format: format)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            for _ in 0 ..< 5 {
                for window in [ChartWindow.recent, .session] {
                    chart.set(session: session, window: window)
                    chart.layer.displayIfNeeded()
                    _ = renderer.image { chart.layer.render(in: $0.cgContext) }
                }
            }
        }
    }
}
