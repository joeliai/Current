import Foundation

enum ChargeState: String, Codable {
    case unknown
    case unplugged
    case charging
    case pluggedIn
    case full

    var isConnected: Bool {
        self == .charging || self == .pluggedIn || self == .full
    }

    var title: String {
        switch self {
        case .unknown: "Waiting for battery"
        case .unplugged: "On battery"
        case .charging: "Charging"
        case .pluggedIn: "Connected to power"
        case .full: "Fully charged"
        }
    }
}

enum TelemetrySource: String, Codable {
    case publicAPI
    // Retained for decoding exports from the old registry reader.
    case privateAPI
    case hidSensors

    var title: String {
        switch self {
        case .publicAPI: "iOS battery API"
        case .privateAPI: "IOKit registry"
        case .hidSensors: "IOHID sensors"
        }
    }
}

enum PowerMeasurement: String, Codable {
    case usbInput
    case batteryIntake

    var title: String {
        switch self {
        case .usbInput: "USB input"
        case .batteryIntake: "Battery intake"
        }
    }

    var definition: String {
        switch self {
        case .usbInput:
            "USB-input sensor volts × amps. Includes power used by the phone, not just battery charging. Not wall power."
        case .batteryIntake:
            "Nonnegative net battery intake: battery volts × signed amps. Not wall or USB input power."
        }
    }
}

enum DeviceThermalState: String, Codable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Elevated"
        case .serious: "Serious"
        case .critical: "Critical"
        case .unknown: "Unavailable"
        }
    }
}

struct BatterySnapshot: Codable, Equatable {
    var timestamp: Date
    var level: Double?
    var state: ChargeState
    var source: TelemetrySource
    // Missing in old exports, whose measurements were battery-side.
    var powerMeasurement: PowerMeasurement?
    var usbInputVoltageVolts: Double?
    var usbInputCurrentAmps: Double?
    // Legacy battery-side fields must never be filled with USB sensor values.
    var voltageVolts: Double?
    var currentAmps: Double?
    var temperatureCelsius: Double?
    var adapterRatedWatts: Double?
    var adapterName: String?
    var isWireless: Bool?
    var isLowPowerMode: Bool
    var thermalState: DeviceThermalState
    var diagnostic: String
    var fieldSources: [String: String]
    var readerDiagnostics: [String: String]?

    static let unavailable = BatterySnapshot(
        timestamp: .now,
        level: nil,
        state: .unknown,
        source: .publicAPI,
        powerMeasurement: .usbInput,
        isLowPowerMode: false,
        thermalState: .unknown,
        diagnostic: "Waiting for the first reading.",
        fieldSources: [:]
    )

    var measurement: PowerMeasurement {
        powerMeasurement ?? .batteryIntake
    }

    var usbInputPowerWatts: Double? {
        guard state.isConnected, isWireless == false,
              let usbInputVoltageVolts, let usbInputCurrentAmps,
              usbInputVoltageVolts.isFinite, usbInputCurrentAmps.isFinite,
              usbInputVoltageVolts > 0, usbInputCurrentAmps >= 0
        else { return nil }
        let power = usbInputVoltageVolts * usbInputCurrentAmps
        return power.isFinite ? power : nil
    }

    var netBatteryPowerWatts: Double? {
        guard let voltageVolts, let currentAmps else { return nil }
        let power = voltageVolts * currentAmps
        return power.isFinite ? power : nil
    }

    /// The basis is explicit so USB readings cannot be mixed with legacy
    /// battery-intake statistics. Missing measurements are never rated watts.
    var chargingPowerWatts: Double? {
        switch measurement {
        case .usbInput:
            return usbInputPowerWatts
        case .batteryIntake:
            guard state.isConnected, let power = netBatteryPowerWatts else { return nil }
            return max(0, power)
        }
    }

    var hasElectricalTelemetry: Bool {
        switch measurement {
        case .usbInput: usbInputPowerWatts != nil
        case .batteryIntake: netBatteryPowerWatts != nil
        }
    }

    var hasReceivedReading: Bool {
        !fieldSources.isEmpty
    }

    var hasDetailedTelemetry: Bool {
        usbInputVoltageVolts != nil || usbInputCurrentAmps != nil ||
            voltageVolts != nil || currentAmps != nil || temperatureCelsius != nil ||
            adapterRatedWatts != nil
    }
}
