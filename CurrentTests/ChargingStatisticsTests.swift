@testable import Current
import XCTest

final class ChargingStatisticsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ second: Double, _ watts: Double?, level: Double? = nil) -> ChargingSample {
        ChargingSample(timestamp: epoch.addingTimeInterval(second), level: level, powerWatts: watts)
    }

    func testAverageIsTimeWeightedNotSampleWeighted() throws {
        let result = ChargingStatistics.calculate([sample(0, 10), sample(2, 20), sample(10, 20)])
        XCTAssertEqual(try XCTUnwrap(result.averageWatts), 19, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.energyWh), 190 / 3600, accuracy: 0.0001)
        XCTAssertEqual(result.peakWatts, 20)
        XCTAssertEqual(result.coveredSeconds, 10)
        XCTAssertEqual(result.coverage, 1)
    }

    func testWindowClipsAndInterpolatesBothEdges() throws {
        let result = ChargingStatistics.calculate(
            [sample(0, 10, level: 0.2), sample(10, 30, level: 0.4), sample(20, 10, level: 0.6)],
            in: DateInterval(start: epoch.addingTimeInterval(5), end: epoch.addingTimeInterval(15))
        )
        XCTAssertEqual(try XCTUnwrap(result.averageWatts), 25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.energyWh), 250 / 3600, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.levelGain), 20, accuracy: 0.0001)
        XCTAssertEqual(result.coveredSeconds, 10)
        XCTAssertEqual(result.peakWatts, 30)
    }

    func testFiveMinuteWindowDoesNotIncludeEarlierPeak() throws {
        let samples = (0 ... 360).map { second in
            sample(Double(second), second < 60 ? 30 : 10)
        }
        let result = ChargingStatistics.calculate(
            samples,
            in: DateInterval(start: epoch.addingTimeInterval(60), end: epoch.addingTimeInterval(360))
        )
        XCTAssertEqual(result.peakWatts, 10)
        XCTAssertEqual(try XCTUnwrap(result.averageWatts), 10, accuracy: 0.0001)
        XCTAssertEqual(result.coveredSeconds, 300)
    }

    func testLongGapDoesNotCreateEnergy() throws {
        let result = ChargingStatistics.calculate([
            sample(0, 10), sample(10, 10), sample(100, 40), sample(105, 40),
        ])
        XCTAssertEqual(result.coveredSeconds, 15)
        XCTAssertEqual(try XCTUnwrap(result.averageWatts), 20, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(result.energyWh), 300 / 3600, accuracy: 0.0001)
        XCTAssertEqual(result.coverage, 15 / 105, accuracy: 0.0001)
    }

    func testMissingReadingBreaksIntegration() {
        let result = ChargingStatistics.calculate([sample(0, 20), sample(2, nil), sample(4, 20)])
        XCTAssertNil(result.averageWatts)
        XCTAssertNil(result.energyWh)
        XCTAssertEqual(result.peakWatts, 20)
        XCTAssertEqual(result.coveredSeconds, 0)
    }

    func testMissingPowerStillAllowsObservedBatteryGain() throws {
        let result = ChargingStatistics.calculate([sample(0, nil, level: 0.4), sample(2, nil, level: 0.42)])
        XCTAssertNil(result.averageWatts)
        XCTAssertNil(result.energyWh)
        XCTAssertNil(result.peakWatts)
        XCTAssertEqual(try XCTUnwrap(result.levelGain), 2, accuracy: 0.0001)
    }

    func testSingleSampleDoesNotInventAverageOrEnergy() {
        let result = ChargingStatistics.calculate([sample(0, 18)])
        XCTAssertEqual(result.peakWatts, 18)
        XCTAssertNil(result.averageWatts)
        XCTAssertNil(result.energyWh)
        XCTAssertNil(result.levelGain)
    }

    func testZeroPowerIsMeasuredNotMissing() {
        let result = ChargingStatistics.calculate([sample(0, 0), sample(2, 0)])
        XCTAssertEqual(result.averageWatts, 0)
        XCTAssertEqual(result.energyWh, 0)
        XCTAssertEqual(result.coverage, 1)
    }

    func testNonfiniteAndNegativePowersAreExcluded() {
        let result = ChargingStatistics.calculate([
            sample(0, .nan), sample(2, .infinity), sample(4, -3), sample(6, 10),
        ])
        XCTAssertNil(result.averageWatts)
        XCTAssertNil(result.energyWh)
        XCTAssertEqual(result.peakWatts, 10)
    }

    func testOutsideWindowIsEmpty() {
        let result = ChargingStatistics.calculate(
            [sample(0, 20), sample(2, 20)],
            in: DateInterval(start: epoch.addingTimeInterval(20), duration: 300)
        )
        XCTAssertEqual(result.sampleCount, 0)
        XCTAssertNil(result.averageWatts)
    }
}
