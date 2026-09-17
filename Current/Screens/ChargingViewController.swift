import UIKit

final class ChargingViewController: ScrollingMonitorViewController {
    private let mode = GlassBadge(text: "LIVE", symbol: "circle.fill")
    private let accessNotice = TelemetryNoticeView(identifier: "chargingAccessNotice")
    private let gauge = ChargeGaugeView()
    private let powerValue = makeLabel("--", size: 35, weight: .medium, style: .largeTitle)
    private let powerCaption = makeLabel(
        "USB INPUT",
        size: 10,
        weight: .medium,
        color: Palette.secondary,
        style: .caption2
    )
    private let adapterTitle = makeLabel(size: 13, weight: .medium)
    private let adapterDetail = makeLabel(size: 11, color: Palette.secondary, style: .caption1)
    private let peak = MetricTile(
        title: "Peak",
        symbol: "arrow.up.right",
        color: Palette.coral,
        subtitle: "sampled peak"
    )
    private let average = MetricTile(
        title: "Average",
        symbol: "waveform.path",
        color: Palette.accent,
        subtitle: "this session"
    )
    private let recent = MetricTile(title: "Last 5 min", symbol: "clock", color: Palette.blue, subtitle: "average")
    private let chart = PowerChartView()
    private let windowControl = UISegmentedControl(items: ["5 min", "Session"])
    private let chartReadout = makeLabel(size: 12, color: Palette.secondary, style: .caption1)
    private let observed = DataRow("Observed time", symbol: "clock")
    private let energy = DataRow("USB energy in", symbol: "bolt")
    private let gain = DataRow("Battery gained", symbol: "battery.100percent")
    private let coverage = DataRow("Power coverage", symbol: "waveform.path")
    private let availability = makeLabel(size: 13, color: Palette.secondary, style: .footnote)
    private let refreshControl = UIRefreshControl()
    private var hasReading = false
    private var selectedSample: ChargingSample?
    private var sessionStatistics: ChargingStatistics?
    private var fiveMinuteStatistics: ChargingStatistics?

    override func viewDidLoad() {
        super.viewDidLoad()
        let wordmark = makeLabel("Current", size: 23, weight: .semibold, style: .title2)
        wordmark.accessibilityTraits = .header
        navigationItem.titleView = wordmark
        let share = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
            target: self, action: #selector(exportReadings(_:))
        )
        share.accessibilityLabel = "Export readings"
        share.accessibilityIdentifier = "exportButton"
        navigationItem.leftBarButtonItem = share
        let eyebrow = makeLabel(
            UIDevice.current.userInterfaceIdiom == .pad ? "THIS IPAD" : "THIS IPHONE",
            size: 11, weight: .medium, color: Palette.secondary, style: .caption1
        )
        #if targetEnvironment(simulator)
            eyebrow.text = "SIMULATOR"
        #endif
        let top = makeStack([eyebrow, UIView(), mode], axis: .horizontal, spacing: 12, alignment: .center)
        content.addArrangedSubview(top)
        content.setCustomSpacing(4, after: top)
        accessNotice.onDetails = { [weak self] in
            self?.navigationController?.pushViewController(DiagnosticsViewController(), animated: true)
        }
        content.addArrangedSubview(accessNotice)
        gauge.heightAnchor.constraint(greaterThanOrEqualToConstant: 274).isActive = true

        let symbolContainer = UIView()
        symbolContainer.backgroundColor = Palette.mint.withAlphaComponent(0.11)
        symbolContainer.layer.cornerRadius = 8
        let symbol = UIImageView(image: UIImage(systemName: "bolt.fill"))
        symbol.tintColor = Palette.accent
        symbol.contentMode = .scaleAspectFit
        symbolContainer.addSubview(symbol)
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false
        symbol.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 44),
            symbolContainer.heightAnchor.constraint(equalToConstant: 48),
            symbol.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 17),
            symbol.heightAnchor.constraint(equalToConstant: 24),
        ])
        powerValue.font = Palette.font(35, weight: .medium, style: .largeTitle, monospaced: true)
        powerValue.numberOfLines = 1
        powerValue.minimumScaleFactor = 0.6
        powerValue.adjustsFontSizeToFitWidth = true
        powerValue.accessibilityIdentifier = "currentPower"
        let powerLabels = makeStack([powerCaption, powerValue], spacing: 3)
        let powerGroup = makeStack([symbolContainer, powerLabels], axis: .horizontal, spacing: 12, alignment: .center)
        adapterTitle.textAlignment = .right
        adapterDetail.textAlignment = .right
        let adapter = makeStack([adapterTitle, adapterDetail], spacing: 5)
        adapter.setContentHuggingPriority(.required, for: .horizontal)
        let live = makeStack([powerGroup, adapter], axis: .horizontal, spacing: 12, alignment: .center)
        let hero = makeStack([gauge, live], spacing: 20)
        content.addArrangedSubview(hero)
        content.addArrangedSubview(AdaptiveMetricStrip([peak, average, recent]))

        windowControl.selectedSegmentIndex = 0
        windowControl.accessibilityIdentifier = "chartWindow"
        windowControl.addTarget(self, action: #selector(windowChanged), for: .valueChanged)
        windowControl.widthAnchor.constraint(equalToConstant: 146).isActive = true
        let chartHeading = makeSectionHeading("Charging curve", accessory: windowControl)
        chart.heightAnchor.constraint(equalToConstant: 176).isActive = true
        chartReadout.accessibilityIdentifier = "chartReadout"
        chart.onScrub = { [weak self] sample in
            self?.selectedSample = sample
            self?.updateChartReadout()
        }
        let chartSection = makeStack([chartHeading, chartReadout, chart], spacing: 14)
        content.addArrangedSubview(chartSection)
        let sessionHeading = makeSectionHeading("This session")
        content.addArrangedSubview(makeStack([
            sessionHeading, makeRows([observed, energy, gain, coverage]),
        ], spacing: 5))
        availability.accessibilityIdentifier = "telemetryAvailability"
        content.addArrangedSubview(availability)

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        scrollView.refreshControl = refreshControl
        mode.accessibilityIdentifier = "dataMode"

        registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self]
        ) { (controller: ChargingViewController, _: UITraitCollection) in
            let accessible = controller.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            live.axis = accessible ? .vertical : .horizontal
            live.alignment = accessible ? .fill : .center
            chartHeading.axis = accessible ? .vertical : .horizontal
            chartHeading.alignment = accessible ? .leading : .center
        }
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            live.axis = .vertical
            live.alignment = .fill
            chartHeading.axis = .vertical
            chartHeading.alignment = .leading
        }
    }

    override func render() {
        let value = monitor.snapshot
        let limited = value.hasReceivedReading &&
            value.state != .unplugged && !value.hasElectricalTelemetry
        mode.set(
            text: limited ? "LIMITED DATA" : "LIVE",
            symbol: limited ? "lock" : "circle.fill",
            color: limited ? Palette.amber : Palette.accent
        )
        accessNotice.isHidden = !limited
        accessNotice.update(title: "USB input unavailable", message: value.diagnostic)
        gauge.update(value, animated: hasReading || view.window != nil)
        hasReading = value.level != nil
        let powerText = value.chargingPowerWatts.map { "\(ReadingFormat.number($0)) W" } ?? "-- W"
        if powerValue.text != powerText, view.window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(
                with: powerValue, duration: 0.25,
                options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.powerValue.text = powerText
            }
        } else {
            powerValue.text = powerText
        }
        powerValue.accessibilityLabel = "USB input"
        powerValue.accessibilityValue = ReadingFormat.measurement(value.chargingPowerWatts, unit: "watts")
        if value.state.isConnected {
            adapterTitle.text = value.isWireless == true ? "Wireless" : value.isWireless == false ? "Wired power" : "Connected"
            adapterDetail.text = value.adapterRatedWatts.map { "\(ReadingFormat.number($0, digits: 0)) W rated" } ?? "Rating unavailable"
        } else {
            adapterTitle.text = value.state == .unknown ? "Waiting" : "Not connected"
            adapterDetail.text = "No power source"
        }

        let session = monitor.recorder.active
        let statistics = session?.statistics
        sessionStatistics = statistics
        fiveMinuteStatistics = session?.recentStatistics
        peak.set(statistics?.peakWatts)
        average.set(statistics?.averageWatts)
        recent.set(fiveMinuteStatistics?.averageWatts)
        let window = ChartWindow(rawValue: windowControl.selectedSegmentIndex) ?? .recent
        chart.set(session: session, window: window)
        observed.set(session.map { ReadingFormat.duration($0.duration) } ?? "Not recording")
        energy.set(ReadingFormat.measurement(statistics?.energyWh, unit: "Wh", digits: 2))
        gain.set(ReadingFormat.gain(statistics?.levelGain))
        coverage.set(statistics.map {
            "\(ReadingFormat.number($0.coverage * 100, digits: 0))% of observed time"
        } ?? "Unavailable")
        if !value.hasElectricalTelemetry {
            availability.text = value.diagnostic
        } else {
            availability.text = """
            USB input estimated from IOHID sensors; includes phone use, not just battery charging. \
            Foreground observations only.
            """
        }
        if let error = monitor.storageError {
            availability.text = [availability.text, error].compactMap { $0 }.joined(separator: "\n")
        }
        updateChartReadout()
        refreshControl.endRefreshing()
    }

    private func updateChartReadout() {
        if let selectedSample {
            let watts = ReadingFormat.measurement(selectedSample.powerWatts, unit: "W")
            let time = selectedSample.timestamp.formatted(date: .omitted, time: .standard)
            chartReadout.text = "\(watts)  \u{00B7}  \(time)"
            chartReadout.textColor = Palette.accent
        } else {
            let duration = windowControl.selectedSegmentIndex == 0
                ? fiveMinuteStatistics?.coveredSeconds
                : sessionStatistics?.coveredSeconds
            chartReadout.text = duration.map {
                "\((windowControl.selectedSegmentIndex == 0) ? "Last 5 minutes" : "Full session")  \u{00B7}  \(ReadingFormat.duration($0)) measured"
            } ?? "No measured power yet"
            chartReadout.textColor = Palette.secondary
        }
    }

    @objc private func windowChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
        selectedSample = nil
        chart.set(
            session: monitor.recorder.active,
            window: ChartWindow(rawValue: windowControl.selectedSegmentIndex) ?? .recent
        )
        updateChartReadout()
    }

    @objc private func refresh() {
        monitor.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    @objc private func exportReadings(_ item: UIBarButtonItem) {
        share(from: item)
    }
}
