@testable import Current
import XCTest

final class PowerChartSeriesTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ time: Double, _ power: Double?) -> ChargingSample {
        ChargingSample(timestamp: epoch.addingTimeInterval(time), powerWatts: power)
    }

    func testReductionPreservesPeaksValleysAndOriginalSamples() {
        let original = (0 ..< 4000).map { index in
            sample(Double(index * 2), index == 123 ? 40 : index == 367 ? 0 : 12)
        }
        let series = PowerChartSeries(samples: original, window: .session, columns: 16)
        let drawn = series.segments.flatMap { $0 }
        XCTAssertLessThanOrEqual(drawn.count, 64)
        XCTAssertEqual(drawn.compactMap(\.powerWatts).max(), 40)
        XCTAssertEqual(drawn.compactMap(\.powerWatts).min(), 0)
        XCTAssertEqual(drawn.first, original.first)
        XCTAssertEqual(drawn.last, original.last)
        XCTAssertEqual(series.samples, original, "Scrubbing must use full-resolution readings.")
    }

    func testMissingValuesAndLongGapsNeverGetConnected() {
        let series = PowerChartSeries(
            samples: [sample(0, 10), sample(2, 12), sample(4, nil), sample(6, 14), sample(8, 16), sample(100, 20)],
            window: .session, columns: 10
        )
        XCTAssertEqual(series.segments.map(\.count), [2, 2, 1])
        XCTAssertEqual(series.samples.count, 5)
    }

    func testInvalidValuesBreakTheCurveAndZeroRemainsValid() {
        let series = PowerChartSeries(
            samples: [sample(0, 10), sample(2, .nan), sample(4, 20), sample(6, .infinity),
                      sample(8, 0), sample(10, -1), sample(12, 30)],
            window: .session, columns: 10
        )
        XCTAssertEqual(series.segments.map(\.count), [1, 1, 1, 1])
        XCTAssertEqual(series.samples.compactMap(\.powerWatts), [10, 20, 0, 30])
    }

    func testFiveMinuteScrubbingCannotSelectOutsideTheWindow() {
        let series = PowerChartSeries(
            samples: (0 ... 300).map { sample(Double($0 * 2), $0 == 0 ? 100 : 10) },
            window: .recent, columns: 50
        )
        XCTAssertEqual(series.start, epoch.addingTimeInterval(300))
        XCTAssertEqual(series.samples.first?.timestamp, series.start)
        XCTAssertEqual(series.samples.count, 151)
        XCTAssertEqual(series.maximumWatts, 10)
        XCTAssertEqual(series.nearestIndex(to: epoch), 0)
        XCTAssertEqual(series.nearestIndex(to: epoch.addingTimeInterval(301)), 0)
        XCTAssertEqual(series.nearestIndex(to: epoch.addingTimeInterval(302)), 1)
        XCTAssertEqual(series.nearestIndex(to: epoch.addingTimeInterval(800)), 150)
    }

    func testEmptySeriesHasNoSelection() {
        let series = PowerChartSeries(samples: [], window: .recent, columns: 0)
        XCTAssertTrue(series.segments.isEmpty)
        XCTAssertNil(series.nearestIndex(to: epoch))
    }
}
