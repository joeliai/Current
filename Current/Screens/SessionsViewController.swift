import UIKit

final class SessionsViewController: MonitorViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private var sessions: [ChargingSession] = []
    private let emptyLabel = makeLabel("No recorded charging sessions", size: 17, color: Palette.secondary)
    private let summary = makeLabel(size: 12, color: Palette.secondary, style: .caption1)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Sessions"
        table.backgroundColor = .clear
        table.separatorColor = Palette.separator
        table.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 104
        table.register(SessionCell.self, forCellReuseIdentifier: "session")
        table.accessibilityIdentifier = "sessionsList"
        table.cellLayoutMarginsFollowReadableWidth = true
        view.addSubview(table)
        table.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        emptyLabel.textAlignment = .center
        emptyLabel.accessibilityIdentifier = "emptySessions"
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 46))
        header.addSubview(summary)
        summary.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            summary.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            summary.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        table.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = table.tableHeaderView, table.bounds.width > 0 else { return }
        let size = summary.sizeThatFits(CGSize(
            width: table.bounds.width - 40, height: .greatestFiniteMagnitude
        ))
        let height = max(46, ceil(size.height) + 28)
        if abs(header.frame.height - height) > 0.5 {
            header.frame.size = CGSize(width: table.bounds.width, height: height)
            table.tableHeaderView = header
        }
    }

    override func render() {
        guard !table.isDragging, !table.isDecelerating else { return }
        sessions = [monitor.recorder.active].compactMap { $0 } + monitor.visibleHistory
        summary.text = "FOREGROUND OBSERVATIONS"
        table.backgroundView = sessions.isEmpty ? emptyLabel : nil
        table.reloadData()
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        sessions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "session", for: indexPath) as? SessionCell
            ?? SessionCell(style: .default, reuseIdentifier: "session")
        let session = sessions[indexPath.row]
        cell.configure(session)
        cell.accessibilityIdentifier = session.endedAt == nil ? "activeSession" : "savedSession.\(indexPath.row)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            SessionDetailViewController(session: sessions[indexPath.row]),
            animated: true
        )
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let session = sessions[indexPath.row]
        guard session.endedAt != nil else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.monitor.deleteSession(id: session.id)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        render()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { render() }
    }
}

private final class SessionCell: UITableViewCell {
    private let sessionTitle = makeLabel(size: 16, weight: .semibold)
    private let subtitle = makeLabel(size: 12, color: Palette.secondary, style: .caption1)
    private let power = makeLabel(size: 21, weight: .medium, style: .title3)
    private let powerLabel = makeLabel("average", size: 11, color: Palette.secondary, style: .caption2)
    private let symbol = UIImageView(image: UIImage(systemName: "bolt.fill"))
    private let row: UIStackView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let labels = makeStack([sessionTitle, subtitle], spacing: 7)
        let trailing = makeStack([power, powerLabel], spacing: 4)
        row = makeStack([symbol, labels, trailing], axis: .horizontal, spacing: 16, alignment: .center)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        accessoryType = .disclosureIndicator
        symbol.tintColor = Palette.accent
        symbol.contentMode = .scaleAspectFit
        symbol.widthAnchor.constraint(equalToConstant: 22).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 28).isActive = true
        power.textAlignment = .right
        powerLabel.textAlignment = .right
        power.font = Palette.font(21, weight: .medium, style: .title3, monospaced: true)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
        ])
        updateAxis()
        registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self]
        ) { (view: SessionCell, _: UITraitCollection) in
            view.updateAxis()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ session: ChargingSession) {
        let active = session.endedAt == nil
        sessionTitle.text = active ? "Recording now" : session.startedAt
            .formatted(.dateTime.month(.abbreviated).day().hour().minute())
        let from = ReadingFormat.percent(session.samples.first?.level)
        let to = ReadingFormat.percent(session.samples.last?.level)
        subtitle.text = "\(ReadingFormat.duration(session.duration))  \u{00B7}  \(from) to \(to)"
        power.text = session.statistics.averageWatts.map { "\(ReadingFormat.number($0)) W" } ?? "-- W"
        powerLabel.text = "\(session.measurement.title.lowercased()) avg"
        symbol.tintColor = active ? Palette.accent : Palette.secondary
        power.textColor = active ? Palette.accent : Palette.ink
        accessibilityLabel = [
            sessionTitle.text,
            subtitle.text,
            power.text.map { "\($0) average \(session.measurement.title.lowercased())" },
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private func updateAxis() {
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        row.axis = accessible ? .vertical : .horizontal
        row.alignment = accessible ? .leading : .center
    }
}

final class SessionDetailViewController: ScrollingMonitorViewController {
    private var session: ChargingSession
    private let heading = makeLabel(size: 14, color: Palette.secondary)
    private let mode = GlassBadge(text: "SESSION", symbol: "bolt.fill")
    private let averageValue = makeLabel(size: 49, weight: .light, style: .largeTitle)
    private let chart = PowerChartView()
    private let readout = makeLabel(size: 12, color: Palette.secondary, style: .caption1)
    private let measurement = DataRow("Measurement")
    private let measurementNote = makeLabel(size: 12, color: Palette.secondary, style: .footnote)
    private let peak = MetricTile(
        title: "Peak",
        symbol: "arrow.up.right",
        color: Palette.coral,
        subtitle: "sampled peak"
    )
    private let recent = MetricTile(title: "Last 5 min", symbol: "clock", color: Palette.blue, subtitle: "average")
    private let duration = DataRow("Observed time")
    private let energy = DataRow("Observed energy")
    private let gain = DataRow("Battery gained")
    private let coverage = DataRow("Power coverage")
    private let count = DataRow("Samples")
    private let ended = DataRow("Status")
    private let period = DataRow("Battery level")

    init(session: ChargingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Session"
        let export = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
            target: self, action: #selector(exportSession(_:))
        )
        export.accessibilityLabel = "Export session"
        export.accessibilityIdentifier = "exportSessionButton"
        navigationItem.rightBarButtonItem = export
        content.addArrangedSubview(makeStack([mode, UIView()], axis: .horizontal, alignment: .center))
        content.addArrangedSubview(heading)
        averageValue.numberOfLines = 1
        averageValue.minimumScaleFactor = 0.5
        averageValue.adjustsFontSizeToFitWidth = true
        averageValue.accessibilityIdentifier = "sessionAverage"
        content.addArrangedSubview(makeStack([
            averageValue,
            makeLabel("Time-weighted average", size: 14, color: Palette.secondary),
        ], spacing: 3))
        chart.heightAnchor.constraint(equalToConstant: 200).isActive = true
        readout.text = "\(session.measurement.title) power"
        chart.onScrub = { [weak self] sample in
            guard let self else { return }
            readout.text = sample.map {
                "\(ReadingFormat.measurement($0.powerWatts, unit: "W")) at \(ReadingFormat.time($0.timestamp))"
            } ?? "\(session.measurement.title) power"
        }
        content.addArrangedSubview(makeStack([readout, chart], spacing: 12))
        content.addArrangedSubview(AdaptiveMetricStrip([peak, recent]))
        content.addArrangedSubview(makeRows([measurement, duration, energy, gain, period, coverage, count, ended]))
        content.addArrangedSubview(measurementNote)
        content.addArrangedSubview(makeLabel(
            """
            Only observed intervals contribute to averages and energy. Unmeasured gaps are excluded; \
            the sampled peak may be lower than the physical peak.
            """,
            size: 12, color: Palette.secondary, style: .footnote
        ))
    }

    override func render() {
        session = monitor.session(id: session.id) ?? session
        let statistics = session.statistics
        heading.text = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        mode.set(
            text: session.endedAt == nil ? "RECORDING" : "OBSERVED SESSION",
            symbol: session.endedAt == nil ? "circle.fill" : "checkmark",
            color: Palette.accent
        )
        averageValue.text = statistics.averageWatts.map { "\(ReadingFormat.number($0)) W" } ?? "-- W"
        measurement.set(session.measurement.title)
        measurementNote.text = session.measurement.definition
        chart.set(session: session, window: .session)
        peak.set(statistics.peakWatts)
        recent.set(session.recentStatistics.averageWatts)
        duration.set(ReadingFormat.duration(session.duration))
        energy.set(ReadingFormat.measurement(statistics.energyWh, unit: "Wh", digits: 3))
        gain.set(ReadingFormat.gain(statistics.levelGain))
        period
            .set(
                "\(ReadingFormat.percent(session.samples.first?.level)) to \(ReadingFormat.percent(session.samples.last?.level))"
            )
        coverage.set("\(ReadingFormat.number(statistics.coverage * 100, digits: 0))% of observed time")
        count.set(statistics.sampleCount.formatted())
        ended.set(session.endReason?.title ?? "Recording")
    }

    @objc private func exportSession(_ sender: UIBarButtonItem) {
        share(session: session, from: sender)
    }
}
