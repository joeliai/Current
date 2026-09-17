@testable import Current
import XCTest

final class HIDTelemetryParserTests: XCTestCase {
    private var baseline: BatterySnapshot {
        var snapshot = BatterySnapshot.unavailable
        snapshot.level = 0.68
        snapshot.state = .charging
        snapshot.fieldSources = ["Connection": "UIDevice.batteryState", "Battery level": "UIDevice.batteryLevel"]
        return snapshot
    }

    private func sensor(_ name: String, _ value: Any, page: Int = 0xFF08, usage: Int) -> [String: Any] {
        ["name": name, "value": value, "PrimaryUsagePage": page, "PrimaryUsage": usage]
    }

    private var telemetry: HIDTelemetry {
        HIDTelemetry(
            sensors: [
                sensor("Charger VQ0u", 5.0, usage: 3),
                sensor("Charger IQ0u", 2.0, usage: 2),
                sensor("gas gauge battery", 33.5, page: 0xFF00, usage: 5),
            ],
            adapter: ["Watts": 30, "IsWireless": false, "AdapterVoltage": 9000, "Current": 3000]
        )
    }

    func testUSBSensorUnitsAreNotBatteryOrAdapterContractUnits() {
        let snapshot = HIDTelemetryParser.parse(telemetry, into: baseline)
        XCTAssertEqual(snapshot.source, .hidSensors)
        XCTAssertEqual(snapshot.measurement, .usbInput)
        XCTAssertEqual(snapshot.usbInputVoltageVolts, 5)
        XCTAssertEqual(snapshot.usbInputCurrentAmps, 2)
        XCTAssertEqual(snapshot.chargingPowerWatts, 10)
        XCTAssertEqual(snapshot.temperatureCelsius, 33.5)
        XCTAssertEqual(snapshot.adapterRatedWatts, 30)
        XCTAssertNil(snapshot.voltageVolts)
        XCTAssertNil(snapshot.currentAmps)
        XCTAssertNil(snapshot.netBatteryPowerWatts)
        XCTAssertEqual(snapshot.level, 0.68)
        XCTAssertEqual(snapshot.fieldSources["USB voltage"], "IOHID.Charger VQ0u (V)")
    }

    func testAdapterRatingAndContractNeverSubstituteForSensorMeasurements() {
        var raw = telemetry
        raw.sensors = []
        let snapshot = HIDTelemetryParser.parse(raw, into: baseline)
        XCTAssertEqual(snapshot.adapterRatedWatts, 30)
        XCTAssertNil(snapshot.chargingPowerWatts)
        XCTAssertNil(snapshot.usbInputVoltageVolts)
        XCTAssertNil(snapshot.usbInputCurrentAmps)
    }

    func testMissingEventIsUnavailableNotZero() {
        var raw = telemetry
        raw.sensors[1].removeValue(forKey: "value")
        let snapshot = HIDTelemetryParser.parse(raw, into: baseline)
        XCTAssertNil(snapshot.chargingPowerWatts)
        XCTAssertFalse(snapshot.hasElectricalTelemetry)
        XCTAssertEqual(snapshot.temperatureCelsius, 33.5)
    }

    func testZeroCurrentIsAValidMeasurementAndDoesNotInferPaused() {
        var raw = telemetry
        raw.sensors[1]["value"] = 0
        let snapshot = HIDTelemetryParser.parse(raw, into: baseline)
        XCTAssertEqual(snapshot.chargingPowerWatts, 0)
        XCTAssertTrue(snapshot.hasElectricalTelemetry)
        XCTAssertEqual(snapshot.state, .charging)
        XCTAssertEqual(snapshot.fieldSources["Connection"], "UIDevice.batteryState")
    }

    func testInvalidValuesAreRejected() {
        for invalid in [true, Double.nan, Double.infinity, -1, 1000, "2.0"] as [Any] {
            var raw = telemetry
            raw.sensors[1]["value"] = invalid
            XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        }
        for invalid in [true, Double.nan, 0, 1, 5000] as [Any] {
            var raw = telemetry
            raw.sensors[0]["value"] = invalid
            XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        }
    }

    func testWrongUsageAndUnknownSensorNamesCannotFormUSBPair() {
        var raw = telemetry
        raw.sensors[0]["PrimaryUsage"] = 2
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        raw = telemetry
        raw.sensors[0]["PrimaryUsagePage"] = 0xFF00
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        raw = telemetry
        raw.sensors[1]["name"] = "Charger IQ0B"
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        raw = telemetry
        raw.sensors[0]["name"] = "Charger VQ1u"
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
    }

    func testDuplicateUSBSensorNameIsAmbiguousEvenIfDuplicateIsInvalid() {
        for duplicate in [2.0, Double.nan] {
            var raw = telemetry
            raw.sensors.append(sensor("Charger IQ0u", duplicate, usage: 2))
            XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        }
    }

    func testWirelessAndUnknownAdapterTypesNeverUseUSBReadings() {
        var raw = telemetry
        raw.adapter["IsWireless"] = true
        let wireless = HIDTelemetryParser.parse(raw, into: baseline)
        XCTAssertNil(wireless.chargingPowerWatts)
        XCTAssertEqual(wireless.temperatureCelsius, 33.5)
        XCTAssertTrue(wireless.diagnostic.contains("Wireless"))
        for unknown in [nil, 2, "false"] as [Any?] {
            raw.adapter["IsWireless"] = unknown
            XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).chargingPowerWatts)
        }
    }

    func testPublicDisconnectClearsPowerAndAdapterButKeepsTemperature() {
        var publicReading = baseline
        publicReading.state = .unplugged
        let snapshot = HIDTelemetryParser.parse(telemetry, into: publicReading)
        XCTAssertEqual(snapshot.state, .unplugged)
        XCTAssertNil(snapshot.chargingPowerWatts)
        XCTAssertNil(snapshot.usbInputVoltageVolts)
        XCTAssertNil(snapshot.adapterRatedWatts)
        XCTAssertNil(snapshot.isWireless)
        XCTAssertEqual(snapshot.temperatureCelsius, 33.5)
    }

    func testUnknownStateDoesNotInferConnectionFromStaleSensors() {
        var publicReading = baseline
        publicReading.state = .unknown
        let snapshot = HIDTelemetryParser.parse(telemetry, into: publicReading)
        XCTAssertEqual(snapshot.state, .unknown)
        XCTAssertNil(snapshot.chargingPowerWatts)
        XCTAssertNil(snapshot.adapterRatedWatts)
    }

    func testFullAndConnectedStatesMayStillHaveUSBInputWithoutBatteryCharging() {
        for state in [ChargeState.full, .pluggedIn] {
            var publicReading = baseline
            publicReading.state = state
            let snapshot = HIDTelemetryParser.parse(telemetry, into: publicReading)
            XCTAssertEqual(snapshot.chargingPowerWatts, 10)
            XCTAssertEqual(snapshot.state, state)
            XCTAssertNil(snapshot.netBatteryPowerWatts)
        }
    }

    func testSlowOrInvalidPollIsNotRecordedAsSimultaneousPower() {
        for duration in [2.1, -1, Double.infinity, Double.nan] {
            var raw = telemetry
            raw.duration = duration
            let snapshot = HIDTelemetryParser.parse(raw, into: baseline)
            XCTAssertNil(snapshot.chargingPowerWatts)
            XCTAssertNil(snapshot.temperatureCelsius)
        }
    }

    func testAgreeingBatteryTemperatureDuplicatesUseMedian() {
        var raw = telemetry
        raw.sensors.append(sensor("gas gauge battery", 33.7, page: 0xFF00, usage: 5))
        XCTAssertEqual(HIDTelemetryParser.parse(raw, into: baseline).temperatureCelsius, 33.6)
        raw.sensors.append(sensor("gas gauge battery", 33.8, page: 0xFF00, usage: 5))
        XCTAssertEqual(HIDTelemetryParser.parse(raw, into: baseline).temperatureCelsius, 33.7)
    }

    func testDisagreeingOrInvalidTemperaturesAreNotInvented() {
        var raw = telemetry
        raw.sensors.append(sensor("gas gauge battery", 39, page: 0xFF00, usage: 5))
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).temperatureCelsius)
        raw = telemetry
        raw.sensors[2]["value"] = -9199.4
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).temperatureCelsius)
        raw.sensors[2]["name"] = "Charger TQ0j"
        raw.sensors[2]["value"] = 33
        XCTAssertNil(HIDTelemetryParser.parse(raw, into: baseline).temperatureCelsius)
    }

    func testNewPollDoesNotReusePriorPower() {
        let previous = HIDTelemetryParser.parse(telemetry, into: baseline)
        let snapshot = HIDTelemetryParser.parse(HIDTelemetry(sensors: []), into: previous)
        XCTAssertNil(snapshot.chargingPowerWatts)
        XCTAssertNil(snapshot.temperatureCelsius)
        XCTAssertNil(snapshot.fieldSources["USB voltage"])
        XCTAssertEqual(snapshot.source, .publicAPI)
    }

    func testDiagnosticsAndExportContainOnlyAllowlistedSensorData() throws {
        var raw = telemetry
        raw.adapter["SerialNumber"] = "private-adapter-serial"
        raw.sensors[0]["SerialNumber"] = "private-sensor-serial"
        raw.sensors.append(sensor("private-unrelated-sensor", 12, usage: 3))
        let snapshot = HIDTelemetryParser.parse(raw, into: baseline)
        XCTAssertEqual(snapshot.readerDiagnostics?["USB pair"], "validated")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        XCTAssertFalse(json.contains("private-adapter-serial"))
        XCTAssertFalse(json.contains("private-sensor-serial"))
        XCTAssertFalse(json.contains("private-unrelated-sensor"))
        XCTAssertTrue(json.contains("usbInput"))
    }

    #if targetEnvironment(simulator)
        func testSimulatorCannotReadHostSensorsOrAdapter() {
            XCTAssertThrowsError(try BatterySensorReader.reading()) { error in
                XCTAssertTrue(error.localizedDescription.contains("Host-computer IOHID"))
            }
        }
    #endif
}
