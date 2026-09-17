import CoreFoundation
import Foundation

struct HIDTelemetry {
    var sensors: [[String: Any]]
    var adapter: [String: Any] = [:]
    var diagnostics: [String: String] = [:]
    var duration: TimeInterval = 0
}

enum HIDTelemetryParser {
    // Reverse-engineered mappings observed on a physical iPhone.
    // Unknown names/usage codes and ambiguous pairs are not interchangeable.
    private static let usbVoltage = "Charger VQ0u"
    private static let usbCurrent = "Charger IQ0u"
    private static let batteryTemperature = "gas gauge battery"

    static func parse(_ telemetry: HIDTelemetry, into baseline: BatterySnapshot) -> BatterySnapshot {
        var result = baseline
        result.powerMeasurement = .usbInput
        result.usbInputVoltageVolts = nil
        result.usbInputCurrentAmps = nil
        result.voltageVolts = nil
        result.currentAmps = nil
        result.temperatureCelsius = nil
        result.adapterRatedWatts = nil
        result.adapterName = nil
        result.isWireless = nil
        result.fieldSources = baseline.fieldSources.filter {
            $0.value.hasPrefix("UIDevice.") || $0.value.hasPrefix("ProcessInfo.")
        }
        var diagnostics = baseline.readerDiagnostics ?? [:]
        diagnostics.merge(telemetry.diagnostics) { _, new in new }
        diagnostics["Power measurement"] = PowerMeasurement.usbInput.definition

        if result.state.isConnected {
            if let wireless = telemetry.adapter["IsWireless"] as? NSNumber,
               wireless.doubleValue == 0 || wireless.doubleValue == 1
            {
                result.isWireless = wireless.boolValue
                result.fieldSources["Power connection type"] = "IOPSCopyExternalPowerAdapterDetails.IsWireless"
            }
            if let ratedWatts = number(telemetry.adapter["Watts"]), (1 ... 500).contains(ratedWatts) {
                result.adapterRatedWatts = ratedWatts
                result.fieldSources["Adapter rating"] = "IOPSCopyExternalPowerAdapterDetails.Watts (rated, not measured)"
            }
        }

        let timely = telemetry.duration.isFinite && (0 ... 2).contains(telemetry.duration)
        diagnostics["Sensor poll"] = timely ? "Sensor pair read in one poll" : "Slow / invalid poll discarded"
        let voltage = values(usbVoltage, page: 0xFF08, usage: 3, range: 3.5 ... 24, in: telemetry)
        let current = values(usbCurrent, page: 0xFF08, usage: 2, range: 0 ... 6, in: telemetry)
        // Require explicit wired confirmation: USB sensors must not be reused as
        // wireless input, and disconnects must clear the previous adapter/power.
        if timely, result.state.isConnected, result.isWireless == false,
           voltage.count == 1, current.count == 1
        {
            result.usbInputVoltageVolts = voltage[0]
            result.usbInputCurrentAmps = current[0]
            result.fieldSources["USB voltage"] = "IOHID.\(usbVoltage) (V)"
            result.fieldSources["USB current"] = "IOHID.\(usbCurrent) (A)"
            result.fieldSources["USB input power"] = "IOHID USB voltage × USB current; not battery intake"
        }

        let temperatures = values(
            batteryTemperature, page: 0xFF00, usage: 5, range: -20 ... 90, in: telemetry
        ).sorted()
        // Some phones expose several identically named gas-gauge services.
        // Use their median only when they agree; never select an arbitrary one.
        if timely, let first = temperatures.first, let last = temperatures.last, last - first <= 1 {
            let middle = temperatures.count / 2
            result.temperatureCelsius = temperatures.count.isMultiple(of: 2)
                ? (temperatures[middle - 1] + temperatures[middle]) / 2 : temperatures[middle]
            result.fieldSources["Temperature"] = "IOHID.gas gauge battery (°C; median of agreeing sensors)"
        }

        for name in [usbVoltage, usbCurrent, batteryTemperature] {
            let matches = telemetry.sensors.filter { $0["name"] as? String == name }
            diagnostics[name] = matches.isEmpty ? "not found" : matches.map {
                number($0["value"]).map { String($0) } ?? "no finite value"
            }.joined(separator: ", ")
        }
        diagnostics["USB pair"] = result.hasElectricalTelemetry ? "validated" : "unavailable / rejected"
        diagnostics["Battery temperature"] = result.temperatureCelsius == nil ? "unavailable / rejected" : "validated"
        result.readerDiagnostics = diagnostics
        result.source = result.hasDetailedTelemetry ? .hidSensors : .publicAPI
        if result.hasElectricalTelemetry {
            result.diagnostic = """
            USB input is estimated from live IOHID voltage and current sensors. \
            It includes the phone's own power use, not just battery charging.
            """
        } else if result.state == .unplugged {
            result.diagnostic = "Connect a wired charger to measure USB input. Battery temperature is read independently."
        } else if result.isWireless == true {
            result.diagnostic = """
            Wireless power is connected. These USB sensors cannot measure wireless input; \
            battery temperature remains independent.
            """
        } else {
            result.diagnostic = """
            A usable USB voltage/current pair and a confirmed wired adapter were not returned in this poll. \
            No adapter rating or battery percentage is substituted for measured watts.
            """
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite
        else { return nil }
        return number.doubleValue
    }

    private static func values(
        _ name: String, page: Int, usage: Int, range: ClosedRange<Double>, in telemetry: HIDTelemetry
    ) -> [Double] {
        let matches = telemetry.sensors.filter { $0["name"] as? String == name }
        // Invalid duplicates still make a USB mapping ambiguous.
        if name != batteryTemperature, matches.count != 1 { return [] }
        return matches.compactMap {
            guard number($0["PrimaryUsagePage"]) == Double(page),
                  number($0["PrimaryUsage"]) == Double(usage),
                  let value = number($0["value"]), range.contains(value)
            else { return nil }
            return value
        }
    }
}
