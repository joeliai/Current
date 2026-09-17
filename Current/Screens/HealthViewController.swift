import UIKit

final class HealthViewController: ScrollingMonitorViewController {
    private let mode = GlassBadge(text: "LIVE SENSORS", symbol: "waveform.path")
    private let temperature = makeLabel("-- °C", size: 68, weight: .light, style: .largeTitle)
    private let temperatureDetail = makeLabel(size: 13, color: Palette.secondary, style: .footnote)
    private let voltage = DataRow("USB input voltage", symbol: "bolt")
    private let current = DataRow("USB input current", symbol: "waveform.path")
    private let inputPower = DataRow("USB input power", symbol: "bolt.circle")
    private let adapter = DataRow("Adapter rating", symbol: "powerplug")
    private let lowPower = DataRow("Low Power Mode", symbol: "leaf")
    private let thermal = DataRow("System thermal state", symbol: "thermometer.medium")
    private let source = DataRow("Data source", symbol: "cpu")
    private let status = makeLabel(size: 13, color: Palette.secondary, style: .footnote)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Battery health"
        content.addArrangedSubview(makeStack([mode, UIView()], axis: .horizontal, alignment: .center))
        temperature.font = Palette.font(68, weight: .light, style: .largeTitle, maximumSize: 96, monospaced: true)
        temperature.textAlignment = .center
        temperature.numberOfLines = 1
        temperature.adjustsFontSizeToFitWidth = true
        temperature.minimumScaleFactor = 0.6
        temperature.accessibilityIdentifier = "batteryTemperature"
        temperature.accessibilityLabel = "Battery temperature"
        let caption = makeLabel("Battery temperature", size: 15, color: Palette.secondary)
        caption.textAlignment = .center
        temperatureDetail.textAlignment = .center
        content.addArrangedSubview(makeStack([temperature, caption, temperatureDetail], spacing: 8))
        content.addArrangedSubview(makeStack([
            makeSectionHeading("USB input"),
            makeRows([voltage, current, inputPower, adapter]),
            makeLabel(
                """
                USB input includes power used by the phone, not just the battery. \
                Adapter rating is a reported limit, not measured charging power.
                """,
                size: 12, color: Palette.secondary, style: .footnote
            ),
        ], spacing: 6))
        content.addArrangedSubview(makeStack([
            makeSectionHeading("System"), makeRows([lowPower, thermal, source]),
        ], spacing: 6))
        content.addArrangedSubview(status)
        var configuration = UIButton.Configuration.glass()
        configuration.title = "Source diagnostics"
        configuration.image = UIImage(systemName: "list.bullet.rectangle")
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18)
        let diagnostics = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(DiagnosticsViewController(), animated: true)
        })
        diagnostics.accessibilityIdentifier = "diagnosticsButton"
        content.addArrangedSubview(diagnostics)
    }

    override func render() {
        let snapshot = monitor.snapshot
        let hasSensors = snapshot.temperatureCelsius != nil || snapshot.hasElectricalTelemetry
        mode.set(
            text: hasSensors ? "LIVE SENSORS" : "SYSTEM STATUS",
            symbol: hasSensors ? "waveform.path" : "iphone",
            color: hasSensors ? Palette.accent : Palette.secondary
        )
        temperature.text = "\(ReadingFormat.number(snapshot.temperatureCelsius)) °C"
        temperature.accessibilityValue = ReadingFormat.measurement(snapshot.temperatureCelsius, unit: "degrees Celsius")
        temperatureDetail.text = snapshot.temperatureCelsius == nil
            ? "Battery temperature is unavailable."
            : "Read directly from the battery's temperature sensors."
        voltage.set(ReadingFormat.measurement(snapshot.usbInputVoltageVolts, unit: "V", digits: 3))
        current.set(ReadingFormat.measurement(snapshot.usbInputCurrentAmps, unit: "A", digits: 3))
        inputPower.set(ReadingFormat.measurement(snapshot.usbInputPowerWatts, unit: "W", digits: 2))
        adapter.set(ReadingFormat.measurement(snapshot.adapterRatedWatts, unit: "W rated", digits: 0))
        lowPower.set(snapshot.isLowPowerMode ? "On" : "Off")
        thermal.set(
            snapshot.thermalState.title,
            color: snapshot.thermalState == .nominal ? Palette.accent : Palette.amber
        )
        source.set(snapshot.source.title)
        status.text = snapshot.diagnostic
    }
}
