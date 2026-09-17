import UIKit

final class SettingsViewController: UITableViewController {
    private let monitor = BatteryMonitor.shared
    private let appearance = AppearanceSettings.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Settings"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = Palette.background
        tableView.accessibilityIdentifier = "settingsList"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Close settings"
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "closeSettings"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        5
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        [2, 3, 1, 2, 1][section]
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Monitoring", "Appearance", "Data source", "On-device data", "Current"][section]
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            """
            Samples every 2 seconds while foregrounded. Backgrounding or locking ends the observation. \
            Keeping the screen on consumes additional power.
            """
        case 1:
            "Auto follows your device's appearance. Your choice is saved and applies throughout Current."
        case 2:
            """
            Read-only IOHID sensors provide USB input and battery temperature when available. \
            Sensor mappings vary by device and OS. \
            Not intended for App Store distribution.
            """
        case 3:
            "Up to 30 device sessions stay on this device. No analytics or network requests."
        default:
            """
            USB input is sensor voltage \u{00D7} current, including the phone's own power use. \
            Averages use valid observed time. Older sessions remain labeled as battery intake.
            """
        }
    }

    override func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = Palette.surface
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = Palette.font(16)
        cell.textLabel?.textColor = Palette.ink
        cell.selectionStyle = .none
        if indexPath.section == 0 {
            let titles = ["Private telemetry", "Keep screen on"]
            let icons = ["cpu", "sun.max"]
            cell.textLabel?.text = titles[indexPath.row]
            cell.imageView?.image = UIImage(systemName: icons[indexPath.row])
            let toggle = UISwitch()
            toggle.onTintColor = Palette.accent
            toggle.tag = indexPath.row
            toggle.isOn = [monitor.privateTelemetryEnabled, monitor.keepScreenAwake][indexPath.row]
            toggle.accessibilityLabel = titles[indexPath.row]
            toggle.accessibilityIdentifier = ["privateTelemetryToggle", "keepAwakeToggle"][indexPath.row]
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        } else if indexPath.section == 1 {
            let mode = AppearanceMode.allCases[indexPath.row]
            let selected = appearance.mode == mode
            cell.textLabel?.text = mode.title
            cell.imageView?.image = UIImage(systemName: mode.symbol)
            cell.detailTextLabel?.text = mode == .automatic ? "Follow system" : nil
            cell.detailTextLabel?.textColor = Palette.secondary
            cell.accessoryType = selected ? .checkmark : .none
            cell.selectionStyle = .default
            cell.accessibilityIdentifier = "appearance.\(mode.rawValue)"
            cell.accessibilityTraits.insert(.button)
            if selected { cell.accessibilityTraits.insert(.selected) }
        } else if indexPath.section == 2 {
            cell.textLabel?.text = "Source diagnostics"
            cell.imageView?.image = UIImage(systemName: "list.bullet.rectangle")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityIdentifier = "sourceDiagnostics"
        } else if indexPath.section == 3 {
            cell.textLabel?.text = indexPath.row == 0 ? "Export readings" : "Delete saved sessions"
            cell.imageView?.image = UIImage(systemName: indexPath.row == 0 ? "square.and.arrow.up" : "trash")
            cell.textLabel?.textColor = indexPath.row == 0 ? Palette.ink : .systemRed
            cell.selectionStyle = .default
            cell.accessibilityIdentifier = indexPath.row == 0 ? "settingsExport" : "deleteSessions"
        } else {
            cell.textLabel?.text = "Version"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            cell.detailTextLabel?.text = version
        }
        cell.imageView?.tintColor = Palette.accent
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            appearance.select(AppearanceMode.allCases[indexPath.row])
            UISelectionFeedbackGenerator().selectionChanged()
            tableView.reloadData()
        } else if indexPath.section == 2 {
            navigationController?.pushViewController(DiagnosticsViewController(), animated: true)
        } else if indexPath.section == 3, indexPath.row == 1 {
            let alert = UIAlertController(
                title: "Delete saved sessions?",
                message: "The active recording will be kept. This cannot be undone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                self?.monitor.clearHistory()
            })
            present(alert, animated: true)
        } else if indexPath.section == 3, indexPath.row == 0 {
            do {
                let controller = try UIActivityViewController(
                    activityItems: [monitor.export()],
                    applicationActivities: nil
                )
                controller.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
                present(controller, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: "Export unavailable", message: error.localizedDescription, preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        switch sender.tag {
        case 0: monitor.privateTelemetryEnabled = sender.isOn
        case 1: monitor.keepScreenAwake = sender.isOn
        default: break
        }
        UISelectionFeedbackGenerator().selectionChanged()
        tableView.reloadData()
    }
}

final class DiagnosticsViewController: ScrollingMonitorViewController {
    private let badge = GlassBadge(text: "READ ONLY", symbol: "lock")
    private let diagnostic = makeLabel(size: 15)
    private let source = DataRow("Provider")
    private let power = DataRow("Electrical readings")
    private let chargingState = DataRow("Charging status")
    private let chargingSource = DataRow("Status source")
    private let sampling = DataRow("Sampling interval", value: "2 seconds")
    private let timestamp = DataRow("Last reading")
    private let fields = UIStackView()
    private let storage = makeLabel(size: 13, color: Palette.coral, style: .footnote)
    private var sourceSignature = ""
    private let readerDetails = makeLabel(size: 12, color: Palette.secondary, style: .footnote)
    private lazy var readerSection = makeStack([
        makeSectionHeading("Reader diagnostics"), readerDetails,
    ], spacing: 14)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Diagnostics"
        navigationItem.rightBarButtonItem = nil
        content.addArrangedSubview(makeStack([badge, UIView()], axis: .horizontal, alignment: .center))
        diagnostic.accessibilityIdentifier = "diagnosticMessage"
        content.addArrangedSubview(diagnostic)
        content.addArrangedSubview(makeRows([source, power, chargingState, chargingSource, sampling, timestamp]))
        readerDetails.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .monospacedSystemFont(ofSize: 12, weight: .regular)
        )
        readerDetails.lineBreakMode = .byCharWrapping
        readerDetails.accessibilityIdentifier = "sensorReadout"
        content.addArrangedSubview(readerSection)
        fields.axis = .vertical
        fields.spacing = 16
        content.addArrangedSubview(makeStack([makeSectionHeading("Field provenance"), fields], spacing: 20))
        content.addArrangedSubview(storage)
        content.addArrangedSubview(makeLabel(
            """
            Only identified power and battery-temperature sensors are interpreted. \
            Missing or implausible values remain unavailable. Device identifiers and serial numbers are not saved or exported.
            """,
            size: 12, color: Palette.secondary, style: .footnote
        ))
    }

    override func render() {
        let snapshot = monitor.snapshot
        diagnostic.text = snapshot.diagnostic
        source.set(snapshot.source.title)
        power.set(snapshot.hasElectricalTelemetry ? "Available" : "Restricted / missing")
        chargingState.set(snapshot.state.title)
        if snapshot.fieldSources["Connection"]?.hasPrefix("UIDevice.") == true {
            chargingSource.set("iOS (UIDevice)")
        } else {
            chargingSource.set("Unavailable")
        }
        readerDetails.text = snapshot.readerDiagnostics?.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: "\n\n")
            ?? "Waiting for a hardware sensor read."
        timestamp.set(snapshot.timestamp.formatted(date: .omitted, time: .standard))
        storage.text = monitor.storageError
        storage.isHidden = monitor.storageError == nil
        let sorted = snapshot.fieldSources.sorted { $0.key < $1.key }
        let signature = sorted.map { "\($0.key):\($0.value)" }.joined(separator: "|")
        guard signature != sourceSignature else { return }
        sourceSignature = signature
        for arrangedSubview in fields.arrangedSubviews {
            fields.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }
        for (name, path) in sorted {
            let key = makeLabel(name, size: 13, weight: .medium)
            let value = makeLabel(path, size: 12, color: Palette.secondary, style: .footnote)
            value.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
                for: .monospacedSystemFont(ofSize: 12, weight: .regular)
            )
            value.lineBreakMode = .byCharWrapping
            fields.addArrangedSubview(makeStack([key, value], spacing: 5))
        }
    }
}
