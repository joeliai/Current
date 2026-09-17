@testable import Current
import XCTest

final class SessionRecorderTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(_ seconds: Double, state: ChargeState = .charging) -> BatterySnapshot {
        var value = BatterySnapshot.unavailable
        value.timestamp = epoch.addingTimeInterval(seconds)
        value.state = state
        value.level = 0.5
        value.usbInputVoltageVolts = 5
        value.usbInputCurrentAmps = 2.4
        value.isWireless = false
        return value
    }

    func testConnectPauseFullAndDisconnectLifecycle() throws {
        var recorder = SessionRecorder()
        recorder.record(snapshot(0, state: .unplugged))
        XCTAssertNil(recorder.active)
        recorder.record(snapshot(2))
        let id = try XCTUnwrap(recorder.active?.id)
        recorder.record(snapshot(4, state: .pluggedIn))
        recorder.record(snapshot(6, state: .full))
        XCTAssertEqual(recorder.active?.id, id)
        recorder.record(snapshot(8, state: .unplugged))
        XCTAssertNil(recorder.active)
        XCTAssertEqual(recorder.history.count, 1)
        XCTAssertEqual(recorder.history.first?.endReason, .disconnected)
        XCTAssertEqual(recorder.history.first?.endedAt, epoch.addingTimeInterval(6))
    }

    func testForegroundGapStartsNewObservation() throws {
        var recorder = SessionRecorder()
        recorder.record(snapshot(0))
        recorder.record(snapshot(2))
        let id = try XCTUnwrap(recorder.active?.id)
        recorder.record(snapshot(20))
        XCTAssertNotEqual(recorder.active?.id, id)
        XCTAssertEqual(recorder.history.first?.endReason, .interrupted)
        XCTAssertEqual(recorder.history.first?.duration, 2)
    }

    func testBackgroundEndsAtLastObservedSample() {
        var recorder = SessionRecorder()
        recorder.record(snapshot(0))
        recorder.record(snapshot(2))
        recorder.finish(reason: .monitoringPaused)
        XCTAssertNil(recorder.active)
        XCTAssertEqual(recorder.history.first?.duration, 2)
        XCTAssertEqual(recorder.history.first?.endReason, .monitoringPaused)
    }

    func testDuplicateAndReversedTimestampsAreIgnored() {
        var recorder = SessionRecorder()
        recorder.record(snapshot(2))
        recorder.record(snapshot(2))
        recorder.record(snapshot(1))
        XCTAssertEqual(recorder.active?.samples.count, 1)
    }

    func testRestoreDropsLegacyDemoSessionsWithoutDroppingRealHistory() {
        let real = ChargingSession(startedAt: epoch, samples: [ChargingSample(snapshot: snapshot(0))])
        var legacyDemo = real
        legacyDemo.isDemo = true
        var recorder = SessionRecorder()
        recorder.restore(history: [legacyDemo, real], interrupted: legacyDemo)
        XCTAssertNil(recorder.active)
        XCTAssertEqual(recorder.history, [real])
    }

    func testClearingHistoryKeepsActiveObservation() {
        var recorder = SessionRecorder()
        recorder.record(snapshot(0))
        recorder.finish(reason: .disconnected)
        recorder.record(snapshot(4))
        recorder.clearHistory()
        XCTAssertTrue(recorder.history.isEmpty)
        XCTAssertEqual(recorder.active?.samples.count, 1)
        XCTAssertEqual(recorder.active?.isDemo, false)
    }

    func testRestoreNeverResumesAnUnobservedConnection() throws {
        var original = SessionRecorder()
        original.record(snapshot(0))
        original.record(snapshot(2))
        let archive = SessionArchive(sessions: original.history, activeSession: original.active)
        let data = try JSONEncoder().encode(archive)
        let restored = try JSONDecoder().decode(SessionArchive.self, from: data)
        var recorder = SessionRecorder()
        recorder.restore(history: restored.sessions, interrupted: restored.activeSession)
        XCTAssertNil(recorder.active)
        XCTAssertEqual(recorder.history.first?.endReason, .interrupted)
        XCTAssertEqual(recorder.history.first?.samples.count, 2)
    }

    func testUnknownStateDoesNotLeaveAnActiveSession() {
        var recorder = SessionRecorder()
        recorder.record(snapshot(0))
        recorder.record(snapshot(2, state: .unknown))
        XCTAssertNil(recorder.active)
        XCTAssertEqual(recorder.history.first?.endReason, .interrupted)
    }

    func testHistoryIsBounded() {
        var recorder = SessionRecorder()
        for index in 0 ..< 40 {
            recorder.record(snapshot(Double(index * 4)))
            recorder.finish(reason: .disconnected)
        }
        XCTAssertEqual(recorder.history.count, SessionRecorder.historyLimit)
    }

    func testMeasurementBasisChangeStartsSeparateSession() throws {
        var recorder = SessionRecorder()
        var legacy = snapshot(0)
        legacy.powerMeasurement = .batteryIntake
        legacy.voltageVolts = 4
        legacy.currentAmps = 1
        recorder.record(legacy)
        recorder.record(snapshot(2))
        recorder.record(snapshot(4))
        XCTAssertEqual(recorder.history.first?.measurement, .batteryIntake)
        XCTAssertEqual(recorder.history.first?.endReason, .sourceChanged)
        XCTAssertEqual(recorder.history.first?.statistics.peakWatts, 4)
        XCTAssertEqual(recorder.active?.measurement, .usbInput)
        XCTAssertEqual(try XCTUnwrap(recorder.active?.statistics.averageWatts), 12, accuracy: 0.001)
    }

    func testMissingUSBReadingsDoNotSwitchToBatteryPowerOrAdapterRating() {
        var recorder = SessionRecorder()
        recorder.record(snapshot(0))
        var missing = snapshot(2)
        missing.usbInputCurrentAmps = nil
        missing.voltageVolts = 4
        missing.currentAmps = 3
        missing.adapterRatedWatts = 30
        recorder.record(missing)
        recorder.record(snapshot(4))
        XCTAssertTrue(recorder.history.isEmpty)
        XCTAssertEqual(recorder.active?.samples.count, 3)
        XCTAssertNil(recorder.active?.samples[1].powerWatts)
        XCTAssertNil(recorder.active?.statistics.averageWatts)
    }

    func testLegacyArchiveRetainsBatteryIntakeMeaning() throws {
        let session = ChargingSession(
            startedAt: epoch,
            endedAt: epoch.addingTimeInterval(2),
            isDemo: false,
            samples: [
                ChargingSample(timestamp: epoch, powerWatts: 4),
                ChargingSample(timestamp: epoch.addingTimeInterval(2), powerWatts: 4),
            ]
        )
        let oldArchive = SessionArchive(version: 1, sessions: [session])
        let oldData = try JSONEncoder().encode(oldArchive)
        let oldJSON = try XCTUnwrap(String(data: oldData, encoding: .utf8))
        XCTAssertFalse(oldJSON.contains("powerMeasurement"))
        let restored = try JSONDecoder().decode(SessionArchive.self, from: oldData)
        XCTAssertEqual(restored.sessions.first?.measurement, .batteryIntake)
        XCTAssertEqual(restored.sessions.first?.statistics.averageWatts, 4)
        let newArchive = SessionArchive(sessions: restored.sessions)
        XCTAssertEqual(newArchive.version, 2)
        let roundTrip = try JSONDecoder().decode(SessionArchive.self, from: JSONEncoder().encode(newArchive))
        XCTAssertEqual(roundTrip.sessions.first?.measurement, .batteryIntake)
    }

    func testLegacySnapshotStillDecodesAsBatteryIntake() throws {
        var oldSnapshot = snapshot(0)
        oldSnapshot.powerMeasurement = nil
        oldSnapshot.source = .privateAPI
        oldSnapshot.usbInputVoltageVolts = nil
        oldSnapshot.usbInputCurrentAmps = nil
        oldSnapshot.voltageVolts = 4
        oldSnapshot.currentAmps = 3
        let data = try JSONEncoder().encode(oldSnapshot)
        let restored = try JSONDecoder().decode(BatterySnapshot.self, from: data)
        XCTAssertEqual(restored.measurement, .batteryIntake)
        XCTAssertEqual(restored.chargingPowerWatts, 12)
        XCTAssertNil(restored.usbInputPowerWatts)
    }

    @MainActor
    func testExportContainsRealReadingsAndMeasurementDefinition() throws {
        let session = ChargingSession(
            startedAt: epoch, powerMeasurement: .usbInput,
            samples: [ChargingSample(snapshot: snapshot(0)), ChargingSample(snapshot: snapshot(2))]
        )
        let url = try BatteryMonitor.shared.export(session: session)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json["isDemo"] as? Bool, false)
        XCTAssertEqual(json["formatVersion"] as? Int, 2)
        XCTAssertTrue((json["measurement"] as? String)?.contains("Not wall") == true)
        XCTAssertTrue((json["measurement"] as? String)?.contains("USB") == true)
        XCTAssertNil(json["snapshot"])
        XCTAssertEqual((json["sessions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((json["sessions"] as? [[String: Any]])?.first?["powerMeasurement"] as? String, "usbInput")
    }
}
