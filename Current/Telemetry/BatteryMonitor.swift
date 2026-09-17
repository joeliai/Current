import UIKit

@MainActor
final class BatteryMonitor {
    static let shared = BatteryMonitor()
    static let didUpdate = Notification.Name("Current.BatteryMonitor.didUpdate")
    static let sampleInterval: TimeInterval = 2

    private(set) var snapshot = BatterySnapshot.unavailable
    private(set) var recorder = SessionRecorder()
    private(set) var isMonitoring = false
    private(set) var storageError: String?
    private let defaults = UserDefaults.standard
    private let store = SessionStore()
    private let worker = DispatchQueue(label: "Current.battery-reader", qos: .utility)
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var isReading = false
    private var lastSavedAt = Date.distantPast
    private var persistenceAllowed = true

    var privateTelemetryEnabled: Bool {
        get { defaults.object(forKey: "privateTelemetryEnabled") as? Bool ?? true }
        set {
            guard newValue != privateTelemetryEnabled else { return }
            defaults.set(newValue, forKey: "privateTelemetryEnabled")
            resetSource()
        }
    }

    var keepScreenAwake: Bool {
        get { defaults.bool(forKey: "keepScreenAwake") }
        set {
            defaults.set(newValue, forKey: "keepScreenAwake")
            updateIdleTimer()
            publish()
        }
    }

    var visibleHistory: [ChargingSession] {
        recorder.history
    }

    private init() {
        defaults.removeObject(forKey: "demoEnabled")
        do {
            if let archive = try store.load() {
                recorder.restore(history: archive.sessions, interrupted: archive.activeSession)
            }
        } catch {
            storageError = "Saved sessions could not be read: \(error.localizedDescription)"
            // Preserve an unreadable archive rather than silently replacing it.
            persistenceAllowed = false
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
            ProcessInfo.thermalStateDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
        ] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.25
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refresh()
    }

    func pause() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        generation += 1
        isReading = false
        recorder.finish(reason: .monitoringPaused)
        persist(synchronously: true)
        updateIdleTimer()
        publish()
    }

    func refresh() {
        guard isMonitoring else { return }
        guard !isReading else {
            // A stalled private call must not leave old watts labeled as live.
            if snapshot.hasElectricalTelemetry,
               Date.now.timeIntervalSince(snapshot.timestamp) > ChargingStatistics.maximumSampleGap
            {
                var waiting = publicSnapshot()
                waiting.diagnostic = "The sensor reader is taking too long. Previous power readings have expired."
                accept(waiting)
            }
            return
        }
        let baseline = publicSnapshot()
        guard privateTelemetryEnabled else {
            var reading = baseline
            reading.diagnostic = "Private telemetry is turned off. iOS reports battery level, charging state and system thermal state only."
            accept(reading)
            return
        }

        isReading = true
        let currentGeneration = generation
        worker.async { [weak self] in
            let result: Result<HIDTelemetry, Error> = Result {
                let reading = try BatterySensorReader.reading()
                return HIDTelemetry(
                    sensors: reading.sensors,
                    adapter: reading.adapterDetails,
                    diagnostics: reading.diagnostics,
                    duration: reading.duration
                )
            }
            DispatchQueue.main.async {
                guard let self, self.generation == currentGeneration, self.isMonitoring else { return }
                self.isReading = false
                // Connection notifications can arrive while IOHID is reading.
                // Use the latest public state, not the pre-read snapshot.
                var reading = self.publicSnapshot()
                switch result {
                case let .success(telemetry):
                    reading = HIDTelemetryParser.parse(telemetry, into: reading)
                case let .failure(error):
                    reading.diagnostic = error.localizedDescription
                    reading.readerDiagnostics?["IOHID read"] = error.localizedDescription
                }
                self.accept(reading)
            }
        }
    }

    func clearHistory() {
        recorder.clearHistory()
        persist()
        publish()
    }

    func deleteSession(id: UUID) {
        recorder.delete(id: id)
        persist()
        publish()
    }

    func session(id: UUID) -> ChargingSession? {
        if recorder.active?.id == id { return recorder.active }
        return recorder.history.first { $0.id == id }
    }

    func export(session: ChargingSession? = nil) throws -> URL {
        struct Export: Encodable {
            let formatVersion: Int
            let exportedAt: Date
            let isDemo: Bool
            let measurement: String
            let samplingIntervalSeconds: Double
            let note: String
            let snapshot: BatterySnapshot?
            let sessions: [ChargingSession]
        }
        let payload = Export(
            formatVersion: 2,
            exportedAt: .now,
            isDemo: false,
            measurement: session?.measurement.definition ?? """
            Each session declares its powerMeasurement. New sessions measure USB input, not net battery intake. \
            Sessions without powerMeasurement are legacy battery-intake observations. Not wall power.
            """,
            samplingIntervalSeconds: Self.sampleInterval,
            note: """
            Foreground observations only. Averages are time-weighted over valid sample intervals. \
            Gaps over 10 seconds are excluded. USB sensor mappings are reverse-engineered and model-dependent. \
            Rated adapter watts are not measured power.
            """,
            snapshot: session == nil ? snapshot : nil,
            sessions: session.map { [$0] } ?? ([recorder.active].compactMap { $0 } + visibleHistory)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            session == nil ? "Current-readings.json" : "Current-session.json"
        )
        try encoder.encode(payload).write(to: url, options: .atomic)
        return url
    }

    private func publicSnapshot() -> BatterySnapshot {
        let device = UIDevice.current
        var value = BatterySnapshot.unavailable
        value.timestamp = .now
        value.level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        switch device.batteryState {
        case .unknown: value.state = .unknown
        case .unplugged: value.state = .unplugged
        case .charging: value.state = .charging
        case .full: value.state = .full
        @unknown default: value.state = .unknown
        }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: value.thermalState = .nominal
        case .fair: value.thermalState = .fair
        case .serious: value.thermalState = .serious
        case .critical: value.thermalState = .critical
        @unknown default: value.thermalState = .unknown
        }
        value.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        value.fieldSources = [
            "Battery level": "UIDevice.batteryLevel",
            "Connection": "UIDevice.batteryState",
            "System thermal state": "ProcessInfo.thermalState",
        ]
        value.readerDiagnostics = [
            "iOS version": device.systemVersion,
            "iOS battery state": value.state.rawValue,
            "Private telemetry": privateTelemetryEnabled ? "enabled" : "disabled",
        ]
        return value
    }

    private func accept(_ value: BatterySnapshot) {
        snapshot = value
        let previousSession = recorder.active?.id
        recorder.record(value)
        if Date.now.timeIntervalSince(lastSavedAt) >= 30 || previousSession != recorder.active?.id {
            persist()
        }
        updateIdleTimer()
        publish()
    }

    private func resetSource() {
        generation += 1
        isReading = false
        recorder.finish(reason: .sourceChanged)
        snapshot = .unavailable
        persist()
        refresh()
        publish()
    }

    private func persist(synchronously: Bool = false) {
        guard persistenceAllowed else { return }
        lastSavedAt = .now
        let archive = SessionArchive(
            sessions: recorder.history.filter { !$0.isDemo },
            activeSession: recorder.active?.isDemo == false ? recorder.active : nil
        )
        store.save(archive, synchronously: synchronously) { [weak self] message in
            self?.storageError = message.map { "Sessions could not be saved: \($0)" }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && isMonitoring && snapshot.state.isConnected
    }

    private func publish() {
        NotificationCenter.default.post(name: Self.didUpdate, object: self)
    }
}
